#!/usr/bin/env bash
# 提交前的静态检查。
#
# 收在这里的都是真踩过的坑，不是风格洁癖。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
cd "$repo"

fail=0

note() { printf '%s\n' "$*"; }
bad() { printf '  不合规：%s\n' "$*"; fail=1; }

note "1. JavaScript / QML 里的 .length() 误用"
# length 是属性不是函数，加括号一调就抛 TypeError。
# 这类异常在 callDBus 回调里会被静默吞掉、在 QML 里只留一行指向无关行的报错，
# 排查成本很高。已经犯过两次，直接拦死。
if grep -rn '\.length()' --include='*.js' --include='*.qml' . \
        | grep -v '^\./node_modules' >/tmp/ls-lint-length.txt; then
    while IFS= read -r line; do
        bad "$line"
    done < /tmp/ls-lint-length.txt
else
    note "  未发现"
fi

note "2. MoonBit 里的 Array<...> 尖括号写法"
# 新语法是 Array[T]。尖括号是旧写法，混用会让解析器从那一行起就脉络，
# 报错还会指向无关行（排查了很久）。直接拦死。
if grep -rn 'Array<' --include='*.mbt' . >/tmp/ls-lint-angle.txt; then
    while IFS= read -r line; do
        bad "$line"
    done < /tmp/ls-lint-angle.txt
else
    note "  未发现"
fi

note "3. QML 里的 console.* 调用"
# 面板环境里 console.info 走 qDebug，默认不进 journal；console.warn 的行号
# 在多处补丁后会指向无关行。诊断信息应走 helper 的 Note 方法。
if grep -rn 'console\.' --include='*.qml' . >/tmp/ls-lint-console.txt; then
    while IFS= read -r line; do
        bad "$line"
    done < /tmp/ls-lint-console.txt
else
    note "  未发现"
fi

note "4. shell 与 JS 语法"
for f in scripts/*.sh overlay/*.sh; do
    bash -n "$f" || bad "$f 语法错误"
done
if command -v node >/dev/null 2>&1; then
    for f in kwin/contents/code/main.js scripts/*.js; do
        node --check "$f" >/dev/null || bad "$f 语法错误"
    done
fi
if command -v qmllint >/dev/null 2>&1; then
    for f in overlay/*.qml package/contents/ui/*.qml; do
        qmllint "$f" >/dev/null 2>&1 || bad "$f 未通过 qmllint"
    done
fi
if command -v desktop-file-validate >/dev/null 2>&1; then
    for f in data/*.desktop; do
        # 占位符不是合法字段码，替换后再校验
        sed -e 's|@HELPER@|/tmp/x|' -e 's|@WRAPPER@|/tmp/x|' -e 's|@OVERLAY@|/tmp/x|' "$f" >/tmp/ls-lint.desktop
        desktop-file-validate /tmp/ls-lint.desktop || bad "$f 不是合法的 desktop 文件"
    done
fi

note "5. 配置键与设置页属性对齐"
# KCM 加载设置页时，会拿配置里的每个键去找页面上对应的 cfg_<键> 属性。
# 只要有一个键对不上（改键名后留了旧键，或声明了却没写属性），
# 「设置初始属性」这一步就整体失败：整页的值既读不出也存不进，
# 用户看到的是「设置项改了没反应」，配置文件里那几项还会凭空消失。
# 只声明不用不行，只写属性不声明也不行，所以两边必须严格相等。
xml_keys="$(grep -oE '<entry name="[A-Za-z0-9_]+"' panel/contents/config/main.xml \
    | sed 's/.*name="//; s/"//' | sort)"
qml_keys="$(grep -oE 'property (alias|string|bool|int|real) cfg_[A-Za-z0-9_]+' \
    panel/contents/ui/configGeneral.qml | sed 's/.*cfg_//' | sort)"
if [ "$xml_keys" != "$qml_keys" ]; then
    bad "main.xml 的键与 configGeneral.qml 的 cfg_ 属性不一致（左 xml / 右 qml）"
    diff <(echo "$xml_keys") <(echo "$qml_keys") || true
fi
# 另外：废弃键若还留在用户配置里，同样会让整页初始化失败（安装脚本会清，这里只提示）。
if command -v python3 >/dev/null 2>&1 && [ -f "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]; then
    stale="$(python3 scripts/prune-panel-keys.py \
        "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" \
        panel/contents/config/main.xml --check || true)"
    if [ -n "$stale" ] && [ "$stale" != "0" ]; then
        note "  提示：用户配置里还有废弃键（$stale），重装或重载后会自动清掉"
    fi
fi

# 设置页回写 cfg_ 必须只由用户操作触发：控件初始化时会先把自己置成默认项，
# 用 onCurrentIndexChanged / onValueChanged 之类回写，那一下就把配置里的值冲成
# 列表第一项（真踩过：浮层位置永远回到 bottom，背景设置直接从配置里消失）。
# 排掉注释行：注释里正好会拿这条错误写法当反例。
if grep -vE '^\s*//' panel/contents/ui/configGeneral.qml \
        | grep -qE 'on(CurrentIndexChanged|ValueChanged|CheckedChanged)[^:]*:.*cfg_'; then
    bad "设置页用了初始化也会触发的信号回写 cfg_，请改用 onActivated / onValueModified / onToggled"
fi

note "6. MoonBit"
moon check --target native >/dev/null || bad "moon check 失败"

if [ "$fail" -ne 0 ]; then
    note ""
    note "检查未通过"
    exit 1
fi
note ""
note "检查通过"
