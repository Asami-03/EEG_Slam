#!/bin/bash
# Start the ROS1 <-> ROS2 Bridge
# This bridges topics from VIR-SLAM (ROS1) to your host (ROS2)

set -e

echo "🌉 Starting ROS1-ROS2 Bridge"
echo "============================="

# Check if VIR-SLAM container is running
if ! docker ps --format '{{.Names}}' | grep -q "^vir_slam_dev$"; then
    echo "❌ VIR-SLAM container is not running!"
    echo "💡 Start it first with: docker start vir_slam_dev"
    exit 1
fi

# Check if roscore is running in VIR-SLAM container
if ! docker exec vir_slam_dev bash -c "source /opt/ros/noetic/setup.bash && rostopic list" &>/dev/null; then
    echo "⚠️  ROS1 roscore not detected in VIR-SLAM container"
    echo "🚀 Starting roscore..."
    docker exec -d vir_slam_dev bash -c "source /opt/ros/noetic/setup.bash && roscore"
    sleep 3
fi

echo "✅ ROS1 environment ready"
echo "🌉 Starting dynamic bridge..."
echo ""
echo "📡 Bridge will forward these topics from ROS1 → ROS2:"
echo "   /tf, /tf_static (transforms)"
echo "   /camera/image_raw (images)"
echo "   /imu/data (IMU)"
echo "   /odometry/* (odometry)"
echo "   And more standard sensor_msgs, nav_msgs topics"
echo ""
echo "💡 On your host machine, you can now:"
echo "   - ros2 topic list (see bridged topics)"
echo "   - rviz2 (visualize in RViz2)"
echo ""
echo "Press Ctrl+C to stop the bridge"
echo "================================"

# Start the bridge container with --net=host to share network with VIR-SLAM container
docker run -it --rm \
  --net=host \
  --name ros1_bridge \
  ros:humble-ros1-bridge \
  bash -c "source /opt/ros/humble/setup.bash && ros2 run ros1_bridge dynamic_bridge --bridge-all-topics"
