#!/bin/bash
CONTAINER_NAME="vir_slam_dev"
IMAGE_NAME="vir_slam:noetic"

# 检查容器是否已存在
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "🔄 启动已存在的容器..."
    docker start $CONTAINER_NAME
    echo "✅ 容器已启动: $CONTAINER_NAME"
else
    echo "🆕 创建新容器..."

    # 确保持久化目录存在
    mkdir -p $HOME/vir_slam_docker/catkin_ws_build
    mkdir -p $HOME/vir_slam_docker/catkin_ws_devel
    mkdir -p $HOME/vir_slam_docker/catkin_ws_logs

    docker run -d \
        --name $CONTAINER_NAME \
        --privileged \
        --network host \
        -v /dev:/dev \
        -v $HOME/vir_slam_docker/catkin_ws_src:/root/catkin_ws/src \
        -v $HOME/vir_slam_docker/catkin_ws_build:/root/catkin_ws/build \
        -v $HOME/vir_slam_docker/catkin_ws_devel:/root/catkin_ws/devel \
        -v $HOME/vir_slam_docker/catkin_ws_logs:/root/catkin_ws/logs \
        -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
        -v $HOME/vir_slam_docker:/host \
        -v $HOME/vir_slam_output:/root/vir_slam_output \
        -e DISPLAY=$DISPLAY \
        -e QT_X11_NO_MITSHM=1 \
        $IMAGE_NAME \
        tail -f /dev/null
    echo "✅ 容器已创建: $CONTAINER_NAME"
fi
