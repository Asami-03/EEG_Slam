#!/usr/bin/env bash
# ============================================================
# start_all_sensors.sh  (Stable v7 - Auto Camera Detection)
#  - roscore + livox_ros_driver2 + usb_cam + nlink_parser (LinkTrack)
#  - 关键修复：容器内用 nohup 后台启动，避免 docker exec 结束就挂
#  - 自动重试 + 等待首帧
#  - LinkTrack UWB: nlink_parser + linktrack_converter.py
#  - 自动检测 USB 相机设备（支持 IMX291 等 UVC 相机）
# ============================================================

set -u
set -o pipefail

CONTAINER="vir_slam_dev"

# UWB 设备
UWB_DEVICE_HOST="/dev/ttyACM0"
UWB_DEVICE_CONT="/dev/ttyACM0"

# 相机设备（将通过 auto_detect_camera 自动设置）
CAMERA_DEVICE_HOST=""
CAMERA_DEVICE_CONT=""

# 相机自动检测：优先查找 UVC 相机（如 IMX291）
auto_detect_camera() {
  info "🔍 自动检测 USB 相机..."

  # 方法1：通过 v4l2-ctl 查找 UVC 相机
  if command -v v4l2-ctl &>/dev/null; then
    # 查找所有 video 设备，筛选 uvcvideo 驱动的设备
    for dev in /dev/video*; do
      [[ -e "$dev" ]] || continue
      local driver=$(v4l2-ctl -d "$dev" --info 2>/dev/null | grep "Driver name" | awk '{print $NF}')
      if [[ "$driver" == "uvcvideo" ]]; then
        # 检查是否支持视频捕获（排除元数据接口）
        if v4l2-ctl -d "$dev" --list-formats-ext 2>/dev/null | grep -q "Video Capture"; then
          CAMERA_DEVICE_HOST="$dev"
          CAMERA_DEVICE_CONT="$dev"
          local card=$(v4l2-ctl -d "$dev" --info 2>/dev/null | grep "Card type" | cut -d: -f2-)
          ok "检测到 UVC 相机: $dev (${card})"
          return 0
        fi
      fi
    done
  fi

  # 方法2：回退到查找任何可用的 video 设备
  for dev in /dev/video0 /dev/video1 /dev/video2 /dev/video4 /dev/video6 /dev/video8; do
    if [[ -e "$dev" ]]; then
      # 检查是否能读取设备信息
      if v4l2-ctl -d "$dev" --info &>/dev/null; then
        CAMERA_DEVICE_HOST="$dev"
        CAMERA_DEVICE_CONT="$dev"
        warn "使用回退设备: $dev"
        return 0
      fi
    fi
  done

  # 未找到相机
  CAMERA_DEVICE_HOST=""
  CAMERA_DEVICE_CONT=""
  return 1
}

# 话题名
TOPIC_LIDAR="/livox/lidar"
TOPIC_CAMERA="/usb_cam/image_raw"
TOPIC_UWB="/uwb/pose"

# 相机参数
CAM_W=640
CAM_H=480
CAM_FPS=30

# 重试配置
RETRY_LIVOX=3
RETRY_CAMERA=3
RETRY_UWB=2

# 等待首帧参数
WAIT_STEP=1
ECHO_TIMEOUT=2
ECHO_TRY=10

# 日志
LOG_ROSCORE="/tmp/roscore.log"
LOG_LIVOX="/tmp/livox.log"
LOG_CAMERA="/tmp/camera.log"
LOG_UWB="/tmp/uwb.log"
LOG_UWB_CONVERTER="/tmp/uwb_converter.log"

GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[1;33m"; BLUE="\033[0;34m"; NC="\033[0m"

die() { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${BLUE}$*${NC}"; }
ok() { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

docker_ok() { docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; }

# 统一 docker exec：不使用 -t，避免会话相关问题
ic() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
  return $?
}

# 容器内后台启动（关键：nohup + & + 写 pid）
ic_bg() {
  local cmd="$1"
  local log="$2"
  local pidfile="$3"
  ic "nohup bash -lc '${cmd}' > '${log}' 2>&1 & echo \$! > '${pidfile}'"
}

tail_log() {
  local f="$1"
  echo -e "${YELLOW}--- tail ${f} ---${NC}"
  ic "test -f '${f}' && tail -80 '${f}' || echo '(log not found)'"
}

check_host_dev() {
  local dev="$1"; local name="$2"
  if [[ -e "$dev" ]]; then ok "${name}: ${dev}"; else warn "${name} 未找到: ${dev}"; fi
}

wait_first_msg() {
  local topic="$1"
  for _ in $(seq 1 "${ECHO_TRY}"); do
    ic "source /opt/ros/noetic/setup.bash && timeout ${ECHO_TIMEOUT} rostopic echo -n 1 '${topic}' >/dev/null 2>&1"
    if [[ $? -eq 0 ]]; then return 0; fi
    sleep 0.4
  done
  return 1
}

kill_old() {
  info "🧹 清理旧进程（避免重复占用设备/重复节点）..."
  ic "set +e;
      pkill -f roscore >/dev/null 2>&1 || true;
      pkill -f rosout >/dev/null 2>&1 || true;
      pkill -f usb_cam_node >/dev/null 2>&1 || true;
      pkill -f livox_ros_driver2 >/dev/null 2>&1 || true;
      pkill -f livox_lidar_publisher2 >/dev/null 2>&1 || true;
      pkill -f nlink_parser >/dev/null 2>&1 || true;
      pkill -f linktrack >/dev/null 2>&1 || true;
      pkill -f linktrack_converter >/dev/null 2>&1 || true;
      pkill -f roslaunch >/dev/null 2>&1 || true;
      rm -f /tmp/roscore.pid /tmp/livox.pid /tmp/camera.pid /tmp/uwb.pid /tmp/uwb_converter.pid;
      exit 0" >/dev/null 2>&1 || true
  sleep 0.5
}

start_roscore() {
  info "[1/6] 启动 ROS master..."
  ic_bg "source /opt/ros/noetic/setup.bash && roscore" "${LOG_ROSCORE}" "/tmp/roscore.pid"
  # 等 roscore ready
  for _ in $(seq 1 10); do
    ic "source /opt/ros/noetic/setup.bash && rosnode list >/dev/null 2>&1"
    [[ $? -eq 0 ]] && { ok "roscore OK"; return 0; }
    sleep 1
  done
  tail_log "${LOG_ROSCORE}"
  return 1
}

start_livox() {
  info "[2/6] 启动 Livox MID360 雷达..."
  for attempt in $(seq 1 "${RETRY_LIVOX}"); do
    echo -e "${YELLOW}  - 尝试 ${attempt}/${RETRY_LIVOX}${NC}"
    ic "pkill -f livox_ros_driver2 >/dev/null 2>&1 || true; pkill -f livox_lidar_publisher2 >/dev/null 2>&1 || true; rm -f /tmp/livox.pid; exit 0" >/dev/null 2>&1 || true
    sleep 0.5

    ic_bg "source /opt/ros/noetic/setup.bash
           source /root/catkin_ws/devel/setup.bash
           roslaunch livox_ros_driver2 msg_MID360.launch" "${LOG_LIVOX}" "/tmp/livox.pid"
    sleep "${WAIT_STEP}"
    sleep 2

    if wait_first_msg "${TOPIC_LIDAR}"; then
      ok "Livox 有输出: ${TOPIC_LIDAR}"
      return 0
    fi
    warn "Livox 未抓到首帧，准备重试"
    tail_log "${LOG_LIVOX}"
  done
  return 1
}

start_camera_try_fmt() {
  local fmt="$1"  # mjpeg / yuyv
  ic "pkill -f usb_cam_node >/dev/null 2>&1 || true; rm -f /tmp/camera.pid; exit 0" >/dev/null 2>&1 || true
  sleep 0.3

  ic_bg "source /opt/ros/noetic/setup.bash
         rosrun usb_cam usb_cam_node \
           _video_device:=${CAMERA_DEVICE_CONT} \
           _image_width:=${CAM_W} \
           _image_height:=${CAM_H} \
           _framerate:=${CAM_FPS} \
           _io_method:=mmap \
           _pixel_format:=${fmt} \
           _camera_name:=usb_cam \
           _camera_frame_id:=usb_cam" "${LOG_CAMERA}" "/tmp/camera.pid"
}

start_camera() {
  info "[3/6] 启动 USB 相机..."
  for attempt in $(seq 1 "${RETRY_CAMERA}"); do
    echo -e "${YELLOW}  - 尝试 ${attempt}/${RETRY_CAMERA} (mjpeg -> yuyv)${NC}"

    start_camera_try_fmt "mjpeg"
    sleep "${WAIT_STEP}"
    if wait_first_msg "${TOPIC_CAMERA}"; then
      ok "相机有输出 (mjpeg): ${TOPIC_CAMERA}"
      return 0
    fi

    warn "mjpeg 未抓到首帧，回退 yuyv"
    start_camera_try_fmt "yuyv"
    sleep "${WAIT_STEP}"
    if wait_first_msg "${TOPIC_CAMERA}"; then
      ok "相机有输出 (yuyv): ${TOPIC_CAMERA}"
      return 0
    fi

    warn "相机本轮失败，打印日志"
    tail_log "${LOG_CAMERA}"
    ic "ps -ef | grep -E 'usb_cam_node|usb_cam' | grep -v grep || true"
  done
  return 1
}

start_uwb() {
  info "[4/6] 启动 LinkTrack UWB 定位..."
  for attempt in $(seq 1 "${RETRY_UWB}"); do
    echo -e "${YELLOW}  - 尝试 ${attempt}/${RETRY_UWB}${NC}"

    # 清理旧进程
    ic "pkill -f nlink_parser >/dev/null 2>&1 || true; pkill -f linktrack >/dev/null 2>&1 || true; pkill -f linktrack_converter >/dev/null 2>&1 || true; rm -f /tmp/uwb.pid /tmp/uwb_converter.pid; exit 0" >/dev/null 2>&1 || true
    sleep 0.3

    # 启动 LinkTrack 解析器
    ic_bg "source /opt/ros/noetic/setup.bash
           source /root/catkin_ws/devel/setup.bash
           roslaunch nlink_parser linktrack.launch" "${LOG_UWB}" "/tmp/uwb.pid"
    
    # 等待 LinkTrack 节点启动
    sleep 2

    # 启动数据格式转换器
    ic_bg "source /opt/ros/noetic/setup.bash
           source /root/catkin_ws/devel/setup.bash
           rosrun nooploop_uwb nodeframe2_converter.py" "${LOG_UWB_CONVERTER}" "/tmp/uwb_converter.pid"
    
    sleep "${WAIT_STEP}"

    # 直接检查转换后的UWB话题（更可靠）
    if wait_first_msg "${TOPIC_UWB}"; then
      ok "UWB 标准格式输出: ${TOPIC_UWB}"
      return 0
    else
      warn "UWB转换器未输出，检查日志"
      tail_log "${LOG_UWB}"
      tail_log "${LOG_UWB_CONVERTER}"
    fi
  done

  # UWB 不作为硬失败（你后面还要先采集 LiDAR+相机也能用）
  warn "UWB 可能未稳定输出（继续流程，不强制退出）"
  return 0
}

verify_all() {
  info "[5/6] 传感器数据验证（抓首帧）..."
  ic "source /opt/ros/noetic/setup.bash && rosnode list || true"

  if wait_first_msg "${TOPIC_LIDAR}"; then ok "LiDAR OK"; else warn "LiDAR 无首帧"; fi
  if wait_first_msg "${TOPIC_CAMERA}"; then ok "Camera OK"; else warn "Camera 无首帧"; tail_log "${LOG_CAMERA}"; fi
  if wait_first_msg "${TOPIC_UWB}"; then 
    ok "UWB OK"
  else 
    warn "UWB 无首帧"; 
    tail_log "${LOG_UWB}"; 
    tail_log "${LOG_UWB_CONVERTER}"
  fi
}

monitor_sensors() {
  info "🔄 传感器监控模式启动 (Ctrl+C 退出)"
  echo -e "${BLUE}监控间隔: 30秒${NC}"
  echo -e "${YELLOW}实时状态检查...${NC}"
  
  local check_count=0
  
  while true; do
    ((check_count++))
    echo -e "\n${BLUE}======== 第 ${check_count} 次检查 $(date '+%H:%M:%S') ========${NC}"
    
    # 检查ROS节点状态
    echo -e "${YELLOW}ROS节点状态:${NC}"
    ic "source /opt/ros/noetic/setup.bash && rosnode list 2>/dev/null | head -10 || echo '❌ ROS未运行'"
    
    # 检查传感器话题
    local lidar_ok=0; local camera_ok=0; local uwb_ok=0
    
    if ic "source /opt/ros/noetic/setup.bash && timeout 3 rostopic echo -n 1 '${TOPIC_LIDAR}' >/dev/null 2>&1"; then
      ok "LiDAR 数据流正常: ${TOPIC_LIDAR}"
      lidar_ok=1
    else
      warn "LiDAR 数据流异常"
    fi
    
    if ic "source /opt/ros/noetic/setup.bash && timeout 3 rostopic echo -n 1 '${TOPIC_CAMERA}' >/dev/null 2>&1"; then
      ok "Camera 数据流正常: ${TOPIC_CAMERA}"
      camera_ok=1
    else
      warn "Camera 数据流异常"
    fi
    
    if ic "source /opt/ros/noetic/setup.bash && timeout 3 rostopic echo -n 1 '${TOPIC_UWB}' >/dev/null 2>&1"; then
      ok "UWB 数据流正常: ${TOPIC_UWB}"
      uwb_ok=1
    else
      warn "UWB 数据流异常"
    fi
    
    # 统计状态
    local total_ok=$((lidar_ok + camera_ok + uwb_ok))
    echo -e "${BLUE}状态汇总: ${total_ok}/3 传感器正常${NC}"
    
    # 如果有传感器异常，尝试重启
    if [[ $total_ok -lt 3 ]]; then
      warn "检测到传感器异常，30秒后尝试重启异常传感器..."
    fi
    
    # 等待30秒或用户中断
    echo -e "${YELLOW}等待30秒进行下次检查... (Ctrl+C 停止监控)${NC}"
    sleep 30 || break
  done
}

restart_failed_sensors() {
  info "🔧 重启异常传感器..."
  
  # 检查并重启LiDAR
  if ! wait_first_msg "${TOPIC_LIDAR}"; then
    warn "重启 Livox LiDAR..."
    start_livox || warn "Livox 重启失败"
  fi
  
  # 检查并重启Camera
  if ! wait_first_msg "${TOPIC_CAMERA}"; then
    warn "重启 USB Camera..."
    start_camera || warn "Camera 重启失败"
  fi
  
  # 检查并重启UWB
  if ! wait_first_msg "${TOPIC_UWB}"; then
    warn "重启 UWB..."
    start_uwb || warn "UWB 重启失败"
  fi
}

cleanup_on_exit() {
  echo -e "\n${YELLOW}接收到退出信号，清理进程...${NC}"
  kill_old
  echo -e "${GREEN}清理完成，退出。${NC}"
  exit 0
}

main() {
  # 设置退出信号处理
  trap cleanup_on_exit INT TERM

  echo -e "${GREEN}=================================================${NC}"
  echo -e "${GREEN}🚀 VIR-SLAM 传感器持续运行模式${NC}"
  echo -e "${BLUE}   📡 Livox MID360 + 📷 USB Cam + 🔗 LinkTrack UWB${NC}"
  echo -e "${GREEN}=================================================${NC}"

  docker_ok || die "容器未运行：${CONTAINER}（先 docker start ${CONTAINER}）"

  # 自动检测相机设备
  if ! auto_detect_camera; then
    die "未检测到 USB 相机，请检查连接"
  fi

  info "硬件设备检测（Host侧）..."
  check_host_dev "${CAMERA_DEVICE_HOST}" "单目相机 (自动检测)"
  check_host_dev "${UWB_DEVICE_HOST}" "LinkTrack UWB"

  info "传感器信息展示..."
  ok "Livox MID360: 网络雷达 (192.168.20.178 → 192.168.20.50)"
  ok "端口: 56301 (点云), 56401 (IMU)"
  ok "LinkTrack UWB: 串口设备 ${UWB_DEVICE_HOST} (921600 baud)"

  kill_old

  info "[阶段 1/3] 启动核心服务..."
  start_roscore || die "roscore 启动失败"
  
  info "[阶段 2/3] 启动传感器..."
  start_livox   || die "Livox 启动失败（请先确保 MID360 网络 OK）"

  if ! start_camera; then
    die "相机启动失败（重点看 /tmp/camera.log）"
  fi

  start_uwb || true

  info "[阶段 3/3] 初始验证..."
  verify_all

  echo -e "${GREEN}=================================================${NC}"
  echo -e "${GREEN}🎉 所有传感器启动完成！${NC}"
  echo -e "${GREEN}=================================================${NC}"
  echo -e "${YELLOW}快速检查命令：${NC}"
  echo "  docker exec -i ${CONTAINER} bash -lc 'source /opt/ros/noetic/setup.bash && rostopic list'"
  echo "  docker exec -i ${CONTAINER} bash -lc 'source /opt/ros/noetic/setup.bash && rostopic echo -n 1 ${TOPIC_UWB}'"
  
  # 进入持续监控模式
  monitor_sensors
}

main "$@"
