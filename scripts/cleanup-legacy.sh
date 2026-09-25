#!/usr/bin/env bash
# 清掉历次改名留下的旧名遗留物。
#
# 项目改过两次名字：letterswitch（字母切窗）→ windownavigator（窗口导航器）→ winwitch（WinWitch）。
# 旧名字装过的东西不会自动消失：面板组件、KWin 脚本、自启动项、可执行文件、数据目录、
# 快捷键条目都会留在原地，不清就会新旧两套并存互相打架。
#
# 维护方式：以后再加改名，只往下面几张表里加一行即可。
set -euo pipefail

# ── 旧名清单 ───────────────────────────────────────────────
LEGACY_PLASMOID_IDS=(
    org.clyzhi.letterswitch.order
    org.clyzhi.letterswitch.labels
    org.clyzhi.letterswitch.probe
    io.github.conglinyizhi.windownavigator.panel
    io.github.conglinyizhi.windownavigator.strip
)
LEGACY_KWIN_IDS=(letterswitch windownavigator)
LEGACY_BIN_NAMES=(
    letterswitch
    letterswitch-overlay
    windownavigator
    windownavigator-overlay
)
LEGACY_AUTOSTART=(
    letterswitch-helper.desktop
    letterswitch-overlay.desktop
    windownavigator-helper.desktop
    windownavigator-overlay.desktop
)
LEGACY_DATA_DIRS=(letterswitch windownavigator)
LEGACY_SHORTCUT_PREFIXES=("字母切窗 " "窗口导航器 ")

# ── 执行 ───────────────────────────────────────────────────
say() { printf '  %s\n' "$*"; }
removed=0

for id in "${LEGACY_PLASMOID_IDS[@]}"; do
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$id"; then
        kpackagetool6 --type Plasma/Applet --remove "$id" >/dev/null 2>&1 || true
        say "已卸载面板组件 $id"
        removed=$((removed + 1))
    fi
    if [ -d "$HOME/.local/share/plasma/plasmoids/$id" ]; then
        rm -rf "$HOME/.local/share/plasma/plasmoids/$id"
        say "已删除面板组件目录 $id"
        removed=$((removed + 1))
    fi
done

for id in "${LEGACY_KWIN_IDS[@]}"; do
    if kpackagetool6 --type KWin/Script --list 2>/dev/null | grep -qx "$id"; then
        kpackagetool6 --type KWin/Script --remove "$id" >/dev/null 2>&1 || true
        say "已卸载 KWin 脚本 $id"
        removed=$((removed + 1))
    fi
    rm -rf "$HOME/.local/share/kwin/scripts/$id"
    # 旧启用键：kwinrc 的 [Plugins] 段
    kwriteconfig6 --file kwinrc --group Plugins --key "${id}Enabled" --delete 2>/dev/null || true
done

for name in "${LEGACY_AUTOSTART[@]}"; do
    if [ -f "$HOME/.config/autostart/$name" ]; then
        rm -f "$HOME/.config/autostart/$name"
        say "已删除自启动项 $name"
        removed=$((removed + 1))
    fi
done

for name in "${LEGACY_BIN_NAMES[@]}"; do
    if [ -f "$HOME/.local/bin/$name" ]; then
        rm -f "$HOME/.local/bin/$name"
        say "已删除可执行文件 ~/.local/bin/$name"
        removed=$((removed + 1))
    fi
done

for name in "${LEGACY_DATA_DIRS[@]}"; do
    if [ -d "$HOME/.local/share/$name" ]; then
        rm -rf "$HOME/.local/share/$name"
        say "已删除数据目录 ~/.local/share/$name"
        removed=$((removed + 1))
    fi
done

# 旧动作名的快捷键条目（如「字母切窗 进入选择模式」「窗口导航器 提交选择」）
rc="$HOME/.config/kglobalshortcutsrc"
if [ -f "$rc" ]; then
    for prefix in "${LEGACY_SHORTCUT_PREFIXES[@]}"; do
        while IFS= read -r key; do
            [ -n "$key" ] || continue
            kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "$key" --delete 2>/dev/null || true
            say "已删除快捷键条目 $key"
            removed=$((removed + 1))
        done < <(grep -oP "^${prefix}[^=]+" "$rc" 2>/dev/null || true)
    done
fi

if [ "$removed" -gt 0 ]; then
    say "共清理 $removed 项"
else
    say "没有发现旧名遗留物"
fi

# ── 面板配置里的旧 ID 条目 ─────────────────────────────────
#
# 改名后配置里会留下「加载失败的占位」条目，拿不到 Applet 对象因而没法用脚本 API 删除，
# 只能在 plasmashell 停止时直接改配置文件（它退出时会回写配置，运行中改会被覆盖）。
rc="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
stale=$(python3 "$(dirname "${BASH_SOURCE[0]}")/clean-panel-config.py" "$rc" --check "${LEGACY_PLASMOID_IDS[@]}" 2>/dev/null || echo 0)
if [ "${stale:-0}" -gt 0 ]; then
    say "面板配置里有 $stale 个旧 ID 条目，停掉 plasmashell 清理"
    systemctl --user stop plasma-plasmashell.service 2>/dev/null || true
    sleep 2
    removed_now=$(python3 "$(dirname "${BASH_SOURCE[0]}")/clean-panel-config.py" "$rc" --apply "${LEGACY_PLASMOID_IDS[@]}" 2>/dev/null || echo 0)
    systemctl --user start plasma-plasmashell.service 2>/dev/null || true
    say "已清理 $removed_now 个旧条目，plasmashell 已重启"
    removed=$((removed + removed_now))
fi
