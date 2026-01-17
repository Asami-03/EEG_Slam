#!/usr/bin/env bash
set -euo pipefail

# VIR-SLAM Bag Processing Script
# 用于将录制好的bag文件导入VIR-SLAM进行处理

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

# ====== 参数检查 ======
if [ $# -ne 1 ]; then
    echo "❌ 用法: $0 <bag文件路径>"
    echo "   例如: $0 /home/jetson/vir_slam_output/bags/virslam_20260112_205424/virslam_20260112_205424.bag"
    exit 1
fi

BAG_PATH="$1"

# ====== 工具函数 ======
die() { echo "❌ $*" 1>&2; exit 1; }

docker_running() {
  docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"
}

in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}

# ====== 检查 ======
[ -f "${BAG_PATH}" ] || die "Bag文件不存在: ${BAG_PATH}"
docker_running || die "容器 ${CONTAINER} 未运行。请先运行 ./start_container.sh"

# ====== 转换路径到容器内路径 ======
# 将宿主机路径转换为容器内可访问的路径
if [[ "${BAG_PATH}" == /home/jetson/vir_slam_output/* ]]; then
    # 如果在output目录，需要先复制到挂载目录
    BAG_FILENAME=$(basename "${BAG_PATH}")
    HOST_TEMP_DIR="/home/jetson/vir_slam_docker/temp_bags"
    mkdir -p "${HOST_TEMP_DIR}"
    
    echo "📋 复制bag文件到挂载目录..."
    cp "${BAG_PATH}" "${HOST_TEMP_DIR}/${BAG_FILENAME}"
    
    CONTAINER_BAG_PATH="/host/temp_bags/${BAG_FILENAME}"
elif [[ "${BAG_PATH}" == /home/jetson/vir_slam_docker/* ]]; then
    # 如果已经在docker挂载目录内
    CONTAINER_BAG_PATH="/host${BAG_PATH#/home/jetson/vir_slam_docker}"
else
    die "Bag文件必须在 /home/jetson/vir_slam_docker/ 或 /home/jetson/vir_slam_output/ 目录下"
fi

echo "🎯 开始处理bag文件: ${BAG_PATH}"
echo "📍 容器内路径: ${CONTAINER_BAG_PATH}"

# ====== 检查bag文件内容 ======
echo "📋 检查bag文件内容..."
in_container "${ROS_SETUP}; rosbag info ${CONTAINER_BAG_PATH}"

echo ""
echo "🚀 启动VIR-SLAM处理..."

# ====== 启动VIR-SLAM ======
# 在后台启动VIR-SLAM
echo "📍 启动VIR-SLAM核心节点..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup roslaunch vir_estimator vir_spiriBag.launch enable_real_uwb_module:=0 > /tmp/vir_slam.log 2>&1 &"

# 启动UWB话题转换器
echo "🔄 启动UWB话题转换器..."
in_container "${ROS_SETUP}; nohup python3 /host/uwb_pose_to_range_converter.py > /tmp/uwb_converter.log 2>&1 &"

# 等待系统启动
echo "⏱️  等待VIR-SLAM系统启动..."
sleep 8

# 检查节点是否正常运行
echo "🔍 检查VIR-SLAM节点状态..."
in_container "${ROS_SETUP}; rosnode list | grep -E '(vir_feature_tracker|vir_estimator|uwb_pose_to_range)'"

echo ""
echo "🔄 检查UWB话题转换..."
in_container "${ROS_SETUP}; timeout 3s rostopic hz /uwb/corrected_range 2>/dev/null || echo 'UWB转换器准备中...'"

echo ""
echo "▶️  播放bag文件..."
# 播放bag文件 (可以调整播放速度)
PLAY_RATE="1.0"  # 播放速度倍数
in_container "${ROS_SETUP}; rosbag play ${CONTAINER_BAG_PATH} -r ${PLAY_RATE} --clock"

echo ""
echo "✅ Bag文件处理完成!"
echo "ℹ️  VIR-SLAM输出日志: docker exec ${CONTAINER} cat /tmp/vir_slam.log"
echo "ℹ️  UWB转换器日志: docker exec ${CONTAINER} cat /tmp/uwb_converter.log"
echo "ℹ️  要停止VIR-SLAM: docker exec ${CONTAINER} pkill -f 'vir_|uwb_pose_to_range'"

# 清理临时文件
if [[ -n "${HOST_TEMP_DIR:-}" ]] && [[ -f "${HOST_TEMP_DIR}/${BAG_FILENAME}" ]]; then
    echo "🧹 清理临时文件..."
    rm -f "${HOST_TEMP_DIR}/${BAG_FILENAME}"
    rmdir "${HOST_TEMP_DIR}" 2>/dev/null || true
fi
