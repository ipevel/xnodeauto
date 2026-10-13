#!/bin/bash
# ============================================================
# 多节点（manual_node_ids）回归测试
#
# 背景：v1.2.8 的 `xnode add-node` 在缺少 yq 时会走 awk 回退分支，
# 该分支会丢掉列表里已有的节点 ID；随后的同步任务把「不在列表里的节点」
# 全部停用并删除配置 —— 表现为「一台服务器上只剩一个节点」。
#
# 用法: bash tests/test_multi_node.sh
# 说明: 测试直接从 xnode.sh 里抽取真实函数执行，避免测试与实现脱节。
# ============================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XNODE="${XNODE_SH:-$(dirname "$SCRIPT_DIR")/xnode.sh}"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

ICON_OK="[OK]"
ICON_ERR="[ERR]"
ICON_WARN="[WARN]"
ICON_INFO="[INFO]"
ICON_ARROW="[->]"

if [[ ! -f "$XNODE" ]]; then
    echo "找不到 xnode.sh: $XNODE"
    exit 1
fi

# ---- 抽取被测函数（真实实现，非副本）----
extract_fn() {
    sed -n "/^$1() {/,/^}\$/p" "$XNODE"
}

WORK="$TMPDIR_TEST/work.sh"
{
    extract_fn get_manual_node_ids
    extract_fn manual_node_id_exists
    extract_fn append_manual_node_id
    extract_fn remove_manual_node_id
} > "$WORK"

for fn in get_manual_node_ids manual_node_id_exists append_manual_node_id remove_manual_node_id; do
    if ! grep -q "^${fn}() {" "$WORK"; then
        echo "无法从 $XNODE 抽取函数 $fn"
        exit 1
    fi
done
# shellcheck source=/dev/null
source "$WORK"

