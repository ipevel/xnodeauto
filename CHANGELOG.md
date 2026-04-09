# 更新日志

## v1.2.2 (2026-04-08)

### ✨ 新功能
- **update_script() 全面升级**: 同时更新所有相关组件
  - ✅ 更新 xnode 管理脚本
  - ✅ 更新 update-xboard-node.sh 自动更新脚本
  - ✅ 更新 sync-nodes 同步程序
  - ✅ 自动检测系统架构（x86_64 / ARM64）
  - ✅ 备份和恢复机制
  - ✅ 完善的错误处理和提示

### 🐛 Bug 修复
- **修复路径不一致问题**: 统一所有脚本使用 `/usr/local/bin/` 路径
- **修复更新不完整问题**: 解决只更新 xnode.sh 导致其他组件版本不一致的问题

### 📦 影响范围
- 只影响管理脚本和相关组件
- 不影响配置文件
- 不影响运行中的节点

### 🔄 如何更新

**已安装的服务器**:

```bash
# 一键更新所有组件
wget -O /usr/local/bin/xnode https://raw.githubusercontent.com/ipevel/xnodeauto/main/xnode.sh && \
chmod +x /usr/local/bin/xnode && \
xnode
# 选择 [4] 更新 → [2] 更新管理脚本
```

**或直接执行**:

```bash
# 手动更新所有组件
xnode
# 选择 [4] 更新 → [2] 更新管理脚本
```

### ✅ 更新后的效果

执行 `[2] 更新管理脚本` 后，将会自动更新：

1. `/usr/local/bin/xnode` - 管理脚本
2. `/usr/local/bin/update-xboard-node.sh` - xboard-node 自动更新脚本
3. `/usr/local/bin/sync-nodes` - 节点同步程序

所有组件都会从 `ipevel/xnodeauto` 和 `ipevel/Xboard-Node` 下载，确保版本一致。

---

## v1.2.1 (2026-04-08)

### ✨ 新功能
- TUI 安装向导（美观的 ASCII 艺术 Banner）
- 美化输出格式（Unicode 图标、颜色、边框）
- 节点别名功能
- 长时间操作显示进度条
- 改进用户体验

### 🐛 Bug 修复
- 修复手动添加节点功能的两个 bug
  - Bug 1: 首次安装选择手动添加时，支持逗号分隔多个节点ID
  - Bug 2: add_node() 函数添加节点启动验证，处理空数组情况

---

## v1.2.0

### ✨ 新功能
- 手动节点管理命令
- 安全策略改进（≥2个节点时停止自动添加）

---

## v1.1.0

### ✨ 新功能
- sync-nodes 更新功能
- 安全编译参数
- Go 版本升级

---

## v1.0.0

### 🎉 初始版本
- 自动同步面板节点操作
- 支持多节点和中转机
- 每天自动更新 xboard-node
- 节点别名管理
