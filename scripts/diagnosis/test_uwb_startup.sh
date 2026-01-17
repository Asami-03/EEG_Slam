#!/bin/bash
# 测试UWB启动脚本

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

echo "🧪 UWB系统启动测试"
echo "=================="

# 工具函数
in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}

# 1. 清理UWB相关进程
echo "🧹 清理UWB相关进程..."
in_container "pkill -f 'nlink_parser|linktrack|nodeframe2' 2>/dev/null || true"
sleep 2

# 2. 确保roscore运行
echo "🔍 检查roscore..."
if ! in_container "${ROS_SETUP}; pgrep roscore >/dev/null"; then
    echo "🚀 启动roscore..."
    in_container "${ROS_SETUP}; nohup roscore > /tmp/roscore.log 2>&1 &"
    sleep 3
fi

# 3. 启动LinkTrack解析器
echo "📡 启动LinkTrack解析器..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup roslaunch nlink_parser linktrack.launch > /tmp/uwb_nlink.log 2>&1 &"
sleep 5

# 4. 检查中间话题
echo "🔍 检查LinkTrack原始话题..."
if in_container "${ROS_SETUP}; timeout 5 rostopic list | grep -E '(nlink|linktrack)'"; then
    echo "✅ LinkTrack话题存在"
    in_container "${ROS_SETUP}; timeout 5 rostopic list | grep -E '(nlink|linktrack)'"
else
    echo "❌ LinkTrack话题不存在，检查日志:"
    in_container "tail -10 /tmp/uwb_nlink.log"
    exit 1
fi

# 5. 启动格式转换器
echo "🔄 启动UWB格式转换器..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup rosrun nooploop_uwb nodeframe2_converter.py > /tmp/uwb_converter.log 2>&1 &"
sleep 3

# 6. 检查最终话题
echo "🎯 检查最终UWB话题..."
for i in {1..20}; do
    if in_container "${ROS_SETUP}; timeout 3 rostopic list | grep -qx '/uwb/pose'"; then
        echo "✅ /uwb/pose 话题已就绪！"
        
        # 测试数据流
        echo "📊 测试数据流..."
        if in_container "${ROS_SETUP}; timeout 5 rostopic echo /uwb/pose --count=1"; then
            echo "✅ UWB数据流正常！"
        else
            echo "⚠️ UWB话题存在但无数据"
        fi
        exit 0
    fi
    echo -n "."
    sleep 1
done

echo ""
echo "❌ /uwb/pose 话题超时未出现"
echo ""
echo "🔍 调试信息:"
echo "LinkTrack日志:"
in_container "tail -10 /tmp/uwb_nlink.log"
echo ""
echo "转换器日志:"  
in_container "tail -10 /tmp/uwb_converter.log"
echo ""
echo "当前话题列表:"
in_container "${ROS_SETUP}; rostopic list | grep -E '(uwb|nlink|linktrack)'"
