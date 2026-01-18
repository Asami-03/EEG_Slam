#!/usr/bin/env bash
# VIR-SLAM 传感器和转换系统启动脚本（持续运行版本）
# 确保所有组件启动并持续监控状态

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

# 相机设备（自动检测）
CAMERA_DEVICE=""

# 工具函数
die() { echo "❌ $*" 1>&2; exit 1; }

# 自动检测USB相机设备
auto_detect_camera() {
  echo "🔍 自动检测USB相机..."

  # 方法1：通过 v4l2-ctl 查找 UVC 相机
  if command -v v4l2-ctl &>/dev/null; then
    for dev in /dev/video*; do
      [[ -e "$dev" ]] || continue
      local driver=$(v4l2-ctl -d "$dev" --info 2>/dev/null | grep "Driver name" | awk '{print $NF}')
      if [[ "$driver" == "uvcvideo" ]]; then
        if v4l2-ctl -d "$dev" --list-formats-ext 2>/dev/null | grep -q "Video Capture"; then
          CAMERA_DEVICE="$dev"
          local card=$(v4l2-ctl -d "$dev" --info 2>/dev/null | grep "Card type" | cut -d: -f2-)
          echo "  ✅ 检测到UVC相机: $dev (${card})"
          return 0
        fi
      fi
    done
  fi

  # 方法2：回退查找
  for dev in /dev/video0 /dev/video1 /dev/video2 /dev/video4 /dev/video6 /dev/video8; do
    if [[ -e "$dev" ]] && v4l2-ctl -d "$dev" --info &>/dev/null; then
      CAMERA_DEVICE="$dev"
      echo "  ⚠️ 使用回退设备: $dev"
      return 0
    fi
  done

  echo "  ❌ 未检测到相机"
  return 1
}
docker_running() {
  docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"
}
in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}

# 安全的话题等待函数
wait_for_topic_safe() {
  local topic="$1"
  local timeout="${2:-30}"
  local max_retries=3
  
  echo "   🔍 等待话题: $topic"
  
  for retry in $(seq 1 $max_retries); do
    echo "   尝试 $retry/$max_retries..."
    
    for i in $(seq 1 $timeout); do
      if in_container "${ROS_SETUP}; timeout 5 rostopic list 2>/dev/null | grep -qx '$topic'" 2>/dev/null; then
        echo "   ✅ $topic 已就绪"
        return 0
      fi
      sleep 1
      if [ $((i % 10)) -eq 0 ]; then
        echo -n " ${i}s"
      else
        echo -n "."
      fi
    done
    
    echo ""
    if [ $retry -lt $max_retries ]; then
      echo "   ⚠️ $topic 未就绪，重试中..."
      sleep 5
    fi
  done
  
  echo "   ⚠️ $topic 超时未就绪，但继续执行..."
  return 1
}

echo "🚀 VIR-SLAM 传感器+转换系统启动 (持续运行版本)"
echo "=================================================="

# 1. 检查容器状态
echo "🔍 检查Docker容器状态..."
if docker_running; then
    echo "✅ 容器运行中"
else
    die "容器未运行，请先执行: ./start_container.sh"
fi

# 2. 清理旧进程（温和模式）
echo ""
echo "🧹 清理可能的冲突进程..."
in_container "pkill -f 'livox_ros_driver2|usb_cam|nooploop|converter|sync' 2>/dev/null || echo '  无冲突进程'"
sleep 3

# 2.5 确保 Livox SDK 库可用（容器重建后需要重新安装）
echo ""
echo "🔧 检查 Livox SDK..."
if ! in_container "ldconfig -p | grep -q livox_lidar_sdk"; then
    echo "   安装 Livox SDK..."
    in_container "cd /root/catkin_ws/src/Livox-SDK2/build && make install > /dev/null 2>&1 && ldconfig"
    echo "   ✅ Livox SDK 已安装"
else
    echo "   ✅ Livox SDK 已就绪"
fi

# 2.6 确保 usb_cam 已安装（容器重建后需要重新安装）
echo ""
echo "🔧 检查 usb_cam..."
if ! in_container "dpkg -l | grep -q ros-noetic-usb-cam"; then
    echo "   安装 usb_cam..."
    in_container "apt-get update > /dev/null 2>&1 && apt-get install -y ros-noetic-usb-cam > /dev/null 2>&1"
    echo "   ✅ usb_cam 已安装"
else
    echo "   ✅ usb_cam 已就绪"
fi

# 3. 启动roscore
echo ""
echo "🏁 确保ROS核心运行..."
if in_container "${ROS_SETUP}; pgrep roscore >/dev/null 2>&1"; then
    echo "✅ roscore已在运行"
else
    echo "🚀 启动roscore..."
    in_container "${ROS_SETUP}; nohup roscore > /tmp/roscore.log 2>&1 &"
    sleep 5
    
    if in_container "${ROS_SETUP}; pgrep roscore >/dev/null 2>&1"; then
        echo "✅ roscore启动成功"
    else
        echo "❌ roscore启动失败，查看日志:"
        in_container "cat /tmp/roscore.log 2>/dev/null || echo 'No log file'"
        exit 1
    fi
