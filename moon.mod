name = "conglinyizhi/winwitch"

version = "0.1.0"

readme = "README.md"

license = "GPL-3.0-or-later"

keywords = [ "kde", "plasma", "kwin", "window-switcher" ]

description = "Letter-based window switcher for KDE Plasma 6 on Wayland. MoonBit holds the session state, KWin supplies windows and activation, Plasma draws the labels."

preferred_target = "native"

import {
  "conglinyizhi/moondbus@0.1.1",
  "moonbitlang/x@0.5.5",
}
