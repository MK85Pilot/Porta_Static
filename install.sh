#!/bin/bash

# =========================================================
# NodePass & Agent 组合安装脚本 (Debian)
# 逻辑: 检查 -> 下载 NodePass -> 启动验证 -> 下载 Agent -> 启动验证
# 仓库: MK85Pilot/Porta_Static (Raw)
# =========================================================

export DEBIAN_FRONTEND=noninteractive
WORK_DIR='/etc/nodepass'
GH_PROXY='https://gh-proxy.com/'
BASE_URL="https://github.com/MK85Pilot/Porta_Static/raw/refs/heads/main"

# 颜色
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
PLAIN='\033[0m'

# Root 检测
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 运行${PLAIN}" && exit 1

# --- 1. 环境与冲突检测 ---

# 架构检测
case "$(uname -m)" in
    x86_64 | amd64 ) ARCH="amd64" ;;
    aarch64 | arm64 ) ARCH="arm64" ;;
    *) echo -e "${RED}不支持的架构: $(uname -m)${PLAIN}"; exit 1 ;;
esac

# 冲突检测
if [[ -f "/etc/systemd/system/nodepass.service" ]] || [[ -f "/etc/systemd/system/nodepass-agent.service" ]]; then
    echo -e "${RED}检测到 NodePass 或 Agent 已安装!${PLAIN}"
    echo -e "请先运行卸载或手动清理 /etc/systemd/system/nodepass*.service"
    exit 1
fi

# 依赖检测
if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install -y curl
fi
mkdir -p "$WORK_DIR"

# --- 2. 参数处理 ---

# 参数1: 端口
INPUT_PORT="$1"
# 参数2: Agent 参数
INPUT_AGENT_ARGS="$2"

echo -e "========================================"
echo -e "   NodePass & Agent 组合安装"
echo -e "   架构: ${CYAN}$ARCH${PLAIN}"
echo -e "========================================"

# 处理端口
if [[ -n "$INPUT_PORT" ]]; then
    PORT="$INPUT_PORT"
else
    # 交互输入
    read -rp "请输入 NodePass 端口 (回车随机): " PORT
    [[ -z "$PORT" ]] && PORT=$((RANDOM % 64511 + 1024))
fi

# 处理 Agent 参数 (如果脚本参数没传，必须交互)
if [[ -z "$INPUT_AGENT_ARGS" ]]; then
    echo -e "${YELLOW}请输入 Agent 启动参数 (例如: client://key@ip:port)${PLAIN}"
    read -rp "> " AGENT_ARGS
else
    AGENT_ARGS="$INPUT_AGENT_ARGS"
fi

# 最终非空校验
if [[ -z "$AGENT_ARGS" ]]; then
    echo -e "${RED}错误: Agent 参数不能为空${PLAIN}"; exit 1
fi

# --- 3. 安装 NodePass ---

echo -e "\n${GREEN}>>> 第一步: 安装 NodePass 服务端${PLAIN}"
echo -e "端口: ${CYAN}$PORT${PLAIN} | TLS: ${CYAN}开启${PLAIN}"

# 下载
NP_FILE="nodepass_linux_${ARCH}"
echo -e "正在下载: $NP_FILE ..."
curl -L -f -o "$WORK_DIR/server" "${GH_PROXY}${BASE_URL}/${NP_FILE}"

if [[ ! -s "$WORK_DIR/server" ]]; then
    echo -e "${RED}NodePass 下载失败，请检查网络或仓库文件${PLAIN}"; exit 1
fi
chmod +x "$WORK_DIR/server"

# 创建服务 (TLS 默认 1)
cat > "/etc/systemd/system/nodepass.service" << EOF
[Unit]
Description=NodePass Server
After=network.target

[Service]
Type=simple
ExecStart=$WORK_DIR/server master://127.0.0.1:${PORT}/api?tls=1
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
sleep 2
if ! systemctl is-active --quiet nodepass; then
    echo -e "${RED}NodePass 启动失败! 停止安装流程。${PLAIN}"
    systemctl status nodepass --no-pager
    exit 1
else
    echo -e "${GREEN}NodePass 启动成功!${PLAIN}"
fi

# --- 4. 安装 Agent ---

echo -e "\n${GREEN}>>> 第二步: 安装 Agent 中间件${PLAIN}"
echo -e "参数: ${CYAN}$AGENT_ARGS${PLAIN}"

# 下载
AGENT_FILE="agent_linux_${ARCH}"
echo -e "正在下载: $AGENT_FILE ..."
curl -L -f -o "$WORK_DIR/agent_bin" "${GH_PROXY}${BASE_URL}/${AGENT_FILE}"

if [[ ! -s "$WORK_DIR/agent_bin" ]]; then
    echo -e "${RED}Agent 下载失败${PLAIN}"; exit 1
fi
chmod +x "$WORK_DIR/agent_bin"

# 创建服务
cat > "/etc/systemd/system/nodepass-agent.service" << EOF
[Unit]
Description=NodePass Agent
After=network.target nodepass.service

[Service]
Type=simple
ExecStart=$WORK_DIR/agent_bin $AGENT_ARGS
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
    echo -e "${RED}Agent 启动失败! 请检查参数是否正确。${PLAIN}"
    systemctl status nodepass-agent --no-pager
    exit 1
else
    echo -e "${GREEN}Agent 启动成功!${PLAIN}"
fi

# --- 5. 完成 ---

echo -e "\n========================================"
echo -e "   全部安装完成"
echo -e "========================================"
echo -e "服务端状态: ${GREEN}运行中${PLAIN} (端口: $PORT)"
echo -e "中间件状态: ${GREEN}运行中${PLAIN}"
echo -e "配置文件目录: $WORK_DIR"
echo -e "查看日志:"
echo -e "  journalctl -u nodepass -f"
echo -e "  journalctl -u nodepass-agent -f"
echo -e "========================================"
