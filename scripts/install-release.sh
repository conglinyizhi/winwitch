#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 从发布包安装：不编译，不需要 MoonBit 工具链。
# 用法：解包后在本目录执行 ./install.sh
#
# 本脚本负责：helper、KWin 脚本、面板组件、浮层、自启动项。
# 剩下两步要动你的桌面配置，留给人工，脚本末尾会打印出来。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$HOME/.local/bin"
kwin_id="io.github.conglinyizhi.winwitch.kwin"
plasmoid_id="io.github.conglinyizhi.winwitch.panel"
data_dir="$HOME/.local/share/winwitch"
kwin_dir="$HOME/.local/share/kwin/scripts/$kwin_id"
plasmoid_dir="$HOME/.local/share/plasma/plasmoids/$plasmoid_id"
autostart_dir="$HOME/.config/autostart"

[ -f "$here/winwitch-helper" ] || {
    echo "找不到 winwitch-helper，请在解包后的目录里运行本脚本" >&2
    exit 1
}

echo "安装 helper 与浮层"
install -Dm755 "$here/winwitch-helper" "$bin_dir/winwitch"
install -Dm644 "$here/overlay/main.qml" "$data_dir/overlay/main.qml"
sed "s|@OVERLAY@|$data_dir/overlay/main.qml|" "$here/overlay/winwitch-overlay.sh" > "$bin_dir/winwitch-overlay"
chmod 755 "$bin_dir/winwitch-overlay"

echo "安装 KWin 脚本"
rm -rf "$kwin_dir"
mkdir -p "$(dirname "$kwin_dir")"
cp -r "$here/kwin" "$kwin_dir"
kwriteconfig6 --file kwinrc --group Plugins --key "${kwin_id}Enabled" true

echo "安装面板组件"
rm -rf "$plasmoid_dir"
mkdir -p "$(dirname "$plasmoid_dir")"
cp -r "$here/panel" "$plasmoid_dir"

echo "配置自启动"
mkdir -p "$autostart_dir"
sed "s|@HELPER@|$bin_dir/winwitch|" "$here/data/winwitch-helper.desktop" \
    > "$autostart_dir/winwitch-helper.desktop"
sed -e "s|@OVERLAY@|$data_dir/overlay/main.qml|" -e "s|@WRAPPER@|$bin_dir/winwitch-overlay|" \
    "$here/data/winwitch-overlay.desktop" > "$autostart_dir/winwitch-overlay.desktop"
chmod 644 "$autostart_dir"/winwitch-*.desktop

echo "让 KWin 重新加载脚本（开关一次插件，避免僵尸动作）"
kwriteconfig6 --file kwinrc --group Plugins --key "${kwin_id}Enabled" false
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
sleep 1
kwriteconfig6 --file kwinrc --group Plugins --key "${kwin_id}Enabled" true
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
sleep 2

echo "重启 plasmashell 让面板组件生效（面板会闪一下）"
# QML 改动后 plasmashell 会继续跑内存里的旧版本，必须清缓存再重启
rm -rf "$HOME/.cache/plasmashell/qmlcache"
systemctl --user restart plasma-plasmashell.service
sleep 6
if [ -f "$here/scripts/ensure-panel.js" ]; then
    timeout 15 qdbus6 org.kde.plasmashell /PlasmaShell \
        org.kde.PlasmaShell.evaluateScript "$(cat "$here/scripts/ensure-panel.js")" >/dev/null 2>&1 \
        && echo "已把面板组件加到任务栏" || echo "面板组件没能自动添加，请手动加（见下方第 1 步）"
fi

echo "重启 helper 与浮层"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/winwitch"
# 必须先建目录：全新用户没有它，而 set -e 会在重定向失败时中止整个脚本，
# helper 就永远起不来（本机测不出来，因为目录早就在了）
mkdir -p "$state_dir"
pkill -x winwitch 2>/dev/null || true
: > "$state_dir/helper.log"
setsid nohup stdbuf -oL "$bin_dir/winwitch" > "$state_dir/helper.log" 2>&1 </dev/null &
sleep 2
pgrep -x winwitch >/dev/null && echo "helper 已启动" || echo "helper 未启动，看上面的日志"

# 浮层的实际进程是 `/usr/lib/qt6/bin/qml …/overlay/main.qml`，不含包装脚本的名字，
# 按包装脚本名去杀会匹配不到，于是每装一次就多留一个实例（多个浮层叠着）。
# 而且必须在 KWin/plasmashell 重载之后才启动：先启动会被重载带走。
pkill -f 'winwitch/overlay/main.qml' 2>/dev/null || true
sleep 1
setsid nohup "$bin_dir/winwitch-overlay" >/dev/null 2>&1 </dev/null &
sleep 3
n_ovl=$(pgrep -x qml -a 2>/dev/null | grep -c 'winwitch/overlay' || true)
if [ "$n_ovl" -ge 1 ]; then
    echo "浮层已启动（实例数 $n_ovl，应为 1）"
else
    echo "浮层未起来，日志最后几行：" >&2
    tail -8 "$state_dir/overlay.log" 2>/dev/null >&2 || true
fi

cat <<'TIP'

装好了。还有两步要你手动做：

  1. 确认任务栏上有 WinWitch 面板组件（上面已尝试自动添加）
     没有的话：右键任务栏 → 编辑面板 → 添加组件 → 搜 WinWitch
     它提供任务栏顺序与应用图标；少了它，字母就对不上你的图标位置

  2. 快捷键默认是 Meta+F，想改在 系统设置 → 快捷键 里找 WinWitch

然后按 Meta+F 试试。
TIP
