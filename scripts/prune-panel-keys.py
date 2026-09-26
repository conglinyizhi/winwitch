#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
# SPDX-License-Identifier: GPL-3.0-or-later

"""删掉面板配置里已被设置页废弃的键。

为什么必须清：KCM 加载「外观」设置页时，会拿配置里的每个键去找页面上对应的
`cfg_<键>` 属性；只要有一个键找不到属性，「设置初始属性」这一步就整体失败，
整页的值既读不出也存不进。症状是「设置项改了没反应」，配置文件里那几项甚至会凭空消失
（整页保存失败）。改键名之后不清旧键，这一页就废了。

声明以 panel/contents/config/main.xml 为准：不在里面的键就是废弃的。
改名时把旧键名加进 RETIRED，之后每次安装自动清掉。

必须在 plasmashell 停止时改：它在退出时会回写配置，运行中改会被覆盖。

用法：
    prune-panel-keys.py <appletsrc> <main.xml> --check
    prune-panel-keys.py <appletsrc> <main.xml> --apply
"""

import re
import sys

# 已经废弃的键：设置页里对应的 cfg_ 属性删掉之后，把键名留在这里，安装时顺手清掉。
RETIRED = ["transparentBackground"]

SECTION_RE = re.compile(
    r"^\[Containments\]\[\d+\]\[Applets\]\[\d+\]\[Configuration\]\[General\]$"
)
ENTRY_RE = re.compile(r"<entry\s+name=\"([A-Za-z0-9_]+)\"")


def declared_keys(xml_path):
    with open(xml_path, encoding="utf-8") as fh:
        return set(ENTRY_RE.findall(fh.read()))


def main(argv):
    rest = argv[1:]
    mode = "check" if "--check" in rest else "apply"
    positional = [a for a in rest if not a.startswith("--")]
    if len(positional) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    path, xml_path = positional
    declared = declared_keys(xml_path)
    known = declared | set(RETIRED)

    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")

    out = []
    removed = []
    in_ours = False
    for line in lines:
        if line.startswith("["):
            in_ours = bool(SECTION_RE.match(line))
            out.append(line)
            continue
        if in_ours:
            key = line.split("=", 1)[0].strip()
            # 只动「我们自己的键」里已经废弃的那些，别人的配置一概不碰
            if key in known and key not in declared:
                removed.append(key)
                continue
        out.append(line)

    if mode == "check":
        print("\n".join(removed) if removed else "0")
        return 0

    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out))
    print(len(removed))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
