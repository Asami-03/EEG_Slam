#!/bin/bash
set -e

# Source ROS1 environment
source /opt/ros/noetic/setup.bash

# Source catkin workspace if it exists
if [ -f /root/catkin_ws/devel/setup.bash ]; then
    source /root/catkin_ws/devel/setup.bash
fi

exec "$@"
