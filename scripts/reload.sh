#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# 重新装载与冒烟测试。
#
# 浮层是独立进程，改了它的 QML 只要重启这个进程就行，不必再重启 plasmashell
# （那一步会闪面板，只有改面板组件时才需要）。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

bin="$HOME/.local/bin/winwitch"
overlay_bin="$HOME/.local/bin/winwitch-overlay"
data_dir="$HOME/.local/share/winwitch"
kwin_id="io.github.conglinyizhi.winwitch.kwin"

say() { printf '\n=== %s ===\n' "$*"; }

say "1/6 编译 helper"
(
    cd "$repo"
    moon build cmd/main --target native --release
)
mkdir -p "$HOME/.local/bin"
install -m 755 "$repo/_build/native/release/build/cmd/main/main.exe" "$bin"

say "2/6 重装 KWin 脚本"
kpackagetool6 --type KWin/Script --remove "$kwin_id" >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/kwin/scripts/$kwin_id"
kpackagetool6 --type KWin/Script --install "$repo/kwin" >/dev/null
# reconfigure 不会重载已重装过的脚本，但也不能用 Scripting.unloadScript + loadScript：
# 那样会留下僵尸动作（旧动作仍在 kglobalaccel，新实例同名注册被拒，触发没反应）。
# 正确做法是开关一次插件，让 KWin 自己卸载旧实例、加载新实例。
kwriteconfig6 --file kwinrc --group Plugins --key io.github.conglinyizhi.winwitch.kwinEnabled false
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
sleep 1
kwriteconfig6 --file kwinrc --group Plugins --key io.github.conglinyizhi.winwitch.kwinEnabled true
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
sleep 2

# 清掉废弃的快捷键条目（26 个字母序列 + 取消）。它们从来没生效过，
# 还会让 Plasma 报「Meta+F 遮蔽了以下全局操作」。
bash "$repo/scripts/clean-shortcuts.sh" || true

say "2.5/6 确保面板顺序源就位"
kpackagetool6 --type Plasma/Applet --remove io.github.conglinyizhi.winwitch.panel >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/plasma/plasmoids/io.github.conglinyizhi.winwitch.panel"
kpackagetool6 --type Plasma/Applet --install "$repo/panel" >/dev/null
# 重装后 QML 变了，plasmashell 会继续跑内存里的旧版本，必须重启一次并清缓存。
rm -rf "$HOME/.cache/plasmashell/qmlcache"
systemctl --user restart plasma-plasmashell.service
sleep 6
timeout 15 qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    "$(cat "$repo/scripts/ensure-panel.js")" >/dev/null 2>&1 || true

say "3/6 更新浮层与翻译"
mkdir -p "$data_dir/overlay"
install -m 644 "$repo/overlay/main.qml" "$data_dir/overlay/main.qml"
# 浮层订阅 helper 状态用的等待脚本（QML 侧拿不到流式 D-Bus，只能靠它）
install -m 755 "$repo/scripts/watch-state.sh" "$data_dir/winwitch-watch"
# 界面文案的翻译。domain 必须与 Plasma 按组件 Id 推出来的那个一致，
# 否则文件在、名字不对，界面依然是英文（不会报错，只会静默不生效）。
locale_dir="$HOME/.local/share/locale"
translation_domain="plasma_applet_io.github.conglinyizhi.winwitch.panel"
if command -v msgfmt >/dev/null 2>&1; then
    mkdir -p "$locale_dir/zh_CN/LC_MESSAGES"
    msgfmt -o "$locale_dir/zh_CN/LC_MESSAGES/$translation_domain.mo" "$repo/po/zh_CN.po"
    echo "已安装中文翻译"
else
    echo "提示：未找到 msgfmt（gettext），跳过翻译安装，界面将显示英文"
fi
sed "s|@OVERLAY@|$data_dir/overlay/main.qml|" \
    "$repo/overlay/winwitch-overlay.sh" > "$overlay_bin"
chmod 755 "$overlay_bin"

say "4/6 重启 helper"
pkill -x winwitch 2>/dev/null || true
sleep 1
: > /tmp/winwitch.log
setsid nohup stdbuf -oL "$bin" >/tmp/winwitch.log 2>&1 </dev/null &
sleep 2
pgrep -x winwitch >/dev/null && echo "helper 已启动" || {
    echo "helper 启动失败，日志：" >&2
    cat /tmp/winwitch.log >&2
    exit 1
}

say "5/6 重启浮层"
# 实际进程是 `/usr/bin/qml .../winwitch/overlay/main.qml`，不包含包装脚本的名字，
# 按包装脚本名 pkill 会匹配不到，于是每次重载都多留一个实例（会多个浮层叠在一起）。
pkill -f 'winwitch/overlay/main.qml' 2>/dev/null || true
sleep 1
setsid nohup "$overlay_bin" >/dev/null 2>&1 </dev/null &
sleep 3
count=$(pgrep -x qml -a 2>/dev/null | grep -c 'winwitch/overlay' || true)
if [ "$count" -ge 1 ]; then
    echo "浮层已启动（实例数 $count）"
else
    echo "浮层未起来，日志（最后 15 行）：" >&2
    tail -15 "${XDG_STATE_HOME:-$HOME/.local/state}/winwitch/overlay.log" 2>/dev/null >&2 || true
fi

say "6/6 冒烟测试"
echo "初始状态：$(timeout 8 qdbus6 io.github.conglinyizhi.winwitch /winwitch io.github.conglinyizhi.winwitch.Status | head -1 | cut -c1-40)"
timeout 15 qdbus6 org.kde.kglobalaccel /component/kwin \
    org.kde.kglobalaccel.Component.invokeShortcut "WinWitch 进入选择模式" >/dev/null 2>&1
sleep 3
echo "触发后状态：$(timeout 8 qdbus6 io.github.conglinyizhi.winwitch /winwitch io.github.conglinyizhi.winwitch.Status | cut -c1-60)"
echo
echo "浮层上报："
grep '界面' /tmp/winwitch.log | tail -3 || echo "  （没有上报，浮层可能没起来）"
echo
echo "最终状态：$(timeout 8 qdbus6 io.github.conglinyizhi.winwitch /winwitch io.github.conglinyizhi.winwitch.Status | head -1 | cut -c1-40)"

echo
echo "明细行的四列是：字母、应用名、图标名、窗口标题。"
echo "第一个字母应与任务栏第一个图标一致（启动器图标会空掉一个字母位）。"
echo "若顺序不对，先看面板上的「顺序源」是否在跑（make status）。"
echo "注：刻意没有自动超时，退出只靠 Esc 或选中字母；上面保持 selecting 是正常的。"
