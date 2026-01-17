#!/usr/bin/env python3
"""
轨迹对齐和可视化 - 使用Umeyama算法进行SE(3)对齐
参考: evo工具的对齐方法
"""

import numpy as np
import matplotlib.pyplot as plt
import sys
import os

def load_tum(filename):
    """加载TUM格式轨迹"""
    data = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                parts = line.split()
                if len(parts) >= 8:
                    t = float(parts[0])
                    x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                    data.append([t, x, y, z])
    return np.array(data)

def umeyama_alignment(x, y, with_scale=False):
    """
    Umeyama算法：计算两组3D点之间的相似变换
    x: 源点云 (N, 3)
    y: 目标点云 (N, 3)
    返回: (s, R, t) 尺度、旋转矩阵、平移向量
    
    使得 y ≈ s * R @ x + t
    """
    assert x.shape == y.shape
    n, m = x.shape

    # 计算质心
    mx = x.mean(0)
    my = y.mean(0)

    # 中心化
    xc = x - mx
    yc = y - my

    # 计算尺度
    sx = np.mean(np.sum(xc**2, 1))
    sy = np.mean(np.sum(yc**2, 1))

    # 协方差矩阵
    Sxy = np.dot(yc.T, xc) / n

    # SVD分解
    U, D, Vt = np.linalg.svd(Sxy)
    
    # 计算旋转矩阵
    r = np.linalg.matrix_rank(Sxy)
    S = np.eye(m)
    if r < m:
        # 防止反射
        if np.linalg.det(Sxy) < 0:
            S[m-1, m-1] = -1
    elif np.linalg.det(U) * np.linalg.det(Vt) < 0:
        S[m-1, m-1] = -1
    
    R = U @ S @ Vt

    # 计算尺度
    if with_scale:
        s = np.trace(np.diag(D) @ S) / sx
    else:
        s = 1.0

    # 计算平移
    t = my - s * R @ mx

    return s, R, t

def align_trajectory_umeyama(traj, gt, sample_rate=10):
    """
    使用Umeyama算法对齐轨迹到Ground Truth
    sample_rate: 采样率，避免使用所有点（太慢）
    """
    if len(traj) == 0 or len(gt) == 0:
        return traj, None, None, None
    
    # 时间对齐：找到重叠的时间段
    t_start = max(traj[0, 0], gt[0, 0])
    t_end = min(traj[-1, 0], gt[-1, 0])
    
    # 从GT中采样对应的点
    gt_mask = (gt[:, 0] >= t_start) & (gt[:, 0] <= t_end)
    gt_segment = gt[gt_mask]
    
    # 从traj中采样对应的点
    traj_mask = (traj[:, 0] >= t_start) & (traj[:, 0] <= t_end)
    traj_segment = traj[traj_mask]
    
    # 均匀采样以加速计算
    n_samples = min(len(gt_segment), len(traj_segment), 1000)
    gt_indices = np.linspace(0, len(gt_segment)-1, n_samples, dtype=int)
    traj_indices = np.linspace(0, len(traj_segment)-1, n_samples, dtype=int)
    
    gt_points = gt_segment[gt_indices, 1:4]
    traj_points = traj_segment[traj_indices, 1:4]
    
    # 执行Umeyama对齐
    s, R, t = umeyama_alignment(traj_points, gt_points, with_scale=False)
    
    # 应用变换到整个轨迹
    aligned = traj.copy()
    aligned[:, 1:4] = (s * (R @ traj[:, 1:4].T).T + t)
    
    return aligned, s, R, t

