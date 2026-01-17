#!/bin/bash
# Simple ROS1-ROS2 bridge using Docker Compose
# This is much more reliable than building from source on Ubuntu 22.04

set -e

echo "=========================================="
echo "Setting up ROS1-ROS2 Bridge with Docker"
echo "=========================================="
echo ""
echo "This is a simpler alternative to building from source."
echo "It uses a pre-built Docker image with ros1_bridge."
echo ""

# Stop any existing bridge containers
docker stop ros1_bridge 2>/dev/null || true
docker rm ros1_bridge 2>/dev/null || true

echo "Creating bridge container..."
echo ""

# Create a bridge container that can communicate with both ROS1 and ROS2
cat > /tmp/run_bridge.sh << 'EOF'
#!/bin/bash
source /opt/ros/noetic/setup.bash
source /opt/ros/foxy/setup.bash
export ROS_MASTER_URI=http://172.17.0.1:11311
export ROS_HOSTNAME=172.17.0.1
ros2 run ros1_bridge dynamic_bridge --bridge-all-topics
EOF

chmod +x /tmp/run_bridge.sh

echo "Starting bridge container..."
echo ""
echo "Note: This uses a community-built image with ROS1 Noetic + ROS2 Foxy"
echo ""

# Try to pull and run a pre-built ros1_bridge image
docker run -it --rm \
  --name ros1_bridge \
  --network host \
  -v /tmp/run_bridge.sh:/run_bridge.sh \
  dustynv/ros:foxy-ros1-bridge-l4t-r35.2.1 \
  /bin/bash -c "
    source /opt/ros/noetic/setup.bash && 
    source /opt/ros/foxy/setup.bash && 
    export ROS_MASTER_URI=http://localhost:11311 && 
    ros2 run ros1_bridge dynamic_bridge --bridge-all-topics
  "

echo ""
echo "Bridge stopped."
