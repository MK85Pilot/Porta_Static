#!/bin/sh

# =========================================================
# NodePass Hub & Agent 安装脚本
# 修复：getcwd 崩溃（bash <(curl ...) 场景）
# =========================================================

# ---------- 关键修复 ----------
cd / || exit 1

export DEBIAN_FRONTEND=noninteractive

WORK_DIR="/etc/nodepass"
GH_PROXY="https://gh-proxy.com/"
BASE_URL="https://raw.githubusercontent.com/MK85Pilot/Porta_Static/main"

# ---------- 颜色 ----------
print_info() { printf "\033[32m%s\033[0m\n" "$1"; }
print_warn() { printf "\033[33m%s\033[0m\n" "$1"; }
print_err()  { printf "\033[31m%s\033[0m\n" "$1"; }

# ---------- Root ----------
[ "$(id -u)" -eq 0 ] || { print_err "必须使用 root 运行"; exit 1; }

# ---------- 卸载 ----------
if [ "$1" = "uninstall" ]; then
    print_warn "卸载 Conduit、NodePass 和 Agent"

    systemctl stop conduit nodepass nodepass-agent 2>/dev/null
    systemctl disable conduit nodepass nodepass-agent 2>/dev/null
    rm -f /etc/systemd/system/conduit.service
    rm -f /etc/systemd/system/nodepass.service
    rm -f /etc/systemd/system/nodepass-agent.service
    systemctl daemon-reload
    rm -rf "$WORK_DIR"

    print_info "卸载完成"
    exit 0
fi

# ---------- 组件安装状态检测 ----------
HUB_INSTALLED=false
NODEPASS_INSTALLED=false
AGENT_INSTALLED=false

if [ -f /etc/systemd/system/conduit.service ]; then
    HUB_INSTALLED=true
    print_warn "检测到 Conduit 已安装，将跳过安装"
fi

if [ -f /etc/systemd/system/nodepass.service ]; then
    NODEPASS_INSTALLED=true
    print_warn "检测到 NodePass 已安装，将跳过安装"
fi

if [ -f /etc/systemd/system/nodepass-agent.service ]; then
    AGENT_INSTALLED=true
    print_warn "检测到 Agent 已安装，将跳过安装"
fi

# 如果所有组件都已安装，询问是否继续更新配置
if [ "$HUB_INSTALLED" = true ] && [ "$NODEPASS_INSTALLED" = true ] && [ "$AGENT_INSTALLED" = true ]; then
    print_warn "所有组件已安装"
    printf "是否更新配置文件? (y/N): "
    read UPDATE_CFG
    if [ "$UPDATE_CFG" != "y" ] && [ "$UPDATE_CFG" != "Y" ]; then
        print_info "取消安装"
        exit 0
    fi
fi

# ---------- 依赖 ----------
command -v curl >/dev/null 2>&1 || {
    apt-get update -y && apt-get install -y curl
}

mkdir -p "$WORK_DIR"

# ---------- 随机生成函数 ----------
generate_random_string() {
    length=$1
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

generate_random_password() {
    length=$1
    tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c "$length"
}

# =========================================================
# 环境变量检查
# =========================================================

# 从环境变量读取配置，如果没有则使用空字符串（后续交互式输入）
CFG_TOKEN="${AUTH_TOKEN:-}"
CFG_PORT="${NODEPASS_PORT:-}"
CFG_WS_PROTO="${WS_PROTOCOL:-}"
CFG_HUB_ADDR="${HUB_ADDRESS:-}"
CFG_NODE_TYPE="${NODE_TYPE:-}"
INSTALL_HUB="${INSTALL_HUB:-}"

printf "========================================\n"
printf " NodePass Agent 安装\n"
printf "========================================\n"

# ---------- AUTH_TOKEN ----------
if [ -z "$CFG_TOKEN" ]; then
    printf "\n"
    printf "========================================\n"
    printf " Agent 配置\n"
    printf "========================================\n"
    printf "AUTH_TOKEN (用于 Agent 连接 Hub 的认证令牌): "
    read CFG_TOKEN
fi

[ -n "$CFG_TOKEN" ] || { print_err "AUTH_TOKEN 不能为空"; exit 1; }

# ---------- PORT ----------
if [ -z "$CFG_PORT" ]; then
    printf "\n"
    printf "本地 NodePass 节点监听端口 (格式: 18080): "
    read CFG_PORT
fi

case "$CFG_PORT" in
    ''|*[!0-9]*) CFG_PORT=18080 ;;
