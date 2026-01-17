#!/bin/bash

echo "╔════════════════════════════════════════════════════════╗"
echo "║     进入 VIR-SLAM Docker 容器                          ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "📂 挂载配置："
echo "   容器内: /root/catkin_ws/src  ←→  主机: $HOME/vir_slam_docker/catkin_ws_src"
echo ""
echo "🖥️  GUI支持: 已启用 (可显示相机画面)"
echo ""

CONTAINER_NAME="vir_slam_interactive"
IMAGE_NAME="vir_slam:noetic"
SRC_DIR="$HOME/vir_slam_docker/catkin_ws_src"

# 检查容器是否存在
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "🔄 发现已存在的容器，正在删除..."
    docker rm -f $CONTAINER_NAME >/dev/null 2>&1
fi

echo "🆕 创建新容器（支持GUI）..."
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
    $IMAGE_NAME \
    bash

echo ""
echo "✅ 已退出容器"
echo "📁 源代码保留在: $SRC_DIR"
