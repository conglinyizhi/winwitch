#!/usr/bin/env bash
# 清掉废弃的快捷键条目。
#
# 背景：早先给 26 个字母各注册了一个 `Meta+F, X` 序列，还注册了 `Meta+F, Escape`。
# 后来发现两件事，它们全都没必要：
#   1. KGlobalAccel 不派发两段式序列的第二段，这些注册从来没生效过；
#   2. 它们会让 Plasma 报「Meta+F 遮蔽了以下全局操作」的告警。
# 现在只保留「进入选择模式」与无按键的「提交选择」。
#
# KDE 不会因为脚本不再注册就删掉动作，条目会一直留在 kglobalshortcutsrc 里，
# 所以这里显式清理一次。
set -euo pipefail

rc="$HOME/.config/kglobalshortcutsrc"
[ -f "$rc" ] || { echo "没有 $rc，跳过"; exit 0; }

removed=0
for letter in A S D F G H J K L Q W E R T Y U I O P Z X C V B N M; do
    if grep -q "^字母切窗 ${letter}=" "$rc"; then
        kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "字母切窗 ${letter}" --delete
        removed=$((removed + 1))
    fi
done
if grep -q '^字母切窗 取消=' "$rc"; then
    kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "字母切窗 取消" --delete
    removed=$((removed + 1))
fi

echo "已删除 $removed 个废弃条目"
if [ "$removed" -gt 0 ]; then
    # 让 kglobalaccel 重新读取
    systemctl --user restart plasma-kglobalaccel.service 2>/dev/null || true
    sleep 1
fi
