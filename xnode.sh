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
ICON_INFO="i️"
ICON_ROCKET="🚀"
ICON_GEAR="⚙️"
ICON_CHECK="✔"
ICON_ARROW="→"
ICON_NODE="🔷"

cur_dir=$(pwd)
alias_file="/etc/xboard-node/node_alias.yml"

# ========== 工具函数 ==========

# 操作完成后暂停等待，统一处理
break_end() {
    echo ""
    echo -e "${green}${ICON_OK} 操作完成${plain}"
    echo -n -e "${yellow}按任意键继续... ${plain}"
    read -n 1 -s -r -p ""
    echo ""
    clear
}

# 带重试的 curl 调用
retry_curl() {
    local url="$1"
    local retries=3
    local delay=2

    for i in $(seq 1 $retries); do
        local result=$(curl -sL "$url" 2>/dev/null)
        if [[ -n "$result" ]]; then
            echo "$result"
            return 0
        fi
        [[ $i -lt $retries ]] && sleep $delay
    done
    return 1
}

# 版本比较函数 (version_gt "1.0.0" "0.9.0" -> true)
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# 版本比较函数 (version_ge "1.0.0" "1.0.0" -> true)
version_ge() {
    # 检查 $1 >= $2
    test "$(printf '%s\n' "$1" "$2" | sort -V | head -n 1)" != "$1" -o "$1" = "$2"
}

# ========== 系统检查 ==========

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}${ICON_ERR} 错误:${plain} 必须使用root用户运行此脚本!\n" && exit 1

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
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
else
    echo -e "${red}${ICON_ERR} 未检测到系统版本!${plain}\n"
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

