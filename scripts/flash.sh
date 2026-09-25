#!/usr/bin/env bash
# 闪测：唤醒一次浮层，短暂显示后自动收掉。
#
# 为什么是脚本而不是浮层里的「调试模式」：调试用的东西不该长在正式功能里。
# 早先加过一版（置底 + 右下角标注「调试模式」），既不好看、标注还出来得慢，
# 反而拖慢排障，已按提督要求删掉。这里只是「触发 + 定时取消」两步，
# 浮层与 KWin 那边不需要任何特殊分支。
#
# 用法：
#     flash.sh            # 显示 1.2 秒后自动收掉
#     flash.sh 3          # 显示 3 秒
set -euo pipefail

service="io.github.conglinyizhi.winwitch"
object="/winwitch"
seconds="${1:-1.2}"

timeout 10 qdbus6 org.kde.kglobalaccel /component/kwin \
    org.kde.kglobalaccel.Component.invokeShortcut "WinWitch 进入选择模式" \
    >/dev/null 2>&1 || true

sleep "$seconds"

token="$(timeout 8 qdbus6 "$service" "$object" "$service.Status" 2>/dev/null | head -1 || true)"
token="${token#selecting:}"
token="${token%%:*}"

case "$token" in
    idle*|"")
        echo "闪测：没有进入选择模式（可能有别的选择模式占着）"
        ;;
    *)
        timeout 8 qdbus6 "$service" "$object" "$service.Cancel" "$token" >/dev/null 2>&1 || true
        echo "闪测：显示 ${seconds}s 后已收掉（token=$token）"
        ;;
esac
