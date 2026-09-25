#!/usr/bin/env python3
"""删掉面板配置里指向旧包 ID 的组件段。

背景：改名之后，面板配置里仍留着旧 ID 的条目。这种条目在 Plasma 里是「加载失败的占位」，
拿不到 Applet 对象，所以没法用脚本 API 调 remove()——这就是上次清组件时漏掉它们的原因
（脚本里 `widgetById()` 返回空就跳过了）。只能直接改配置文件。

必须在 plasmashell 停止时改：它在退出时会回写配置，运行中改会被覆盖。

用法：
    clean-panel-config.py <appletsrc 路径> --check <旧ID> [旧ID ...]
    clean-panel-config.py <appletsrc 路径> --apply <旧ID> [旧ID ...]

--check 只打印将要删除的段数。
"""

import re
import sys

SECTION_RE = re.compile(r"^\[Containments\]\[(\d+)\]\[Applets\]\[(\d+)\]\s*$")


def find_stale_prefixes(lines, legacy_ids):
    """找出 plugin= 指向旧 ID 的 Applet 段前缀。"""
    prefixes = set()
    current = None
    for line in lines:
        m = SECTION_RE.match(line)
        if m:
            current = "[Containments][%s][Applets][%s]" % (m.group(1), m.group(2))
            continue
        if line.startswith("plugin=") and current is not None:
            plugin = line.split("=", 1)[1].strip()
            if plugin in legacy_ids:
                prefixes.add(current)
    return prefixes


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2

    path = sys.argv[1]
    mode = sys.argv[2]
    legacy_ids = set(sys.argv[3:])

    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except FileNotFoundError:
        print("0")
        return 0

    prefixes = find_stale_prefixes(lines, legacy_ids)

    if mode == "--check":
        print(len(prefixes))
        return 0

    if mode != "--apply":
        print("未知模式：%s" % mode, file=sys.stderr)
        return 2

    if not prefixes:
        print("0")
        return 0

    out = []
    skip = False
    for line in lines:
        if line.startswith("["):
            # 段前缀以 ] 结尾，所以 [51] 不会误伤 [511]
            skip = any(line.startswith(p) for p in prefixes)
        if not skip:
            out.append(line)

    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out))

    print(len(prefixes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
