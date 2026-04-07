#!/bin/bash
set -e

# ============================================================
# Xboard Node Auto-Sync 一键安装脚本
#
# 用法:
#   bash <(curl -sL https://raw.githubusercontent.com/fuckproxy/xnodeauto/main/install.sh) \
#     --url https://panel.example.com \
#     --admin-path abc12345 \
#     --admin-email admin@example.com \
#     --admin-password your-password \
#     --panel-token node-comm-token
# ============================================================

REPO_RAW="https://raw.githubusercontent.com/fuckproxy/xnodeauto/main"
REPO_API="https://api.github.com/repos/fuckproxy/xnodeauto/releases/latest"

# ---------- 解析参数 ----------
XBOARD_URL=""
ADMIN_PATH=""
ADMIN_EMAIL=""
ADMIN_PASSWORD=""
PANEL_TOKEN=""

while [ $# -gt 0 ]; do
    case "$1" in
        --url)            XBOARD_URL="$2";     shift 2 ;;
        --admin-path)     ADMIN_PATH="$2";     shift 2 ;;
        --admin-email)    ADMIN_EMAIL="$2";    shift 2 ;;
        --admin-password) ADMIN_PASSWORD="$2"; shift 2 ;;
        --panel-token)    PANEL_TOKEN="$2";    shift 2 ;;
        *)
            echo "[ERR] Unknown option: $1"
            echo "Usage: $0 --url <url> --admin-path <path> --admin-email <email> --admin-password <pwd> --panel-token <token>"
            exit 1
            ;;
    esac
done

echo "=== Xboard Node Auto-Sync Installer ==="

# ---------- 1. 系统依赖 ----------
echo "[1/7] Installing system dependencies..."
apt update
apt install -y wget

# ---------- 架构检测 ----------
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *)
        echo "[ERR] Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# ---------- 2. 下载 xboard-node 二进制 ----------
echo "[2/7] Downloading xboard-node binary..."

XBOARD_NODE_VERSION=$(wget -qO- "https://api.github.com/repos/cedar2025/Xboard-Node/releases/latest" \
  | grep '"tag_name"' | head -1 | cut -d'"' -f4)

if [ -z "$XBOARD_NODE_VERSION" ]; then
    echo "[WARN] Failed to fetch latest version, falling back to v1.0.2"
    XBOARD_NODE_VERSION="v1.0.2"
fi

echo "  xboard-node version: ${XBOARD_NODE_VERSION}"

DOWNLOAD_URL="https://github.com/cedar2025/Xboard-Node/releases/download/${XBOARD_NODE_VERSION}/xboard-node-linux-${ARCH_SUFFIX}"

if [ ! -f /usr/local/bin/xboard-node ]; then
    wget -O /usr/local/bin/xboard-node "$DOWNLOAD_URL"
    chmod +x /usr/local/bin/xboard-node
    echo "  Downloaded xboard-node (${ARCH_SUFFIX})"
else
    echo "  /usr/local/bin/xboard-node already exists, skipping"
fi

# ---------- 3. 下载 sync-nodes 二进制 ----------
echo "[3/7] Downloading sync-nodes binary..."

SYNC_VERSION=$(wget -qO- "$REPO_API" | grep '"tag_name"' | head -1 | cut -d'"' -f4)

if [ -z "$SYNC_VERSION" ]; then
    echo "[WARN] Failed to fetch sync-nodes version, downloading from main branch"
    wget -qO /usr/local/bin/sync-nodes "${REPO_RAW}/sync-nodes-linux-${ARCH_SUFFIX}"
else
    echo "  sync-nodes version: ${SYNC_VERSION}"
    wget -qO /usr/local/bin/sync-nodes "https://github.com/fuckproxy/xnodeauto/releases/download/${SYNC_VERSION}/sync-nodes-linux-${ARCH_SUFFIX}"
fi
chmod +x /usr/local/bin/sync-nodes

# ---------- 4. 创建配置目录 ----------
echo "[4/7] Creating config directory..."
mkdir -p /etc/xboard-node

# ---------- 5. 下载并安装 systemd 文件 ----------
echo "[5/7] Installing systemd unit files..."
wget -qO /etc/systemd/system/xboard-node@.service  "${REPO_RAW}/systemd/xboard-node@.service"
wget -qO /etc/systemd/system/sync-nodes.service     "${REPO_RAW}/systemd/sync-nodes.service"
wget -qO /etc/systemd/system/sync-nodes.timer       "${REPO_RAW}/systemd/sync-nodes.timer"

# ---------- 6. 写入配置 ----------
echo "[6/7] Writing config..."

if [ -n "$XBOARD_URL" ] && [ -n "$ADMIN_PATH" ] && [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASSWORD" ] && [ -n "$PANEL_TOKEN" ]; then
    cat > /etc/xboard-node/sync.yml << EOF
xboard_url: "${XBOARD_URL}"
admin_path: "${ADMIN_PATH}"
admin_email: "${ADMIN_EMAIL}"
admin_password: "${ADMIN_PASSWORD}"
panel_token: "${PANEL_TOKEN}"
EOF
    chmod 600 /etc/xboard-node/sync.yml
    echo "  Config written to /etc/xboard-node/sync.yml"
elif [ ! -f /etc/xboard-node/sync.yml ]; then
    wget -qO /etc/xboard-node/sync.yml "${REPO_RAW}/sync.example.yml"
    chmod 600 /etc/xboard-node/sync.yml
    echo "  [WARN] No config params provided, created example config"
    echo "  Please edit /etc/xboard-node/sync.yml before enabling the timer"
fi

# ---------- 7. 重载 systemd ----------
echo "[7/7] Reloading systemd..."
systemctl daemon-reload

# ---------- 完成提示 ----------
echo ""
echo "============================================"
echo "  Installation complete!"
echo "============================================"
echo ""

if [ -n "$XBOARD_URL" ] && [ -n "$ADMIN_PATH" ] && [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASSWORD" ] && [ -n "$PANEL_TOKEN" ]; then
    echo "Config is ready. Quick verify:"
    echo ""
    echo "  1. Test sync:  sync-nodes"
    echo "  2. Enable:     systemctl enable --now sync-nodes.timer"
else
    echo "Next steps:"
    echo ""
    echo "  1. Edit /etc/xboard-node/sync.yml"
    echo "  2. Test sync:  sync-nodes"
    echo "  3. Enable:     systemctl enable --now sync-nodes.timer"
fi
echo ""
