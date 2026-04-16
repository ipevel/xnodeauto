#!/bin/bash

# ============================================================
# Xboard Node Auto-Sync 一键安装脚本
# ============================================================

REPO_RAW="https://raw.githubusercontent.com/ipevel/xnodeauto/main"
REPO_API="https://api.github.com/repos/ipevel/xnodeauto/releases/latest"

# 显示步骤标题
show_step() {
    local step=$1
    local total=$2
    local title="$3"
    echo ""
    echo "[$step/$total] $title"
    echo ""
}

# 显示成功消息
show_success() {
    echo "  [OK] $1"
}

# 显示错误消息
show_error() {
    echo "  [ERROR] $1"
}

# 显示警告消息
show_warn() {
    echo "  [WARN] $1"
}

# 显示信息消息
show_info() {
    echo "  [INFO] $1"
}

# 检查 root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        show_error "必须使用root用户运行此脚本！"
        echo ""
        echo "  使用命令: sudo bash install.sh"
        echo ""
        exit 1
    fi
}

# 解析参数
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
        --admin-password) ADMIN_PASSWORD="$2";  shift 2 ;;
        --panel-token)    PANEL_TOKEN="$2";    shift 2 ;;
        *)
            show_error "未知参数: $1"
            exit 1
            ;;
    esac
done

# 开始安装
echo "Xboard Node Auto-Sync 安装脚本"
echo "版本: v1.2.6"
echo "仓库: https://github.com/ipevel/xnodeauto"
echo ""

check_root

# ---------- 1. 系统依赖 ----------
show_step 1 9 "安装系统依赖"

show_info "检测系统类型..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    show_success "系统: $NAME $VERSION"
fi

show_info "跳过软件包更新（如需更新请手动执行 apt update）"

show_info "安装必要工具..."
if apt install -y wget curl > /dev/null 2>&1; then
    show_success "工具安装完成"
else
    show_error "工具安装失败"
    exit 1
fi

# 架构检测
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *)
        show_error "不支持的架构: $ARCH"
        exit 1
        ;;
esac
show_success "检测到架构: $ARCH_SUFFIX"

# ---------- 2. 下载 xboard-node ----------
show_step 2 9 "下载 xboard-node"

show_info "获取最新版本..."
XBOARD_NODE_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/Xboard-Node/releases/latest" \
  | grep '"tag_name"' | head -1 | cut -d'"' -f4)

if [ -z "$XBOARD_NODE_VERSION" ]; then
    show_warn "无法获取最新版本，使用 v1.0.2"
    XBOARD_NODE_VERSION="v1.0.2"
fi

show_success "版本: $XBOARD_NODE_VERSION"

DOWNLOAD_URL="https://github.com/ipevel/Xboard-Node/releases/download/${XBOARD_NODE_VERSION}/xboard-node-linux-${ARCH_SUFFIX}"

if [ -f /usr/local/bin/xboard-node ]; then
    show_warn "xboard-node 已存在，跳过下载"
else
    show_info "下载中..."
    
    if wget -q -O /usr/local/bin/xboard-node "$DOWNLOAD_URL" 2>&1; then
        if [ -s /usr/local/bin/xboard-node ]; then
            chmod +x /usr/local/bin/xboard-node
            show_success "下载完成"
        else
            show_error "下载失败：文件为空"
            exit 1
        fi
    else
        show_error "下载失败"
        exit 1
    fi
fi

# ---------- 3. 下载 sync-nodes ----------
show_step 3 9 "下载 sync-nodes"

show_info "获取最新版本..."

# 尝试获取最新正式版本
SYNC_VERSION=$(curl -sL "$REPO_API" | grep '"tag_name"' | head -1 | cut -d'"' -f4)

# 如果没有正式版本，获取最新的 beta 版本
if [ -z "$SYNC_VERSION" ]; then
    show_info "未找到正式版本，查找 beta 版本..."
    SYNC_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/xnodeauto/releases" | \
        grep '"tag_name"' | head -1 | cut -d'"' -f4)
fi

if [ -z "$SYNC_VERSION" ]; then
    show_warn "无法获取版本，使用 v1.2.1-beta"
    SYNC_VERSION="v1.2.1-beta"
fi

show_success "版本: $SYNC_VERSION"

SYNC_URL="https://github.com/ipevel/xnodeauto/releases/download/${SYNC_VERSION}/sync-nodes-linux-${ARCH_SUFFIX}"

