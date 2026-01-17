#!/usr/bin/env bash
# 检查bag文件内容的脚本

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"

echo "🔍 检查bag文件内容..."

# 方法1: 使用rosbag info (可能很慢)
echo "📋 尝试获取bag信息..."
timeout 30s docker exec "${CONTAINER}" bash -c "${ROS_SETUP} && rosbag info /host/temp_processing.bag" 2>/dev/null | grep -E "topics:|messages:|duration:" || echo "rosbag info 超时"

echo ""
echo "📊 播放前几秒检查话题..."
# 方法2: 播放几秒钟看看有什么话题
timeout 10s docker exec "${CONTAINER}" bash -c "${ROS_SETUP} && rosbag play /host/temp_processing.bag --clock -u 5 &" 2>/dev/null &
sleep 3

echo "当前活动话题:"
docker exec "${CONTAINER}" bash -c "${ROS_SETUP} && rostopic list 2>/dev/null" || echo "无法获取话题列表"

echo ""
echo "🎯 检查关键话题频率..."
for topic in "/livox/lidar" "/usb_cam/image_raw" "/uwb/pose" "/livox/imu" "/camera/color/image_raw" "/mavros/imu/data_raw"
do
    echo -n "  $topic: "
    timeout 3s docker exec "${CONTAINER}" bash -c "${ROS_SETUP} && rostopic hz $topic" 2>/dev/null | head -1 || echo "无数据"
done

# 停止播放
docker exec "${CONTAINER}" bash -c "pkill -f rosbag" 2>/dev/null || true
