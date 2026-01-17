#!/usr/bin/env bash
set -euo pipefail

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash 2>/dev/null || true"

# ====== 输出目录（宿主机）======
HOST_BASE="/home/jetson/vir_slam_output/bags"
mkdir -p "${HOST_BASE}"

# ====== 容器内目录 ======
BAG_ROOT_IN="/tmp/virslam_bags"

# ====== 必录/可选话题 ======
REQUIRED_TOPICS=(
  "/livox/lidar"
  "/usb_cam/image_raw"
  "/uwb/pose"
)

OPTIONAL_TOPICS=(
  "/livox/imu"
  "/usb_cam/camera_info"  
  "/nlink_linktrack_anchorframe0"
  "/nlink_linktrack_nodeframe2"
)

# ====== 工具函数 ======
die() { echo "❌ $*" 1>&2; exit 1; }

docker_running() {
  docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"
}

in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}

topic_exists() {
  local t="$1"
  in_container "${ROS_SETUP}; rostopic list 2>/dev/null | grep -qx '${t}'"
}

wait_first_msg() {
  local t="$1"
  local timeout_s="${2:-30}"
  # echo -n 1 拿到一条就返回；timeout 防卡死
  in_container "${ROS_SETUP}; timeout ${timeout_s} rostopic echo -n 1 '${t}' >/dev/null 2>&1"
}

# ====== 开始 ======
echo " Bag Recorder"


docker_running || die "容器 ${CONTAINER} 未运行。先 ./start_container.sh"

BAG_ID="virslam_$(date +%Y%m%d_%H%M%S)"
BAG_DIR_IN="${BAG_ROOT_IN}/${BAG_ID}"
BAG_FILE_IN="${BAG_DIR_IN}/${BAG_ID}.bag"

echo "ℹ️  本次录制 ID: ${BAG_ID}"
echo "ℹ️  容器内保存: ${BAG_DIR_IN}"
echo "ℹ️  宿主机保存: ${HOST_BASE}/${BAG_ID}"

echo "ℹ️  检查必录话题是否存在..."
for t in "${REQUIRED_TOPICS[@]}"; do
  topic_exists "${t}" || die "必录话题不存在：${t}（先启动传感器发布）"
  echo "✅ 存在: ${t}"
done

RECORD_TOPICS=("${REQUIRED_TOPICS[@]}")
echo "ℹ️  检查可选话题（存在则加入录制）..."
for t in "${OPTIONAL_TOPICS[@]}"; do
  if topic_exists "${t}"; then
    echo "✅ 加入录制: ${t}"
    RECORD_TOPICS+=("${t}")
  else
    echo "➖ 不存在(跳过): ${t}"
  fi
done

echo "ℹ️  等待必录话题首帧（最长 30s），确保不是空包..."
for t in "${REQUIRED_TOPICS[@]}"; do
  wait_first_msg "${t}" 30 || die "等待首帧超时：${t}（请检查该传感器是否真在发）"
done
echo "✅ 三路必录话题均已抓到首帧，开始录包！"

# 确保容器内目录存在
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; mkdir -p '${BAG_DIR_IN}'"

echo "-------------------------------------------------"
echo "🟢 Recording..."
echo "  Bag: ${BAG_FILE_IN}"
echo "  Topics:"
for t in "${RECORD_TOPICS[@]}"; do echo "    - ${t}"; done
echo ""
echo "  Press Ctrl+C to stop."
echo "-------------------------------------------------"

# 前台录制：用户 Ctrl+C 会停止 rosbag record
set +e
docker exec -it "${CONTAINER}" bash -lc "
  ${ROS_SETUP};
  ${CATKIN_SETUP};
  cd '${BAG_DIR_IN}';
  rosbag record -O '${BAG_FILE_IN}' ${RECORD_TOPICS[*]}
"
RET=$?
set -e

echo ""
echo "ℹ️  录制结束（exit=${RET}），开始校验与拷贝到宿主机..."r

# 1) 容器内校验文件存在且非空
in_container "ls -lh '${BAG_FILE_IN}'" || die "容器内找不到 bag：${BAG_FILE_IN}"

# 2) rosbag info 校验 topic/message count
in_container "${ROS_SETUP}; rosbag info '${BAG_FILE_IN}' | sed -n '1,120p'" || true

# 3) 拷贝到宿主机（强制 docker cp，避免挂载没配导致 host 为空）
mkdir -p "${HOST_BASE}"
docker cp "${CONTAINER}:${BAG_DIR_IN}" "${HOST_BASE}/" || die "docker cp 失败"

echo "✅ 已拷贝到宿主机：${HOST_BASE}/${BAG_ID}"
echo "ℹ️  宿主机文件列表："
ls -lh "${HOST_BASE}/${BAG_ID}" || true


echo "Done"
