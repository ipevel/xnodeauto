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

---

## 📋 准备工作

在安装之前，你需要准备以下信息：

| 信息 | 从哪里获取 | 举例 |
|------|-----------|------|
| 面板地址 | 你的 Xboard 网站地址 | `example.com` |
| 后台路径 | 登录后台时的 URL 中的一段 | 如果后台是 `example.com/abc12345#/`，那后台路径就是 `abc12345` |
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
  --url https://你的面板地址 \
  --admin-path 你的后台路径 \
  --admin-email 你的管理员邮箱 \
  --admin-password 你的管理员密码 \
  --panel-token 你的节点通信密钥
```

### 步骤 3：验证安装

```bash
# 手动测试一次同步
sync-nodes

# 查看输出，应该显示类似：
# [INFO] my ips: [1.2.3.4]
# [+] started node 1 (节点名称)
```

### 步骤 4：启用自动功能

```bash
# 启用节点自动同步（每60秒检查一次）
systemctl enable --now sync-nodes.timer

# 启用自动更新（每天凌晨3点检查更新）
systemctl enable --now update-xboard-node.timer
```

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

## 🔧 常用命令

### 查看状态

```bash
# 查看所有正在运行的节点
systemctl list-units 'xboard-node@*'

# 查看某个具体节点的状态
systemctl status xboard-node@1

# 查看同步服务状态
systemctl status sync-nodes.timer

# 查看自动更新服务状态
systemctl status update-xboard-node.timer
```

### 查看日志

```bash
# 查看同步日志（实时）
journalctl -u sync-nodes.service -f

# 查看某个节点的日志
journalctl -u xboard-node@1 -f

# 查看自动更新日志
tail -f /var/log/xboard-node-update.log
```

### 手动操作

```bash
# 手动触发一次同步
sync-nodes

# 手动触发一次更新检查
/usr/local/bin/update-xboard-node.sh

# 手动停止某个节点
systemctl stop xboard-node@1

# 手动启动某个节点
systemctl start xboard-node@1
```

### 停用自动功能

```bash
# 停止自动同步
systemctl disable --now sync-nodes.timer

# 停止自动更新
systemctl disable --now update-xboard-node.timer
```

---

## ❓ 常见问题

### 1. 安装后节点没有自动启动？

**检查步骤**：
```bash
# 1. 手动运行一次，看报什么错
sync-nodes

# 2. 检查 IP 是否被识别
# 输出应该包含 [INFO] my ips: [你的IP]
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

重新运行安装命令，带上新的参数即可：

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
# 停止所有服务
systemctl disable --now sync-nodes.timer
systemctl disable --now update-xboard-node.timer

# 停止所有节点
systemctl stop 'xboard-node@*'

# 删除文件
rm -rf /usr/local/bin/sync-nodes
rm -rf /usr/local/bin/xboard-node
rm -rf /usr/local/bin/update-xboard-node.sh
rm -rf /etc/xboard-node
rm -rf /etc/systemd/system/xboard-node@.service
rm -rf /etc/systemd/system/sync-nodes.*
rm -rf /etc/systemd/system/update-xboard-node.*

# 重载 systemd
systemctl daemon-reload
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
| 更新日志 | `/var/log/xboard-node-update.log` | 更新日志 |

---

## 📜 许可证

MIT

---

## 🙏 鸣谢

基于 [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto) 修改，增加了自动更新功能。
