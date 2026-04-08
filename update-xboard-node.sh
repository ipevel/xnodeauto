#!/bin/bash
set -e

# ============================================================
# Xboard-Node 自动更新脚本
# 功能：检查并更新 xboard-node，保留所有运行中的节点
# 定时：每天凌晨3点执行
# ============================================================

LOG_FILE="/var/log/xboard-node-update.log"
XBOARD_NODE_BIN="/usr/local/bin/xboard-node"
REPO_API="https://api.github.com/repos/cedar2025/Xboard-Node/releases/latest"
ARCH=$(uname -m)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 获取架构后缀
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *)
        log "[ERROR] 不支持的架构: $ARCH"
        exit 1
        ;;
esac

log "========== 开始检查 xboard-node 更新 =========="

# 获取最新版本
LATEST_VERSION=$(wget -qO- "$REPO_API" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
if [ -z "$LATEST_VERSION" ]; then
    log "[ERROR] 无法获取最新版本"
    exit 1
fi

log "最新版本: $LATEST_VERSION"

# 获取当前版本
if [ ! -f "$XBOARD_NODE_BIN" ]; then
    log "[WARN] xboard-node 未安装，准备安装..."
    CURRENT_VERSION="未安装"
else
    CURRENT_VERSION=$($XBOARD_NODE_BIN --version 2>&1 | head -1 || echo "v0.0.0")
fi

log "当前版本: $CURRENT_VERSION"

# 比较版本
if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ] || [ "$CURRENT_VERSION" = "v$LATEST_VERSION" ]; then
    log "[INFO] 已是最新版本，无需更新"
    exit 0
fi

log "[INFO] 发现新版本，准备更新..."

# ====== 停止所有运行中的节点 ======
log "[1/4] 停止所有运行中的节点..."
RUNNING_NODES=$(systemctl list-units --all --no-legend --plain "xboard-node@*.service" | grep "xboard-node@" | awk '{print $1}')

if [ -z "$RUNNING_NODES" ]; then
    log "[INFO] 没有运行中的节点"
else
    for svc in $RUNNING_NODES; do
        log "停止 $svc"
        systemctl stop "$svc" 2>/dev/null || true
    done
fi

# ====== 下载新版本 ======
log "[2/4] 下载新版本..."
DOWNLOAD_URL="https://github.com/cedar2025/Xboard-Node/releases/download/${LATEST_VERSION}/xboard-node-linux-${ARCH_SUFFIX}"

wget -qO /tmp/xboard-node-new "$DOWNLOAD_URL" || {
    log "[ERROR] 下载失败"
    exit 1
}

# 验证下载的文件
if [ ! -s /tmp/xboard-node-new ]; then
    log "[ERROR] 下载的文件为空"
    exit 1
fi

# ====== 替换二进制 ======
log "[3/4] 替换二进制文件..."
mv "$XBOARD_NODE_BIN" "${XBOARD_NODE_BIN}.bak"  # 备份旧版本
mv /tmp/xboard-node-new "$XBOARD_NODE_BIN"
chmod +x "$XBOARD_NODE_BIN"

# 验证新版本
NEW_VERSION=$($XBOARD_NODE_BIN --version 2>&1 | head -1 || echo "未知")
log "新版本已安装: $NEW_VERSION"

# ====== 启动之前停止的节点 ======
log "[4/4] 恢复启动所有节点..."
if [ -n "$RUNNING_NODES" ]; then
    for svc in $RUNNING_NODES; do
        log "启动 $svc"
        systemctl start "$svc" 2>/dev/null || {
            log "[WARN] 启动 $svc 失败，可能是配置问题"
        }
    done
else
    log "[INFO] 没有需要恢复的节点"
fi

log "========== 更新完成 =========="
log ""

# 清理备份（7天后）
find /usr/local/bin -name "xboard-node.bak.*" -mtime +7 -delete 2>/dev/null || true