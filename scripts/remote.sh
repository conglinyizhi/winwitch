#!/usr/bin/env bash
# 把编译、测试、安装放到另一台机器上跑，本机只负责编辑源码。
#
#   scripts/remote.sh sync             只同步源码
#   scripts/remote.sh make ci          同步后在远程跑 make ci
#   scripts/remote.sh make install     同步后在远程装（装到那台机器的会话里）
#
# 为什么这么做：本机是提督日常在用的机器，重载 plasmashell、清 QML 缓存、
# 重启 KWin 脚本这些动作会打断他手上的活。搬到专门的机器上就没这问题。
#
# 远程需要：ssh 免密、~/.moon/bin 里有与本机同版本的 moon（每夜构建）。
# 可用 WINWITCH_REMOTE / WINWITCH_REMOTE_DIR 覆盖默认值。
set -euo pipefail

REMOTE="${WINWITCH_REMOTE:-user@remote-host}"
DEST="${WINWITCH_REMOTE_DIR:-disk/ai_workspace/kde-winwitch}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sync_src() {
    rsync -a --delete --exclude _build --exclude .git "$SRC/" "$REMOTE:$DEST/"
}

main() {
    if [ "${1:-}" = "sync" ]; then
        sync_src
        echo "已同步到 $REMOTE:$DEST"
        return
    fi
    if [ "$#" -eq 0 ]; then
        sync_src
        echo "已同步到 $REMOTE:$DEST（没给命令）"
        return
    fi

    sync_src
    # 参数原样带过去：引号用 %q 保住，别让本地 shell 先吃掉一层
    local cmd=""
    for arg in "$@"; do
        cmd+="$(printf '%q ' "$arg")"
    done
    # shellcheck disable=SC2029
    ssh "$REMOTE" "export PATH=\$HOME/.moon/bin:\$PATH; cd \"\$HOME/$DEST\" && $cmd"

    # 装完/重载完顺手确认浮层还在跑。踩过四次「改了没生效」，其中两次是
    # 浮层进程根本没起来——helper 那边完全看不出异常，只有人到屏幕前才发现。
    case "$cmd" in
        *"make install"* | *"make reload"*)
            if ! ssh "$REMOTE" "pgrep -f '[w]inwitch/overlay/main.qml' >/dev/null"; then
                # shellcheck disable=SC2029
                ssh "$REMOTE" "systemd-run --user --unit=wx-main --collect \"\$HOME/.local/bin/winwitch-overlay\" >/dev/null 2>&1" || true
                sleep 3
                if ssh "$REMOTE" "pgrep -f '[w]inwitch/overlay/main.qml' >/dev/null"; then
                    echo "提示：浮层原本没在跑，已自动拉起"
                else
                    echo "警告：浮层没起来，手动查 journalctl --user -u wx-main" >&2
                fi
            fi
            ;;
    esac
}

main "$@"
