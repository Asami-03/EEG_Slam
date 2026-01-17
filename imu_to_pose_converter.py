
import rospy
from sensor_msgs.msg import Imu
from geometry_msgs.msg import PoseStamped, Pose, Point, Quaternion
from nav_msgs.msg import Path
import numpy as np
from scipy.spatial.transform import Rotation

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
        
        rospy.loginfo("IMU to Pose converter started (with orientation integration)!")
        rospy.loginfo("Subscribing to: /synced/imu")
        rospy.loginfo("Publishing to: /imu_pose and /imu_path")
        
    def imu_callback(self, imu_msg):
        """处理IMU消息并转换为Pose"""
        
        current_time = imu_msg.header.stamp.to_sec()
        
        # 初始化时间
        if self.last_time is None:
            self.last_time = current_time
            return
        
        dt = current_time - self.last_time
        if dt <= 0 or dt > 0.1:  # 忽略异常时间间隔
            self.last_time = current_time
            return
        
        # 1. 从角速度积分姿态
        angular_vel = np.array([
            imu_msg.angular_velocity.x,
            imu_msg.angular_velocity.y,
            imu_msg.angular_velocity.z
        ])
        
        # 角速度转旋转增量
        angle = np.linalg.norm(angular_vel) * dt
        if angle > 1e-6:  # 避免除零
            axis = angular_vel / np.linalg.norm(angular_vel)
            delta_rotation = Rotation.from_rotvec(axis * angle)
            self.orientation = self.orientation * delta_rotation
        
        # 2. 获取线性加速度并转换到世界坐标系
        acc_body = np.array([
            imu_msg.linear_acceleration.x,
            imu_msg.linear_acceleration.y,
            imu_msg.linear_acceleration.z
        ])
        
        # 转换到世界坐标系并减去重力
        acc_world = self.orientation.apply(acc_body) - self.gravity
        
        # 3. 速度和位置积分（带衰减减少漂移）
        self.velocity += acc_world * dt
        self.velocity *= 0.999  # 简单的速度衰减
        
        self.position += self.velocity * dt
        
        # 4. 创建PoseStamped消息
        pose_msg = PoseStamped()
        pose_msg.header = imu_msg.header
        pose_msg.header.frame_id = "world"
        
        # 设置位置
        pose_msg.pose.position.x = self.position[0]
        pose_msg.pose.position.y = self.position[1]
        pose_msg.pose.position.z = self.position[2]
        
        # 设置姿态（从积分得到）
        quat = self.orientation.as_quat()  # [x, y, z, w]
        pose_msg.pose.orientation.x = quat[0]
        pose_msg.pose.orientation.y = quat[1]
        pose_msg.pose.orientation.z = quat[2]
        pose_msg.pose.orientation.w = quat[3]
        
        # 发布单个Pose
        self.pose_pub.publish(pose_msg)
        
        # 添加到路径并发布
        self.path.header.stamp = imu_msg.header.stamp
        self.path.poses.append(pose_msg)
        
        # 限制路径长度（保留最近1000个点）
        if len(self.path.poses) > 1000:
            self.path.poses.pop(0)
        
        self.path_pub.publish(self.path)
        
        self.last_time = current_time
        
    def run(self):
        rospy.spin()

if __name__ == '__main__':
    try:
        converter = IMUToPoseConverter()
        converter.run()
    except rospy.ROSInterruptException:
        pass
