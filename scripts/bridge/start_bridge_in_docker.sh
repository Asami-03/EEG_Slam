#!/bin/bash
#
# 在Docker容器内启动ROS1-ROS2 Bridge
# 用于将宿主机ROS2的D435话题桥接到Docker内的ROS1
#
# 使用方法:
#   1. 确保宿主机ROS2已发布D435话题
#   2. 在Docker内的另一个终端运行roscore
#   3. 运行此脚本
#

echo "=========================================="
echo "  ROS1-ROS2 Bridge (Docker内部)"
echo "=========================================="

# ============================================
# 配置 - 根据你的环境修改
# ============================================
ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-66}  # 与宿主机ROS2一致

echo ""
echo "配置信息:"
echo "  ROS_DOMAIN_ID: $ROS_DOMAIN_ID"
echo "  ROS_MASTER_URI: ${ROS_MASTER_URI:-http://localhost:11311}"
echo ""

# ============================================
# 检查roscore是否运行
# ============================================
echo "检查ROS1 Master..."
source /opt/ros/noetic/setup.bash

if ! rostopic list &>/dev/null; then
    echo ""
    echo "错误: ROS1 Master (roscore) 未运行!"
    echo ""
    echo "请在另一个终端先运行:"
    echo "  source /opt/ros/noetic/setup.bash"
    echo "  roscore"
    echo ""
    exit 1
fi
echo "ROS1 Master 运行中"

# ============================================
# 检查ROS2话题
# ============================================
echo ""
echo "检查ROS2话题..."
source /opt/ros/foxy/setup.bash
export ROS_DOMAIN_ID=$ROS_DOMAIN_ID

ROS2_TOPICS=$(ros2 topic list 2>/dev/null | grep -E "camera|image" | head -5)
if [ -z "$ROS2_TOPICS" ]; then
    echo ""
    echo "警告: 未检测到ROS2相机话题"
    echo "请确保宿主机的D435驱动正在运行"
    echo ""
    echo "宿主机运行命令:"
    echo "  ros2 launch realsense2_camera rs_launch.py"
    echo ""
    echo "按Enter继续启动bridge，或Ctrl+C取消..."
    read
else
    echo "检测到ROS2话题:"
    echo "$ROS2_TOPICS"
fi

# ============================================
# 启动Bridge
# ============================================
echo ""
echo "=========================================="
echo "启动Bridge..."
echo ""
echo "桥接后，以下话题将在ROS1中可用:"
echo "  /camera/camera/color/image_raw"
echo "  /camera/camera/color/camera_info"
echo "  /camera/camera/depth/image_rect_raw"
echo "  /camera/imu (如果D435i有IMU)"
echo ""
echo "验证命令 (在另一个终端):"
echo "  rostopic list | grep camera"
echo "  rostopic hz /camera/camera/color/image_raw"
echo ""
echo "按 Ctrl+C 停止bridge"
echo "=========================================="
echo ""

# 关键: 先source ROS1, 再source ROS2
# 这样ros1_bridge才能同时访问两个环境
source /opt/ros/noetic/setup.bash
source /opt/ros/foxy/setup.bash

# 设置环境变量
export ROS_DOMAIN_ID=$ROS_DOMAIN_ID
export ROS_MASTER_URI=${ROS_MASTER_URI:-http://localhost:11311}

# 启动动态bridge
ros2 run ros1_bridge dynamic_bridge --bridge-all-topics
