#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
# SPDX-License-Identifier: GPL-3.0-or-later

"""给 winwitch 面板组件写一个配置键。

    scripts/set-panel-key.py <appletsrc> <键> <值>

只动 winwitch 那个组件的 [Configuration][General] 段：先按
plugin=io.github.conglinyizhi.winwitch.panel 定位它的 Applets 段，
再在对应 General 段里写键。找不到就报错退出，不乱猜组号。
"""
import re
import sys

if len(sys.argv) != 4:
    sys.exit(__doc__)

path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
plugin = "io.github.conglinyizhi.winwitch.panel"
lines = open(path, encoding="utf-8").read().split("\n")

applet = None
seen = None
for line in lines:
    stripped = line.strip()
    m = re.match(r"^\[Containments\]\[(\d+)\]\[Applets\]\[(\d+)\]$", stripped)
    if m:
        seen = (m.group(1), m.group(2))
        continue
    if seen and stripped == "plugin=" + plugin:
        applet = seen
        break

if applet is None:
    sys.exit("没找到 winwitch 面板组件")

group = "[Containments][%s][Applets][%s][Configuration][General]" % applet
start = None
for i, line in enumerate(lines):
    if line.strip() == group:
        start = i
        break

if start is None:
    # 全新组件可能还没有配置段，KConfig 不要求段的先后，补在文件末尾即可
    lines.append("")
    lines.append(group)
    lines.append("%s=%s" % (key, value))
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    print("已新建 %s 并写入 %s=%s" % (group, key, value))
    sys.exit(0)

end = len(lines)
for i in range(start + 1, len(lines)):
    if lines[i].startswith("["):
        end = i
        break

for i in range(start + 1, end):
    if lines[i].split("=")[0].strip() == key:
        lines[i] = "%s=%s" % (key, value)
        break
else:
    lines.insert(end, "%s=%s" % (key, value))

open(path, "w", encoding="utf-8").write("\n".join(lines))
print("已写入 %s=%s" % (key, value))
