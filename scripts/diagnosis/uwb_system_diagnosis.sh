#!/usr/bin/env bash
# UWB系统诊断脚本

set -e

CONTAINER="vir_slam_dev"
UWB_DEVICE="/dev/ttyACM0"

GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[1;33m"; BLUE="\033[0;34m"; NC="\033[0m"

die() { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${BLUE}$*${NC}"; }
ok() { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

# 检查容器
docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}" || die "容器未运行：${CONTAINER}"

# 统一 docker exec
ic() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
  return $?
}

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE} 🔍 UWB系统诊断${NC}"
echo -e "${BLUE}=================================================${NC}"

echo -e "\n${YELLOW}1. 检查硬件设备${NC}"
if [[ -e "${UWB_DEVICE}" ]]; then
  ok "Host设备存在: ${UWB_DEVICE}"
  ls -la "${UWB_DEVICE}"
else
  die "Host设备不存在: ${UWB_DEVICE}"
fi

echo -e "\n${YELLOW}2. 检查容器内设备${NC}"
if ic "test -e '${UWB_DEVICE}'"; then
  ok "容器内设备存在: ${UWB_DEVICE}"
  ic "ls -la '${UWB_DEVICE}'"
else
  die "容器内设备不存在: ${UWB_DEVICE}"
fi

echo -e "\n${YELLOW}3. 检查设备权限${NC}"
ic "stat ${UWB_DEVICE}"

echo -e "\n${YELLOW}4. 尝试读取设备数据${NC}"
info "测试串口通信..."
if ic "timeout 3 head -c 10 '${UWB_DEVICE}' >/dev/null 2>&1"; then
  ok "设备可读取"
else
  warn "设备读取测试失败或无数据"
fi

echo -e "\n${YELLOW}5. 检查波特率兼容性${NC}"
info "测试不同波特率..."
for baud in 921600 460800 230400 115200; do
  if ic "python3 -c \"
import serial
try:
  ser = serial.Serial('${UWB_DEVICE}', ${baud}, timeout=1)
  ser.close()
  print('波特率 ${baud}: OK')
except Exception as e:
  print('波特率 ${baud}: 失败 -', str(e))
\""; then
    continue
  fi
done

echo -e "\n${YELLOW}6. 检查ROS环境${NC}"
if ic "source /opt/ros/noetic/setup.bash && rosnode list >/dev/null 2>&1"; then
  ok "ROS master运行中"
else
  warn "ROS master未运行"
fi

echo -e "\n${YELLOW}7. 测试nlink_parser${NC}"
info "尝试启动LinkTrack解析器..."
ic "source /opt/ros/noetic/setup.bash && source /root/catkin_ws/devel/setup.bash && timeout 5 roslaunch nlink_parser linktrack.launch" || warn "LinkTrack启动测试失败"

echo -e "\n${YELLOW}8. 检查Python依赖${NC}"
ic "python3 -c \"
try:
  import serial
  print('✅ pyserial: OK')
except ImportError:
  print('❌ pyserial: 缺失')

try:
  import numpy
  print('✅ numpy: OK')  
except ImportError:
  print('❌ numpy: 缺失')

try:
  import yaml
  print('✅ pyyaml: OK')
except ImportError:
  print('❌ pyyaml: 缺失')
\""

echo -e "\n${BLUE}=================================================${NC}"
echo -e "${GREEN}🔍 诊断完成${NC}"
echo -e "${BLUE}=================================================${NC}"
