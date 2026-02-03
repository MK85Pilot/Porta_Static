#!/bin/sh

# =========================================================
# NodePass Node & Agent 安装脚本 (无Hub版)
# =========================================================

# 修复 getcwd 错误：切换到根目录并忽略可能的错误
cd / 2>/dev/null || true

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
    print_warn "卸载 NodePass 和 Agent"

    systemctl stop nodepass nodepass-agent 2>/dev/null
    systemctl disable nodepass nodepass-agent 2>/dev/null
    rm -f /etc/systemd/system/nodepass.service
    rm -f /etc/systemd/system/nodepass-agent.service
    systemctl daemon-reload
    rm -rf "$WORK_DIR"

    print_info "卸载完成"
    exit 0
fi

# ---------- 组件安装状态检测 ----------
NODEPASS_INSTALLED=false
AGENT_INSTALLED=false

if [ -f /etc/systemd/system/nodepass.service ]; then
    NODEPASS_INSTALLED=true
    print_warn "检测到 NodePass 已安装，将跳过安装"
fi

if [ -f /etc/systemd/system/nodepass-agent.service ]; then
    AGENT_INSTALLED=true
    print_warn "检测到 Agent 已安装，将跳过安装"
fi

# 如果所有组件都已安装，询问是否继续更新配置
if [ "$NODEPASS_INSTALLED" = true ] && [ "$AGENT_INSTALLED" = true ]; then
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

# =========================================================
# 环境变量检查
# =========================================================

# 从环境变量读取配置，如果没有则使用空字符串（后续交互式输入）
CFG_TOKEN="${AUTH_TOKEN:-}"
CFG_PORT="${NODEPASS_PORT:-}"
CFG_WS_PROTO="${WS_PROTOCOL:-}"
CFG_HUB_ADDR="${HUB_ADDRESS:-}"
CFG_NODE_TYPE="${NODE_TYPE:-}"

printf "========================================\n"
printf " NodePass 节点 & Agent 安装\n"
printf "========================================\n"

# ---------- AUTH_TOKEN ----------
if [ -z "$CFG_TOKEN" ]; then
    printf "\n"
    printf "========================================\n"
    printf " Agent 连接配置\n"
    printf "========================================\n"
    printf "AUTH_TOKEN (用于连接远程 Hub 的认证令牌): "
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
    printf "远程 Hub 服务器地址 (格式: 1.1.1.1:8088 或 hub.example.com): "
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
# NodePass (核心组件)
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
After=network.target

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
# Agent (与 Hub 通信组件)
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
    systemctl restart nodepass-agent
    printf "服务已重启\n"
fi

print_info "安装完成"
