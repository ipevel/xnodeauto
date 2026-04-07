# Xboard Node Auto-Sync

面板加节点 → 本机自动起 xboard-node;面板删节点 → 自动停。无需 SSH。

## 工作原理

```
Xboard 面板 API (getNodes)
    ↓
sync-nodes.py (每 60s)
    ↓ 对比 host=本机IP 的节点 vs 本机 systemd 实例
    ↓
xboard-node@<node_id>.service → 读 /etc/xboard-node/<node_id>.yml
```

节点 `host` 解析后等于本机 IP → 自动认领,面板加节点时 host 填对即可。

## 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/githubactions/xnodeauto/main/install.sh) \
  --url https://your-panel.com \
  --admin-path your-secure-path \
  --admin-email admin@example.com \
  --admin-password your-password \
  --panel-token node-comm-token
```

脚本幂等,可重复执行。带参数时会更新配置,不带参数时不会覆盖已有配置。

**参数说明:**

| 参数 | 来源 |
|------|------|
| `--url` | 面板地址 |
| `--admin-path` | 面板后台 URL 里 `/api/v2/{这一段}/...`,即 `secure_path` |
| `--admin-email` | 面板管理员邮箱 |
| `--admin-password` | 面板管理员密码 |
| `--panel-token` | 面板后台 → 系统设置 → 节点通信密钥 |

## 验证 & 启用

```bash
# 1. 手动跑一次,看输出是否正常
python3 /usr/local/bin/sync-nodes.py

# 2. 确认节点在跑
systemctl status xboard-node@<node_id>

# 3. 启用定时同步
systemctl enable --now sync-nodes.timer
```

## 日志

```bash
journalctl -u sync-nodes.service -f      # 同步脚本日志
journalctl -u xboard-node@1.service -f   # 某个节点日志
```

## 常见问题

**API 401/403** — 确认 admin 账号是管理员 (`is_admin = true`),用 F12 抓请求对比格式。

**多 IP 识别不到** — 编辑 `/usr/local/bin/sync-nodes.py`,在 `MY_IPS = get_my_ips()` 后加 `MY_IPS.add("1.2.3.4")`。

## 许可

MIT
