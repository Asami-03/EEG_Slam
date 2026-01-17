# ROS1-ROS2 Bridge Usage Guide

This guide shows you how to use the ROS1-ROS2 bridge to visualize VIR-SLAM data in RViz2 on your host machine.

## Architecture

```
┌─────────────────────┐   ┌────────────────────┐   ┌──────────────────┐
│ VIR-SLAM Container  │   │ Bridge Container   │   │ Host Machine     │
│ (Ubuntu 20.04)      │   │ (Ubuntu 22.04)     │   │ (Ubuntu 22.04)   │
│ ROS1 Noetic         │──>│ ROS1 + ROS2 Humble │──>│ ROS2 Humble      │
│                     │   │ ros1_bridge        │   │                  │
│ - VIR-SLAM nodes    │   │                    │   │ - rviz2          │
│ - rosbag play       │   │                    │   │ - ros2 topic list│
└─────────────────────┘   └────────────────────┘   └──────────────────┘
```

## Quick Start

### Terminal 1: Start VIR-SLAM

```bash
# Start VIR-SLAM container (if not running)
docker start vir_slam_dev

# Enter container and start VIR-SLAM
docker exec -it vir_slam_dev bash
source /opt/ros/noetic/setup.bash
source /root/catkin_ws/devel/setup.bash

# Start roscore
roscore &

# Launch VIR-SLAM
roslaunch vir_estimator vir_spiriBag.launch config_type:=imx291_mid360 enable_real_uwb_module:=0 &

# Play your bag file
rosbag play /host/temp_bags/virslam_complete_20260114_143124.bag --clock
```

### Terminal 2: Start the Bridge (on host)

```bash
cd /home/jetson/vir_slam_docker
./bridge_ros2_to_ros1.sh
```

This will:
- Check if VIR-SLAM container is running
- Start roscore if needed
- Launch the ros1_bridge to forward ROS1 → ROS2 topics

### Terminal 3: Check ROS2 Topics (on host)

```bash
# List all available ROS2 topics
ros2 topic list

# Echo a specific topic
ros2 topic echo /tf

# Check topic info
ros2 topic info /camera/image_raw
```

### Terminal 4: Start RViz2 (on host)

```bash
# Set simulation time (important for bag playback)
ros2 param set /rviz2 use_sim_time true

# Start RViz2
rviz2
```

In RViz2, add displays:
- **TF** - to see coordinate frames
- **Odometry** - to see robot pose (if available)
- **Path** - to see trajectory
- **Image** - to see camera feed
- **PointCloud2** - to see lidar points

## Common Topics Bridged

| ROS1 Topic (VIR-SLAM) | ROS2 Topic (Host) | Type |
|----------------------|-------------------|------|
| `/tf` | `/tf` | tf2_msgs/TFMessage |
| `/tf_static` | `/tf_static` | tf2_msgs/TFMessage |
| `/synced/image_raw` | `/synced/image_raw` | sensor_msgs/Image |
| `/synced/imu` | `/synced/imu` | sensor_msgs/Imu |
| `/synced/lidar` | `/synced/lidar` | sensor_msgs/PointCloud2 |
| `/vins_estimator/odometry` | `/vins_estimator/odometry` | nav_msgs/Odometry |
| `/vins_estimator/path` | `/vins_estimator/path` | nav_msgs/Path |

## Troubleshooting

### Bridge shows no topics

**Problem:** ros1_bridge starts but no topics are bridged

**Solution:**
1. Make sure roscore is running in VIR-SLAM container:
   ```bash
   docker exec vir_slam_dev bash -c "source /opt/ros/noetic/setup.bash && rostopic list"
   ```

2. Make sure topics are being published:
   ```bash
   docker exec vir_slam_dev bash -c "source /opt/ros/noetic/setup.bash && rostopic hz /tf"
   ```

### RViz2 shows "No tf data"

**Problem:** RViz2 can't see transform data

**Solution:**
1. Set `use_sim_time` to true:
   ```bash
   ros2 param set /rviz2 use_sim_time true
   ```

2. Make sure `/tf` topic is being published on ROS2 side:
   ```bash
   ros2 topic echo /tf --once
   ```

### Topics appear but no data in RViz2

**Problem:** Topics exist but RViz2 shows "No messages received"

**Solution:**
1. Check if bag file is playing with `--clock` flag:
   ```bash
   rosbag play your.bag --clock
   ```

2. Verify data is flowing:
   ```bash
   ros2 topic hz /synced/image_raw
   ```

### Custom message types not bridged

**Problem:** VIR-SLAM custom messages (like `vins_msgs/*`) don't appear

**Solution:**
The bridge only supports standard ROS messages (sensor_msgs, nav_msgs, geometry_msgs, tf2_msgs).
For custom messages, you would need to rebuild the bridge with those message types included.

## Performance Tips

1. **Reduce bag playback speed** if bridge is slow:
   ```bash
   rosbag play your.bag --clock -r 0.5  # Half speed
   ```

2. **Bridge only needed topics** (advanced):
   Instead of `--bridge-all-topics`, specify topics manually:
   ```bash
   ros2 run ros1_bridge parameter_bridge /tf@tf2_msgs/msg/TFMessage
   ```

3. **Use lightweight visualizations**:
   - Disable point cloud if you only need trajectory
   - Reduce image quality if needed

## Stopping Everything

1. **Stop RViz2**: Close the window or Ctrl+C
2. **Stop Bridge**: Ctrl+C in the bridge terminal
3. **Stop VIR-SLAM**: 
   ```bash
   docker exec vir_slam_dev pkill -f vir_estimator
   docker exec vir_slam_dev pkill roscore
   ```

## Alternative: Offline Visualization

If real-time bridging is too complex, you can visualize results offline:

```bash
# Copy trajectory file from container
docker cp vir_slam_dev:/tmp/vins_result_no_loop.csv/vins_result_no_loop.csv ./

# Visualize with Python
python3 visualize_trajectory.py vins_result_no_loop.csv
```

## Next Steps

Once the bridge is working:
1. Record the bridged ROS2 topics for later playback
2. Analyze VIR-SLAM performance
3. Tune VIR-SLAM parameters based on visualization

For more help, see:
- Official ros1_bridge docs: https://github.com/ros2/ros1_bridge
- RViz2 user guide: https://docs.ros.org/en/humble/Tutorials/Intermediate/RViz/RViz-User-Guide/RViz-User-Guide.html
