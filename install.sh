#!/bin/sh

# =========================================================
# NodePass & Agent 安装脚本 (Hub/Env模式 - 最终修复版)
# 修复: printf 在 Debian dash 下输出分隔符报错的问题
# =========================================================

export DEBIAN_FRONTEND=noninteractive
WORK_DIR='/etc/nodepass'
GH_PROXY='https://gh-proxy.com/'
BASE_URL="https://raw.githubusercontent.com/MK85Pilot/Porta_Static/main"

# 颜色函数
print_info() { printf "\033[32m%s\033[0m\n" "$1"; }
print_err() { printf "\033[31m%s\033[0m\n" "$1"; }
print_warn() { printf "\033[33m%s\033[0m\n" "$1"; }

# 检查 Root
if [ "$(id -u)" -ne 0 ]; then
    print_err "错误: 必须使用 root 运行"
    exit 1
fi

# --- 卸载功能 ---
uninstall() {
    print_warn "正在卸载 NodePass 和 Agent..."
    
    systemctl stop nodepass-agent 2>/dev/null
    systemctl disable nodepass-agent 2>/dev/null
    systemctl stop nodepass 2>/dev/null
    systemctl disable nodepass 2>/dev/null
    
    rm -f /etc/systemd/system/nodepass.service
    rm -f /etc/systemd/system/nodepass-agent.service
    systemctl daemon-reload
    
    rm -rf "$WORK_DIR"
    print_info "卸载完成。"
}

if [ "$1" = "uninstall" ]; then
    uninstall
    exit 0
fi

# --- 1. 环境准备 ---

# 冲突检测
if [ -f "/etc/systemd/system/nodepass-agent.service" ]; then
    print_err "检测到 Agent 已安装!"
    print_warn "请先运行卸载命令: sh install.sh uninstall"
    exit 1
fi

# 依赖安装
if ! command -v curl > /dev/null || ! command -v grep > /dev/null; then
    apt-get update -y && apt-get install -y curl grep
fi
mkdir -p "$WORK_DIR"

# --- 2. 参数处理 ---

ARG_HUB_URL="$1"
ARG_TOKEN="$2"
ARG_NODE_TYPE="$3"

printf "========================================\n"
printf "   NodePass & Agent (Hub模式) 安装\n"
printf "========================================\n"

# 2.1 获取 HUB_URL
if [ -n "$ARG_HUB_URL" ]; then
    CFG_HUB_URL="$ARG_HUB_URL"
else
    DEFAULT_HUB="ws://127.0.0.1:8088/ws/agent"
    printf "请输入 HUB_URL [默认: %s]: " "$DEFAULT_HUB"
    read INPUT_HUB
    if [ -z "$INPUT_HUB" ]; then
        CFG_HUB_URL="$DEFAULT_HUB"
    else
        CFG_HUB_URL="$INPUT_HUB"
    fi
fi

# 2.2 获取 Token
if [ -n "$ARG_TOKEN" ] && [ "$ARG_TOKEN" != "auto" ]; then
    CFG_TOKEN="$ARG_TOKEN"
    AUTO_TOKEN=0
else
    if [ -z "$ARG_TOKEN" ]; then
        printf "请输入 AUTH_TOKEN [留空自动从本地 NodePass 获取]: "
        read INPUT_TOKEN
        if [ -z "$INPUT_TOKEN" ]; then
            AUTO_TOKEN=1
        else
            CFG_TOKEN="$INPUT_TOKEN"
            AUTO_TOKEN=0
        fi
    else
        AUTO_TOKEN=1
    fi
fi

# 2.3 获取 Node Type
if [ -n "$ARG_NODE_TYPE" ]; then
    CFG_NODE_TYPE="$ARG_NODE_TYPE"
else
    printf "请输入 NODE_TYPE (both/master/slave) [默认: both]: "
    read INPUT_TYPE
    if [ -z "$INPUT_TYPE" ]; then
        CFG_NODE_TYPE="both"
    else
        CFG_NODE_TYPE="$INPUT_TYPE"
    fi
fi

# --- 3. 安装 NodePass ---

print_info "\n>>> 1. 安装 NodePass 服务端"

