#!/usr/bin/env bash
# 安装WinWitch：helper（D-Bus 会话服务）+ KWin 脚本 + 浮层进程。只写用户目录。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

bin_dir="$HOME/.local/bin"
data_dir="$HOME/.local/share/winwitch"
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

# 先清掉改名前的遗留物，避免新旧两套并存
say "0/5 清理旧名遗留物"
bash "$repo/scripts/cleanup-legacy.sh"

say "1/5 编译 MoonBit helper"
(
    cd "$repo"
    moon build cmd/main --target native --release
)
mkdir -p "$bin_dir"
install -m 755 "$repo/_build/native/release/build/cmd/main/main.exe" "$bin_dir/winwitch"
echo "已安装 $bin_dir/winwitch"

say "2/5 安装 helper 自启动"
mkdir -p "$autostart_dir"
sed "s|@HELPER@|$bin_dir/winwitch|" \
    "$repo/data/winwitch-helper.desktop" \
    > "$autostart_dir/winwitch-helper.desktop"
chmod 644 "$autostart_dir/winwitch-helper.desktop"
echo "已安装 $autostart_dir/winwitch-helper.desktop"

say "3/5 安装 KWin 脚本"
# 先移除再安装：旧的坏 metadata 会让 --upgrade 自己认不出包。
kpackagetool6 --type KWin/Script --remove winwitch >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/kwin/scripts/winwitch"
kpackagetool6 --type KWin/Script --install "$repo/kwin" >/dev/null
kwriteconfig6 --file kwinrc --group Plugins --key winwitchEnabled true
# 重载插件管理的脚本：开关一次插件，让 KWin 卸载旧实例并加载新实例。
# 不要用 Scripting.unloadScript + loadScript，那会留下僵尸动作。
kwriteconfig6 --file kwinrc --group Plugins --key winwitchEnabled false
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
sleep 1
kwriteconfig6 --file kwinrc --group Plugins --key winwitchEnabled true
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 \
    || echo "提示：KWin 重载失败，注销后重新登录即可生效。"
sleep 1

say "4/5 安装浮层"
mkdir -p "$data_dir/overlay"
install -m 644 "$repo/overlay/main.qml" "$data_dir/overlay/main.qml"
sed "s|@OVERLAY@|$data_dir/overlay/main.qml|" \
    "$repo/overlay/winwitch-overlay.sh" > "$bin_dir/winwitch-overlay"
chmod 755 "$bin_dir/winwitch-overlay"
sed "s|@WRAPPER@|$bin_dir/winwitch-overlay|" \
    "$repo/data/winwitch-overlay.desktop" \
    > "$autostart_dir/winwitch-overlay.desktop"
chmod 644 "$autostart_dir/winwitch-overlay.desktop"
echo "已安装浮层：$data_dir/overlay/main.qml"

# 清掉废弃的快捷键条目（26 个字母序列 + 取消）。它们从来没生效过，
# 还会让 Plasma 报「Meta+F 遮蔽了以下全局操作」。
bash "$repo/scripts/clean-shortcuts.sh" || true

say "5/5 安装面板顺序源"
kpackagetool6 --type Plasma/Applet --remove io.github.conglinyizhi.winwitch.strip >/dev/null 2>&1 || true
kpackagetool6 --type Plasma/Applet --remove org.clyzhi.winwitch.probe >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/plasma/plasmoids/io.github.conglinyizhi.winwitch.strip"
rm -rf "$HOME/.local/share/plasma/plasmoids/org.clyzhi.winwitch.probe"
kpackagetool6 --type Plasma/Applet --remove io.github.conglinyizhi.winwitch.panel >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/plasma/plasmoids/io.github.conglinyizhi.winwitch.panel"
kpackagetool6 --type Plasma/Applet --install "$repo/panel" >/dev/null
# 顺序源必须在面板上才能读任务模型；它本身不绘制任何内容。
# 重装后 QML 变了，plasmashell 会继续跑内存里的旧版本，所以清缓存并重启一次。
rm -rf "$HOME/.cache/plasmashell/qmlcache"
# 清掉设置页已废弃的配置键。留着的话 KCM 加载「设置初始属性」会整体失败，
# 整页的值都读不出存不进（改过键名就得清，见脚本注释）。
# 必须在 plasmashell 停止时改：它退出时会回写配置。
systemctl --user stop plasma-plasmashell.service
python3 "$repo/scripts/prune-panel-keys.py" \
    "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" \
    "$repo/panel/contents/config/main.xml" --apply >/dev/null || true
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
echo "  nohup stdbuf -oL $bin_dir/winwitch >/tmp/winwitch.log 2>&1 &"
echo "  nohup $bin_dir/winwitch-overlay >/dev/null 2>&1 &"
echo
echo "自检：qdbus6 io.github.conglinyizhi.winwitch /winwitch io.github.conglinyizhi.winwitch.Order"
echo "      以及 qdbus6 ...Status（空闲时应输出 idle:t0）"
