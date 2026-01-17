# VIR-SLAM 评估快速指南

## 🚀 一键评估

```bash
# 评估单个数据集（推荐先测试）
./eval_fresh.sh MH_01_easy && ./eval_align.sh MH_01_easy

# 评估所有数据集
for ds in MH_01_easy MH_02_easy MH_03_medium MH_04_difficult MH_05_difficult; do
    ./eval_fresh.sh $ds && ./eval_align.sh $ds
done
```

## 📊 查看结果

```bash
# 查看评估指标
cat ~/vir_slam_evaluation_*/evaluations/metrics_aligned.txt

# 查看可视化（对齐前后对比）
xdg-open ~/vir_slam_evaluation_*/visualizations/trajectory_aligned.png
```

## 📁 核心文件

- `eval_fresh.sh` - 运行Docker测试（GT + VIO + VIR）
- `align_trajectories.py` - Umeyama对齐 + 生成可视化
- `eval_align.sh` - 快速对齐已有数据

## 💡 工作流程

```
1. eval_fresh.sh
   ├── 提取Ground Truth (从ZIP)
   ├── 运行VIO测试 (use_uwb=0)
   └── 运行VIR测试 (use_uwb=1)

2. eval_align.sh
   ├── Umeyama算法对齐坐标系
   ├── 计算ATE和Loop Error
   └── 生成4张可视化图表
```

## 📈 评估指标说明

- **Loop Closure Error**: 起点-终点距离（越小越好）
- **ATE RMSE**: 与Ground Truth的平均误差（越小越好）

---

详细文档：`EVALUATION_README.md`
