# VIR-SLAM 完整使用指南

## 📋 目录
1. [快速开始](#快速开始)
2. [核心脚本说明](#核心脚本说明)
3. [完整评估流程](#完整评估流程)
4. [查看源代码](#查看源代码)
5. [结果说明](#结果说明)
6. [常见问题](#常见问题)

---

## 🚀 快速开始

### 评估单个数据集
```bash
cd ~/vir_slam_docker

# 1. 运行测试并生成轨迹
./eval_fresh.sh MH_01_easy

# 2. 对齐轨迹并生成可视化
./eval_align.sh MH_01_easy
```

### 批量评估所有数据集
```bash
cd ~/vir_slam_docker

for ds in MH_01_easy MH_02_easy MH_03_medium MH_04_difficult MH_05_difficult; do
  ./eval_fresh.sh $ds && ./eval_align.sh $ds
done
```

### 进入Docker容器查看源代码
```bash
cd ~/vir_slam_docker
./enter_container.sh
```

---

## 📂 核心脚本说明

### 1. `eval_fresh.sh` - 完整测试脚本
运行Docker容器测试，生成VIO和VIR轨迹

**用法：**
```bash
./eval_fresh.sh <dataset_name>
```

**示例：**
```bash
./eval_fresh.sh MH_01_easy
./eval_fresh.sh MH_03_medium
```

**功能：**
- 从ZIP提取Ground Truth
- 运行VIO测试（UWB关闭）
- 运行VIR-SLAM测试（UWB开启）
- 转换轨迹为TUM格式
- 创建评估目录：`~/vir_slam_evaluation_YYYYMMDD_HHMMSS/`

**输出：**
```
~/vir_slam_evaluation_20260106_HHMMSS/
├── raw_data/
│   ├── vio_raw.txt          # VIO原始输出
│   └── vir_raw.txt          # VIR原始输出
├── trajectories/
│   ├── gt_MH_01_easy.txt    # Ground Truth (TUM格式)
│   ├── vio_MH_01_easy.txt   # VIO轨迹
│   └── vir_MH_01_easy.txt   # VIR轨迹
├── evaluations/             # (下一步生成)
└── visualizations/          # (下一步生成)
```

---

### 2. `eval_align.sh` - 对齐和可视化脚本
使用Umeyama算法对齐轨迹并生成可视化

**用法：**
```bash
./eval_align.sh <dataset_name> [eval_directory]
```

**示例：**
```bash
# 自动使用最新的评估目录
./eval_align.sh MH_01_easy

# 或指定评估目录
./eval_align.sh MH_01_easy ~/vir_slam_evaluation_20260106_120854
```

**功能：**
- 使用Umeyama算法计算SE(3)变换（旋转+平移）
- 对齐VIO和VIR轨迹到Ground Truth坐标系
- 生成4个对齐后的可视化
- 计算ATE RMSE和Loop Closure Error
- 保存对齐后的轨迹

**输出：**
```
evaluations/
├── metrics_aligned.txt           # 评估指标
├── vio_MH_01_easy_aligned.txt   # 对齐后的VIO轨迹
└── vir_MH_01_easy_aligned.txt   # 对齐后的VIR轨迹

visualizations/
├── xy_trajectory.png            # XY平面轨迹（全局+局部）
├── xz_trajectory.png            # XZ平面轨迹
├── error_analysis.png           # 位置误差随时间变化
└── uwb_distance.png             # UWB锚点距离分析
```

---

### 3. `enter_container.sh` - 进入容器脚本
启动交互式Docker容器，自动挂载源代码

**用法：**
```bash
./enter_container.sh
```

**功能：**
- 首次运行：复制源代码到 `~/vir_slam_docker/catkin_ws_src/`
- 挂载源代码目录，实现主机与容器双向同步
- 挂载数据集目录
- 进入交互式bash终端

**容器内常用命令：**
```bash
# 查看源代码
cd /root/catkin_ws/src/VIR-SLAM
ls -la

# 查看配置文件
cat src/VIR_VINS/config/euroc/euroc_config.yaml

# 查看launch文件
cat src/VIR_VINS/vir_estimator/launch/vir_euroc.launch

# 退出容器
exit
```

---

### 4. `align_trajectories.py` - 对齐算法核心
Python脚本，实现Umeyama对齐算法和可视化

**直接调用（一般不需要）：**
```bash
python3 align_trajectories.py <eval_directory> <dataset_name>
```

**功能：**
- 实现Umeyama算法（SVD分解求解SE(3)变换）
- 时间同步轨迹（采样1000个时间点）
- 生成4个可视化PNG
- 计算ATE RMSE和Loop Closure Error
- 保存对齐后的轨迹和评估指标

---

## 🔄 完整评估流程

### 单数据集评估
```bash
cd ~/vir_slam_docker

# 步骤1: 运行测试（5-10分钟）
./eval_fresh.sh MH_01_easy

# 步骤2: 对齐和可视化（10-30秒）
./eval_align.sh MH_01_easy

# 步骤3: 查看结果
cat ~/vir_slam_evaluation_*/evaluations/metrics_aligned.txt
xdg-open ~/vir_slam_evaluation_*/visualizations/*.png
```

### 批量评估（推荐）
```bash
cd ~/vir_slam_docker

# 评估所有5个数据集（20-50分钟）
for ds in MH_01_easy MH_02_easy MH_03_medium MH_04_difficult MH_05_difficult; do
  echo "========================================="
  echo "🔄 评估数据集: $ds"
  echo "========================================="
  ./eval_fresh.sh $ds
  if [ $? -eq 0 ]; then
    ./eval_align.sh $ds
    echo "✅ $ds 完成"
  else
    echo "❌ $ds 失败"
  fi
  echo ""
done

# 查看所有结果
for dir in $(ls -dt ~/vir_slam_evaluation_*); do
  echo "📁 $dir"
  cat "$dir/evaluations/metrics_aligned.txt"
  echo ""
done
```

### 只重新生成可视化
如果已有轨迹数据，只想重新生成可视化：

```bash
# 方法1: 使用eval_align.sh
./eval_align.sh MH_01_easy ~/vir_slam_evaluation_20260106_120854

# 方法2: 直接调用Python脚本
python3 align_trajectories.py ~/vir_slam_evaluation_20260106_120854 MH_01_easy
```

---

## 👀 查看源代码

### 方法1: 在主机上查看（推荐）
```bash
# 用VS Code打开
code ~/vir_slam_docker/catkin_ws_src/VIR-SLAM

# 或用文件管理器
xdg-open ~/vir_slam_docker/catkin_ws_src

# 或命令行
cd ~/vir_slam_docker/catkin_ws_src/VIR-SLAM
ls -la
```

### 方法2: 在容器内查看
```bash
# 进入容器
./enter_container.sh

# 在容器内
cd /root/catkin_ws/src/VIR-SLAM
cat src/VIR_VINS/config/euroc/euroc_config.yaml
```

### 重要文件位置
```
catkin_ws_src/VIR-SLAM/
├── src/
│   ├── VIR_VINS/
│   │   ├── config/
│   │   │   └── euroc/
│   │   │       └── euroc_config.yaml        # 主配置文件 ⭐
│   │   │           use_uwb: 0/1             # UWB开关
│   │   │           ranging_weight: 30       # UWB权重
│   │   ├── vir_estimator/
│   │   │   ├── launch/
│   │   │   │   └── vir_euroc.launch        # Launch文件 ⭐
│   │   │   └── src/                        # 核心估计器源代码
│   │   ├── feature_tracker/                # 特征跟踪
│   │   ├── pose_graph/                     # 后端优化
│   │   └── camera_model/                   # 相机模型
│   ├── uwb_pypkg/                          # UWB Python包
│   └── benchmark_publisher/                # 基准测试工具
└── README.md
```

---

## 📊 结果说明

### 评估指标

**1. ATE RMSE (Absolute Trajectory Error)**
- 绝对轨迹误差的均方根
- 测量整体轨迹与Ground Truth的偏差
- 单位：米(m)
- 越小越好

**2. Loop Closure Error**
- 闭环误差（起点到终点的距离）
- 测量长期漂移和累积误差
- 单位：米(m)
- 越小越好

### 可视化文件说明

**1. xy_trajectory.png**
- 左图：XY平面全局轨迹对比
- 右图：局部放大细节
- 显示：Ground Truth（绿）、VIO（蓝）、VIR-SLAM（红）

**2. xz_trajectory.png**
- XZ平面轨迹对比
- 显示高度变化和3D轨迹投影
- 标注起点（绿圆）和终点（红X）

**3. error_analysis.png**
- 位置误差随时间变化曲线
- 蓝色：VIO误差
- 红色：VIR-SLAM误差
- 虚线：平均误差
- 统计框：改进百分比、最大误差

**4. uwb_distance.png**
- 上半部分：到UWB锚点的距离随时间变化
- 下半部分：距离误差（与Ground Truth的差异）
- 统计框：距离误差改进百分比

### 结果解读

**VIO vs VIR-SLAM 对比：**
- **VIO** = VIR-SLAM代码**关闭UWB** (use_uwb=0)
- **VIR** = VIR-SLAM代码**启用UWB** (use_uwb=1)

**关键发现：**
1. **Loop Closure Error**: VIR-SLAM通常有显著改善（5%-40%）
2. **ATE RMSE**: 基本持平，说明UWB主要改善长期漂移而非短期精度
3. **难度影响**: 在更困难的序列上，UWB效果更明显

**示例结果（MH_01_easy）：**
```
ATE RMSE (m):
  VIO:  6.662m
  VIR:  6.664m
  改进: -0.04% (基本相同)

Loop Closure Error (m):
  VIO:  0.807m
  VIR:  0.764m
  改进: +5.39% (显著改善) ✅
```

---

## 🗂️ 目录结构

```
~/vir_slam_docker/
├── eval_fresh.sh                 # 完整测试脚本
├── eval_align.sh                 # 对齐和可视化
├── enter_container.sh            # 进入容器
├── align_trajectories.py         # 对齐算法核心
├── README_COMPLETE.md            # 本文档
├── DOCKER_USAGE.md               # Docker使用指南
├── EVALUATION_README.md          # 技术文档
├── QUICKSTART.md                 # 快速开始
├── catkin_ws_src/                # 挂载的源代码 ⭐
│   └── VIR-SLAM/
└── datasets/
    └── machine_hall/
        ├── MH_01_easy/
        ├── MH_02_easy/
        ├── MH_03_medium/
        ├── MH_04_difficult/
        └── MH_05_difficult/

~/vir_slam_evaluation_YYYYMMDD_HHMMSS/  # 评估结果目录
├── raw_data/                     # 原始ROS输出
├── trajectories/                 # TUM格式轨迹
├── evaluations/                  # 评估指标
│   ├── metrics_aligned.txt       # 对齐后的指标 ⭐
│   ├── vio_*_aligned.txt         # 对齐后的VIO轨迹
│   └── vir_*_aligned.txt         # 对齐后的VIR轨迹
└── visualizations/               # 可视化结果 ⭐
    ├── xy_trajectory.png
    ├── xz_trajectory.png
    ├── error_analysis.png
    └── uwb_distance.png
```

---

## ❓ 常见问题

### Q1: 如何查看某个数据集的结果？
```bash
# 方法1: 查看最新结果
cat $(ls -dt ~/vir_slam_evaluation_* | head -1)/evaluations/metrics_aligned.txt

# 方法2: 查看特定数据集
ls -dt ~/vir_slam_evaluation_* | while read dir; do
  if grep -q "MH_01_easy" "$dir/evaluations/metrics_aligned.txt" 2>/dev/null; then
    cat "$dir/evaluations/metrics_aligned.txt"
  fi
done

# 方法3: 打开可视化
xdg-open ~/vir_slam_evaluation_*/visualizations/xy_trajectory.png
```

### Q2: 评估失败怎么办？
```bash
# 1. 检查Docker容器是否正常
docker ps -a

# 2. 查看日志
docker logs <container_name>

# 3. 手动清理旧容器
docker stop $(docker ps -aq)
docker rm $(docker ps -aq)

# 4. 重新运行
./eval_fresh.sh MH_01_easy
```

### Q3: 如何修改UWB配置？
```bash
# 方法1: 在主机修改（推荐）
code ~/vir_slam_docker/catkin_ws_src/VIR-SLAM/src/VIR_VINS/config/euroc/euroc_config.yaml

# 方法2: 在容器内修改
./enter_container.sh
vi /root/catkin_ws/src/VIR-SLAM/src/VIR_VINS/config/euroc/euroc_config.yaml

# 修改后重新编译（如果需要）
cd /root/catkin_ws
catkin_make
source devel/setup.bash
exit

# 重新运行测试
./eval_fresh.sh MH_01_easy
```

### Q4: 如何只重新生成可视化？
```bash
# 不需要重新运行Docker测试，直接运行对齐脚本
./eval_align.sh MH_01_easy ~/vir_slam_evaluation_20260106_120854

# 或批量重新生成
for dir in ~/vir_slam_evaluation_*; do
  dataset=$(ls $dir/trajectories/gt_*.txt | xargs -n1 basename | sed 's/gt_//' | sed 's/.txt//')
  rm -f $dir/visualizations/*
  python3 align_trajectories.py "$dir" "$dataset"
done
```

### Q5: 如何清理旧的评估结果？
```bash
# 查看所有评估目录
ls -dt ~/vir_slam_evaluation_*

# 删除特定目录
rm -rf ~/vir_slam_evaluation_20260106_120854

# 只保留最新的3个
ls -dt ~/vir_slam_evaluation_* | tail -n +4 | xargs rm -rf

# 清理所有（谨慎！）
rm -rf ~/vir_slam_evaluation_*
```

### Q6: 源代码在哪里？
```bash
# 主机上（推荐查看这里）
~/vir_slam_docker/catkin_ws_src/VIR-SLAM/

# 容器内
/root/catkin_ws/src/VIR-SLAM/

# 两者是实时同步的！
```

### Q7: 坐标对齐的原理？
- VIO/VIR输出的是**相对坐标**（起点为原点）
- Ground Truth是**EuRoC世界坐标**
- 两者有约90°旋转差异
- 使用**Umeyama算法**计算SE(3)变换（旋转R + 平移t）
- 详见：`EVALUATION_README.md`

---

## 📚 更多文档

- **QUICKSTART.md** - 5分钟快速开始
- **EVALUATION_README.md** - 完整技术文档（Umeyama算法、坐标系、故障排除）
- **DOCKER_USAGE.md** - Docker容器使用详解
- **EVALUATION_SUMMARY.md** - 所有数据集评估总结

---

## 🎯 一键命令速查

```bash
# 评估单个数据集
./eval_fresh.sh MH_01_easy && ./eval_align.sh MH_01_easy

# 批量评估全部
for ds in MH_{01,02}_easy MH_03_medium MH_{04,05}_difficult; do 
  ./eval_fresh.sh $ds && ./eval_align.sh $ds
done

# 查看最新结果
cat $(ls -dt ~/vir_slam_evaluation_* | head -1)/evaluations/metrics_aligned.txt

# 查看所有可视化
xdg-open $(ls -dt ~/vir_slam_evaluation_* | head -1)/visualizations/*.png

# 进入容器
./enter_container.sh

# 查看源代码
code ~/vir_slam_docker/catkin_ws_src/VIR-SLAM
```

---

**版本**: 2026-01-06  
**作者**: VIR-SLAM Evaluation System  
**仓库**: https://github.com/MISTLab/VIR-SLAM
