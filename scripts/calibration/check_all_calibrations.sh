#!/usr/bin/env bash
# 全面的传感器标定检查和修复脚本

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}

echo "🔧 传感器标定全面检查"
echo "=================================="

# 1. 检查相机标定
echo "📷 1. 相机标定检查"
echo "当前USB相机参数检查..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; timeout 10s rostopic echo -n 1 /usb_cam/camera_info 2>/dev/null" || echo "❌ 相机info话题无数据"

echo ""
echo "📊 2. IMU数据质量检查" 
echo "检查IMU话题数据..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; timeout 5s rostopic echo -n 1 /livox/imu 2>/dev/null" || echo "❌ IMU话题无数据"

echo ""
echo "📡 3. UWB定位检查"
echo "检查UWB话题数据..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; timeout 5s rostopic echo -n 1 /uwb/pose 2>/dev/null" || echo "❌ UWB话题无数据"

echo ""
echo "🔍 4. 数据同步检查"
echo "检查时间戳同步..."

# 创建数据质量检查脚本
in_container "cat > /tmp/check_data_sync.py << 'EOF'
#!/usr/bin/env python3
import rospy
from sensor_msgs.msg import Image, Imu, CameraInfo
from geometry_msgs.msg import PoseStamped
import time

class DataSyncChecker:
    def __init__(self):
        self.last_image_time = None
        self.last_imu_time = None
        self.last_uwb_time = None
        self.image_count = 0
        self.imu_count = 0
        self.uwb_count = 0
        
        rospy.init_node('data_sync_checker')
        
        # 订阅话题
        rospy.Subscriber('/usb_cam/image_raw', Image, self.image_callback)
        rospy.Subscriber('/livox/imu', Imu, self.imu_callback)
        rospy.Subscriber('/uwb/pose', PoseStamped, self.uwb_callback)
        
        print(\"🔍 开始数据同步检查 (10秒)...\")
        
    def image_callback(self, msg):
        self.last_image_time = msg.header.stamp.to_sec()
        self.image_count += 1
        
    def imu_callback(self, msg):
        self.last_imu_time = msg.header.stamp.to_sec()
        self.imu_count += 1
        
    def uwb_callback(self, msg):
        self.last_uwb_time = msg.header.stamp.to_sec()
        self.uwb_count += 1
    
    def check_sync(self):
        rospy.sleep(10)  # 收集10秒数据
        
        print(f\"📊 数据统计:\")
        print(f\"  图像: {self.image_count} 帧\")
        print(f\"  IMU: {self.imu_count} 帧\") 
        print(f\"  UWB: {self.uwb_count} 帧\")
        
        if self.image_count < 50:
            print(\"❌ 图像频率过低! 应该 >5Hz\")
        if self.imu_count < 500:
            print(\"❌ IMU频率过低! 应该 >50Hz\")
        if self.uwb_count < 10:
            print(\"❌ UWB频率过低! 应该 >1Hz\")
            
        if all([self.last_image_time, self.last_imu_time, self.last_uwb_time]):
            sync_diff = abs(self.last_image_time - self.last_imu_time)
            print(f\"⏰ 图像-IMU时间差: {sync_diff:.3f}s\")
            if sync_diff > 0.1:
                print(\"❌ 时间同步问题！差异 >100ms\")
            else:
                print(\"✅ 时间同步正常\")

if __name__ == '__main__':
    checker = DataSyncChecker()
    checker.check_sync()
EOF"

echo "🔍 启动数据质量检查 (需要传感器运行)..."
if in_container "${ROS_SETUP}; ${CATKIN_SETUP}; rostopic list | grep -q usb_cam"; then
    echo "✅ 检测到相机话题，开始检查..."
    in_container "${ROS_SETUP}; ${CATKIN_SETUP}; python3 /tmp/check_data_sync.py" || echo "数据检查完成"
else
    echo "❌ 未检测到传感器数据，请先启动:"
    echo "   ./start_all_sensors.sh"
fi

echo ""
echo "🛠️  建议的标定流程："
echo "=================================="
echo "1. 📷 相机标定:"
echo "   rosrun camera_calibration cameracalibrator.py --size 8x6 --square 0.108 image:=/usb_cam/image_raw camera:=/usb_cam"
echo ""
echo "2. 📊 IMU标定:"
echo "   # 静态偏置标定 - 设备静放30秒"
echo "   ./calibrate_imu_static.sh"
echo ""
echo "3. 🔄 视觉-惯性外参标定:"
echo "   # 使用标定板做激励运动"
echo "   ./calibrate_vi_extrinsics.sh"
echo ""
echo "4. 📡 UWB基站位置验证:"
echo "   ./verify_uwb_anchors.sh"
echo ""
echo "5. 🎯 完整数据采集:"
echo "   ./record_virslam_bag.sh"
