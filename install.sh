#!/bin/sh

# =========================================================
# NodePass Hub & Agent 安装脚本（安全版）
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
# 参数解析
# $1 AUTH_TOKEN
# $2 HUB_URL
# $3 NODE_TYPE
# $4 PORT
# =========================================================

ARG_TOKEN="$1"
ARG_HUB_URL="$2"
ARG_NODE_TYPE="$3"
ARG_PORT="$4"

printf "========================================\n"
printf " NodePass Hub & Agent 安装\n"
printf "========================================\n"

# ---------- AUTH_TOKEN ----------
if [ -n "$ARG_TOKEN" ]; then
    CFG_TOKEN="$ARG_TOKEN"
else
    printf "请输入 AUTH_TOKEN: "
    read CFG_TOKEN
fi

[ -n "$CFG_TOKEN" ] || { print_err "AUTH_TOKEN 不能为空"; exit 1; }

# ---------- PORT ----------
DEFAULT_PORT=18080
if [ -n "$ARG_PORT" ]; then
    CFG_PORT="$ARG_PORT"
else
    printf "监听端口 [默认 %s]: " "$DEFAULT_PORT"
    read INPUT
    CFG_PORT="${INPUT:-$DEFAULT_PORT}"
fi

case "$CFG_PORT" in
    ''|*[!0-9]*) CFG_PORT=18080 ;;
esac

# ---------- HUB_URL ----------
DEFAULT_HUB_URL="ws://127.0.0.1:${CFG_PORT}/ws/agent"
if [ -n "$ARG_HUB_URL" ]; then
    CFG_HUB_URL="$ARG_HUB_URL"
else
    printf "HUB_URL [默认 %s]: " "$DEFAULT_HUB_URL"
    read INPUT
    CFG_HUB_URL="${INPUT:-$DEFAULT_HUB_URL}"
fi

# ---------- NODE_TYPE ----------
if [ -n "$ARG_NODE_TYPE" ]; then
    CFG_NODE_TYPE="$ARG_NODE_TYPE"
else
    printf "NODE_TYPE (both/master/slave) [both]: "
    read INPUT
    CFG_NODE_TYPE="${INPUT:-both}"
fi

# =========================================================
# NodePass Hub
# =========================================================

print_info "安装 NodePass Hub (端口 $CFG_PORT)"

curl -fsSL -o "$WORK_DIR/nodepass" "${GH_PROXY}${BASE_URL}/nodepass" || exit 1
chmod +x "$WORK_DIR/nodepass"

cat > /etc/systemd/system/nodepass.service <<EOF
[Unit]
Description=NodePass Hub
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

# =========================================================
# Agent
# =========================================================

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

print_info "安装完成"
