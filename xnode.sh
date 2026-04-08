#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

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
    echo -e "${red}未检测到系统版本！${plain}\n"
fi

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
    echo -e "${green}开始更新 xboard-node...${plain}"
    /usr/local/bin/update-xboard-node.sh
    echo -e "${green}更新完成！${plain}"
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_script() {
    echo -e "${green}开始更新 xnode 管理脚本...${plain}"
    
    # 备份当前版本
    if [ -f /usr/bin/xnode ]; then
        cp /usr/bin/xnode /usr/bin/xnode.bak
    fi
    
    # 下载新版本
    wget -q -O /usr/bin/xnode https://raw.githubusercontent.com/ipevel/xnodeauto/main/xnode.sh
    
    if [ $? -eq 0 ] && [ -s /usr/bin/xnode ]; then
        chmod +x /usr/bin/xnode
        echo -e "${green}管理脚本更新完成！${plain}"
        rm -f /usr/bin/xnode.bak
    else
        echo -e "${red}更新失败，恢复旧版本${plain}"
        [ -f /usr/bin/xnode.bak ] && mv /usr/bin/xnode.bak /usr/bin/xnode
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_sync_nodes() {
    echo -e "${green}开始更新 sync-nodes...${plain}"
    
    # 检测架构
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_SUFFIX="amd64" ;;
        aarch64) ARCH_SUFFIX="arm64" ;;
        *)
            echo -e "${red}不支持的架构: $ARCH${plain}"
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            return
            ;;
    esac
    
    BINARY_NAME="sync-nodes-linux-${ARCH_SUFFIX}"
    DOWNLOAD_URL="https://github.com/ipevel/xnodeauto/releases/latest/download/${BINARY_NAME}"
    
    echo -e "${yellow}架构: $ARCH ($ARCH_SUFFIX)${plain}"
    echo -e "${yellow}下载地址: $DOWNLOAD_URL${plain}"
    
    # 备份当前版本
    if [ -f /usr/local/bin/sync-nodes ]; then
        cp /usr/local/bin/sync-nodes /usr/local/bin/sync-nodes.bak
        echo -e "${yellow}已备份旧版本${plain}"
    fi
    
    # 下载新版本
    wget -q -O /usr/local/bin/sync-nodes "$DOWNLOAD_URL"
    
    if [ $? -eq 0 ] && [ -s /usr/local/bin/sync-nodes ]; then
        chmod +x /usr/local/bin/sync-nodes
        echo -e "${green}sync-nodes 更新完成！${plain}"
        
        # 显示版本
        if /usr/local/bin/sync-nodes -v 2>/dev/null; then
            echo ""
        fi
        
        rm -f /usr/local/bin/sync-nodes.bak
        
        # 询问是否重启同步服务
        if [[ x"${release}" == x"alpine" ]]; then
            if rc-service sync-nodes status 2>/dev/null | grep -q "started"; then
                echo -e "${yellow}重启同步服务...${plain}"
                rc-service sync-nodes restart
            fi
        else
            if systemctl is-active sync-nodes.service 2>/dev/null | grep -q "active"; then
                echo -e "${yellow}重启同步服务...${plain}"
                systemctl restart sync-nodes.service
            fi
        fi
    else
        echo -e "${red}更新失败，恢复旧版本${plain}"
        [ -f /usr/local/bin/sync-nodes.bak ] && mv /usr/local/bin/sync-nodes.bak /usr/local/bin/sync-nodes
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    if [[ ! -f /etc/xboard-node/sync.yml ]]; then
        echo -e "${red}配置文件不存在，请先安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    
    echo -e "${green}配置文件路径: /etc/xboard-node/sync.yml${plain}"
    echo ""
    vi /etc/xboard-node/sync.yml
    
    echo ""
    echo -e "${yellow}配置已修改，是否重启同步服务？${plain}"
    confirm "重启同步服务"
    if [[ $? == 0 ]]; then
        if [[ x"${release}" == x"alpine" ]]; then
            rc-service sync-nodes restart
        else
            systemctl restart sync-nodes.service
        fi
        echo -e "${green}同步服务已重启${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall() {
    confirm "确定要卸载 xnodeauto 吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    
    echo -e "${yellow}正在卸载...${plain}"
    
    # 停止并禁用所有节点服务
    echo -e "${yellow}停止所有节点服务...${plain}"
    if [[ x"${release}" == x"alpine" ]]; then
        # Alpine: 停止所有 xboard-node 服务
        for service in $(ls /etc/init.d/ 2>/dev/null | grep "^xboard-node@"); do
            rc-service "$service" stop 2>/dev/null
            rc-update del "$service" 2>/dev/null
            rm -f "/etc/init.d/$service"
        done
        # 停止同步和更新服务
        rc-service sync-nodes stop 2>/dev/null
        rc-service update-xboard-node stop 2>/dev/null
        rc-update del sync-nodes 2>/dev/null
        rc-update del update-xboard-node 2>/dev/null
        rm -f /etc/init.d/sync-nodes
        rm -f /etc/init.d/update-xboard-node
    else
        # systemd: 停止所有 xboard-node 服务
        for service in $(systemctl list-units --all --type=service 2>/dev/null | grep "xboard-node@" | awk '{print $1}'); do
            systemctl stop "$service" 2>/dev/null
            systemctl disable "$service" 2>/dev/null
        done
        # 删除所有 xboard-node 服务文件
        rm -f /etc/systemd/system/xboard-node@*.service
        # 停止同步和更新服务
        systemctl stop sync-nodes.timer 2>/dev/null
        systemctl stop sync-nodes.service 2>/dev/null
        systemctl stop update-xboard-node.timer 2>/dev/null
        systemctl disable sync-nodes.timer 2>/dev/null
        systemctl disable sync-nodes.service 2>/dev/null
        systemctl disable update-xboard-node.timer 2>/dev/null
        # 删除服务文件
        rm -f /etc/systemd/system/sync-nodes.service
        rm -f /etc/systemd/system/sync-nodes.timer
        rm -f /etc/systemd/system/update-xboard-node.service
        rm -f /etc/systemd/system/update-xboard-node.timer
        rm -f /etc/systemd/system/xboard-node@.service
        # 重新加载 systemd
        systemctl daemon-reload
    fi
    
    # 删除配置目录
    echo -e "${yellow}删除配置文件...${plain}"
    rm -rf /etc/xboard-node
    
    # 删除程序文件
    echo -e "${yellow}删除程序文件...${plain}"
    rm -f /usr/local/bin/sync-nodes
    rm -f /usr/local/bin/xboard-node
    rm -f /usr/local/bin/update-xboard-node.sh
    rm -f /usr/bin/xnode
    
    # 删除日志文件
    echo -e "${yellow}删除日志文件...${plain}"
    rm -f /var/log/xboard-node-update.log
    rm -f /var/log/sync-nodes.log
    
    # 删除备份文件
    rm -f /usr/local/bin/sync-nodes.bak
    rm -f /usr/local/bin/xboard-node.bak
    rm -f /usr/bin/xnode.bak
    
    echo ""
    echo -e "${green}卸载成功！${plain}"
    echo -e "${green}已删除所有服务、配置和程序文件${plain}"
    echo ""
    
    if [[ $# == 0 ]]; then
        exit 0
    fi
}

# 列出所有节点
list_nodes() {
    echo -e "${green}节点列表:${plain}"
    echo ""
    
    # 读取手动配置的节点ID
    local manual_ids=""
    if [[ -f /etc/xboard-node/sync.yml ]]; then
        manual_ids=$(grep -A 100 "manual_node_ids:" /etc/xboard-node/sync.yml 2>/dev/null | grep -E "^\s+-\s+[0-9]+" | awk '{print $2}' | tr '\n' ' ')
    fi
    
    if [[ -n "$manual_ids" ]]; then
        echo -e "${yellow}手动配置的节点:${plain} $manual_ids"
    else
        echo -e "${yellow}手动配置的节点:${plain} 无（使用IP自动匹配）"
    fi
    echo ""
    
    # 列出所有节点
    local count=0
    for node_id in $(get_node_ids); do
        ((count++))
        if check_node_status $node_id; then
            echo -e "  ${green}●${plain} 节点 $node_id - 运行中"
        else
            echo -e "  ${red}○${plain} 节点 $node_id - 已停止"
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        echo -e "  ${yellow}无节点${plain}"
    fi
    echo ""
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 添加节点
add_node() {
    local node_id=$1
    
    if [[ -z "$node_id" ]]; then
        echo -e "${red}错误: 请指定节点ID${plain}"
        echo "用法: xnode add-node <节点ID>"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    
    # 检查配置文件
    if [[ ! -f /etc/xboard-node/sync.yml ]]; then
        echo -e "${red}错误: 配置文件不存在，请先运行安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    
    # 检查节点ID是否有效（必须是数字）
    if ! [[ "$node_id" =~ ^[0-9]+$ ]]; then
        echo -e "${red}错误: 节点ID必须是数字${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    
    # 检查是否已存在
    if grep -q "^\s*-\s*${node_id}$" /etc/xboard-node/sync.yml 2>/dev/null; then
        echo -e "${yellow}节点 $node_id 已在配置中${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    
    # 添加节点ID到配置文件
    echo -e "${yellow}添加节点 $node_id...${plain}"
    
    # 检查是否已有 manual_node_ids 配置
    if grep -q "^manual_node_ids:" /etc/xboard-node/sync.yml; then
        # 在 manual_node_ids 下添加
        sed -i "/^manual_node_ids:/a \ \ - ${node_id}" /etc/xboard-node/sync.yml
    else
        # 添加 manual_node_ids 配置
        echo -e "\nmanual_node_ids:\n  - ${node_id}" >> /etc/xboard-node/sync.yml
    fi
    
    echo -e "${green}节点 $node_id 已添加到配置文件${plain}"
    echo -e "${yellow}正在同步节点...${plain}"
    
    # 执行同步
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service sync-nodes restart
    else
        systemctl restart sync-nodes.service
    fi
    
    echo -e "${green}完成！${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 删除节点
remove_node() {
    local node_id=$1
    
    if [[ -z "$node_id" ]]; then
        echo -e "${red}错误: 请指定节点ID${plain}"
        echo "用法: xnode remove-node <节点ID>"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    
    echo -e "${yellow}删除节点 $node_id...${plain}"
    
    # 停止服务
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service xboard-node@$node_id stop 2>/dev/null
    else
        systemctl stop xboard-node@$node_id 2>/dev/null
    fi
    
    # 禁用服务
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del xboard-node@$node_id 2>/dev/null
        rm -f /etc/init.d/xboard-node@$node_id
    else
        systemctl disable xboard-node@$node_id 2>/dev/null
    fi
    
    # 删除配置文件
    rm -f /etc/xboard-node/${node_id}.yml
    
    # 从 sync.yml 中移除节点ID
    if [[ -f /etc/xboard-node/sync.yml ]]; then
        sed -i "/^\s*-\s*${node_id}$/d" /etc/xboard-node/sync.yml
    fi
    
    echo -e "${green}节点 $node_id 已完全删除${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}


# 获取所有节点ID
get_node_ids() {
    if [[ -d /etc/xboard-node ]]; then
        for f in /etc/xboard-node/*.yml; do
            if [[ -f "$f" ]]; then
                basename "$f" .yml
            fi
        done | grep -E '^[0-9]+$' | sort -n
    fi
}

# 检查节点状态
check_node_status() {
    local node_id=$1
    if [[ x"${release}" == x"alpine" ]]; then
        if rc-service xboard-node@$node_id status 2>/dev/null | grep -q "started"; then
            return 0
        else
            return 1
        fi
    else
        local status=$(systemctl is-active xboard-node@$node_id 2>/dev/null)
        if [[ "$status" == "active" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

start_all() {
    echo -e "${green}启动所有节点...${plain}"
    
    local nodes=$(get_node_ids)
    if [[ -z "$nodes" ]]; then
        echo -e "${yellow}没有找到节点配置${plain}"
        echo -e "${yellow}请先运行同步: xnode sync${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return
    fi
    
    for node_id in $nodes; do
        if [[ x"${release}" == x"alpine" ]]; then
            rc-service xboard-node@$node_id start
        else
            systemctl start xboard-node@$node_id
        fi
        echo -e "  节点 ${node_id}: ${green}已启动${plain}"
    done
    
    echo -e "${green}所有节点已启动${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop_all() {
    echo -e "${yellow}停止所有节点...${plain}"
    
    local nodes=$(get_node_ids)
    if [[ -z "$nodes" ]]; then
        echo -e "${yellow}没有找到运行中的节点${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return
    fi
    
    for node_id in $nodes; do
        if [[ x"${release}" == x"alpine" ]]; then
            rc-service xboard-node@$node_id stop
        else
            systemctl stop xboard-node@$node_id
        fi
        echo -e "  节点 ${node_id}: ${red}已停止${plain}"
    done
    
    echo -e "${green}所有节点已停止${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_all() {
    echo -e "${yellow}重启所有节点...${plain}"
    
    local nodes=$(get_node_ids)
    if [[ -z "$nodes" ]]; then
        echo -e "${yellow}没有找到节点配置${plain}"
        echo -e "${yellow}请先运行同步: xnode sync${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return
    fi
    
    for node_id in $nodes; do
        if [[ x"${release}" == x"alpine" ]]; then
            rc-service xboard-node@$node_id restart
        else
            systemctl restart xboard-node@$node_id
        fi
        echo -e "  节点 ${node_id}: ${green}已重启${plain}"
    done
    
    echo -e "${green}所有节点已重启${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

sync() {
    echo -e "${green}开始同步节点...${plain}"
    
    if [[ ! -f /usr/local/bin/sync-nodes ]]; then
        echo -e "${red}sync-nodes 未安装，请先安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    
    /usr/local/bin/sync-nodes
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    echo -e "${green}====== 节点状态 ======${plain}"
    echo ""
    
    # 检查同步服务状态
    echo -e "${yellow}同步服务:${plain}"
    if [[ x"${release}" == x"alpine" ]]; then
        if rc-service sync-nodes status 2>/dev/null | grep -q "started"; then
            echo -e "  状态: ${green}运行中${plain}"
        else
            echo -e "  状态: ${red}未运行${plain}"
        fi
    else
        local sync_status=$(systemctl is-active sync-nodes.timer 2>/dev/null)
        if [[ "$sync_status" == "active" ]]; then
            echo -e "  定时器: ${green}运行中${plain}"
        else
            echo -e "  定时器: ${red}未运行${plain}"
        fi
    fi
    
    echo ""
    
    # 检查自动更新服务状态
    echo -e "${yellow}自动更新:${plain}"
    if [[ x"${release}" == x"alpine" ]]; then
        if rc-service update-xboard-node status 2>/dev/null | grep -q "started"; then
            echo -e "  状态: ${green}运行中${plain}"
        else
            echo -e "  状态: ${red}未运行${plain}"
        fi
    else
        local update_status=$(systemctl is-active update-xboard-node.timer 2>/dev/null)
        if [[ "$update_status" == "active" ]]; then
            echo -e "  定时器: ${green}运行中${plain}"
        else
            echo -e "  定时器: ${red}未运行${plain}"
        fi
    fi
    
    echo ""
    
    # 检查所有节点状态
    echo -e "${yellow}节点列表:${plain}"
    local nodes=$(get_node_ids)
    if [[ -z "$nodes" ]]; then
        echo -e "  ${red}没有找到节点${plain}"
    else
        for node_id in $nodes; do
            if check_node_status $node_id; then
                echo -e "  节点 ${node_id}: ${green}运行中${plain}"
            else
                echo -e "  节点 ${node_id}: ${red}已停止${plain}"
            fi
        done
    fi
    
    echo ""
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

sync_log() {
    echo -e "${green}同步日志 (按 Ctrl+C 退出):${plain}"
    echo ""
    
    if [[ x"${release}" == x"alpine" ]]; then
        cat /var/log/sync-nodes.log 2>/dev/null || echo -e "${red}日志文件不存在${plain}"
    else
        journalctl -u sync-nodes.service -f --no-pager
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_log() {
    echo -e "${green}更新日志:${plain}"
    echo ""
    
    if [[ -f /var/log/xboard-node-update.log ]]; then
        tail -100 /var/log/xboard-node-update.log
    else
        echo -e "${red}日志文件不存在${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable_autostart() {
    echo -e "${green}设置开机自启...${plain}"
    
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add sync-nodes default
        rc-update add update-xboard-node default
    else
        systemctl enable sync-nodes.timer
        systemctl enable update-xboard-node.timer
        systemctl start sync-nodes.timer
        systemctl start update-xboard-node.timer
    fi
    
    echo -e "${green}已设置开机自启${plain}"
    echo -e "${green}已启动定时服务${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable_autostart() {
    echo -e "${yellow}取消开机自启...${plain}"
    
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del sync-nodes default
        rc-update del update-xboard-node default
    else
        systemctl disable sync-nodes.timer
        systemctl disable update-xboard-node.timer
        systemctl stop sync-nodes.timer
        systemctl stop update-xboard-node.timer
    fi
    
    echo -e "${green}已取消开机自启${plain}"
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

version() {
    echo -e "${green}版本信息:${plain}"
    echo ""
    
    if [[ -f /usr/local/bin/xboard-node ]]; then
        echo -e "  xboard-node: $($(/usr/local/bin/xboard-node -v 2>/dev/null || echo "未知"))"
    else
        echo -e "  xboard-node: ${red}未安装${plain}"
    fi
    
    if [[ -f /usr/local/bin/sync-nodes ]]; then
        SYNC_VERSION=$(/usr/local/bin/sync-nodes -v 2>/dev/null || echo "未知")
        echo -e "  sync-nodes: ${green}${SYNC_VERSION}${plain}"
    else
        echo -e "  sync-nodes: ${red}未安装${plain}"
    fi
    
    if [[ -f /usr/local/bin/update-xboard-node.sh ]]; then
        echo -e "  update-script: ${green}已安装${plain}"
    else
        echo -e "  update-script: ${red}未安装${plain}"
    fi
    
    echo ""
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_usage() {
    echo "xnode 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "xnode              - 显示管理菜单"
    echo "xnode status       - 查看所有节点状态"
    echo "xnode start        - 启动所有节点"
    echo "xnode stop         - 停止所有节点"
    echo "xnode restart      - 重启所有节点"
    echo "xnode sync         - 手动同步节点"
    echo "xnode update       - 更新 xboard-node"
    echo "xnode update-script- 更新管理脚本"
    echo "xnode update-sync  - 更新 sync-nodes"
    echo "xnode list-nodes   - 列出所有节点"
    echo "xnode add-node <ID>- 手动添加节点"
    echo "xnode remove-node <ID> - 手动删除节点"
    echo "xnode config       - 修改配置文件"
    echo "xnode log          - 查看同步日志"
    echo "xnode updatelog    - 查看更新日志"
    echo "xnode enable       - 设置开机自启"
    echo "xnode disable      - 取消开机自启"
    echo "xnode version      - 查看版本信息"
    echo "xnode install      - 安装/重新安装"
    echo "xnode uninstall    - 卸载"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}xnodeauto 管理脚本${plain}
--- https://github.com/ipevel/xnodeauto ---
  ${green}0.${plain} 修改配置文件
————————————————
  ${green}1.${plain} 查看所有节点状态
  ${green}2.${plain} 启动所有节点
  ${green}3.${plain} 停止所有节点
  ${green}4.${plain} 重启所有节点
  ${green}5.${plain} 手动同步节点
————————————————
  ${green}6.${plain} 更新 xboard-node
  ${green}7.${plain} 更新管理脚本
  ${green}8.${plain} 更新 sync-nodes
————————————————
  ${green}9.${plain} 列出所有节点
  ${green}10.${plain} 手动添加节点
  ${green}11.${plain} 手动删除节点
————————————————
  ${green}12.${plain} 查看同步日志
  ${green}13.${plain} 查看更新日志
————————————————
  ${green}14.${plain} 设置开机自启
  ${green}15.${plain} 取消开机自启
————————————————
  ${green}16.${plain} 查看版本信息
  ${green}17.${plain} 安装/重新安装
  ${green}18.${plain} 卸载
  ${green}19.${plain} 退出脚本
"
    
    # 显示状态
    echo -e "${yellow}当前状态:${plain}"
    
    # 检查同步服务
    if [[ x"${release}" == x"alpine" ]]; then
        if rc-service sync-nodes status 2>/dev/null | grep -q "started"; then
            echo -e "  同步服务: ${green}运行中${plain}"
        else
            echo -e "  同步服务: ${red}未运行${plain}"
        fi
    else
        local sync_status=$(systemctl is-active sync-nodes.timer 2>/dev/null)
        if [[ "$sync_status" == "active" ]]; then
            echo -e "  同步服务: ${green}运行中${plain}"
        else
            echo -e "  同步服务: ${red}未运行${plain}"
        fi
    fi
    
    # 统计节点数量
    local running=0
    local stopped=0
    for node_id in $(get_node_ids); do
        if check_node_status $node_id; then
            ((running++))
        else
            ((stopped++))
        fi
    done
    
    echo -e "  节点: ${green}${running} 运行中${plain}, ${red}${stopped} 已停止${plain}"
    echo ""
    
    echo -n -e "${yellow}请输入选择 [0-19]: ${plain}"
    read num

    case "${num}" in
        0) config ;;
        1) status ;;
        2) start_all ;;
        3) stop_all ;;
        4) restart_all ;;
        5) sync ;;
        6) update ;;
        7) update_script ;;
        8) update_sync_nodes ;;
        9) list_nodes ;;
        10) add_node ;;
        11) remove_node ;;
        12) sync_log ;;
        13) update_log ;;
        14) enable_autostart ;;
        15) disable_autostart ;;
        16) version ;;
        17) install ;;
        18) uninstall ;;
        19) exit 0 ;;
        *) echo -e "${red}请输入正确的数字 [0-19]${plain}" && show_menu ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
        "start") start_all 0 ;;
        "stop") stop_all 0 ;;
        "restart") restart_all 0 ;;
        "status") status 0 ;;
        "sync") sync 0 ;;
        "update") update 0 ;;
        "update-script") update_script 0 ;;
        "update-sync") update_sync_nodes 0 ;;
        "list-nodes") list_nodes 0 ;;
        "add-node") add_node $2 ;;
        "remove-node") remove_node $2 ;;
        "config") config 0 ;;
        "log") sync_log 0 ;;
        "updatelog") update_log 0 ;;
        "enable") enable_autostart 0 ;;
        "disable") disable_autostart 0 ;;
        "version") version 0 ;;
        "install") install 0 ;;
        "uninstall") uninstall 0 ;;
        *) show_usage ;;
    esac
else
    show_menu
fi
