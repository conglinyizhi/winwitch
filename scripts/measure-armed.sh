#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# 量一次启动器冷却的实际时长：按字母进冷却，轮询快照里 @armed 消失的时刻。
# 验收「启动器确认时间」设置是否真的生效，不依赖人眼。
#   用法：scripts/measure-armed.sh [字母]
set -uo pipefail

Q="qdbus6 io.github.conglinyizhi.winwitch /winwitch io.github.conglinyizhi.winwitch"
letter="${1:-A}"

make flash SEC=40 >/dev/null 2>&1 &
sleep 2
tok=$($Q.Status 2>/dev/null | head -1 | sed 's/selecting:\([^:]*\):.*/\1/')
if [ -z "$tok" ] || [ "$tok" = "$($Q.Status 2>/dev/null | head -1)" ]; then
    echo "没进选择模式，量不了"
    exit 1
fi

$Q.Key "$tok:$letter" >/dev/null
t0=$(date +%s%N)
seen=0
for _ in $(seq 1 200); do
    if $Q.Status 2>/dev/null | grep -q '^@armed='; then
        seen=1
    elif [ "$seen" = 1 ]; then
        break
    fi
    sleep 0.05
done
t1=$(date +%s%N)

if [ "$seen" = 0 ]; then
    echo "冷却没出现过（可能不是启动器条目）"
else
    echo "冷却时长 $(( (t1 - t0) / 1000000 )) ms（字母 $letter）"
fi
make cancel >/dev/null 2>&1 || true
