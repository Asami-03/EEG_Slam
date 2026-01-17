#!/bin/bash
# IMX291相机标定脚本
# 使用棋盘格标定IMX291相机内参

echo "=== IMX291 相机标定流程 ==="
echo "确保已启动Docker容器..."

# 1. 启动相机
echo "1. 启动IMX291相机..."
echo "在主机执行："
echo "  cd /path/to/your/camera/driver"
echo "  ./start_imx291_camera.sh  # 或您的相机启动命令"
echo ""

# 2. 准备标定板
echo "2. 准备标定板："
echo "  - 建议使用 9x6 棋盘格"
echo "  - 方格大小约 2.5cm"
echo "  - 打印在平整硬纸板上"
echo ""

# 3. 进入Docker进行标定
echo "3. 在Docker容器内进行标定："
echo ""
echo "# 进入容器"
echo "./enter_container.sh"
echo ""
echo "# 检查相机话题"
echo "rostopic list | grep image"
echo ""
echo "# 启动相机标定节点"
echo "rosrun camera_calibration cameracalibrator.py \\"
echo "  --size 8x5 \\"
echo "  --square 0.025 \\"
echo "  image:=/usb_cam/image_raw \\"
echo "  camera:=/usb_cam"
echo ""

# 4. 标定操作指导
echo "4. 标定操作："
echo "  - 在不同位置、角度展示棋盘格"
echo "  - 覆盖整个图像区域"
echo "  - X,Y,Size,Skew 进度条都变绿后点击 CALIBRATE"
echo "  - 等待计算完成后点击 SAVE"
echo ""

# 5. 标定结果文件
echo "5. 标定结果："
echo "  结果保存在 /tmp/calibrationdata.tar.gz"
echo "  解压后查看 ost.yaml 文件"
echo ""

echo "=== 获取标定参数 ==="
cat << 'EOF'
# 标定完成后，从 ost.yaml 提取参数：

camera_matrix:
  data: [fx, 0, cx, 0, fy, cy, 0, 0, 1]
distortion_coefficients:  
  data: [k1, k2, p1, p2, k3]

# 将这些参数填入 VIR-SLAM 配置文件的对应位置：
projection_parameters:
   fx: [从camera_matrix提取]
   fy: [从camera_matrix提取]  
   cx: [从camera_matrix提取]
   cy: [从camera_matrix提取]

distortion_parameters:
   k1: [从distortion_coefficients提取]
   k2: [从distortion_coefficients提取]
   p1: [从distortion_coefficients提取] 
   p2: [从distortion_coefficients提取]
EOF

echo ""
echo "=== 更新VIR-SLAM配置 ==="
echo "标定完成后，将参数更新到："
echo "/catkin_ws_src/VIR-SLAM/src/VIR_VINS/config/realsense/realsense_spiri.yaml"
echo ""
echo "或者复制模板文件并修改："
echo "cp /host/imx291_mid360_config_template.yaml \\"
echo "   /catkin_ws_src/VIR-SLAM/src/VIR_VINS/config/imx291/imx291_mid360.yaml"

chmod +x /home/jetson/vir_slam_docker/calibrate_imx291_camera.sh
