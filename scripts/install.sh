#!/usr/bin/env bash
# 安装字母切窗：helper + KWin 脚本 + 任务栏组件。只写用户目录。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

bin_dir="$HOME/.local/bin"
autostart_dir="$HOME/.config/autostart"

say() { printf '%s\n' "$*"; }

require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        say "缺少依赖：$1 —— 请先安装后再运行本脚本。"
        exit 1
    fi
}

require kpackagetool6
require moon
require stdbuf

say "== 1/4 编译 MoonBit helper =="
(
    cd "$repo"
    moon build cmd/main --target native --release
)
mkdir -p "$bin_dir"
install -m 755 "$repo/_build/native/release/build/cmd/main/main.exe" "$bin_dir/letterswitch"
say "已安装 $bin_dir/letterswitch"

say "== 2/4 安装 KWin 脚本 =="
# 先移除再安装：旧的坏 metadata（缺 KPackageStructure）会让 --upgrade 自己认不出包。
kpackagetool6 --type KWin/Script --remove letterswitch >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/kwin/scripts/letterswitch"
kpackagetool6 --type KWin/Script --install "$repo/kwin"

say "== 3/4 安装任务栏组件 =="
kpackagetool6 --type Plasma/Applet --remove org.clyzhi.letterswitch.labels >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/plasma/plasmoids/org.clyzhi.letterswitch.labels"
kpackagetool6 --type Plasma/Applet --install "$repo/package"

say "== 4/4 启用脚本与自启动 =="
kwriteconfig6 --file kwinrc --group Plugins --key letterswitchEnabled true
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || say "提示：KWin 重载失败，注销后重新登录即可生效。"

mkdir -p "$autostart_dir"
sed "s|@HELPER@|$bin_dir/letterswitch|" \
    "$repo/data/letterswitch-helper.desktop" \
    > "$autostart_dir/letterswitch-helper.desktop"
chmod 644 "$autostart_dir/letterswitch-helper.desktop"

say ""
say "安装完成。接下来需要手动确认三件事："
say "  1. 现在先手动启动一次 helper：nohup stdbuf -oL letterswitch >/tmp/letterswitch.log 2>&1 &"
say "  2. 系统设置 → 窗口管理 → KWin 脚本，确认「字母切窗」已勾选。"
say "  3. 面板上添加「字母切窗标签」组件（它会替代原任务栏）。"
say ""
say "自检：qdbus6 org.clyzhi.LetterSwitch /LetterSwitch org.clyzhi.LetterSwitch.Status"
say "      空闲时应输出 idle:t0"
