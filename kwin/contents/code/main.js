// 字母切窗 · KWin 侧
//
// 职责边界（刻意保持很薄）：
//   - 注册入口快捷键与每个字母的后续快捷键；
//   - 枚举可切换窗口；
//   - 调用 MoonBit helper（D-Bus）得到决定；
//   - 激活 helper 指定的窗口。
//
// 决策（字母分配、Esc 优先级、会话 token、超时）全在 MoonBit 与界面侧，
// 这里**不保存**「是否正在选择」这类状态。早期版本存过，结果界面侧看门狗
// 取消之后本地标志与 helper 不一致，再按 Meta+F 会变成取消而不是开始。

var SERVICE = "org.clyzhi.LetterSwitch";
var PATH = "/LetterSwitch";
var IFACE = "org.clyzhi.LetterSwitch";

// 前缀常量：不要在用的时候现取长度。曾经把 length 当函数调用，
// 一调就抛 TypeError，而 callDBus 回调里的异常会被静默吞掉，
// 外部只看到「按了没反应」。
var ACTIVATE_PREFIX = "activate:";
var ERROR_PREFIX = "error";

// 与 core 中的 default_alphabet 保持一致：主行 → 上排 → 下排。
var ALPHABET = "ASDFGHJKLQWERTYUIOPZXCVBNM";

// 最近一次 Begin 拿到的 token。空表示当前没有会话；陈旧 token 由 helper 拒绝。
var sessionToken = "";

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

function windowTitleOf(win) {
    return win && win.caption ? String(win.caption) : "";
}

// Meta+F：每次都重新开始。helper 的 Begin 会换新 token 并重新分配字母，
// 所以连按两次等于「按当前窗口列表重来」，不会留下半开状态。
function beginSelection() {
    var windows = switchableWindows();
    var ids = [];
    for (var i = 0; i < windows.length; i++) {
        ids.push(windowIdOf(windows[i]));
    }
    callDBus(SERVICE, PATH, IFACE, "Begin", ids.join("\t"), function (reply) {
        var text = reply ? String(reply) : "";
        var parts = text.split("\t");
        if (parts.length === 0 || parts[0] === "" || parts[0].indexOf(ERROR_PREFIX) === 0) {
            sessionToken = "";
            print("letterswitch: 进入选择模式失败，reply=" + text);
            return;
        }
        sessionToken = parts[0];
        print("letterswitch: 选择模式开始 token=" + sessionToken +
              " 映射=" + parts.slice(1).join(" "));
    });
}

// 取消：不激活任何窗口。Esc 与界面侧看门狗都会走到这里。
function callCancel() {
    var token = sessionToken;
    sessionToken = "";
    if (token === "") {
        return;
    }
    callDBus(SERVICE, PATH, IFACE, "Cancel", token, function () {
        print("letterswitch: 已取消");
    });
}

function activateWindowById(id) {
    var windows = switchableWindows();
    for (var i = 0; i < windows.length; i++) {
        if (windowIdOf(windows[i]) === id) {
            try {
                var title = windowTitleOf(windows[i]);
                print("letterswitch: 准备激活 " + title + " (" + id + ")");
                workspace.activeWindow = windows[i];
                print("letterswitch: 已激活 " + title);
            } catch (e) {
                print("letterswitch: 激活抛错 " + e);
            }
            return true;
        }
    }
    print("letterswitch: 目标窗口已不存在，忽略 " + id);
    return false;
}

// 单个字母：交给 helper 判定。Esc 的优先级、陈旧 token、超时都在那边。
//
// 激活过程全部包在 try/catch 里：callDBus 回调里抛出的异常会被静默吞掉，
// 外部只能看到「按了没反应」。得自己把错误打出来。
function handleLetter(letter) {
    if (sessionToken === "") {
        return;
    }
    var token = sessionToken;
    callDBus(SERVICE, PATH, IFACE, "Key", token + ":" + letter, function (reply) {
        try {
            var text = reply ? String(reply) : "ignore";
            print("letterswitch: 按键 " + letter + " -> " + text);
            if (text.indexOf(ACTIVATE_PREFIX) !== 0) {
                sessionToken = "";
                return;
            }
            var id = text.substring(ACTIVATE_PREFIX.length);
            sessionToken = "";
            var windows = switchableWindows();
            print("letterswitch: 候选窗口 " + windows.length + " 个，查找 " + id);
            for (var i = 0; i < windows.length; i++) {
                if (windowIdOf(windows[i]) === id) {
                    print("letterswitch: 命中下标 " + i + "，标题 " + windowTitleOf(windows[i]));
                    workspace.activeWindow = windows[i];
                    print("letterswitch: 已激活");
                    return;
                }
            }
            print("letterswitch: 未找到目标窗口 " + id);
        } catch (e) {
            print("letterswitch: 激活流程抛错 " + e);
        }
    });
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
        callCancel
    );

    registerLetterShortcuts(prefix, useSequences);

    print("letterswitch: 已注册，入口 " + prefix +
          (useSequences ? "（组合序列）" : "（Meta+Alt+字母 平铺）"));
}

// 脚本重载或 KWin 退出时不留半开状态。超时由界面侧看门狗负责：
// KWin 脚本里的 callLater 实测会漏触发，不能作为唯一保障。
function cleanup() {
    callCancel();
}

init();
