#!/bin/bash

# Gensyn一键部署脚本
# 版本：1.0
# 作者：自动生成

set -e  # 遇到错误时退出

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以root用户运行。请使用sudo或切换到root用户。"
        exit 1
    else
        log_info "检测到root用户，继续执行..."
    fi
}

# 检查目录是否存在，如果不存在则创建
check_and_create_dir() {
    local dir=$1
    if [[ ! -d "$dir" ]]; then
        log_info "创建目录: $dir"
        mkdir -p "$dir" || {
            log_error "无法创建目录: $dir"
            return 1
        }
    fi
    return 0
}

# 第一步：安装依赖
install_dependencies() {
    log_info "开始安装系统依赖..."
    
    # 更新包列表并安装系统依赖
    apt update
    apt install -y screen python3.12-venv zip build-essential python3-dev python3-pip wget curl git
    
    # 安装Node.js
    if ! command -v node &> /dev/null; then
        log_info "安装Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt install -y nodejs
    fi
    
    # 安装ngrok
    if ! command -v ngrok &> /dev/null; then
        log_info "安装ngrok..."
        snap install ngrok
    fi
    
    # 清理旧的环境变量
    unset GOROOT 2>/dev/null || true
    unset GOPATH 2>/dev/null || true
    
    if [[ -f ~/.bashrc ]]; then
        sed -i '/export GOROOT/d' ~/.bashrc
        sed -i '/export GOPATH/d' ~/.bashrc
        sed -i '/export PATH.*go/d' ~/.bashrc
    fi
    
    # 安装Go语言
    if ! command -v go &> /dev/null; then
        log_info "安装Go语言..."
        apt install -y golang-go
        
        if ! command -v go &> /dev/null; then
            log_warning "apt安装Go失败，尝试官方二进制包..."
            
            # 使用官方二进制包安装Go
            GO_VERSION="1.22.0"
            GO_ARCHIVE="go${GO_VERSION}.linux-amd64.tar.gz"
            GO_URL="https://golang.org/dl/${GO_ARCHIVE}"
            
            cd /tmp
            wget -q --show-progress "$GO_URL" || {
                log_warning "下载最新版本失败，尝试备用版本..."
                GO_VERSION="1.21.5"
                GO_ARCHIVE="go${GO_VERSION}.linux-amd64.tar.gz"
                GO_URL="https://golang.org/dl/${GO_ARCHIVE}"
                wget -q --show-progress "$GO_URL" || {
                    log_error "下载Go失败"
                    exit 1
                }
            }
            
            # 删除旧安装
            rm -rf /usr/local/go
            
            # 解压安装
            tar -C /usr/local -xzf "$GO_ARCHIVE"
            
            # 添加到PATH
            echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
            export PATH=$PATH:/usr/local/go/bin
        fi
    fi
    
    # 配置Go环境
    echo 'export GOPATH=$HOME/go' >> ~/.bashrc
    echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.bashrc
    export GOPATH=$HOME/go
    export PATH=$PATH:$HOME/go/bin
    
    # 创建Go工作目录
    mkdir -p $HOME/go
    
    # 安装p2pd
    log_info "安装libp2p daemon (p2pd)..."
    
    # 确保Go环境变量已设置
    export GOPATH=$HOME/go
    export PATH=$PATH:$HOME/go/bin:/usr/local/go/bin
    
    # 设置Go代理（针对中国用户）
    echo 'export GOPROXY=https://goproxy.cn,direct' >> ~/.bashrc
    echo 'export GOSUMDB=sum.golang.org' >> ~/.bashrc
    export GOPROXY=https://goproxy.cn,direct
    export GOSUMDB=sum.golang.org
    
    # 安装p2pd
    go install github.com/libp2p/go-libp2p-daemon/p2pd@latest
    
    # 优化系统资源限制
    log_info "优化系统资源限制..."
    
    # 增加文件描述符限制
    echo 'fs.file-max = 65536' >> /etc/sysctl.conf
    echo '* soft nofile 65536' >> /etc/security/limits.conf
    echo '* hard nofile 65536' >> /etc/security/limits.conf
    
    # 增加进程限制
    echo '* soft nproc 32768' >> /etc/security/limits.conf
    echo '* hard nproc 32768' >> /etc/security/limits.conf
    
    # 应用配置
    sysctl -p > /dev/null 2>&1 || true
    
    # 设置当前session的限制
    ulimit -n 65536 2>/dev/null || true
    ulimit -u 32768 2>/dev/null || true
    
    log_success "系统依赖安装完成"
}

