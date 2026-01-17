#!/bin/bash
# VIR-SLAM bag 播放脚本 - 播放完自动停止

BAG_PATH="$1"
CONFIG_TYPE="${2:-imx291_mid360}"
CONTAINER="vir_slam_dev"

if [ -z "$BAG_PATH" ]; then
    echo "用法: $0 <bag文件路径> [config_type]"
    echo "示例: $0 /root/vir_slam_output/bags/xxx.bag imx291_mid360"
    exit 1
fi

ROS_SETUP="source /opt/ros/noetic/setup.bash && source /root/catkin_ws/devel/setup.bash"

echo "🚀 启动 VIR-SLAM 处理"
echo "  Bag: $BAG_PATH"
echo "  Config: $CONFIG_TYPE"
echo ""

# 清理之前的结果
docker exec -i $CONTAINER bash -c "rm -f /tmp/vins_result*.csv"

# 后台启动 rosbag play
echo "▶️ 后台启动 bag 播放..."
docker exec -d $CONTAINER bash -c "$ROS_SETUP && rosbag play $BAG_PATH --clock -r 1.0"
sleep 2

# 前台启动 VIR-SLAM (显示所有输出)
echo "📡 启动 VIR-SLAM..."
echo "==========================================="

# 捕获 Ctrl+C 来清理
cleanup() {
    echo ""
    echo "🛑 停止 VIR-SLAM..."
    docker exec -i $CONTAINER bash -c "pkill -f 'rosbag play' 2>/dev/null; rosnode kill /vir_estimator /vir_feature_tracker 2>/dev/null; pkill -f vir_estimator 2>/dev/null"
    sleep 2

    # 检查结果
    echo ""
    echo "📊 检查结果..."
    RESULT=$(docker exec -i $CONTAINER bash -c "wc -l /tmp/vins_result_no_loop.csv 2>/dev/null | cut -d' ' -f1")

    if [ "$RESULT" -gt "0" ] 2>/dev/null; then
        echo "✅ 处理成功! 轨迹点数: $RESULT"
        echo ""
        echo "结果文件: /tmp/vins_result_no_loop.csv"
        docker exec -i $CONTAINER bash -c "head -3 /tmp/vins_result_no_loop.csv"
    else
        echo "❌ 未生成有效结果"
        echo "可能原因: IMU激励不足 / 特征点不够 / 初始化失败"
    fi

    echo ""
    echo "✅ 完成"
    exit 0
}

trap cleanup SIGINT SIGTERM

# 前台运行 VIR-SLAM，显示所有输出
docker exec -it $CONTAINER bash -c "$ROS_SETUP && roslaunch vir_estimator vir_spiriBag.launch config_type:=$CONFIG_TYPE"

# 如果 roslaunch 正常退出，也执行清理
cleanup
