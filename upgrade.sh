#!/bin/bash

# ============================================================
# xnodeauto 无损升级脚本
# 用途：从老版本无损升级到最新版本
# 特点：保留所有配置文件和节点别名
# ============================================================

set -e

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

# 图标
ICON_OK="✅"
ICON_ERR="❌"
ICON_WARN="⚠️"
ICON_INFO="ℹ️"
ICON_ROCKET="🚀"
ICON_GEAR="⚙️"
ICON_ARROW="→"

# 备份目录
BACKUP_DIR="/tmp/xnode-backup-$(date +%Y%m%d_%H%M%S)"

# 显示标题
echo -e "${cyan}"
cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║                xnodeauto 无损升级脚本                         ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${plain}"
echo ""

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}${ICON_ERR} 错误：${plain} 必须使用 root 用户运行此脚本！"
    exit 1
fi

# 检查是否已安装
if [[ ! -f /etc/xboard-node/sync.yml ]]; then
    echo -e "${red}${ICON_ERR} 错误：${plain} 未检测到已安装的 xnodeauto"
    echo -e "${ICON_INFO} 请先运行安装脚本: bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)"
    exit 1
fi

echo -e "${ICON_INFO} 开始无损升级..."
echo ""

# ========== 1. 备份配置 ==========
echo -e "${cyan}[1/6]${plain} 备份配置文件..."
mkdir -p "$BACKUP_DIR"