esac

# ---------- WS_PROTOCOL (ws/wss) ----------
if [ -z "$CFG_WS_PROTO" ]; then
    printf "WebSocket 协议 (格式: ws 或 wss): "
    read CFG_WS_PROTO
fi

case "$CFG_WS_PROTO" in
    ws|wss) ;;
    *) CFG_WS_PROTO="ws" ;;
esac

# ---------- HUB_ADDRESS (ip:port 或域名) ----------
if [ -z "$CFG_HUB_ADDR" ]; then
    printf "Hub 服务器地址 (格式: 192.168.1.100:8088 或 hub.example.com:8088): "
    read CFG_HUB_ADDR
fi

# 自动构建完整的 HUB_URL
CFG_HUB_URL="${CFG_WS_PROTO}://${CFG_HUB_ADDR}/ws/agent"

# ---------- NODE_TYPE ----------
if [ -z "$CFG_NODE_TYPE" ]; then
    printf "Agent 节点类型 (格式: both 或 master 或 slave): "
    read CFG_NODE_TYPE
fi

# =========================================================
# Hub (独立服务器)
# =========================================================

if [ "$INSTALL_HUB" = "true" ]; then
    if [ "$HUB_INSTALLED" = true ]; then
        print_info "Hub 已安装，跳过安装"
    else
        print_info "安装 Hub 服务器"
        
        # 采集 Hub 配置信息
        printf "\n"
        printf "========================================\n"
        printf " Hub 服务器配置\n"
        printf "========================================\n"
        printf "\n"
        
        # 服务器绑定地址
        printf "服务器绑定地址 (格式: 0.0.0.0:8088): "
        read HUB_BIND_ADDRESS
        
        # MySQL 数据库配置
        printf "\nMySQL 数据库配置\n"
        printf "数据库地址 (格式: mysql.example.com): "
        read HUB_DB_HOST
        printf "数据库端口 (格式: 3306): "
        read HUB_DB_PORT
        printf "数据库用户名 (格式: agent-ws): "
        read HUB_DB_USER
        printf "数据库名 (格式: agent-ws): "
        read HUB_DB_NAME
        printf "数据库密码 (留空随机生成): "
        read HUB_DB_PASSWORD
        [ -z "$HUB_DB_PASSWORD" ] && HUB_DB_PASSWORD=$(generate_random_password 32)
        
        # 系统基础 URL
        printf "\n系统配置\n"
        printf "系统基础 URL (格式: https://portal.example.com): "
        read HUB_BASE_URL
        
        # Telegram Bot 配置
        printf "\nTelegram Bot 配置\n"
        printf "Bot Token (从 @BotFather 获取): "
        read HUB_TELEGRAM_BOT_TOKEN
        printf "Bot 用户名 (格式: Portforward_bot): "
        read HUB_TELEGRAM_BOT_USERNAME
        
        # Telegram Webhook URL
        printf "Webhook URL (留空使用默认): "
        read HUB_TELEGRAM_WEBHOOK
        [ -z "$HUB_TELEGRAM_WEBHOOK" ] && HUB_TELEGRAM_WEBHOOK="${HUB_BASE_URL}/api/v1/telegram/webhook"
        
        # 生成随机密钥
        HUB_API_KEY=$(generate_random_string 64)
        HUB_JWT_SECRET=$(generate_random_string 64)
        HUB_ADMIN_PASSWORD=$(generate_random_password 16)
        
        # 下载 Hub 可执行文件
        curl -fsSL -o "$WORK_DIR/hub" "${GH_PROXY}${BASE_URL}/hub" || exit 1
        chmod +x "$WORK_DIR/hub"
        
        # 创建 Hub 环境配置文件
        cat > "$WORK_DIR/hub.env" <<EOF
# 服务器绑定地址
BIND_ADDRESS=$HUB_BIND_ADDRESS

# MySQL 数据库配置
DB_HOST=$HUB_DB_HOST
DB_PORT=$HUB_DB_PORT
DB_USER=$HUB_DB_USER
DB_PASSWORD=$HUB_DB_PASSWORD
DB_NAME=$HUB_DB_NAME

