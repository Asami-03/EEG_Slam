#!/usr/bin/env bash
set -euo pipefail

# VIR-SLAM完整录制脚本 - 包含所有传感器数据 + UWB
# Ctrl+C后自动复制到宿主机

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

# 输出配置
HOST_OUTPUT_DIR="/home/jetson/vir_slam_output/bags"
CONTAINER_BAG_DIR="/tmp/virslam_bags"

# 全局变量存储bag路径
BAG_NAME=""
CONTAINER_BAG_PATH=""
HOST_BAG_PATH=""

# 工具函数
in_container() {
    docker exec "${CONTAINER}" bash -c "$1"
}

# 信号处理函数 - Ctrl+C时自动复制bag文件
cleanup_and_copy() {
    echo ""
    echo "🛑 录制中断，正在处理..."
    
    # 等待rosbag进程完全结束
    sleep 3
    
    # 查找最新的bag文件（包括.active文件）
    LATEST_BAG=$(in_container "find ${CONTAINER_BAG_DIR} -name '*.bag*' -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-" || echo "")
    
    if [ -n "$LATEST_BAG" ]; then
        # 如果是.active文件，重命名为.bag
        if [[ "$LATEST_BAG" == *.active ]]; then
            NEW_BAG="${LATEST_BAG%.active}"
            echo "📝 重命名活跃bag文件..."
            in_container "mv '$LATEST_BAG' '$NEW_BAG'" || true
            LATEST_BAG="$NEW_BAG"
        fi
        
        # 获取文件名
        BAG_FILENAME=$(basename "$LATEST_BAG")
        HOST_FINAL_PATH="${HOST_OUTPUT_DIR}/${BAG_FILENAME}"
        
        echo "📋 复制bag文件到宿主机..."
        mkdir -p "${HOST_OUTPUT_DIR}"
        
        if docker cp "${CONTAINER}:${LATEST_BAG}" "${HOST_FINAL_PATH}"; then
            echo "✅ 录制完成！文件已保存: ${HOST_FINAL_PATH}"
            
            # 显示文件信息
            echo ""
            echo "📊 录制信息:"
            ls -lh "${HOST_FINAL_PATH}" 2>/dev/null || echo "文件信息获取失败"
            
            # 尝试显示bag内容（如果可能）
            echo ""
            echo "🎯 Bag内容预览:"
            timeout 10 docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; rosbag info '${LATEST_BAG}'" 2>/dev/null || echo "无法获取bag信息"
            
        else
            echo "❌ 文件复制失败"
        fi
    else
        echo "❌ 未找到bag文件"
    fi
    
    exit 0
}

# 设置信号处理
trap cleanup_and_copy SIGINT SIGTERM

echo "🎥 VIR-SLAM完整数据录制 (包含UWB)"
echo "=================================="
echo "📝 按 Ctrl+C 停止录制并自动复制文件"
echo ""

# 1. 检查容器状态
if ! docker ps --format "table {{.Names}}" | grep -qx "${CONTAINER}"; then
    echo "❌ 容器 ${CONTAINER} 未运行"
    echo "💡 请先运行: ./start_container.sh"
    exit 1
fi

# 2. 确保ROS环境
echo "🏁 检查ROS环境..."
if ! in_container "${ROS_SETUP}; pgrep roscore >/dev/null 2>&1"; then
    echo "🚀 启动roscore..."
    in_container "${ROS_SETUP}; nohup roscore > /tmp/roscore.log 2>&1 &"
    sleep 5
fi

# 3. 检查所有可用话题
echo ""
echo "🔍 检查可用话题..."
AVAILABLE_TOPICS=""

# 检查基础传感器话题
for topic in "/synced/image_raw" "/synced/imu" "/synced/lidar" "/synced/camera_info"; do
    if in_container "${ROS_SETUP}; timeout 3 rostopic list | grep -qx '$topic'"; then
        echo "  ✅ $topic"
        AVAILABLE_TOPICS="$AVAILABLE_TOPICS $topic"
    else
        echo "  ❌ $topic (缺失)"
    fi
done

