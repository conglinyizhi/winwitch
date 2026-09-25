#!/usr/bin/env bash
# 重新装载与冒烟测试。
#
# 浮层是独立进程，改了它的 QML 只要重启这个进程就行，不必再重启 plasmashell
# （那一步会闪面板，只有改面板组件时才需要）。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

bin="$HOME/.local/bin/letterswitch"
overlay_bin="$HOME/.local/bin/letterswitch-overlay"
data_dir="$HOME/.local/share/letterswitch"
kwin_id="letterswitch"

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
kwriteconfig6 --file kwinrc --group Plugins --key letterswitchEnabled false
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
sleep 1
kwriteconfig6 --file kwinrc --group Plugins --key letterswitchEnabled true
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
sleep 2

say "2.5/6 确保面板上没有旧组件"
timeout 10 qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$repo/scripts/remove-panel-widget.js")" >/dev/null 2>&1 || true

say "3/6 更新浮层"
mkdir -p "$data_dir/overlay"
install -m 644 "$repo/overlay/main.qml" "$data_dir/overlay/main.qml"
sed "s|@OVERLAY@|$data_dir/overlay/main.qml|" \
    "$repo/overlay/letterswitch-overlay.sh" > "$overlay_bin"
chmod 755 "$overlay_bin"

say "4/6 重启 helper"
pkill -x letterswitch 2>/dev/null || true
sleep 1
: > /tmp/letterswitch.log
setsid nohup stdbuf -oL "$bin" >/tmp/letterswitch.log 2>&1 </dev/null &
sleep 2
pgrep -x letterswitch >/dev/null && echo "helper 已启动" || {
    echo "helper 启动失败，日志：" >&2
    cat /tmp/letterswitch.log >&2
    exit 1
}

say "5/6 重启浮层"
# 实际进程是 `/usr/bin/qml .../letterswitch/overlay/main.qml`，不包含包装脚本的名字，
# 按包装脚本名 pkill 会匹配不到，于是每次重载都多留一个实例（会多个浮层叠在一起）。
pkill -f 'letterswitch/overlay/main.qml' 2>/dev/null || true
sleep 1
setsid nohup "$overlay_bin" >/dev/null 2>&1 </dev/null &
sleep 3
count=$(pgrep -x qml -a 2>/dev/null | grep -c 'letterswitch/overlay' || true)
if [ "$count" -ge 1 ]; then
    echo "浮层已启动（实例数 $count）"
else
    echo "浮层未起来，日志（最后 15 行）：" >&2
    tail -15 "${XDG_STATE_HOME:-$HOME/.local/state}/letterswitch/overlay.log" 2>/dev/null >&2 || true
fi

say "6/6 冒烟测试"
echo "初始状态：$(timeout 8 qdbus6 org.clyzhi.LetterSwitch /LetterSwitch org.clyzhi.LetterSwitch.Status | cut -c1-40)"
timeout 15 qdbus6 org.kde.kglobalaccel /component/kwin \
    org.kde.kglobalaccel.Component.invokeShortcut "字母切窗 进入选择模式" >/dev/null 2>&1
sleep 3
echo "触发后状态：$(timeout 8 qdbus6 org.clyzhi.LetterSwitch /LetterSwitch org.clyzhi.LetterSwitch.Status | cut -c1-60)"
echo
echo "浮层上报："
grep '界面' /tmp/letterswitch.log | tail -3 || echo "  （没有上报，浮层可能没起来）"
echo
echo "等待看门狗（8 秒）……"
sleep 11
echo "最终状态：$(timeout 8 qdbus6 org.clyzhi.LetterSwitch /LetterSwitch org.clyzhi.LetterSwitch.Status | cut -c1-40)"

echo
echo "完成。有 overlay-selecting 上报且最后回到 idle，说明链路是通的。"
