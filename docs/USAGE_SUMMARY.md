# VIR-SLAM 评估系统 - 快速参考

## 🎯 核心脚本（4个）

| 脚本 | 用途 | 耗时 |
|------|------|------|
| `eval_fresh.sh <dataset>` | 运行Docker测试生成轨迹 | 5-10分钟 |
| `eval_align.sh <dataset>` | 对齐轨迹并生成可视化 | 10-30秒 |
| `enter_container.sh` | 进入容器查看源代码 | 立即 |
| `align_trajectories.py` | 对齐算法核心（自动调用） | - |

## ⚡ 常用命令

### 评估单个数据集
```bash
./eval_fresh.sh MH_01_easy && ./eval_align.sh MH_01_easy
```

### 批量评估全部（20-50分钟）
```bash
for ds in MH_01_easy MH_02_easy MH_03_medium MH_04_difficult MH_05_difficult; do
  ./eval_fresh.sh $ds && ./eval_align.sh $ds
done
```

### 查看源代码
```bash
# 方法1: 主机上用VS Code
code ~/vir_slam_docker/catkin_ws_src/VIR-SLAM

# 方法2: 进入容器
./enter_container.sh
```

### 查看结果
```bash
# 查看最新评估指标
cat $(ls -dt ~/vir_slam_evaluation_* | head -1)/evaluations/metrics_aligned.txt

# 打开可视化
xdg-open $(ls -dt ~/vir_slam_evaluation_* | head -1)/visualizations/*.png
```

## 📊 输出文件（每个数据集）

```
~/vir_slam_evaluation_YYYYMMDD_HHMMSS/
├── evaluations/
│   └── metrics_aligned.txt              # 评估指标 ⭐
└── visualizations/                      # 4个可视化PNG ⭐
    ├── xy_trajectory.png                # XY平面轨迹
    ├── xz_trajectory.png                # XZ平面轨迹  
    ├── error_analysis.png               # 位置误差分析
    └── uwb_distance.png                 # UWB距离分析
```

## 🗂️ 源代码位置

- **主机**: `~/vir_slam_docker/catkin_ws_src/VIR-SLAM/`
- **容器**: `/root/catkin_ws/src/VIR-SLAM/`
- **配置**: `src/VIR_VINS/config/euroc/euroc_config.yaml`

## 📚 完整文档

- **README_COMPLETE.md** - 完整使用指南（本文档的详细版）
- **EVALUATION_README.md** - 技术文档（Umeyama算法、坐标系）
- **DOCKER_USAGE.md** - Docker容器详解
- **QUICKSTART.md** - 5分钟快速开始

## ❓ 问题？

1. 评估失败 → 查看 `README_COMPLETE.md` Q2
2. 修改配置 → 查看 `README_COMPLETE.md` Q3
3. 重新生成可视化 → 查看 `README_COMPLETE.md` Q4
4. 坐标对齐原理 → 查看 `EVALUATION_README.md`