fi

# 4. 自动检测相机设备
echo ""
if ! auto_detect_camera; then
    die "未检测到USB相机，请检查连接"
fi

# 5. 使用成功的传感器启动方法
echo ""
echo "📡 启动传感器系统 (使用验证过的方法)..."

# 5.1 直接调用工作的传感器启动脚本
echo "🎯 启动所有传感器..."

# Livox MID360
echo "   启动Livox MID360..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup roslaunch livox_ros_driver2 msg_MID360.launch > /tmp/livox.log 2>&1 &"
sleep 10

# IMX291相机 (640x480 @ 60fps)
echo "   启动IMX291相机 (${CAMERA_DEVICE}, 640x480@60fps)..."
in_container "${ROS_SETUP}; nohup rosrun usb_cam usb_cam_node _video_device:=${CAMERA_DEVICE} _image_width:=640 _image_height:=480 _pixel_format:=yuyv _camera_frame_id:=usb_cam _io_method:=mmap _framerate:=60 > /tmp/camera.log 2>&1 &"
sleep 5

# UWB系统 (使用原来成功的方法)
echo "   启动UWB系统..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup roslaunch nlink_parser linktrack.launch > /tmp/nlink.log 2>&1 &"
sleep 5
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup rosrun nooploop_uwb nodeframe2_converter.py > /tmp/uwb_converter.log 2>&1 &"
sleep 5

# 5. 检查传感器话题（非阻塞）
echo ""
echo "🔍 检查传感器话题状态..."
wait_for_topic_safe "/livox/lidar" 20
wait_for_topic_safe "/livox/imu" 15  
wait_for_topic_safe "/usb_cam/image_raw" 15
wait_for_topic_safe "/uwb/pose" 20

# 6. 部署和启动转换器
echo ""
echo "🔧 部署数据转换器..."
docker cp catkin_ws_src/image_color_to_gray_converter.py "${CONTAINER}:/root/catkin_ws/src/" 2>/dev/null || echo "   图像转换器已存在"
docker cp catkin_ws_src/uwb_pose_to_range_converter.py "${CONTAINER}:/root/catkin_ws/src/" 2>/dev/null || echo "   UWB转换器已存在"

in_container "chmod +x /root/catkin_ws/src/image_color_to_gray_converter.py" 2>/dev/null || true
in_container "chmod +x /root/catkin_ws/src/uwb_pose_to_range_converter.py" 2>/dev/null || true

echo ""
echo "🎨 启动图像转换器..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup python3 /root/catkin_ws/src/image_color_to_gray_converter.py _input_topic:=/usb_cam/image_raw _output_topic:=/camera/color/image_raw _enable_clahe:=true _clahe_limit:=2.0 > /tmp/image_converter.log 2>&1 &"

echo "📡 启动UWB转换器..."  
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup python3 /root/catkin_ws/src/uwb_pose_to_range_converter.py _input_topic:=/uwb/pose _output_topic:=/uwb/corrected_range _conversion_mode:=magnitude _enable_filter:=true _filter_alpha:=0.8 _max_range_jump:=2.0 > /tmp/uwb_converter.log 2>&1 &"

sleep 5

# 7. 启动时间同步系统
echo ""  
echo "⏰ 启动统一时间同步系统..."
in_container "cat > /tmp/unified_timestamp_sync.py << 'EOF'
#!/usr/bin/env python3
import rospy
from sensor_msgs.msg import Image, Imu, PointCloud2, CameraInfo
from geometry_msgs.msg import PointStamped
from std_msgs.msg import String
import threading
import json
from collections import deque

