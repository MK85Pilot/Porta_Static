# NodePass 安装脚本

NodePass Hub、NodePass 和 Agent 的自动化安装脚本，支持智能检测、配置管理和服务部署。

## 组件介绍

### 1. Conduit（Hub 服务器）
- **服务名**：`conduit.service`
- **可执行文件**：`/etc/nodepass/hub`
- **配置文件**：`/etc/nodepass/hub.env`
- **作用**：作为中心服务器，提供 WebSocket 服务、API 接口、Telegram Bot 集成
- **安装方式**：使用环境变量 `INSTALL_HUB=true` 安装

### 2. NodePass（本地节点）
- **服务名**：`nodepass.service`
- **可执行文件**：`/etc/nodepass/nodepass`
- **作用**：本地 NodePass 节点，监听指定端口提供服务
- **启动命令**：`nodepass master://0.0.0.0:PORT/api?tls=1`

### 3. Agent（代理）
- **服务名**：`nodepass-agent.service`
- **可执行文件**：`/etc/nodepass/agent`
- **配置文件**：`/etc/nodepass/.env`
- **作用**：连接到 Hub 服务器，执行管理任务

## 系统要求

- **操作系统**：Linux（支持 systemd）
- **权限**：需要 root 权限
- **依赖**：curl（脚本会自动安装）
- **Conduit 依赖**：MySQL 数据库

## 快速开始

### 安装 NodePass 和 Agent（交互式）

```bash
sudo sh install.sh
```

### 安装 Conduit 服务器（交互式）

```bash
sudo INSTALL_HUB=true sh install.sh
```

### 安装所有组件（环境变量自动化）

```bash
sudo AUTH_TOKEN=your-token HUB_ADDRESS=127.0.0.1:8088 INSTALL_HUB=true sh install.sh
```

### 卸载所有组件

```bash
sudo sh install.sh uninstall
```

## 环境变量

| 环境变量 | 说明 | 必需 | 示例 |
|---------|------|------|------|
| `INSTALL_HUB` | 安装 Conduit 服务器 | 否 | `INSTALL_HUB=true` |
| `AUTH_TOKEN` | Agent 认证令牌 | 是（Agent） | `AUTH_TOKEN=abc123` |
| `HUB_ADDRESS` | Hub 服务器地址 | 否 | `HUB_ADDRESS=192.168.1.100:8088` |
| `NODE_TYPE` | Agent 节点类型 | 否 | `NODE_TYPE=both` |
| `NODEPASS_PORT` | NodePass 监听端口 | 否 | `NODEPASS_PORT=18080` |
| `WS_PROTOCOL` | WebSocket 协议 | 否 | `WS_PROTOCOL=ws` 或 `WS_PROTOCOL=wss` |

## 使用场景

### 场景 1：只安装 NodePass 和 Agent（交互式）

```bash
sudo sh install.sh
```

**交互式配置**：
```
========================================
 NodePass Agent 安装
========================================

========================================
 Agent 配置
========================================
AUTH_TOKEN (用于 Agent 连接 Hub 的认证令牌): my-token

本地 NodePass 节点监听端口 (格式: 18080): 18080
WebSocket 协议 (格式: ws 或 wss): ws
Hub 服务器地址 (格式: 192.168.1.100:8088 或 hub.example.com:8088): 192.168.1.100:8088
Agent 节点类型 (格式: both 或 master 或 slave): both

安装 NodePass (端口 18080)
安装 Agent
安装完成
```

### 场景 2：安装 Conduit 服务器（交互式）

```bash
sudo INSTALL_HUB=true sh install.sh
```

**交互式配置**：
```
========================================
 Hub 服务器配置
========================================

服务器绑定地址 (格式: 0.0.0.0:8088): 0.0.0.0:8088

MySQL 数据库配置
数据库地址 (格式: mysql.example.com): mysql.example.com
数据库端口 (格式: 3306): 3306
数据库用户名 (格式: agent-ws): agent-ws
数据库名 (格式: agent-ws): agent-ws
数据库密码 (留空随机生成): 

系统配置
系统基础 URL (格式: https://portal.example.com): https://portal.example.com

Telegram Bot 配置
Bot Token (从 @BotFather 获取): 6457274789:AAE7hvDnGLLBS-1669Y4T-t6l4JG4eW8zDk
Bot 用户名 (格式: Portforward_bot): Portforward_bot
Webhook URL (留空使用默认): 

安装 Hub 服务器
Hub 安装完成
重要信息已保存到 /etc/nodepass/hub.env
管理员默认密码: aB3$xK9#mP2@nQ7R
```