def plot_comparison(eval_dir, dataset):
    """生成对比图 - 只保留对齐后的可视化"""
    gt = load_tum(f"{eval_dir}/trajectories/gt_{dataset}.txt")
    vio = load_tum(f"{eval_dir}/trajectories/vio_{dataset}.txt")
    vir = load_tum(f"{eval_dir}/trajectories/vir_{dataset}.txt")
    
    print("🔧 使用Umeyama算法对齐轨迹...")
    vio_aligned, s_vio, R_vio, t_vio = align_trajectory_umeyama(vio, gt)
    vir_aligned, s_vir, R_vir, t_vir = align_trajectory_umeyama(vir, gt)
    
    print(f"\nVIO对齐参数:")
    print(f"  尺度: {s_vio:.6f}")
    print(f"  旋转矩阵:\n{R_vio}")
    print(f"  平移: {t_vio}")
    
    print(f"\nVIR对齐参数:")
    print(f"  尺度: {s_vir:.6f}")
    print(f"  旋转矩阵:\n{R_vir}")
    print(f"  平移: {t_vir}")
    
    # 保存对齐后的轨迹
    np.savetxt(f"{eval_dir}/trajectories/vio_{dataset}_aligned.txt", vio_aligned, 
               fmt='%.9f %.9f %.9f %.9f')
    np.savetxt(f"{eval_dir}/trajectories/vir_{dataset}_aligned.txt", vir_aligned, 
               fmt='%.9f %.9f %.9f %.9f')
    print(f"\n✅ 对齐后的轨迹已保存")
    
    # 图1: XY平面对齐轨迹对比
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 7))
    
    # 左图：全轨迹
    ax1.plot(gt[:, 1], gt[:, 2], 'g-', linewidth=2.5, alpha=0.6, label='Ground Truth', zorder=1)
    ax1.plot(vio_aligned[:, 1], vio_aligned[:, 2], 'b-', linewidth=1.8, alpha=0.7, label='VIO (VINS-Mono)', zorder=2)
    ax1.plot(vir_aligned[:, 1], vir_aligned[:, 2], 'r-', linewidth=1.8, alpha=0.7, label='VIR-SLAM', zorder=3)
    ax1.scatter(gt[0, 1], gt[0, 2], c='green', s=200, marker='o', edgecolors='black', linewidths=2, label='Start', zorder=5)
    ax1.scatter(gt[-1, 1], gt[-1, 2], c='red', s=200, marker='X', edgecolors='black', linewidths=2, label='End', zorder=5)
    ax1.set_xlabel('X (m)', fontsize=13, fontweight='bold')
    ax1.set_ylabel('Y (m)', fontsize=13, fontweight='bold')
    ax1.set_title('XY Trajectory (Aligned)', fontsize=14, fontweight='bold')
    ax1.legend(fontsize=11, loc='best')
    ax1.grid(True, alpha=0.3)
    ax1.axis('equal')
    
    # 右图：局部放大
    mid_idx = len(gt) // 2
    window = len(gt) // 10
    start_idx = max(0, mid_idx - window)
    end_idx = min(len(gt), mid_idx + window)
    
    ax2.plot(gt[start_idx:end_idx, 1], gt[start_idx:end_idx, 2], 
             'g-', linewidth=2.5, alpha=0.6, label='Ground Truth')
    
    t_start, t_end = gt[start_idx, 0], gt[end_idx, 0]
    vio_mask = (vio_aligned[:, 0] >= t_start) & (vio_aligned[:, 0] <= t_end)
    vir_mask = (vir_aligned[:, 0] >= t_start) & (vir_aligned[:, 0] <= t_end)
    
    if vio_mask.any():
        ax2.plot(vio_aligned[vio_mask, 1], vio_aligned[vio_mask, 2], 
                'b-', linewidth=2, alpha=0.7, label='VIO')
    if vir_mask.any():
        ax2.plot(vir_aligned[vir_mask, 1], vir_aligned[vir_mask, 2], 
                'r-', linewidth=2, alpha=0.7, label='VIR-SLAM')
    
    ax2.set_xlabel('X (m)', fontsize=13, fontweight='bold')
    ax2.set_ylabel('Y (m)', fontsize=13, fontweight='bold')
    ax2.set_title('Local Detail', fontsize=14, fontweight='bold')
    ax2.legend(fontsize=11, loc='best')
    ax2.grid(True, alpha=0.3)
    ax2.axis('equal')
    
    plt.suptitle(f'Trajectory Comparison: {dataset}', fontsize=16, fontweight='bold')
    plt.tight_layout()
    plt.savefig(f"{eval_dir}/visualizations/xy_trajectory.png", dpi=150, bbox_inches='tight')
    print(f"✅ 保存: xy_trajectory.png")
    plt.close()
    
    # 图2: 误差随时间变化
    print("📊 生成误差分析图...")
    
    min_len = min(len(gt), len(vio_aligned), len(vir_aligned))
    vio_errors = []
    vir_errors = []
    timestamps = []
    
    for i in range(0, min_len, max(1, min_len // 500)):
        gt_idx = min(i * len(gt) // min_len, len(gt)-1)
        vio_idx = min(i * len(vio_aligned) // min_len, len(vio_aligned)-1)
        vir_idx = min(i * len(vir_aligned) // min_len, len(vir_aligned)-1)
        
        vio_err = np.linalg.norm(gt[gt_idx, 1:4] - vio_aligned[vio_idx, 1:4])
        vir_err = np.linalg.norm(gt[gt_idx, 1:4] - vir_aligned[vir_idx, 1:4])
        
        vio_errors.append(vio_err)
        vir_errors.append(vir_err)
        timestamps.append(i)
    
    fig, ax = plt.subplots(figsize=(14, 6))
    
    ax.plot(timestamps, vio_errors, 'b-', linewidth=2, alpha=0.7, label='VIO Error')
    ax.plot(timestamps, vir_errors, 'r-', linewidth=2, alpha=0.7, label='VIR-SLAM Error')
    ax.fill_between(timestamps, vio_errors, alpha=0.3, color='blue')
    ax.fill_between(timestamps, vir_errors, alpha=0.3, color='red')
    
    vio_mean = np.mean(vio_errors)
    vir_mean = np.mean(vir_errors)
    
    ax.axhline(vio_mean, color='blue', linestyle='--', linewidth=1.5, alpha=0.5, label=f'VIO Mean: {vio_mean:.3f}m')
    ax.axhline(vir_mean, color='red', linestyle='--', linewidth=1.5, alpha=0.5, label=f'VIR Mean: {vir_mean:.3f}m')
    
    ax.set_xlabel('Trajectory Progress', fontsize=13, fontweight='bold')
    ax.set_ylabel('Position Error (m)', fontsize=13, fontweight='bold')
    ax.set_title(f'Position Error vs Ground Truth: {dataset}', fontsize=15, fontweight='bold')
    ax.legend(fontsize=11, loc='best')
    ax.grid(True, alpha=0.3)
    
    improve = (vio_mean - vir_mean) / vio_mean * 100
    stats_text = f'Improvement: {improve:+.2f}%\n'
    stats_text += f'VIO Max: {max(vio_errors):.3f}m\n'
    stats_text += f'VIR Max: {max(vir_errors):.3f}m'
    
    ax.text(0.02, 0.98, stats_text, transform=ax.transAxes,
           fontsize=12, verticalalignment='top',
           bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8))
    
    plt.tight_layout()
    plt.savefig(f"{eval_dir}/visualizations/error_analysis.png", dpi=150, bbox_inches='tight')
    print(f"✅ 保存: error_analysis.png")
    plt.close()
    
    # 图3: XZ平面轨迹
    print("📊 生成XZ平面轨迹图...")
    fig, ax = plt.subplots(figsize=(14, 7))
    
    ax.plot(gt[:, 1], gt[:, 3], 'g-', linewidth=2.5, alpha=0.6, label='Ground Truth', zorder=1)
    ax.plot(vio_aligned[:, 1], vio_aligned[:, 3], 'b-', linewidth=1.8, alpha=0.7, label='VIO (VINS-Mono)', zorder=2)
    ax.plot(vir_aligned[:, 1], vir_aligned[:, 3], 'r-', linewidth=1.8, alpha=0.7, label='VIR-SLAM', zorder=3)
    ax.scatter(gt[0, 1], gt[0, 3], c='green', s=200, marker='o', edgecolors='black', linewidths=2, label='Start', zorder=5)
    ax.scatter(gt[-1, 1], gt[-1, 3], c='red', s=200, marker='X', edgecolors='black', linewidths=2, label='End', zorder=5)
    
    ax.set_xlabel('X (m)', fontsize=13, fontweight='bold')
    ax.set_ylabel('Z (m)', fontsize=13, fontweight='bold')
    ax.set_title(f'XZ Plane Trajectory (Aligned): {dataset}', fontsize=15, fontweight='bold')
    ax.legend(fontsize=11, loc='best')
    ax.grid(True, alpha=0.3)
    ax.axis('equal')
    
    plt.tight_layout()
    plt.savefig(f"{eval_dir}/visualizations/xz_trajectory.png", dpi=150, bbox_inches='tight')
    print(f"✅ 保存: xz_trajectory.png")
    plt.close()
    
    # 图4: 与UWB锚点的距离对比
    print("📊 生成UWB锚点距离对比图...")
    
    # UWB锚点位置 (假设在原点或GT起始点)
    uwb_anchor = gt[0, 1:4]  # 使用GT起始点作为UWB锚点
    
    # 计算每个时刻到UWB锚点的距离
    gt_dist_uwb = np.linalg.norm(gt[:, 1:4] - uwb_anchor, axis=1)
    vio_dist_uwb = np.linalg.norm(vio_aligned[:, 1:4] - uwb_anchor, axis=1)
    vir_dist_uwb = np.linalg.norm(vir_aligned[:, 1:4] - uwb_anchor, axis=1)
    
    # 计算采样索引
    gt_indices = np.linspace(0, len(gt)-1, min(len(gt), 1000), dtype=int)
    vio_indices = np.linspace(0, len(vio_aligned)-1, min(len(vio_aligned), 1000), dtype=int)
    vir_indices = np.linspace(0, len(vir_aligned)-1, min(len(vir_aligned), 1000), dtype=int)
    
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 10))
    
    # 子图1: 距离随时间变化
    ax1.plot(gt_indices, gt_dist_uwb[gt_indices], 'g-', linewidth=2, alpha=0.6, label='Ground Truth', zorder=1)
    ax1.plot(vio_indices, vio_dist_uwb[vio_indices], 'b-', linewidth=1.5, alpha=0.7, label='VIO', zorder=2)
    ax1.plot(vir_indices, vir_dist_uwb[vir_indices], 'r-', linewidth=1.5, alpha=0.7, label='VIR-SLAM', zorder=3)
    
    ax1.set_xlabel('Trajectory Progress', fontsize=12, fontweight='bold')
    ax1.set_ylabel('Distance to UWB Anchor (m)', fontsize=12, fontweight='bold')
    ax1.set_title('Distance to UWB Anchor Over Time', fontsize=14, fontweight='bold')
    ax1.legend(fontsize=11, loc='best')
    ax1.grid(True, alpha=0.3)
    
    # 子图2: 与GT的距离差异
    min_len = min(len(gt_dist_uwb), len(vio_dist_uwb), len(vir_dist_uwb))
    
    vio_dist_diff = []
    vir_dist_diff = []
    progress = []
    
    for i in range(0, min_len, max(1, min_len // 500)):
        gt_idx = min(i * len(gt_dist_uwb) // min_len, len(gt_dist_uwb)-1)
        vio_idx = min(i * len(vio_dist_uwb) // min_len, len(vio_dist_uwb)-1)
        vir_idx = min(i * len(vir_dist_uwb) // min_len, len(vir_dist_uwb)-1)
        
        vio_diff = abs(vio_dist_uwb[vio_idx] - gt_dist_uwb[gt_idx])
        vir_diff = abs(vir_dist_uwb[vir_idx] - gt_dist_uwb[gt_idx])
        
        vio_dist_diff.append(vio_diff)
        vir_dist_diff.append(vir_diff)
        progress.append(i)
    
    ax2.plot(progress, vio_dist_diff, 'b-', linewidth=2, alpha=0.7, label='VIO Distance Error')
    ax2.plot(progress, vir_dist_diff, 'r-', linewidth=2, alpha=0.7, label='VIR-SLAM Distance Error')
    ax2.fill_between(progress, vio_dist_diff, alpha=0.3, color='blue')
    ax2.fill_between(progress, vir_dist_diff, alpha=0.3, color='red')
    
    vio_mean_diff = np.mean(vio_dist_diff)
    vir_mean_diff = np.mean(vir_dist_diff)
    
    ax2.axhline(vio_mean_diff, color='blue', linestyle='--', linewidth=1.5, alpha=0.5, 
                label=f'VIO Mean: {vio_mean_diff:.3f}m')
    ax2.axhline(vir_mean_diff, color='red', linestyle='--', linewidth=1.5, alpha=0.5, 
                label=f'VIR Mean: {vir_mean_diff:.3f}m')
    
    ax2.set_xlabel('Trajectory Progress', fontsize=12, fontweight='bold')
    ax2.set_ylabel('Distance Error (m)', fontsize=12, fontweight='bold')
    ax2.set_title('Position Difference vs Ground Truth', fontsize=14, fontweight='bold')
    ax2.legend(fontsize=11, loc='best')
    ax2.grid(True, alpha=0.3)
    
    # 添加统计信息
    dist_improve = (vio_mean_diff - vir_mean_diff) / vio_mean_diff * 100
    stats_text = f'Distance Error Improvement: {dist_improve:+.2f}%\n'
    stats_text += f'VIO Max Diff: {max(vio_dist_diff):.3f}m\n'
    stats_text += f'VIR Max Diff: {max(vir_dist_diff):.3f}m'
    
    ax2.text(0.02, 0.98, stats_text, transform=ax2.transAxes,
            fontsize=11, verticalalignment='top',
            bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8))
    
    plt.suptitle(f'UWB Anchor Distance Analysis: {dataset}', fontsize=16, fontweight='bold')
    plt.tight_layout()
    plt.savefig(f"{eval_dir}/visualizations/uwb_distance.png", dpi=150, bbox_inches='tight')
    print(f"✅ 保存: uwb_distance.png")
    plt.close()
    
    # 计算对齐后的误差
    print("\n📊 计算对齐后的评估指标...")
    
    def compute_ate(gt, est):
        """计算ATE"""
        min_len = min(len(gt), len(est))
        errors = []
        for i in range(0, min_len, max(1, min_len // 100)):
            gt_pos = gt[min(i, len(gt)-1), 1:4]
            est_pos = est[min(i, len(est)-1), 1:4]
            error = np.linalg.norm(gt_pos - est_pos)
            errors.append(error)
        return np.sqrt(np.mean(np.array(errors)**2))
    
    def compute_loop_error(traj):
        """计算环路闭合误差"""
        if len(traj) < 2:
            return None
        return np.linalg.norm(traj[0, 1:4] - traj[-1, 1:4])
    
    vio_ate = compute_ate(gt, vio_aligned)
    vir_ate = compute_ate(gt, vir_aligned)
    vio_loop = compute_loop_error(vio_aligned)
    vir_loop = compute_loop_error(vir_aligned)
    
    print(f"\n对齐后的评估结果:")
    print(f"  ATE RMSE:")
    print(f"    VIO:  {vio_ate:.4f} m")
    print(f"    VIR:  {vir_ate:.4f} m")
    print(f"    改进: {(vio_ate-vir_ate)/vio_ate*100:+.2f}%")
    print(f"\n  Loop Closure Error:")
    print(f"    VIO:  {vio_loop:.4f} m")
    print(f"    VIR:  {vir_loop:.4f} m")
    print(f"    改进: {(vio_loop-vir_loop)/vio_loop*100:+.2f}%")
    
    # 保存评估结果
    with open(f"{eval_dir}/evaluations/metrics_aligned.txt", 'w') as f:
        f.write(f"VIR-SLAM 评估结果（Umeyama对齐后）: {dataset}\n")
        f.write("="*60 + "\n\n")
        f.write(f"对齐方法: Umeyama算法 (SE(3)变换)\n\n")
        f.write(f"ATE RMSE (m):\n")
        f.write(f"  VIO:  {vio_ate:.4f}\n")
        f.write(f"  VIR:  {vir_ate:.4f}\n")
        f.write(f"  改进: {(vio_ate-vir_ate)/vio_ate*100:+.2f}%\n\n")
        f.write(f"Loop Closure Error (m):\n")
        f.write(f"  VIO:  {vio_loop:.4f}\n")
        f.write(f"  VIR:  {vir_loop:.4f}\n")
        f.write(f"  改进: {(vio_loop-vir_loop)/vio_loop*100:+.2f}%\n")

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 align_trajectories.py <eval_dir> <dataset>")
        sys.exit(1)
    
    eval_dir = sys.argv[1]
    dataset = sys.argv[2]
    
    print(f"🎯 使用Umeyama算法对齐轨迹: {dataset}")
    print("")
    
    os.makedirs(f"{eval_dir}/visualizations", exist_ok=True)
    os.makedirs(f"{eval_dir}/evaluations", exist_ok=True)
    
    plot_comparison(eval_dir, dataset)
    
    print("")
    print("✅ 轨迹对齐和评估完成！")

if __name__ == "__main__":
    main()