# 备份所有配置文件
if [[ -d /etc/xboard-node ]]; then
    cp -a /etc/xboard-node/* "$BACKUP_DIR/" 2>/dev/null || true
    echo -e "  ${ICON_OK} 配置已备份到: ${cyan}$BACKUP_DIR${plain}"
else
    echo -e "  ${ICON_WARN} 未找到配置目录"
fi

# ========== 2. 停止服务 ==========
echo ""
echo -e "${cyan}[2/6]${plain} 停止所有服务..."

# 停止所有 xboard-node 服务
for svc in $(systemctl list-units --all --no-legend --plain "xboard-node@*.service" 2>/dev/null | grep "xboard-node@" | awk '{print $1}'); do
    echo -e "  ${ICON_ARROW} 停止 $svc"
    systemctl stop "$svc" 2>/dev/null || true
done

# 停止定时服务
systemctl stop sync-nodes.timer 2>/dev/null || true
systemctl stop update-xboard-node.timer 2>/dev/null || true
systemctl stop sync-nodes.service 2>/dev/null || true

echo -e "  ${ICON_OK} 服务已停止"

# ========== 3. 检测架构 ==========
echo ""
echo -e "${cyan}[3/6]${plain} 检测系统架构..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *)
        echo -e "${red}${ICON_ERR} 不支持的架构: $ARCH${plain}"
        exit 1
        ;;
esac
echo -e "  ${ICON_OK} 架构: ${cyan}$ARCH ($ARCH_SUFFIX)${plain}"

# ========== 4. 获取最新版本 ==========
echo ""
echo -e "${cyan}[4/6]${plain} 获取最新版本..."

# 获取 sync-nodes 版本
SYNC_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/xnodeauto/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
if [[ -z "$SYNC_VERSION" ]]; then
    SYNC_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/xnodeauto/releases" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
fi
[[ -z "$SYNC_VERSION" ]] && SYNC_VERSION="v1.2.5"
echo -e "  ${ICON_INFO} sync-nodes: ${cyan}$SYNC_VERSION${plain}"

# 获取 xboard-node 版本
XBOARD_NODE_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/Xboard-Node/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
if [[ -z "$XBOARD_NODE_VERSION" ]]; then
    XBOARD_NODE_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/Xboard-Node/releases" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
fi
[[ -z "$XBOARD_NODE_VERSION" ]] && XBOARD_NODE_VERSION="v1.0.2"
echo -e "  ${ICON_INFO} xboard-node: ${cyan}$XBOARD_NODE_VERSION${plain}"

# ========== 5. 下载最新组件 ==========
echo ""
echo -e "${cyan}[5/6]${plain} 下载最新组件..."
echo ""

# 下载 sync-nodes
echo -e "  ${ICON_ARROW} 下载 sync-nodes ($SYNC_VERSION)"
SYNC_URL="https://github.com/ipevel/xnodeauto/releases/download/${SYNC_VERSION}/sync-nodes-linux-${ARCH_SUFFIX}"
if wget -q --show-progress -O /usr/local/bin/sync-nodes "$SYNC_URL" 2>&1; then
    chmod +x /usr/local/bin/sync-nodes
    echo -e "  ${ICON_OK} sync-nodes 更新完成"
else
    echo -e "  ${ICON_ERR} sync-nodes 下载失败"
    echo -e "  ${ICON_INFO} URL: $SYNC_URL"
fi

# 下载 xboard-node
echo ""
echo -e "  ${ICON_ARROW} 下载 xboard-node ($XBOARD_NODE_VERSION)"
XBOARD_URL="https://github.com/ipevel/Xboard-Node/releases/download/${XBOARD_NODE_VERSION}/xboard-node-linux-${ARCH_SUFFIX}"
if wget -q --show-progress -O /usr/local/bin/xboard-node "$XBOARD_URL" 2>&1; then
    chmod +x /usr/local/bin/xboard-node
    echo -e "  ${ICON_OK} xboard-node 更新完成"
else
    echo -e "  ${ICON_ERR} xboard-node 下载失败"
    echo -e "  ${ICON_INFO} URL: $XBOARD_URL"
fi

# 下载最新的管理脚本
echo ""
echo -e "  ${ICON_ARROW} 下载 xnode 管理脚本"
if wget -q -O /tmp/xnode.tmp "https://raw.githubusercontent.com/ipevel/xnodeauto/main/xnode.sh?t=$(date +%s)"; then
    chmod +x /tmp/xnode.tmp
    mv -f /tmp/xnode.tmp /usr/local/bin/xnode
    echo -e "  ${ICON_OK} xnode 更新完成"
else
    rm -f /tmp/xnode.tmp
    echo -e "  ${ICON_ERR} xnode 下载失败"
fi

# 下载 systemd 服务文件
echo ""
echo -e "  ${ICON_ARROW} 更新 systemd 服务文件"
for file in xboard-node@.service sync-nodes.service sync-nodes.timer update-xboard-node.service update-xboard-node.timer; do
    wget -q -O "/etc/systemd/system/$file" "https://raw.githubusercontent.com/ipevel/xnodeauto/main/systemd/$file" 2>/dev/null || true
done
systemctl daemon-reload
echo -e "  ${ICON_OK} systemd 服务文件更新完成"

# 下载 update-xboard-node.sh
echo ""
echo -e "  ${ICON_ARROW} 下载 update-xboard-node.sh"
if wget -q -O /tmp/update-xboard-node.tmp "https://raw.githubusercontent.com/ipevel/xnodeauto/main/update-xboard-node.sh?t=$(date +%s)"; then
    chmod +x /tmp/update-xboard-node.tmp
    mv -f /tmp/update-xboard-node.tmp /usr/local/bin/update-xboard-node.sh
    echo -e "  ${ICON_OK} update-xboard-node.sh 更新完成"
else
    rm -f /tmp/update-xboard-node.tmp
    echo -e "  ${ICON_ERR} update-xboard-node.sh 下载失败"
fi

# ========== 6. 恢复配置并启动服务 ==========
echo ""
echo -e "${cyan}[6/6]${plain} 恢复配置并启动服务..."

# 恢复配置文件（如果备份存在）
if [[ -d "$BACKUP_DIR" ]]; then
    # 不覆盖已存在的配置，只恢复节点配置和别名
    for file in "$BACKUP_DIR"/*.yml "$BACKUP_DIR"/*.yaml "$BACKUP_DIR"/*.hash; do
        if [[ -f "$file" ]]; then
            filename=$(basename "$file")
            # sync.yml 已存在，不覆盖
            if [[ "$filename" != "sync.yml" ]]; then
                cp -f "$file" "/etc/xboard-node/" 2>/dev/null || true
            fi
        fi
    done
    echo -e "  ${ICON_OK} 配置已恢复"
fi

# 启动定时服务
echo ""
echo -e "  ${ICON_ARROW} 启动定时服务..."
systemctl enable --now sync-nodes.timer > /dev/null 2>&1 || true
systemctl enable --now update-xboard-node.timer > /dev/null 2>&1 || true
echo -e "  ${ICON_OK} 定时服务已启动"

# 执行同步（恢复节点服务）
echo ""
echo -e "  ${ICON_ARROW} 执行节点同步..."
/usr/local/bin/sync-nodes

# ========== 完成 ==========
echo ""
echo -e "${green}╔══════════════════════════════════════════════════════════════╗${plain}"
echo -e "${green}║${plain}                                                              ${green}║${plain}"
echo -e "${green}║${plain}           ${ICON_ROCKET} 升级完成！                                       ${green}║${plain}"
echo -e "${green}║${plain}                                                              ${green}║${plain}"
echo -e "${green}╚══════════════════════════════════════════════════════════════╝${plain}"
echo ""

echo -e "${ICON_INFO} 版本信息:"
echo -e "  - sync-nodes:    $(/usr/local/bin/sync-nodes -v 2>&1 | head -1 || echo "未知")"
echo -e "  - xboard-node:   $(/usr/local/bin/xboard-node -v 2>&1 | head -1 || echo "未知")"
echo ""
echo -e "${ICON_INFO} 备份位置: ${cyan}$BACKUP_DIR${plain}"
echo -e "${ICON_INFO} 管理命令: ${cyan}xnode${plain}"
echo ""
