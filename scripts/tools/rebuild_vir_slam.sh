#!/bin/bash
# 重新编译 VIR-SLAM
# 使用方法: ./rebuild_vir_slam.sh

echo "==========================================="
echo "重新编译 VIR-SLAM"
echo "==========================================="

# 检查容器是否运行
if ! docker ps | grep -q vir_slam_dev; then
    echo "错误: vir_slam_dev 容器未运行"
    echo "请先启动容器: docker start vir_slam_dev"
    exit 1
fi

echo ""
echo "正在编译..."
docker exec vir_slam_dev bash -c "
    source /opt/ros/noetic/setup.bash && 
    cd /root/catkin_ws && 
    catkin_make -j4
"

if [ $? -eq 0 ]; then
    echo ""
    echo "==========================================="
    echo "✅ VIR-SLAM 编译成功!"
    echo "==========================================="
else
    echo ""
    echo "==========================================="
    echo "❌ VIR-SLAM 编译失败"
    echo "==========================================="
    exit 1
fi
