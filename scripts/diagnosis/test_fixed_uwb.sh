#!/usr/bin/env bash
# 快速UWB测试脚本

set -e

CONTAINER="vir_slam_dev"
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
echo -e "${BLUE} 🧪 UWB快速测试${NC}"
echo -e "${BLUE}=================================================${NC}"

info "1. 清理旧进程..."
ic "pkill -f ros || true; pkill -f linktrack || true"
sleep 1

info "2. 启动ROS master..."
ic "source /opt/ros/noetic/setup.bash && nohup roscore > /tmp/roscore_quick.log 2>&1 &"
sleep 3

info "3. 启动LinkTrack解析器..."
ic "source /opt/ros/noetic/setup.bash && source /root/catkin_ws/devel/setup.bash && nohup roslaunch nlink_parser linktrack.launch > /tmp/linktrack_quick.log 2>&1 &"
sleep 3

info "4. 检查话题列表..."
ic "source /opt/ros/noetic/setup.bash && rostopic list"

info "5. 启动数据监听器..."
echo -e "${YELLOW}监听所有UWB话题，观察接收到什么格式的数据...${NC}"
echo -e "${YELLOW}按 Ctrl+C 停止监听${NC}"

ic "source /opt/ros/noetic/setup.bash && source /root/catkin_ws/devel/setup.bash && python3 /root/catkin_ws/src/nooploop_uwb/scripts/test_uwb_data.py"
