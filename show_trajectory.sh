#!/bin/bash
# Quick script to extract and visualize VIR-SLAM results

echo "🎯 VIR-SLAM Results Visualization"
echo "=================================="

# 1. Copy trajectory from container
echo "📁 Copying trajectory file from container..."
docker cp vir_slam_dev:/tmp/vins_result_no_loop.csv/vins_result_no_loop.csv ./vins_result_no_loop.csv 2>/dev/null

if [ -f "./vins_result_no_loop.csv" ]; then
    FILE_SIZE=$(wc -l < ./vins_result_no_loop.csv)
    echo "✅ Trajectory file copied: $FILE_SIZE lines"
    
    if [ "$FILE_SIZE" -gt 0 ]; then
        echo "📊 Visualizing trajectory..."
        python3 visualize_trajectory.py vins_result_no_loop.csv
    else
        echo "❌ Trajectory file is empty!"
        echo "💡 VIR-SLAM may not have initialized successfully."
        echo "   Check if there was enough motion and features in the data."
    fi
else
    echo "❌ Could not find trajectory file!"
    echo "💡 Make sure VIR-SLAM has processed a bag file first."
fi
