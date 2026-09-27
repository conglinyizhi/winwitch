#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# WinWitch浮层的启动包装。
#
# 直接让 autostart 跑 qml6 的话，输出会丢；这里统一记到日志文件，排障时有据可查。
# @OVERLAY@ 由 scripts/install.sh 在安装时替换为实际 QML 路径。
set -euo pipefail

qml_runtime=""
for candidate in /usr/lib/qt6/bin/qml /usr/bin/qml6 /usr/bin/qml; do
    if [ -x "$candidate" ]; then
        qml_runtime="$candidate"
        break
    fi
done

if [ -z "$qml_runtime" ]; then
    echo "winwitch-overlay: 找不到 Qt6 的 qml 运行时，浮层无法启动" >&2
    exit 1
fi

log="${XDG_STATE_HOME:-$HOME/.local/state}/winwitch/overlay.log"
mkdir -p "$(dirname "$log")"

# 图标主题靠这两个变量认。缺了的话 Qt 不知道自己在 KDE 会话里，
# 图标主题会退回 hicolor 这个兜底目录；而 Breeze 独有那些通用图标名
# （preferences-system、utilities-terminal、hwinfo 之类）就一个都取不到。
# 现象很有辨识度：只有一部分卡片没图标，而且没的那几张都是同一类名字。
# autostart 路径本来就带这两个变量，这里是给手动/脚本拉起的情况兜底。
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-KDE}"
export KDE_FULL_SESSION="${KDE_FULL_SESSION:-true}"

exec stdbuf -oL -eL "$qml_runtime" "@OVERLAY@" >> "$log" 2>&1
