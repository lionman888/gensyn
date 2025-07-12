# Gensyn RL-Swarm 监控脚本使用说明

## 功能概述

这个监控脚本专门为Ubuntu VPS上的Gensyn RL-Swarm提供全面的监控和自动重启功能。

### 主要功能

1. **P2P连接错误处理** - 自动检测并重启P2P连接问题
2. **运行状态监控** - 实时监控训练进程和Screen会话状态
3. **查分报警系统** - 每小时查分，连续3小时无变化自动重启
4. **名称验证** - 验证动物名称是否在预设名单中
5. **Screen内部重启** - 优先在Screen内部重启，避免重建会话
6. **电报机器人通知** - 自动发送故障和恢复通知

## 部署配置

### 1. 基础环境要求

- Ubuntu VPS
- Python3 (用于API查询和JSON解析)
- Screen (用于会话管理)
- curl (用于API调用)
- 已配置的Gensyn RL-Swarm环境

### 2. 路径配置

脚本默认配置：
- Gensyn目录: `/root/rl-swarm`
- 虚拟环境: `/root/rl-swarm/myenv`
- 日志文件: `/root/rl-swarm/logs/swarm_launcher.log`
- Screen会话: `gensyn`

### 3. 权限设置

```bash
# 给脚本执行权限
chmod +x gensyn_monitor.sh

# 确保可以访问相关目录
sudo chown -R $USER:$USER /root/rl-swarm
```

## 使用方法

### 1. 启动监控

```bash
# 前台运行（测试用）
./gensyn_monitor.sh

# 后台运行（生产环境）
nohup ./gensyn_monitor.sh > monitor_output.log 2>&1 &

# 使用screen运行（推荐）
screen -S gensyn_monitor
./gensyn_monitor.sh
# Ctrl+A+D 分离会话
```

### 2. 查看监控状态

```bash
# 查看监控日志
tail -f monitor.log

# 查看状态文件
cat monitor_state.json

# 查看gensyn日志
tail -f /root/rl-swarm/logs/swarm_launcher.log
```

### 3. 停止监控

```bash
# 如果是前台运行
Ctrl+C

# 如果是后台运行
pkill -f gensyn_monitor.sh
```

## 监控机制详解

### 1. 启动成功检测

监控脚本会检查日志中的启动成功标志：
```
🐱 Hello 🐈 [twitchy ravenous lemur] 🦮 [QmR1xfMT55CkvMmS2qH4aB327ZzkpgwND2YhZt6SiuuoRW]!
```

从中提取动物名称：`twitchy ravenous lemur`

### 2. P2P连接错误处理

检测错误模式：
```
P2PDaemonError('Daemon failed to start in 15.0 seconds')
```

自动重启机制：
- 最多重试5次
- 每次重启后等待30秒
- 在Screen内部重启，不重建会话

### 3. 查分系统

每小时查询一次分数和奖励：
- API地址: `https://dashboard.gensyn.ai/api/v1/peer?name={节点名}`
- 连续3小时分数无变化触发重启
- 设备离线立即触发重启

### 4. 健康检查

每5分钟进行一次健康检查：
- Screen会话存在性
- 核心进程运行状态
- 日志文件完整性
- 训练进度正常性

## Screen会话管理

### 优先级策略

1. **Screen内部重启** (首选)
   - 发送Ctrl+C终止当前进程
   - 清理残留进程
   - 重新激活虚拟环境
   - 重新启动脚本

2. **强制重启Screen会话** (最后手段)
   - 终止整个Screen会话
   - 清理所有相关进程
   - 重新创建Screen会话

### 命令示例

```bash
# 查看Screen会话
screen -list

# 连接到gensyn会话
screen -r gensyn

# 连接到监控会话
screen -r gensyn_monitor

# 在Screen内部发送命令
screen -S gensyn -X stuff "command\n"
```

## 预设名单

脚本包含30个预设的动物名称：
- melodic playful slug
- giant deft giraffe
- strong scaly kingfisher
- enormous hulking crocodile
- ... (完整列表在脚本中)

## 电报机器人配置

配置信息已内置在脚本中：
- Bot Token: `8095489389:AAGYdN-mBpiQdniKgEpFtnzC8wfHZAABE1o`
- Chat ID: `5519262792`

### 通知类型

- 启动成功/失败通知
- P2P连接错误通知
- 分数异常通知
- 设备离线通知
- 名称验证失败通知

## 故障排除

### 1. 常见问题

**Q: 监控脚本启动失败**
A: 检查Python3是否安装，curl是否可用，路径配置是否正确

**Q: 查分功能不工作**
A: 检查网络连接，确认API地址可访问，验证节点名称格式

**Q: Screen会话管理失败**
A: 确认Screen已安装，检查会话权限，验证工作目录

### 2. 调试命令

```bash
# 测试查分功能
python3 -c "
import urllib.parse
import requests
name = 'twitchy ravenous lemur'
url = f'https://dashboard.gensyn.ai/api/v1/peer?name={urllib.parse.quote(name)}'
response = requests.get(url)
print(response.json())
"

# 测试电报机器人
curl -X POST "https://api.telegram.org/bot8095489389:AAGYdN-mBpiQdniKgEpFtnzC8wfHZAABE1o/sendMessage" \
  -d chat_id="5519262792" \
  -d text="测试消息"

# 检查进程状态
ps aux | grep -E "(python.*rgym|yarn.*start|screen)"
```

### 3. 日志文件

- `monitor.log` - 监控脚本主日志
- `monitor_state.json` - 状态持久化文件
- `/root/rl-swarm/logs/swarm_launcher.log` - Gensyn主日志
- `/root/rl-swarm/logs/yarn.log` - Modal服务器日志

## 配置调整

如需调整监控参数，修改脚本中的配置变量：

```bash
# 监控间隔调整
SCORE_CHECK_INTERVAL=3600  # 查分间隔（秒）
HEALTH_CHECK_INTERVAL=300  # 健康检查间隔（秒）
LOG_CHECK_INTERVAL=60      # 日志检查间隔（秒）

# 重启阈值调整
SCORE_UNCHANGED_THRESHOLD=3  # 分数连续无变化次数
MAX_P2P_RETRIES=5           # P2P重试次数
```

## 维护建议

1. **定期检查** - 每天查看监控日志
2. **状态备份** - 定期备份状态文件
3. **性能监控** - 监控VPS资源使用情况
4. **更新维护** - 定期更新脚本和依赖

## 联系支持

如遇到问题，请提供以下信息：
- 监控日志文件
- 系统环境信息
- 错误重现步骤
- VPS配置信息 