#!/usr/bin/env python3
"""
Xboard 节点同步器
- 从 Xboard 面板拉取节点列表
- 自动识别 host 等于本机对外 IP 的节点
- 对比本机 systemd 实例,自动 start/stop/restart
"""
import os
import sys
import socket
import subprocess
from pathlib import Path

import yaml
import requests

# ============ 配置 ============
SYNC_CONFIG_PATH = Path("/etc/xboard-node/sync.yml")
CONFIG_DIR       = Path("/etc/xboard-node")
SERVICE_NAME     = "xboard-node@{}.service"
REQUEST_TIMEOUT  = 10

def load_config():
    if not SYNC_CONFIG_PATH.exists():
        print(f"[ERR] config not found: {SYNC_CONFIG_PATH}", file=sys.stderr)
        print("  Run: cp sync.example.yml /etc/xboard-node/sync.yml && edit it", file=sys.stderr)
        sys.exit(1)
    cfg = yaml.safe_load(SYNC_CONFIG_PATH.read_text())
    missing = [k for k in ("xboard_url", "admin_path", "admin_email", "admin_password", "panel_token") if not cfg.get(k)]
    if missing:
        print(f"[ERR] missing config keys: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)
    return cfg

CFG = load_config()
XBOARD_URL     = CFG["xboard_url"]
ADMIN_PATH     = CFG["admin_path"]
ADMIN_EMAIL    = CFG["admin_email"]
ADMIN_PASSWORD = CFG["admin_password"]
PANEL_TOKEN    = CFG["panel_token"]
# ================================


# ---------- IP 探测 ----------

def get_my_ips():
    """拿本机所有可能的对外 IP(本地出口网卡 + 公网探测)"""
    ips = set()

    # 本地出口网卡 IP(不真发包,只是让内核选路由)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.add(s.getsockname()[0])
        s.close()
    except Exception as e:
        print(f"[WARN] local ip detect failed: {e}", file=sys.stderr)

    # 公网出口 IP(NAT 后面的机器需要这个)
    try:
        r = requests.get("https://api.ipify.org", timeout=5)
        ips.add(r.text.strip())
    except Exception as e:
        print(f"[WARN] public ip detect failed: {e}", file=sys.stderr)

    return ips


def host_to_ip(host):
    """域名或 IP 都解析成 IP"""
    if not host:
        return None
    try:
        return socket.gethostbyname(host)
    except Exception:
        return None


MY_IPS = get_my_ips()


# ---------- Xboard API ----------

TOKEN_CACHE = CONFIG_DIR / ".token"


def login():
    """用 admin 账号密码登录,拿到 Bearer token"""
    url = f"{XBOARD_URL}/api/v2/passport/auth/login"
    r = requests.post(url, json={
        "email": ADMIN_EMAIL,
        "password": ADMIN_PASSWORD,
    }, timeout=REQUEST_TIMEOUT)
    r.raise_for_status()
    data = r.json().get("data", {})
    token = data.get("auth_data") or data.get("token")
    if not token:
        raise RuntimeError(f"login response has no token: {data}")
    TOKEN_CACHE.write_text(token)
    TOKEN_CACHE.chmod(0o600)
    return token


def get_token():
    """优先用缓存的 token,失败了再重新登录"""
    if TOKEN_CACHE.exists():
        return TOKEN_CACHE.read_text().strip()
    return login()


def fetch_nodes():
    """从 Xboard 拉全量节点,token 过期自动重登"""
    token = get_token()
    url = f"{XBOARD_URL}/api/v2/{ADMIN_PATH}/server/manage/getNodes"
    r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=REQUEST_TIMEOUT)
    if r.status_code == 401 or r.status_code == 403:
        print("[INFO] token expired, re-login...")
        token = login()
        r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=REQUEST_TIMEOUT)
    r.raise_for_status()
    return r.json().get("data", [])


def my_nodes(all_nodes):
    """节点 host 解析后命中本机任一 IP,就是自己的"""
    return [n for n in all_nodes
            if host_to_ip(n.get("host", "")) in MY_IPS]


# ---------- 配置文件管理 ----------

def write_config(node):
    """为一个节点写 config.yml,返回是否有变化"""
    node_id = node["id"]
    cfg = {
        "panel": {
            "url":     XBOARD_URL,
            "token":   PANEL_TOKEN,
            "node_id": node_id,
        }
    }
    path = CONFIG_DIR / f"{node_id}.yml"
    new_content = yaml.safe_dump(cfg)
    if path.exists() and path.read_text() == new_content:
        return False
    path.write_text(new_content)
    return True


# ---------- systemd 操作 ----------

def running_instances():
    """列出当前机器上所有 xboard-node@N 实例的 node_id"""
    r = subprocess.run(
        ["systemctl", "list-units", "--all", "--no-legend",
         "--plain", "xboard-node@*.service"],
        capture_output=True, text=True,
    )
    ids = set()
    for line in r.stdout.strip().splitlines():
        parts = line.split()
        if not parts:
            continue
        unit = parts[0]
        try:
            node_id = unit.split("@")[1].split(".")[0]
            if node_id.isdigit():
                ids.add(int(node_id))
        except IndexError:
            continue
    return ids


def systemctl(action, node_id):
    unit = SERVICE_NAME.format(node_id)
    subprocess.run(["systemctl", action, unit], check=False)


# ---------- 主流程 ----------

def main():
    if not MY_IPS:
        print("[ERR] could not detect any local IP, abort", file=sys.stderr)
        sys.exit(1)

    print(f"[INFO] my ips: {sorted(MY_IPS)}")

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    try:
        all_nodes = fetch_nodes()
    except Exception as e:
        print(f"[ERR] fetch nodes failed: {e}", file=sys.stderr)
        sys.exit(1)

    wanted = my_nodes(all_nodes)
    wanted_ids = {n["id"] for n in wanted}
    current_ids = running_instances()

    to_add    = wanted_ids - current_ids
    to_remove = current_ids - wanted_ids
    to_check  = wanted_ids & current_ids

    for n in wanted:
        if n["id"] in to_add:
            write_config(n)
            systemctl("enable", n["id"])
            systemctl("start", n["id"])
            print(f"[+] started node {n['id']} ({n.get('name', '')})")

    for nid in to_remove:
        systemctl("stop", nid)
        systemctl("disable", nid)
        print(f"[-] stopped node {nid}")

    for n in wanted:
        if n["id"] in to_check:
            if write_config(n):
                systemctl("restart", n["id"])
                print(f"[~] restarted node {n['id']} (config changed)")

    if not (to_add or to_remove):
        print(f"[INFO] no changes, {len(wanted_ids)} nodes running")


if __name__ == "__main__":
    main()
