# Xboard 节点自动同步

自动管理 Xboard 节点，面板操作自动同步到服务器。

## ✨ 特性

- 🚀 **自动同步**：面板添加/删除/修改节点，服务器自动响应
- 🔷 **多节点支持**：一台服务器可运行多个节点
- 🔄 **中转机支持**：手动指定节点ID，适合中转机/CDN场景
- ⏰ **自动更新**：每天凌晨 3 点自动更新 xboard-node
- 🏷️ **节点别名**：为节点设置易记的别名
- 🎨 **美化界面**：TUI 安装向导，美观的输出格式
- 📊 **进度显示**：长时间操作显示进度条

## 📦 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)
```

安装时选择同步方式：
- **自动同步**：节点域名直接解析到本机IP
- **手动添加**：中转机/CDN场景（默认推荐）

## 🎯 快速开始

### 基本命令

```bash
xnode                    # 打开管理菜单
xnode status             # 查看节点状态
xnode sync               # 手动同步节点
xnode list-nodes         # 列出所有节点
xnode log                # 查看同步日志
```

### 节点管理

```bash
xnode add-node <ID>              # 添加节点
xnode add-node <ID> <别名>        # 添加节点并设置别名
xnode remove-node <ID>           # 删除节点
xnode set-alias <ID> <别名>       # 设置节点别名
```

### 更新命令

```bash
xnode update           # 更新 xboard-node
xnode update-script    # 更新管理脚本
xnode update-sync      # 更新 sync-nodes
```

## 📋 菜单功能

```
╔══════════════════════════════════════════════════════════════╗
║                  xnodeauto 管理菜单                          ║
╚══════════════════════════════════════════════════════════════╝

  [0] 修改配置文件
  
  [1] 查看节点状态
  [2] 节点操作（启动/停止/重启）
  [3] 手动同步节点
  
  [4] 更新（xboard-node/脚本/sync-nodes）
  
  [5] 节点管理（列表/添加/删除/别名）
  
  [6] 查看日志（同步/更新）
  
  [7] 开机自启（切换）
  [8] 查看版本信息
  
  [9] 安装/重新安装
  [10] 卸载
  
  [11] 退出脚本
```

## 🏷️ 节点别名

为节点设置易记的别名：

```bash
# 设置别名
xnode set-alias 1 香港节点
xnode set-alias 2 美国节点
xnode set-alias 3 日本节点

# 查看节点列表（显示别名）
xnode list-nodes

# 输出示例：
  节点ID  别名              状态      
  ──────  ────────────────  ────────
  1       香港节点          ● 运行中
  2       美国节点          ○ 已停止
  3       日本节点          ● 运行中
```

别名配置文件：`/etc/xboard-node/node_alias.yml`

## ⚙️ 配置文件

### 主配置文件

**路径**：`/etc/xboard-node/sync.yml`

```yaml
xboard_url: "https://panel.example.com"
admin_path: "admin"
admin_email: "admin@example.com"
admin_password: "password"
panel_token: "your_token"

# 手动指定节点ID（可选）
manual_node_ids:
  - 1
  - 2
  - 3
```

### 节点配置文件

**路径**：`/etc/xboard-node/<节点ID>.yml`

每个节点一个独立的配置文件，由 sync-nodes 自动生成。

## 🔧 高级配置

### 中转机配置

如果一台服务器运行多个节点（中转机场景），使用手动模式：

```bash
# 安装时选择"手动添加"模式
# 或手动编辑配置文件

# 添加节点
xnode add-node 1 香港节点
xnode add-node 2 美国节点
xnode add-node 3 日本节点
```

### 自动更新时间

自动更新默认在凌晨 3 点执行，可以通过修改 systemd timer 调整：

```bash
# 编辑定时器
systemctl edit update-xboard-node.timer

# 修改执行时间
[Timer]
OnCalendar=*-*-* 04:00:00  # 改为凌晨 4 点
```

### 同步频率

节点同步默认每分钟执行一次，可以通过修改 systemd timer 调整：

```bash
# 编辑定时器
systemctl edit sync-nodes.timer

# 修改同步频率
[Timer]
OnUnitActiveSec=5m  # 改为每 5 分钟
```

## 🚨 安全策略

### 自动匹配规则

当使用自动同步模式时，脚本会检测节点域名解析：

| 检测结果 | 行为 |
|----------|------|
| 0 个节点 | ✅ 正常运行（无节点需要启动） |
| 1 个节点 | ✅ 自动启动该节点 |
| ≥2 个节点 | ❌ 停止并提示使用手动模式 |

这是为了防止中转机场景下的误操作。

### 中转机场景

对于中转机/CDN场景，**必须**使用手动模式：

```bash
# 方式1：安装时选择手动模式
# 方式2：编辑配置文件添加 manual_node_ids

# 推荐使用命令添加
xnode add-node <节点ID>
```

## 📊 日志查看

### 同步日志

```bash
xnode log
# 或
journalctl -u sync-nodes.service -f
```

### 更新日志

```bash
tail -f /var/log/xboard-node-update.log
```

### 节点日志

```bash
journalctl -u xboard-node@<节点ID>.service -f
```

## 🔍 故障排查

### 节点没有启动

```bash
# 检查同步状态
xnode sync

# 查看节点状态
xnode status

# 查看同步日志
xnode log
```

### API 401/403 错误

- 检查邮箱、密码是否正确
- 检查节点通信密钥是否正确
- 确认账号是管理员（`is_admin = true`）

### 节点域名解析失败

```bash
# 测试域名解析
nslookup node.example.com

# 检查本机IP
curl ip.sb
```

## 📁 文件结构

```
/usr/local/bin/
├── xboard-node          # 节点程序
├── sync-nodes           # 同步程序
├── update-xboard-node.sh # 自动更新脚本
└── xnode                # 管理脚本

/etc/xboard-node/
├── sync.yml             # 主配置文件
├── node_alias.yml       # 节点别名配置
├── .token               # Token 缓存
├── 1.yml                # 节点1配置
├── 2.yml                # 节点2配置
└── ...

/etc/systemd/system/
├── xboard-node@.service # 节点服务模板
├── sync-nodes.service   # 同步服务
├── sync-nodes.timer     # 同步定时器
├── update-xboard-node.service # 自动更新服务
└── update-xboard-node.timer   # 自动更新定时器
```

## 🆕 更新日志

### v1.2.1

- ✨ TUI 安装向导（美观的 ASCII 艺术 Banner）
- 🎨 美化输出格式（Unicode 图标、颜色、边框）
- 🏷️ 节点别名功能
- 📊 长时间操作显示进度条
- 🔧 改进用户体验

### v1.2.0

- ✨ 手动节点管理命令
- 🔒 安全策略改进（≥2个节点时停止自动添加）
- 🐛 修复卸载 Bug

### v1.1.0

- ✨ sync-nodes 更新功能
- 🔒 安全编译参数
- 📦 Go 版本升级

### v1.0.0

- 🎉 初始版本

## 📝 许可证

MIT

## 🙏 鸣谢

- [cedar2025/Xboard-Node](https://github.com/cedar2025/Xboard-Node)
- [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto)