### 场景 3：使用环境变量自动化安装

```bash
sudo AUTH_TOKEN=my-token HUB_ADDRESS=192.168.1.100:8088 WS_PROTOCOL=ws NODE_TYPE=both NODEPASS_PORT=18080 INSTALL_HUB=true sh install.sh
```

**输出**：
```
========================================
 NodePass Agent 安装
========================================

========================================
 Agent 配置
========================================
...

========================================
 Hub 服务器配置
========================================
...

安装 Hub 服务器
Hub 安装完成
安装 NodePass (端口 18080)
安装 Agent
安装完成
```

### 场景 4：更新配置

当所有组件都已安装时：

```bash
sudo sh install.sh
```

**交互式更新**：
```
检测到 Conduit 已安装，将跳过安装
检测到 NodePass 已安装，将跳过安装
检测到 Agent 已安装，将跳过安装
所有组件已安装
是否更新配置文件? (y/N): y

========================================
 配置更新
========================================

选择要更新的配置：
  1. Agent 配置 (连接 Hub 的配置)
  2. Hub 服务器配置 (服务器运行配置)

请输入选项编号 (1-2，多个用空格分隔，更新全部直接回车): 
```

## 配置文件说明

### Conduit 配置文件（/etc/nodepass/hub.env）

```bash
# 服务器绑定地址
BIND_ADDRESS=0.0.0.0:8088

# MySQL 数据库配置
DB_HOST=mysql.example.com
DB_PORT=3306
DB_USER=agent-ws
DB_PASSWORD=random-password
DB_NAME=agent-ws

# API 密钥（64位随机字符串）
API_KEY=your-api-key

# JWT 配置
JWT_SECRET=your-jwt-secret
JWT_ISSUER=hub-api

# 管理员默认密码（16位随机密码）
ADMIN_DEFAULT_PASSWORD=admin-password

# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=bot-token
TELEGRAM_BOT_USERNAME=bot-username

# 系统基础URL
BASE_URL=https://portal.example.com

# Telegram Webhook URL
TELEGRAM_WEBHOOK_URL=https://portal.example.com/api/v1/telegram/webhook
```

### Agent 配置文件（/etc/nodepass/.env）

```bash
# Hub 服务器地址
HUB_URL=ws://127.0.0.1:8088/ws/agent

# 认证令牌
AUTH_TOKEN=your-token

# 节点类型
NODE_TYPE=both

# 日志级别
LOG_LEVEL=info
```

## 服务管理

### 查看服务状态

```bash
# Conduit
systemctl status conduit

# NodePass
systemctl status nodepass

# Agent
systemctl status nodepass-agent
```

### 启动/停止/重启服务

```bash
# 启动
sudo systemctl start conduit nodepass nodepass-agent

# 停止
sudo systemctl stop conduit nodepass nodepass-agent

# 重启
sudo systemctl restart conduit nodepass nodepass-agent
```

### 开机自启

```bash
# 启用
sudo systemctl enable conduit nodepass nodepass-agent

# 禁用
sudo systemctl disable conduit nodepass nodepass-agent
```

### 查看日志

```bash
# 实时日志
sudo journalctl -u conduit -f
sudo journalctl -u nodepass -f
sudo journalctl -u nodepass-agent -f

# 最近100条日志
sudo journalctl -u conduit -n 100
```

### 查看配置文件

```bash
# Conduit 配置
cat /etc/nodepass/hub.env

# Agent 配置
cat /etc/nodepass/.env
```

## 配置参数说明

