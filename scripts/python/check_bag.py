#!/usr/bin/env python3
import rosbag
import sys

def check_bag_topics(bag_path):
    try:
        bag = rosbag.Bag(bag_path, 'r')
        print(f"📋 Bag文件: {bag_path}")
        print(f"⏰ 时长: {bag.get_end_time() - bag.get_start_time():.2f} 秒")
        print(f"📊 消息总数: {bag.get_message_count()}")
        print("\n📋 话题列表:")
        
        info = bag.get_type_and_topic_info()
        for topic, topic_info in info.topics.items():
            msg_count = topic_info.message_count
            msg_type = topic_info.msg_type
            print(f"  {topic}: {msg_type} ({msg_count} 条消息)")
        
        bag.close()
    except Exception as e:
        print(f"❌ 错误: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("用法: python3 check_bag.py <bag文件路径>")
        sys.exit(1)
    
    check_bag_topics(sys.argv[1])
