#!/usr/bin/env bash
set -euo pipefail

# 带数据转换的VIR-SLAM同步录制脚本
# 包含图像灰度转换和UWB格式转换

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

# 输出目录
HOST_BASE="/home/jetson/vir_slam_output/bags"
mkdir -p "${HOST_BASE}"
BAG_ROOT_IN="/tmp/virslam_bags"

# 传感器话题 (转换后的话题)
SENSOR_TOPICS=(
  "/livox/lidar"
  "/camera/color/image_raw"      # 转换后的灰度图像
  "/uwb/corrected_range"         # 转换后的距离数据
  "/livox/imu"
  "/usb_cam/camera_info"
  "/synced/timestamp_info"
)

# 工具函数
die() { echo "❌ $*" 1>&2; exit 1; }
docker_running() {
  docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"
}
in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}
topic_exists() {
  in_container "${ROS_SETUP}; timeout 3 rostopic list | grep -qx '$1'" 2>/dev/null
}

echo "🎥 带转换的VIR-SLAM数据录制"
echo "=============================="

# 检查容器状态
docker_running || die "容器未运行，请先运行 ./start_container.sh"

# 1. 启动数据转换节点
echo "🔧 启动数据转换节点..."
./start_data_converters.sh

sleep 3

# 2. 创建时间同步节点
echo "⏰ 创建时间同步节点..."
in_container "cat > /tmp/enhanced_timestamp_sync_node.py << 'EOF'
#!/usr/bin/env python3
import rospy
from sensor_msgs.msg import Image, Imu, PointCloud2, CameraInfo
from geometry_msgs.msg import PointStamped
from std_msgs.msg import String
import json

class EnhancedTimestampSyncNode:
    def __init__(self):
        rospy.init_node('enhanced_timestamp_sync_node')
        
        # 同步发布器 - 发布转换后的数据
        self.publishers = {
            'lidar': rospy.Publisher('/synced/lidar', PointCloud2, queue_size=10),
            'image': rospy.Publisher('/synced/image_raw', Image, queue_size=10),
            'uwb': rospy.Publisher('/synced/uwb_range', PointStamped, queue_size=10),
            'imu': rospy.Publisher('/synced/imu', Imu, queue_size=50),
            'camera_info': rospy.Publisher('/synced/camera_info', CameraInfo, queue_size=10),
            'timestamp_info': rospy.Publisher('/synced/timestamp_info', String, queue_size=10)
        }
        
        # 订阅转换后的话题
        rospy.Subscriber('/livox/lidar', PointCloud2, self.sync_lidar)
        rospy.Subscriber('/camera/color/image_raw', Image, self.sync_image)  # 转换后的灰度图
        rospy.Subscriber('/uwb/corrected_range', PointStamped, self.sync_uwb)  # 转换后的距离数据
        rospy.Subscriber('/livox/imu', Imu, self.sync_imu)
        rospy.Subscriber('/usb_cam/camera_info', CameraInfo, self.sync_camera_info)
        
        self.msg_count = 0
        self.start_time = rospy.Time.now()
        
        rospy.loginfo('⏰ 增强时间同步节点已启动 (支持数据转换)')
        
    def get_sync_timestamp(self):
        return rospy.Time.now()
        
    def sync_lidar(self, msg):
        msg.header.stamp = self.get_sync_timestamp()
        self.publishers['lidar'].publish(msg)
        self.update_stats('LiDAR')
        
    def sync_image(self, msg):
        msg.header.stamp = self.get_sync_timestamp()
        self.publishers['image'].publish(msg)
        self.update_stats('Image(灰度)')
        
    def sync_uwb(self, msg):
        msg.header.stamp = self.get_sync_timestamp()
        self.publishers['uwb'].publish(msg)
        self.update_stats('UWB(距离)')
        
    def sync_imu(self, msg):
        msg.header.stamp = self.get_sync_timestamp()
        self.publishers['imu'].publish(msg)
        self.update_stats('IMU')
        
    def sync_camera_info(self, msg):
        msg.header.stamp = self.get_sync_timestamp()
        self.publishers['camera_info'].publish(msg)
        
    def update_stats(self, sensor_name):
        self.msg_count += 1
        if self.msg_count % 50 == 0:
            elapsed = (rospy.Time.now() - self.start_time).to_sec()
            rate = self.msg_count / elapsed if elapsed > 0 else 0
            
            # 发布时间戳信息
            info = {
                'sensor': sensor_name,
                'count': self.msg_count,
                'rate': rate,
                'timestamp': rospy.Time.now().to_sec()
            }
            info_msg = String()
            info_msg.data = json.dumps(info)
            self.publishers['timestamp_info'].publish(info_msg)
            
            rospy.loginfo(f'{sensor_name} 同步 #{self.msg_count}, 总速率: {rate:.1f} msg/s')