# API 密钥
API_KEY=$HUB_API_KEY

# JWT 配置
JWT_SECRET=$HUB_JWT_SECRET
JWT_ISSUER=hub-api

# 管理员默认密码
ADMIN_DEFAULT_PASSWORD=$HUB_ADMIN_PASSWORD

# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=$HUB_TELEGRAM_BOT_TOKEN
TELEGRAM_BOT_USERNAME=$HUB_TELEGRAM_BOT_USERNAME

# 系统基础URL
BASE_URL=$HUB_BASE_URL

# Telegram Webhook URL
TELEGRAM_WEBHOOK_URL=$HUB_TELEGRAM_WEBHOOK
EOF
        
        print_info "正在启动 Hub 进行初始化..."
        print_warn "Hub 需要前台运行以生成鉴权文件"
        print_warn "请按照提示完成初始化配置"
        print_warn "初始化完成后，请按 Ctrl+C 停止 Hub，脚本将继续安装"
        printf "\n"
        
        # 前台运行 Hub 进行初始化
        # 用户完成配置后按 Ctrl+C 停止
        cd "$WORK_DIR"
        . ./hub.env
        ./hub || true  # 忽略退出码，允许用户手动停止
        
        print_info "\nHub 初始化完成，正在配置为系统服务..."
        
        # 创建 Hub systemd 服务
        cat > /etc/systemd/system/conduit.service <<EOF
[Unit]
Description=Conduit Server
After=network.target mysql.service

[Service]
EnvironmentFile=$WORK_DIR/hub.env
ExecStart=$WORK_DIR/hub
WorkingDirectory=$WORK_DIR
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable conduit
        systemctl restart conduit
        
        print_info "Hub 安装完成"
        print_warn "重要信息已保存到 $WORK_DIR/hub.env"
        print_warn "管理员默认密码: $HUB_ADMIN_PASSWORD"
    fi
fi

# =========================================================
# NodePass
# =========================================================

if [ "$NODEPASS_INSTALLED" = true ]; then
    print_info "NodePass 已安装，跳过安装"
else
    print_info "安装 NodePass (端口 $CFG_PORT)"

    curl -fsSL -o "$WORK_DIR/nodepass" "${GH_PROXY}${BASE_URL}/nodepass" || exit 1
    chmod +x "$WORK_DIR/nodepass"

    cat > /etc/systemd/system/nodepass.service <<EOF
[Unit]
Description=NodePass
After=network.target nodepass-hub.service

[Service]
ExecStart=$WORK_DIR/nodepass master://0.0.0.0:${CFG_PORT}/api?tls=1
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nodepass
    systemctl restart nodepass
fi

# =========================================================
# Agent
# =========================================================

if [ "$AGENT_INSTALLED" = true ]; then
    print_info "Agent 已安装，跳过安装"
else
    print_info "安装 Agent"

    curl -fsSL -o "$WORK_DIR/agent" "${GH_PROXY}${BASE_URL}/agent" || exit 1
    chmod +x "$WORK_DIR/agent"

    cat > "$WORK_DIR/.env" <<EOF
HUB_URL=$CFG_HUB_URL
AUTH_TOKEN=$CFG_TOKEN
NODE_TYPE=$CFG_NODE_TYPE
LOG_LEVEL=info
EOF

    cat > /etc/systemd/system/nodepass-agent.service <<EOF
[Unit]
Description=NodePass Agent
After=network.target nodepass.service

[Service]
EnvironmentFile=$WORK_DIR/.env
ExecStart=$WORK_DIR/agent
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nodepass-agent
    systemctl restart nodepass-agent
fi

# =========================================================
# 更新配置文件（如果需要）
# =========================================================

