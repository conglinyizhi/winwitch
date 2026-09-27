#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# 等一条 StateChanged 信号，打印出来就退出。
#
# 为什么需要这么个脚本：
#
# 1. QML 侧调 D-Bus 只能起外部命令（Qt6 与 KDE 都没有 QML 的 D-Bus 客户端绑定）；
# 2. Plasma5Support 的 DataSource 是「命令结束后才把输出交给 onNewData」，
#    实测跑一个每秒输出一行的常驻命令，onNewData 只触发一次。
#    所以订阅必须做成「有信号就结束的短命令」。
#
# 而 `gdbus monitor` 收到信号后不会自己退出（它阻塞在等下一个）。
# 这里用一个 fifo 加显式 kill：读满需要的行数就退出，
# trap 随后把 monitor 收掉，整条命令立刻结束。
#
# 用法：winwitch-watch <bus-name> [行数]
#
#   行数默认 3：monitor 自己会先打两行抬头（"Monitoring signals …" 与
#   "The name … is owned by …"），第三行才是第一条信号。
#
#   超时由调用方用 timeout 兜底，本脚本自己不管超时。

set -euo pipefail

dest="${1:?用法: winwitch-watch <bus-name> [行数]}"
lines="${2:-3}"

tmpd="$(mktemp -d)"
fifo="$tmpd/pipe"
mkfifo "$fifo"

monitor_pid=""

cleanup() {
    if [ -n "$monitor_pid" ]; then
        kill "$monitor_pid" 2>/dev/null || true
    fi
    rm -rf "$tmpd"
}
trap cleanup EXIT

gdbus monitor --session --dest "$dest" 2>/dev/null > "$fifo" &
monitor_pid=$!

# 读够行数就退出。刻意用 bash 内建 read + printf，不用 `head`：
# head 走 stdio 缓冲，而「等到超时才是头」这条路径上进程会被 SIGTERM 收掉，
# 缓冲里那两三行就丢了。这条路径恰好是面板用来判断 helper 上下线的，
# 丢了就永远发现不了它重启。
exec 3< "$fifo"
n=0
while [ "$n" -lt "$lines" ]; do
    if ! IFS= read -r line <&3; then
        break
    fi
    printf '%s\n' "$line"
    n=$((n + 1))
done
exec 3<&-
