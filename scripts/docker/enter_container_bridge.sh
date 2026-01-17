#!/bin/bash

echo "╔════════════════════════════════════════════════════════╗"
echo "║   进入 VIR-SLAM Docker 容器 (带ROS1-ROS2 Bridge)       ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "📂 挂载配置："
echo "   容器内: /root/catkin_ws/src  ←→  主机: $HOME/vir_slam_docker/catkin_ws_src"
echo ""
echo "🌉 Bridge使用说明:"
echo "   1. 在容器内开一个终端运行: roscore"
echo "   2. 开另一个终端运行: /host/scripts/bridge/start_bridge_in_docker.sh"
echo "   3. 验证: rostopic list | grep camera"
echo ""

CONTAINER_NAME="vir_slam_bridge"
IMAGE_NAME="vir_slam:bridge"
SRC_DIR="$HOME/vir_slam_docker/catkin_ws_src"

# 检查镜像是否存在
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
    echo "❌ 镜像 $IMAGE_NAME 不存在"
    echo ""
    echo "请先构建镜像:"
    echo "  cd $HOME/vir_slam_docker"
    echo "  docker build -f Dockerfile.bridge -t vir_slam:bridge ."
    echo ""
    exit 1
fi

# 检查容器是否存在
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "🔄 发现已存在的容器，正在删除..."
    docker rm -f $CONTAINER_NAME >/dev/null 2>&1
fi

echo "🆕 创建新容器..."

# 获取宿主机的ROS_DOMAIN_ID
HOST_DOMAIN_ID=${ROS_DOMAIN_ID:-66}

docker run -it --rm \
    --name $CONTAINER_NAME \
    --privileged \
    --network host \
    -v /dev:/dev \
    -v $SRC_DIR:/root/catkin_ws/src \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v $HOME/vir_slam_docker:/host \
    -e DISPLAY=$DISPLAY \
    -e QT_X11_NO_MITSHM=1 \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e ROS_DOMAIN_ID=$HOST_DOMAIN_ID \
    $IMAGE_NAME \
    bash

echo ""
echo "✅ 已退出容器"
echo "📁 源代码保留在: $SRC_DIR"
