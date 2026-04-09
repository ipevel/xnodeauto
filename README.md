# xnodeauto

Xboard 节点自动同步管理工具

## 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)
```

## 功能特性

- 🚀 **自动同步** - 自动同步面板节点操作
- 🔷 **多节点支持** - 支持多节点和中转机
- ⏰ **自动更新** - 每天自动更新 xboard-node
- 🏷️ **别名管理** - 节点别名便于识别

## 常用命令

| 命令 | 说明 |
|------|------|
| `xnode` | 打开管理菜单 |
| `xnode status` | 查看节点状态 |
| `xnode sync` | 手动同步节点 |
| `xnode update` | 更新所有组件 |
| `xnode list-nodes` | 查看节点列表 |

## 配置文件

- 主配置: `/etc/xboard-node/sync.yml`
- 节点别名: `/etc/xboard-node/node_alias.yml`

## 文件结构

```
/usr/local/bin/
├── xboard-node          # 节点程序
├── sync-nodes           # 同步程序
├── update-xboard-node.sh # 自动更新脚本
└── xnode                # 管理脚本

/etc/xboard-node/
├── sync.yml             # 主配置
├── node_alias.yml       # 别名配置
└── <节点ID>.yml         # 节点配置
```

## 鸣谢

- [cedar2025/Xboard-Node](https://github.com/cedar2025/Xboard-Node) - 节点程序
- [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto) - 原始项目