show_info "下载中..."

if wget -q -O /usr/local/bin/sync-nodes "$SYNC_URL" 2>&1; then
    if [ -s /usr/local/bin/sync-nodes ]; then
        chmod +x /usr/local/bin/sync-nodes
        show_success "下载完成"
    else
        show_error "下载失败：文件为空"
        exit 1
    fi
else
    show_error "下载失败"
    show_info "请检查网络连接或手动下载："
    echo "  $SYNC_URL"
    exit 1
fi

# ---------- 4. 创建配置目录 ----------
show_step 4 9 "创建配置目录"

mkdir -p /etc/xboard-node
show_success "配置目录已创建: /etc/xboard-node"

# ---------- 5. 下载 systemd 文件 ----------
show_step 5 9 "安装 systemd 服务"

show_info "下载服务文件..."
files=(
    "xboard-node@.service"
    "sync-nodes.service"
    "sync-nodes.timer"
    "update-xboard-node.service"
    "update-xboard-node.timer"
)

for file in "${files[@]}"; do
    if wget -q -O "/etc/systemd/system/$file" "${REPO_RAW}/systemd/$file"; then
        show_success "下载 $file"
    else
        show_error "下载 $file 失败"
        exit 1
    fi
done

show_success "服务文件安装完成"

# ---------- 6. 安装自动更新脚本 ----------
show_step 6 9 "安装自动更新脚本"

if wget -q -O /usr/local/bin/update-xboard-node.sh "${REPO_RAW}/update-xboard-node.sh"; then
    chmod +x /usr/local/bin/update-xboard-node.sh
    show_success "自动更新脚本安装完成"
else
    show_error "下载失败"
    exit 1
fi

# ---------- 7. 安装管理脚本 ----------
show_step 7 9 "安装管理脚本"

if wget -q -O /usr/local/bin/xnode "${REPO_RAW}/xnode.sh"; then
    chmod +x /usr/local/bin/xnode
    show_success "管理脚本安装完成"
else
    show_error "下载失败"
    exit 1
fi

# ---------- 8. 重载 systemd ----------
show_step 8 9 "重载 systemd"

systemctl daemon-reload
show_success "systemd 已重载"

# ---------- 9. 配置引导 ----------
show_step 9 9 "配置设置"

# 如果没有通过参数传入配置，则引导用户填写
if [ -z "$XBOARD_URL" ] || [ -z "$ADMIN_PATH" ] || [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ] || [ -z "$PANEL_TOKEN" ]; then
    echo "请填写以下配置信息"
    echo ""
    
    # 面板地址
    echo "面板地址是你的 Xboard 网站地址"
    echo "示例: https://panel.example.com"
    read -rp "请输入面板地址: " XBOARD_URL
    while [ -z "$XBOARD_URL" ]; do
        show_error "面板地址不能为空"
        read -rp "请输入面板地址: " XBOARD_URL
    done
    
    # 后台路径
    echo ""
    echo "后台路径是登录后台 URL 中的一段"
    echo "示例: 后台是 https://panel.example.com/abc12345#/"
    echo "路径就是 abc12345"
    read -rp "请输入后台路径: " ADMIN_PATH
    while [ -z "$ADMIN_PATH" ]; do
        show_error "后台路径不能为空"
        read -rp "请输入后台路径: " ADMIN_PATH
    done
    
    # 管理员邮箱
    echo ""
    echo "管理员邮箱是你登录后台使用的邮箱"
    echo "示例: admin@example.com"
    read -rp "请输入管理员邮箱: " ADMIN_EMAIL
    while [ -z "$ADMIN_EMAIL" ]; do
        show_error "管理员邮箱不能为空"
        read -rp "请输入管理员邮箱: " ADMIN_EMAIL
    done
    
    # 管理员密码
    echo ""
    echo "管理员密码是你登录后台使用的密码"
    read -rsp "请输入管理员密码: " ADMIN_PASSWORD
    echo ""
    while [ -z "$ADMIN_PASSWORD" ]; do
        show_error "管理员密码不能为空"
        read -rsp "请输入管理员密码: " ADMIN_PASSWORD
        echo ""
    done
    
    # 节点通信密钥
    echo ""
    echo "节点通信密钥在 后台 -> 系统设置 -> 节点通信密钥"
    read -rsp "请输入节点通信密钥: " PANEL_TOKEN
    echo ""
    while [ -z "$PANEL_TOKEN" ]; do
        show_error "节点通信密钥不能为空"
        read -rsp "请输入节点通信密钥: " PANEL_TOKEN
        echo ""
    done
