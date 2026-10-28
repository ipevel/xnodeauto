# sync-nodes 源码

`sync-nodes` 是 xnodeauto 的节点同步器：从 Xboard 面板拉节点列表，为本机需要运行的节点生成 `xboard-node` 实例配置，并管理 `xboard-node@<id>.service` 的启动、重启与停止。

从 v1.3.0 起源码随仓库发布（此前只有 release 里的预编译二进制）。

## 为什么有这一版

旧版（≤ v1.2.11）写出的实例配置只有 `panel:` 三段：

```yaml
panel:
    url: https://panel.example.com
    token: <panel_token>
    node_id: 150
```

`xboard-node` 在缺少 `kernel` 段时落到默认的 **sing-box** 内核。sing-box 不支持 `xhttp` 传输，也不支持 VLESS Encryption，于是 xhttp 节点同步时报：

```
transport "xhttp" is not supported by sing-box kernel; use xray kernel instead
```

节点起不来。v1.3.0 起默认写入 `kernel: type: xray`，并支持用 `kernel_type` 覆盖。

## 新增配置项（都可选）

```yaml
# /etc/xboard-node/sync.yml
kernel_type: xray        # xray（默认）| singbox
kernel_log_level: warn   # 传给 kernel.log_level
config_dir: /etc/xboard-node
cert_mode: none          # 写 cert.cert_mode，省略则不写 cert 段
```

## 行为

与旧版一致，未改变既有语义：

1. 用 `admin_email` / `admin_password` 登录面板（`/api/v2/passport/auth/login`），拿 `auth_data` 作为 `Authorization` 头。
2. 拉节点列表：`{xboard_url}/api/v2/{admin_path}/server/manage/getNodes`。
3. 决定跑哪些节点：
   - 配了 `manual_node_ids` → 只跑这些（面板里不存在的跳过并告警）。
   - 没配 → 自动模式：用本机网卡 IP + `https://api.ipify.org` 的公网 IP 去匹配节点 `host` 解析结果；命中 ≥2 个时**拒绝执行**并打印建议的 `manual_node_ids`（中转/CDN 场景防止误管）。
4. 为每个目标节点写 `<config_dir>/<id>.yml`，内容见上文（含 `kernel` 段）。
5. 配置有变化才 `systemctl restart`；新节点 `systemctl start`；面板里已消失的节点 `stop` + `disable` 并删配置。
6. 每次启动后轮询 `systemctl is-active`，15 秒内未 active 记一条 health check 警告（不中断同步）。

## 命令行

```
sync-nodes [--config <path>] [--node-dir <dir>] [--dry-run] [-v]
```

- `--dry-run` 只打印将要写的内容和将要执行的 systemctl 动作，不落盘、不动服务。
- `-v` 打印版本。

## 构建

```bash
go build -trimpath -ldflags "-s -w" -o sync-nodes ./cmd/sync-nodes
```

交叉编译见 `.github/workflows/release-sync-nodes.yml`（推 `v*` tag 自动出 amd64 / arm64 两个资产，文件名与 `install.sh` 期望的一致）。