# 从面板获取节点名称
get_node_name_from_panel() {
    local node_id=$1

    # 检查配置文件是否存在
    if [[ ! -f /etc/xboard-node/sync.yml ]]; then
        echo ""
        return
    fi

    # 读取配置
    local xboard_url=$(grep '^xboard_url:' /etc/xboard-node/sync.yml 2>/dev/null | awk '{print $2}' | tr -d '"')
    local admin_path=$(grep '^admin_path:' /etc/xboard-node/sync.yml 2>/dev/null | awk '{print $2}' | tr -d '"')
    local panel_token=$(grep '^panel_token:' /etc/xboard-node/sync.yml 2>/dev/null | awk '{print $2}' | tr -d '"')

    if [[ -z "$xboard_url" || -z "$admin_path" || -z "$panel_token" ]]; then
        echo ""
        return
    fi

    # 调用面板 API 获取节点信息
    local api_url="${xboard_url}/api/v2/${admin_path}/server/manage/fetch"
    local response=$(curl -sL -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${panel_token:0:8}..." \
        -d "{\"node_id\": ${node_id}}" 2>/dev/null)


    # 解析响应获取节点名称
    if [[ -n "$response" ]]; then
        local name=$(echo "$response" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        if [[ -n "$name" ]]; then
            echo "$name"
            return
        fi
    fi

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
            temp="$2"
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
    # 只等待用户按回车,不调用 show_menu
    # 调用此函数的函数会继续执行,然后返回主菜单
    echo ""
    echo -n -e "${yellow}按回车返回主菜单: ${plain}"
    read temp
    # 不调用 show_menu,让调用者继续执行
}





config() {
    if [[ ! -f /etc/xboard-node/sync.yml ]]; then
        echo -e "${red}${ICON_ERR} 配置文件不存在,请先安装${plain}"
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
    echo -e "${yellow}${ICON_WARN} 配置已修改,是否重启同步服务?${plain}"
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
        show_menu
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
        show_menu
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
        echo -e "  ${ICON_ERR} ${red}未安装,请先运行安装脚本${plain}"
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
        show_menu
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
            # 如果没有 manual_node_ids,尝试从配置文件中查找
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
        show_menu
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
        show_menu
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
        show_menu
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
        show_menu
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
            echo -e "  ${ICON_INFO} 使用自动同步模式(未配置手动节点)"
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
        show_menu
    fi
}

add_node() {
    local node_id=$1
    local alias=$2

    if [[ -z "$node_id" ]]; then
        echo -e "${red}${ICON_ERR} 用法: xnode add-node <节点ID> [别名]${plain}"
        return 1
    fi
    
    # 验证节点ID必须是数字
    if ! [[ "$node_id" =~ ^[0-9]+$ ]]; then
        echo -e "${red}${ICON_ERR} 节点ID必须是数字${plain}"
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
                    echo -e "${yellow}${ICON_WARN} 节点 $node_id 未运行,正在启动...${plain}"
                    systemctl start xboard-node@$node_id.service
                    sleep 2
                    status=$(systemctl is-active xboard-node@$node_id.service 2>/dev/null || echo "inactive")
                    if [[ "$status" == "active" ]]; then
                        echo -e "${green}${ICON_OK} 节点 $node_id 已启动${plain}"
                    else
                        echo -e "${red}${ICON_ERR} 节点 $node_id 启动失败,请检查日志${plain}"
                    fi
                fi

                # 如果提供了别名,更新别名
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
            # 已有 manual_node_ids,检查是否为空数组
            if grep -q "manual_node_ids: \[\]" /etc/xboard-node/sync.yml; then
                # 替换空数组
                sed -i "s/manual_node_ids: \[\]/manual_node_ids:\n  - $node_id/" /etc/xboard-node/sync.yml
            else
                # 添加到列表
                sed -i "/manual_node_ids:/a \ \ - $node_id" /etc/xboard-node/sync.yml
            fi
        else
            # 没有 manual_node_ids,添加到文件末尾
            echo "" >> /etc/xboard-node/sync.yml
            echo "# 手动指定的节点ID" >> /etc/xboard-node/sync.yml
            echo "manual_node_ids:" >> /etc/xboard-node/sync.yml
            echo "  - $node_id" >> /etc/xboard-node/sync.yml
        fi
        echo -e "${green}${ICON_OK} 已添加节点 $node_id 到配置${plain}"
    else
        echo -e "${red}${ICON_ERR} 配置文件不存在,请先安装${plain}"
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
        echo -e "${red}${ICON_ERR} 节点 $node_id 启动失败,请检查日志${plain}"
        echo -e "${ICON_INFO} 查看日志: ${cyan}journalctl -u xboard-node@$node_id.service -n 20${plain}"
    fi

    echo ""
    if [[ $# -le 2 ]]; then
        before_show_menu
        show_menu
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
        show_menu
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
        show_menu
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
        show_menu
    fi
}

# ========== 开机自启 ==========

toggle_autostart() {
    clear
    echo -e "${cyan}------------------------${plain}"
    echo -e "${cyan}开机自启管理${plain}"
    echo -e "${cyan}------------------------${plain}"

    # 检查状态
    local sync_timer=$(systemctl is-enabled sync-nodes.timer 2>/dev/null)
    local update_timer=$(systemctl is-enabled update-xboard-node.timer 2>/dev/null)

    if [[ "$sync_timer" == "enabled" ]]; then
        echo -e "节点同步: ${green}已启用${plain}"
    else
        echo -e "节点同步: ${yellow}未启用${plain}"
    fi

    if [[ "$update_timer" == "enabled" ]]; then
        echo -e "自动更新: ${green}已启用${plain}"
    else
        echo -e "自动更新: ${yellow}未启用${plain}"
    fi

    echo ""
    echo -e "${cyan}------------------------${plain}"
    echo -e "${cyan}请选择操作${plain}"
    echo -e "${cyan}------------------------${plain}"
    echo -e "${cyan}1.  ${plain}启用所有开机自启"
    echo -e "${cyan}2.  ${plain}禁用所有开机自启"
    echo -e "${cyan}3.  ${plain}仅启用节点同步"
    echo -e "${cyan}4.  ${plain}仅启用自动更新"
    echo -e "${cyan}------------------------${plain}"
    echo -e "${cyan}0.  ${plain}返回主菜单"
    echo -e "${cyan}------------------------${plain}"
    read -rp "请输入你的选择: " choice

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
        show_menu
    fi
}

# ========== 版本信息 ==========

# 从 GitHub 获取最新版本
get_latest_version_from_github() {
    local repo="$1"
    local response
    local latest_version

    # 使用重试机制获取最新版本
    response=$(retry_curl "https://api.github.com/repos/${repo}/releases/latest")
    if [[ -n "$response" ]]; then
        latest_version=$(echo "$response" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
    fi

    # 如果失败,尝试获取 releases 列表
    if [[ -z "$latest_version" ]]; then
        response=$(retry_curl "https://api.github.com/repos/${repo}/releases")
        if [[ -n "$response" ]]; then
            latest_version=$(echo "$response" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
        fi
    fi

    echo "${latest_version:-未知}"
}

# 提取版本号
extract_version() {
    local text="$1"
    # 提取 v1.0.3 或 1.0.3 格式
    echo "$text" | grep -oE '[vV]?[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*' | head -1
}

show_version() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_INFO} 版本信息"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    
    echo -e "  ${purple}组件             版本${plain}"
    echo -e "  ${cyan}──────────────────────────────────${plain}"
    
    # xboard-node
    if [[ -f /usr/local/bin/xboard-node ]]; then
        local current_xb_ver=$(/usr/local/bin/xboard-node -v 2>&1 | head -1)
        local extracted_xb_ver=$(extract_version "$current_xb_ver")
        if [[ -z "$extracted_xb_ver" ]]; then
            current_xb_ver="${red}未知${plain}"
        else
            current_xb_ver="${green}${extracted_xb_ver}${plain}"
        fi
        echo -e "  xboard-node      ${current_xb_ver}"
    else
        echo -e "  xboard-node      ${red}未安装${plain}"
    fi
    
    # sync-nodes
    if [[ -f /usr/local/bin/sync-nodes ]]; then
        local current_sync_ver=$(/usr/local/bin/sync-nodes -v 2>&1 | head -1)
        local extracted_sync_ver=$(extract_version "$current_sync_ver")
        if [[ -z "$extracted_sync_ver" ]]; then
            current_sync_ver="${red}未知${plain}"
        else
            current_sync_ver="${green}${extracted_sync_ver}${plain}"
        fi
        echo -e "  sync-nodes       ${current_sync_ver}"
    else
        echo -e "  sync-nodes       ${red}未安装${plain}"
    fi

    # 管理脚本
    local current_xnode_ver="v1.2.5"
    echo -e "  xnode            ${green}${current_xnode_ver}${plain}"
    
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
        show_menu
    fi
}


# ========== 新菜单函数 ==========

show_node_management_menu() {
    while true; do
        clear
        echo -e "${cyan}------------------------${plain}"
        echo -e "${cyan}节点管理${plain}"
        echo -e "${cyan}------------------------${plain}"

        # 显示节点状态
        RUNNING_NODES=$(systemctl list-units --type=service --state=running | grep "xboard-node@" | wc -l)
        TOTAL_NODES=$(ls /etc/xboard-node/*.yml 2>/dev/null | grep -v "sync.yml" | grep -v "node_alias.yml" | wc -l)
        echo -e "运行中: ${green}${RUNNING_NODES}${plain} / 总数: ${TOTAL_NODES}"
        echo ""

        echo -e "${cyan}1.  ${plain}查看节点状态"
        echo -e "${cyan}2.  ${plain}启动所有节点"
        echo -e "${cyan}3.  ${plain}停止所有节点"
        echo -e "${cyan}4.  ${plain}重启所有节点"
        echo -e "${cyan}5.  ${plain}手动同步节点"
        echo -e "${cyan}6.  ${plain}列出所有节点"
        echo -e "${cyan}7.  ${plain}添加节点"
        echo -e "${cyan}8.  ${plain}删除节点"
        echo -e "${cyan}9.  ${plain}设置节点别名"
        echo -e "${cyan}------------------------${plain}"
        echo -e "${cyan}0.  ${plain}返回主菜单"
        echo -e "${cyan}------------------------${plain}"
        read -rp "请输入你的选择: " choice

        case "$choice" in
            1) status ;;
            2) start_all ;;
            3) stop_all ;;
            4) restart_all ;;
            5) sync ;;
            6) list_nodes ;;
            7)
                read -rp "  请输入节点ID: " node_id
                read -rp "  请输入节点别名(可选): " alias
                add_node "$node_id" "$alias"
                ;;
            8)
                read -rp "  请输入节点ID: " node_id
                remove_node "$node_id"
                ;;
            9)
                read -rp "  请输入节点ID: " node_id
                read -rp "  请输入节点别名: " alias
                set_node_alias "$node_id" "$alias"
                ;;
            0) return ;;
            *) echo -e "${red}${ICON_ERR} 无效选择${plain}" && sleep 1 ;;
        esac

        echo ""
        read -rp "  按 Enter 继续..."
    done
}

update_all() {
    echo -e "${cyan}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${plain} ${ICON_GEAR} 更新"
    echo -e "${cyan}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""

    # 检查配置文件
    if [ ! -d "/etc/xboard-node" ] || [ ! -f "/etc/xboard-node/sync.yml" ]; then
        echo -e "  ${ICON_ERR} ${red}未检测到配置文件,请先安装${plain}"
        echo ""
        echo -e "${yellow}按回车返回主菜单: ${plain}"
        read temp
        return 1
    fi

    # 备份配置
    BACKUP_DIR="/tmp/xnode-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    echo -e "  ${ICON_INFO} 备份配置文件..."
    for file in /etc/xboard-node/*.yml /etc/xboard-node/*.yaml; do
        [ -f "$file" ] && cp "$file" "$BACKUP_DIR/" && echo -e "    ${ICON_OK} $(basename $file)"
    done
    [ -f "/etc/xboard-node/node_alias.yml" ] && cp /etc/xboard-node/node_alias.yml "$BACKUP_DIR/" && echo -e "    ${ICON_OK} node_alias.yml"
    echo -e "  ${ICON_OK} 配置已备份到: ${cyan}$BACKUP_DIR${plain}"
    echo ""

    # 停止服务
    echo -e "  ${ICON_INFO} 停止服务..."
    RUNNING_NODES=$(systemctl list-units --type=service --state=running | grep "xboard-node@" | awk '{print $1}' | cut -d'@' -f2 | cut -d'.' -f1)
    if [ -n "$RUNNING_NODES" ]; then
        for node in $RUNNING_NODES; do
            systemctl stop "xboard-node@$node" 2>/dev/null
            echo -e "    ${ICON_OK} 停止节点: $node"
        done
    fi
    systemctl stop sync-nodes.timer 2>/dev/null
    systemctl stop update-xboard-node.timer 2>/dev/null
    echo -e "  ${ICON_OK} 服务已停止"
    echo ""

    # 下载组件
    echo -e "  ${ICON_INFO} 下载最新组件..."
    echo ""

    # 检测架构
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_SUFFIX="amd64" ;;
        aarch64) ARCH_SUFFIX="arm64" ;;
        *)       echo -e "  ${ICON_ERR} ${red}不支持的架构: $ARCH${plain}"; rm -rf "$BACKUP_DIR"; return 1 ;;
    esac

    # 获取版本
    SYNC_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/xnodeauto/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
    [ -z "$SYNC_VERSION" ] && SYNC_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/xnodeauto/releases" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
    [ -z "$SYNC_VERSION" ] && SYNC_VERSION="v1.2.5"

    # 获取 xboard-node 版本
    XBOARD_NODE_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/Xboard-Node/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
    [ -z "$XBOARD_NODE_VERSION" ] && XBOARD_NODE_VERSION=$(curl -sL "https://api.github.com/repos/ipevel/Xboard-Node/releases" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
    [ -z "$XBOARD_NODE_VERSION" ] && XBOARD_NODE_VERSION="v1.0.2"

    # 下载 sync-nodes
    echo -e "    ${ICON_ARROW} sync-nodes ($SYNC_VERSION)"
    if wget -q --show-progress -O /usr/local/bin/sync-nodes "https://github.com/ipevel/xnodeauto/releases/download/${SYNC_VERSION}/sync-nodes-linux-${ARCH_SUFFIX}" 2>&1; then
        chmod +x /usr/local/bin/sync-nodes
        echo -e "    ${ICON_OK} sync-nodes 更新完成"
    else
        echo -e "    ${ICON_ERR} sync-nodes 下载失败"
    fi

    # 下载 xboard-node
    echo -e "    ${ICON_ARROW} xboard-node ($XBOARD_NODE_VERSION)"
    if wget -q --show-progress -O /usr/local/bin/xboard-node "https://github.com/ipevel/Xboard-Node/releases/download/${XBOARD_NODE_VERSION}/xboard-node-linux-${ARCH_SUFFIX}" 2>&1; then
        chmod +x /usr/local/bin/xboard-node
        echo -e "    ${ICON_OK} xboard-node 更新完成"
    else
        echo -e "    ${ICON_ERR} xboard-node 下载失败"
    fi

    # 下载管理脚本(先下载到临时文件,避免正在运行时覆盖出错)
    echo -e "    ${ICON_ARROW} xnode"
    if wget -q -O /tmp/xnode.tmp "https://raw.githubusercontent.com/ipevel/xnodeauto/main/xnode.sh?t=$(date +%s)"; then
        chmod +x /tmp/xnode.tmp
        mv -f /tmp/xnode.tmp /usr/local/bin/xnode
        echo -e "    ${ICON_OK} xnode 更新完成"
    else
        rm -f /tmp/xnode.tmp
        echo -e "    ${ICON_ERR} xnode 下载失败"
    fi

    # 下载 systemd 文件
    echo -e "    ${ICON_ARROW} systemd 服务文件"
    for file in xboard-node@.service sync-nodes.service sync-nodes.timer update-xboard-node.service update-xboard-node.timer; do
        wget -q -O "/etc/systemd/system/$file" "https://raw.githubusercontent.com/ipevel/xnodeauto/main/systemd/$file" 2>/dev/null
    done
    systemctl daemon-reload
    echo -e "    ${ICON_OK} systemd 服务文件更新完成"

    # 下载 update-xboard-node.sh(先下载到临时文件,避免正在运行时覆盖出错)
    echo -e "    ${ICON_ARROW} update-xboard-node.sh"
    if wget -q -O /tmp/update-xboard-node.tmp "https://raw.githubusercontent.com/ipevel/xnodeauto/main/update-xboard-node.sh?t=$(date +%s)"; then
        chmod +x /tmp/update-xboard-node.tmp
        mv -f /tmp/update-xboard-node.tmp /usr/local/bin/update-xboard-node.sh
        echo -e "    ${ICON_OK} update-xboard-node.sh 更新完成"
    else
        rm -f /tmp/update-xboard-node.tmp
        echo -e "    ${ICON_ERR} update-xboard-node.sh 下载失败"
    fi
    echo ""

    # 恢复配置
    echo -e "  ${ICON_INFO} 恢复配置文件..."
    for file in "$BACKUP_DIR"/*.yml "$BACKUP_DIR"/*.yaml; do
        [ -f "$file" ] && cp "$file" /etc/xboard-node/ && echo -e "    ${ICON_OK} $(basename $file)"
    done
    [ -f "$BACKUP_DIR/node_alias.yml" ] && cp "$BACKUP_DIR/node_alias.yml" /etc/xboard-node/ && echo -e "    ${ICON_OK} node_alias.yml"
    rm -rf "$BACKUP_DIR"
    echo -e "  ${ICON_OK} 配置恢复完成"
    echo ""

    # 重启服务
    if [ -n "$RUNNING_NODES" ]; then
        echo -e "  ${ICON_INFO} 重启节点服务..."
        for node in $RUNNING_NODES; do
            systemctl start "xboard-node@$node" 2>/dev/null
            echo -e "    ${ICON_OK} 启动节点: $node"
        done
        echo ""
    fi

    systemctl start sync-nodes.timer 2>/dev/null
    systemctl start update-xboard-node.timer 2>/dev/null

    echo -e "${green}╔══════════════════════════════════════════════════════════════╗${plain}"
    echo -e "${green}║${plain}                                                              ${green}║${plain}"
    echo -e "${green}║${plain}           ${ICON_OK} 更新完成!配置已保留                        ${green}║${plain}"
    echo -e "${green}║${plain}                                                              ${green}║${plain}"
    echo -e "${green}╚══════════════════════════════════════════════════════════════╝${plain}"
    echo ""

    # 直接返回主菜单,不等待输入
    if [[ $# == 0 ]]; then
        echo ""
        show_menu
    fi
}

install_all() {
    echo -e "${red}┌──────────────────────────────────────────────────────────────┐${plain}"
    echo -e "${red}│${plain} ${ICON_WARN} 安装"
    echo -e "${red}└──────────────────────────────────────────────────────────────┘${plain}"
    echo ""
    echo -e "  ${yellow}这将清除所有现有配置并重新安装${plain}"
    echo ""
    confirm "确定要继续吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    echo ""

    # 调用官方安装脚本
    bash <(curl -Ls https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)

    # 直接返回主菜单,不等待输入
    if [[ $# == 0 ]]; then
        echo ""
        show_menu
    fi
}


# ========== 子菜单 ==========



show_log_menu() {
    clear
    echo -e "${cyan}------------------------${plain}"
    echo -e "${cyan}查看日志${plain}"
    echo -e "${cyan}------------------------${plain}"
    echo -e "${cyan}1.  ${plain}查看同步日志"
    echo -e "${cyan}2.  ${plain}查看更新日志"
    echo -e "${cyan}------------------------${plain}"
    echo -e "${cyan}0.  ${plain}返回主菜单"
    echo -e "${cyan}------------------------${plain}"
    read -rp "请输入你的选择: " choice

    case "$choice" in
        1) show_sync_log ;;
        2) show_update_log ;;
        0) clear && show_menu ;;
        *) echo -e "${red}${ICON_ERR} 无效选择${plain}" && sleep 1 && clear && show_log_menu ;;
    esac
}


# ========== 主菜单 ==========

show_menu() {
    clear
    echo "============================================"
    echo "    XNode Auto-Sync 管理菜单"
    echo "============================================"
    echo ""
    echo "  1. 版本信息"
    echo "  2. 修改配置"
    echo "  3. 节点管理"
    echo "  4. 查看日志"
    echo "  5. 开机自启"
    echo "  6. 更新脚本"
    echo "  7. 重新安装"
    echo "  8. 卸载脚本"
    echo ""
    echo "  0. 退出脚本"
    echo ""
    echo "============================================"
    read -rp "请输入你的选择: " choice

    case "$choice" in
        1) show_version ;;
        2) config ;;
        3) show_node_management_menu ;;
        4) show_log_menu ;;
        5) toggle_autostart ;;
        6) update_all ;;
        7) install_all ;;
        8) uninstall ;;
        0) echo "" && echo "再见!" && echo "" && exit 0 ;;
        *) echo "无效选择，请重新输入" && sleep 1 && clear && show_menu ;;
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
        update_all 1
        ;;
    version)
        show_version 1
        ;;
    install)
        install_all 1
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
