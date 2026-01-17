#!/usr/bin/env bash
# 检查UWB设备当前输出什么格式的数据

CONTAINER="vir_slam_dev"
GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[1;33m"; BLUE="\033[0;34m"; NC="\033[0m"

die() { echo -e "${RED}❌ $*${NC}"; exit 1; }
info() { echo -e "${BLUE}$*${NC}"; }
ok() { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

# 检查容器
docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}" || die "容器未运行：${CONTAINER}"

ic() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
  return $?
}

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE} 🔍 UWB数据格式检测${NC}"
echo -e "${BLUE}=================================================${NC}"

info "清理旧进程..."
ic "pkill -f ros || true; pkill -f linktrack || true"
sleep 1

info "启动ROS和LinkTrack..."
ic "source /opt/ros/noetic/setup.bash && nohup roscore > /tmp/check_roscore.log 2>&1 &"
sleep 2

ic "source /opt/ros/noetic/setup.bash && source /root/catkin_ws/devel/setup.bash && nohup roslaunch nlink_parser linktrack.launch > /tmp/check_linktrack.log 2>&1 &"
sleep 3

info "检查发布的话题..."
topics=$(ic "source /opt/ros/noetic/setup.bash && rostopic list | grep nlink_linktrack")

if [[ -n "$topics" ]]; then
  ok "检测到以下UWB话题:"
  echo "$topics"
  
  echo -e "\n${YELLOW}检查各话题的数据...${NC}"
  
  for topic in $topics; do
    echo -e "\n${BLUE}检查话题: $topic${NC}"
    
    # 尝试接收一条消息
    if ic "source /opt/ros/noetic/setup.bash && timeout 5 rostopic echo -n 1 '$topic' 2>/dev/null"; then
      ok "话题 $topic 有数据"
    else
      warn "话题 $topic 无数据或超时"
    fi
  done
  
  echo -e "\n${YELLOW}特别检查NodeFrame2话题...${NC}"
  if echo "$topics" | grep -q "nodeframe2"; then
    ok "✅ 检测到NodeFrame2话题！"
    echo -e "${GREEN}您的设备已配置为NodeFrame2格式${NC}"
  else
    warn "❌ 未检测到NodeFrame2话题"
    echo -e "${YELLOW}需要配置UWB设备输出NodeFrame2格式${NC}"
    echo -e "${YELLOW}请使用NAssistant软件配置设备协议${NC}"
  fi
  
else
  die "未检测到任何UWB话题，请检查设备连接"
fi

echo -e "\n${BLUE}=================================================${NC}"
echo -e "${GREEN}检测完成${NC}"
echo -e "${BLUE}=================================================${NC}"
