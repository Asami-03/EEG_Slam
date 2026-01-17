#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
UWB话题转换器 - 将/uwb/pose转换为VIR-SLAM需要的/uwb/corrected_range
"""

import rospy
import math
from geometry_msgs.msg import PoseStamped, PointStamped
from std_msgs.msg import Header

class UWBPoseToRangeConverter:
    def __init__(self):
        rospy.init_node('uwb_pose_to_range_converter', anonymous=True)
        
        # 发布corrected_range话题 (VIR-SLAM需要的)
        self.range_pub = rospy.Publisher('/uwb/corrected_range', PointStamped, queue_size=10)
        
        # 订阅pose话题 (bag文件中的)
        self.pose_sub = rospy.Subscriber('/uwb/pose', PoseStamped, self.pose_callback, queue_size=10)
        
        # 基站位置 (从VIR-SLAM配置文件获取，假设第一个基站作为参考)
        # 这里使用原点作为参考基站位置
        self.anchor_pos = [0.0, 0.0, 0.0]  # [x, y, z]
        
        rospy.loginfo("🔄 UWB话题转换器启动")
        rospy.loginfo("   输入: /uwb/pose (PoseStamped)")
        rospy.loginfo("   输出: /uwb/corrected_range (PointStamped)")
        rospy.loginfo(f"   参考基站位置: {self.anchor_pos}")
        
    def pose_callback(self, pose_msg):
        """将位置转换为到参考基站的距离"""
        try:
            # 提取位置
            x = pose_msg.pose.position.x
            y = pose_msg.pose.position.y
            z = pose_msg.pose.position.z
            
            # 计算到参考基站的距离
            dx = x - self.anchor_pos[0]
            dy = y - self.anchor_pos[1] 
            dz = z - self.anchor_pos[2]
            
            distance = math.sqrt(dx*dx + dy*dy + dz*dz)
            
            # 创建距离消息
            range_msg = PointStamped()
            range_msg.header = pose_msg.header
            range_msg.point.x = distance
            range_msg.point.y = 0.0
            range_msg.point.z = 0.0
            
            # 发布距离数据
            self.range_pub.publish(range_msg)
            
            rospy.loginfo_throttle(1.0, f"🔄 位置({x:.2f}, {y:.2f}, {z:.2f}) -> 距离: {distance:.2f}m")
            
        except Exception as e:
            rospy.logerr(f"转换失败: {e}")

if __name__ == '__main__':
    try:
        converter = UWBPoseToRangeConverter()
        rospy.spin()
    except rospy.ROSInterruptException:
        rospy.loginfo("转换器节点关闭")