# 第二步：拷贝gensyn-monitor文件夹到root路径
copy_gensyn_monitor() {
    log_info "复制gensyn-monitor文件夹到root路径..."
    
    # 确保目标目录存在
    check_and_create_dir "/root" || {
        log_error "无法创建/root目录，跳过监控脚本复制"
        return 1
    }
    
    # 检查脚本同级目录下是否有gensyn-monitor文件夹
    if [[ -d "${SCRIPT_DIR}/gensyn-monitor" ]]; then
        cp -r "${SCRIPT_DIR}/gensyn-monitor" "/root/" || {
            log_error "复制gensyn-monitor文件夹失败"
            return 1
        }
        chmod +x /root/gensyn-monitor/gensyn_monitor.sh || {
            log_warning "无法设置监控脚本可执行权限"
        }
        log_success "已复制gensyn-monitor文件夹到/root/路径"
    else
        log_error "未找到gensyn-monitor文件夹，请确保文件夹与此脚本在同一目录: ${SCRIPT_DIR}"
        return 1
    fi
    
    return 0
}

# 第三步：拉取官方库到root路径
clone_official_repo() {
    log_info "拉取官方库到root路径..."
    
    # 确保root目录存在
    check_and_create_dir "/root" || {
        log_error "无法创建/root目录，跳过仓库克隆"
        return 1
    }
    
    # 检查目录是否已存在，如果存在则先备份
    if [[ -d "/root/rl-swarm" ]]; then
        log_warning "发现已存在的rl-swarm目录，正在备份..."
        BACKUP_DIR="/root/rl-swarm-backup-$(date +%Y%m%d%H%M%S)"
        mv /root/rl-swarm "$BACKUP_DIR" || {
            log_error "备份旧目录失败，将尝试删除旧目录"
            rm -rf /root/rl-swarm || {
                log_error "无法移除旧目录，无法继续"
                return 1
            }
        }
        log_success "已备份旧目录到 $BACKUP_DIR"
    fi
    
    # 克隆仓库
    cd /root || {
        log_error "无法切换到/root目录"
        return 1
    }
    
    git clone https://github.com/gensyn-ai/rl-swarm.git || {
        log_error "克隆仓库失败，请检查网络连接"
        return 1
    }
    
    log_success "官方库已成功克隆到/root/rl-swarm"
    return 0
}

# 第四步：替换配置文件
replace_config() {
    log_info "替换配置文件..."
    
    # 检查脚本同级目录下是否有rg-swarm.yaml文件
    if [[ -f "${SCRIPT_DIR}/rg-swarm.yaml" ]]; then
        # 确保目标目录存在
        check_and_create_dir "/root/rl-swarm/rgym_exp/config" || {
            log_error "无法创建配置文件目录，跳过配置文件复制"
            return 1
        }
        
        # 复制文件
        cp "${SCRIPT_DIR}/rg-swarm.yaml" "/root/rl-swarm/rgym_exp/config/rg-swarm.yaml" || {
            log_error "复制配置文件失败"
            return 1
        }
        
        log_success "配置文件已替换"
    else
        log_error "未找到rg-swarm.yaml文件，请确保文件与此脚本在同一目录: ${SCRIPT_DIR}"
        return 1
    fi
    
    return 0
}

# 第五步：替换启动脚本
replace_startup_script() {
    log_info "替换启动脚本..."
    
    # 确保目标目录存在
    check_and_create_dir "/root/rl-swarm" || {
        log_error "无法创建rl-swarm目录，跳过启动脚本替换"
        return 1
    }
    
    # 检查脚本同级目录下是否有run_rl_swarm.sh文件
    if [[ -f "${SCRIPT_DIR}/run_rl_swarm.sh" ]]; then
        cp "${SCRIPT_DIR}/run_rl_swarm.sh" "/root/rl-swarm/" || {
            log_error "复制启动脚本失败"
            return 1
        }
        chmod +x /root/rl-swarm/run_rl_swarm.sh || {
            log_warning "无法设置脚本可执行权限"
        }
        log_success "启动脚本已替换"
    else
        log_error "未找到run_rl_swarm.sh文件，请确保文件与此脚本在同一目录: ${SCRIPT_DIR}"
        return 1
    fi
    
    return 0
}

# 第六步：复制证书文件
copy_certificate() {
    log_info "复制证书文件..."
    
    # 确保目标目录存在
    check_and_create_dir "/root/rl-swarm" || {
        log_error "无法创建rl-swarm目录，跳过证书复制"
        return 1
    }
    
    # 查找最新的备份目录（如果存在多个）
    LATEST_BACKUP=$(find /root -maxdepth 1 -name "rl-swarm-backup*" -type d | sort -r | head -n 1)
    
    # 检查备份目录中是否有swarm.pem文件
    if [[ -n "$LATEST_BACKUP" ]] && [[ -f "$LATEST_BACKUP/swarm.pem" ]]; then
        cp "$LATEST_BACKUP/swarm.pem" "/root/rl-swarm/" || {
            log_error "从备份目录复制证书失败"
            return 1
        }
        log_success "证书文件已从备份目录 $LATEST_BACKUP 复制"
    # 检查固定的备份目录
    elif [[ -d "/root/rl-swarm-backup" ]] && [[ -f "/root/rl-swarm-backup/swarm.pem" ]]; then
        cp "/root/rl-swarm-backup/swarm.pem" "/root/rl-swarm/" || {
            log_error "从标准备份目录复制证书失败"
            return 1
        }
        log_success "证书文件已从标准备份目录复制"
    # 检查脚本同级目录下是否有swarm.pem文件    
    elif [[ -f "${SCRIPT_DIR}/swarm.pem" ]]; then
        cp "${SCRIPT_DIR}/swarm.pem" "/root/rl-swarm/" || {
            log_error "从脚本目录复制证书失败"
            return 1
        }
        log_success "证书文件已从脚本目录复制"
    else
        log_warning "未找到证书文件，请手动上传。"
        echo -e "${YELLOW}请在启动前将swarm.pem证书文件上传至/root/rl-swarm/目录。${NC}"
        # 移除交互式等待
        # read -p "按Enter键继续..."
    fi
    
    return 0
}

