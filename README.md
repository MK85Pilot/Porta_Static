---

# Porta Static Installer

用于快速部署 **nodepass 及其 agent** 的一键安装脚本。

---

## 使用方法

在服务器上执行以下命令：

```bash
bash <(curl -fsSL https://github.com/MK85Pilot/Porta_Static/raw/refs/heads/main/install.sh)
```

---

## 安装说明

* 脚本以 **交互式方式** 运行
* 会询问是否安装：

  * `nodepass`
  * `agent`
* **nodepass 与 agent 为前置必需组件，必须先完成安装**

---

## 适用环境

* Linux 服务器
* 需要 root 或 sudo 权限
* 需能访问 GitHub

---

## 说明

本脚本仅用于初始化与安装基础组件，后续功能基于 nodepass 与 agent 扩展。

---
