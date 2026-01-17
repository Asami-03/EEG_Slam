#!/bin/bash

# 在Docker容器内安装硬件驱动脚本
# 使用方法: 
#   1. ./enter_container.sh
#   2. 在容器内运行: bash /host/install_drivers.sh

echo "╔════════════════════════════════════════════════════════╗"
echo "║  在Docker容器内安装硬件驱动                            ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

cd /root/catkin_ws/src

# 1. 安装Livox MID-360驱动
echo "========================================="
echo "📦 安装 Livox MID-360 驱动"
echo "========================================="
if [ ! -d "livox_ros_driver2" ]; then
    git clone https://github.com/Livox-SDK/livox_ros_driver2.git
    echo "✅ Livox驱动已克隆"
else
    echo "⏭️  Livox驱动已存在"
fi

# 2. 安装相机驱动 (usb_cam)
echo ""
echo "========================================="
echo "📦 安装 USB Camera 驱动"
echo "========================================="
apt-get update
apt-get install -y ros-noetic-usb-cam
echo "✅ usb_cam 已安装"

# 3. 安装UWB驱动 (Nooploop)
echo ""
echo "========================================="
echo "📦 安装 Nooploop LinkTrack 驱动"
echo "========================================="
if [ ! -d "nlink_parser" ]; then
    git clone https://github.com/nooploop-dev/nlink_parser.git
    echo "✅ Nooploop驱动已克隆"
else
    echo "⏭️  Nooploop驱动已存在"
fi

# 4. 编译
echo ""
echo "========================================="
echo "🔨 编译ROS工作空间"
echo "========================================="
cd /root/catkin_ws
catkin_make

echo ""
echo "========================================="
echo "✅ 驱动安装完成！"
echo "========================================="
echo ""
echo "下一步："
echo "  1. 配置相机参数: /root/catkin_ws/src/VIR-SLAM/src/VIR_VINS/config/"
echo "  2. 标定相机内参和IMU外参"
echo "  3. 测试硬件连接: "
echo "     roslaunch usb_cam usb_cam-test.launch"
echo "     roslaunch livox_ros_driver2 msg_MID360.launch"
echo "     roslaunch nlink_parser linktrack.launch"
echo ""
