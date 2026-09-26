#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# 生成「这是哪一份构建」的标识，落成文本，供 make status 和排障时对号。
#
# 为什么需要：这轮反复出现「我验的版本」和「提督打开的那份」不是同一个——
# 改了没装、面板吃缓存、KWin 脚本没重载，都会造成两边说的不是一回事。
#
# 光有版本号不够：版本号相同但装的是不同一次构建，照样对不上。
# 所以再记一个「已安装产物内容哈希」，它才是一份构建的唯一身份。
# 报问题时带上这个哈希，就能确定看的是同一份东西。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

out="$HOME/.local/share/winwitch/build-info.txt"
mkdir -p "$(dirname "$out")"

version="$(git -C "$repo" describe --tags --always --dirty 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null || true)" ]; then
    version="$version (工作区有未提交改动)"
fi

# 已安装的产物：这些文件的内容一起决定「这是哪一份」
artifacts=(
    "$HOME/.local/bin/winwitch"
    "$HOME/.local/share/kwin/scripts/io.github.conglinyizhi.winwitch.kwin/contents/code/main.js"
    "$HOME/.local/share/winwitch/overlay/main.qml"
    "$HOME/.local/share/plasma/plasmoids/io.github.conglinyizhi.winwitch.panel/contents/ui/main.qml"
    "$HOME/.local/share/plasma/plasmoids/io.github.conglinyizhi.winwitch.panel/contents/ui/configGeneral.qml"
    "$HOME/.local/share/plasma/plasmoids/io.github.conglinyizhi.winwitch.panel/contents/config/main.xml"
)

hash=""
build_time=""
for f in "${artifacts[@]}"; do
    [ -f "$f" ] || continue
    hash="$hash$(sha256sum "$f" | cut -c1-64)"
    mtime="$(date -r "$f" '+%Y-%m-%d %H:%M:%S')"
    if [ -z "$build_time" ] || [[ "$mtime" > "$build_time" ]]; then
        build_time="$mtime"
    fi
done
content_hash="$(printf '%s' "$hash" | sha256sum | cut -c1-8)"

cat > "$out" <<EOF
版本      $version
构建时间  ${build_time:-未知}
安装时间  $(date '+%Y-%m-%d %H:%M:%S')
内容哈希  ${content_hash:-未知}
EOF

cat "$out"