# 检查UWB话题
if in_container "${ROS_SETUP}; timeout 3 rostopic list | grep -qx '/synced/uwb_range'"; then
    echo "  ✅ /synced/uwb_range (UWB数据可用)"
    AVAILABLE_TOPICS="$AVAILABLE_TOPICS /synced/uwb_range"
elif in_container "${ROS_SETUP}; timeout 3 rostopic list | grep -qx '/uwb/pose'"; then
    echo "  📡 检测到UWB原始数据，启动转换器..."
    
    # 启动UWB转换为synced格式
    in_container "cat > /tmp/uwb_to_synced.py << 'EOF'
#!/usr/bin/env python3
import rospy
from geometry_msgs.msg import PoseStamped, PointStamped
import math

def uwb_callback(msg):
    # 转换PoseStamped到PointStamped (距离)
    point_msg = PointStamped()
    point_msg.header = msg.header
    point_msg.header.frame_id = 'uwb_frame'
    
    # 计算距离 (从原点到位置的欧几里得距离)
    distance = math.sqrt(
        msg.pose.position.x**2 + 
        msg.pose.position.y**2 + 
        msg.pose.position.z**2
    )
    
    point_msg.point.x = distance
    point_msg.point.y = 0.0
    point_msg.point.z = 0.0
    
    pub.publish(point_msg)
    rospy.loginfo_throttle(5, f'UWB Range: {distance:.2f}m')

if __name__ == '__main__':
    rospy.init_node('uwb_to_synced_converter')
    pub = rospy.Publisher('/synced/uwb_range', PointStamped, queue_size=10)
    sub = rospy.Subscriber('/uwb/pose', PoseStamped, uwb_callback)
    rospy.loginfo('UWB到synced转换器启动')
    rospy.spin()
EOF"
    
    in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup python3 /tmp/uwb_to_synced.py > /tmp/uwb_synced_converter.log 2>&1 &"
    sleep 3
    
    if in_container "${ROS_SETUP}; timeout 3 rostopic list | grep -qx '/synced/uwb_range'"; then
        echo "  ✅ /synced/uwb_range (UWB转换成功)"
        AVAILABLE_TOPICS="$AVAILABLE_TOPICS /synced/uwb_range"
    else
        echo "  ⚠️ UWB转换失败，继续录制其他数据"
    fi
else
    echo "  ⚠️ UWB数据不可用，录制其他传感器数据"
fi

# 4. 准备录制
if [ -z "$AVAILABLE_TOPICS" ]; then
    echo ""
    echo "❌ 没有可用的话题进行录制"
    exit 1
fi

mkdir -p "${HOST_OUTPUT_DIR}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BAG_NAME="virslam_complete_${TIMESTAMP}.bag"
CONTAINER_BAG_PATH="${CONTAINER_BAG_DIR}/${BAG_NAME}"
HOST_BAG_PATH="${HOST_OUTPUT_DIR}/${BAG_NAME}"

# 确保容器内目录存在
in_container "mkdir -p ${CONTAINER_BAG_DIR}"

echo ""
echo "📁 录制配置:"
echo "  输出文件: ${HOST_BAG_PATH}"
echo "  录制话题:$AVAILABLE_TOPICS"
echo ""

# 5. 数据质量检查
echo "🔍 数据质量检查..."
for topic in $AVAILABLE_TOPICS; do
    if timeout 3 docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; rostopic echo '$topic' --count=1 >/dev/null 2>&1"; then
        echo "  ✅ $topic - 数据流正常"
    else
        echo "  ⚠️ $topic - 数据流异常"
    fi
done

echo ""
echo "🔴 开始录制... (按 Ctrl+C 停止并自动保存)"
echo "📊 实时统计将显示在下方..."
echo ""

# 6. 开始录制 (这里会一直运行直到Ctrl+C)
RECORD_CMD="${ROS_SETUP}; rosbag record -O ${CONTAINER_BAG_PATH} ${AVAILABLE_TOPICS}"

# 在后台启动录制，这样可以捕获Ctrl+C
in_container "${RECORD_CMD}" &
RECORD_PID=$!

# 等待用户按Ctrl+C
wait $RECORD_PID

# 如果程序正常结束到这里，也执行复制
cleanup_and_copy
