#!/bin/bash

# ============================================================
# xnodeauto 无损升级脚本
# 用途：从老版本无损升级到最新版本
# 特点：保留所有配置文件和节点别名
# 注意：此脚本已整合到 xnode 菜单中，执行 xnode update 效果相同
# ============================================================

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "错误：必须使用 root 用户运行此脚本！"
    exit 1
fi

# 检查是否已安装
if [[ ! -f /etc/xboard-node/sync.yml ]]; then
    echo "错误：未检测到已安装的 xnodeauto"
    echo "请先运行安装脚本: bash <(curl -sL https://raw.githubusercontent.com/ipevel/xnodeauto/main/install.sh)"
    exit 1
fi

# 直接调用 xnode 命令执行更新（复用 update_all 函数）
exec /usr/local/bin/xnode update
