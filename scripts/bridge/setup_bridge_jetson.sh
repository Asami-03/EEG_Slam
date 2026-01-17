#!/bin/bash
# Use NVIDIA's pre-built ros1_bridge for Jetson
# This is the EASIEST and MOST RELIABLE method for Jetson ARM64

set -e

echo "==========================================="
echo "ROS1-ROS2 Bridge for Jetson (Docker method)"
echo "==========================================="
echo ""

# Check if vir_slam_dev is running
if ! docker ps | grep -q vir_slam_dev; then
    echo "Error: vir_slam_dev container is not running"
    echo "Please start it first with: docker start vir_slam_dev"
    exit 1
fi

echo "Searching for Jetson-compatible ros1_bridge images..."
echo ""

# List of potential images to try (for Jetson ARM64)
IMAGES=(
    "dustynv/ros:foxy-ros1-bridge-l4t-r36.2.0"
    "dustynv/ros:foxy-ros1-bridge-l4t-r35.4.1"
    "dustynv/ros:foxy-ros1-bridge-l4t-r35.2.1"
    "dustynv/ros:humble-ros1-bridge-l4t-r36.2.0"
)

# Try each image
for img in "${IMAGES[@]}"; do
    echo "Trying to pull: $img"
    if docker pull $img 2>/dev/null; then
        echo "✅ Successfully pulled $img"
        BRIDGE_IMAGE=$img
        break
    else
        echo "❌ Image not found, trying next..."
    fi
done

if [ -z "$BRIDGE_IMAGE" ]; then
    echo ""
    echo "⚠️  No pre-built image found."
    echo ""
    echo "Alternative: Install ROS2 Foxy in the existing container"
    read -p "Would you like to try that instead? (y/n): " choice
    if [ "$choice" = "y" ]; then
        ./install_ros2_in_container.sh
    fi
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ Bridge image ready: $BRIDGE_IMAGE"
echo "=========================================="
echo ""
echo "To use the bridge:"
echo ""
echo "Terminal 1 (Start roscore in vir_slam_dev):"
echo "  docker exec -it vir_slam_dev bash -c 'source /opt/ros/noetic/setup.bash && roscore'"
echo ""
echo "Terminal 2 (Start bridge):"
echo "  docker run -it --rm --network host $BRIDGE_IMAGE \\"
echo "    bash -c 'source /opt/ros/noetic/setup.bash && source /opt/ros/foxy/setup.bash && \\"
echo "    export ROS_MASTER_URI=http://localhost:11311 && \\"
echo "    ros2 run ros1_bridge dynamic_bridge --bridge-all-topics'"
echo ""
echo "Terminal 3 (Check ROS2 topics on host):"
echo "  source /opt/ros/humble/setup.bash"
echo "  ros2 topic list"
echo ""
echo "Terminal 4 (RViz2 on host):"
echo "  source /opt/ros/humble/setup.bash"
echo "  rviz2"
echo ""

# Save the image name for future reference
echo "$BRIDGE_IMAGE" > /home/jetson/vir_slam_docker/.bridge_image
