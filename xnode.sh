#!/bin/bash

# ============================================================
# Xboard Node Auto-Sync 管理脚本
# ============================================================

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
plain='\033[0m'

# 图标
ICON_OK="✅"
ICON_ERR="❌"
ICON_WARN="⚠️"
ICON_INFO="ℹ️"
ICON_ROCKET="🚀"
ICON_GEAR="⚙️"
ICON_CHECK="✔"
ICON_ARROW="→"
ICON_NODE="🔷"

cur_dir=$(pwd)
alias_file="/etc/xboard-node/node_alias.yml"

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}${ICON_ERR} 错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat //proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
else
    echo -e "${red}${ICON_ERR} 未检测到系统版本！${plain}\n"
fi

# ========== 别名管理 ==========

# 加载节点别名
load_aliases() {
    declare -gA node_aliases
    if [[ -f "$alias_file" ]]; then
        while IFS=: read -r id alias; do
            [[ -n "$id" && -n "$alias" ]] && node_aliases["$id"]="$alias"
        done < <(grep -v '^#' "$alias_file" 2>/dev/null | grep ':')
    fi
}

# 保存节点别名
save_aliases() {
    mkdir -p /etc/xboard-node
    echo "# 节点别名配置" > "$alias_file"
    echo "# 格式: 节点ID:别名" >> "$alias_file"
    for id in "${!node_aliases[@]}"; do
        echo "$id:${node_aliases[$id]}" >> "$alias_file"
    done
}

# 获取节点别名
get_alias() {
    local node_id=$1
    load_aliases
    if [[ -n "${node_aliases[$node_id]}" ]]; then
        echo "${node_aliases[$node_id]}"
    else
        # 尝试从面板获取节点名称
        local name=$(get_node_name_from_panel "$node_id" 2>/dev/null)
        if [[ -n "$name" ]]; then
            echo "$name"
        else
            echo "节点$node_id"
        fi
    fi
}

# 从面板获取节点名称（需要改进）
get_node_name_from_panel() {
    local node_id=$1
    # TODO: 通过 API 获取节点名称
    echo ""
}

# 设置节点别名
set_alias() {
    local node_id=$1
    local alias=$2
    
    load_aliases
    node_aliases["$node_id"]="$alias"
    save_aliases
    echo -e "${green}${ICON_OK} 已设置节点 $node_id 别名为: $alias${plain}"
}

# 删除节点别名
remove_alias() {
    local node_id=$1
    
    load_aliases
    if [[ -n "${node_aliases[$node_id]}" ]]; then
        unset "node_aliases[$node_id]"
        save_aliases
        echo -e "${green}${ICON_OK} 已删除节点 $node_id 的别名${plain}"
    fi
}

# ========== 进度条显示 ==========

show_progress() {
    local current=$1
    local total=$2
    local desc="$3"
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${cyan}  ${ICON_GEAR}${plain} ${desc} [${green}"
    for ((i=0; i<filled; i++)); do printf "█"; done
    printf "${plain}"
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "] %3d%%" "$percent"
    
    if [ $current -eq $total ]; then
        echo ""
    fi
}

# ========== 显示函数 ==========

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
    fi
}

update() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 更新 xboard-node"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    /usr/local/bin/update-xboard-node.sh
    echo ""
    echo -e "${green}${ICON_OK} 更新完成！${plain}"
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_script() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 更新管理脚本"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    # 备份当前版本
    if [ -f /usr/local/bin/xnode ]; then
        cp /usr/local/bin/xnode /usr/local/bin/xnode.bak
        echo -e "  ${ICON_INFO} 已备份当前版本"
    fi
    
    echo -e "  ${ICON_ARROW} 下载新版本..."
    
    # 下载新版本
    if wget -q -O /usr/local/bin/xnode https://raw.githubusercontent.com/ipevel/xnodeauto/main/xnode.sh; then
        if [ -s /usr/local/bin/xnode ]; then
            chmod +x /usr/local/bin/xnode
            echo -e "  ${ICON_OK} ${green}管理脚本更新完成！${plain}"
            echo -e "  ${ICON_INFO} 重新运行以应用更新"
            rm -f /usr/local/bin/xnode.bak
        else
            echo -e "  ${ICON_ERR} ${red}下载文件为空，恢复旧版本${plain}"
            [ -f /usr/local/bin/xnode.bak ] && mv /usr/local/bin/xnode.bak /usr/local/bin/xnode
        fi
    else
        echo -e "  ${ICON_ERR} ${red}下载失败，恢复旧版本${plain}"
        [ -f /usr/local/bin/xnode.bak ] && mv /usr/local/bin/xnode.bak /usr/local/bin/xnode
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_sync_nodes() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 更新 sync-nodes"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    # 检测架构
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_SUFFIX="amd64" ;;
        aarch64) ARCH_SUFFIX="arm64" ;;
        *)
            echo -e "${red}${ICON_ERR} 不支持的架构: $ARCH${plain}"
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            return
            ;;
    esac
    
    BINARY_NAME="sync-nodes-linux-${ARCH_SUFFIX}"
    
    # 获取最新版本（优先正式版，其次beta版）
    echo -e "  ${ICON_INFO} 正在获取最新版本..."
    SYNC_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/xnodeauto/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
    
    # 如果没有正式版，获取最新beta版
    if [ -z "$SYNC_VERSION" ]; then
        SYNC_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/xnodeauto/releases" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
    fi
    
    if [ -z "$SYNC_VERSION" ]; then
        echo -e "  ${ICON_WARN} ${yellow}无法获取版本，使用默认版本${plain}"
        SYNC_VERSION="v1.2.1-beta"
    fi
    
    DOWNLOAD_URL="https://github.com/ipevel/xnodeauto/releases/download/${SYNC_VERSION}/${BINARY_NAME}"
    
    echo -e "  ${ICON_INFO} 架构: ${cyan}$ARCH ($ARCH_SUFFIX)${plain}"
    echo -e "  ${ICON_INFO} 版本: ${cyan}$SYNC_VERSION${plain}"
    echo -e "  ${ICON_ARROW} 下载中..."
    
    # 备份当前版本
    if [ -f /usr/local/bin/sync-nodes ]; then
        cp /usr/local/bin/sync-nodes /usr/local/bin/sync-nodes.bak
        echo -e "  ${ICON_INFO} 已备份旧版本"
    fi
    
    # 下载新版本
    if wget -q --show-progress -O /usr/local/bin/sync-nodes "$DOWNLOAD_URL"; then
        if [ -s /usr/local/bin/sync-nodes ]; then
            chmod +x /usr/local/bin/sync-nodes
            echo -e "\n  ${ICON_OK} ${green}sync-nodes 更新完成！${plain}"
            
            # 显示版本
            echo ""
            /usr/local/bin/sync-nodes -v 2>/dev/null
            echo ""
            
            rm -f /usr/local/bin/sync-nodes.bak
            
            # 重启同步服务
            if [[ x"${release}" == x"alpine" ]]; then
                if rc-service sync-nodes status 2>/dev/null | grep -q "started"; then
                    echo -e "  ${ICON_ARROW} 重启同步服务..."
                    rc-service sync-nodes restart
                    echo -e "  ${ICON_OK} 同步服务已重启"
                fi
            else
                if systemctl is-active sync-nodes.service 2>/dev/null | grep -q "active"; then
                    echo -e "  ${ICON_ARROW} 重启同步服务..."
                    systemctl restart sync-nodes.service
                    echo -e "  ${ICON_OK} 同步服务已重启"
                fi
            fi
        else
            echo -e "\n  ${ICON_ERR} ${red}下载文件为空，恢复旧版本${plain}"
            [ -f /usr/local/bin/sync-nodes.bak ] && mv /usr/local/bin/sync-nodes.bak /usr/local/bin/sync-nodes
        fi
    else
        echo -e "\n  ${ICON_ERR} ${red}下载失败，恢复旧版本${plain}"
        [ -f /usr/local/bin/sync-nodes.bak ] && mv /usr/local/bin/sync-nodes.bak /usr/local/bin/sync-nodes
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    if [[ ! -f /etc/xboard-node/sync.yml ]]; then
        echo -e "${red}${ICON_ERR} 配置文件不存在，请先安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 编辑配置文件"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    echo -e "  ${ICON_INFO} 配置文件路径: ${cyan}/etc/xboard-node/sync.yml${plain}"
    echo ""
    vi /etc/xboard-node/sync.yml
    
    echo ""
    echo -e "${yellow}${ICON_WARN} 配置已修改，是否重启同步服务？${plain}"
    confirm "重启同步服务"
    if [[ $? == 0 ]]; then
        if [[ x"${release}" == x"alpine" ]]; then
            rc-service sync-nodes restart
        else
            systemctl restart sync-nodes.service
        fi
        echo -e "${green}${ICON_OK} 同步服务已重启${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall() {
    echo -e "${red}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${red}│${plain} ${ICON_WARN} 卸载警告"
    echo -e "${red}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    echo -e "  ${yellow}这将删除所有节点配置和服务${plain}"
    echo ""
    confirm "确定要卸载 xnodeauto 吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    
    echo ""
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 卸载中..."
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    # 停止并禁用所有 xboard-node 服务
    echo -e "  ${ICON_ARROW} 停止所有 xboard-node 服务..."
    for svc in $(systemctl list-units --all --no-legend --plain "xboard-node@*.service" 2>/dev/null | awk '{print $1}'); do
        systemctl stop "$svc" 2>/dev/null
        systemctl disable "$svc" 2>/dev/null
    done
    echo -e "  ${ICON_OK} 服务已停止"
    
    # 停止定时任务
    echo -e "  ${ICON_ARROW} 停止定时任务..."
    systemctl stop sync-nodes.timer 2>/dev/null
    systemctl disable sync-nodes.timer 2>/dev/null
    systemctl stop update-xboard-node.timer 2>/dev/null
    systemctl disable update-xboard-node.timer 2>/dev/null
    echo -e "  ${ICON_OK} 定时任务已停止"
    
    # 删除配置和程序文件
    echo -e "  ${ICON_ARROW} 删除文件..."
    rm -rf /etc/xboard-node
    rm -f /usr/local/bin/xboard-node
    rm -f /usr/local/bin/sync-nodes
    rm -f /usr/local/bin/update-xboard-node.sh
    rm -f /usr/local/bin/xnode
    rm -f /etc/systemd/system/xboard-node@.service
    rm -f /etc/systemd/system/sync-nodes.service
    rm -f /etc/systemd/system/sync-nodes.timer
    rm -f /etc/systemd/system/update-xboard-node.service
    rm -f /etc/systemd/system/update-xboard-node.timer
    echo -e "  ${ICON_OK} 文件已删除"
    
    # 重载 systemd
    systemctl daemon-reload
    
    echo ""
    echo -e "${green}${ICON_OK} 卸载完成${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# ========== 节点状态 ==========

status() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_NODE} 节点状态"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    # 检查配置文件
    if [[ ! -f /etc/xboard-node/sync.yml ]]; then
        echo -e "  ${ICON_ERR} ${red}未安装，请先运行安装脚本${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    
    # 加载别名
    load_aliases
    
    # 获取所有节点服务
    local nodes=$(systemctl list-units --all --no-legend --plain "xboard-node@*.service" 2>/dev/null | grep "xboard-node@")
    
    if [[ -z "$nodes" ]]; then
        echo -e "  ${ICON_WARN} ${yellow}没有运行任何节点${plain}"
        echo ""
        echo -e "  ${ICON_INFO} 使用 ${cyan}xnode add-node <节点ID>${plain} 添加节点"
    else
        echo -e "  ${purple}节点ID  别名              状态      ${plain}"
        echo -e "  ${cyan}──────  ────────────────  ────────${plain}"
        
        while IFS= read -r line; do
            local unit=$(echo "$line" | awk '{print $1}')
            local status=$(echo "$line" | awk '{print $3}')
            
            # 提取节点ID
            local node_id=$(echo "$unit" | sed 's/xboard-node@\([0-9]*\)\.service/\1/')
            
            # 获取别名
            local alias="${node_aliases[$node_id]:-节点$node_id}"
            
            # 格式化状态
            if [[ "$status" == "active" ]]; then
                status_text="${green}● 运行中${plain}"
            elif [[ "$status" == "inactive" ]]; then
                status_text="${red}○ 已停止${plain}"
            elif [[ "$status" == "failed" ]]; then
                status_text="${red}✕ 失败${plain}"
            else
                status_text="${yellow}○ $status${plain}"
            fi
            
            # 对齐输出
            printf "  %-6s  %-16s  %b\n" "$node_id" "$alias" "$status_text"
        done <<< "$nodes"
    fi
    
    echo ""
    echo -e "${cyan}────────────────────────────────────────────────────────────${plain}"
    echo ""
    
    # 定时任务状态
    echo -e "  ${purple}定时任务状态${plain}"
    echo -e "  ${cyan}────────────────${plain}"
    
    local sync_timer=$(systemctl is-enabled sync-nodes.timer 2>/dev/null)
    local sync_active=$(systemctl is-active sync-nodes.timer 2>/dev/null)
    
    if [[ "$sync_timer" == "enabled" ]]; then
        echo -e "  节点同步: ${green}已启用${plain} ($sync_active)"
    else
        echo -e "  节点同步: ${yellow}未启用${plain}"
    fi
    
    local update_timer=$(systemctl is-enabled update-xboard-node.timer 2>/dev/null)
    local update_active=$(systemctl is-active update-xboard-node.timer 2>/dev/null)
    
    if [[ "$update_timer" == "enabled" ]]; then
        echo -e "  自动更新: ${green}已启用${plain} ($update_active)"
    else
        echo -e "  自动更新: ${yellow}未启用${plain}"
    fi
    
    echo ""
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# ========== 节点操作 ==========

