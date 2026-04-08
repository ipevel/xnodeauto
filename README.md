# Xboard 节点自动同步

自动管理 Xboard 节点，面板操作自动同步到服务器。

## 功能

- 自动同步：面板添加/删除/修改节点，服务器自动响应
- 多节点支持：一台服务器可运行多个节点
- 中转机支持：手动指定节点ID，适合中转机/CDN场景
- 自动更新：每天凌晨 3 点自动更新 xboard-node
- 节点管理：手动添加/删除节点

## 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)
```

安装时选择同步方式：
- **自动同步**：节点域名直接解析到本机IP
- **手动添加**：中转机/CDN场景（默认）

## 命令

```bash
xnode                    # 打开管理菜单
xnode status             # 查看节点状态
xnode sync               # 手动同步节点
xnode add-node <ID>      # 手动添加节点
xnode remove-node <ID>   # 删除节点
xnode update-script      # 更新管理脚本
xnode update-sync        # 更新 sync-nodes
```

## 中转机配置

编辑 `/etc/xboard-node/sync.yml`：

```yaml
xboard_url: "https://panel.example.com"
admin_path: "admin"
admin_email: "admin@example.com"
admin_password: "password"
panel_token: "your_token"

# 手动指定节点ID
manual_node_ids:
  - 1
  - 2
  - 3
```

## 常见问题

**节点没有自动启动？**
- 检查节点地址是否正确
- 手动同步：`xnode sync`
- 查看日志：`xnode log`

**中转机节点不匹配？**
- 使用 `xnode add-node <ID>` 手动添加节点

**API 401/403 错误？**
- 检查邮箱、密码、节点通信密钥是否正确
- 确认账号是管理员（`is_admin = true`）

## 许可证

MIT

## 鸣谢

- [cedar2025/Xboard-Node](https://github.com/cedar2025/Xboard-Node)
- [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto)
