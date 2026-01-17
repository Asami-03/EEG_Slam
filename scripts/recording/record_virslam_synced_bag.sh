#!/usr/bin/env bash
set -euo pipefail

# VIR-SLAM 专用bag录制脚本
# 录制格式完全匹配、时间戳对齐的数据

CONTAINER="vir_slam_dev" 
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

# 输出配置
HOST_OUTPUT_DIR="/home/jetson/vir_slam_output/bags"
CONTAINER_BAG_DIR="/tmp/virslam_bags"

# VIR-SLAM标准话题 (同步后的格式)
VIRSLAM_TOPICS=(
  "/synced/lidar"        # PointCloud2 - Livox点云
  "/synced/image_raw"    # Image (mono8) - 灰度图像  
  "/synced/imu"          # Imu - 惯性数据
  "/synced/uwb_range"    # PointStamped - UWB距离
  "/synced/camera_info"  # CameraInfo - 相机参数
  "/synced/status"       # String - 同步状态信息
)

# 工具函数
die() { echo "❌ $*" 1>&2; exit 1; }
docker_running() {
  docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"
}
in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}

echo "📹 VIR-SLAM专用数据录制"
echo "======================"

# 1. 环境检查
docker_running || die "容器未运行，请先运行 ./start_container.sh"

# 2. 检查同步系统是否运行
echo "🔍 检查同步系统状态..."
if ! in_container "${ROS_SETUP}; rosnode list | grep -q unified_timestamp_sync"; then
    echo "❌ 时间同步节点未运行"
    echo "💡 请先执行: ./scripts/tools/start.sh"
    exit 1
fi

# 3. 验证所有必需话题
echo "📋 验证VIR-SLAM话题..."
missing_topics=()
for topic in "${VIRSLAM_TOPICS[@]}"; do
  if in_container "${ROS_SETUP}; timeout 3 rostopic list | grep -qx '$topic'"; then
    echo "  ✅ $topic"
  else
    echo "  ❌ $topic (缺失)"
    missing_topics+=("$topic")
  fi
done

