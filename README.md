# Xboard 节点自动同步 + 自动更新

这是一个帮你自动管理 Xboard 节点的工具。

## 🎯 它能做什么？

### 1. 自动同步节点
- **面板添加节点** → 服务器自动启动节点服务
- **面板删除节点** → 服务器自动停止节点服务
- **修改节点配置** → 服务器自动更新并重启

**简单说**：你只需要在 Xboard 面板上操作，服务器会自动跟着变，不用再 SSH 登录服务器手动操作了！

### 2. 自动更新 xboard-node（新增功能）
- 每天凌晨 3 点自动检查更新
- 发现新版本自动下载更新
- 更新后自动恢复所有运行中的节点
- 更新日志记录在 `/var/log/xboard-node-update.log`

### 3. 交互式管理命令
- 输入 `xnode` 直接打开管理菜单
- 支持命令行参数快速操作
- 一键管理所有节点

---

## 📋 准备工作

在安装之前，你需要准备以下信息：

| 信息 | 从哪里获取 | 举例 |
|------|-----------|------|
| 面板地址 | 你的 Xboard 网站地址 | `https://panel.example.com` |
| 后台路径 | 登录后台时的 URL 中的一段 | 如果后台是 `https://panel.example.com/abc12345#/`，那后台路径就是 `abc12345` |
| 管理员邮箱 | 你登录后台的邮箱 | `admin@example.com` |
| 管理员密码 | 你登录后台的密码 | `yourpassword123` |
| 节点通信密钥 | 后台 → 系统设置 → 节点通信密钥 | `node_comm_token_xxx` |

---

## 🚀 一键安装

### 步骤 1：SSH 登录你的服务器

```bash
ssh root@你的服务器IP
```

### 步骤 2：执行安装命令

把下面的信息替换成你自己的，然后复制执行：

```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh) \
  --url https://你的面板地址.com \
  --admin-path 你的后台路径 \
  --admin-email 你的管理员邮箱 \
  --admin-password 你的管理员密码 \
  --panel-token 你的节点通信密钥
```

### 步骤 3：设置开机自启

```bash
xnode enable
```

---

## 💻 管理命令

安装完成后，你可以使用 `xnode` 命令来管理：

### 交互式菜单

直接输入 `xnode` 打开管理菜单：

```
  xnodeauto 管理脚本
--- https://github.com/ipevel/xnodeauto ---
  0. 修改配置文件
————————————————
  1. 查看所有节点状态
  2. 启动所有节点
  3. 停止所有节点
  4. 重启所有节点
  5. 手动同步节点
  6. 更新 xboard-node
————————————————
  7. 查看同步日志
  8. 查看更新日志
————————————————
  9. 设置开机自启
  10. 取消开机自启
————————————————
  11. 查看版本信息
  12. 安装/重新安装
  13. 卸载
  14. 退出脚本
```

### 命令行快速操作

| 命令 | 功能 |
|------|------|
| `xnode` | 打开管理菜单 |
| `xnode status` | 查看所有节点状态 |
| `xnode start` | 启动所有节点 |
| `xnode stop` | 停止所有节点 |
| `xnode restart` | 重启所有节点 |
| `xnode sync` | 手动同步节点 |
| `xnode update` | 更新 xboard-node |
| `xnode config` | 修改配置文件 |
| `xnode log` | 查看同步日志 |
| `xnode updatelog` | 查看更新日志 |
| `xnode enable` | 设置开机自启 |
| `xnode disable` | 取消开机自启 |
| `xnode version` | 查看版本信息 |
| `xnode uninstall` | 卸载 |

---

## 📖 详细说明

### 工作原理（通俗版）

```
┌─────────────────┐
│  Xboard 面板     │  ← 你在这里添加/删除节点
│  (网站后台)      │
└────────┬────────┘
         │
         ↓ 每60秒检查一次
┌─────────────────┐
│  sync-nodes     │  ← 同步脚本，对比面板和服务器
│  (同步脚本)      │
└────────┬────────┘
         │
         ↓ 发现差异就自动操作
┌─────────────────┐
│  服务器上的节点   │  ← 自动启动/停止/重启
│  (xboard-node)  │
└─────────────────┘
```

### 节点如何被自动认领？

脚本会自动检测服务器的 IP 地址（包括公网 IP 和内网 IP）。

当你在面板添加节点时，**节点的"节点地址"填写这台服务器的 IP 或域名**，脚本就会自动认领这个节点并启动它。

**示例**：
- 服务器 IP 是 `1.2.3.4`
- 在面板添加节点，节点地址填 `1.2.3.4` 或 `node.example.com`（解析到 1.2.3.4）
- 脚本检测到这个节点的地址指向本机，自动启动

---

## ❓ 常见问题

### 1. 安装后节点没有自动启动？

**检查步骤**：
```bash
# 1. 手动运行一次，看报什么错
xnode sync

# 2. 查看状态
xnode status
```

**可能原因**：
- 节点的"节点地址"填写不正确，不是这台服务器的 IP
- 节点的"节点地址"填的是域名，但域名还没解析到这台服务器

### 2. 提示 API 401/403 错误？

**原因**：管理员账号或密码不正确

**解决方法**：
1. 确认邮箱和密码正确
2. 确认这个账号是管理员（`is_admin = true`）
3. 重新运行安装命令，带上正确的参数

### 3. 多个 IP 识别不到？

脚本会自动探测：
- 本地网卡的 IP（通过 UDP 连接探测）
- 公网 IP（通过 api.ipify.org 获取）

如果还是识别不到，可以提 issue 反馈。

### 4. 想换一个面板怎么办？

**方法一**：修改配置文件
```bash
xnode config
```

**方法二**：重新运行安装命令
```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh) \
  --url https://新面板地址 \
  --admin-path 新后台路径 \
  --admin-email 新邮箱 \
  --admin-password 新密码 \
  --panel-token 新通信密钥
```

### 5. 如何卸载？

```bash
xnode uninstall
```

---

## 📁 文件位置

| 文件 | 路径 | 说明 |
|------|------|------|
| 配置文件 | `/etc/xboard-node/sync.yml` | 面板登录信息 |
| 节点配置 | `/etc/xboard-node/1.yml` | 节点1的配置 |
| 同步程序 | `/usr/local/bin/sync-nodes` | 同步脚本 |
| 节点程序 | `/usr/local/bin/xboard-node` | 节点主程序 |
| 更新脚本 | `/usr/local/bin/update-xboard-node.sh` | 自动更新脚本 |
| 管理脚本 | `/usr/bin/xnode` | 管理命令 |
| 更新日志 | `/var/log/xboard-node-update.log` | 更新日志 |

---

## 📜 许可证

MIT

---

## 🙏 鸣谢

基于 [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto) 修改，增加了：
- 自动更新功能
- 交互式管理菜单
- 一键管理命令