# 端口解析逻辑
TEMP_URL=${CFG_HUB_URL#*://}
HOST_PORT=${TEMP_URL%%/*}
NP_PORT=${HOST_PORT##*:}

case "$NP_PORT" in
    ''|*[!0-9]*) 
        NP_PORT=8088 
        ;;
esac

printf "解析端口: \033[36m%s\033[0m\n" "$NP_PORT"

# 下载 nodepass
DOWNLOAD_URL="${GH_PROXY}${BASE_URL}/nodepass"
printf "下载: %s ...\n" "nodepass"
curl -L -f -o "$WORK_DIR/nodepass" "$DOWNLOAD_URL"

if [ ! -s "$WORK_DIR/nodepass" ]; then
    print_err "下载 nodepass 失败"
    exit 1
fi
chmod +x "$WORK_DIR/nodepass"

# 启动服务
cat > "/etc/systemd/system/nodepass.service" << EOF
[Unit]
Description=NodePass Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/nodepass master://0.0.0.0:${NP_PORT}/api?tls=1
Restart=always
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nodepass
systemctl restart nodepass

# 验证启动
sleep 3
if ! systemctl is-active --quiet nodepass; then
    print_err "NodePass 启动失败! 请检查端口 $NP_PORT 是否被占用。"
    exit 1
else
    print_info "NodePass 启动成功"
fi

# --- 4. 自动提取 Token ---

if [ "$AUTO_TOKEN" -eq 1 ]; then
    printf "正在从 NodePass 获取 Token..."
    sleep 2
    GOB_FILE="$WORK_DIR/gob/nodepass.gob"
    
    if [ -f "$GOB_FILE" ]; then
        EXTRACTED_KEY=$(grep -a -o '[0-9a-f]\{32\}' "$GOB_FILE" | head -n1)
        if [ -n "$EXTRACTED_KEY" ]; then
            CFG_TOKEN="$EXTRACTED_KEY"
            printf "\033[32m 成功 (%s)\033[0m\n" "$CFG_TOKEN"
        else
            print_err " 失败 (无法解析 Key)"
            exit 1
        fi
    else
        print_err " 失败 (未找到 gob 文件)"
        exit 1
    fi
fi

# --- 5. 安装 Agent ---

print_info "\n>>> 2. 安装 Agent 中间件"

# 下载 agent
DOWNLOAD_URL="${GH_PROXY}${BASE_URL}/agent"
printf "下载: %s ...\n" "agent"
curl -L -f -o "$WORK_DIR/agent" "$DOWNLOAD_URL"

if [ ! -s "$WORK_DIR/agent" ]; then
    print_err "下载 agent 失败"
    exit 1
fi
chmod +x "$WORK_DIR/agent"

# 生成 .env
ENV_FILE="$WORK_DIR/.env"
cat > "$ENV_FILE" << EOF
HUB_URL=$CFG_HUB_URL
AUTH_TOKEN=$CFG_TOKEN
NODE_TYPE=$CFG_NODE_TYPE
LOG_LEVEL=info
EOF

# 创建服务
cat > "/etc/systemd/system/nodepass-agent.service" << EOF
[Unit]
Description=NodePass Agent
After=network.target nodepass.service

[Service]
Type=simple
WorkingDirectory=$WORK_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$WORK_DIR/agent
Restart=always
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nodepass-agent
systemctl restart nodepass-agent

# 验证启动
sleep 2
if ! systemctl is-active --quiet nodepass-agent; then
    print_err "Agent 启动失败!"
    systemctl status nodepass-agent --no-pager
    exit 1
else
    print_info "Agent 启动成功"
fi

# --- 6. 完成 ---

printf "\n========================================\n"
print_info "   安装完成"
printf "========================================\n"
printf "Hub 地址 : %s\n" "$CFG_HUB_URL"
printf "Token    : %s\n" "$CFG_TOKEN"
# 修复: 使用 %s 格式化输出分隔线，避免被当做参数
printf '%s\n' "----------------------------------------"
printf "NodePass : \033[32m运行中\033[0m (端口: $NP_PORT)\n"
printf "Agent    : \033[32m运行中\033[0m\n"
printf "========================================\n"
