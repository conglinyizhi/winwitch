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

echo "让 KWin 与 plasmashell 重新加载（面板会闪一下）"
bash "$here/scripts/reload.sh" >/dev/null 2>&1 || true

cat <<'TIP'

装好了。还有两步要你手动做：

  1. 把 WinWitch 面板组件加到任务栏
     右键任务栏 → 编辑面板 → 添加组件 → 搜 WinWitch
     它提供任务栏顺序与应用图标；少了它，字母就对不上你的图标位置

  2. 快捷键默认是 Meta+F，想改在 系统设置 → 快捷键 里找 WinWitch

然后按 Meta+F 试试。
TIP
