#!/bin/bash
# VIR-SLAM 完整操作指南

echo "🚀 VIR-SLAM 完整操作流程"
echo "========================"
echo ""

echo "📋 两步式操作流程:"
echo ""

echo "1️⃣ 启动传感器和转换系统 (一次性启动):"
echo "   ./start_sensors_and_converters.sh"
echo "   ⏰ 等待所有传感器和转换节点就绪 (~60秒)"
echo ""

echo "2️⃣ 录制VIR-SLAM兼容数据:"
echo "   ./record_virslam_synced_bag.sh" 
echo "   📹 录制完全同步、格式匹配的数据"
echo ""

echo "3️⃣ 处理数据生成轨迹:"
echo "   ./process_virslam_bag.sh <bag文件路径>"
echo "   🎯 直接处理，无需格式转换"
echo ""

echo "========================================="
echo ""

echo "🔧 故障排除工具:"
echo "   ./check_sensor_status.sh     # 检查传感器状态"
echo "   ./test_data_converters.sh    # 测试转换节点"
echo "   ./diagnose_slam_issues.sh    # 深度问题诊断"
echo ""

echo "📊 实时监控命令:"
echo "   # 查看同步状态"
echo "   docker exec vir_slam_dev bash -c 'source /opt/ros/noetic/setup.bash; rostopic echo /synced/status --count=1'"
echo ""
echo "   # 查看话题列表"  
echo "   docker exec vir_slam_dev bash -c 'source /opt/ros/noetic/setup.bash; rostopic list | grep synced'"
echo ""
echo "   # 检查消息频率"
echo "   docker exec vir_slam_dev bash -c 'source /opt/ros/noetic/setup.bash; rostopic hz /synced/image_raw'"
echo ""

echo "⚠️  关键保证:"
echo "   ✅ 时间戳完全对齐 - 统一时间基准"
echo "   ✅ 格式完全匹配 - mono8图像 + PointStamped距离"
echo "   ✅ 坐标系统一 - 标准frame_id"
echo "   ✅ 数据质量检查 - 自动验证异常值"
echo ""

echo "🎯 录制的bag文件直接兼容VIR-SLAM，无需任何额外转换!"

# 显示当前系统状态
echo ""
echo "========================================="
echo "💻 当前系统状态:"

if docker ps --format '{{.Names}}' | grep -qx "vir_slam_dev"; then
    echo "   ✅ Docker容器运行中"
    
    if docker exec vir_slam_dev bash -c "source /opt/ros/noetic/setup.bash; rosnode list 2>/dev/null | grep -q unified_timestamp_sync"; then
        echo "   ✅ 同步系统运行中"
        echo ""
        echo "🚀 系统已就绪，可以直接录制:"
        echo "   ./record_virslam_synced_bag.sh"
    else
        echo "   ❌ 同步系统未启动"
        echo ""
        echo "💡 请先启动传感器系统:"
        echo "   ./start_sensors_and_converters.sh"
    fi
else
    echo "   ❌ Docker容器未运行"
    echo ""
    echo "💡 请先启动容器:"
    echo "   ./start_container.sh"
fi

echo ""
echo "========================================="
