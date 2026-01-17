#!/bin/bash
# VIR-SLAM 脚本管理和清理记录
# 
# 📋 清理完成的脚本列表

echo "🗂️  VIR-SLAM脚本整理完成"
echo "================================"

echo "❌ 已删除的过时脚本："
echo "  - fix_slam_init.sh          # 已被时间同步方案替代"
echo "  - fix_timestamp_sync.sh     # 功能整合到record_synced_virslam_bag.sh"
echo "  - process_with_remapping.sh # 话题重映射已整合到主处理脚本"
echo "  - process_synced_bag.sh     # 已被process_virslam_bag.sh替代"
echo "  - diagnose_slam.sh          # 简化版，保留完整版diagnose_slam_issues.sh"
echo ""

echo "✅ 保留的核心脚本分类："
echo ""

echo "📦 容器管理："
echo "  - start_container.sh        # 启动Docker容器"
echo "  - enter_container.sh        # 进入容器环境"
echo ""

echo "🚀 传感器启动："
echo "  - start_all_sensors.sh      # 启动所有传感器(主要脚本)"
echo "  - start_ros1_livox_pointcloud2.sh"
echo "  - start_vir_slam_direct.sh"
echo "  - start_uwb_calibration.sh"
echo ""

echo "📹 数据录制："
echo "  - record_synced_virslam_bag.sh  # ⭐ 主要录制脚本(时间同步)"
echo "  - record_with_excitation.sh     # ⭐ 带激励指导的录制"
echo "  - record_virslam_bag.sh         # 基础录制脚本"
echo ""

echo "⚙️  数据处理："
echo "  - process_virslam_bag.sh    # ⭐ 主要处理脚本"
echo "  - simple_slam_process.sh    # 简化处理脚本"
echo ""

echo "🔧 标定工具："
echo "  - calibrate_imx291_camera.sh    # ⭐ IMX291相机标定"
echo "  - calibrate_imu_static.sh       # IMU标定"
echo "  - check_all_calibrations.sh     # 标定检查"
echo ""

echo "🔍 诊断工具："
echo "  - diagnose_slam_issues.sh   # ⭐ 完整问题诊断"
echo "  - test_camera_uwb.sh        # 相机UWB测试"
echo "  - test_fixed_uwb.sh         # UWB固定测试"
echo ""

echo "🛠️  系统工具："
echo "  - bridge_ros2_to_ros1.sh    # ROS版本桥接"
echo "  - check_uwb_topics.sh       # UWB话题检查"
echo "  - fix_ros1_lidar.sh         # ROS1激光雷达修复"
echo "  - install_drivers.sh        # 驱动安装"
echo "  - nodeframe2_config_guide.sh # 配置指导"
echo "  - quick_check.sh            # 快速检查"
echo "  - uwb_config_guide.sh       # UWB配置指导"
echo "  - uwb_system_diagnosis.sh   # UWB系统诊断"
echo ""

echo "🎯 推荐使用流程："
echo "  1️⃣  启动: ./start_container.sh && ./start_all_sensors.sh"
echo "  2️⃣  标定: ./calibrate_imx291_camera.sh"
echo "  3️⃣  录制: ./record_with_excitation.sh"
echo "  4️⃣  处理: ./process_virslam_bag.sh <bag文件>"
echo "  5️⃣  诊断: ./diagnose_slam_issues.sh (如果有问题)"
echo ""

echo "📊 脚本统计："
TOTAL_SCRIPTS=$(ls -1 *.sh 2>/dev/null | wc -l)
echo "  总计脚本数量: ${TOTAL_SCRIPTS}"
echo "  清理前数量: 32"
echo "  删除脚本数量: 5"
echo ""

echo "✨ 清理完成！现在脚本结构更清晰，功能不重复。"
