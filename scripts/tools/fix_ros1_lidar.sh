#!/bin/bash

################################################################################
# 修复 ROS1 Livox 雷达数据输出问题
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

clear
echo "╔════════════════════════════════════════════════════════╗"
echo "║        修复 ROS1 Livox 雷达数据输出                    ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# 1. 完全清理所有旧进程
log_step "1/5: 完全清理旧进程"
docker exec vir_slam_dev pkill -9 -f "livox" 2>/dev/null || true
docker exec vir_slam_dev pkill -9 -f "roslaunch" 2>/dev/null || true
docker exec vir_slam_dev pkill -9 rosmaster 2>/dev/null || true
docker exec vir_slam_dev pkill -9 roscore 2>/dev/null || true
sleep 2
docker exec vir_slam_dev bash -c "source ~/catkin_ws/devel/setup.bash && rosnode cleanup 2>/dev/null" || true
sleep 1

# 验证清理
REMAINING=$(docker exec vir_slam_dev pgrep -f "livox\|roscore" | wc -l)
if [ "$REMAINING" -eq 0 ]; then
    log_info "✅ 所有旧进程已清理"
else
    log_warn "⚠️  仍有 $REMAINING 个进程残留，强制清理..."
    docker exec vir_slam_dev pkill -9 -f "ros" 2>/dev/null || true
    sleep 2
fi
echo ""

# 2. 检查网络连接
log_step "2/5: 检查雷达网络连接"
LIDAR_IP="192.168.20.178"
if ping -c 2 -W 1 $LIDAR_IP &>/dev/null; then
    log_info "✅ 雷达网络连接正常 ($LIDAR_IP)"
else
    log_error "❌ 无法连接雷达 $LIDAR_IP"
    echo ""
    echo "请检查："
    echo "  1. 雷达是否上电"
    echo "  2. 网线是否连接"
    echo "  3. 主机IP配置: $(ip addr show | grep 192.168.20 | awk '{print $2}')"
    exit 1
fi
echo ""

# 3. 检查配置文件
log_step "3/5: 检查配置文件"
CONFIG_FILE="/home/jetson/vir_slam_docker/catkin_ws_src/livox_ros_driver2/config/MID360_config.json"
if [ -f "$CONFIG_FILE" ]; then
    HOST_IP=$(docker exec vir_slam_dev grep -A 1 "cmd_data_ip" ~/catkin_ws/src/livox_ros_driver2/config/MID360_config.json | grep "192.168" | sed 's/.*"\(192.168[^"]*\)".*/\1/')
    LIDAR_CFG_IP=$(docker exec vir_slam_dev grep '"ip"' ~/catkin_ws/src/livox_ros_driver2/config/MID360_config.json | grep -v "//" | sed 's/.*"\(192.168[^"]*\)".*/\1/')
    
    log_info "配置文件检查:"
    echo "  Host IP: $HOST_IP"
    echo "  Lidar IP: $LIDAR_CFG_IP"
    
    # 验证IP配置
    ACTUAL_HOST_IP=$(ip addr show | grep "192.168.20" | head -1 | awk '{print $2}' | cut -d'/' -f1)
    if [ "$HOST_IP" != "$ACTUAL_HOST_IP" ]; then
        log_warn "⚠️  配置文件中的Host IP ($HOST_IP) 与实际IP ($ACTUAL_HOST_IP) 不匹配"
        echo "  建议修改配置文件或检查网络配置"
    else
        log_info "✅ IP配置正确"
    fi
else
    log_error "❌ 配置文件不存在: $CONFIG_FILE"
    exit 1
fi
echo ""

# 4. 启动 roscore
log_step "4/5: 启动 ROS Master"
docker exec -d vir_slam_dev bash -c "source /opt/ros/noetic/setup.bash && roscore" 2>/dev/null
sleep 3

if docker exec vir_slam_dev pgrep -f roscore >/dev/null; then
    log_info "✅ roscore 已启动"
else
    log_error "❌ roscore 启动失败"
    exit 1
fi
echo ""

# 5. 启动 Livox 驱动（只启动一次）
log_step "5/5: 启动 Livox 雷达驱动"
docker exec -d vir_slam_dev bash -c "
    source ~/catkin_ws/devel/setup.bash && \
    roslaunch livox_ros_driver2 msg_MID360.launch 2>&1 | tee /tmp/livox_launch.log
" 2>/dev/null

sleep 5

# 检查进程
LIVOX_COUNT=$(docker exec vir_slam_dev pgrep -f livox_ros_driver2_node | wc -l)
if [ "$LIVOX_COUNT" -eq 1 ]; then
    log_info "✅ Livox 驱动已启动（进程数: 1）"
elif [ "$LIVOX_COUNT" -gt 1 ]; then
    log_warn "⚠️  检测到多个Livox进程 ($LIVOX_COUNT)，这可能导致问题"
else
    log_error "❌ Livox 驱动未启动"
    exit 1
fi
echo ""

# 6. 等待并验证数据输出
log_step "验证数据输出"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sleep 3

# 检查话题
log_info "检查 ROS 话题..."
TOPICS=$(docker exec vir_slam_dev bash -c "source ~/catkin_ws/devel/setup.bash && rostopic list 2>/dev/null")
echo "$TOPICS"
echo ""

if echo "$TOPICS" | grep -q "/livox/lidar"; then
    log_info "✅ 发现话题: /livox/lidar"
    
    # 检查数据频率
    log_info "测试数据频率（10秒）..."
    timeout 10 docker exec vir_slam_dev bash -c "
        source ~/catkin_ws/devel/setup.bash && \
        rostopic hz /livox/lidar 2>&1
    " || log_warn "⚠️  超时或无数据"
    
    echo ""
    
    # 检查带宽
    log_info "检查数据带宽（5秒）..."
    timeout 5 docker exec vir_slam_dev bash -c "
        source ~/catkin_ws/devel/setup.bash && \
        rostopic bw /livox/lidar 2>&1
    " || log_warn "⚠️  无数据传输"
    
else
    log_error "❌ 未找到 /livox/lidar 话题"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 7. 诊断信息
log_step "诊断信息"
echo ""
echo "📊 端口监听状态:"
docker exec vir_slam_dev bash -c "netstat -anp 2>/dev/null | grep -E '56[0-9]{3}' || echo '  未检测到Livox端口监听'"
echo ""

echo "📊 进程状态:"
docker exec vir_slam_dev bash -c "ps aux | grep -E 'livox|roscore' | grep -v grep"
echo ""

echo "💡 如果仍无数据，请检查："
echo "  1. 查看详细日志: docker exec -it vir_slam_dev cat /tmp/livox_launch.log"
echo "  2. 检查驱动日志: docker exec -it vir_slam_dev tail -100 ~/.ros/log/latest/rosout.log"
echo "  3. 验证雷达固件版本和驱动兼容性"
echo "  4. 尝试重启雷达设备"
echo ""

log_info "✅ 修复脚本执行完成"
