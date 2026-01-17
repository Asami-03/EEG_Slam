#!/usr/bin/env bash
# 时间戳同步检查和修复脚本

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}

echo "⏰ 多传感器时间戳同步检查"
echo "=================================="

# 创建时间戳同步检查脚本
in_container "cat > /tmp/timestamp_sync_checker.py << 'EOF'
#!/usr/bin/env python3
import rospy
from sensor_msgs.msg import Image, Imu, PointCloud2
from geometry_msgs.msg import PoseStamped
import time
from collections import deque

class TimestampSyncChecker:
    def __init__(self):
        rospy.init_node('timestamp_checker')
        
        self.image_times = deque(maxlen=100)
        self.imu_times = deque(maxlen=1000) 
        self.lidar_times = deque(maxlen=100)
        self.uwb_times = deque(maxlen=100)
        
        self.image_count = 0
        self.imu_count = 0
        self.lidar_count = 0
        self.uwb_count = 0
        
        # 系统时间基准
        self.start_time = time.time()
        self.start_ros_time = rospy.Time.now().to_sec()
        
        print(\"⏰ 开始时间戳同步检查...\")
        print(f\"系统时间基准: {self.start_time}\")
        print(f\"ROS时间基准: {self.start_ros_time}\")
        print(\"-\" * 50)
        
        # 订阅所有传感器话题
        rospy.Subscriber('/usb_cam/image_raw', Image, self.image_callback)
        rospy.Subscriber('/livox/imu', Imu, self.imu_callback)
        rospy.Subscriber('/livox/lidar', PointCloud2, self.lidar_callback)
        rospy.Subscriber('/uwb/pose', PoseStamped, self.uwb_callback)
        
    def image_callback(self, msg):
        current_time = rospy.Time.now().to_sec()
        msg_time = msg.header.stamp.to_sec()
        self.image_times.append((current_time, msg_time))
        self.image_count += 1
        
        if self.image_count % 10 == 0:
            delay = current_time - msg_time
            print(f\"📷 图像 #{self.image_count}: 时间戳延迟 {delay:.3f}s\")
        
    def imu_callback(self, msg):
        current_time = rospy.Time.now().to_sec()
        msg_time = msg.header.stamp.to_sec()
        self.imu_times.append((current_time, msg_time))
        self.imu_count += 1
        
        if self.imu_count % 100 == 0:
            delay = current_time - msg_time
            print(f\"📊 IMU #{self.imu_count}: 时间戳延迟 {delay:.3f}s\")
        
    def lidar_callback(self, msg):
        current_time = rospy.Time.now().to_sec()
        msg_time = msg.header.stamp.to_sec()
        self.lidar_times.append((current_time, msg_time))
        self.lidar_count += 1
        
        delay = current_time - msg_time
        print(f\"🔶 激光 #{self.lidar_count}: 时间戳延迟 {delay:.3f}s\")
        
    def uwb_callback(self, msg):
        current_time = rospy.Time.now().to_sec()
        msg_time = msg.header.stamp.to_sec()
        self.uwb_times.append((current_time, msg_time))
        self.uwb_count += 1
        
        delay = current_time - msg_time
        print(f\"📡 UWB #{self.uwb_count}: 时间戳延迟 {delay:.3f}s\")
    
    def analyze_sync(self):
        rospy.sleep(15)  # 收集15秒数据
        
        print(\"\\n\" + \"=\" * 50)
        print(\"📊 时间戳同步分析结果\")
        print(\"=\" * 50)
        
        print(f\"数据统计:\")
        print(f\"  📷 图像: {self.image_count} 帧 ({self.image_count/15:.1f} Hz)\")
        print(f\"  📊 IMU: {self.imu_count} 帧 ({self.imu_count/15:.1f} Hz)\")
        print(f\"  🔶 激光: {self.lidar_count} 帧 ({self.lidar_count/15:.1f} Hz)\")
        print(f\"  📡 UWB: {self.uwb_count} 帧 ({self.uwb_count/15:.1f} Hz)\")
        
        # 分析时间戳延迟
        if self.image_times:
            img_delays = [ct - mt for ct, mt in self.image_times]
            avg_img_delay = sum(img_delays) / len(img_delays)
            print(f\"\\n📷 图像平均延迟: {avg_img_delay:.3f}s (std: {(sum([(d-avg_img_delay)**2 for d in img_delays])/len(img_delays))**0.5:.3f})\")
            
        if self.imu_times:
            imu_delays = [ct - mt for ct, mt in self.imu_times]
            avg_imu_delay = sum(imu_delays) / len(imu_delays)
            print(f\"📊 IMU平均延迟: {avg_imu_delay:.3f}s (std: {(sum([(d-avg_imu_delay)**2 for d in imu_delays])/len(imu_delays))**0.5:.3f})\")
            
        if self.lidar_times:
            lidar_delays = [ct - mt for ct, mt in self.lidar_times]
            avg_lidar_delay = sum(lidar_delays) / len(lidar_delays)
            print(f\"🔶 激光平均延迟: {avg_lidar_delay:.3f}s (std: {(sum([(d-avg_lidar_delay)**2 for d in lidar_delays])/len(lidar_delays))**0.5:.3f})\")
            
        if self.uwb_times:
            uwb_delays = [ct - mt for ct, mt in self.uwb_times]
            avg_uwb_delay = sum(uwb_delays) / len(uwb_delays)
            print(f\"📡 UWB平均延迟: {avg_uwb_delay:.3f}s (std: {(sum([(d-avg_uwb_delay)**2 for d in uwb_delays])/len(uwb_delays))**0.5:.3f})\")
        
        # 检查相对同步
        print(\"\\n🔄 相对时间同步检查:\")
        if self.image_times and self.imu_times:
            img_time = self.image_times[-1][1]
            imu_time = self.imu_times[-1][1] 
            sync_diff = abs(img_time - imu_time)
            print(f\"  📷↔️📊 图像-IMU: {sync_diff:.3f}s {'✅' if sync_diff < 0.05 else '❌'}\")
            
        if self.image_times and self.lidar_times:
            img_time = self.image_times[-1][1]
            lidar_time = self.lidar_times[-1][1]
            sync_diff = abs(img_time - lidar_time)
            print(f\"  📷↔️🔶 图像-激光: {sync_diff:.3f}s {'✅' if sync_diff < 0.1 else '❌'}\")
            
        if self.image_times and self.uwb_times:
            img_time = self.image_times[-1][1]
            uwb_time = self.uwb_times[-1][1]
            sync_diff = abs(img_time - uwb_time)
            print(f\"  📷↔️📡 图像-UWB: {sync_diff:.3f}s {'✅' if sync_diff < 0.2 else '❌'}\")
        
        # 给出建议
        print(\"\\n💡 同步建议:\")
        if all(self.image_count > 0, self.imu_count > 0):
            if abs(avg_img_delay - avg_imu_delay) > 0.05:
                print(\"  ⚠️  图像和IMU时间戳基准不一致，需要校正\")
            else:
                print(\"  ✅ 图像和IMU时间戳基准一致\")
                
        if self.image_count/15 < 5:
            print(\"  ⚠️  图像频率过低，建议 >10Hz\")
        if self.imu_count/15 < 50:
            print(\"  ⚠️  IMU频率过低，建议 >100Hz\")

if __name__ == '__main__':
    try:
        checker = TimestampSyncChecker()
        checker.analyze_sync()
    except rospy.ROSInterruptException:
        pass
EOF"

echo "🚀 启动时间戳检查 (需要传感器运行)..."
echo "检查时长: 15秒"

if in_container "${ROS_SETUP}; rostopic list | grep -q usb_cam"; then
    echo "✅ 检测到传感器数据，开始分析..."
    in_container "${ROS_SETUP}; ${CATKIN_SETUP}; python3 /tmp/timestamp_sync_checker.py"
else
    echo "❌ 未检测到传感器数据"
    echo "请先启动传感器: ./start_all_sensors.sh"
    echo "然后重新运行此脚本"
fi

echo ""
echo "🛠️ 时间戳同步修复建议:"
echo "1. 使用统一时间源 (如 chrony 或 ntpd)"
echo "2. 启用 use_sim_time 进行bag播放"
echo "3. 在录制时使用 --clock 参数"
echo "4. 检查传感器驱动的时间戳设置"
