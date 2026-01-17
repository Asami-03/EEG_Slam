#!/usr/bin/env bash
# TAG设备NodeFrame2配置检查和指导

echo "=============================================="
echo "🔍 TAG设备NodeFrame2配置指导"
echo "=============================================="
echo ""

echo "📋 当前状态:"
echo "✅ UWB系统正常运行，输出位置数据到 /uwb/pose"
echo "⚠️  设备当前发送AnchorFrame0格式，不是NodeFrame2"
echo ""

echo "🎯 NodeFrame2配置步骤:"
echo ""
echo "1️⃣  连接TAG设备到Windows PC"
echo "   - 使用USB转串口线连接TAG设备"
echo "   - 确认设备在设备管理器中显示为COM端口"
echo ""

echo "2️⃣  打开NAssistant软件"
echo "   - 下载并安装最新版本NAssistant"
echo "   - 选择正确的COM端口"
echo "   - 波特率设置为 921600"
echo "   - 点击'连接'"
echo ""

echo "3️⃣  配置输出协议"
echo "   - 在'系统配置'或'Protocol'选项中"
echo "   - 找到'输出协议'或'Output Protocol'"
echo "   - 选择 'NodeFrame2' 格式"
echo "   - 确保以下选项都启用:"
echo "     ✅ 位置输出 (Position Output)"
echo "     ✅ 距离输出 (Distance Output)"
echo "     ✅ IMU输出 (IMU Output)"
echo "     ✅ 四元数输出 (Quaternion Output)"
echo ""

echo "4️⃣  保存并应用配置"
echo "   - 点击'写入'或'Write'按钮"
echo "   - 等待配置写入完成"
echo "   - 重启TAG设备 (断电再上电)"
echo ""

echo "5️⃣  验证配置"
echo "   - 重新启动系统: ./start_all_sensors.sh"
echo "   - 查看是否显示: '🎯 检测到NodeFrame2话题！'"
echo ""

echo "🔧 如果仍然显示AnchorFrame0:"
echo "   - 确认TAG设备而不是基站设备被配置"
echo "   - 检查设备固件版本是否支持NodeFrame2"
echo "   - 尝试恢复出厂设置后重新配置"
echo "   - 联系设备厂商技术支持"
echo ""

echo "📞 技术支持信息:"
echo "   - 设备型号: $(lsusb | grep -i 'nooploop\\|uwb' || echo '请确认设备型号')"
echo "   - 当前波特率: 921600"
echo "   - 当前设备: /dev/ttyACM0"
echo ""

echo "✨ 临时方案:"
echo "   当前系统已经能够处理AnchorFrame0数据并输出位置"
echo "   可以继续使用，但NodeFrame2会提供更准确的数据"
echo ""

echo "=============================================="
