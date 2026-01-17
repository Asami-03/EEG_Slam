# Docker 容器使用指南

## 快速进入容器（推荐）

```bash
cd ~/vir_slam_docker
./enter_container.sh
```

### 首次运行
- 自动复制源代码到 `~/vir_slam_docker/catkin_ws_src/`
- 挂载源代码目录，实现主机与容器双向同步
- 你可以在主机上用任何编辑器查看/修改代码

### 后续运行
- 直接使用已复制的源代码
- 所有修改会立即在容器内生效

## 挂载目录说明

| 容器内路径 | 主机路径 | 说明 |
|-----------|---------|------|
| `/root/catkin_ws/src` | `~/vir_slam_docker/catkin_ws_src` | VIR-SLAM源代码（可编辑）|
| `/host` | `~/vir_slam_docker` | 评估脚本和工具 |
| `/datasets` | `~/vir_slam_docker/datasets` | EuRoC数据集 |

## 在主机上查看/编辑源代码

### 方法1: VS Code（推荐）
```bash
code ~/vir_slam_docker/catkin_ws_src
```

### 方法2: 文件管理器
```bash
nautilus ~/vir_slam_docker/catkin_ws_src &
# 或
xdg-open ~/vir_slam_docker/catkin_ws_src
```

### 方法3: 命令行
```bash
cd ~/vir_slam_docker/catkin_ws_src/VIR-SLAM
ls -la
cat src/VIR_VINS/config/euroc/euroc_config.yaml
```

## 重要文件位置

### 配置文件
- **EuRoC配置**: `catkin_ws_src/VIR-SLAM/src/VIR_VINS/config/euroc/euroc_config.yaml`
  - `use_uwb: 0/1` - 控制是否启用UWB
  - `ranging_weight: 30` - UWB测距权重
  
- **Launch文件**: `catkin_ws_src/VIR-SLAM/src/VIR_VINS/vir_estimator/launch/vir_euroc.launch`

### 源代码
- **核心估计器**: `catkin_ws_src/VIR-SLAM/src/VIR_VINS/vir_estimator/src/`
- **UWB模块**: `catkin_ws_src/VIR-SLAM/src/uwb_pypkg/`
- **后端优化**: `catkin_ws_src/VIR-SLAM/src/VIR_VINS/pose_graph/`

## 容器内常用操作

### 查看配置
```bash
cd /root/catkin_ws/src/VIR-SLAM
cat src/VIR_VINS/config/euroc/euroc_config.yaml
```

### 修改配置（在主机或容器内都可以）
```bash
# 在容器内
vi src/VIR_VINS/config/euroc/euroc_config.yaml

# 或在主机上
code ~/vir_slam_docker/catkin_ws_src/VIR-SLAM/src/VIR_VINS/config/euroc/euroc_config.yaml
```

### 重新编译（如果修改了源代码）
```bash
cd /root/catkin_ws
catkin_make
source devel/setup.bash
```

### 运行SLAM节点
```bash
source /root/catkin_ws/devel/setup.bash
roslaunch vir_estimator vir_euroc.launch
```

## 其他进入容器的方式

### 方式1: 临时容器（不挂载）
```bash
docker run -it --rm vir_slam:noetic bash
```

### 方式2: 只挂载数据集
```bash
docker run -it --rm \
  -v ~/vir_slam_docker/datasets:/datasets \
  vir_slam:noetic bash
```

### 方式3: 进入正在运行的容器
```bash
# 查看运行中的容器
docker ps

# 进入容器
docker exec -it <container_id_or_name> bash
```

## 常见问题

### Q: 修改后的代码没有生效？
A: 如果修改了C++源代码，需要在容器内重新编译：
```bash
cd /root/catkin_ws
catkin_make
source devel/setup.bash
```

### Q: 如何更新容器内的源代码到主机？
A: 不需要！挂载是双向同步的，容器内的修改会立即反映到主机。

### Q: 如何恢复原始源代码？
A: 删除挂载目录，下次运行会重新复制：
```bash
rm -rf ~/vir_slam_docker/catkin_ws_src
./enter_container.sh
```

### Q: 容器退出后，修改的代码会丢失吗？
A: 不会！代码保存在主机的 `~/vir_slam_docker/catkin_ws_src/` 目录中。

## 提示

1. **避免权限问题**: 挂载目录由Docker守护进程创建，可能需要sudo权限访问
   ```bash
   sudo chown -R $USER:$USER ~/vir_slam_docker/catkin_ws_src
   ```

2. **代码备份**: 在修改重要代码前，建议备份
   ```bash
   cp -r ~/vir_slam_docker/catkin_ws_src ~/vir_slam_docker/catkin_ws_src.backup
   ```

3. **Git版本控制**: 源代码目录保留了.git，可以使用git管理修改
   ```bash
   cd ~/vir_slam_docker/catkin_ws_src/VIR-SLAM
   git status
   git diff
   ```
