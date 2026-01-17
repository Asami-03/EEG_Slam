#!/bin/bash
# 检查传感器启动状态脚本

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"

echo "🔍 传感器启动状态检查"
echo "===================="

# 检查容器状态
if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    echo "❌ Docker容器未运行"
    echo "💡 请先执行: ./start_container.sh"
    exit 1
fi

echo "✅ Docker容器运行中"
echo ""

# 检查各个传感器状态
sensors_ok=true

echo "📷 检查IMX291相机..."
if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 5 rostopic list | grep -q '/usb_cam/image_raw'"; then
    echo "  ✅ 相机话题存在: /usb_cam/image_raw"
    
    # 检查图像数据
    if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 5 rostopic hz /usb_cam/image_raw --window=10 2>/dev/null | grep -q 'average rate'"; then
        echo "  ✅ 相机数据正常"
    else
        echo "  ⚠️ 相机话题存在但无数据流"
        sensors_ok=false
    fi
else
    echo "  ❌ 相机话题不存在"
    echo "  💡 检查USB相机连接和驱动"
    sensors_ok=false
fi

echo ""
echo "🎯 检查MID360 LiDAR+IMU..."
if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 5 rostopic list | grep -q '/livox/lidar'"; then
    echo "  ✅ LiDAR话题存在: /livox/lidar"
else
    echo "  ❌ LiDAR话题不存在"
    sensors_ok=false
fi

if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 5 rostopic list | grep -q '/livox/imu'"; then
    echo "  ✅ IMU话题存在: /livox/imu"
    
    # 检查IMU数据
    if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 5 rostopic hz /livox/imu --window=10 2>/dev/null | grep -q 'average rate'"; then
        echo "  ✅ IMU数据正常"
    else
        echo "  ⚠️ IMU话题存在但无数据流"
        sensors_ok=false
    fi
else
    echo "  ❌ IMU话题不存在"
    echo "  💡 检查MID360连接和Livox驱动"
    sensors_ok=false
fi

echo ""
echo "📡 检查UWB系统..."
if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 5 rostopic list | grep -q '/uwb/pose'"; then
    echo "  ✅ UWB话题存在: /uwb/pose"
    
    # 检查UWB数据
    if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 5 rostopic hz /uwb/pose --window=10 2>/dev/null | grep -q 'average rate'"; then
        echo "  ✅ UWB数据正常"
    else
        echo "  ⚠️ UWB话题存在但无数据流"
        sensors_ok=false
    fi
else
    echo "  ❌ UWB话题不存在"
    echo "  💡 检查UWB设备连接和nooploop驱动"
    sensors_ok=false
fi

echo ""
echo "📊 系统资源检查..."
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
mem_usage=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')
echo "  CPU使用率: ${cpu_usage}%"
echo "  内存使用率: ${mem_usage}%"

if (( $(echo "$cpu_usage > 80" | bc -l) )); then
    echo "  ⚠️ CPU使用率过高，可能影响数据处理"
fi

echo ""
echo "==============================================="

if $sensors_ok; then
    echo "✅ 所有传感器状态正常！"
    echo ""
    echo "🚀 可以继续执行以下步骤:"
    echo "1. 启动转换节点: ./start_data_converters.sh"
    echo "2. 测试转换效果: ./test_data_converters.sh" 
    echo "3. 录制数据: ./record_converted_virslam_bag.sh"
    exit 0
else
    echo "❌ 部分传感器存在问题！"
    echo ""
    echo "🔧 故障排除建议:"
    echo "1. 检查硬件连接"
    echo "2. 重启传感器: ./start_all_sensors.sh"
    echo "3. 检查驱动程序状态"
    echo "4. 查看容器日志"
    exit 1
fi
