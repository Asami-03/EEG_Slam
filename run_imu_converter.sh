#!/bin/bash
# 运行 IMU 到 Pose 转换器
# 用于将bag文件中的IMU数据转换为可在RViz中可视化的Pose消息

echo "==========================================="
echo "启动 IMU 到 Pose 转换器"
echo "==========================================="

# 检查容器是否运行
if ! docker ps | grep -q vir_slam_dev; then
    echo "错误: vir_slam_dev 容器未运行"
    echo "请先启动容器: docker start vir_slam_dev"
    exit 1
fi

# 复制脚本到容器
echo "复制转换脚本到容器..."
docker cp /home/jetson/vir_slam_docker/imu_to_pose_converter.py vir_slam_dev:/root/

echo ""
echo "启动转换器..."
echo "订阅话题: /synced/imu"
echo "发布话题: /imu_pose (PoseStamped)"
echo "发布话题: /imu_path (Path)"
echo ""

# 在容器内运行转换器
docker exec -it vir_slam_dev bash -c "
    source /opt/ros/noetic/setup.bash && 
    cd /root && 
    python3 imu_to_pose_converter.py
"
