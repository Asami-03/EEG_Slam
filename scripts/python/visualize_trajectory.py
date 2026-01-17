#!/usr/bin/env python3
"""
Visualize VIR-SLAM trajectory results
Usage: python3 visualize_trajectory.py vins_result_no_loop.csv
"""

import sys
import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D

def parse_vins_csv(filename):
    """Parse VINS trajectory CSV file"""
    timestamps = []
    positions = []
    
    try:
        with open(filename, 'r') as f:
            for line in f:
                if line.strip():
                    parts = line.strip().split(',')
                    if len(parts) >= 4:
                        # Format: timestamp, x, y, z, qx, qy, qz, qw
                        timestamps.append(float(parts[0]))
                        x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                        positions.append([x, y, z])
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found!")
        sys.exit(1)
    
    if not positions:
        print("Warning: No trajectory data found in file!")
        return None, None
    
    return np.array(timestamps), np.array(positions)

def plot_trajectory(timestamps, positions):
    """Plot 3D trajectory"""
    if positions is None or len(positions) == 0:
        print("No data to plot!")
        return
    
    fig = plt.figure(figsize=(15, 10))
    
    # 3D trajectory plot
    ax1 = fig.add_subplot(221, projection='3d')
    ax1.plot(positions[:, 0], positions[:, 1], positions[:, 2], 'b-', linewidth=2)
    ax1.scatter(positions[0, 0], positions[0, 1], positions[0, 2], 
                c='g', s=100, marker='o', label='Start')
    ax1.scatter(positions[-1, 0], positions[-1, 1], positions[-1, 2], 
                c='r', s=100, marker='x', label='End')
    ax1.set_xlabel('X (m)')
    ax1.set_ylabel('Y (m)')
    ax1.set_zlabel('Z (m)')
    ax1.set_title('3D Trajectory')
    ax1.legend()
    ax1.grid(True)
    
    # Top view (X-Y)
    ax2 = fig.add_subplot(222)
    ax2.plot(positions[:, 0], positions[:, 1], 'b-', linewidth=2)
    ax2.scatter(positions[0, 0], positions[0, 1], c='g', s=100, marker='o', label='Start')
    ax2.scatter(positions[-1, 0], positions[-1, 1], c='r', s=100, marker='x', label='End')
    ax2.set_xlabel('X (m)')
    ax2.set_ylabel('Y (m)')
    ax2.set_title('Top View (X-Y)')
    ax2.legend()
    ax2.grid(True)
    ax2.axis('equal')
    
    # Side view (X-Z)
    ax3 = fig.add_subplot(223)
    ax3.plot(positions[:, 0], positions[:, 2], 'b-', linewidth=2)
    ax3.scatter(positions[0, 0], positions[0, 2], c='g', s=100, marker='o', label='Start')
    ax3.scatter(positions[-1, 0], positions[-1, 2], c='r', s=100, marker='x', label='End')
    ax3.set_xlabel('X (m)')
    ax3.set_ylabel('Z (m)')
    ax3.set_title('Side View (X-Z)')
    ax3.legend()
    ax3.grid(True)
    
    # Position over time
    ax4 = fig.add_subplot(224)
    if timestamps is not None and len(timestamps) > 0:
        t_rel = timestamps - timestamps[0]
        ax4.plot(t_rel, positions[:, 0], 'r-', label='X', linewidth=2)
        ax4.plot(t_rel, positions[:, 1], 'g-', label='Y', linewidth=2)
        ax4.plot(t_rel, positions[:, 2], 'b-', label='Z', linewidth=2)
        ax4.set_xlabel('Time (s)')
    else:
        ax4.plot(positions[:, 0], 'r-', label='X', linewidth=2)
        ax4.plot(positions[:, 1], 'g-', label='Y', linewidth=2)
        ax4.plot(positions[:, 2], 'b-', label='Z', linewidth=2)
        ax4.set_xlabel('Frame')
    ax4.set_ylabel('Position (m)')
    ax4.set_title('Position vs Time')
    ax4.legend()
    ax4.grid(True)
    
    plt.tight_layout()
    
    # Print statistics
    total_distance = np.sum(np.linalg.norm(np.diff(positions, axis=0), axis=1))
    print(f"\n=== Trajectory Statistics ===")
    print(f"Total points: {len(positions)}")
    print(f"Start position: ({positions[0, 0]:.3f}, {positions[0, 1]:.3f}, {positions[0, 2]:.3f})")
    print(f"End position: ({positions[-1, 0]:.3f}, {positions[-1, 1]:.3f}, {positions[-1, 2]:.3f})")
    print(f"Total distance: {total_distance:.3f} m")
    if timestamps is not None and len(timestamps) > 1:
        duration = timestamps[-1] - timestamps[0]
        print(f"Duration: {duration:.3f} s")
        print(f"Average speed: {total_distance/duration:.3f} m/s")
    
    plt.show()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 visualize_trajectory.py <trajectory_csv_file>")
        print("Example: python3 visualize_trajectory.py vins_result_no_loop.csv")
        sys.exit(1)
    
    filename = sys.argv[1]
    print(f"Loading trajectory from: {filename}")
    
    timestamps, positions = parse_vins_csv(filename)
    plot_trajectory(timestamps, positions)
