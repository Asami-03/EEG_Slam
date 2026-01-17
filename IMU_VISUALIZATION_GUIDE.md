# IMU数据可视化指南

## 功能说明
将bag文件中的IMU数据转换为Pose消息，可以在RViz中可视化IMU的姿态和轨迹。

## 使用步骤

### 步骤1: 启动 roscore
```bash
# 终端1
docker exec -it vir_slam_dev bash -c "source /opt/ros/noetic/setup.bash && roscore"
```

### 步骤2: 播放bag文件
```bash
# 终端2
docker exec -it vir_slam_dev bash -c "source /opt/ros/noetic/setup.bash && rosbag play /host/temp_bags/virslam_complete_20260114_143124.bag --clock -r 0.5"
```

### 步骤3: 启动IMU转Pose转换器
```bash
# 终端3
cd /home/jetson/vir_slam_docker
./run_imu_converter.sh
```

### 步骤4: 启动RViz可视化（在宿主机上）
```bash
# 终端4（在宿主机，不在Docker内）
source /opt/ros/humble/setup.bash  # 如果你有ROS2
# 或
source /opt/ros/noetic/setup.bash  # 如果你有ROS1

rviz
```

## RViz配置

在RViz中添加以下显示项：

1. **Fixed Frame**: 设置为 `world`

2. **Axes** - 显示坐标轴
   - Size: 1.0

3. **PoseStamped** - 显示当前IMU姿态
   - Topic: `/imu_pose`
   - Shape: Arrow
   - Color: Red
   - Alpha: 1.0
   - Shaft Length: 0.5
   - Head Length: 0.3

4. **Path** - 显示IMU轨迹
   - Topic: `/imu_path`
   - Color: Green
   - Alpha: 1.0
   - Line Width: 0.01

## 发布的话题

转换器会发布以下话题：

- `/imu_pose` (geometry_msgs/PoseStamped)
  - 实时IMU姿态（位置+方向）
  
- `/imu_path` (nav_msgs/Path)
  - IMU轨迹路径（最多保留1000个点）

## 订阅的话题

- `/synced/imu` (sensor_msgs/Imu)
  - 从bag文件中读取IMU数据

## 注意事项

1. **位置估计精度**: 脚本使用简单的双重积分来估计位置，会有累积误差
   - 仅用于可视化参考
   - 实际精确定位应该使用VIR-SLAM的输出

2. **时间同步**: 确保使用 `--clock` 参数播放bag文件

3. **播放速度**: 建议使用 `-r 0.5` 或 `-r 1.0` 的播放速度

## 快速启动（一键脚本）

创建一个一键启动所有服务的脚本：

```bash
# 使用tmux或多个终端窗口
./start_imu_visualization.sh
```

## 故障排除

### 问题1: 没有数据显示
- 检查roscore是否运行
- 检查bag文件是否正在播放
- 使用 `rostopic echo /synced/imu` 确认IMU数据正在发布

### 问题2: RViz中看不到轨迹
- 确认Fixed Frame设置为 `world`
- 检查话题名称是否正确
- 使用 `rostopic list` 查看可用话题

### 问题3: 轨迹漂移严重
- 这是正常的，因为使用了简单的积分方法
- 如需精确轨迹，请使用VIR-SLAM的输出: `/vins_estimator/odometry`
