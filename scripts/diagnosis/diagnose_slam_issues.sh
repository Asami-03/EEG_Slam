#!/usr/bin/env bash
# 完整的VIR-SLAM数据质量检查和修复脚本

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}

echo "🔍 VIR-SLAM数据质量全面检查"
echo "===================================="

# 1. 检查时间戳对齐
echo "1. ⏰ 时间戳同步检查"
echo "--------------------"

in_container "cat > /tmp/quick_timestamp_check.py << 'EOF'
#!/usr/bin/env python3
import rospy
from sensor_msgs.msg import Image, Imu
from geometry_msgs.msg import PoseStamped
import time

class QuickTimestampCheck:
    def __init__(self):
        rospy.init_node('quick_timestamp_check')
        self.latest_times = {}
        
        # 订阅关键话题
        rospy.Subscriber('/usb_cam/image_raw', Image, lambda msg: self.record_time('image', msg.header.stamp.to_sec()))
        rospy.Subscriber('/livox/imu', Imu, lambda msg: self.record_time('imu', msg.header.stamp.to_sec()))
        rospy.Subscriber('/uwb/pose', PoseStamped, lambda msg: self.record_time('uwb', msg.header.stamp.to_sec()))
        
    def record_time(self, sensor, timestamp):
        self.latest_times[sensor] = timestamp
        
    def check_sync(self):
        rospy.sleep(5)  # 收集5秒数据
        
        current_ros_time = rospy.Time.now().to_sec()
        print(f\"当前ROS时间: {current_ros_time:.3f}\")
        
        for sensor, timestamp in self.latest_times.items():
            delay = current_ros_time - timestamp
            status = \"✅\" if delay < 0.1 else \"❌\"
            print(f\"{status} {sensor}: {timestamp:.3f} (延迟: {delay:.3f}s)\")
        
        # 检查传感器间同步
        if len(self.latest_times) >= 2:
            times = list(self.latest_times.values())
            max_diff = max(times) - min(times)
            sync_status = \"✅\" if max_diff < 0.1 else \"❌\"
            print(f\"{sync_status} 传感器间最大时差: {max_diff:.3f}s\")

if __name__ == '__main__':
    checker = QuickTimestampCheck()
    checker.check_sync()
EOF"

if in_container "${ROS_SETUP}; rostopic list | grep -q usb_cam"; then
    in_container "${ROS_SETUP}; python3 /tmp/quick_timestamp_check.py"
else
    echo "❌ 传感器未启动，跳过时间戳检查"
fi

echo ""
echo "2. 📷 相机标定检查"
echo "--------------------"

# 检查相机内参
in_container "cat > /tmp/check_camera_params.py << 'EOF'
#!/usr/bin/env python3
import rospy
from sensor_msgs.msg import CameraInfo, Image
import cv2
from cv_bridge import CvBridge
import numpy as np

class CameraParamChecker:
    def __init__(self):
        rospy.init_node('camera_param_checker')
        self.bridge = CvBridge()
        self.got_info = False
        self.got_image = False
        
        rospy.Subscriber('/usb_cam/camera_info', CameraInfo, self.info_callback)
        rospy.Subscriber('/usb_cam/image_raw', Image, self.image_callback)
        
    def info_callback(self, msg):
        if not self.got_info:
            self.got_info = True
            print(f\"📷 相机分辨率: {msg.width}x{msg.height}\")
            print(f\"📊 内参矩阵:\")
            K = np.array(msg.K).reshape(3,3)
            print(f\"   fx: {K[0,0]:.1f}, fy: {K[1,1]:.1f}\")
            print(f\"   cx: {K[0,2]:.1f}, cy: {K[1,2]:.1f}\")
            print(f\"🔧 畸变系数: {msg.D[:4]}\")
            
            # 判断是否已标定
            if abs(K[0,0] - K[1,1]) < 1 and K[0,0] > 100:
                print(\"✅ 相机已标定\")
            else:
                print(\"❌ 相机未标定或参数异常\")
    
    def image_callback(self, msg):
        if not self.got_image:
            self.got_image = True
            try:
                cv_image = self.bridge.imgmsg_to_cv2(msg, \"bgr8\")
                
                # 图像质量检查
                gray = cv2.cvtColor(cv_image, cv2.COLOR_BGR2GRAY)
                
                # 亮度检查
                mean_brightness = np.mean(gray)
                print(f\"💡 平均亮度: {mean_brightness:.1f} (理想: 80-180)\")
                
                # 对比度检查  
                contrast = np.std(gray)
                print(f\"🎨 对比度: {contrast:.1f} (理想: >30)\")
                
                # 清晰度检查 (Laplacian方差)
                laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
                print(f\"🔍 清晰度: {laplacian_var:.1f} (理想: >100)\")
                
                # 特征点检查
                sift = cv2.SIFT_create()
                keypoints = sift.detect(gray, None)
                print(f\"🎯 特征点数量: {len(keypoints)}\")
                
                # 综合评估
                print(f\"\\n📋 图像质量评估:\")
                if mean_brightness < 50 or mean_brightness > 200:
                    print(\"❌ 亮度异常 (过暗或过亮)\")
                elif 80 <= mean_brightness <= 180:
                    print(\"✅ 亮度正常\")
                else:
                    print(\"⚠️ 亮度偏离理想范围\")
                    
                if contrast < 20:
                    print(\"❌ 对比度过低\")
                elif contrast >= 30:
                    print(\"✅ 对比度良好\")
                else:
                    print(\"⚠️ 对比度偏低\")
                    
                if laplacian_var < 50:
                    print(\"❌ 图像模糊\")
                elif laplacian_var >= 100:
                    print(\"✅ 图像清晰\")
                else:
                    print(\"⚠️ 图像轻微模糊\")
                    
                if len(keypoints) < 50:
                    print(\"❌ 特征点过少\")
                elif len(keypoints) >= 100:
                    print(\"✅ 特征点丰富\")
                else:
                    print(\"⚠️ 特征点偏少\")
                    
            except Exception as e:
                print(f\"❌ 图像处理错误: {e}\")

if __name__ == '__main__':
    checker = CameraParamChecker()
    rospy.sleep(3)
    if not (checker.got_info and checker.got_image):
        print(\"❌ 未能获取相机数据\")
EOF"

if in_container "${ROS_SETUP}; rostopic list | grep -q usb_cam"; then
    in_container "${ROS_SETUP}; python3 /tmp/check_camera_params.py"
else
    echo "❌ 相机话题不可用"
fi

echo ""
echo "3. 🎯 VIR-SLAM兼容性检查"  
echo "--------------------"

echo "📋 当前VIR-SLAM配置:"
in_container "cat /root/catkin_ws/src/VIR-SLAM/src/VIR_VINS/config/realsense/realsense_spiri.yaml | grep -E 'imu_topic|image_topic|fx|fy|cx|cy|k1|k2'"

echo ""
echo "🛠️ 修复建议:"
echo "============"
echo "1. ⏰ 时间戳同步:"
echo "   - 使用: ./record_synced_virslam_bag.sh"
echo ""
echo "2. 📷 相机标定:"
echo "   - 执行: ./calibrate_camera.sh"
echo "   - 或手动: rosrun camera_calibration cameracalibrator.py --size 8x6 --square 0.108 image:=/usb_cam/image_raw camera:=/usb_cam"
echo ""
echo "3. 📸 图像质量优化:"
echo "   - 调整曝光: v4l2-ctl -d /dev/video0 -c exposure_auto=1,exposure_absolute=300"
echo "   - 调整亮度: v4l2-ctl -d /dev/video0 -c brightness=150"
echo "   - 调整对比度: v4l2-ctl -d /dev/video0 -c contrast=150"
echo ""
echo "4. 🎯 建议的完整流程:"
echo "   a) ./fix_camera_settings.sh     # 优化相机设置"
echo "   b) ./calibrate_camera.sh        # 相机标定"
echo "   c) ./record_synced_virslam_bag.sh  # 录制同步数据"
echo "   d) ./process_synced_bag.sh <bag>   # 处理SLAM"