# 第七步：创建Python虚拟环境并启动脚本
setup_and_start() {
    log_info "设置Python虚拟环境..."
    
    # 检查rl-swarm目录是否存在
    if [[ ! -d "/root/rl-swarm" ]]; then
        log_error "未找到/root/rl-swarm目录，无法设置环境"
        return 1
    fi
    
    # 创建并激活Python虚拟环境
    cd /root/rl-swarm || {
        log_error "无法切换到/root/rl-swarm目录"
        return 1
    }
    
    python3 -m venv myenv || {
        log_error "创建Python虚拟环境失败，请确保python3-venv已安装"
        log_info "尝试安装python3-venv..."
        apt install -y python3-venv && python3 -m venv myenv || {
            log_error "创建Python虚拟环境仍然失败，请手动检查"
            return 1
        }
    }
    
    log_success "环境设置完成，准备启动脚本。"
    
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${GREEN}Gensyn一键部署已完成！${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${YELLOW}请使用以下命令启动程序：${NC}"
    echo -e "${BLUE}cd${NC}"
    echo -e "${BLUE}screen -S gensyn${NC}"
    echo -e "${BLUE}cd rl-swarm${NC}"
    echo -e "${BLUE}source myenv/bin/activate${NC}"
    echo -e "${BLUE}chmod +x run_rl_swarm.sh${NC}"
    echo -e "${BLUE}./run_rl_swarm.sh${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    
    # 自动选择启动，无需询问
    # read -p "是否立即启动程序？(y/n): " start_now
    start_now="y"
    
    if [[ "$start_now" == "y" ]] || [[ "$start_now" == "Y" ]]; then
        log_info "正在启动程序..."
        
        # 检查screen是否安装
        if ! command -v screen &> /dev/null; then
            log_warning "screen未安装，尝试安装..."
            apt install -y screen || {
                log_error "无法安装screen，请手动启动程序"
                return 1
            }
        fi
        
        # 确保没有同名会话
        screen -wipe &>/dev/null || true
        screen -S gensyn -X quit &>/dev/null || true
        
        cd || {
            log_warning "无法切换到主目录，但将继续执行"
        }
        
        screen -dmS gensyn bash -c "cd /root/rl-swarm && source myenv/bin/activate && chmod +x run_rl_swarm.sh && ./run_rl_swarm.sh" || {
            log_error "启动screen会话失败"
            return 1
        }
        
        log_success "程序已在screen会话中启动，使用 'screen -r gensyn' 命令查看。"
    fi
    
    return 0
}

# 主函数
main() {
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${GREEN}            Gensyn一键部署脚本 v1.0                      ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    
    # 检查是否为root用户
    check_root
    
    # 自动继续，无需询问
    # read -p "此脚本将在当前系统上部署Gensyn环境，是否继续？(y/n): " continue_setup
    continue_setup="y"
    
    if [[ "$continue_setup" != "y" ]] && [[ "$continue_setup" != "Y" ]]; then
        log_info "用户取消安装，退出脚本。"
        exit 0
    fi
    
    # 执行所有步骤
    log_info "开始安装依赖..."
    install_dependencies || {
        log_error "安装依赖失败，请检查网络连接和系统环境。"
        exit 1
    }
    
    log_info "开始复制监控脚本..."
    copy_gensyn_monitor || {
        log_error "复制监控脚本失败。"
        exit 1
    }
    
    log_info "开始克隆官方仓库..."
    clone_official_repo || {
        log_error "克隆官方仓库失败，请检查网络连接。"
        exit 1
    }
    
    log_info "开始替换配置文件..."
    replace_config || {
        log_warning "替换配置文件失败，但将继续执行。"
    }
    
    log_info "开始替换启动脚本..."
    replace_startup_script || {
        log_warning "替换启动脚本失败，但将继续执行。"
    }
    
    log_info "开始复制证书文件..."
    copy_certificate || {
        log_warning "复制证书文件失败，可能需要手动上传。"
    }
    
    log_info "设置环境并启动程序..."
    setup_and_start || {
        log_error "设置环境或启动程序失败。"
        exit 1
    }
}

# 执行主函数
main 