#!/bin/sh

# =========================================================
# NodePass & Agent 安装脚本
# =========================================================

export DEBIAN_FRONTEND=noninteractive

WORK_DIR='/etc/nodepass'
GH_PROXY='https://gh-proxy.com/'
BASE_URL="https://raw.githubusercontent.com/MK85Pilot/Porta_Static/main"

# ---------- 颜色输出 ----------
print_info() { printf "\033[32m%s\033[0m\n" "$1"; }
print_warn() { printf "\033[33m%s\033[0m\n" "$1"; }
print_err()  { printf "\033[31m%s\033[0m\n" "$1"; }

# ---------- Root 检查 ----------
if [ "$(id -u)" -ne 0 ]; then
    print_err "错误: 必须使用 root 运行"
    exit 1
fi

# ---------- 卸载 ----------
uninstall() {
    print_warn "正在卸载 NodePass 与 Agent..."

    systemctl stop nodepass-agent 2>/dev/null
    systemctl disable nodepass-agent 2>/dev/null
    systemctl stop nodepass 2>/dev/null
    systemctl disable nodepass 2>/dev/null

    rm -f /etc/systemd/system/nodepass.service
    rm -f /etc/systemd/system/nodepass-agent.service
    systemctl daemon-reload

    rm -rf "$WORK_DIR"
    print_info "卸载完成"
}

if [ "$1" = "uninstall" ]; then
    uninstall
    exit 0
fi

# ---------- 冲突检测 ----------
if [ -f "/etc/systemd/system/nodepass-agent.service" ]; then
    print_err "检测到 NodePass Agent 已存在"
    print_warn "请先运行: sh install.sh uninstall"
    exit 1
fi

# ---------- 依赖 ----------
if ! command -v curl >/dev/null || ! command -v grep >/dev/null; then
    apt-get update -y && apt-get install -y curl grep
fi

mkdir -p "$WORK_DIR"

# =========================================================
# 参数处理
# =========================================================

ARG_HUB_URL="$1"
ARG_TOKEN="$2"
ARG_NODE_TYPE="$3"

printf "========================================\n"
printf "   NodePass & Agent 安装（AUTH_TOKEN 必填）\n"
printf "========================================\n"

# ---------- HUB_URL ----------
if [ -n "$ARG_HUB_URL" ]; then
    CFG_HUB_URL="$ARG_HUB_URL"
else
    DEFAULT_HUB="ws://127.0.0.1:8088/ws/agent"
    printf "请输入 HUB_URL [默认: %s]: " "$DEFAULT_HUB"
    read INPUT
    CFG_HUB_URL="${INPUT:-$DEFAULT_HUB}"
fi

# ---------- AUTH_TOKEN（强制） ----------
if [ -n "$ARG_TOKEN" ]; then
    CFG_TOKEN="$ARG_TOKEN"
else
    printf "请输入 AUTH_TOKEN（Hub 侧签发，不能为空）: "
    read INPUT_TOKEN
    CFG_TOKEN="$INPUT_TOKEN"
fi

if [ -z "$CFG_TOKEN" ]; then
    print_err "AUTH_TOKEN 不能为空"
    print_warn "该令牌必须由 Hub 侧生成，用于 Agent ↔ Hub 通信校验"
    exit 1
fi

# ---------- NODE_TYPE ----------
if [ -n "$ARG_NODE_TYPE" ]; then
    CFG_NODE_TYPE="$ARG_NODE_TYPE"
else
    printf "请输入 NODE_TYPE (both/master/slave) [默认: both]: "
    read INPUT
    CFG_NODE_TYPE="${INPUT:-both}"
fi

# =========================================================
# 安装 NodePass（Hub）
# =========================================================

print_info "\n>>> 1. 安装 NodePass Hub"

TEMP_URL=${CFG_HUB_URL#*://}
HOST_PORT=${TEMP_URL%%/*}
NP_PORT=${HOST_PORT##*:}

case "$NP_PORT" in
    ''|*[!0-9]*) NP_PORT=8088 ;;
esac

printf "监听端口: \033[36m%s\033[0m\n" "$NP_PORT"

curl -L -f -o "$WORK_DIR/nodepass" "${GH_PROXY}${BASE_URL}/nodepass"
[ -s "$WORK_DIR/nodepass" ] || { print_err "nodepass 下载失败"; exit 1; }
chmod +x "$WORK_DIR/nodepass"

cat > /etc/systemd/system/nodepass.service <<EOF
[Unit]
Description=NodePass Hub
After=network.target

[Service]
Type=simple
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/nodepass master://0.0.0.0:${NP_PORT}/api?tls=1
Restart=always
RestartSec=5
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

print_info "NodePass 启动成功"

# =========================================================
# 安装 Agent
# =========================================================

print_info "\n>>> 2. 安装 Agent"

curl -L -f -o "$WORK_DIR/agent" "${GH_PROXY}${BASE_URL}/agent"
[ -s "$WORK_DIR/agent" ] || { print_err "agent 下载失败"; exit 1; }
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
RestartSec=5
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
printf "========================================\n"
printf "Hub URL   : %s\n" "$CFG_HUB_URL"
printf "AuthToken : %s\n" "$CFG_TOKEN"
printf '%s\n' "----------------------------------------"
printf "NodePass  : \033[32m运行中\033[0m (端口 %s)\n" "$NP_PORT"
printf "Agent     : \033[32m运行中\033[0m\n"
printf "========================================\n"
