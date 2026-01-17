#!/usr/bin/env bash
set -euo pipefail

# 完整的VIR-SLAM数据录制脚本
# 自动处理所有数据转换和同步

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

# 输出配置
HOST_OUTPUT_DIR="/home/jetson/vir_slam_output/bags"
CONTAINER_BAG_DIR="/tmp/virslam_bags"

# 全局变量
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
            
            # 尝试显示bag内容
            echo ""
            echo "🎯 Bag内容预览:"
            timeout 10 in_container "${ROS_SETUP}; rosbag info '${LATEST_BAG}'" 2>/dev/null || echo "无法获取详细信息，但文件已保存"
            
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

echo "🎥 VIR-SLAM完整数据录制系统"
echo "============================="
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

# 3. 创建临时的完整转换和同步节点
echo "🔧 部署完整的数据处理节点..."
in_container "cat > /tmp/complete_virslam_processor.py << 'EOF'
#!/usr/bin/env python3
import rospy
import tf2_ros
from sensor_msgs.msg import Image, Imu, PointCloud2, CameraInfo
from geometry_msgs.msg import PoseStamped, PointStamped
from cv_bridge import CvBridge
import cv2
import numpy as np
import message_filters
from threading import Lock
import math

class VIRSLAMProcessor:
    def __init__(self):
        rospy.init_node('virslam_complete_processor', anonymous=True)
        self.bridge = CvBridge()
        
        # 发布器
        self.pub_image = rospy.Publisher('/synced/image_raw', Image, queue_size=10)
        self.pub_imu = rospy.Publisher('/synced/imu', Imu, queue_size=50)
        self.pub_lidar = rospy.Publisher('/synced/lidar', PointCloud2, queue_size=10)
        self.pub_uwb = rospy.Publisher('/synced/uwb_range', PointStamped, queue_size=10)
        self.pub_camera_info = rospy.Publisher('/synced/camera_info', CameraInfo, queue_size=10)
        
        # 订阅器
        self.image_sub = rospy.Subscriber('/usb_cam/image_raw', Image, self.image_callback)
        self.imu_sub = rospy.Subscriber('/livox/imu', Imu, self.imu_callback) 
        self.lidar_sub = rospy.Subscriber('/livox/lidar', PointCloud2, self.lidar_callback)
        self.uwb_sub = rospy.Subscriber('/uwb/pose', PoseStamped, self.uwb_callback)
        self.camera_info_sub = rospy.Subscriber('/usb_cam/camera_info', CameraInfo, self.camera_info_callback)
        
        # 统计
        self.stats = {'image': 0, 'imu': 0, 'lidar': 0, 'uwb': 0}
        self.timer = rospy.Timer(rospy.Duration(10), self.print_stats)
        
        rospy.loginfo(\"✅ VIR-SLAM完整处理器启动成功\")

    def image_callback(self, msg):
        try:
            # RGB转灰度
            if msg.encoding in ['rgb8', 'bgr8']:
                cv_image = self.bridge.imgmsg_to_cv2(msg, 'bgr8')
                gray_image = cv2.cvtColor(cv_image, cv2.COLOR_BGR2GRAY)
                
                # CLAHE增强
                clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8,8))
                enhanced_image = clahe.apply(gray_image)
                
                # 发布
                out_msg = self.bridge.cv2_to_imgmsg(enhanced_image, 'mono8')
                out_msg.header = msg.header
                out_msg.header.stamp = rospy.Time.now()
                self.pub_image.publish(out_msg)
                self.stats['image'] += 1
            
        except Exception as e:
            rospy.logwarn(f\"图像处理错误: {e}\")

    def imu_callback(self, msg):
        try:
            # 直接转发IMU数据，更新时间戳
            out_msg = msg
            out_msg.header.stamp = rospy.Time.now()
            self.pub_imu.publish(out_msg)
            self.stats['imu'] += 1
        except Exception as e:
            rospy.logwarn(f\"IMU处理错误: {e}\")

    def lidar_callback(self, msg):
        try:
            # 直接转发点云数据，更新时间戳
            out_msg = msg
            out_msg.header.stamp = rospy.Time.now()
            self.pub_lidar.publish(out_msg)
            self.stats['lidar'] += 1
        except Exception as e:
            rospy.logwarn(f\"点云处理错误: {e}\")

    def uwb_callback(self, msg):
        try:
            # 转换PoseStamped到PointStamped (距离)
            pos = msg.pose.position
            distance = math.sqrt(pos.x**2 + pos.y**2 + pos.z**2)
            
            # 创建PointStamped消息
            point_msg = PointStamped()
            point_msg.header.stamp = rospy.Time.now()
            point_msg.header.frame_id = msg.header.frame_id
            point_msg.point.x = distance
            point_msg.point.y = 0.0
            point_msg.point.z = 0.0
            
            self.pub_uwb.publish(point_msg)
            self.stats['uwb'] += 1
            
        except Exception as e:
            rospy.logwarn(f\"UWB处理错误: {e}\")

    def camera_info_callback(self, msg):
        try:
            # 转发相机信息
            out_msg = msg
            out_msg.header.stamp = rospy.Time.now()
            self.pub_camera_info.publish(out_msg)
        except Exception as e:
            rospy.logwarn(f\"相机信息处理错误: {e}\")

    def print_stats(self, event):
        rospy.loginfo(f\"📊 数据统计 - 图像:{self.stats['image']} IMU:{self.stats['imu']} 点云:{self.stats['lidar']} UWB:{self.stats['uwb']}\")

if __name__ == '__main__':
    try:
        processor = VIRSLAMProcessor()
        rospy.spin()
    except rospy.ROSInterruptException:
        pass
EOF"

# 4. 启动完整处理器
echo "🚀 启动完整数据处理器..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup python3 /tmp/complete_virslam_processor.py > /tmp/virslam_processor.log 2>&1 &"
sleep 8

# 5. 检查所有必需的同步话题
echo "🔍 检查同步话题..."
SYNCED_TOPICS=(
    "/synced/image_raw"
    "/synced/imu" 
    "/synced/lidar"
    "/synced/camera_info"
)

for topic in "${SYNCED_TOPICS[@]}"; do
    if in_container "${ROS_SETUP}; timeout 5 rostopic list | grep -qx '$topic'"; then
        echo "  ✅ $topic"
    else
        echo "  ❌ $topic (缺失)"
    fi
done

# 6. 数据质量检查
echo ""
echo "📊 数据质量检查..."

# 图像格式
image_encoding=$(in_container "${ROS_SETUP}; timeout 5 rostopic echo /synced/image_raw --count=1 2>/dev/null | grep 'encoding:' | awk '{print \$2}'" || echo "none")
echo "📷 图像格式: $image_encoding"

# IMU数据
imu_check=$(in_container "${ROS_SETUP}; timeout 3 rostopic hz /synced/imu --window=10 2>/dev/null | grep 'average rate' | head -1" || echo "无数据")
echo "🎯 IMU频率: $imu_check"

# 点云数据  
lidar_check=$(in_container "${ROS_SETUP}; timeout 3 rostopic hz /synced/lidar --window=5 2>/dev/null | grep 'average rate' | head -1" || echo "无数据")
echo "☁️ 点云频率: $lidar_check"

# 7. 开始录制
mkdir -p "${HOST_OUTPUT_DIR}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BAG_NAME="virslam_complete_${TIMESTAMP}.bag"
HOST_BAG_PATH="${HOST_OUTPUT_DIR}/${BAG_NAME}"
CONTAINER_BAG_PATH="${CONTAINER_BAG_DIR}/${BAG_NAME}"

echo ""
echo "📁 录制配置:"
echo "  输出文件: ${HOST_BAG_PATH}"
echo "  录制话题: ${SYNCED_TOPICS[*]}"

# 确保目录存在
in_container "mkdir -p ${CONTAINER_BAG_DIR}"

echo ""
echo "🔴 开始录制... (按 Ctrl+C 停止)"
echo ""

# 录制命令 - 包含UWB（如果可用）
RECORD_TOPICS="${SYNCED_TOPICS[*]}"
if in_container "${ROS_SETUP}; rostopic list | grep -q '/synced/uwb_range'"; then
    RECORD_TOPICS="$RECORD_TOPICS /synced/uwb_range"
    echo "📡 包含UWB数据"
fi

RECORD_CMD="${ROS_SETUP}; rosbag record -O ${CONTAINER_BAG_PATH} $RECORD_TOPICS"

echo ""
echo "🔴 开始录制... (按 Ctrl+C 停止并自动保存)"
echo ""

# 在后台启动录制，这样可以捕获Ctrl+C
in_container "${RECORD_CMD}" &
RECORD_PID=$!

# 等待用户按Ctrl+C或录制进程结束
wait $RECORD_PID

# 如果程序正常结束到这里，也执行复制
cleanup_and_copy
