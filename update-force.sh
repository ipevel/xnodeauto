#!/bin/bash

# ============================================================
# Xboard Node 强制更新脚本（保留配置）
# ============================================================

REPO_RAW="https://raw.githubusercontent.com/ipevel/xnodeauto/main"
REPO_API="https://api.github.com/repos/ipevel/xnodeauto/releases/latest"

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
ICON_GEAR="⚙️"

echo ""
echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
echo -e "${cyan}│${plain} ${ICON_GEAR} Xboard Node 强制更新（保留配置）"
echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
echo ""

# 检测是否已安装
if [ ! -d "/etc/xboard-node" ] || [ ! -f "/etc/xboard-node/sync.yml" ]; then
    echo -e "  ${ICON_ERR} ${red}未检测到安装，请先运行安装脚本${plain}"
    echo ""
    exit 1
fi

# 备份配置
BACKUP_DIR="/tmp/xboard-node-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo -e "  ${ICON_INFO} 备份配置文件..."
for file in /etc/xboard-node/*.yml /etc/xboard-node/*.yaml; do
    if [ -f "$file" ]; then
        cp "$file" "$BACKUP_DIR/" 2>/dev/null
        echo -e "    ${ICON_OK} $(basename $file)"
    fi
done

if [ -f "/etc/xboard-node/node_alias.yml" ]; then
    cp /etc/xboard-node/node_alias.yml "$BACKUP_DIR/" 2>/dev/null
    echo -e "    ${ICON_OK} node_alias.yml"
fi

echo -e "  ${ICON_OK} 配置已备份到: ${cyan}$BACKUP_DIR${plain}"
echo ""

# 停止所有节点服务
echo -e "  ${ICON_INFO} 停止节点服务..."
RUNNING_NODES=$(systemctl list-units --type=service --state=running | grep "xboard-node@" | awk '{print $1}' | cut -d'@' -f2 | cut -d'.' -f1)
if [ -n "$RUNNING_NODES" ]; then
    for node in $RUNNING_NODES; do
        systemctl stop "xboard-node@$node" 2>/dev/null
        echo -e "    ${ICON_OK} 停止节点: $node"
    done
else
    echo -e "    ${ICON_INFO} 没有运行中的节点"
fi
echo ""

# 下载最新版本
echo -e "  ${ICON_INFO} 检测最新版本..."
LATEST_VERSION=$(curl -sL "$REPO_API" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
if [ -z "$LATEST_VERSION" ]; then
    LATEST_VERSION="v1.2.3"
fi
echo -e "    ${ICON_OK} 版本: ${cyan}$LATEST_VERSION${plain}"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *)       echo -e "  ${ICON_ERR} ${red}不支持的架构: $ARCH${plain}"; exit 1 ;;
esac

SYNC_URL="https://github.com/ipevel/xnodeauto/releases/download/${LATEST_VERSION}/sync-nodes-linux-${ARCH_SUFFIX}"

echo -e "  ${ICON_INFO} 下载组件..."
if wget -q --show-progress -O /usr/local/bin/sync-nodes "$SYNC_URL"; then
    chmod +x /usr/local/bin/sync-nodes
    echo -e "    ${ICON_OK} sync-nodes"
else
    echo -e "    ${ICON_ERR} sync-nodes 下载失败"
    exit 1
fi

# 下载其他组件
if wget -q -O /usr/local/bin/update-xboard-node.sh "${REPO_RAW}/update-xboard-node.sh"; then
    chmod +x /usr/local/bin/update-xboard-node.sh
    echo -e "    ${ICON_OK} update-xboard-node.sh"
else
    echo -e "    ${ICON_ERR} update-xboard-node.sh 下载失败"
fi

if wget -q -O /usr/local/bin/xnode "${REPO_RAW}/xnode.sh?t=$(date +%s)"; then
    chmod +x /usr/local/bin/xnode
    echo -e "    ${ICON_OK} xnode"
else
    echo -e "    ${ICON_ERR} xnode 下载失败"
fi

# 下载 systemd 文件
for file in xboard-node@.service sync-nodes.service sync-nodes.timer update-xboard-node.service update-xboard-node.timer; do
    if wget -q -O "/etc/systemd/system/$file" "${REPO_RAW}/systemd/$file"; then
        echo -e "    ${ICON_OK} $file"
    fi
done

systemctl daemon-reload
echo ""

# 恢复配置
echo -e "  ${ICON_INFO} 恢复配置文件..."
for file in "$BACKUP_DIR"/*.yml "$BACKUP_DIR"/*.yaml; do
    if [ -f "$file" ]; then
        cp "$file" /etc/xboard-node/ 2>/dev/null
        echo -e "    ${ICON_OK} $(basename $file)"
    fi
done

if [ -f "$BACKUP_DIR/node_alias.yml" ]; then
    cp "$BACKUP_DIR/node_alias.yml" /etc/xboard-node/ 2>/dev/null
    echo -e "    ${ICON_OK} node_alias.yml"
fi

rm -rf "$BACKUP_DIR"
echo -e "  ${ICON_OK} 配置恢复完成"
echo ""

# 重启节点服务
if [ -n "$RUNNING_NODES" ]; then
    echo -e "  ${ICON_INFO} 重启节点服务..."
    for node in $RUNNING_NODES; do
        systemctl start "xboard-node@$node" 2>/dev/null
        echo -e "    ${ICON_OK} 启动节点: $node"
    done
    echo ""
fi

echo -e "${green}╔══════════════════════════════════════════════════════════════╗${plain}"
echo -e "${green}║${plain}                                                              ${green}║${plain}"
echo -e "${green}║${plain}           ${ICON_OK} 更新完成！配置已保留                    ${green}║${plain}"
echo -e "${green}║${plain}                                                              ${green}║${plain}"
echo -e "${green}╚══════════════════════════════════════════════════════════════╝${plain}"
echo ""

