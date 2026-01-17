# VIR-SLAM 完整评估系统

## 📋 概述

本系统用于评估VIR-SLAM（VIO + UWB融合）相对于纯VIO（VINS-Mono）的性能改进。包含Ground Truth对齐、Docker测试运行、Umeyama坐标变换和可视化分析。

---

## 🚀 快速开始

### 单个数据集完整评估

```bash
# 1. 运行Docker测试（提取GT + VIO测试 + VIR测试）
./eval_fresh.sh MH_01_easy

# 2. 执行Umeyama对齐和生成可视化
./eval_align.sh MH_01_easy
```

### 评估其他数据集

```bash
# MH_02_easy
./eval_fresh.sh MH_02_easy && ./eval_align.sh MH_02_easy

# MH_03_medium
./eval_fresh.sh MH_03_medium && ./eval_align.sh MH_03_medium

# MH_04_difficult
./eval_fresh.sh MH_04_difficult && ./eval_align.sh MH_04_difficult

# MH_05_difficult
./eval_fresh.sh MH_05_difficult && ./eval_align.sh MH_05_difficult
```

---

## 📁 文件说明

### 核心脚本

| 文件 | 说明 |
|------|------|
| `eval_fresh.sh` | 完整Docker测试流程：提取GT → VIO测试 → VIR测试 → 基础评估 |
| `align_trajectories.py` | Umeyama算法SE(3)对齐 + ATE/Loop Error计算 + 可视化生成 |
| `eval_align.sh` | 快速对齐脚本，自动找到最新评估目录并执行对齐 |

### 输出结构

```
~/vir_slam_evaluation_YYYYMMDD_HHMMSS/
├── trajectories/               # 轨迹文件（TUM格式）
│   ├── gt_MH_XX.txt           # Ground Truth（从EuRoC ZIP提取）
│   ├── vio_MH_XX.txt          # VIO原始轨迹（相对坐标系）
│   ├── vir_MH_XX.txt          # VIR原始轨迹（相对坐标系）
│   ├── vio_MH_XX_aligned.txt  # VIO对齐后轨迹（世界坐标系）
│   └── vir_MH_XX_aligned.txt  # VIR对齐后轨迹（世界坐标系）
│
├── evaluations/                # 评估指标
│   └── metrics_aligned.txt    # Umeyama对齐后的精度指标
│
├── visualizations/             # 可视化图表
│   ├── trajectory_aligned.png      # ⭐ 对齐前后三图对比
│   ├── xy_comparison_aligned.png   # XY平面对齐轨迹
│   ├── error_over_time.png         # 误差随时间变化曲线
│   └── statistics.png              # 统计信息柱状图
│
└── raw_data/                   # 原始ROS数据
    ├── vio_raw.txt
    └── vir_raw.txt
```

---

## 📊 评估指标

### 1. Loop Closure Error（环路闭合误差）
- 定义：起点和终点之间的欧氏距离
- 理想值：0米（完美闭合）
- 评估：越小越好

### 2. ATE RMSE（绝对轨迹误差均方根）
- 定义：估计轨迹与Ground Truth的平均偏差
- 计算：采样100个点计算欧氏距离的RMSE
- 评估：越小越好

---

## 🔧 技术细节

### 坐标系对齐

**问题**：VIO/VIR输出的是相对坐标系（以起始点为原点），Ground Truth是EuRoC世界坐标系

**解决方案**：使用Umeyama算法进行SE(3)对齐
- 计算旋转矩阵R（3×3）
- 计算平移向量t（3×1）
- 可选：计算尺度因子s（本系统固定为1.0）

**变换公式**：
```
P_aligned = s × R × P_original + t
```

### Docker测试流程

1. **启动容器**：运行ROS Noetic环境
2. **配置模式**：修改euroc_config.yaml中的use_uwb参数
3. **启动节点**：roslaunch vir_estimator vir_euroc.launch
4. **记录轨迹**：rostopic echo /vir_estimator/odometry
5. **播放数据**：rosbag play *.bag --clock
6. **转换格式**：Python正则表达式提取位姿 → TUM格式

---

## 📈 示例结果（MH_01_easy）

```
VIR-SLAM 评估结果（Umeyama对齐后）: MH_01_easy
============================================================

对齐方法: Umeyama算法 (SE(3)变换)

ATE RMSE (m):
  VIO:  6.6616
  VIR:  6.6639
  改进: -0.04%

Loop Closure Error (m):
  VIO:  0.8072
  VIR:  0.7636
  改进: +5.39% ✅
```

**结论**：
- VIR-SLAM在环路闭合精度上优于VIO（+5.39%）
- ATE基本持平，说明整体轨迹跟踪能力相当
- UWB约束主要改善了长期漂移和闭环精度

---

## 🛠️ 依赖

### 系统依赖
- Docker (vir_slam:noetic 镜像)
- Python 3.8+
- NumPy
- Matplotlib

### 数据集
- EuRoC Machine Hall 数据集（ZIP格式）
- 位置：`~/vir_slam_docker/datasets/machine_hall/`

---

## 📝 注意事项

1. **Docker权限**：确保当前用户可以运行docker命令
2. **存储空间**：每个数据集评估约需500MB空间
3. **运行时间**：单个数据集完整评估约5-10分钟
4. **Ground Truth**：自动从ZIP文件提取，无需手动操作

---

## 🎯 查看结果

```bash
# 查看最新评估的指标
cat ~/vir_slam_evaluation_*/evaluations/metrics_aligned.txt

# 查看可视化图表
xdg-open ~/vir_slam_evaluation_*/visualizations/trajectory_aligned.png

# 列出所有评估目录
ls -d ~/vir_slam_evaluation_*
```

---

## 🔍 故障排查

### Docker容器启动失败
```bash
# 检查Docker服务
sudo systemctl status docker

# 检查镜像是否存在
docker images | grep vir_slam
```

### 找不到Ground Truth
```bash
# 检查ZIP文件
ls ~/vir_slam_docker/datasets/machine_hall/*/*.zip

# 手动提取测试
unzip -l datasets/machine_hall/MH_01_easy/MH_01_easy.zip | grep groundtruth
```

### Python依赖缺失
```bash
pip3 install numpy matplotlib
```

---

## 📚 参考文献

- **Umeyama算法**: Shinji Umeyama, "Least-squares estimation of transformation parameters between two point patterns", IEEE TPAMI, 1991
- **EuRoC数据集**: M. Burri et al., "The EuRoC Micro Aerial Vehicle Datasets", IJRR, 2016
- **VINS-Mono**: T. Qin et al., "VINS-Mono: A Robust and Versatile Monocular Visual-Inertial State Estimator", IEEE TRO, 2018

---

**最后更新**: 2026-01-06