fi

# 同步方式选择
echo ""
echo "请选择同步方式"
echo ""
echo "  [1] 自动同步（直连节点）"
echo "      适合节点域名直接解析到本机IP的场景"
echo "      自动匹配所有属于本机的节点"
echo "      检测到>=2个节点时需要手动配置"
echo ""
echo "  [2] 手动添加（中转节点） [推荐]"
echo "      适合中转机/CDN场景"
echo "      需要手动指定节点ID"
echo "      一台服务器可运行多个节点"
echo ""
read -rp "请选择 [1-2，默认2]: " SYNC_MODE

case "$SYNC_MODE" in
    1)
        SYNC_MODE="auto"
        echo ""
        show_success "已选择：自动同步（直连节点）"
        ;;
    *)
        SYNC_MODE="manual"
        echo ""
        show_success "已选择：手动添加（中转节点）"
        ;;
esac

# 写入配置
cat > /etc/xboard-node/sync.yml << EOF
xboard_url: "${XBOARD_URL}"
admin_path: "${ADMIN_PATH}"
admin_email: "${ADMIN_EMAIL}"
admin_password: "${ADMIN_PASSWORD}"
panel_token: "${PANEL_TOKEN}"
EOF

chmod 400 /etc/xboard-node/sync.yml
show_success "配置已保存到 /etc/xboard-node/sync.yml"

# 如果选择手动添加，让用户输入节点ID
if [ "$SYNC_MODE" = "manual" ]; then
    echo ""
    echo "手动添加节点"
    echo ""
    echo "请输入节点ID，多个ID用逗号分隔（例如: 1,2,3）"
    echo "如果暂时不添加，请直接按回车跳过"
    echo ""
    read -rp "请输入节点ID: " NODE_IDS_INPUT
    
    if [ -n "$NODE_IDS_INPUT" ]; then
        # 解析节点ID（支持逗号分隔）
        IFS=',' read -ra NODE_IDS <<< "$NODE_IDS_INPUT"
        
        if [ ${#NODE_IDS[@]} -gt 0 ]; then
            echo ""
            echo "添加节点ID: ${NODE_IDS[*]}"
            echo ""
            
            # 写入配置文件
            echo "" >> /etc/xboard-node/sync.yml
            echo "# 手动指定的节点ID" >> /etc/xboard-node/sync.yml
            echo "manual_node_ids:" >> /etc/xboard-node/sync.yml
            for id in "${NODE_IDS[@]}"; do
                # 去除空格
                id=$(echo "$id" | tr -d ' ')
                echo "  - $id" >> /etc/xboard-node/sync.yml
            done
            
            show_success "已添加 ${#NODE_IDS[@]} 个节点到配置"
        fi
    else
        # 没有输入节点ID，创建空的手动配置
        echo "" >> /etc/xboard-node/sync.yml
        echo "# 手动指定的节点ID（使用 xnode add-node 命令添加）" >> /etc/xboard-node/sync.yml
        echo "manual_node_ids: []" >> /etc/xboard-node/sync.yml
        echo ""
        show_info "稍后可以使用 xnode add-node <节点ID> 添加节点"
    fi
fi

# ---------- 完成提示 ----------
echo ""
echo "====================================="
echo "安装完成！正在执行首次同步..."
echo "====================================="
echo ""

# 执行首次同步
echo "首次同步..."
/usr/local/bin/sync-nodes

# 启动定时服务
echo ""
echo "启动定时服务..."
systemctl enable --now sync-nodes.timer > /dev/null 2>&1
systemctl enable --now update-xboard-node.timer > /dev/null 2>&1
show_success "定时服务已启动"

# 最终提示
echo ""
echo "====================================="
echo "全部完成！"
echo "====================================="
echo ""
echo "常用命令："
echo "  xnode          打开管理菜单"
echo "  xnode status   查看节点状态"
echo "  xnode sync     手动同步节点"
echo "  xnode log      查看同步日志"
echo ""

if [ "$SYNC_MODE" = "manual" ]; then
    echo "你选择了手动添加模式，请使用以下命令添加节点："
    echo "  xnode add-node <节点ID>"
    echo ""
fi