ok()   { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $1"; }

check_ids() {
    # check_ids <说明> <期望ID(空格分隔)> <sync.yml>
    local desc="$1" expect="$2" cfg="$3"
    local got
    got="$(get_manual_node_ids "$cfg" | tr '\n' ' ')"
    got="${got% }"
    if [[ "$got" == "$expect" ]]; then
        ok "$desc"
    else
        bad "$desc (期望: [$expect] 实际: [$got])"
        sed 's/^/         | /' "$cfg"
    fi
}

write_cfg() {
    cat > "$1"
}

base_head() {
    cat <<'EOF'
xboard_url: "https://panel.example.com"
admin_path: "admin"
admin_email: "a@b.com"
admin_password: "pw"
panel_token: "tk"
EOF
}

echo "============================================"
echo "多节点回归测试 (xnode.sh)"
echo "============================================"
echo ""

echo "[1] 读取 manual_node_ids（多种写法）"
{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo "  - 1"
    echo "  - 2"
    echo "  - 3"
} > "$TMPDIR_TEST/r1.yml"
check_ids "块列表" "1 2 3" "$TMPDIR_TEST/r1.yml"

{
    base_head
    echo "manual_node_ids: [4, 5]"
} > "$TMPDIR_TEST/r2.yml"
check_ids "行内列表 [4, 5]" "4 5" "$TMPDIR_TEST/r2.yml"

{
    base_head
    echo "manual_node_ids: []"
} > "$TMPDIR_TEST/r3.yml"
check_ids "空列表 []" "" "$TMPDIR_TEST/r3.yml"

{
    base_head
} > "$TMPDIR_TEST/r4.yml"
check_ids "没有该键（自动模式）" "" "$TMPDIR_TEST/r4.yml"

{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo "    - 7"
    echo "    - 8   # 尾注"
} > "$TMPDIR_TEST/r5.yml"
check_ids "自定义缩进 + 尾注" "7 8" "$TMPDIR_TEST/r5.yml"

echo ""
echo "[2] 追加节点：绝不能丢失已有 ID（v1.2.8 的回归点）"
{
    base_head
    echo ""
    echo "# 手动指定的节点ID"
    echo "manual_node_ids:"
    echo "  - 1"
} > "$TMPDIR_TEST/a1.yml"
append_manual_node_id 2 "$TMPDIR_TEST/a1.yml"
check_ids "已有 [1] → 添加 2" "1 2" "$TMPDIR_TEST/a1.yml"
append_manual_node_id 3 "$TMPDIR_TEST/a1.yml"
check_ids "已有 [1,2] → 添加 3" "1 2 3" "$TMPDIR_TEST/a1.yml"

{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo "  - 1"
    echo "  - 2"
    echo "  - 3"
} > "$TMPDIR_TEST/a2.yml"
append_manual_node_id 4 "$TMPDIR_TEST/a2.yml"
check_ids "3 个节点后添加第 4 个" "1 2 3 4" "$TMPDIR_TEST/a2.yml"

{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo "  - 1"
    echo "  - 2"
    echo ""
    echo "# 结尾注释"
    echo "other_key: keep-me"
} > "$TMPDIR_TEST/a3.yml"
append_manual_node_id 9 "$TMPDIR_TEST/a3.yml"
check_ids "列表后有空行/其它键" "1 2 9" "$TMPDIR_TEST/a3.yml"
if grep -q "^other_key: keep-me$" "$TMPDIR_TEST/a3.yml" && [[ "$(grep -c '^# 结尾注释$' "$TMPDIR_TEST/a3.yml")" == "1" ]]; then
    ok "后续内容与注释原样保留（未重复、未丢失）"
else
    bad "后续内容与注释被破坏"
    sed 's/^/         | /' "$TMPDIR_TEST/a3.yml"
fi

{
    base_head
    echo ""
    echo "manual_node_ids: []"
} > "$TMPDIR_TEST/a4.yml"
append_manual_node_id 5 "$TMPDIR_TEST/a4.yml"
check_ids "空列表 → 添加 5" "5" "$TMPDIR_TEST/a4.yml"
append_manual_node_id 6 "$TMPDIR_TEST/a4.yml"
check_ids "添加后再添加 6" "5 6" "$TMPDIR_TEST/a4.yml"

{
    base_head
    echo "manual_node_ids: [1, 2]"
} > "$TMPDIR_TEST/a5.yml"
append_manual_node_id 3 "$TMPDIR_TEST/a5.yml"
check_ids "行内列表 → 追加 3" "1 2 3" "$TMPDIR_TEST/a5.yml"

{
    base_head
    echo "manual_node_ids:"
} > "$TMPDIR_TEST/a6.yml"
append_manual_node_id 7 "$TMPDIR_TEST/a6.yml"
check_ids "只有键没有条目 → 添加 7" "7" "$TMPDIR_TEST/a6.yml"

{
    base_head
} > "$TMPDIR_TEST/a7.yml"
append_manual_node_id 8 "$TMPDIR_TEST/a7.yml"
check_ids "文件里没有该键 → 添加 8" "8" "$TMPDIR_TEST/a7.yml"

{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo "    - 11"
    echo "    - 12"
} > "$TMPDIR_TEST/a8.yml"
append_manual_node_id 13 "$TMPDIR_TEST/a8.yml"
check_ids "自定义缩进 → 添加 13" "11 12 13" "$TMPDIR_TEST/a8.yml"

echo ""
echo "[3] 幂等与安全校验"
cp "$TMPDIR_TEST/a1.yml" "$TMPDIR_TEST/b1.yml"
append_manual_node_id 2 "$TMPDIR_TEST/b1.yml"
if cmp -s "$TMPDIR_TEST/a1.yml" "$TMPDIR_TEST/b1.yml"; then
    ok "重复添加已存在的 ID：文件零变更"
else
    bad "重复添加已存在的 ID 时改动了文件"
fi

cp "$TMPDIR_TEST/a1.yml" "$TMPDIR_TEST/b2.yml"
append_manual_node_id "3; rm -rf /" "$TMPDIR_TEST/b2.yml" >/dev/null 2>&1
if [[ $? -ne 0 ]] && cmp -s "$TMPDIR_TEST/a1.yml" "$TMPDIR_TEST/b2.yml"; then
    ok "非法节点ID被拒绝：文件零变更"
else
    bad "非法节点ID未被正确拒绝"
fi

cp "$TMPDIR_TEST/a1.yml" "$TMPDIR_TEST/b3.yml"
append_manual_node_id "" "$TMPDIR_TEST/b3.yml" >/dev/null 2>&1
if cmp -s "$TMPDIR_TEST/a1.yml" "$TMPDIR_TEST/b3.yml"; then
    ok "空节点ID被拒绝：文件零变更"
else
    bad "空节点ID未被正确拒绝"
fi

if manual_node_id_exists 2 "$TMPDIR_TEST/a1.yml"; then
    ok "manual_node_id_exists 命中已存在 ID"
else
    bad "manual_node_id_exists 未命中已存在 ID"
fi
if manual_node_id_exists 99 "$TMPDIR_TEST/a1.yml"; then
    bad "manual_node_id_exists 误报不存在的 ID"
else
    ok "manual_node_id_exists 对不存在的 ID 返回否"
fi

echo ""
echo "[4] 权限与并发安全"
cp "$TMPDIR_TEST/a1.yml" "$TMPDIR_TEST/c1.yml"
if [[ "$(uname -s)" != "Linux" ]]; then
    echo "  [SKIP] 文件权限检查（仅 Linux 有效，当前: $(uname -s)）"
else
    chmod 600 "$TMPDIR_TEST/c1.yml"
    append_manual_node_id 4 "$TMPDIR_TEST/c1.yml"
    mode="$(stat -c '%a' "$TMPDIR_TEST/c1.yml" 2>/dev/null || echo unknown)"
    if [[ "$mode" == "600" ]]; then
        ok "写入后 sync.yml 权限保持 600"
    else
        bad "sync.yml 权限变成了 $mode（期望 600）"
    fi
fi
leftover=$(find "$(dirname "$TMPDIR_TEST/c1.yml")" -name 'c1.yml.*' | wc -l)
if [[ "$leftover" -eq 0 ]]; then
    ok "没有残留临时文件"
else
    bad "残留 $leftover 个临时文件"
fi

echo ""
echo "[5] 移除节点：只删目标 ID，其余节点必须保留"
{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo "  - 1"
    echo "  - 2"
    echo "  - 3"
} > "$TMPDIR_TEST/d1.yml"
remove_manual_node_id 2 "$TMPDIR_TEST/d1.yml"
check_ids "从 [1,2,3] 移除 2" "1 3" "$TMPDIR_TEST/d1.yml"

{
    base_head
    echo "manual_node_ids: [4, 5, 6]"
} > "$TMPDIR_TEST/d2.yml"
remove_manual_node_id 5 "$TMPDIR_TEST/d2.yml"
check_ids "从行内列表 [4,5,6] 移除 5" "4 6" "$TMPDIR_TEST/d2.yml"

# 文件其它位置出现同形的 "  - 2" 时不能被误删
{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo "  - 1"
    echo "  - 2"
    echo "other:"
    echo "  - 2"
} > "$TMPDIR_TEST/d3.yml"
remove_manual_node_id 2 "$TMPDIR_TEST/d3.yml"
check_ids "只删列表内的 2" "1" "$TMPDIR_TEST/d3.yml"
if grep -q '^  - 2$' "$TMPDIR_TEST/d3.yml"; then
    ok "其它键下的同形行未被误删"
else
    bad "其它键下的 '  - 2' 被误删"
fi

cp "$TMPDIR_TEST/d1.yml" "$TMPDIR_TEST/d4.yml"
remove_manual_node_id 99 "$TMPDIR_TEST/d4.yml"
if cmp -s "$TMPDIR_TEST/d1.yml" "$TMPDIR_TEST/d4.yml"; then
    ok "移除不存在的 ID：文件零变更"
else
    bad "移除不存在的 ID 时改动了文件"
fi

echo ""
echo "[6] 端到端：连续 add-node 后列表必须单调增长（v1.2.8 的真实故障场景）"
{
    base_head
    echo ""
    echo "# 手动指定的节点ID"
    echo "manual_node_ids:"
} > "$TMPDIR_TEST/e1.yml"
for id in 1 2 3 4 5; do
    append_manual_node_id "$id" "$TMPDIR_TEST/e1.yml"
done
check_ids "连续添加 1..5" "1 2 3 4 5" "$TMPDIR_TEST/e1.yml"
remove_manual_node_id 3 "$TMPDIR_TEST/e1.yml"
append_manual_node_id 6 "$TMPDIR_TEST/e1.yml"
check_ids "移除 3 后再添加 6" "1 2 4 5 6" "$TMPDIR_TEST/e1.yml"

echo ""
echo "[7] 列表内注释条目：其后 ID 不得丢失（v1.2.10 仍可复现的丢 ID 路径）"
{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo "  - 1"
    echo "  - # 备用线路"
    echo "  - 2"
    echo "  - 3"
} > "$TMPDIR_TEST/f1.yml"
check_ids "注释条目之后的 ID 仍能读出" "1 2 3" "$TMPDIR_TEST/f1.yml"
append_manual_node_id 9 "$TMPDIR_TEST/f1.yml"
check_ids "追加后注释之后的 ID 不丢" "1 2 3 9" "$TMPDIR_TEST/f1.yml"
# 新 ID 必须落在最后一个条目之后，而不是插到注释前面
if [[ "$(grep -nE '^[[:space:]]*-[[:space:]]*9' "$TMPDIR_TEST/f1.yml" | cut -d: -f1)" \
      -gt "$(grep -nE '^[[:space:]]*-[[:space:]]*3' "$TMPDIR_TEST/f1.yml" | cut -d: -f1)" ]]; then
    ok "新 ID 追加在最后条目之后（未插到注释前）"
else
    bad "新 ID 被插到了注释之前"
fi

{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo "  - 1"
    echo "  - # 说明"
    echo "  - 2"
    echo "  - 3"
} > "$TMPDIR_TEST/f2.yml"
remove_manual_node_id 2 "$TMPDIR_TEST/f2.yml"
check_ids "注释之后的目标条目能被移除" "1 3" "$TMPDIR_TEST/f2.yml"

{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo "  # 纯注释行"
    echo "  - 4"
    echo "  - 5"
} > "$TMPDIR_TEST/f3.yml"
append_manual_node_id 6 "$TMPDIR_TEST/f3.yml"
check_ids "纯注释行不影响读取与追加" "4 5 6" "$TMPDIR_TEST/f3.yml"

echo ""
echo "[8] CRLF 文件：读取与改写都不得丢 ID"
printf 'xboard_url: "https://example.com"\r\nmanual_node_ids:\r\n  - 11\r\n  - 22\r\n' > "$TMPDIR_TEST/g1.yml"
check_ids "CRLF 块列表读取" "11 22" "$TMPDIR_TEST/g1.yml"
append_manual_node_id 33 "$TMPDIR_TEST/g1.yml"
check_ids "CRLF 块列表追加" "11 22 33" "$TMPDIR_TEST/g1.yml"
remove_manual_node_id 11 "$TMPDIR_TEST/g1.yml"
check_ids "CRLF 块列表移除" "22 33" "$TMPDIR_TEST/g1.yml"

printf 'xboard_url: "https://example.com"\r\nmanual_node_ids: [101, 205]\r\n' > "$TMPDIR_TEST/g2.yml"
check_ids "CRLF 行内列表读取" "101 205" "$TMPDIR_TEST/g2.yml"
append_manual_node_id 308 "$TMPDIR_TEST/g2.yml"
check_ids "CRLF 行内列表追加后 205 必须保留" "101 205 308" "$TMPDIR_TEST/g2.yml"

echo ""
echo "[9] 引号 ID：读/追加/移除与 yaml.v3 语义一致"
{
    base_head
    echo ""
    echo "manual_node_ids:"
    echo '  - "5"'
    echo "  - 6"
} > "$TMPDIR_TEST/h1.yml"
check_ids "引号 ID 可读" "5 6" "$TMPDIR_TEST/h1.yml"
append_manual_node_id 7 "$TMPDIR_TEST/h1.yml"
check_ids "引号 ID 存在时追加不产生重复" "5 6 7" "$TMPDIR_TEST/h1.yml"
remove_manual_node_id 5 "$TMPDIR_TEST/h1.yml"
check_ids "引号 ID 可移除" "6 7" "$TMPDIR_TEST/h1.yml"

{
    base_head
    echo "manual_node_ids: [\"8\", 9]"
} > "$TMPDIR_TEST/h2.yml"
check_ids "行内列表中的引号 ID 可读" "8 9" "$TMPDIR_TEST/h2.yml"

echo ""
echo "[10] 键写法容错：前导空格键 / 无键 / 空列表 / 幂等"
{
    base_head
    echo "  manual_node_ids:"
    echo "  - 13"
} > "$TMPDIR_TEST/i1.yml"
append_manual_node_id 22 "$TMPDIR_TEST/i1.yml"
if [[ "$(grep -cE '^[[:space:]]*manual_node_ids:' "$TMPDIR_TEST/i1.yml")" -eq 1 ]]; then
    ok "前导空格键：未写出第二个同名键"
else
    bad "前导空格键写出了第二个同名键（YAML 将不可解析）"
fi
check_ids "前导空格键：读到的 ID 完整" "13 22" "$TMPDIR_TEST/i1.yml"

{
    base_head
} > "$TMPDIR_TEST/i2.yml"
append_manual_node_id 5 "$TMPDIR_TEST/i2.yml"
check_ids "无 manual_node_ids 键时追加" "5" "$TMPDIR_TEST/i2.yml"

{
    base_head
    echo "manual_node_ids: []"
} > "$TMPDIR_TEST/i3.yml"
append_manual_node_id 4 "$TMPDIR_TEST/i3.yml"
check_ids "空列表 [] 时追加" "4" "$TMPDIR_TEST/i3.yml"

{
    base_head
    echo "manual_node_ids:"
    echo "  - 1"
} > "$TMPDIR_TEST/i4.yml"
append_manual_node_id 1 "$TMPDIR_TEST/i4.yml"
check_ids "重复添加同一 ID 保持幂等" "1" "$TMPDIR_TEST/i4.yml"

echo ""
echo "============================================"
echo "通过: $PASS  失败: $FAIL"
echo "============================================"
[[ $FAIL -eq 0 ]] || exit 1