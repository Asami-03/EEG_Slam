#!/bin/bash
# 测试数据转换节点功能

CONTAINER="vir_slam_dev"
ROS_SETUP="source /opt/ros/noetic/setup.bash"

echo "🧪 测试VIR-SLAM数据转换节点"
echo "============================"

# 检查容器状态
if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    echo "❌ 容器未运行，请先运行 ./start_container.sh"
    exit 1
fi

echo "1️⃣ 测试图像转换节点..."
echo "   检查输入话题: /usb_cam/image_raw"
if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 3 rostopic list | grep -q '/usb_cam/image_raw'"; then
    echo "   ✅ 输入话题存在"
    
    # 启动转换节点进行测试
    echo "   🚀 启动图像转换节点 (测试5秒)..."
    ./start_data_converters.sh &
    CONVERTER_PID=$!
    
    sleep 5
    
    echo "   🔍 检查输出话题: /camera/color/image_raw"
    if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 3 rostopic list | grep -q '/camera/color/image_raw'"; then
        echo "   ✅ 图像转换节点工作正常"
        
        # 检查消息格式
        echo "   📋 检查输出图像格式..."
        docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 3 rostopic echo /camera/color/image_raw --count=1" | grep -E "(encoding|width|height)"
    else
        echo "   ❌ 图像转换节点未产生输出"
    fi
    
    # 停止测试
    kill $CONVERTER_PID 2>/dev/null || true
else
    echo "   ⚠️ 输入话题不存在，请先启动相机"
fi

echo ""
echo "2️⃣ 测试UWB转换节点..."
echo "   检查输入话题: /uwb/pose"
if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 3 rostopic list | grep -q '/uwb/pose'"; then
    echo "   ✅ 输入话题存在"
    
    sleep 2
    
    echo "   🔍 检查输出话题: /uwb/corrected_range"
    if docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 3 rostopic list | grep -q '/uwb/corrected_range'"; then
        echo "   ✅ UWB转换节点工作正常"
        
        # 检查消息格式
        echo "   📋 检查输出距离格式..."
        docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; timeout 3 rostopic echo /uwb/corrected_range --count=1" | grep -E "(point|stamp)"
    else
        echo "   ❌ UWB转换节点未产生输出"
    fi
else
    echo "   ⚠️ 输入话题不存在，请先启动UWB系统"
fi

echo ""
echo "3️⃣ 检查节点运行状态..."
docker exec "${CONTAINER}" bash -c "${ROS_SETUP}; rosnode list" | grep -E "(converter|sync)" || echo "   ⚠️ 未发现转换节点"

echo ""
echo "4️⃣ 检查日志输出..."
echo "图像转换日志:"
docker exec "${CONTAINER}" tail -n 5 /tmp/image_converter.log 2>/dev/null || echo "   📝 日志文件不存在"

echo ""
echo "UWB转换日志:"
docker exec "${CONTAINER}" tail -n 5 /tmp/uwb_converter.log 2>/dev/null || echo "   📝 日志文件不存在"

echo ""
echo "✅ 转换节点测试完成！"
echo ""
echo "💡 使用建议:"
echo "1. 确保所有传感器正常运行"
echo "2. 使用 ./start_data_converters.sh 启动转换节点"
echo "3. 使用 ./record_converted_virslam_bag.sh 录制转换后的数据"
echo "4. 直接使用转换后的bag文件进行VIR-SLAM处理"
