#!/bin/bash

# =========================================================
# NodePass & Agent 安装脚本 (Debian Only)
# 仓库: MK85Pilot/Porta_Static
# 说明: 支持分别安装服务端(NodePass)和中间件(Agent)
# 日期: 2025-01-18
# =========================================================

# --- 基础配置 ---
export DEBIAN_FRONTEND=noninteractive
WORK_DIR='/etc/nodepass'
GH_PROXY='https://gh-proxy.com/'
REPO_OWNER="MK85Pilot"
REPO_NAME="Porta_Static"

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
PLAIN='\033[0m'

# --- 检查 Root ---
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：请使用 root 用户运行此脚本。${PLAIN}" && exit 1

# --- 帮助信息 ---
show_help() {
    echo -e "用法: $0 [选项]"
    echo -e "  --type [nodepass|agent] 安装类型：服务端(nodepass) 或 中间件(agent)"
    echo -e "  --port [PORT]           服务端端口 (仅 nodepass 模式)"
    echo -e "  --tls [0|1]             服务端是否开启 TLS (仅 nodepass 模式, 默认0)"
    echo -e "  --args [STRING]         Agent 启动参数 (仅 agent 模式, 例如连接地址)"
    echo -e "  --help                  显示帮助"
}

# --- 参数解析 ---
MODE="interactive"
INSTALL_TYPE=""
ARG_PORT=""
ARG_TLS="0"
ARG_ARGS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type) INSTALL_TYPE="$2"; MODE="cli"; shift 2 ;;
        --port) ARG_PORT="$2"; shift 2 ;;
        --tls)  ARG_TLS="$2"; shift 2 ;;
        --args) ARG_ARGS="$2"; shift 2 ;;
        --help) show_help; exit 0 ;;
        *) shift ;;
    esac
done

# --- 核心工具函数 ---

check_deps() {
    # 检查 jq，用于解析 GitHub API
    if ! command -v jq &> /dev/null || ! command -v curl &> /dev/null; then
        echo -e "${GREEN}正在安装依赖 (curl, wget, jq, tar)...${PLAIN}"
        apt-get update -y
        apt-get install -y curl wget jq tar
    fi
    mkdir -p "$WORK_DIR"
}

check_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64 | amd64 ) FILE_ARCH="amd64" ;;
        aarch64 | arm64 ) FILE_ARCH="arm64" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${PLAIN}"; exit 1 ;;
    esac
}

get_release_info() {
    echo -e "${GREEN}正在获取 $REPO_OWNER/$REPO_NAME 最新版本信息...${PLAIN}"
    API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
    
    RELEASE_JSON=$(curl -sL "${GH_PROXY}$API_URL")
    TAG_NAME=$(echo "$RELEASE_JSON" | jq -r .tag_name)
    
    if [[ "$TAG_NAME" == "null" || -z "$TAG_NAME" ]]; then
        echo -e "${RED}获取版本失败，请检查网络或 GitHub API 限制。${PLAIN}"
        exit 1
    fi
    echo -e "最新版本: ${CYAN}$TAG_NAME${PLAIN} (架构: $FILE_ARCH)"
}

# 下载函数
# 参数1: 搜索关键词 (nodepass 或 agent)
# 参数2: 保存的文件名 (nodepass_server 或 nodepass_agent)
download_binary() {
    KEYWORD="$1"
    SAVE_NAME="$2"

    echo -e "${GREEN}正在搜索包含 '$KEYWORD' 和 '$FILE_ARCH' 的文件...${PLAIN}"

    # 使用 jq 过滤包含 keyword, linux 和 arch 的文件名
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r --arg k "$KEYWORD" --arg a "$FILE_ARCH" '.assets[] | select(.name | contains($k)) | select(.name | contains($a)) | select(.name | contains("linux")) | .browser_download_url' | head -n 1)

    if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
        echo -e "${RED}未在 Release 中找到匹配 '$KEYWORD' 的文件。${PLAIN}"
        echo -e "请检查仓库 Release 是否包含带有 '$KEYWORD', 'linux' 和 '$FILE_ARCH' 的文件。"
        exit 1
    fi

    echo -e "下载地址: $DOWNLOAD_URL"
    curl -L -o "$WORK_DIR/$SAVE_NAME" "${GH_PROXY}${DOWNLOAD_URL}"

    if [[ ! -s "$WORK_DIR/$SAVE_NAME" ]]; then
        echo -e "${RED}下载失败或文件为空。${PLAIN}"
        exit 1
    fi

    chmod +x "$WORK_DIR/$SAVE_NAME"
    echo -e "${GREEN}下载并安装成功: $WORK_DIR/$SAVE_NAME${PLAIN}"
}

