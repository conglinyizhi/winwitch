# Plasma 6 字母窗口切换器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Plasma 6 Wayland window switcher that shows A-Z labels on taskbar icons after `Super+F`, activates the selected window, and gives `Esc` an emergency cancel path.

**Architecture:** A user-installed Plasma taskbar widget renders labels over task icons and publishes the current task mapping. A KWin script owns the `Super+F` entry point, window enumeration, activation, session state, and cleanup. A small user-level input helper handles arbitrary A-Z and `Esc` input only while a selection session is active.

**Tech Stack:** Plasma 6 QML, Qt 6, KWin JavaScript API, a small helper in the platform language selected after environment inspection, local IPC, shell packaging scripts, and unit tests for pure mapping/state logic.

## Global Constraints

- Target KDE Plasma 6 on Wayland only for the first release
- Do not modify files under `/usr/share`; install only to user-local locations
- `Super+F` enters selection mode; A-Z selects; `Esc` cancels without activation
- The taskbar label is rendered at the icon's upper-right corner
- Do not use `wmctrl`, X11 IDs, synthetic mouse clicks, or unbounded key logging
- Every mode message carries a session token and stale sessions are ignored
- Verify before claiming success; host environment may not have a running Plasma session

---

### Task 1: Establish project package layout and pure interaction model

**Files:**
- Create: `package/metadata.json`
- Create: `package/contents/ui/main.qml`
- Create: `src/label_mapping.js`
- Create: `tests/label_mapping.test.js`
- Create: `README.md`

**Interfaces:**
- `src/label_mapping.js` exports `labelsForTasks(taskIds, alphabet)` and `selectionForKey(mapping, key)`
- `package/contents/ui/main.qml` exposes `selectionMode`, `taskLabels`, and `sessionToken` properties for the taskbar layer

- [ ] **Step 1: Write failing tests**

Add tests for empty tasks, first 26 tasks, duplicate task IDs, invalid keys, and a stale session token.

- [ ] **Step 2: Run the tests and confirm failure**

Run `node --test tests/label_mapping.test.js`.

Expected: FAIL because `src/label_mapping.js` does not exist.

- [ ] **Step 3: Implement minimal mapping functions**

`labelsForTasks` must return an object mapping each unique task ID to `alphabet[index]`, capped at the alphabet length. `selectionForKey` must return the task ID for a valid label and `null` otherwise.

- [ ] **Step 4: Run tests and confirm pass**

Run `node --test tests/label_mapping.test.js`.

Expected: PASS.

- [ ] **Step 5: Add the minimal Plasma package shell**

Use `KPackageStructure: Plasma/Applet`, Plasma API minimum `6.0`, and a QML entry point. Keep the QML layer presentational and make it safe when no task model is available in a test viewer.

- [ ] **Step 6: Commit**

```bash
git add package src tests README.md
git commit -m "feat(plasmoid): 建立窗口导航器基础模型"
```

---

### Task 2: Implement KWin window-session controller

**Files:**
- Create: `kwin/metadata.json`
- Create: `kwin/contents/code/main.js`
- Create: `tests/kwin_session.test.js`

**Interfaces:**
- `main.js` owns `startSelection()`, `cancelSelection()`, `selectLetter(letter)`, and `cleanup()`
- The controller sends messages `{type, token, mapping}` and accepts only `show`, `select`, `cancel`, and `hide` message types

- [ ] **Step 1: Write failing pure-controller tests**

Test that `startSelection` creates a token and mapping, `selectLetter` activates only a live mapped window, `cancelSelection` never activates a window, and a stale token is ignored.

- [ ] **Step 2: Run tests and confirm failure**

Run `node --test tests/kwin_session.test.js`.

Expected: FAIL because the pure controller functions are missing.

- [ ] **Step 3: Implement the state machine**

Use `Idle` and `Selecting`. Register `Meta+F` with KWin's `registerShortcut`. Enumerate only normal, taskbar-visible windows and use `internalId` as the mapping key. `Esc` must call `cancelSelection` before any letter handling.

- [ ] **Step 4: Add KWin packaging metadata and runtime adapter**

Package the JavaScript as a `KWin/Script`. Keep runtime calls isolated behind small adapter functions so unit tests can use fake workspace/window objects.

- [ ] **Step 5: Run tests and confirm pass**

