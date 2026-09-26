# WinWitch

**English** | [简体中文](README.zh-CN.md)

A letter-based window switcher for KDE Plasma 6 on Wayland. Press `Meta+F`, an overlay shows
a letter for every window, press the letter to jump there.

It is not a replacement for Alt+Tab. It is for when you know *which* window you want and would
rather not cycle past the others to reach it.

## Features

- **One letter, one window.** Up to 26 targets, ordered the way your taskbar icons are.
- **Pinned apps are first-class.** A pinned-but-not-running app gets a slot too. Press its
  letter once to arm it (a countdown pie appears), press it again to launch. Pressing any
  other letter cancels and switches instead, so you can't launch by accident.
- **Window state is visible.** Cards show which window is in the foreground, which is
  minimized, and which entry is not running yet.
- **Selecting the foreground window minimizes it**, the way clicking its taskbar icon does.
  Configurable in the panel settings.
- **No auto-timeout.** The overlay stays until you pick a letter or press `Esc`.

## Requirements

- KDE Plasma 6 on Wayland
- MoonBit toolchain — **use the nightly** (`MOONBIT_INSTALL_VERSION=nightly`); stable
  releases are often missing language features this project uses
- `qdbus6` (from `qttools`) and a Qt 6 QML runtime

## Install from source

```bash
git clone https://github.com/conglinyizhi/winwitch
cd winwitch
make install     # builds the helper, installs the KWin script, panel applet and overlay
make reload      # asks KWin and plasmashell to reload
```

Two one-time steps after that:

1. Add the **WinWitch** panel widget to your taskbar. It supplies the taskbar order and app
   icons; without it the letters cannot line up with your icons.
2. The default shortcut is `Meta+F`. Change it in System Settings if you prefer.

Releases also ship a statically linked helper plus the add-on files (`*-addon.tar.gz`).
### From a release

The release page has one tarball. Unpack it and run:

```bash
tar -xzf winwitch-<version>.tar.gz
cd winwitch-<version>
./install.sh
```

It installs the helper, the KWin script, the panel applet, the overlay and the autostart
entries — no toolchain needed — then prints the two steps that touch your desktop settings.

## Usage

| Keys | Action |
| --- | --- |
| `Meta+F` | open the overlay |
| `<letter>` | switch to that window |
| `<letter>` twice | launch the pinned app (the first press only arms it) |
| `Esc` | close without switching |

## Configuration

Panel widget settings, two pages:

- **Appearance** — overlay position, maximum columns, whether to show window titles,
  background style
- **Behavior** — launcher confirmation time (the two-press window, 300–5000 ms) and whether
  selecting the foreground window minimizes it

## Architecture

Four pieces, because each is good at something different:

```
Meta+F
  |
  +- KWin script      shortcut, window list, activation and minimize
  +- MoonBit helper   session state and letter assignment, exposed over D-Bus
  +- Panel applet     taskbar order and app metadata (icons, names, settings)
  +- Overlay (QML)    draws the cards and captures the keystrokes
```

The overlay cannot activate windows (the compositor owns that) and cannot read the taskbar
model (only the panel can), so the choice travels through the helper and KWin performs the
activation. The helper also owns the letter table, which is why it is a separate process
instead of living inside one of the QML pieces.

**Why the letters line up with the taskbar:** KWin's window enumeration order is not the
taskbar order, so the panel applet pushes the taskbar order to the helper and the helper
assigns letters by slot. Once you press a key, the letter table freezes until that selection
ends — otherwise a changing window set (an app launching itself, say) would re-label the
letter under your finger.

## Notes

- **The panel widget has to stay on your taskbar.** It is what tells WinWitch your taskbar
  order and gives it app icons and names. Without it the letters do not line up with your
  icons, and pinned-app entries cannot show a name.
- The default shortcut is `Meta+F`; change it under System Settings → Shortcuts → WinWitch.
- **There is no auto-timeout.** The overlay stays until you press a letter or `Esc`.
  If it ever seems stuck, `Esc` always exits.
- The helper is autostarted. If `Meta+F` does nothing, check that `winwitch` is running —
  the overlay draws the cards, the helper holds the state, and a dead one shows no error.
- Wayland only. X11 is untested.
- Building from source needs the MoonBit **nightly** toolchain (see Requirements).

## Development

```bash
make ci              # lint, 64 unit tests, config-key checks
make reload          # reload the KWin script and plasmashell
make status          # process, appearance config, installed build identity
make flash SEC=3     # open the overlay and auto-cancel, handy for a quick look
make cancel          # the escape hatch (no auto-timeout, by design)
```

The helper's logic lives in `core/` and is deliberately free of KWin, Qt and D-Bus
dependencies, so `moon test` can run it anywhere.

`scripts/build-static.sh` produces a statically linked helper — that is what the release
workflow ships.

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).

Copyright (C) 2026 conglinyizhi <conglinyizhi@qq.com>