if [ ${#missing_topics[@]} -ne 0 ]; then
    echo ""
    echo "❌ 缺少关键话题: ${missing_topics[*]}"
    echo "💡 请检查传感器和转换节点状态"
    exit 1
fi

# 4. 数据质量检查 (使用Python更可靠)
echo ""
echo "🔍 数据质量检查..."

check_result=$(docker exec -i "${CONTAINER}" bash -lc "${ROS_SETUP}; python3 << 'PYEOF'
import rospy
from sensor_msgs.msg import Image, Imu
from geometry_msgs.msg import PointStamped
import sys

rospy.init_node(\"data_check\", anonymous=True)
results = {}

# 检查图像
try:
    msg = rospy.wait_for_message(\"/synced/image_raw\", Image, timeout=5)
    results[\"image\"] = f\"{msg.width}x{msg.height},{msg.encoding}\"
except:
    results[\"image\"] = \"timeout\"

# 检查IMU
try:
    msg = rospy.wait_for_message(\"/synced/imu\", Imu, timeout=5)
    results[\"imu\"] = f\"{msg.linear_acceleration.z:.2f}\"
except:
    results[\"imu\"] = \"timeout\"

# 检查UWB
try:
    msg = rospy.wait_for_message(\"/synced/uwb_range\", PointStamped, timeout=5)
    results[\"uwb\"] = f\"{msg.point.x:.2f}\"
except:
    results[\"uwb\"] = \"timeout\"

print(f\"IMAGE:{results['image']}|IMU:{results['imu']}|UWB:{results['uwb']}\")
PYEOF
" 2>/dev/null)

# 解析结果
image_info=$(echo "$check_result" | grep -oP 'IMAGE:\K[^|]+')
imu_info=$(echo "$check_result" | grep -oP 'IMU:\K[^|]+')
uwb_info=$(echo "$check_result" | grep -oP 'UWB:\K[^|]+')

echo "📷 检查图像格式..."
if [[ "$image_info" == *"mono8"* ]]; then
    echo "  ✅ 图像格式正确: $image_info"
elif [[ "$image_info" == "timeout" ]]; then
    echo "  ⚠️ 图像数据超时"
else
    echo "  ⚠️ 图像格式: $image_info (期望mono8)"
fi

echo "🎯 检查IMU数据..."
if [[ "$imu_info" != "timeout" ]] && [[ -n "$imu_info" ]]; then
    echo "  ✅ IMU重力: ${imu_info}m/s²"
else
    echo "  ⚠️ IMU数据超时"
fi

echo "📡 检查UWB数据..."
if [[ "$uwb_info" != "timeout" ]] && [[ -n "$uwb_info" ]]; then
    echo "  ✅ UWB距离: ${uwb_info}m"
else
    echo "  ⚠️ UWB数据超时"
fi

# 6. 启动实时图像显示（使用image_view）
echo ""
echo "📺 启动实时图像显示..."
in_container "${ROS_SETUP}; export DISPLAY=:0; nohup rosrun image_view image_view image:=/synced/image_raw > /tmp/image_view.log 2>&1 &"
sleep 2

# 7. 准备录制
mkdir -p "${HOST_OUTPUT_DIR}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BAG_NAME="virslam_synced_${TIMESTAMP}.bag"
HOST_BAG_PATH="${HOST_OUTPUT_DIR}/${BAG_NAME}"
CONTAINER_BAG_PATH="${CONTAINER_BAG_DIR}/${BAG_NAME}"

echo ""
echo "🎬 开始录制VIR-SLAM数据..."
echo "  文件名: ${BAG_NAME}"
echo "  保存到: ${HOST_BAG_PATH}"
echo "  话题数: ${#VIRSLAM_TOPICS[@]}"
echo ""
echo "📝 录制信息:"
echo "  - 时间戳: 完全同步"
echo "  - 图像格式: mono8 (灰度)"  
echo "  - UWB格式: PointStamped (距离)"
echo "  - 坐标系: 统一frame_id"
echo ""
echo "⏸️  按 Ctrl+C 停止录制"
echo ""

# 7. 在容器内创建录制目录并开始录制
in_container "mkdir -p ${CONTAINER_BAG_DIR}"

# 构建录制命令
RECORD_TOPICS_STR="${VIRSLAM_TOPICS[*]}"

echo "🔴 录制开始..."

# 清理函数 - 处理录制结束后的文件复制
cleanup_and_copy() {
    echo ""
    echo "🛑 停止录制..."

    # 停止容器内的rosbag进程
    in_container "pkill -SIGINT -f 'rosbag record'" 2>/dev/null || true
    sleep 2

    # 停止状态监控
    kill $STATUS_PID 2>/dev/null || true

    # 关闭图像显示窗口
    in_container "pkill -f rqt_image_view" 2>/dev/null || true

    echo "🔄 处理录制文件..."

    # 等待bag文件写入完成
    sleep 2

    # 检查容器内是否有bag文件
    if in_container "test -f ${CONTAINER_BAG_PATH}" 2>/dev/null; then
        if docker cp "${CONTAINER}:${CONTAINER_BAG_PATH}" "${HOST_BAG_PATH}"; then
            BAG_SIZE=$(du -h "${HOST_BAG_PATH}" | cut -f1)

            echo "✅ 录制完成!"
            echo "  文件: ${HOST_BAG_PATH}"
            echo "  大小: ${BAG_SIZE}"

            # 验证bag文件内容
            echo ""
            echo "🔍 验证bag文件内容:"
            bag_info=$(in_container "${ROS_SETUP}; rosbag info ${CONTAINER_BAG_PATH}" 2>/dev/null || echo "")
            if [ -n "$bag_info" ]; then
                echo "$bag_info" | grep -E "(topics|messages|duration|start|end)" || true

                echo ""
                echo "📋 话题数据统计:"
                for topic in "${VIRSLAM_TOPICS[@]}"; do
                    count=$(echo "$bag_info" | grep "$topic" | awk '{print $2}' || echo "0")
                    echo "  $topic: $count 条消息"
                done
            fi

            # 清理容器文件
            in_container "rm -f ${CONTAINER_BAG_PATH}" 2>/dev/null || true

            echo ""
            echo "🎯 可以直接用于VIR-SLAM处理:"
            echo "  ./process_virslam_bag.sh '${HOST_BAG_PATH}'"
            echo ""
            echo "📊 查看详细信息:"
            echo "  rosbag info '${HOST_BAG_PATH}'"
        else
            echo "❌ 文件传输失败"
        fi
    else
        # 检查是否有.active文件（正在写入的bag）
        ACTIVE_BAG="${CONTAINER_BAG_PATH}.active"
        if in_container "test -f ${ACTIVE_BAG}" 2>/dev/null; then
            echo "⚠️ 发现未完成的bag文件，尝试恢复..."
            in_container "mv ${ACTIVE_BAG} ${CONTAINER_BAG_PATH}" 2>/dev/null || true
            if docker cp "${CONTAINER}:${CONTAINER_BAG_PATH}" "${HOST_BAG_PATH}" 2>/dev/null; then
                echo "✅ 已恢复并复制bag文件: ${HOST_BAG_PATH}"
                in_container "rm -f ${CONTAINER_BAG_PATH}" 2>/dev/null || true
            else
                echo "❌ 恢复失败"
            fi
        else
            echo "❌ 未找到录制文件"
        fi
    fi

    echo ""
    echo "✅ 录制流程结束"
    exit 0
}

# 设置信号处理 - 捕获 Ctrl+C
trap cleanup_and_copy SIGINT SIGTERM

# 显示录制状态
(
  sleep 5
  while true; do
    # 检查容器内bag文件大小
    size=$(in_container "du -h ${CONTAINER_BAG_PATH} 2>/dev/null | cut -f1" 2>/dev/null || echo "")
    if [ -n "$size" ]; then
      echo "📊 录制中... 当前大小: $size"
    fi
    sleep 10
  done
) &
STATUS_PID=$!

# 开始录制（前台运行，这样Ctrl+C可以正确传递）
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; rosbag record -O ${CONTAINER_BAG_PATH} ${RECORD_TOPICS_STR}"

# 如果rosbag正常退出（不是被信号中断），也执行清理
cleanup_and_copy

# cleanup_and_copy 函数会处理所有退出情况，不会执行到这里
