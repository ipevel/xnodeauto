# xnodeauto

Xboard 节点自动同步管理工具

## 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)
```

## 系统要求

- 操作系统：Debian/Ubuntu 等 **systemd 发行版**（脚本依赖 `apt` 与 `systemctl`）
- 需要 **root** 权限运行安装与管理脚本
- 依赖工具：`wget`、`curl`（可选 `yq`，安装脚本会自动获取）
- 面板地址必须使用 HTTPS

> **Windows 用户部署须知**：仓库内文件以 LF 存储（见 `.gitattributes`）。若直接从 Windows 工作目录拷贝脚本到 Linux，请先转换行尾，否则 `bash` 会报 `$'\r'` 语法错误：
> ```bash
> sed -i 's/\r$//' xnode.sh install.sh update-xboard-node.sh upgrade.sh
> ```
> 推荐方式：始终从 git 检出/`git archive`/`raw.githubusercontent.com` 获取文件（已为 LF）。

## 功能特性

- 自动同步 - 自动同步面板节点操作（默认每小时）
- 多节点支持 - 支持多节点和中转机
- 手动更新 - 手动更新所有组件（xboard-node / sync-nodes / 脚本 / systemd 单元）
- 每日自动更新 - 默认启用 `update-xboard-node.timer` 每日自动更新 xboard-node（可用菜单 5 关闭）
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
| `xnode update` | 更新所有组件（xboard-node/sync-nodes/脚本/systemd 单元，自动备份回滚） |
| `xnode list-nodes` | 查看节点列表 |
| `xnode add-node <ID> [别名]` | 添加节点 |
| `xnode remove-node <ID>` | 删除节点 |
| `xnode set-alias <ID> <别名>` | 设置别名 |
| `xnode log` | 查看同步日志 |
| `xnode version` | 查看版本 |
| `xnode install` | 重新安装 |
| `xnode uninstall` | 卸载 |
| `xnode config` | 修改配置 |
| `xnode help` | 查看命令用法 |

## 配置文件

- 主配置: `/etc/xboard-node/sync.yml`
- 节点别名: `/etc/xboard-node/node_alias.yml`
- 更新日志: `/var/log/xboard-node-update.log`

## 文件结构

```
/usr/local/bin/
├── xboard-node              # 节点程序
├── sync-nodes               # 同步程序
├── update-xboard-node.sh     # 更新脚本
└── xnode                    # 管理脚本

/etc/xboard-node/
├── sync.yml                 # 主配置
├── node_alias.yml           # 别名配置
└── <节点ID>.yml             # 节点配置

/etc/systemd/system/
├── xboard-node@.service     # 节点模板服务（%i = 节点ID）
├── sync-nodes.service       # 定时同步服务
├── sync-nodes.timer         # 同步定时器（默认每小时）
├── update-xboard-node.service  # 自动更新服务
└── update-xboard-node.timer    # 更新定时器（默认每日）

/var/lock/
├── xnode-sync.lock          # 同步并发锁
└── xnode-update.lock        # 更新并发锁
```

## 定时任务

- `sync-nodes.timer` - 节点自动同步（默认**每小时**）
- `update-xboard-node.timer` - 每日自动更新 xboard-node（默认启用；`xnode` 菜单 5「开机自启」可关闭）

## 维护

- 主仓库: https://github.com/ipevel/xnodeauto
- 节点程序: https://github.com/ipevel/Xboard-Node

## 鸣谢

- [cedar2025/Xboard-Node](https://github.com/cedar2025/Xboard-Node) - 节点程序
- [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto) - 原始项目

---

维护者: Hermes (AI Assistant)