start_all() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 启动所有节点"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    # 读取 sync.yml 获取节点列表
    if [[ -f /etc/xboard-node/sync.yml ]]; then
        # 从配置文件读取 manual_node_ids
        local node_ids=$(grep -A 100 "manual_node_ids:" /etc/xboard-node/sync.yml 2>/dev/null | grep -E "^  - [0-9]+" | awk '{print $2}')
        
        if [[ -z "$node_ids" ]]; then
            # 如果没有 manual_node_ids，尝试从配置文件中查找
            node_ids=$(ls /etc/xboard-node/*.yml 2>/dev/null | grep -v sync.yml | xargs -I {} basename {} .yml)
        fi
        
        if [[ -z "$node_ids" ]]; then
            echo -e "  ${ICON_WARN} ${yellow}没有配置任何节点${plain}"
            echo ""
            echo -e "  ${ICON_INFO} 使用 ${cyan}xnode add-node <节点ID>${plain} 添加节点"
        else
            for id in $node_ids; do
                local alias=$(get_alias "$id")
                echo -e "  ${ICON_ARROW} 启动节点 $id ($alias)..."
                systemctl enable xboard-node@$id.service 2>/dev/null
                systemctl start xboard-node@$id.service 2>/dev/null
                
                if systemctl is-active xboard-node@$id.service > /dev/null 2>&1; then
                    echo -e "  ${ICON_OK} ${green}节点 $id 已启动${plain}"
                else
                    echo -e "  ${ICON_ERR} ${red}节点 $id 启动失败${plain}"
                fi
            done
        fi
    else
        echo -e "  ${ICON_ERR} ${red}配置文件不存在${plain}"
    fi
    
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop_all() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 停止所有节点"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    local nodes=$(systemctl list-units --all --no-legend --plain "xboard-node@*.service" 2>/dev/null | grep "xboard-node@")
    
    if [[ -z "$nodes" ]]; then
        echo -e "  ${ICON_WARN} ${yellow}没有运行任何节点${plain}"
    else
        while IFS= read -r line; do
            local unit=$(echo "$line" | awk '{print $1}')
            local node_id=$(echo "$unit" | sed 's/xboard-node@\([0-9]*\)\.service/\1/')
            local alias=$(get_alias "$node_id")
            
            echo -e "  ${ICON_ARROW} 停止节点 $node_id ($alias)..."
            systemctl stop "$unit" 2>/dev/null
            systemctl disable "$unit" 2>/dev/null
            echo -e "  ${ICON_OK} ${green}节点 $node_id 已停止${plain}"
        done <<< "$nodes"
    fi
    
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_all() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 重启所有节点"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    local nodes=$(systemctl list-units --all --no-legend --plain "xboard-node@*.service" 2>/dev/null | grep "xboard-node@")
    
    if [[ -z "$nodes" ]]; then
        echo -e "  ${ICON_WARN} ${yellow}没有运行任何节点${plain}"
    else
        while IFS= read -r line; do
            local unit=$(echo "$line" | awk '{print $1}')
            local node_id=$(echo "$unit" | sed 's/xboard-node@\([0-9]*\)\.service/\1/')
            local alias=$(get_alias "$node_id")
            
            echo -e "  ${ICON_ARROW} 重启节点 $node_id ($alias)..."
            systemctl restart "$unit" 2>/dev/null
            
            if systemctl is-active "$unit" > /dev/null 2>&1; then
                echo -e "  ${ICON_OK} ${green}节点 $node_id 已重启${plain}"
            else
                echo -e "  ${ICON_ERR} ${red}节点 $node_id 重启失败${plain}"
            fi
        done <<< "$nodes"
    fi
    
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# ========== 同步节点 ==========

sync() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 同步节点"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    if [[ ! -f /usr/local/bin/sync-nodes ]]; then
        echo -e "${red}${ICON_ERR} sync-nodes 未安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    
    /usr/local/bin/sync-nodes
    
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# ========== 节点管理 ==========

list_nodes() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_NODE} 节点列表"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    # 加载别名
    load_aliases
    
    # 读取配置的节点
    if [[ -f /etc/xboard-node/sync.yml ]]; then
        local node_ids=$(grep -A 100 "manual_node_ids:" /etc/xboard-node/sync.yml 2>/dev/null | grep -E "^  - [0-9]+" | awk '{print $2}')
        
        if [[ -z "$node_ids" ]]; then
            echo -e "  ${ICON_INFO} 使用自动同步模式（未配置手动节点）"
            echo ""
            
            # 显示配置文件中的节点
            local config_nodes=$(ls /etc/xboard-node/*.yml 2>/dev/null | grep -v sync.yml)
            if [[ -n "$config_nodes" ]]; then
                echo -e "  ${purple}节点ID  别名              状态      ${plain}"
                echo -e "  ${cyan}──────  ────────────────  ────────${plain}"
                
                for config_file in $config_nodes; do
                    local node_id=$(basename "$config_file" .yml)
                    local alias="${node_aliases[$node_id]:-节点$node_id}"
                    local status=$(systemctl is-active xboard-node@$node_id.service 2>/dev/null || echo "inactive")
                    
                    if [[ "$status" == "active" ]]; then
                        status_text="${green}● 运行中${plain}"
                    else
                        status_text="${red}○ $status${plain}"
                    fi
                    
                    printf "  %-6s  %-16s  %b\n" "$node_id" "$alias" "$status_text"
                done
            fi
        else
            echo -e "  ${purple}节点ID  别名              状态      ${plain}"
            echo -e "  ${cyan}──────  ────────────────  ────────${plain}"
            
            for id in $node_ids; do
                local alias="${node_aliases[$id]:-节点$id}"
                local status=$(systemctl is-active xboard-node@$id.service 2>/dev/null || echo "inactive")
                
                if [[ "$status" == "active" ]]; then
                    status_text="${green}● 运行中${plain}"
                else
                    status_text="${red}○ $status${plain}"
                fi
                
                printf "  %-6s  %-16s  %b\n" "$id" "$alias" "$status_text"
            done
        fi
    else
        echo -e "  ${ICON_ERR} ${red}配置文件不存在${plain}"
    fi
    
    echo ""
    echo -e "  ${ICON_INFO} 设置别名: ${cyan}xnode set-alias <节点ID> <别名>${plain}"
    echo ""
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

add_node() {
    local node_id=$1
    local alias=$2
    
    if [[ -z "$node_id" ]]; then
        echo -e "${red}${ICON_ERR} 用法: xnode add-node <节点ID> [别名]${plain}"
        return 1
    fi
    
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 添加节点 $node_id"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    # 检查是否已在配置中
    if [[ -f /etc/xboard-node/sync.yml ]]; then
        if grep -q "manual_node_ids:" /etc/xboard-node/sync.yml; then
            if grep -E "  - $node_id$" /etc/xboard-node/sync.yml > /dev/null; then
                echo -e "${yellow}${ICON_WARN} 节点 $node_id 已在配置中${plain}"
                
                # 检查节点是否在运行
                local status=$(systemctl is-active xboard-node@$node_id.service 2>/dev/null || echo "inactive")
                if [[ "$status" == "active" ]]; then
                    echo -e "${green}${ICON_OK} 节点 $node_id 正在运行${plain}"
                else
                    echo -e "${yellow}${ICON_WARN} 节点 $node_id 未运行，正在启动...${plain}"
                    systemctl start xboard-node@$node_id.service
                    sleep 2
                    status=$(systemctl is-active xboard-node@$node_id.service 2>/dev/null || echo "inactive")
                    if [[ "$status" == "active" ]]; then
                        echo -e "${green}${ICON_OK} 节点 $node_id 已启动${plain}"
                    else
                        echo -e "${red}${ICON_ERR} 节点 $node_id 启动失败，请检查日志${plain}"
                    fi
                fi
                
                # 如果提供了别名，更新别名
                if [[ -n "$alias" ]]; then
                    set_alias "$node_id" "$alias"
                fi
                
                if [[ $# -le 2 ]]; then
                    before_show_menu
                fi
                return 0
            fi
        fi
    fi
    
    # 添加到配置文件
    if [[ -f /etc/xboard-node/sync.yml ]]; then
        if grep -q "manual_node_ids:" /etc/xboard-node/sync.yml; then
            # 已有 manual_node_ids，检查是否为空数组
            if grep -q "manual_node_ids: \[\]" /etc/xboard-node/sync.yml; then
                # 替换空数组
                sed -i "s/manual_node_ids: \[\]/manual_node_ids:\n  - $node_id/" /etc/xboard-node/sync.yml
            else
                # 添加到列表
                sed -i "/manual_node_ids:/a \ \ - $node_id" /etc/xboard-node/sync.yml
            fi
        else
            # 没有 manual_node_ids，添加到文件末尾
            echo "" >> /etc/xboard-node/sync.yml
            echo "# 手动指定的节点ID" >> /etc/xboard-node/sync.yml
            echo "manual_node_ids:" >> /etc/xboard-node/sync.yml
            echo "  - $node_id" >> /etc/xboard-node/sync.yml
        fi
        echo -e "${green}${ICON_OK} 已添加节点 $node_id 到配置${plain}"
    else
        echo -e "${red}${ICON_ERR} 配置文件不存在，请先安装${plain}"
        return 1
    fi
    
    # 设置别名
    if [[ -n "$alias" ]]; then
        set_alias "$node_id" "$alias"
    fi
    
    # 执行同步
    echo ""
    echo -e "${ICON_ARROW} 执行同步..."
    /usr/local/bin/sync-nodes
    
    # 验证节点是否启动
    echo ""
    sleep 2
    local status=$(systemctl is-active xboard-node@$node_id.service 2>/dev/null || echo "inactive")
    if [[ "$status" == "active" ]]; then
        echo -e "${green}${ICON_OK} 节点 $node_id 已成功启动${plain}"
    else
        echo -e "${red}${ICON_ERR} 节点 $node_id 启动失败，请检查日志${plain}"
        echo -e "${ICON_INFO} 查看日志: ${cyan}journalctl -u xboard-node@$node_id.service -n 20${plain}"
    fi
    
    echo ""
    if [[ $# -le 2 ]]; then
        before_show_menu
    fi
}

remove_node() {
    local node_id=$1
    
    if [[ -z "$node_id" ]]; then
        echo -e "${red}${ICON_ERR} 用法: xnode remove-node <节点ID>${plain}"
        return 1
    fi
    
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 删除节点 $node_id"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    local alias=$(get_alias "$node_id")
    
    # 停止并禁用服务
    echo -e "  ${ICON_ARROW} 停止节点 $node_id ($alias)..."
    systemctl stop xboard-node@$node_id.service 2>/dev/null
    systemctl disable xboard-node@$node_id.service 2>/dev/null
    echo -e "  ${ICON_OK} 服务已停止"
    
    # 删除配置文件
    if [[ -f /etc/xboard-node/$node_id.yml ]]; then
        rm -f /etc/xboard-node/$node_id.yml
        echo -e "  ${ICON_OK} 配置文件已删除"
    fi
    
    # 从 sync.yml 移除
    if [[ -f /etc/xboard-node/sync.yml ]]; then
        sed -i "/^  - $node_id$/d" /etc/xboard-node/sync.yml
        echo -e "  ${ICON_OK} 已从配置中移除"
    fi
    
    # 删除别名
    remove_alias "$node_id"
    
    echo ""
    echo -e "${green}${ICON_OK} 节点 $node_id 已完全删除${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

set_node_alias() {
    local node_id=$1
    local alias=$2
    
    if [[ -z "$node_id" || -z "$alias" ]]; then
        echo -e "${red}${ICON_ERR} 用法: xnode set-alias <节点ID> <别名>${plain}"
        return 1
    fi
    
    set_alias "$node_id" "$alias"
}

# ========== 日志 ==========

show_sync_log() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_INFO} 同步日志"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    if [[ x"${release}" == x"alpine" ]]; then
        journalctl -u sync-nodes.service -n 50 --no-pager
    else
        journalctl -u sync-nodes.service -n 50 --no-pager
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_update_log() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_INFO} 更新日志"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    if [[ -f /var/log/xboard-node-update.log ]]; then
        tail -n 50 /var/log/xboard-node-update.log
    else
        echo -e "  ${ICON_WARN} ${yellow}日志文件不存在${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# ========== 开机自启 ==========

toggle_autostart() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 开机自启管理"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    # 检查当前状态
    local sync_enabled=$(systemctl is-enabled sync-nodes.timer 2>/dev/null)
    local update_enabled=$(systemctl is-enabled update-xboard-node.timer 2>/dev/null)
    
    echo -e "  ${purple}当前状态${plain}"
    echo -e "  ${cyan}────────────────${plain}"
    
    if [[ "$sync_enabled" == "enabled" ]]; then
        echo -e "  节点同步: ${green}已启用${plain}"
    else
        echo -e "  节点同步: ${yellow}未启用${plain}"
    fi
    
    if [[ "$update_enabled" == "enabled" ]]; then
        echo -e "  自动更新: ${green}已启用${plain}"
    else
        echo -e "  自动更新: ${yellow}未启用${plain}"
    fi
    
    echo ""
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${yellow}请选择操作${plain}"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    echo -e "  ${green}[1]${plain} 启用所有开机自启"
    echo -e "  ${green}[2]${plain} 禁用所有开机自启"
    echo -e "  ${green}[3]${plain} 仅启用节点同步"
    echo -e "  ${green}[4]${plain} 仅启用自动更新"
    echo -e "  ${green}[0]${plain} 返回"
    echo ""
    read -rp "  请选择 [0-4]: " choice
    
    case "$choice" in
        1)
            systemctl enable sync-nodes.timer
            systemctl enable update-xboard-node.timer
            echo -e "\n${green}${ICON_OK} 已启用所有开机自启${plain}"
            ;;
        2)
            systemctl disable sync-nodes.timer
            systemctl disable update-xboard-node.timer
            echo -e "\n${green}${ICON_OK} 已禁用所有开机自启${plain}"
            ;;
        3)
            systemctl enable sync-nodes.timer
            echo -e "\n${green}${ICON_OK} 已启用节点同步开机自启${plain}"
            ;;
        4)
            systemctl enable update-xboard-node.timer
            echo -e "\n${green}${ICON_OK} 已启用自动更新开机自启${plain}"
            ;;
        0)
            ;;
        *)
            echo -e "\n${red}${ICON_ERR} 无效选择${plain}"
            ;;
    esac
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# ========== 版本信息 ==========

show_version() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_INFO} 版本信息"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    echo -e "  ${purple}组件          版本        状态    ${plain}"
    echo -e "  ${cyan}──────────────────────────────────${plain}"
    
    # xboard-node
    if [[ -f /usr/local/bin/xboard-node ]]; then
        local xb_ver=$(/usr/local/bin/xboard-node -v 2>&1 | head -1 || echo "未知")
        echo -e "  xboard-node   ${green}$xb_ver${plain}    ${ICON_OK}"
    else
        echo -e "  xboard-node   ${red}未安装${plain}      ${ICON_ERR}"
    fi
    
    # sync-nodes
    if [[ -f /usr/local/bin/sync-nodes ]]; then
        local sync_ver=$(/usr/local/bin/sync-nodes -v 2>&1 | head -1 || echo "未知")
        echo -e "  sync-nodes    ${green}$sync_ver${plain}    ${ICON_OK}"
    else
        echo -e "  sync-nodes    ${red}未安装${plain}      ${ICON_ERR}"
    fi
    
    # 管理脚本
    echo -e "  xnode         ${green}v1.2.1${plain}        ${ICON_OK}"
    
    echo ""
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# ========== 子菜单 ==========

show_node_menu() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_NODE} 节点操作"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    echo -e "  ${green}[1]${plain} 启动所有节点"
    echo -e "  ${green}[2]${plain} 停止所有节点"
    echo -e "  ${green}[3]${plain} 重启所有节点"
    echo -e "  ${green}[0]${plain} 返回主菜单"
    echo ""
    read -rp "  请选择 [0-3]: " choice
    
    case "$choice" in
        1) start_all ;;
        2) stop_all ;;
        3) restart_all ;;
        0) show_menu ;;
        *) echo -e "${red}${ICON_ERR} 无效选择${plain}" && show_node_menu ;;
    esac
}

show_update_menu() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 更新选项"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    echo -e "  ${green}[1]${plain} 更新 xboard-node"
    echo -e "  ${green}[2]${plain} 更新管理脚本"
    echo -e "  ${green}[3]${plain} 更新 sync-nodes"
    echo -e "  ${green}[0]${plain} 返回主菜单"
    echo ""
    read -rp "  请选择 [0-3]: " choice
    
    case "$choice" in
        1) update ;;
        2) update_script ;;
        3) update_sync_nodes ;;
        0) show_menu ;;
        *) echo -e "${red}${ICON_ERR} 无效选择${plain}" && show_update_menu ;;
    esac
}

show_log_menu() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_INFO} 查看日志"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    echo -e "  ${green}[1]${plain} 查看同步日志"
    echo -e "  ${green}[2]${plain} 查看更新日志"
    echo -e "  ${green}[0]${plain} 返回主菜单"
    echo ""
    read -rp "  请选择 [0-2]: " choice
    
    case "$choice" in
        1) show_sync_log ;;
        2) show_update_log ;;
        0) show_menu ;;
        *) echo -e "${red}${ICON_ERR} 无效选择${plain}" && show_log_menu ;;
    esac
}

show_manage_menu() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_NODE} 节点管理"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    echo -e "  ${green}[1]${plain} 列出所有节点"
    echo -e "  ${green}[2]${plain} 添加节点"
    echo -e "  ${green}[3]${plain} 删除节点"
    echo -e "  ${green}[4]${plain} 设置节点别名"
    echo -e "  ${green}[0]${plain} 返回主菜单"
    echo ""
    read -rp "  请选择 [0-4]: " choice
    
    case "$choice" in
        1) list_nodes ;;
        2)
            read -rp "  请输入节点ID: " node_id
            read -rp "  请输入节点别名（可选）: " alias
            add_node "$node_id" "$alias"
            ;;
        3)
            read -rp "  请输入节点ID: " node_id
            remove_node "$node_id"
            ;;
        4)
            read -rp "  请输入节点ID: " node_id
            read -rp "  请输入节点别名: " alias
            set_node_alias "$node_id" "$alias"
            ;;
        0) show_menu ;;
        *) echo -e "${red}${ICON_ERR} 无效选择${plain}" && show_manage_menu ;;
    esac
}

# ========== 主菜单 ==========

show_menu() {
    echo -e "${cyan}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║              ____  __                  __     __             ║
║             / __ \/ /_  ___  ____  ____/ /__  / /_           ║
║            / /_/ / __ \/ _ \/ __ \/ __  / _ \/ __/           ║
║           / ____/ / / /  __/ / / / /_/ /  __/ /_             ║
║          /_/   /_/ /_/\___/_/ /_/\__,_/\___/\__/             ║
║                                                              ║
║                  Node Auto-Sync 管理菜单                     ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${plain}"
    echo -e ""
    echo -e "  ${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "  ${cyan}│${plain} ${yellow}主菜单${plain}                                                       "
    echo -e "  ${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo -e "  ${green}[0]${plain} 修改配置文件"
    echo -e "  ${green}[1]${plain} 查看节点状态"
    echo -e "  ${green}[2]${plain} 节点操作（启动/停止/重启）"
    echo -e "  ${green}[3]${plain} 手动同步节点"
    echo -e "  ${green}[4]${plain} 更新（xboard-node/脚本/sync-nodes）"
    echo -e "  ${green}[5]${plain} 节点管理（列表/添加/删除/别名）"
    echo -e "  ${green}[6]${plain} 查看日志（同步/更新）"
    echo -e "  ${green}[7]${plain} 开机自启（切换）"
    echo -e "  ${green}[8]${plain} 查看版本信息"
    echo -e "  ${green}[9]${plain} 安装/重新安装"
    echo -e "  ${green}[10]${plain} 卸载"
    echo -e "  ${green}[11]${plain} 退出脚本"
    echo -e "${cyan}────────────────────────────────────────────────────────────${plain}"
    read -rp "  请选择 [0-11]: " choice
    
    case "$choice" in
        0) config ;;
        1) status ;;
        2) show_node_menu ;;
        3) sync ;;
        4) show_update_menu ;;
        5) show_manage_menu ;;
        6) show_log_menu ;;
        7) toggle_autostart ;;
        8) show_version ;;
        9) install ;;
        10) uninstall ;;
        11) echo -e "\n${green}再见！${plain}\n" && exit 0 ;;
        *) echo -e "${red}${ICON_ERR} 无效选择，请重新输入${plain}" && sleep 1 && show_menu ;;
    esac
}

# ========== 命令行参数 ==========

case "$1" in
    status)
        status 1
        ;;
    start)
        start_all 1
        ;;
    stop)
        stop_all 1
        ;;
    restart)
        restart_all 1
        ;;
    sync)
        sync 1
        ;;
    list-nodes)
        list_nodes 1
        ;;
    add-node)
        add_node "$2" "$3"
        ;;
    remove-node)
        remove_node "$2"
        ;;
    set-alias)
        set_node_alias "$2" "$3"
        ;;
    log)
        show_sync_log 1
        ;;
    update)
        update 1
        ;;
    update-script)
        update_script 1
        ;;
    update-sync)
        update_sync_nodes 1
        ;;
    version)
        show_version 1
        ;;
    install)
        install 1
        ;;
    uninstall)
        uninstall 1
        ;;
    config)
        config 1
        ;;
    *)
        show_menu
        ;;
esac
