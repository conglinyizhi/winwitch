// 字母切窗 · KWin 侧
//
// 职责边界（刻意保持很薄）：
//   - 注册入口快捷键与每个字母的后续快捷键；
//   - 枚举可切换窗口；
//   - 调用 MoonBit helper（D-Bus）得到决定；
//   - 激活 helper 指定的窗口。
//
// 决策（字母分配、Esc 优先级、会话 token）全在 MoonBit 侧。
// 这里不做窗口 ID 之间的比较，也不读键盘设备。

var SERVICE = "org.clyzhi.LetterSwitch";
var PATH = "/LetterSwitch";
var IFACE = "org.clyzhi.LetterSwitch";

// 与 core 中的 default_alphabet 保持一致：主行 → 上排 → 下排。
var ALPHABET = "ASDFGHJKLQWERTYUIOPZXCVBNM";

// 选择模式的最长存活时间，超时自动取消，避免卡在半个会话里。
var SELECTION_TIMEOUT_MS = 4000;

var sessionToken = "";
var selecting = false;
var timeoutHandle = 0;

function readConfigString(key, fallback) {
    try {
        var value = readConfig(key, fallback);
        if (value === undefined || value === null || value === "") {
            return fallback;
        }
        return String(value);
    } catch (e) {
        return fallback;
    }
}

function scheduleTimeout(fn, ms) {
    if (typeof callLater === "function") {
        return callLater(ms, fn);
    }
    if (typeof setTimeout === "function") {
        return setTimeout(fn, ms);
    }
    return 0;
}

// 可切换窗口：普通窗口、不在任务栏隐藏、不跳过任务切换器。
function switchableWindows() {
    var result = [];
    var windows = workspace.windowList ? workspace.windowList() : workspace.clientList();
    for (var i = 0; i < windows.length; i++) {
        var w = windows[i];
        if (!w) {
            continue;
        }
        if (w.normalWindow === false) {
            continue;
        }
        if (w.skipTaskbar || w.skipSwitcher) {
            continue;
        }
        if (!w.internalId) {
            continue;
        }
        result.push(w);
    }
    return result;
}

function windowIdOf(win) {
    return String(win.internalId);
}

function clearSelection() {
    selecting = false;
    sessionToken = "";
    if (timeoutHandle && typeof cancelCallLater === "function") {
        cancelCallLater(timeoutHandle);
    }
    timeoutHandle = 0;
}

// Meta+F：把当前窗口列表交给 helper，拿回字母分配。
function beginSelection() {
    if (selecting) {
        // 再按一次等于放弃，避免留下半开状态。
        callCancel();
        return;
    }
    var windows = switchableWindows();
    var ids = [];
    for (var i = 0; i < windows.length; i++) {
        ids.push(windowIdOf(windows[i]));
    }
    var payload = ids.join("\t");
    callDBus(SERVICE, PATH, IFACE, "Begin", payload, function (reply) {
        var text = reply ? String(reply) : "";
        if (text === "" || text.indexOf("ignore") === 0) {
            clearSelection();
            return;
        }
        var parts = text.split("\t");
        sessionToken = parts[0];
        selecting = true;
        print("letterswitch: 选择模式开始 token=" + sessionToken +
              " 映射=" + parts.slice(1).join(" "));
        timeoutHandle = scheduleTimeout(function () {
            print("letterswitch: 选择模式超时");
            callCancel();
        }, SELECTION_TIMEOUT_MS);
    });
}

function callCancel() {
    if (!selecting) {
        clearSelection();
        return;
    }
    var token = sessionToken;
    callDBus(SERVICE, PATH, IFACE, "Cancel", token, function () {
        print("letterswitch: 已取消");
    });
    clearSelection();
}

function activateWindowById(id) {
    var windows = switchableWindows();
    for (var i = 0; i < windows.length; i++) {
        if (windowIdOf(windows[i]) === id) {
            workspace.activeWindow = windows[i];
            return true;
        }
    }
    print("letterswitch: 目标窗口已不存在，忽略 " + id);
    return false;
}

// 单个字母：交给 helper 判定，Esc 的优先级也在那边。
function handleLetter(letter) {
    if (!selecting) {
        return;
    }
    var token = sessionToken;
    callDBus(SERVICE, PATH, IFACE, "Key", token + ":" + letter, function (reply) {
        var text = reply ? String(reply) : "ignore";
        if (text.indexOf("activate:") === 0) {
            var id = text.substring("activate:".length());
            clearSelection();
            activateWindowById(id);
        } else if (text === "cancel" || text === "timeout") {
            clearSelection();
        }
    });
}

// Esc：不激活任何窗口，只清理。helper 会作废 token，迟到的按键自然失效。
function handleEscape() {
    callCancel();
}

function registerLetterShortcuts(prefix, useSequences) {
    for (var i = 0; i < ALPHABET.length; i++) {
        (function (letter) {
            var sequence = useSequences ? (prefix + ", " + letter) : ("Meta+Alt+" + letter);
            registerShortcut(
                "字母切窗 " + letter,
                "切换到标签为 " + letter + " 的窗口",
                sequence,
                function () {
                    handleLetter(letter);
                }
            );
        })(ALPHABET[i]);
    }
}

function init() {
    var prefix = readConfigString("shortcutPrefix", "Meta+F");
    var useSequences = readConfigString("useSequences", "true") !== "false";

    registerShortcut(
        "字母切窗 进入选择模式",
        "显示窗口字母标签并进入选择模式",
        prefix,
        beginSelection
    );
    registerShortcut(
        "字母切窗 取消",
        "取消选择模式，不切换窗口",
        prefix + ", Escape",
        handleEscape
    );

    registerLetterShortcuts(prefix, useSequences);

    print("letterswitch: 已注册，入口 " + prefix +
          (useSequences ? "（组合序列）" : "（Meta+Alt+字母 平铺）"));
}

// 脚本重载或 KWin 退出时不留半开状态。
function cleanup() {
    clearSelection();
}

init();