if [ "$UPDATE_CFG" = "y" ] || [ "$UPDATE_CFG" = "Y" ]; then
    printf "\n"
    printf "========================================\n"
    printf " 配置更新\n"
    printf "========================================\n"
    printf "\n"
    
    print_info "选择要更新的配置："
    printf "  1. Agent 配置 (连接 Hub 的配置)\n"
    if [ "$HUB_INSTALLED" = true ]; then
        printf "  2. Hub 服务器配置 (服务器运行配置)\n"
    fi
    printf "\n"
    printf "请输入选项编号 (1-2，多个用空格分隔，更新全部直接回车): "
    read UPDATE_CHOICE
    
    # 更新 Agent 配置
    if [ -z "$UPDATE_CHOICE" ] || echo "$UPDATE_CHOICE" | grep -q "1"; then
        printf "\n"
        printf "========================================\n"
        printf " 更新 Agent 配置\n"
        printf "========================================\n"
        printf "\n"
        
        printf "AUTH_TOKEN (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && CFG_TOKEN="$INPUT"
        
        printf "Hub 服务器地址 (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && CFG_HUB_ADDR="$INPUT"
        
        printf "WebSocket 协议 (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && CFG_WS_PROTO="$INPUT"
        
        printf "节点类型 (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && CFG_NODE_TYPE="$INPUT"
        
        # 重新构建 HUB_URL
        CFG_HUB_URL="${CFG_WS_PROTO}://${CFG_HUB_ADDR}/ws/agent"
        
        cat > "$WORK_DIR/.env" <<EOF
HUB_URL=$CFG_HUB_URL
AUTH_TOKEN=$CFG_TOKEN
NODE_TYPE=$CFG_NODE_TYPE
LOG_LEVEL=info
EOF
        
        print_info "Agent 配置已更新"
        printf "重启命令: systemctl restart nodepass-agent\n"
    fi
    
    # 更新 Hub 服务器配置
    if [ "$HUB_INSTALLED" = true ] && ( [ -z "$UPDATE_CHOICE" ] || echo "$UPDATE_CHOICE" | grep -q "2" ); then
        printf "\n"
        printf "========================================\n"
        printf " 更新 Hub 服务器配置\n"
        printf "========================================\n"
        printf "\n"
        
        printf "服务器绑定地址 (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && HUB_BIND_ADDRESS="$INPUT"
        
        printf "\nMySQL 数据库配置\n"
        printf "数据库地址 (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && HUB_DB_HOST="$INPUT"
        printf "数据库密码 (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && HUB_DB_PASSWORD="$INPUT"
        
        printf "\n系统配置\n"
        printf "系统基础 URL (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && HUB_BASE_URL="$INPUT"
        
        printf "\nTelegram Bot 配置\n"
        printf "Bot Token (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && HUB_TELEGRAM_BOT_TOKEN="$INPUT"
        printf "Bot 用户名 (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && HUB_TELEGRAM_BOT_USERNAME="$INPUT"
        printf "Webhook URL (留空保持当前): "
        read INPUT
        [ -n "$INPUT" ] && HUB_TELEGRAM_WEBHOOK="$INPUT"
        
        # 重新读取现有配置以保留未修改的值
        if [ -f "$WORK_DIR/hub.env" ]; then
            . "$WORK_DIR/hub.env"
        fi
        
        # 创建更新后的配置
        cat > "$WORK_DIR/hub.env" <<EOF
# 服务器绑定地址
BIND_ADDRESS=${HUB_BIND_ADDRESS:-0.0.0.0:8088}

# MySQL 数据库配置
DB_HOST=${HUB_DB_HOST}
DB_PORT=${HUB_DB_PORT:-3306}
DB_USER=${HUB_DB_USER:-agent-ws}
DB_PASSWORD=${HUB_DB_PASSWORD}
DB_NAME=${HUB_DB_NAME:-agent-ws}

# API 密钥
API_KEY=${HUB_API_KEY}

# JWT 配置
JWT_SECRET=${HUB_JWT_SECRET}
JWT_ISSUER=hub-api

# 管理员默认密码
ADMIN_DEFAULT_PASSWORD=${HUB_ADMIN_PASSWORD}

# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=${HUB_TELEGRAM_BOT_TOKEN}
TELEGRAM_BOT_USERNAME=${HUB_TELEGRAM_BOT_USERNAME}

# 系统基础URL
BASE_URL=${HUB_BASE_URL}

# Telegram Webhook URL
TELEGRAM_WEBHOOK_URL=${HUB_TELEGRAM_WEBHOOK}
EOF
        
        print_info "\nConduit 服务器配置已更新"
        printf "重启命令: systemctl restart conduit\n"
    fi
fi

print_info "安装完成"