### Conduit 配置参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| BIND_ADDRESS | 服务器绑定地址 | `0.0.0.0:8088` |
| DB_HOST | MySQL 数据库地址 | 用户输入 |
| DB_PORT | MySQL 数据库端口 | `3306` |
| DB_USER | MySQL 用户名 | `agent-ws` |
| DB_PASSWORD | MySQL 密码 | 随机生成（32位） |
| DB_NAME | 数据库名 | `agent-ws` |
| API_KEY | API 密钥 | 随机生成（64位） |
| JWT_SECRET | JWT 密钥 | 随机生成（64位） |
| JWT_ISSUER | JWT 发布者 | `hub-api` |
| ADMIN_DEFAULT_PASSWORD | 管理员密码 | 随机生成（16位） |
| TELEGRAM_BOT_TOKEN | Telegram Bot Token | 用户输入 |
| TELEGRAM_BOT_USERNAME | Telegram Bot 用户名 | 用户输入 |
| BASE_URL | 系统基础 URL | 用户输入 |
| TELEGRAM_WEBHOOK_URL | Telegram Webhook URL | `{BASE_URL}/api/v1/telegram/webhook` |

### Agent 配置参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| HUB_URL | Hub 服务器地址 | `ws://127.0.0.1:8088/ws/agent` |
| AUTH_TOKEN | 认证令牌 | 用户输入 |
| NODE_TYPE | 节点类型 | `both` |
| LOG_LEVEL | 日志级别 | `info` |

## 节点类型说明

- **both**：同时作为主节点和从节点
- **master**：仅作为主节点
- **slave**：仅作为从节点

## WebSocket 协议说明

- **ws**：非加密连接，用于内网或开发环境
- **wss**：加密连接（SSL/TLS），用于生产环境

## HUB_URL 自动构建规则

```bash
CFG_HUB_URL="${CFG_WS_PROTO}://${CFG_HUB_ADDR}/ws/agent"
```

**示例**：
- 输入 `192.168.1.100:8088` + ws → `ws://192.168.1.100:8088/ws/agent`
- 输入 `hub.example.com:443` + wss → `wss://hub.example.com:443/ws/agent`
- 输入 `myhub.com:8080` + ws → `ws://myhub.com:8080/ws/agent`

## 重要提示

1. **Conduit 是独立服务器**：必须使用 `INSTALL_HUB=true` 环境变量安装
2. **随机密钥**：API_KEY、JWT_SECRET、管理员密码会自动随机生成
3. **配置备份**：所有配置保存在 `/etc/nodepass/` 目录
4. **管理员密码**：安装完成后会显示管理员密码，请妥善保存
5. **数据库依赖**：Conduit 需要 MySQL 数据库支持
6. **Telegram Bot**：需要提供有效的 Telegram Bot Token（从 @BotFather 获取）
7. **智能检测**：脚本会自动检测已安装组件并跳过重复安装
8. **配置更新**：所有组件已安装时可以选择更新配置

## 故障排查

### Conduit 无法启动

1. 检查 MySQL 数据库连接
2. 查看 MySQL 服务状态：`systemctl status mysql`
3. 查看 Conduit 日志：`journalctl -u conduit -f`

### Agent 无法连接 Conduit

1. 检查 HUB_URL 配置是否正确
2. 检查网络连接
3. 查看 Agent 日志：`journalctl -u nodepass-agent -f`
4. 确认 AUTH_TOKEN 是否正确

### 服务无法启动

1. 检查配置文件语法
2. 查看服务日志
3. 确认端口未被占用
4. 检查文件权限

## 卸载

```bash
sudo sh install.sh uninstall
```

卸载操作会：
1. 停止所有服务
2. 禁用开机自启
3. 删除 systemd 服务文件
4. 删除工作目录 `/etc/nodepass/`

## 目录结构

```
/etc/nodepass/
├── hub              # Conduit 可执行文件
├── nodepass         # NodePass 可执行文件
├── agent            # Agent 可执行文件
├── hub.env          # Conduit 配置文件
└── .env             # Agent 配置文件

/etc/systemd/system/
├── conduit.service          # Conduit 服务文件
├── nodepass.service       # NodePass 服务文件
└── nodepass-agent.service # Agent 服务文件
```

## 随机密钥生成

脚本包含两个随机生成函数：

```bash
generate_random_string 64    # 生成 64 位随机字符串（字母+数字）
generate_random_password 16   # 生成 16 位随机密码（字母+数字+特殊字符）
```

## 许可证

本脚本遵循相关开源许可证。

## 支持

如有问题或建议，请提交 Issue 或 Pull Request。
