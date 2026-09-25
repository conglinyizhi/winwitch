#!/usr/bin/env bash
# 安装字母切窗：helper（D-Bus 会话服务）+ KWin 脚本 + 浮层进程。只写用户目录。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

bin_dir="$HOME/.local/bin"
data_dir="$HOME/.local/share/letterswitch"
autostart_dir="$HOME/.config/autostart"

say() { printf '\n=== %s ===\n' "$*"; }

require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        say "缺少依赖：$1 —— 请先安装后再运行本脚本。"
        exit 1
    fi
}

require kpackagetool6
require moon
require stdbuf
require qdbus6

say "1/5 编译 MoonBit helper"
(
    cd "$repo"
    moon build cmd/main --target native --release
)
mkdir -p "$bin_dir"
install -m 755 "$repo/_build/native/release/build/cmd/main/main.exe" "$bin_dir/letterswitch"
echo "已安装 $bin_dir/letterswitch"

say "2/5 安装 helper 自启动"
mkdir -p "$autostart_dir"
sed "s|@HELPER@|$bin_dir/letterswitch|" \
    "$repo/data/letterswitch-helper.desktop" \
    > "$autostart_dir/letterswitch-helper.desktop"
chmod 644 "$autostart_dir/letterswitch-helper.desktop"
echo "已安装 $autostart_dir/letterswitch-helper.desktop"

say "3/5 安装 KWin 脚本"
# 先移除再安装：旧的坏 metadata 会让 --upgrade 自己认不出包。
kpackagetool6 --type KWin/Script --remove letterswitch >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/kwin/scripts/letterswitch"
kpackagetool6 --type KWin/Script --install "$repo/kwin" >/dev/null
kwriteconfig6 --file kwinrc --group Plugins --key letterswitchEnabled true
# 重载插件管理的脚本：开关一次插件，让 KWin 卸载旧实例并加载新实例。
# 不要用 Scripting.unloadScript + loadScript，那会留下僵尸动作。
kwriteconfig6 --file kwinrc --group Plugins --key letterswitchEnabled false
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
sleep 1
kwriteconfig6 --file kwinrc --group Plugins --key letterswitchEnabled true
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 \
    || echo "提示：KWin 重载失败，注销后重新登录即可生效。"
sleep 1

say "4/5 安装浮层"
mkdir -p "$data_dir/overlay"
install -m 644 "$repo/overlay/main.qml" "$data_dir/overlay/main.qml"
sed "s|@OVERLAY@|$data_dir/overlay/main.qml|" \
    "$repo/overlay/letterswitch-overlay.sh" > "$bin_dir/letterswitch-overlay"
chmod 755 "$bin_dir/letterswitch-overlay"
sed "s|@WRAPPER@|$bin_dir/letterswitch-overlay|" \
    "$repo/data/letterswitch-overlay.desktop" \
    > "$autostart_dir/letterswitch-overlay.desktop"
chmod 644 "$autostart_dir/letterswitch-overlay.desktop"
echo "已安装浮层：$data_dir/overlay/main.qml"

# 清掉废弃的快捷键条目（26 个字母序列 + 取消）。它们从来没生效过，
# 还会让 Plasma 报「Meta+F 遮蔽了以下全局操作」。
bash "$repo/scripts/clean-shortcuts.sh" || true

say "5/5 安装面板顺序源"
kpackagetool6 --type Plasma/Applet --remove org.clyzhi.letterswitch.labels >/dev/null 2>&1 || true
kpackagetool6 --type Plasma/Applet --remove org.clyzhi.letterswitch.probe >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/plasma/plasmoids/org.clyzhi.letterswitch.labels"
rm -rf "$HOME/.local/share/plasma/plasmoids/org.clyzhi.letterswitch.probe"
kpackagetool6 --type Plasma/Applet --remove org.clyzhi.letterswitch.order >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/plasma/plasmoids/org.clyzhi.letterswitch.order"
kpackagetool6 --type Plasma/Applet --install "$repo/panel" >/dev/null
# 顺序源必须在面板上才能读任务模型；它本身不绘制任何内容。
# 重装后 QML 变了，plasmashell 会继续跑内存里的旧版本，所以清缓存并重启一次。
rm -rf "$HOME/.cache/plasmashell/qmlcache"
systemctl --user restart plasma-plasmashell.service
sleep 6
if timeout 15 qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "$(cat "$repo/scripts/ensure-panel.js")" >/dev/null 2>&1; then
    echo "已处理面板顺序源"
else
    echo "提示：plasmashell 不可达，顺序源未加入面板，字母将按 KWin 顺序分配"
fi

say "安装完成"
echo "启动（或改用 scripts/reload.sh 一步到位）："
echo "  nohup stdbuf -oL $bin_dir/letterswitch >/tmp/letterswitch.log 2>&1 &"
echo "  nohup $bin_dir/letterswitch-overlay >/dev/null 2>&1 &"
echo
echo "自检：qdbus6 org.clyzhi.LetterSwitch /LetterSwitch org.clyzhi.LetterSwitch.Order"
echo "      以及 qdbus6 ...Status（空闲时应输出 idle:t0）"
