#!/bin/bash
# 在宿主机 Ubuntu 22.04 上安装 ros1_bridge
# 这样就可以直接桥接 Docker 里的 ROS1 到宿主机的 ROS2

set -e

echo "==========================================="
echo "在宿主机上安装 ros1_bridge"
echo "系统要求: Ubuntu 22.04 + ROS2 Humble"
echo "==========================================="

# 1. 安装 ROS1 Noetic (Ubuntu 22.04 需要从源码或使用 Docker)
# Ubuntu 22.04 官方不支持 Noetic，但 ros1_bridge 需要同时有 ROS1 和 ROS2

echo ""
echo "注意: Ubuntu 22.04 不官方支持 ROS1 Noetic"
echo "ros1_bridge 安装有两种方式:"
echo ""
echo "方式1: 安装预编译包（推荐，简单）"
echo "  sudo apt install ros-humble-ros1-bridge"
echo ""
echo "方式2: 从源码编译（复杂，但更灵活）"
echo ""

read -p "使用方式1安装预编译包？(y/n): " choice

if [ "$choice" = "y" ]; then
    echo ""
    echo "正在安装 ros-humble-ros1-bridge..."
    sudo apt update
    sudo apt install -y ros-humble-ros1-bridge
    
    echo ""
    echo "✅ 安装完成！"
    echo ""
    echo "使用方法:"
    echo "1. 确保 Docker 容器的 ROS1 master 可访问:"
    echo "   在容器内: roscore"
    echo "   或设置 ROS_MASTER_URI"
    echo ""
    echo "2. 在宿主机终端1启动 bridge:"
    echo "   source /opt/ros/humble/setup.bash"
    echo "   export ROS_MASTER_URI=http://localhost:11311"
    echo "   ros2 run ros1_bridge dynamic_bridge"
    echo ""
    echo "3. 在宿主机终端2查看话题:"
    echo "   source /opt/ros/humble/setup.bash"
    echo "   ros2 topic list"
    echo ""
    echo "4. 启动 RViz2:"
    echo "   rviz2"
    echo ""
else
    echo ""
    echo "如需从源码编译，请参考:"
    echo "https://github.com/ros2/ros1_bridge"
    echo ""
    echo "但注意：Ubuntu 22.04 上编译 ros1_bridge 需要先从源码编译 ROS1 Noetic"
    echo "这会非常耗时（1-2小时）"
fi
