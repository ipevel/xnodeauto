# xnodeauto

Xboard 节点自动同步管理工具

## 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)
```

## 功能特性

- 自动同步 - 自动同步面板节点操作
- 多节点支持 - 支持多节点和中转机
- 手动更新 - 手动更新 xboard-node 到最新版本
- 别名管理 - 节点别名便于识别
- 开机自启 - 节点同步可设置开机自启

## 管理菜单

运行 `xnode` 进入交互式菜单：

```
1. 版本信息   - 查看组件版本
2. 修改配置   - 编辑 sync.yml
3. 节点管理   - 启停/添加/删除/别名
4. 查看日志   - 同步日志/更新日志
5. 开机自启   - 管理定时任务
6. 更新脚本   - 手动更新所有组件
7. 重新安装   - 重新安装
8. 卸载脚本   - 卸载清理
0. 退出脚本
```

## 常用命令

| 命令 | 说明 |
|------|------|
| `xnode` | 打开管理菜单 |
| `xnode status` | 查看节点状态 |
| `xnode start` | 启动所有节点 |
| `xnode stop` | 停止所有节点 |
| `xnode restart` | 重启所有节点 |
| `xnode sync` | 手动同步节点 |
| `xnode update` | 手动更新 xboard-node |
| `xnode list-nodes` | 查看节点列表 |
| `xnode add-node <ID> [别名]` | 添加节点 |
| `xnode remove-node <ID>` | 删除节点 |
| `xnode set-alias <ID> <别名>` | 设置别名 |
| `xnode log` | 查看同步日志 |
| `xnode version` | 查看版本 |
| `xnode install` | 重新安装 |
| `xnode uninstall` | 卸载 |
| `xnode config` | 修改配置 |

## 配置文件

- 主配置: `/etc/xboard-node/sync.yml`
- 节点别名: `/etc/xboard-node/node_alias.yml`
- 更新日志: `/var/log/xboard-node-update.log`

## 文件结构

```
/usr/local/bin/
├── xboard-node              # 节点程序
├── sync-nodes               # 同步程序
├── update-xboard-node.sh     # 手动更新脚本
└── xnode                    # 管理脚本

/etc/xboard-node/
├── sync.yml                 # 主配置
├── node_alias.yml           # 别名配置
└── <节点ID>.yml             # 节点配置
```

## 定时任务

- `sync-nodes.timer` - 节点自动同步（默认每小时）

## 维护

- 主仓库: https://github.com/ipevel/xnodeauto
- 节点程序: https://github.com/ipevel/Xboard-Node

## 鸣谢

- [cedar2025/Xboard-Node](https://github.com/cedar2025/Xboard-Node) - 节点程序
- [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto) - 原始项目

---

维护者: Hermes (AI Assistant)