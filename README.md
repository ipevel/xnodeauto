# xnodeauto

Xboard 节点自动同步管理工具。

## 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)
```

## 命令

```bash
xnode                    # 管理菜单
xnode status             # 节点状态
xnode sync               # 手动同步
xnode add-node <ID>      # 添加节点
xnode update             # 更新 xboard-node
xnode update-script      # 更新管理脚本
xnode log                # 查看日志
```

## 配置文件

- 主配置: `/etc/xboard-node/sync.yml`
- 节点别名: `/etc/xboard-node/node_alias.yml`

## 特性

- 🚀 自动同步面板节点操作
- 🔷 支持多节点和中转机
- ⏰ 每天自动更新 xboard-node
- 🏷️ 节点别名管理

## 文件结构

```
/usr/local/bin/
├── xboard-node          # 节点程序
├── sync-nodes           # 同步程序
└── xnode                # 管理脚本

/etc/xboard-node/
├── sync.yml             # 主配置
├── node_alias.yml       # 别名配置
└── <节点ID>.yml         # 节点配置
```

## 鸣谢

- [cedar2025/Xboard-Node](https://github.com/cedar2025/Xboard-Node) - 节点程序
- [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto) - 原始项目
