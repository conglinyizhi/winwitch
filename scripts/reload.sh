#!/usr/bin/env bash
# 重新装载与冒烟测试。
#
# 存在的理由：改完组件 QML 之后，重装包、清 QML 缓存、甚至删掉面板组件再重新添加，
# 都不足以让 plasmashell 用上新文件——它会继续跑内存里的旧代码。
# 可靠做法只有重启 plasmashell。把这一串固定动作收在这里，别每次手敲。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

bin="$HOME/.local/bin/letterswitch"
plasmoid_id="org.clyzhi.letterswitch.labels"
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
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

say "3/6 重装面板组件"
kpackagetool6 --type Plasma/Applet --remove "$plasmoid_id" >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/plasma/plasmoids/$plasmoid_id"
kpackagetool6 --type Plasma/Applet --install "$repo/package" >/dev/null

say "4/6 清 QML 缓存并重启 plasmashell"
rm -rf "$HOME/.cache/plasmashell/qmlcache"
systemctl --user restart plasma-plasmashell.service
sleep 6

say "5/6 重启 helper"
pkill -x letterswitch 2>/dev/null || true
sleep 1
setsid nohup stdbuf -oL "$bin" >/tmp/letterswitch.log 2>&1 </dev/null &
sleep 2
pgrep -x letterswitch >/dev/null && echo "helper 已启动" || {
    echo "helper 启动失败，日志：" >&2
    cat /tmp/letterswitch.log >&2
    exit 1
}

say "6/6 冒烟测试"
echo "初始状态：$(timeout 8 qdbus6 org.clyzhi.LetterSwitch /LetterSwitch org.clyzhi.LetterSwitch.Status | cut -c1-40)"
timeout 15 qdbus6 org.kde.kglobalaccel /component/kwin \
    org.kde.kglobalaccel.Component.invokeShortcut "字母切窗 进入选择模式" >/dev/null 2>&1
sleep 3
echo "触发后状态：$(timeout 8 qdbus6 org.clyzhi.LetterSwitch /LetterSwitch org.clyzhi.LetterSwitch.Status | cut -c1-60)"
echo
echo "组件上报："
grep '界面' /tmp/letterswitch.log | tail -3 || echo "  （没有上报，组件可能没加载）"
echo
echo "等待看门狗（8 秒）……"
sleep 11
echo "最终状态：$(timeout 8 qdbus6 org.clyzhi.LetterSwitch /LetterSwitch org.clyzhi.LetterSwitch.Status | cut -c1-40)"

echo
echo "完成。若状态回到 idle 且上面有 letters= 的上报，说明链路是通的。"
echo "改 QML 后重跑本脚本即可，不必手敲重启命令。"
