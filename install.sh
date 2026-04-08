#!/bin/bash

# ============================================================
# Xboard Node Auto-Sync 一键安装脚本
# ============================================================

REPO_RAW="https://raw.githubusercontent.com/ipevel/xnodeauto/main"
REPO_API="https://api.github.com/repos/ipevel/xnodeauto/releases/latest"

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 检查 root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

echo -e "${green}"
echo "============================================"
echo "  Xboard Node Auto-Sync 一键安装脚本"
echo "============================================"
echo -e "${plain}"

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
            echo -e "${red}未知参数: $1${plain}"
            exit 1
            ;;
    esac
done

# ---------- 1. 系统依赖 ----------
echo -e "${green}[1/9]${plain} 安装系统依赖..."
apt update -y
apt install -y wget curl

# ---------- 架构检测 ----------
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *)
        echo -e "${red}不支持的架构: $ARCH${plain}"
        exit 1
        ;;
esac
echo -e "  检测到架构: ${green}${ARCH_SUFFIX}${plain}"

# ---------- 2. 下载 xboard-node 二进制 ----------
echo -e "${green}[2/9]${plain} 下载 xboard-node..."

XBOARD_NODE_VERSION=$(curl -sL "https://api.github.com/repos/cedar2025/Xboard-Node/releases/latest" \
  | grep '"tag_name"' | head -1 | cut -d'"' -f4)

if [ -z "$XBOARD_NODE_VERSION" ]; then
    echo -e "${yellow}  无法获取最新版本，使用 v1.0.2${plain}"
    XBOARD_NODE_VERSION="v1.0.2"
fi

echo -e "  版本: ${green}${XBOARD_NODE_VERSION}${plain}"

DOWNLOAD_URL="https://github.com/cedar2025/Xboard-Node/releases/download/${XBOARD_NODE_VERSION}/xboard-node-linux-${ARCH_SUFFIX}"

if [ -f /usr/local/bin/xboard-node ]; then
    echo -e "${yellow}  xboard-node 已存在，跳过下载${plain}"
else
    wget -q -O /usr/local/bin/xboard-node "$DOWNLOAD_URL"
    chmod +x /usr/local/bin/xboard-node
    echo -e "  ${green}下载完成${plain}"
fi

# ---------- 3. 下载 sync-nodes 二进制 ----------
echo -e "${green}[3/9]${plain} 下载 sync-nodes..."

SYNC_VERSION=$(curl -sL "$REPO_API" | grep '"tag_name"' | head -1 | cut -d'"' -f4)

if [ -z "$SYNC_VERSION" ]; then
    echo -e "${yellow}  无法获取版本，使用 v1.0.0${plain}"
    SYNC_VERSION="v1.0.0"
fi

echo -e "  版本: ${green}${SYNC_VERSION}${plain}"

SYNC_URL="https://github.com/ipevel/xnodeauto/releases/download/${SYNC_VERSION}/sync-nodes-linux-${ARCH_SUFFIX}"

wget -q -O /usr/local/bin/sync-nodes "$SYNC_URL"

# 检查下载是否成功
if [ ! -s /usr/local/bin/sync-nodes ]; then
    echo -e "${red}  下载失败！请检查网络${plain}"
    exit 1
fi

chmod +x /usr/local/bin/sync-nodes
echo -e "  ${green}下载完成${plain}"

# ---------- 4. 创建配置目录 ----------
echo -e "${green}[4/9]${plain} 创建配置目录..."
mkdir -p /etc/xboard-node

# ---------- 5. 下载 systemd 文件 ----------
echo -e "${green}[5/9]${plain} 安装 systemd 服务..."
wget -q -O /etc/systemd/system/xboard-node@.service  "${REPO_RAW}/systemd/xboard-node@.service"
wget -q -O /etc/systemd/system/sync-nodes.service     "${REPO_RAW}/systemd/sync-nodes.service"
wget -q -O /etc/systemd/system/sync-nodes.timer       "${REPO_RAW}/systemd/sync-nodes.timer"
wget -q -O /etc/systemd/system/update-xboard-node.service "${REPO_RAW}/systemd/update-xboard-node.service"
wget -q -O /etc/systemd/system/update-xboard-node.timer    "${REPO_RAW}/systemd/update-xboard-node.timer"
echo -e "  ${green}完成${plain}"

# ---------- 6. 安装自动更新脚本 ----------
echo -e "${green}[6/9]${plain} 安装自动更新脚本..."
wget -q -O /usr/local/bin/update-xboard-node.sh "${REPO_RAW}/update-xboard-node.sh"
chmod +x /usr/local/bin/update-xboard-node.sh
echo -e "  ${green}完成${plain}"

