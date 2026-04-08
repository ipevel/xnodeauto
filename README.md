# Xboard 节点自动同步

自动管理 Xboard 节点，面板操作自动同步到服务器。

## 功能

- **自动同步**：面板添加/删除/修改节点，服务器自动响应
- **自动更新**：每天凌晨 3 点自动更新 xboard-node
- **交互管理**：`xnode` 命令一键管理

## 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)
```

按提示填写面板信息即可。

## 命令

| 命令 | 功能 |
|------|------|
| `xnode` | 打开管理菜单 |
| `xnode status` | 查看节点状态 |
| `xnode start/stop/restart` | 启动/停止/重启节点 |
| `xnode sync` | 手动同步 |
| `xnode update` | 更新 xboard-node |
| `xnode update-script` | 更新管理脚本 |
| `xnode enable` | 设置开机自启 |

## 常见问题

**节点没有自动启动？**

1. 检查节点地址是否填写正确（必须是这台服务器的 IP）
2. 手动同步一次：`xnode sync`
3. 查看状态：`xnode status`

**API 401/403 错误？**

管理员账号或密码不正确，确认：
- 邮箱和密码正确
- 账号是管理员（`is_admin = true`）

## 许可证

MIT

## 鸣谢

- [cedar2025/Xboard-Node](https://github.com/cedar2025/Xboard-Node)
- [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto)
