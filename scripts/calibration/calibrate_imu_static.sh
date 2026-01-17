#!/usr/bin/env bash
# IMU静态标定脚本

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"
CATKIN_SETUP="source /root/catkin_ws/devel/setup.bash"

echo "📊 IMU静态标定"
echo "请确保设备完全静止放置30秒..."
echo "按Enter开始标定，或Ctrl+C取消"
read

in_container() {
  docker exec -i "${CONTAINER}" bash -lc "$*"
}

# 创建IMU标定脚本
in_container "cat > /tmp/imu_calibration.py << 'EOF'
#!/usr/bin/env python3
import rospy
from sensor_msgs.msg import Imu
import numpy as np
import yaml

class IMUCalibrator:
    def __init__(self):
        self.imu_data = []
        rospy.init_node('imu_calibrator')
        
        rospy.Subscriber('/livox/imu', Imu, self.imu_callback)
        print(\"📊 开始IMU标定 - 设备必须静止!\")
        print(\"收集30秒数据...\")
        
    def imu_callback(self, msg):
        acc = [msg.linear_acceleration.x, msg.linear_acceleration.y, msg.linear_acceleration.z]
        gyro = [msg.angular_velocity.x, msg.angular_velocity.y, msg.angular_velocity.z]
        self.imu_data.append({'acc': acc, 'gyro': gyro, 'time': rospy.Time.now().to_sec()})
        
    def calibrate(self):
        rospy.sleep(30)  # 收集30秒
        
        if len(self.imu_data) < 100:
            print(\"❌ 数据不足，请检查IMU话题\")
            return
            
        # 计算偏置
        acc_data = np.array([d['acc'] for d in self.imu_data])
        gyro_data = np.array([d['gyro'] for d in self.imu_data])
        
        acc_bias = np.mean(acc_data, axis=0)
        gyro_bias = np.mean(gyro_data, axis=0)
        
        acc_noise = np.std(acc_data, axis=0)
        gyro_noise = np.std(gyro_data, axis=0)
        
        # 重力应该接近9.81
        gravity_norm = np.linalg.norm(acc_bias)
        
        print(f\"\\n📊 IMU标定结果:\")
        print(f\"数据点数: {len(self.imu_data)}\")
        print(f\"采集时长: {self.imu_data[-1]['time'] - self.imu_data[0]['time']:.1f}秒\")
        print(f\"\\n加速度偏置: [{acc_bias[0]:.6f}, {acc_bias[1]:.6f}, {acc_bias[2]:.6f}]\")
        print(f\"陀螺仪偏置: [{gyro_bias[0]:.6f}, {gyro_bias[1]:.6f}, {gyro_bias[2]:.6f}]\")
        print(f\"\\n加速度噪声: [{acc_noise[0]:.6f}, {acc_noise[1]:.6f}, {acc_noise[2]:.6f}]\")
        print(f\"陀螺仪噪声: [{gyro_noise[0]:.6f}, {gyro_noise[1]:.6f}, {gyro_noise[2]:.6f}]\")
        print(f\"\\n重力大小: {gravity_norm:.3f} m/s² (期望: 9.81)\")
        
        if abs(gravity_norm - 9.81) > 0.5:
            print(\"❌ 重力测量异常！请检查IMU安装方向\")
        else:
            print(\"✅ 重力测量正常\")
        
        # 保存标定结果
        calib_data = {
            'acc_bias': acc_bias.tolist(),
            'gyro_bias': gyro_bias.tolist(),
            'acc_noise': acc_noise.tolist(), 
            'gyro_noise': gyro_noise.tolist(),
            'gravity_norm': float(gravity_norm),
            'sample_count': len(self.imu_data)
        }
        
        with open('/tmp/imu_calibration.yaml', 'w') as f:
            yaml.dump(calib_data, f)
        
        print(\"\\n💾 标定结果已保存到: /tmp/imu_calibration.yaml\")

if __name__ == '__main__':
    calibrator = IMUCalibrator()
    calibrator.calibrate()
EOF"

echo "🚀 执行IMU标定..."
in_container "${ROS_SETUP}; ${CATKIN_SETUP}; python3 /tmp/imu_calibration.py"

echo ""
echo "📋 标定结果："
in_container "cat /tmp/imu_calibration.yaml"

# 复制标定结果到宿主机
docker cp "${CONTAINER}:/tmp/imu_calibration.yaml" "./imu_calibration_results.yaml"
echo ""
echo "✅ 标定结果已复制到宿主机: ./imu_calibration_results.yaml"
