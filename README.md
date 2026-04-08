# Xboard 节点自动同步

自动管理 Xboard 节点，面板操作自动同步到服务器。

## 功能

- **自动同步**：面板添加/删除/修改节点，服务器自动响应
- **多节点支持**：一台服务器可运行多个节点
- **中转机支持**：支持中转机/CDN 场景（手动指定节点ID）
- **自动更新**：每天凌晨 3 点自动更新 xboard-node
- **交互管理**：`xnode` 命令一键管理
- **节点管理**：手动添加/删除节点

## 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)
```

按提示填写面板信息即可。

## 命令

### 基本命令

| 命令 | 功能 |
|------|------|
| `xnode` | 打开管理菜单 |
| `xnode status` | 查看节点状态 |
| `xnode start/stop/restart` | 启动/停止/重启节点 |
| `xnode sync` | 手动同步 |
| `xnode update` | 更新 xboard-node |
| `xnode update-script` | 更新管理脚本 |
| `xnode update-sync` | 更新 sync-nodes |
| `xnode enable` | 设置开机自启 |

### 节点管理命令

| 命令 | 功能 |
|------|------|
| `xnode list-nodes` | 列出所有节点 |
| `xnode add-node <ID>` | 手动添加节点 |
| `xnode remove-node <ID>` | 手动删除节点 |

## 中转机场景配置

如果使用中转机或 CDN，域名解析的 IP 不是服务器实际 IP，需要手动指定节点 ID。

编辑 `/etc/xboard-node/sync.yml`：

```yaml
xboard_url: "https://panel.example.com"
admin_path: "admin"
admin_email: "admin@example.com"
admin_password: "password"

# 手动指定节点ID（用于中转机场景）
manual_node_ids:
  - 1
  - 2
  - 3
```

**优先级**：
1. 如果配置了 `manual_node_ids` → 使用手动指定的节点
2. 如果没有配置 → 使用 IP 自动匹配

**注意**：
- `manual_node_ids` 不会影响自动匹配的节点
- 手动节点和自动节点可以共存

## 菂点管理

### 列出所有节点

```bash
xnode list-nodes
```

输出示例：
```
节点列表:

手动配置的节点: 1 2 3

  ● 节点 1 - 运行中
  ● 节点 2 - 运行中
  ○ 节点 3 - 已停止
```

### 手动添加节点

```bash
xnode add-node 1
```

功能：
- 添加节点 ID 到 `sync.yml` 配置文件
- 自动触发同步

### 手动删除节点

```bash
xnode remove-node 1
```

功能：
- 停止节点服务
- 禁用节点服务
- 删除节点配置文件
- 从 `sync.yml` 中移除节点 ID
- 完全删除节点信息

## 常见问题

**节点没有自动启动？**

1. 检查节点地址是否填写正确（必须是这台服务器的 IP）
2. 手动同步一次：`xnode sync`
3. 查看状态：`xnode status`

**中转机场景节点不匹配？**

配置 `manual_node_ids` 手动指定节点 ID，详见 [中转机场景配置](#中转机场景配置)

**API 401/403 错误？**

管理员账号或密码不正确，确认：
- 邮箱和密码正确
- 账号是管理员（`is_admin = true`）

**如何测试 Beta 版本？**

```bash
# 更新管理脚本
xnode update-script

# 手动下载 beta 版本
wget -O /usr/local/bin/sync-nodes https://github.com/ipevel/xnodeauto/releases/download/v1.2.0-beta/sync-nodes-linux-amd64
chmod +x /usr/local/bin/sync-nodes
```

## 版本历史

### v1.2.0-beta (当前)
- ✅ 新增中转机支持（`manual_node_ids` 配置）
- ✅ 新增节点管理命令（`add-node`, `remove-node`, `list-nodes`）
- ✅ 完全删除节点功能
- ⚠️ Beta 版本，请在测试环境验证

### v1.1.0
- ✅ sync-nodes 优化（健康检查、日志规范化、版本信息）
- ✅ 新增 `xnode update-sync` 命令
- ✅ 使用 Go 1.24.2 编译

### v1.0.0
- ✅ 初始版本
- ✅ 自动同步节点
- ✅ 自动更新 xboard-node
- ✅ 交互管理菜单

## 许可证

MIT

## 鸣谢

- [cedar2025/Xboard-Node](https://github.com/cedar2025/Xboard-Node)
- [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto)
