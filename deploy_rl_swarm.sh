#!/bin/bash
set -e

echo "=================================================================="
echo "         RL Swarm 一键部署脚本 (完整版)"
echo "=================================================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
if [ "$EUID" -eq 0 ]; then
    print_error "请不要使用root用户运行此脚本"
    exit 1
fi

print_status "开始一键部署 RL Swarm..."

# 1. 更新系统
print_status "更新系统包..."
sudo apt update && sudo apt upgrade -y

# 2. 安装基础依赖
print_status "安装基础系统依赖..."
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    git \
    curl \
    wget \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    unzip \
    htop \
    screen \
    tmux \
    vim \
    nano

# 3. 安装 Node.js (LTS版本)
print_status "安装 Node.js..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
else
    print_warning "Node.js 已存在: $(node -v)"
fi

# 4. 安装 Yarn
print_status "安装 Yarn..."
if ! command -v yarn &> /dev/null; then
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    sudo apt update && sudo apt install -y yarn
else
    print_warning "Yarn 已存在: $(yarn -v)"
fi

# 5. 安装 ngrok
print_status "安装 ngrok..."
if ! command -v ngrok &> /dev/null; then
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | \
        sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | \
        sudo tee /etc/apt/sources.list.d/ngrok.list
    sudo apt update && sudo apt install -y ngrok
else
    print_warning "ngrok 已存在"
fi

# 6. 检测GPU支持
print_status "检测GPU支持..."
if command -v nvidia-smi &> /dev/null; then
    print_status "检测到 NVIDIA GPU"
    GPU_SUPPORT=true
    # 安装CUDA工具包 (可选)
    sudo apt install -y nvidia-cuda-toolkit 2>/dev/null || true
else
    print_warning "未检测到 NVIDIA GPU，将使用 CPU 模式"
    GPU_SUPPORT=false
fi

# 7. 升级pip
print_status "升级 pip..."
python3 -m pip install --upgrade pip

# 8. 克隆项目
print_status "克隆 RL Swarm 项目..."
cd /tmp
if [ -d "rl-swarm" ]; then
    print_warning "rl-swarm 目录已存在，删除旧版本..."
    rm -rf rl-swarm
fi
git clone https://github.com/gensyn-ai/rl-swarm.git
cd rl-swarm

# 9. 创建Python虚拟环境
print_status "创建 Python 虚拟环境..."
python3 -m venv venv
source venv/bin/activate

# 10. 安装 PyTorch
print_status "安装 PyTorch..."
if [ "$GPU_SUPPORT" = true ]; then
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
else
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
fi

# 11. 安装核心Python依赖
print_status "安装核心 Python 依赖..."
pip install --upgrade pip setuptools wheel
pip install huggingface_hub  # 重要依赖

# 12. 安装项目特定依赖
print_status "安装项目依赖..."
if [ "$GPU_SUPPORT" = true ]; then
    pip install -r requirements-gpu.txt
    print_status "安装 flash-attn (GPU版本)..."
    pip install flash-attn --no-build-isolation || print_warning "flash-attn 安装失败，但不影响运行"
else
    pip install -r requirements-cpu.txt
fi

# 13. 安装Node.js依赖
print_status "安装 Node.js 依赖..."
cd modal-login
yarn install --immutable
print_status "构建前端项目..."
yarn build
cd ..

# 14. 设置权限和目录
print_status "设置权限和创建目录..."
chmod +x run_rl_swarm.sh
mkdir -p logs

# 15. 系统优化
print_status "应用系统优化..."
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf >/dev/null

# 16. 创建便捷启动脚本
print_status "创建便捷启动脚本..."
cat > start_rl_swarm.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
echo "启动 RL Swarm..."
echo "请确保已经在另一个终端运行: ngrok http 3000"
./run_rl_swarm.sh
EOF
chmod +x start_rl_swarm.sh

# 17. 创建ngrok启动脚本
cat > start_ngrok.sh << 'EOF'
#!/bin/bash
echo "启动 ngrok 隧道..."
echo "请确保已配置 ngrok authtoken: ngrok config add-authtoken YOUR_TOKEN"
ngrok http 3000
EOF
chmod +x start_ngrok.sh

print_status "=================================================================="
print_status "                   部署完成!"
print_status "=================================================================="
echo -e "${BLUE}GPU支持:${NC} $GPU_SUPPORT"
echo -e "${BLUE}Node.js版本:${NC} $(node -v 2>/dev/null || echo '未安装')"
echo -e "${BLUE}Python版本:${NC} $(python3 -V)"
echo -e "${BLUE}Yarn版本:${NC} $(yarn -v 2>/dev/null || echo '未安装')"
echo -e "${BLUE}项目路径:${NC} $(pwd)"

print_status ""
print_status "下一步操作:"
print_status "1. 配置 ngrok token:"
print_status "   - 注册账号: https://ngrok.com"
print_status "   - 运行: ngrok config add-authtoken YOUR_TOKEN"
print_status ""
print_status "2. 启动服务:"
print_status "   终端1: ./start_ngrok.sh"
print_status "   终端2: ./start_rl_swarm.sh"
print_status ""
print_status "或者手动启动:"
print_status "   终端1: ngrok http 3000"
print_status "   终端2: source venv/bin/activate && ./run_rl_swarm.sh"

print_status ""
print_status "=================================================================="
print_status "部署脚本执行完毕，准备就绪!"
print_status "=================================================================="
