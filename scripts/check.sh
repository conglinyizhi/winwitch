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

note "5. MoonBit"
moon check --target native >/dev/null || bad "moon check 失败"

if [ "$fail" -ne 0 ]; then
    note ""
    note "检查未通过"
    exit 1
fi
note ""
note "检查通过"