class UnifiedTimestampSync:
    def __init__(self):
        rospy.init_node('unified_timestamp_sync')
        
        # 同步发布器
        self.sync_publishers = {
            'lidar': rospy.Publisher('/synced/lidar', PointCloud2, queue_size=10),
            'image': rospy.Publisher('/synced/image_raw', Image, queue_size=10),
            'uwb': rospy.Publisher('/synced/uwb_range', PointStamped, queue_size=10),
            'imu': rospy.Publisher('/synced/imu', Imu, queue_size=50),
            'camera_info': rospy.Publisher('/synced/camera_info', CameraInfo, queue_size=10),
            'status': rospy.Publisher('/synced/status', String, queue_size=10)
        }
        
        # 订阅传感器话题
        rospy.Subscriber('/livox/lidar', PointCloud2, self.sync_lidar)
        rospy.Subscriber('/camera/color/image_raw', Image, self.sync_image)
        rospy.Subscriber('/uwb/corrected_range', PointStamped, self.sync_uwb)
        rospy.Subscriber('/livox/imu', Imu, self.sync_imu)
        rospy.Subscriber('/usb_cam/camera_info', CameraInfo, self.sync_camera_info)
        
        # 统计信息
        self.stats = {'lidar': 0, 'image': 0, 'uwb': 0, 'imu': 0, 'camera_info': 0}
        self.start_time = rospy.Time.now()
        
        rospy.loginfo('🔄 统一时间同步节点已启动')
        
    def get_unified_timestamp(self):
        return rospy.Time.now()
        
    def sync_lidar(self, msg):
        msg.header.stamp = self.get_unified_timestamp()
        self.sync_publishers['lidar'].publish(msg)
        self.stats['lidar'] += 1
        
    def sync_image(self, msg):
        msg.header.stamp = self.get_unified_timestamp()
        self.sync_publishers['image'].publish(msg)
        self.stats['image'] += 1
        
    def sync_uwb(self, msg):
        msg.header.stamp = self.get_unified_timestamp()
        self.sync_publishers['uwb'].publish(msg)
        self.stats['uwb'] += 1
        
    def sync_imu(self, msg):
        msg.header.stamp = self.get_unified_timestamp()
        # 将加速度从 g 转换为 m/s² (Livox MID360 输出单位是 g)
        G = 9.805
        msg.linear_acceleration.x *= G
        msg.linear_acceleration.y *= G
        msg.linear_acceleration.z *= G
        self.sync_publishers['imu'].publish(msg)
        self.stats['imu'] += 1
        
    def sync_camera_info(self, msg):
        msg.header.stamp = self.get_unified_timestamp()
        self.sync_publishers['camera_info'].publish(msg)
        self.stats['camera_info'] += 1

if __name__ == '__main__':
    try:
        sync_node = UnifiedTimestampSync()
        rospy.spin()
    except rospy.ROSInterruptException:
        pass
EOF"

in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup python3 /tmp/unified_timestamp_sync.py > /tmp/unified_sync.log 2>&1 &"

# 8. 等待系统稳定
echo ""
echo "⏰ 等待系统稳定 (15秒)..."
sleep 15

# 9. 检查同步话题（非阻塞）
echo ""
echo "🔍 检查同步话题状态..."
wait_for_topic_safe "/synced/lidar" 10
wait_for_topic_safe "/synced/image_raw" 10
wait_for_topic_safe "/synced/uwb_range" 10
wait_for_topic_safe "/synced/imu" 10

# 9.5 启动实时图像显示
echo ""
echo "📺 启动实时图像显示..."
in_container "${ROS_SETUP}; export DISPLAY=:0; nohup rqt_image_view /synced/image_raw > /tmp/image_view.log 2>&1 &"
sleep 2
echo "  ✅ 图像查看器已启动 (显示 /synced/image_raw)"

# 10. 显示系统状态
echo ""
echo "📊 系统状态总览..."
echo "===================================="

echo "🔧 运行中的进程:"
in_container "${ROS_SETUP}; rosnode list 2>/dev/null | grep -E '(livox|usb_cam|nlink|nooploop|converter|sync)' | head -10 || echo '  查询进程列表失败'"

echo ""
echo "📋 可用话题:"
in_container "${ROS_SETUP}; rostopic list 2>/dev/null | grep -E '(livox|usb_cam|uwb|synced)' | head -15 || echo '  查询话题列表失败'"

echo ""
echo "📄 日志文件:"
echo "  Livox: docker exec ${CONTAINER} tail -3 /tmp/livox.log"
echo "  Camera: docker exec ${CONTAINER} tail -3 /tmp/camera.log" 
echo "  UWB: docker exec ${CONTAINER} tail -3 /tmp/nlink.log"
echo "  转换器: docker exec ${CONTAINER} tail -3 /tmp/image_converter.log"
echo "  同步: docker exec ${CONTAINER} tail -3 /tmp/unified_sync.log"
echo "  图像查看: docker exec ${CONTAINER} tail -3 /tmp/image_view.log"

# 11. 持续监控模式
echo ""
echo "🔄 进入持续监控模式..."
echo "===================================="
echo "系统已启动，按 Ctrl+C 退出监控"
echo ""

# 监控循环
trap 'echo ""; echo "🛑 用户中断，退出监控模式"; exit 0' INT

while true; do
    sleep 30
    
    # 检查关键进程
    echo "$(date '+%H:%M:%S') - 系统状态检查:"
    
    # 检查roscore
    if in_container "${ROS_SETUP}; pgrep roscore >/dev/null 2>&1"; then
        echo "  ✅ roscore运行中"
    else
        echo "  ❌ roscore已停止"
    fi
    
    # 检查同步话题数量
    synced_topics=$(in_container "${ROS_SETUP}; rostopic list 2>/dev/null | grep '^/synced/' | wc -l" 2>/dev/null || echo "0")
    echo "  📊 同步话题数量: $synced_topics"
    
    # 检查节点数量
    node_count=$(in_container "${ROS_SETUP}; rosnode list 2>/dev/null | wc -l" 2>/dev/null || echo "0")
    echo "  🔧 运行节点数量: $node_count"
    
    echo ""
done
