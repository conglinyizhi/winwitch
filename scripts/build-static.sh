#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# 静态构建 helper。moon 没有 static 开关，但原生后端最后一步是普通 C 链接，
# 所以用包装脚本接管 cc：它只接受「可执行文件路径」，并且会从该文件所在
# 目录推导归档器 ar，因此两个都要准备好。
#
# 产物：_build/native/release/build/cmd/main/main.exe（statically linked）
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ccdir="$(mktemp -d)"
trap 'rm -rf "$ccdir"' EXIT

printf '#!/bin/sh\nexec cc -static "$@"\n' > "$ccdir/cc"
chmod +x "$ccdir/cc"
ln -sf "$(command -v ar)" "$ccdir/ar"

cd "$root"
MOON_CC="$ccdir/cc" moon build --release

bin="_build/native/release/build/cmd/main/main.exe"
file "$bin" | grep -q 'statically linked' || {
    echo "构建产物不是静态链接，静态构建失败" >&2
    exit 1
}
echo "静态构建完成: $bin ($(stat -c%s "$bin") 字节)"