create_service() {
    SERVICE_NAME="$1"
    BIN_PATH="$2"
    EXEC_ARGS="$3"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    echo -e "${GREEN}正在创建/更新服务: $SERVICE_NAME${PLAIN}"

    # 停止旧服务
    systemctl stop "$SERVICE_NAME" 2>/dev/null

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=NodePass Project - $SERVICE_NAME
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH $EXEC_ARGS
Restart=always
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
}

verify_status() {
    SERVICE_NAME="$1"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "\n========================================"
        echo -e " 状态: ${GREEN}运行中 (Active)${PLAIN}"
        echo -e " 服务: $SERVICE_NAME"
        echo -e " 日志: journalctl -u $SERVICE_NAME -f"
        echo -e "========================================"
    else
        echo -e "\n${RED}服务启动失败！请检查下方日志:${PLAIN}"
        systemctl status "$SERVICE_NAME" --no-pager
        echo -e "${YELLOW}提示: 请检查端口是否被占用或参数是否正确。${PLAIN}"
    fi
}

# --- 业务逻辑 ---

install_nodepass() {
    echo -e "\n=== 安装 NodePass (服务端) ==="
    
    # 1. 获取配置
    if [[ "$MODE" == "interactive" ]]; then
        read -rp "请输入监听端口 (默认随机 1024-65535): " PORT
        [[ -z "$PORT" ]] && PORT=$((RANDOM % 64511 + 1024))
        
        echo -e "是否开启 TLS?"
        echo "0. 关闭 (默认)"
        echo "1. 开启"
        read -rp "请选择: " TLS_MODE
        [[ "$TLS_MODE" != "1" ]] && TLS_MODE="0"
    else
        PORT=${ARG_PORT:-$((RANDOM % 64511 + 1024))}
        TLS_MODE=${ARG_TLS:-0}
    fi

    # 2. 下载
    download_binary "nodepass" "nodepass_server"

    # 3. 启动
    CMD_ARGS="master://0.0.0.0:${PORT}/api?tls=${TLS_MODE}"
    echo -e "启动参数: ${CYAN}$CMD_ARGS${PLAIN}"
    
    create_service "nodepass" "$WORK_DIR/nodepass_server" "$CMD_ARGS"
    verify_status "nodepass"
}

install_agent() {
    echo -e "\n=== 安装 Agent (中间件) ==="

    # 1. 获取配置
    if [[ "$MODE" == "interactive" ]]; then
        echo -e "${YELLOW}请输入 Agent 的完整启动参数${PLAIN}"
        echo -e "说明: 这通常是连接到服务端的字符串，例如: client://uuid@ip:port"
        read -rp "启动参数: " AGENT_ARGS
        while [[ -z "$AGENT_ARGS" ]]; do
            echo -e "${RED}参数不能为空${PLAIN}"
            read -rp "启动参数: " AGENT_ARGS
        done
    else
        AGENT_ARGS="$ARG_ARGS"
        if [[ -z "$AGENT_ARGS" ]]; then
            echo -e "${RED}错误: 自动模式安装 Agent 必须提供 --args 参数${PLAIN}"
            exit 1
        fi
    fi

    # 2. 下载
    download_binary "agent" "nodepass_agent"

    # 3. 启动
    echo -e "启动参数: ${CYAN}$AGENT_ARGS${PLAIN}"
    
    create_service "nodepass-agent" "$WORK_DIR/nodepass_agent" "$AGENT_ARGS"
    verify_status "nodepass-agent"
}

# --- 主程序 ---

check_deps
check_arch
get_release_info

if [[ "$MODE" == "interactive" ]]; then
    clear
    echo "========================================"
    echo "   NodePass & Agent 安装程序"
    echo "   仓库: $REPO_OWNER/$REPO_NAME"
    echo "   架构: $FILE_ARCH"
    echo "========================================"
    echo " 1. 安装 NodePass (服务端)"
    echo " 2. 安装 Agent (中间件)"
    echo " 0. 退出"
    echo "========================================"
    read -rp "请输入选项: " CHOICE
    
    case "$CHOICE" in
        1) install_nodepass ;;
        2) install_agent ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${PLAIN}"; exit 1 ;;
    esac
else
    # 命令行模式
    case "$INSTALL_TYPE" in
        nodepass|server) install_nodepass ;;
        agent|middleware) install_agent ;;
        *) 
            echo -e "${RED}错误: 未知类型 --type $INSTALL_TYPE${PLAIN}"
            show_help
            exit 1 
            ;;
    esac
fi