Run `node --test tests/kwin_session.test.js tests/label_mapping.test.js`.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add kwin tests
git commit -m "feat(kwin): 增加窗口导航器状态机"
```

---

### Task 3: Connect taskbar labels to the real Plasma task model

**Files:**
- Modify: `package/contents/ui/main.qml`
- Create: `package/contents/ui/TaskLabel.qml`
- Create: `package/contents/ui/TaskDelegate.qml`
- Create: `package/contents/config/main.xml`

**Interfaces:**
- `TaskDelegate` accepts `task`, `labelText`, and `selectionMode`
- `TaskLabel` renders nothing when `selectionMode` is false or `labelText` is empty
- The task model order is the sole source of dynamic label assignment

- [ ] **Step 1: Add a QML test fixture**

Create a fake list model in the QML test path that presents task IDs and icons, then verify labels appear only in selection mode.

- [ ] **Step 2: Run the QML fixture in a Plasma viewer**

Run `plasmoidviewer -a package` when Plasma tooling is available.

Expected: the widget loads without QML errors and labels are hidden in idle state.

- [ ] **Step 3: Implement the overlay delegate**

Use the existing task icon item as the parent coordinate system. Anchor a small `Rectangle` to `top` and `right`, with yellow background, black text, a 2–3 px radius, and no layout contribution.

- [ ] **Step 4: Connect real task model roles**

Use Plasma's public task manager QML import and keep task activation delegated to the KWin controller. Do not edit the system task manager package.

- [ ] **Step 5: Verify the fixture again**

Run the QML fixture and inspect the rendered task labels manually. Expected: labels track task delegate positions during list changes.

- [ ] **Step 6: Commit**

```bash
git add package
 git commit -m "feat(plasmoid): 在任务图标上显示字母标签"
```

---

### Task 4: Add input helper with emergency Esc handling

**Files:**
- Create: `helper/README.md`
- Create: `helper/src/main.cpp`
- Create: `helper/CMakeLists.txt`
- Create: `helper/tests/protocol.test.js`
- Create: `scripts/install.sh`
- Create: `scripts/uninstall.sh`

**Interfaces:**
- Helper receives a session token and mapping endpoint from the KWin layer
- Helper emits only `letter`, `cancel`, and `timeout` events
- `Esc` is handled before any letter conversion and ends the session

- [ ] **Step 1: Write protocol tests**

Test that `Esc` emits `cancel`, a supported A-Z key emits `letter`, unknown keys emit nothing, and events from an inactive token are rejected.

- [ ] **Step 2: Run the protocol tests and confirm failure**

Run `node --test helper/tests/protocol.test.js`.

Expected: FAIL because the protocol implementation is missing.

- [ ] **Step 3: Implement the smallest input backend supported by the target system**

Prefer a KWin/Wayland-supported compositor-level input path. Do not silently open every `/dev/input/event*` device. If the system requires a permission or a backend package, fail with an actionable message and keep the widget in `Idle`.

- [ ] **Step 4: Implement cancellation and cleanup first**

On `Esc`, stop the timer, send `cancel`, close the input handle, and exit the active session. Cleanup must also run on SIGTERM, SIGINT, EOF, and helper startup failure.

- [ ] **Step 5: Build and run tests**

Run `cmake -S helper -B build/helper -G Ninja`, `cmake --build build/helper`, and `node --test helper/tests/protocol.test.js`.

Expected: the helper builds and protocol tests pass. Hardware input integration is reported separately if no Wayland session is available.

- [ ] **Step 6: Commit**

```bash
git add helper scripts
 git commit -m "feat(input): 增加字母选择与 Esc 退出"
```

---

### Task 5: Package, install, and verify the full path

**Files:**
- Modify: `README.md`
- Create: `scripts/package.sh`
- Create: `tests/static_check.test.js`

**Interfaces:**
- `scripts/install.sh` installs the Plasmoid and KWin script to user-local KPackage locations and enables only this project
- `scripts/uninstall.sh` removes the installed artifacts without touching unrelated Plasma configuration

- [ ] **Step 1: Add static safety checks**

Check that package metadata declares Plasma 6, no source contains `wmctrl`, X11 window IDs, or unbounded keyboard logging, and the KWin code contains an explicit `Esc` cancellation branch.

- [ ] **Step 2: Run static checks and confirm failure if needed**

Run `node --test tests/static_check.test.js`.

Expected: PASS after the package files exist; any violation must be fixed before packaging.

- [ ] **Step 3: Implement install and uninstall scripts**

Use `kpackagetool6` with user-local package types. Save backups only for files created by this project; do not overwrite existing user shortcut configuration automatically.

- [ ] **Step 4: Build the distributable archive**

Run `scripts/package.sh` and verify the archive contains only project files and no build directory or local test artifacts.

- [ ] **Step 5: Verify available host tooling**

Run `kpackagetool6 --version`, `plasmashell --version`, `echo "$XDG_SESSION_TYPE"`, and `plasmoidviewer --version` when available. If no live Plasma session exists, report the exact unverified integration steps instead of claiming success.

- [ ] **Step 6: Commit**

```bash
git add README.md scripts tests
 git commit -m "docs: 补充 Plasma 安装与验收说明"
```
