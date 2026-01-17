#!/bin/bash
# Build ros1_bridge on Ubuntu 22.04 host with ROS2 Humble
# This requires building ROS1 Noetic from source first, then building ros1_bridge

set -e

echo "=========================================="
echo "Building ros1_bridge on Ubuntu 22.04 Host"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Install ROS1 Noetic from source (~20-30 min)"
echo "  2. Build ros1_bridge (~10-20 min)"
echo "  3. Total time: ~30-60 minutes"
echo ""
echo "Requirements:"
echo "  - Ubuntu 22.04"
echo "  - ROS2 Humble already installed"
echo "  - ~5GB free disk space"
echo ""

read -p "Continue? (y/n): " choice
if [ "$choice" != "y" ]; then
    echo "Aborted."
    exit 0
fi

# Check ROS2 Humble is installed
if [ ! -f /opt/ros/humble/setup.bash ]; then
    echo "Error: ROS2 Humble not found. Please install it first:"
    echo "  sudo apt update"
    echo "  sudo apt install ros-humble-desktop"
    exit 1
fi

echo ""
echo "Step 1/6: Installing dependencies..."
sudo apt update
sudo apt install -y \
    python3-rosdep \
    python3-rosinstall-generator \
    python3-vcstool \
    python3-rosinstall \
    build-essential \
    python3-catkin-pkg \
    python3-colcon-common-extensions \
    cmake \
    g++ \
    gcc \
    git \
    libbz2-dev \
    libconsole-bridge-dev \
    liblz4-dev \
    libpoco-dev \
    libtinyxml2-dev \
    pkg-config

# Initialize rosdep if not already done
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    sudo rosdep init
fi
rosdep update

echo ""
echo "Step 2/6: Creating workspace for ROS1 Noetic..."
mkdir -p ~/ros1_noetic_ws/src
cd ~/ros1_noetic_ws

echo ""
echo "Step 3/6: Downloading ROS1 Noetic source code..."
# Get minimal ROS1 Noetic packages needed for the bridge
# Use a more minimal set to avoid build issues
rosinstall_generator actionlib common_msgs geometry_msgs nav_msgs sensor_msgs std_msgs std_srvs tf2_msgs trajectory_msgs visualization_msgs rospy_tutorials --rosdistro noetic --deps --tar > noetic.rosinstall
vcs import src < noetic.rosinstall

echo ""
echo "Step 4/6: Installing ROS1 dependencies..."
rosdep install --from-paths src --ignore-src -y --skip-keys="python3-catkin-pkg-modules python3-rospkg-modules"

echo ""
echo "Step 5/6: Building ROS1 Noetic (~20-30 min)..."
echo "This will take a while. Go get some coffee! ☕"
# Build ROS1 with catkin_make_isolated in a clean environment
# CRITICAL: Must use env -i to clear ROS2 Humble variables that conflict with ROS1 build
cd ~/ros1_noetic_ws
env -i HOME=$HOME USER=$USER PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    bash -c "./src/catkin/bin/catkin_make_isolated --install \
    --install-space ~/ros1_install \
    --source-space src \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DPYTHON_EXECUTABLE=/usr/bin/python3 \
    --make-args -j4"

echo ""
echo "Step 6/6: Building ros1_bridge..."
mkdir -p ~/ros1_bridge_ws/src
cd ~/ros1_bridge_ws/src

# Clone ros1_bridge
if [ ! -d "ros1_bridge" ]; then
    git clone https://github.com/ros2/ros1_bridge.git -b humble
fi

cd ~/ros1_bridge_ws

# Source both ROS1 and ROS2
source ~/ros1_install/setup.bash
source /opt/ros/humble/setup.bash

# Build the bridge
colcon build --symlink-install --packages-select ros1_bridge --cmake-force-configure

echo ""
echo "=========================================="
echo "✅ Build complete!"
echo "=========================================="
echo ""
echo "To use the bridge:"
echo ""
echo "Terminal 1 (Docker - ROS1 master):"
echo "  docker exec -it vir_slam_dev bash"
echo "  source /opt/ros/noetic/setup.bash"
echo "  roscore"
echo ""
echo "Terminal 2 (Host - ros1_bridge):"
echo "  source ~/ros1_install/setup.bash"
echo "  source /opt/ros/humble/setup.bash"
echo "  source ~/ros1_bridge_ws/install/setup.bash"
echo "  export ROS_MASTER_URI=http://localhost:11311"
echo "  ros2 run ros1_bridge dynamic_bridge --bridge-all-topics"
echo ""
echo "Terminal 3 (Host - RViz2):"
echo "  source /opt/ros/humble/setup.bash"
echo "  rviz2"
echo ""
echo "Setup file created at: ~/ros1_bridge_ws/install/setup.bash"