# ---------- 7. 安装管理脚本 ----------
echo -e "${green}[7/9]${plain} 安装管理脚本..."
wget -q -O /usr/bin/xnode "${REPO_RAW}/xnode.sh"
chmod +x /usr/bin/xnode
echo -e "  ${green}完成${plain}"

# ---------- 8. 重载 systemd ----------
echo -e "${green}[8/9]${plain} 重载 systemd..."
systemctl daemon-reload

# ---------- 9. 配置引导 ----------
echo ""
echo -e "${green}[9/9]${plain} 配置设置"
echo ""

# 如果没有通过参数传入配置，则引导用户填写
if [ -z "$XBOARD_URL" ] || [ -z "$ADMIN_PATH" ] || [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ] || [ -z "$PANEL_TOKEN" ]; then
    echo -e "${yellow}请填写以下配置信息：${plain}"
    echo ""
    
    # 面板地址
    echo -e "${green}提示：${plain}面板地址是你的 Xboard 网站地址"
    read -rp "请输入面板地址 (例如 https://panel.example.com): " XBOARD_URL
    while [ -z "$XBOARD_URL" ]; do
        echo -e "${red}面板地址不能为空${plain}"
        read -rp "请输入面板地址: " XBOARD_URL
    done
    
    # 后台路径
    echo ""
    echo -e "${green}提示：${plain}后台路径是登录后台 URL 中的一段"
    echo -e "例如后台是 ${yellow}https://panel.example.com/abc12345#/${plain}"
    echo -e "那后台路径就是 ${yellow}abc12345${plain}"
    read -rp "请输入后台路径: " ADMIN_PATH
    while [ -z "$ADMIN_PATH" ]; do
        echo -e "${red}后台路径不能为空${plain}"
        read -rp "请输入后台路径: " ADMIN_PATH
    done
    
    # 管理员邮箱
    echo ""
    echo -e "${green}提示：${plain}管理员邮箱是你登录后台使用的邮箱"
    read -rp "请输入管理员邮箱: " ADMIN_EMAIL
    while [ -z "$ADMIN_EMAIL" ]; do
        echo -e "${red}管理员邮箱不能为空${plain}"
        read -rp "请输入管理员邮箱: " ADMIN_EMAIL
    done
    
    # 管理员密码
    echo ""
    echo -e "${green}提示：${plain}管理员密码是你登录后台使用的密码"
    read -rp "请输入管理员密码: " ADMIN_PASSWORD
    while [ -z "$ADMIN_PASSWORD" ]; do
        echo -e "${red}管理员密码不能为空${plain}"
        read -rp "请输入管理员密码: " ADMIN_PASSWORD
    done
    
    # 节点通信密钥
    echo ""
    echo -e "${green}提示：${plain}节点通信密钥在 后台 → 系统设置 → 节点通信密钥"
    read -rp "请输入节点通信密钥: " PANEL_TOKEN
    while [ -z "$PANEL_TOKEN" ]; do
        echo -e "${red}节点通信密钥不能为空${plain}"
        read -rp "请输入节点通信密钥: " PANEL_TOKEN
    done
fi

# 写入配置
cat > /etc/xboard-node/sync.yml << EOF
xboard_url: "${XBOARD_URL}"
admin_path: "${ADMIN_PATH}"
admin_email: "${ADMIN_EMAIL}"
admin_password: "${ADMIN_PASSWORD}"
panel_token: "${PANEL_TOKEN}"
EOF
chmod 600 /etc/xboard-node/sync.yml

echo ""
echo -e "${green}配置已保存到 /etc/xboard-node/sync.yml${plain}"

# ---------- 完成提示 ----------
echo ""
echo -e "${green}============================================"
echo "  安装完成！"
echo "============================================${plain}"
echo ""
echo -e "现在执行首次同步..."
echo ""

# 执行首次同步
/usr/local/bin/sync-nodes

# 启动定时服务
echo ""
echo -e "${yellow}正在启动定时服务...${plain}"
systemctl enable --now sync-nodes.timer
systemctl enable --now update-xboard-node.timer

echo ""
echo -e "${green}============================================${plain}"
echo -e "${green}全部完成！${plain}"
echo -e "${green}============================================${plain}"
echo ""
echo -e "管理命令: ${yellow}xnode${plain}"
echo ""
echo -e "常用命令:"
echo -e "  ${yellow}xnode${plain}          - 打开管理菜单"
echo -e "  ${yellow}xnode status${plain}   - 查看节点状态"
echo -e "  ${yellow}xnode sync${plain}     - 手动同步节点"
echo -e "  ${yellow}xnode log${plain}      - 查看同步日志"
echo ""
echo -e "文档: https://github.com/ipevel/xnodeauto"
echo ""
