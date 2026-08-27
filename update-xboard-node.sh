#!/bin/bash

# ============================================================
# Xboard-Node 手动更新脚本
# 功能：手动更新 xboard-node 到最新版本
# 用法：手动运行或 xnode update 调用
# ============================================================

LOG_FILE="/var/log/xboard-node-update.log"
XBOARD_NODE_BIN="/usr/local/bin/xboard-node"
REPO_API="https://api.github.com/repos/ipevel/Xboard-Node/releases/latest"
ARCH=$(uname -m)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    log "[ERROR] 必须使用 root 用户运行此脚本！"
    exit 1
fi

# 获取架构后缀
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *)
        log "[ERROR] 不支持的架构: $ARCH"
        exit 1
        ;;
esac

log "========== 开始更新 xboard-node =========="

# 并发锁：防止与 update_all / 定时任务同时运行（EXIT trap 统一释放）
exec 9>/var/lock/xnode-update.lock 2>/dev/null || true
if ! flock -n 9 2>/dev/null; then
    log "[WARN] 已有更新任务在运行，本次跳过"
    exit 0
fi
trap 'flock -u 9 2>/dev/null; exec 9>&- 2>/dev/null || true; [ -n "${TMP_FILE:-}" ] && rm -f "$TMP_FILE"' EXIT

# 获取最新版本
LATEST_VERSION=$(wget -qO- --timeout=15 "$REPO_API" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
if [ -z "$LATEST_VERSION" ]; then
    log "[ERROR] 无法获取最新版本"
    exit 1
fi

log "最新版本: $LATEST_VERSION"

# 获取当前版本
CURRENT_VERSION="未知"
if [ -x "$XBOARD_NODE_BIN" ]; then
    CURRENT_VERSION=$($XBOARD_NODE_BIN -v 2>&1 | head -1)
    [ -z "$CURRENT_VERSION" ] && CURRENT_VERSION="未知"
fi

log "当前版本: $CURRENT_VERSION"

# 版本比较：已是最新则跳过下载与重启
version_ge() {
    test "$(printf '%s\n' "$1" "$2" | sort -V | head -n 1)" == "$2"
}
CURRENT_VER_NUM=$(echo "$CURRENT_VERSION" | grep -oE '[vV]?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
LATEST_VER_NUM=$(echo "$LATEST_VERSION" | grep -oE '[vV]?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -n "$CURRENT_VER_NUM" ] && [ -n "$LATEST_VER_NUM" ] && version_ge "$CURRENT_VER_NUM" "$LATEST_VER_NUM"; then
    log "[INFO] 当前版本 ($CURRENT_VER_NUM) 已是最新，无需更新"
    log "========== 更新结束（已是最新） =========="
    exit 0
fi

# ====== 停止所有运行中的节点 ======
log "[1/4] 停止所有运行中的节点..."
RUNNING_NODES=$(systemctl list-units --type=service --state=running --no-legend --plain "xboard-node@*.service" | grep "xboard-node@" | awk '{print $1}')

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
DOWNLOAD_URL="https://github.com/ipevel/Xboard-Node/releases/download/${LATEST_VERSION}/xboard-node-linux-${ARCH_SUFFIX}"

# 下载到 mktemp 临时文件（防固定路径符号链接/TOCTOU 攻击）
TMP_FILE="$(mktemp /tmp/xboard-node-new.XXXXXX)" || { log "[ERROR] 创建临时文件失败"; exit 1; }

wget --timeout=300 -qO "$TMP_FILE" "$DOWNLOAD_URL" || {
    log "[ERROR] 下载失败"
    exit 1
}

# 验证下载的文件
if [ ! -s "$TMP_FILE" ]; then
    log "[ERROR] 下载的文件为空"
    exit 1
fi

# 基础安全校验：检查文件是否可执行
if [ ! -x "$TMP_FILE" ]; then
    log "[ERROR] 下载的文件无执行权限"
    exit 1
fi

# 检查文件 magic bytes (ELF magic)
if ! head -c 4 "$TMP_FILE" 2>/dev/null | grep -q $'\x7fELF'; then
    log "[ERROR] 下载的文件不是有效的 ELF 可执行文件"
    exit 1
fi

# ====== 替换二进制（备份带时间戳，失败自动回滚）======
log "[3/4] 替换二进制文件..."
BAK_FILE="${XBOARD_NODE_BIN}.bak.$(date +%Y%m%d_%H%M%S)"
if [ -f "$XBOARD_NODE_BIN" ]; then
    cp -f "$XBOARD_NODE_BIN" "$BAK_FILE"
fi

mv -f "$TMP_FILE" "$XBOARD_NODE_BIN"
chmod +x "$XBOARD_NODE_BIN"

# 验证新版本
NEW_VERSION=$($XBOARD_NODE_BIN -v 2>&1 | head -1)
if [ -z "$NEW_VERSION" ]; then
    log "[ERROR] 新版本验证失败，回滚到备份..."
    if [ -f "$BAK_FILE" ]; then
        mv -f "$BAK_FILE" "$XBOARD_NODE_BIN"
        log "[INFO] 已自动回滚到备份版本"
    else
        log "[ERROR] 无可用备份，请手动恢复旧二进制"
    fi
    exit 1
fi
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

# 清理备份
find /usr/local/bin -name "xboard-node.bak.*" -mtime +7 -delete 2>/dev/null || true