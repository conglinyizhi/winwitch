#!/usr/bin/env bash
# 卸载WinWitch。只删本项目安装的东西，不动其它 Plasma / KWin 配置。
set -euo pipefail

say() { printf '%s\n' "$*"; }

say "== 停用 KWin 脚本 =="
kwriteconfig6 --file kwinrc --group Plugins --key io.github.conglinyizhi.winwitch.kwinEnabled false
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

say "== 卸载 KWin 脚本 =="
kpackagetool6 --type KWin/Script --remove io.github.conglinyizhi.winwitch.kwin 2>/dev/null || kpackagetool6 --type KWin/Script --remove winwitch 2>/dev/null || say "（未安装，跳过）"

say "== 卸载任务栏组件 =="
kpackagetool6 --type Plasma/Applet --remove io.github.conglinyizhi.winwitch.strip 2>/dev/null || say "（未安装，跳过）"

say "== 删除 helper 与自启动项 =="
rm -f "$HOME/.local/bin/winwitch"
rm -f "$HOME/.config/autostart/winwitch-helper.desktop"

say ""
say "已卸载。仍在运行的 helper 进程需要手动结束：pkill -f winwitch"
say "注意：KWin 脚本注册过的快捷键条目可能残留在系统设置里，重新登录后消失。"
