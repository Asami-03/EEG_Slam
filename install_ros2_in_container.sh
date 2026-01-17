#!/bin/bash
# Install ROS2 Humble and build ros1_bridge from source INSIDE the vir_slam_dev container
# This way we have both ROS1 Noetic and ROS2 Humble in the same container
# Optimized for Jetson ARM64

set -e

echo "==========================================="
echo "Building ros1_bridge from source"
echo "Platform: ARM64 (Jetson)"
echo "Container: vir_slam_dev"
echo "==========================================="

# Check if container is running
if ! docker ps | grep -q vir_slam_dev; then
    echo "Starting vir_slam_dev container..."
    docker start vir_slam_dev || {
        echo "Error: Cannot start container. Is it created?"
        exit 1
    }
fi

echo ""
echo "This will install ROS2 Humble and build ros1_bridge from source"
echo "Estimated time: 20-30 minutes"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Starting installation..."
echo ""

docker exec -it vir_slam_dev bash -c '
set -e

echo ""
echo "========================================"
echo "Step 1/6: Installing prerequisites"
echo "========================================"
apt update
apt install -y software-properties-common curl gnupg lsb-release wget

echo ""
echo "========================================"
echo "Step 2/6: Adding ROS2 repository"
echo "========================================"
# Add ROS2 apt repository
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null

echo ""
echo "========================================"
echo "Step 3/6: Installing ROS2 Humble"
echo "========================================"
apt update
apt install -y ros-humble-ros-base \
    ros-humble-common-interfaces \
    ros-humble-sensor-msgs \
    ros-humble-geometry-msgs \
    ros-humble-nav-msgs \
    ros-humble-std-msgs \
    ros-humble-tf2-msgs

echo ""
echo "========================================"
echo "Step 4/6: Installing build tools"
echo "========================================"
apt install -y \
    python3-colcon-common-extensions \
    python3-rosdep \
    python3-vcstool \
    build-essential \
    cmake \
    git

# Initialize rosdep if not already done
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    rosdep init || true
fi
rosdep update

echo ""
echo "========================================"
echo "Step 5/6: Cloning ros1_bridge source"
echo "========================================"
mkdir -p /root/bridge_ws/src
cd /root/bridge_ws/src

if [ -d "ros1_bridge" ]; then
    echo "ros1_bridge already exists, pulling latest..."
    cd ros1_bridge && git pull && cd ..
else
    echo "Cloning ros1_bridge (humble branch)..."
    git clone https://github.com/ros2/ros1_bridge.git -b humble
fi

cd /root/bridge_ws

echo ""
echo "========================================"
echo "Step 6/6: Building ros1_bridge"
echo "========================================"
echo "This will take 15-20 minutes..."
echo ""

# Source both ROS1 and ROS2 environments
source /opt/ros/noetic/setup.bash
source /opt/ros/humble/setup.bash

# Build with verbose output
colcon build --symlink-install \
    --packages-select ros1_bridge \
    --cmake-force-configure \
    --event-handlers console_direct+

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "✅ BUILD SUCCESSFUL!"
    echo "========================================"
    echo ""
    echo "Setup instructions:"
    echo "1. Enter container: docker exec -it vir_slam_dev bash"
    echo "2. Source environments:"
    echo "   source /opt/ros/noetic/setup.bash"
    echo "   source /opt/ros/humble/setup.bash"
    echo "   source /root/bridge_ws/install/setup.bash"
    echo "3. Start bridge:"
    echo "   ros2 run ros1_bridge dynamic_bridge"
    echo ""
else
    echo ""
    echo "❌ BUILD FAILED"
    echo "Check the error messages above"
    exit 1
fi
'

BUILD_STATUS=$?

echo ""
echo "==========================================="
if [ $BUILD_STATUS -eq 0 ]; then
    echo "✅ ros1_bridge installation complete!"
    echo ""
    echo "Created helper script for easy launching..."
    
    # Create a helper script to launch the bridge
    cat > /home/jetson/vir_slam_docker/start_bridge.sh << 'EOF'
#!/bin/bash
# Start ros1_bridge inside vir_slam_dev container

echo "Starting ros1_bridge..."
echo "Make sure roscore is running in the container!"
echo ""

docker exec -it vir_slam_dev bash -c '
source /opt/ros/noetic/setup.bash
source /opt/ros/humble/setup.bash
source /root/bridge_ws/install/setup.bash
ros2 run ros1_bridge dynamic_bridge --bridge-all-topics
'
EOF
    chmod +x /home/jetson/vir_slam_docker/start_bridge.sh
    
    echo ""
    echo "Quick start:"
    echo "  ./start_bridge.sh"
    echo ""
else
    echo "❌ Installation failed"
    echo "Check error messages above"
fi
echo "==========================================="
