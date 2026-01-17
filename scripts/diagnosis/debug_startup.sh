#!/usr/bin/env bash
# 简化的VIR-SLAM启动脚本（用于调试）

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

echo "🔧 VIR-SLAM 启动调试脚本"
echo "========================="

# 工具函数
die() { echo "❌ $*" 1>&2; exit 1; }
docker_running() {
  docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"
}
in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}

# 1. 检查容器
echo "🔍 检查Docker容器..."
if docker_running; then
    echo "✅ 容器运行中"
else
    die "容器未运行，请先执行: ./start_container.sh"
fi

# 2. 检查ROS环境
echo "🔍 检查ROS环境..."
if in_container "${ROS_SETUP}; which roscore" >/dev/null 2>&1; then
    echo "✅ ROS环境正常"
else
    echo "❌ ROS环境异常"
    exit 1
fi

# 3. 清理旧进程（安全模式）
echo "🧹 安全清理旧进程..."
in_container "pkill -f 'livox_ros_driver2|usb_cam|nooploop' 2>/dev/null || echo '无旧进程需要清理'"

# 4. 启动roscore
echo "🏁 确保roscore运行..."
if in_container "${ROS_SETUP}; pgrep roscore >/dev/null 2>&1"; then
    echo "✅ roscore已运行"
else
    echo "🚀 启动roscore..."
    in_container "${ROS_SETUP}; nohup roscore > /tmp/roscore.log 2>&1 &"
    sleep 5
    if in_container "${ROS_SETUP}; pgrep roscore >/dev/null 2>&1"; then
        echo "✅ roscore启动成功"
    else
        echo "❌ roscore启动失败"
        echo "日志:"
        in_container "cat /tmp/roscore.log || echo '无日志文件'"
        exit 1
    fi
fi

# 5. 测试基本ROS功能
echo "🔍 测试ROS基本功能..."
if in_container "${ROS_SETUP}; timeout 5 rostopic list >/dev/null 2>&1"; then
    echo "✅ ROS通信正常"
else
    echo "❌ ROS通信异常"
    exit 1
fi

echo ""
echo "✅ 基础环境检查通过！"
echo "💡 可以继续运行完整启动脚本:"
echo "   ./start_sensors_and_converters.sh"