if __name__ == '__main__':
    try:
        node = EnhancedTimestampSyncNode()
        rospy.spin()
    except rospy.ROSInterruptException:
        pass
EOF"

# 3. 启动增强同步节点
echo "🚀 启动增强时间同步节点..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; nohup python3 /tmp/enhanced_timestamp_sync_node.py > /tmp/enhanced_sync_node.log 2>&1 &"
sleep 3

# 4. 检查所有必需话题
echo "🔍 检查转换后的传感器话题..."
missing_topics=()
for topic in "${SENSOR_TOPICS[@]}"; do
  if topic_exists "${topic}"; then
    echo "✅ ${topic}"
  else
    echo "❌ ${topic} (缺失)"
    missing_topics+=("${topic}")
  fi
done

if [ ${#missing_topics[@]} -ne 0 ]; then
    echo "⚠️ 缺少话题: ${missing_topics[*]}"
    echo "请检查传感器和转换节点状态"
    echo "继续录制可用的话题..."
fi

# 5. 开始录制
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BAG_NAME="virslam_converted_${TIMESTAMP}.bag"
BAG_PATH_HOST="${HOST_BASE}/${BAG_NAME}"
BAG_PATH_CONTAINER="${BAG_ROOT_IN}/${BAG_NAME}"

echo ""
echo "📹 开始录制转换后的VIR-SLAM数据..."
echo "   文件: ${BAG_NAME}"
echo "   包含: 灰度图像 + UWB距离 + 时间同步"
echo "   按 Ctrl+C 停止录制"
echo ""

# 在容器内创建录制目录并开始录制
in_container "mkdir -p ${BAG_ROOT_IN}"

# 使用synced话题进行录制 (已经过转换和时间同步)
RECORD_TOPICS="/synced/lidar /synced/image_raw /synced/uwb_range /synced/imu /synced/camera_info /synced/timestamp_info"

in_container "${ROS_SETUP}; ${CATKIN_SETUP}; rosbag record -O ${BAG_PATH_CONTAINER} ${RECORD_TOPICS}" &
RECORD_PID=$!

# 等待用户停止
wait $RECORD_PID

# 6. 复制bag文件到主机
echo ""
echo "📋 处理录制文件..."
if docker cp "${CONTAINER}:${BAG_PATH_CONTAINER}" "${BAG_PATH_HOST}"; then
    BAG_SIZE=$(du -h "${BAG_PATH_HOST}" | cut -f1)
    echo "✅ 录制完成: ${BAG_PATH_HOST} (${BAG_SIZE})"
    
    # 验证bag文件内容
    echo ""
    echo "🔍 验证转换后的bag文件内容:"
    in_container "${ROS_SETUP}; rosbag info ${BAG_PATH_CONTAINER}" | grep -E "(topics|messages|duration)"
    
    # 清理容器内文件
    in_container "rm -f ${BAG_PATH_CONTAINER}"
    echo ""
    echo "🎯 可以直接使用此bag文件进行VIR-SLAM处理:"
    echo "   ./process_virslam_bag.sh '${BAG_PATH_HOST}'"
else
    echo "❌ 文件复制失败"
    exit 1
fi
