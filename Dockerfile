# 基于ROS1 Noetic
FROM ros:noetic-robot

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=noetic

# 安装基础依赖
RUN apt-get update && apt-get install -y \
    git \
    wget \
    vim \
    tmux \
    python3-pip \
    python3-catkin-tools \
    ros-noetic-cv-bridge \
    ros-noetic-image-transport \
    ros-noetic-tf \
    ros-noetic-tf2-ros \
    ros-noetic-pcl-ros \
    ros-noetic-rviz \
    ros-noetic-usb-cam \
    && rm -rf /var/lib/apt/lists/*

# 安装Ceres Solver依赖和编译
RUN apt-get update && apt-get install -y \
    libgoogle-glog-dev \
    libgflags-dev \
    libatlas-base-dev \
    libsuitesparse-dev \
    && rm -rf /var/lib/apt/lists/*

# 从源码编译Ceres Solver（使用1.14.0版本以兼容VIR-SLAM）
RUN cd /tmp && \
    git clone https://ceres-solver.googlesource.com/ceres-solver && \
    cd ceres-solver && \
    git checkout 1.14.0 && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) && \
    make install && \
    cd / && rm -rf /tmp/ceres-solver

# 安装GTSAM
RUN apt-get update && apt-get install -y \
    software-properties-common \
    && add-apt-repository ppa:borglab/gtsam-release-4.2 -y \
    && apt-get update \
    && apt-get install -y libgtsam-dev libgtsam-unstable-dev \
    && rm -rf /var/lib/apt/lists/*

# 安装其他依赖
RUN apt-get update && apt-get install -y \
    libeigen3-dev \
    libboost-all-dev \
    libopencv-dev \
    && rm -rf /var/lib/apt/lists/*

# 创建工作空间
RUN mkdir -p /root/catkin_ws/src
WORKDIR /root/catkin_ws

# 克隆VIR-SLAM
RUN cd src && git clone https://github.com/MISTLab/VIR-SLAM.git

# 初始化catkin工作空间
RUN /bin/bash -c "source /opt/ros/noetic/setup.bash && \
    catkin init && \
    catkin config --extend /opt/ros/noetic && \
    catkin config --cmake-args -DCMAKE_BUILD_TYPE=Release"

# 注释掉rosdep步骤，所有依赖都已手动安装
# RUN apt-get update || true && \
#     (rosdep update || echo "rosdep update failed, continuing...") && \
#     (rosdep install --from-paths src --ignore-src -r -y || echo "rosdep install failed, continuing...") && \
#     rm -rf /var/lib/apt/lists/*

# 修复camera_model的OpenCV 4兼容性
RUN cd /root/catkin_ws/src/VIR-SLAM/src/VIR_VINS/camera_model && \
    find . -type f \( -name "*.cc" -o -name "*.cpp" -o -name "*.h" \) -exec sed -i \
        -e 's/CV_GRAY2RGB/cv::COLOR_GRAY2RGB/g' \
        -e 's/CV_GRAY2BGR/cv::COLOR_GRAY2BGR/g' \
        -e 's/CV_BGR2GRAY/cv::COLOR_BGR2GRAY/g' \
        -e 's/CV_AA/cv::LINE_AA/g' \
        -e 's/CV_CALIB_CB_ADAPTIVE_THRESH/cv::CALIB_CB_ADAPTIVE_THRESH/g' \
        -e 's/CV_CALIB_CB_NORMALIZE_IMAGE/cv::CALIB_CB_NORMALIZE_IMAGE/g' \
        -e 's/CV_CALIB_CB_FILTER_QUADS/cv::CALIB_CB_FILTER_QUADS/g' \
        -e 's/CV_CALIB_CB_FAST_CHECK/cv::CALIB_CB_FAST_CHECK/g' \
        -e 's/CV_ADAPTIVE_THRESH_MEAN_C/cv::ADAPTIVE_THRESH_MEAN_C/g' \
        -e 's/CV_THRESH_BINARY_INV/cv::THRESH_BINARY_INV/g' \
        -e 's/CV_THRESH_BINARY/cv::THRESH_BINARY/g' \
        -e 's/CV_SHAPE_CROSS/cv::MORPH_CROSS/g' \
        -e 's/CV_SHAPE_RECT/cv::MORPH_RECT/g' \
        -e 's/CV_TERMCRIT_EPS/cv::TermCriteria::EPS/g' \
        -e 's/CV_TERMCRIT_ITER/cv::TermCriteria::MAX_ITER/g' \
        -e 's/CV_RETR_CCOMP/cv::RETR_CCOMP/g' \
        -e 's/CV_CHAIN_APPROX_SIMPLE/cv::CHAIN_APPROX_SIMPLE/g' \
        {} +

# 编译工作空间（允许部分包失败）
RUN /bin/bash -c "source /opt/ros/noetic/setup.bash && \
    catkin build --continue-on-failure || true"

# 设置环境
RUN echo "source /opt/ros/noetic/setup.bash" >> ~/.bashrc && \
    echo "source /root/catkin_ws/devel/setup.bash" >> ~/.bashrc

# 安装Python依赖：evo评估工具 + pyserial (UWB串口通信)
RUN pip3 install evo pyserial --upgrade --no-cache-dir

# 创建数据集目录
RUN mkdir -p /root/datasets/euroc

# 设置入口点
COPY scripts/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

CMD ["bash"]
