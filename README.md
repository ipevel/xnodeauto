# xnodeauto

Xboard 节点自动同步管理工具

## 一键安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)
```

## 系统要求

- 操作系统：Debian/Ubuntu 等 **systemd 发行版**（脚本依赖 `apt` 与 `systemctl`）
- 需要 **root** 权限运行安装与管理脚本
- 依赖工具：`wget`、`curl`（`yq` 由安装脚本自动获取；即使安装失败，节点列表也能用纯 bash 解析，功能不受影响）
- 面板地址必须使用 HTTPS

> **Windows 用户部署须知**：仓库内文件以 LF 存储（见 `.gitattributes`）。若直接从 Windows 工作目录拷贝脚本到 Linux，请先转换行尾，否则 `bash` 会报 `$'\r'` 语法错误：
> ```bash
> sed -i 's/\r$//' xnode.sh install.sh update-xboard-node.sh upgrade.sh
> ```
> 推荐方式：始终从 git 检出/`git archive`/`raw.githubusercontent.com` 获取文件（已为 LF）。

## 从旧版本升级

老版本（v1.2.x 及更早）可**平滑升级**，推荐路径（自动备份配置、失败可回滚）：

```bash
xnode update        # 或进入菜单选「6. 更新脚本」
```

升级内容：xboard-node / sync-nodes / 管理脚本 / 更新脚本 / systemd 单元全部更新到最新版本；配置（sync.yml / node_alias.yml / 节点配置文件）自动备份并恢复，无需重填。

注意事项：
1. **不要用 `bash install.sh` 重跑来升级**——那是全新安装语义，会覆盖 sync.yml 并要求重新填写；升级请走 `xnode update`。
2. 升级后 `sync-nodes.timer` 同步频率为**每小时**（旧版本为每分钟，与本文档一致），如需更高频请自行调整 `/etc/systemd/system/sync-nodes.timer`。
3. `xboard-node` 由你**手动更新**（`xnode update`）到 Xboard-Node 仓库最新版；自动更新默认关闭，若需开启：`xnode` 菜单 5 →「4. 仅启用自动更新」。
4. 极老版本（v1.0.x）升级前建议先手动备份 `/etc/xboard-node/` 目录。

## 功能特性

- 自动同步 - 自动同步面板节点操作（默认每小时）
- 多节点支持 - 支持多节点和中转机
- 手动更新 - 手动更新所有组件（xboard-node / sync-nodes / 脚本 / systemd 单元）
- 自动更新（可选） - 默认**关闭**；需要时用 `xnode` 菜单 5 开启每日自动更新
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

## 多节点配置

一台服务器可以运行**多个节点**，每个节点对应一个 systemd 模板实例 `xboard-node@<节点ID>.service`，并拥有独立的 `/etc/xboard-node/<节点ID>.yml`。

有两种方式告诉 `sync-nodes` 本机有哪些节点：

1. **手动模式（推荐）**：在 `/etc/xboard-node/sync.yml` 里用 `manual_node_ids` 显式列出全部节点 ID，例如：

   ```yaml
   manual_node_ids:
     - 101
     - 205
     - 308
   ```

   之后用 `xnode add-node <ID>` / `xnode remove-node <ID>` 增删节点。这两个命令只会修改 `manual_node_ids` 列表里的目标条目，**不会影响其它节点**（v1.2.10 修复，v1.2.11 补齐边界场景）。

2. **自动模式**：不配置 `manual_node_ids`，由 `sync-nodes` 从面板 API 按服务器指纹自动发现节点。注意：当面板 API 为这台服务器返回 **≥2 个**匹配节点时（中转/CDN 场景常见），出于安全考虑自动模式会**拒绝执行**并提示改用手动模式。

> 多节点场景下请确认 `sync-nodes.timer`（默认每小时）与 `xnode sync` 的并发锁正常工作；`add-node` 已自动复用同一把锁，不会与定时同步互相破坏配置。

> **v1.2.11 补齐的丢 ID 路径**（v1.2.10 仍可复现，均已修复并有回归用例）：
> - 重跑 `install.sh` 会截断重写 `sync.yml`，此前会整块抹掉 `manual_node_ids` → 现在会备份并保留原有节点列表（选自动模式也保留）。
> - `manual_node_ids` 列表中间夹注释条目（如 `- # 备用线路`）会让其后的 ID 读不出来，新 ID 还会被插到注释之前 → 注释行不再结束列表扫描。
> - CRLF 行尾的 `sync.yml` 配行内列表（`manual_node_ids: [101, 205]`）时，`add-node` 会丢掉除首个以外的 ID → 读取时统一剥离 `\r`。
> - 引号 ID（`- "5"`）读不到、重复追加、`remove-node` 静默失效 → 解析容忍引号。
> - `manual_node_ids` 键带前导空格时会写出第二个同名键（YAML 将无法解析）→ 键判定统一放宽。
>
> 另外 `xnode update` 现在在版本获取失败等中途退出时，会恢复此前被停止的节点与同步定时器（此前会把节点永久停住），升级备份也不再自动删除。
>
> 安装脚本支持非交互执行：设置 `XNODE_NONINTERACTIVE=1` 并传入 `XBOARD_URL`/`ADMIN_PATH`/`ADMIN_EMAIL`/`ADMIN_PASSWORD`/`PANEL_TOKEN`（可选 `XNODE_SYNC_MODE=auto|manual`）即可，适合自动化部署。

## 配置文件

- 主配置: `/etc/xboard-node/sync.yml`（含 `manual_node_ids` 多节点列表）
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
└── update-xboard-node.timer    # 自动更新定时器（默认不启用）

/var/lock/
├── xnode-sync.lock          # 同步并发锁
└── xnode-update.lock        # 更新并发锁
```

## 定时任务

- `sync-nodes.timer` - 节点自动同步（默认**每小时**）
- `update-xboard-node.timer` - 自动更新 xboard-node（**默认不启用**，更新请手动运行 `xnode update`；如需恢复自动更新：`xnode` 菜单 5 →「4. 仅启用自动更新」）

## 维护

- 主仓库: https://github.com/ipevel/xnodeauto
- 节点程序: https://github.com/ipevel/Xboard-Node

## 鸣谢

- [cedar2025/Xboard-Node](https://github.com/cedar2025/Xboard-Node) - 节点程序
- [fuckproxy/xnodeauto](https://github.com/fuckproxy/xnodeauto) - 原始项目

---

维护者: Hermes (AI Assistant)