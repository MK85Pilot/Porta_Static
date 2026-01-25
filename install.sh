#!/bin/sh

# =========================================================
# NodePass Hub & Agent 安装脚本
# 参数顺序：
#   $1 AUTH_TOKEN (必需，Hub 侧签发)
#   $2 HUB_URL
#   $3 NODE_TYPE (both/master/slave)
#   $4 LISTEN_PORT (默认 18080)
# 参数不足时自动进入交互模式
# =========================================================

export DEBIAN_FRONTEND=noninteractive

WORK_DIR="/etc/nodepass"
GH_PROXY="https://gh-proxy.com/"
BASE_URL="https://raw.githubusercontent.com/MK85Pilot/Porta_Static/main"

# ---------- 颜色 ----------
print_info() { printf "\033[32m%s\033[0m\n" "$1"; }
print_warn() { printf "\033[33m%s\033[0m\n" "$1"; }
print_err()  { printf "\033[31m%s\033[0m\n" "$1"; }

# ---------- Root 检查 ----------
[ "$(id -u)" -eq 0 ] || { print_err "必须使用 root 运行"; exit 1; }

# ---------- 卸载 ----------
if [ "$1" = "uninstall" ]; then
    print_warn "卸载 NodePass Hub & Agent"

    systemctl stop nodepass nodepass-agent 2>/dev/null
    systemctl disable nodepass nodepass-agent 2>/dev/null
    rm -f /etc/systemd/system/nodepass*.service
    systemctl daemon-reload
    rm -rf "$WORK_DIR"

    print_info "卸载完成"
    exit 0
fi

# ---------- 冲突检测 ----------
if [ -f /etc/systemd/system/nodepass-agent.service ]; then
    print_err "检测到 NodePass Agent 已存在"
    print_warn "请先运行: sh install.sh uninstall"
    exit 1
fi

# ---------- 依赖 ----------
command -v curl >/dev/null 2>&1 || {
    apt-get update -y && apt-get install -y curl
}

mkdir -p "$WORK_DIR"

# =========================================================
# 参数解析（按你指定的顺序）
# =========================================================

ARG_TOKEN="$1"
ARG_HUB_URL="$2"
ARG_NODE_TYPE="$3"
ARG_PORT="$4"

printf "========================================\n"
printf " NodePass Hub & Agent 安装\n"
printf "========================================\n"

# ---------- 1. AUTH_TOKEN ----------
if [ -n "$ARG_TOKEN" ]; then
    CFG_TOKEN="$ARG_TOKEN"
else
    printf "请输入 AUTH_TOKEN（Hub 侧签发，不能为空）: "
    read CFG_TOKEN
fi

if [ -z "$CFG_TOKEN" ]; then
    print_err "AUTH_TOKEN 不能为空"
    exit 1
fi

# ---------- 2. 监听端口 ----------
DEFAULT_PORT="18080"
if [ -n "$ARG_PORT" ]; then
    CFG_PORT="$ARG_PORT"
else
    printf "请输入 NodePass 监听端口 [默认: %s]: " "$DEFAULT_PORT"
    read INPUT
    CFG_PORT="${INPUT:-$DEFAULT_PORT}"
fi

case "$CFG_PORT" in
    ''|*[!0-9]*)
        print_warn "端口非法，重置为 18080"
        CFG_PORT=18080
        ;;
esac

# ---------- 3. HUB_URL ----------
DEFAULT_HUB_URL="ws://127.0.0.1:${CFG_PORT}/ws/agent"
if [ -n "$ARG_HUB_URL" ]; then
    CFG_HUB_URL="$ARG_HUB_URL"
else
    printf "请输入 HUB_URL [默认: %s]: " "$DEFAULT_HUB_URL"
    read INPUT
    CFG_HUB_URL="${INPUT:-$DEFAULT_HUB_URL}"
fi

# ---------- 4. NODE_TYPE ----------
if [ -n "$ARG_NODE_TYPE" ]; then
    CFG_NODE_TYPE="$ARG_NODE_TYPE"
else
    printf "请输入 NODE_TYPE (both/master/slave) [默认: both]: "
    read INPUT
    CFG_NODE_TYPE="${INPUT:-both}"
fi

# =========================================================
# 安装 NodePass Hub
# =========================================================

print_info "\n>>> 安装 NodePass Hub"
print_info "监听端口: $CFG_PORT"

curl -fsSL -o "$WORK_DIR/nodepass" "${GH_PROXY}${BASE_URL}/nodepass" \
    || { print_err "nodepass 下载失败"; exit 1; }

chmod +x "$WORK_DIR/nodepass"

cat > /etc/systemd/system/nodepass.service <<EOF
[Unit]
Description=NodePass Hub
After=network.target

[Service]
Type=simple
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/nodepass master://0.0.0.0:${CFG_PORT}/api?tls=1
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nodepass
systemctl restart nodepass

sleep 3
systemctl is-active --quiet nodepass || {
    print_err "NodePass 启动失败"
    exit 1
}

# =========================================================
# 安装 Agent
# =========================================================

print_info "\n>>> 安装 Agent"

curl -fsSL -o "$WORK_DIR/agent" "${GH_PROXY}${BASE_URL}/agent" \
    || { print_err "agent 下载失败"; exit 1; }

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
Type=simple
WorkingDirectory=$WORK_DIR
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

sleep 2
systemctl is-active --quiet nodepass-agent || {
    print_err "Agent 启动失败"
    systemctl status nodepass-agent --no-pager
    exit 1
}

# =========================================================
# 完成
# =========================================================

printf "\n========================================\n"
print_info "安装完成"
printf "----------------------------------------\n"
printf "Hub URL   : %s\n" "$CFG_HUB_URL"
printf "Node Type : %s\n" "$CFG_NODE_TYPE"
printf "Port      : %s\n" "$CFG_PORT"
printf "NodePass  : 运行中\n"
printf "Agent     : 运行中\n"
printf "========================================\n"
