#!/usr/bin/env bash
# VIR-SLAM 激励动作指导录制脚本

CONTAINER="vir_slam_dev"

echo "🎯 VIR-SLAM 激励动作指导录制"
echo "========================================"
echo ""
echo "📋 SLAM初始化需要充分的激励动作！"
echo ""
echo "🎬 针对 MID360+IMX291+UWB 的激励动作序列:"
echo ""
echo "   1️⃣  单目相机视差激励 (12秒)"
echo "      - 左右平移 30-40cm (产生水平视差)"
echo "      - 前后平移 20-30cm (产生径向视差)" 
echo "      - 上下平移 15-25cm (产生垂直视差)"
echo "      💡 目的: 让单目相机估计特征点深度"
echo ""
echo "   2️⃣  IMU重力感知激励 (10秒)"
echo "      - 绕X轴缓慢俯仰 ±20度"
echo "      - 绕Y轴缓慢偏航 ±20度"
echo "      - 绕Z轴轻微滚转 ±15度"
echo "      💡 目的: 让IMU感受重力方向变化"
echo ""
echo "   3️⃣  MID360扫描激励 (15秒)"
echo "      - 螺旋形轨迹运动"
echo "      - 确保激光扫描不同角度"
echo "      - 避免遮挡激光发射窗"
echo "      💡 目的: 让MID360建立完整点云地图"
echo ""
echo "   4️⃣  多传感器融合激励 (12秒)"
echo "      - 组合平移+旋转运动"
echo "      - 保持UWB基站可见"
echo "      - 图像特征丰富区域"
echo "      💡 目的: 视觉+激光+UWB数据关联"
echo ""
echo "   5️⃣  稳定收敛 (8秒)"
echo "      - 面向纹理丰富场景"
echo "      - 轻微的微调运动"
echo "      - 让系统收敛初始化"
echo "      💡 目的: 验证初始化成功"
echo ""
echo "⚠️  MID360+IMX291 特别注意:"
echo "   ❌ 避免快速旋转 (单目无法跟上)"
echo "   ❌ 避免遮挡MID360激光窗口"
echo "   ❌ 避免对准反光表面 (影响激光)"
echo "   ❌ 避免纯旋转无平移 (单目无视差)"
echo "   ❌ 避免UWB基站遮挡"
echo ""
echo "💡 最佳录制环境 (针对您的硬件):"
echo "   ✅ 室内结构化环境 (MID360适合)"
echo "   ✅ 充足均匀光照 (IMX291感光好)"
echo "   ✅ 纹理丰富墙面和物体"
echo "   ✅ UWB基站分布均匀可见"
echo "   ✅ 避免玻璃、镜面反射"
echo "   ✅ 静态环境无移动物体"
echo ""

read -p "📷 相机和传感器是否已经启动? (y/n): " sensors_ready
if [ "$sensors_ready" != "y" ]; then
    echo "🚀 启动传感器..."
    ./start_all_sensors.sh
    sleep 5
fi

echo ""
echo "🔍 检查传感器状态..."
docker exec ${CONTAINER} bash -c "
source /opt/ros/noetic/setup.bash
echo '📷 相机话题:'
timeout 3s rostopic hz /usb_cam/image_raw 2>/dev/null | head -1 || echo '❌ 相机无数据'
echo '📊 IMU话题:'
timeout 3s rostopic hz /livox/imu 2>/dev/null | head -1 || echo '❌ IMU无数据'
echo '🔶 激光话题:'
timeout 3s rostopic hz /livox/lidar 2>/dev/null | head -1 || echo '❌ 激光无数据'
"

echo ""
read -p "🎬 准备好执行激励动作了吗? 按Enter开始录制..." start_record

echo ""
echo "🔴 开始录制! 执行激励动作..."
echo ""aj
echo "阶段1: 慢速平移 (10秒)"
echo "👆 请开始左右、前后、上下平移..."

# 启动录制 (后台)
./record_synced_virslam_bag.sh &
RECORD_PID=$!

# 激励动作指导
sleep 3
echo "▶️  录制已开始，继续平移动作..."

sleep 7
echo ""
echo "阶段2: 轻微旋转 (10秒)"
echo "🔄 请开始俯仰、偏航、滚转..."
sleep 10

echo ""
echo "阶段3: 8字形运动 (15秒)" 
echo "∞ 请执行水平和垂直8字轨迹..."
sleep 15

echo ""
echo "阶段4: 稳定观察 (10秒)"
echo "👁️  对准特征丰富区域，保持相对静止..."
sleep 10

echo ""
echo "🎬 激励动作完成! 按Ctrl+C停止录制"
echo "💡 建议再录制10-20秒正常移动数据"

# 等待用户手动停止录制
wait $RECORD_PID 2>/dev/null

echo ""
echo "✅ 激励动作录制完成!"
echo ""
echo "📊 录制质量检查建议:"
echo "   1. 检查图像是否清晰无模糊"
echo "   2. 确认IMU数据频率 >100Hz"
echo "   3. 验证有充足的特征点"
echo "   4. 确保时间戳同步正常"
echo ""
echo "🚀 接下来可以处理bag文件:"
echo "   ./process_synced_bag.sh <刚录制的bag文件>"
