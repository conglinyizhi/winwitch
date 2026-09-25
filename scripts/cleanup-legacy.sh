#!/usr/bin/env bash
# 清掉改名前的遗留物（旧名 letterswitch / 字母切窗 / org.clyzhi.*）。
#
# 项目改名为「窗口导航器」后，旧名字装过的东西不会自动消失：
# 面板组件、KWin 脚本、自启动项、可执行文件、数据目录、快捷键条目都会留在原地。
# 重装前先清一遍，避免两套并存互相打架。
set -euo pipefail

say() { printf '  %s\n' "$*"; }
removed=0

# 1) 面板组件包（旧 ID）
for id in org.clyzhi.letterswitch.order org.clyzhi.letterswitch.labels org.clyzhi.letterswitch.probe; do
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$id"; then
        kpackagetool6 --type Plasma/Applet --remove "$id" >/dev/null 2>&1 || true
        say "已卸载面板组件 $id"
        removed=$((removed + 1))
    fi
    if [ -d "$HOME/.local/share/plasma/plasmoids/$id" ]; then
        rm -rf "$HOME/.local/share/plasma/plasmoids/$id"
        say "已删除 $id 目录"
        removed=$((removed + 1))
    fi
done

# 2) KWin 脚本（旧 id 与旧启用键）
if kpackagetool6 --type KWin/Script --list 2>/dev/null | grep -qx 'letterswitch'; then
    kpackagetool6 --type KWin/Script --remove letterswitch >/dev/null 2>&1 || true
    say "已卸载 KWin 脚本 letterswitch"
    removed=$((removed + 1))
fi
rm -rf "$HOME/.local/share/kwin/scripts/letterswitch"
kwriteconfig6 --file kwinrc --group Plugins --key letterswitchEnabled --delete 2>/dev/null || true

# 3) 自启动项
for f in letterswitch-helper.desktop letterswitch-overlay.desktop; do
    if [ -f "$HOME/.config/autostart/$f" ]; then
        rm -f "$HOME/.config/autostart/$f"
        say "已删除自启动项 $f"
        removed=$((removed + 1))
    fi
done

# 4) 可执行文件与数据目录
for f in "$HOME/.local/bin/letterswitch" "$HOME/.local/bin/letterswitch-overlay"; do
    if [ -f "$f" ]; then
        rm -f "$f"
        say "已删除 $f"
        removed=$((removed + 1))
    fi
done
if [ -d "$HOME/.local/share/letterswitch" ]; then
    rm -rf "$HOME/.local/share/letterswitch"
    say "已删除数据目录 ~/.local/share/letterswitch"
    removed=$((removed + 1))
fi

# 5) 旧名的快捷键条目（旧动作名是「字母切窗 …」）
rc="$HOME/.config/kglobalshortcutsrc"
if [ -f "$rc" ] && grep -q '^字母切窗 ' "$rc"; then
    while IFS= read -r key; do
        kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "$key" --delete 2>/dev/null || true
        say "已删除快捷键条目 $key"
        removed=$((removed + 1))
    done < <(grep -oP '^字母切窗 [^=]+' "$rc")
fi

if [ "$removed" -gt 0 ]; then
    say "共清理 $removed 项"
else
    say "没有发现旧名遗留物"
fi
