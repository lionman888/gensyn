# Gensyn一键部署脚本

这个仓库包含了用于自动部署Gensyn节点的一键部署脚本。

## 文件说明

- `gensyn_deploy.sh`: 主部署脚本
- `gensyn-monitor/`: 监控脚本文件夹
- `rg-swarm.yaml`: 配置文件
- `run_rl_swarm.sh`: 启动脚本

## 使用方法

### 1. 克隆仓库

```bash
git clone https://github.com/lionman888/gensyn.git
cd gensyn
```

### 2. 赋予脚本执行权限

```bash
chmod +x gensyn_deploy.sh
```

### 3. 以root用户身份执行脚本

```bash
sudo ./gensyn_deploy.sh
```

### 4. 按照脚本提示进行操作

脚本会自动执行以下步骤：

1. 安装所需依赖
2. 复制监控脚本到指定位置
3. 克隆官方仓库
4. 替换配置文件
5. 替换启动脚本
6. 复制证书文件
7. 设置环境并启动程序

## 注意事项

- 脚本必须以root用户身份运行
- 如果已有的swarm.pem证书文件，脚本会自动复制；否则需要手动上传
- 脚本执行完成后，将会在screen会话中运行Gensyn程序
- 使用`screen -r gensyn`可以查看运行状态

## 监控程序

启动Gensyn后，可以运行监控程序来自动管理：

```bash
cd /root/gensyn-monitor
chmod +x gensyn_monitor.sh
./gensyn_monitor.sh
```

## 常见问题

- **Q: 如何检查程序是否正常运行？**
  A: 使用命令 `screen -r gensyn` 查看运行状态。

- **Q: 如何离开screen会话但保持程序运行？**
  A: 按下 `Ctrl+A` 然后按 `D` 键。

- **Q: 证书文件在哪里？**
  A: 证书文件应位于 `/root/rl-swarm/swarm.pem`。如果没有，脚本会提示您上传。 