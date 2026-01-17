# Quick Start: ROS1 to ROS2 Bridge for VIR-SLAM

## Setup (One-time): Build ros1_bridge from source

Since you're on Jetson ARM64 with Ubuntu 22.04, you need to build ros1_bridge from source.

**Time required**: 30-60 minutes  
**Disk space**: ~5GB

```bash
# Run the automated build script
cd /home/jetson/vir_slam_docker
./build_ros1_bridge.sh
```

This script will:
1. Install dependencies
2. Download and build ROS1 Noetic from source (~20-30 min)
3. Build ros1_bridge (~10-20 min)

## Usage (Every time):

### Terminal 1: Start VIR-SLAM in Docker
```bash
# Enter the container
docker exec -it vir_slam_dev bash

# Inside container - start roscore
source /opt/ros/noetic/setup.bash
roscore
```

### Terminal 2: Run VIR-SLAM or play bag
```bash
# Enter the container
docker exec -it vir_slam_dev bash

# Inside container
source /opt/ros/noetic/setup.bash
source /root/catkin_ws/devel/setup.bash

# Option A: Run VIR-SLAM with live sensors
roslaunch vir_estimator vir_spiri.launch config_type:=imx291_mid360

# Option B: Play recorded bag
rosbag play /host/temp_bags/virslam_complete_20260114_143124.bag --clock -r 0.5
```

### Terminal 3: Start the Bridge (on host)
```bash
# On your host machine (Ubuntu 22.04)
source ~/ros1_install/setup.bash
source /opt/ros/humble/setup.bash
source ~/ros1_bridge_ws/install/setup.bash

# Connect to ROS1 master in Docker
export ROS_MASTER_URI=http://localhost:11311

# Start the bridge
ros2 run ros1_bridge dynamic_bridge --bridge-all-topics
```

### Terminal 4: Check topics (on host)
```bash
# On your host machine
source /opt/ros/humble/setup.bash

# See ROS2 topics
ros2 topic list

# See specific topic data
ros2 topic echo /camera/image_raw
ros2 topic echo /vins_estimator/odometry
```

### Terminal 5: Visualize in RViz2 (on host)
```bash
# On your host machine
source /opt/ros/humble/setup.bash

# Launch RViz2
rviz2
```

In RViz2:
1. Set **Fixed Frame** to `world` or `camera_init`
2. Add displays:
   - **TF** - to see coordinate frames
   - **Odometry** → Topic: `/vins_estimator/odometry`
   - **Path** → Topic: `/vins_estimator/path`
   - **Image** → Topic: `/camera/image_raw` (if available)
   - **PointCloud2** → Topic: `/cloud_registered` (for LiDAR)

## Key Points:

✅ **ROS1 Noetic built from source on host** - installed to ~/ros1_install
✅ **Docker container provides ROS1 master** - bridge connects to it via network
✅ **Host uses ROS2 Humble** - for receiving bridged topics and visualization
✅ **Network is localhost** - Docker uses host network mode
✅ **One-time build** - takes 30-60 min but only needed once

## Troubleshooting:

**Bridge says "Waiting for ROS 1 nodes..."**
- Make sure roscore is running in Docker container
- Check: `export ROS_MASTER_URI=http://localhost:11311`

**No topics appearing in ROS2**
- Check if topics exist in ROS1: `docker exec vir_slam_dev bash -c "source /opt/ros/noetic/setup.bash && rostopic list"`
- The bridge only forwards topics that are actively published

**RViz2 shows "No tf data"**
- VIR-SLAM might not have initialized yet
- Make sure the bag is playing or sensors are publishing data
- Check if IMU has enough excitation (move the sensor!)
