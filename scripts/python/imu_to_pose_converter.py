
import rospy
from sensor_msgs.msg import Imu
from geometry_msgs.msg import PoseStamped, Pose, Point, Quaternion
from nav_msgs.msg import Path
import numpy as np
from scipy.spatial.transform import Rotation
from collections import deque

class IMUToPoseConverter:
    def __init__(self):
        rospy.init_node('imu_to_pose_converter', anonymous=True)

        # 订阅IMU话题
        self.imu_sub = rospy.Subscriber('/synced/imu', Imu, self.imu_callback)

        # 发布Pose话题
        self.pose_pub = rospy.Publisher('/imu_pose', PoseStamped, queue_size=10)
        self.path_pub = rospy.Publisher('/imu_path', Path, queue_size=10)

        # 存储路径
        self.path = Path()
        self.path.header.frame_id = "world"

        # 位置和速度（numpy数组）
        self.position = np.array([0.0, 0.0, 0.0])
        self.velocity = np.array([0.0, 0.0, 0.0])

        # 姿态（使用scipy的Rotation对象）
        self.orientation = Rotation.identity()

        # 重力向量
        self.gravity = np.array([0.0, 0.0, 9.81])

        self.last_time = None

        # ============ 新增：校准和ZUPT相关 ============
        # 校准阶段
        self.calibration_done = False
        self.calibration_samples = []
        self.calibration_gyro_samples = []
        self.calibration_count = 200  # 收集200帧用于校准

        # 重力模式：True=需要减重力，False=数据已去重力
        self.subtract_gravity = True

        # IMU bias估计
        self.accel_bias = np.array([0.0, 0.0, 0.0])
        self.gyro_bias = np.array([0.0, 0.0, 0.0])

        # ZUPT参数（Zero Velocity Update）
        self.zupt_gyro_thresh = 0.05      # rad/s，静止时角速度阈值
        self.zupt_accel_var_thresh = 0.5  # m/s^2，静止时加速度方差阈值
        self.zupt_window = deque(maxlen=20)  # 滑动窗口检测静止

        # 互补滤波参数（用于roll/pitch校正）
        self.alpha = 0.98  # 陀螺权重，0.98表示98%信任陀螺，2%信任加速度

        # 打印计数器
        self.print_counter = 0

        rospy.loginfo("IMU to Pose converter started (with calibration + ZUPT + complementary filter)!")
        rospy.loginfo("Subscribing to: /synced/imu")
        rospy.loginfo("Publishing to: /imu_pose and /imu_path")
        rospy.loginfo("Collecting %d samples for calibration, please keep IMU stationary..." % self.calibration_count)
        
    def imu_callback(self, imu_msg):
        """处理IMU消息并转换为Pose"""

        # 获取原始数据
        acc_raw = np.array([
            imu_msg.linear_acceleration.x,
            imu_msg.linear_acceleration.y,
            imu_msg.linear_acceleration.z
        ])
        gyro_raw = np.array([
            imu_msg.angular_velocity.x,
            imu_msg.angular_velocity.y,
            imu_msg.angular_velocity.z
        ])

        # ============ 校准阶段 ============
        if not self.calibration_done:
            self.calibration_samples.append(acc_raw.copy())
            self.calibration_gyro_samples.append(gyro_raw.copy())

            if len(self.calibration_samples) >= self.calibration_count:
                self._do_calibration()
            return

        current_time = imu_msg.header.stamp.to_sec()

        # 初始化时间
        if self.last_time is None:
            self.last_time = current_time
            return

        dt = current_time - self.last_time
        if dt <= 0 or dt > 0.1:  # 忽略异常时间间隔
            self.last_time = current_time
            return

        # ============ 去除bias ============
        acc_body = acc_raw - self.accel_bias
        gyro = gyro_raw - self.gyro_bias

        # ============ ZUPT检测 ============
        self.zupt_window.append({
            'acc': acc_body.copy(),
            'gyro': gyro.copy()
        })
        is_stationary = self._detect_stationary()

        # ============ 姿态更新（互补滤波） ============
        # 1. 陀螺积分（高频）
        angle = np.linalg.norm(gyro) * dt
        if angle > 1e-6:
            axis = gyro / np.linalg.norm(gyro)
            delta_rotation = Rotation.from_rotvec(axis * angle)
            self.orientation = self.orientation * delta_rotation

        # 2. 加速度校正roll/pitch（低频，仅当接近静止时）
        acc_norm = np.linalg.norm(acc_body)
        if self.subtract_gravity and 8.0 < acc_norm < 11.0:
            # 从加速度估计roll和pitch
            acc_pitch = np.arctan2(-acc_body[0], np.sqrt(acc_body[1]**2 + acc_body[2]**2))
            acc_roll = np.arctan2(acc_body[1], acc_body[2])

            # 获取当前姿态的euler角
            current_euler = self.orientation.as_euler('xyz')

            # 互补滤波：融合陀螺（高频）和加速度（低频）
            alpha = self.alpha if not is_stationary else 0.9  # 静止时更信任加速度
            fused_roll = alpha * current_euler[0] + (1 - alpha) * acc_roll
            fused_pitch = alpha * current_euler[1] + (1 - alpha) * acc_pitch
            fused_yaw = current_euler[2]  # yaw只能靠陀螺，没有磁力计

            self.orientation = Rotation.from_euler('xyz', [fused_roll, fused_pitch, fused_yaw])

        # ============ 加速度转世界坐标系 ============
        acc_world = self.orientation.apply(acc_body)
        if self.subtract_gravity:
            acc_world -= self.gravity

        # ============ ZUPT：静止时速度归零 ============
        if is_stationary:
            self.velocity *= 0.5  # 快速衰减而非直接归零，更平滑
            acc_world *= 0.1     # 静止时抑制加速度积分

        # ============ 速度和位置积分 ============
        self.velocity += acc_world * dt
        self.velocity *= 0.995  # 持续衰减减少漂移

        self.position += self.velocity * dt

        # ============ 发布消息 ============
        pose_msg = PoseStamped()
        pose_msg.header = imu_msg.header
        pose_msg.header.frame_id = "world"

        pose_msg.pose.position.x = self.position[0]
        pose_msg.pose.position.y = self.position[1]
        pose_msg.pose.position.z = self.position[2]

        quat = self.orientation.as_quat()  # [x, y, z, w]
        pose_msg.pose.orientation.x = quat[0]
        pose_msg.pose.orientation.y = quat[1]
        pose_msg.pose.orientation.z = quat[2]
        pose_msg.pose.orientation.w = quat[3]

        self.pose_pub.publish(pose_msg)

        # 添加到路径并发布
        self.path.header.stamp = imu_msg.header.stamp
        self.path.poses.append(pose_msg)

        if len(self.path.poses) > 1000:
            self.path.poses.pop(0)

        self.path_pub.publish(self.path)

        self.last_time = current_time

        # 调试输出
        self.print_counter += 1
        if self.print_counter % 100 == 0:
            rospy.loginfo("Pos: [%.2f, %.2f, %.2f] Vel: [%.2f, %.2f, %.2f] Static: %s" % (
                self.position[0], self.position[1], self.position[2],
                self.velocity[0], self.velocity[1], self.velocity[2],
                "YES" if is_stationary else "NO"
            ))

    def _do_calibration(self):
        """执行校准：确定重力模式和bias"""
        acc_samples = np.array(self.calibration_samples)
        gyro_samples = np.array(self.calibration_gyro_samples)

        # 计算加速度模长均值
        acc_norms = np.linalg.norm(acc_samples, axis=1)
        mean_acc_norm = np.mean(acc_norms)

        # 判断是否需要减重力
        if mean_acc_norm > 7.0:
            self.subtract_gravity = True
            rospy.loginfo("Calibration: acc_norm=%.2f, data INCLUDES gravity, will subtract" % mean_acc_norm)
            # 加速度bias：均值应该是[0,0,g]，所以bias = mean - [0,0,g]
            mean_acc = np.mean(acc_samples, axis=0)
            # 假设静止时z轴朝上
            expected_acc = np.array([0.0, 0.0, 9.81])
            self.accel_bias = mean_acc - expected_acc
        else:
            self.subtract_gravity = False
            rospy.loginfo("Calibration: acc_norm=%.2f, data EXCLUDES gravity, will NOT subtract" % mean_acc_norm)
            # 已去重力，静止时应该是[0,0,0]
            self.accel_bias = np.mean(acc_samples, axis=0)

        # 陀螺bias：静止时应该是0
        self.gyro_bias = np.mean(gyro_samples, axis=0)

        rospy.loginfo("Calibration done!")
        rospy.loginfo("  Accel bias: [%.4f, %.4f, %.4f]" % tuple(self.accel_bias))
        rospy.loginfo("  Gyro bias: [%.4f, %.4f, %.4f]" % tuple(self.gyro_bias))
        rospy.loginfo("  Subtract gravity: %s" % self.subtract_gravity)

        # 初始化姿态（从加速度估计初始roll/pitch）
        if self.subtract_gravity:
            mean_acc = np.mean(acc_samples, axis=0)
            init_pitch = np.arctan2(-mean_acc[0], np.sqrt(mean_acc[1]**2 + mean_acc[2]**2))
            init_roll = np.arctan2(mean_acc[1], mean_acc[2])
            self.orientation = Rotation.from_euler('xyz', [init_roll, init_pitch, 0.0])
            rospy.loginfo("  Initial orientation: roll=%.2f deg, pitch=%.2f deg" % (
                np.degrees(init_roll), np.degrees(init_pitch)))

        self.calibration_done = True

    def _detect_stationary(self):
        """检测是否静止（用于ZUPT）"""
        if len(self.zupt_window) < 10:
            return False

        gyro_list = np.array([s['gyro'] for s in self.zupt_window])
        acc_list = np.array([s['acc'] for s in self.zupt_window])

        # 检查陀螺是否接近0
        gyro_norm = np.mean(np.linalg.norm(gyro_list, axis=1))

        # 检查加速度方差是否很小
        acc_var = np.mean(np.var(acc_list, axis=0))

        is_static = (gyro_norm < self.zupt_gyro_thresh) and (acc_var < self.zupt_accel_var_thresh)
        return is_static

    def run(self):
        rospy.spin()

if __name__ == '__main__':
    try:
        converter = IMUToPoseConverter()
        converter.run()
    except rospy.ROSInterruptException:
        pass
