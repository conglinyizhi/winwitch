// WinWitch · KWin 侧
//
// 职责边界（刻意保持很薄）：
//   - 注册入口快捷键；
//   - 枚举可切换窗口；
//   - 取出「界面已经选好的窗口」并激活它。
//
// 决策（字母分配、Esc、会话 token）全在 MoonBit 与浮层侧。
//
// 两个踩出来的限制，决定了这里的写法：
//   1. KWin 脚本里**没有** callLater / setTimeout（实测 `probe callLater 不存在`），
//      所以这里做不了定时轮询，只能被动响应；
//   2. KGlobalAccel **不派发两段式序列的第二段**，所以 `Meta+F, A` 这种注册没有意义，
//      而且会让 Plasma 报「Meta+F 遮蔽了这些操作」。
//
// 因此：只注册 `Meta+F`，另加**一个没有按键的快捷键**用于提交。
// 空序列不占用任何组合键，只能按名字触发，因此不会遮蔽任何东西。

var SERVICE = "io.github.conglinyizhi.winwitch";
var PATH = "/winwitch";
var IFACE = "io.github.conglinyizhi.winwitch";

// 前缀常量：length 是属性不是函数，别在用的时候现取（踩过两次）。
var ACTIVATE_PREFIX = "activate:";
var ERROR_PREFIX = "error";

// 浮层自己的窗口标题，绝不能当成可切换目标。
// 窗口类型设了 Qt.Tool，但 Wayland 下 KWin 仍会把它算进窗口列表，
// 结果浮层自己占一个字母（用户实测发现过）。
var OVERLAY_TITLE = "WinWitch";

// 选中之后由界面触发的那一个动作名。没有按键，只按名字触发。
var COMMIT_SHORTCUT = "WinWitch 提交选择";
// 调试入口：空按键，只能用 invokeShortcut 按名字触发。
// 走这条路进选择模式时，浮层会置底、不抢焦点、右下角标「调试模式」，
// 免得排障时糊在用户窗口上还抢走键盘。
var DEBUG_SHORTCUT = "winwitch 调试预览";

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

function windowTitleOf(win) {
    return win && win.caption ? String(win.caption) : "";
}

// 应用标识：用来在界面上取图标。Wayland 上 resourceClass 是应用级标识。
function windowAppIdOf(win) {
    return win && win.resourceClass ? String(win.resourceClass) : "";
}

// 标题里可能有制表符或换行（行协议的分隔符），先清洗再拼装。
function sanitizeField(text) {
    var s = text === undefined || text === null ? "" : String(text);
    return s.replace(/[\t\n\r]/g, " ").substring(0, 60);
}

// 可切换窗口：普通窗口、不在任务栏隐藏、不跳过任务切换器、不是浮层自己。
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
        if (windowTitleOf(w) === OVERLAY_TITLE) {
            continue;
        }
        result.push(w);
    }
    return result;
}

function windowIdOf(win) {
    return String(win.internalId);
}

// Meta+F：每次都重新开始。helper 的 Begin 会换新 token 并重新分配字母，
// 所以连按两次等于「按当前窗口列表重来」，不会留下半开状态。
// 告诉 helper 现在是不是调试模式。浮层和这里都从配置串里读这个标记。
function setDebug(on) {
    callDBus(SERVICE, PATH, IFACE, "SetDebug", on ? "1" : "0", function () {});
}

function beginSelection(debug) {
    setDebug(debug === true);
    var windows = switchableWindows();
    var lines = [];
    for (var i = 0; i < windows.length; i++) {
        var w = windows[i];
        // 每行 id\t标题\t应用标识，顺序即字母顺序。
        // 标题与应用标识要一起送过去，否则界面无法说明「这个字母是哪个窗口」。
        lines.push(windowIdOf(w) + "\t" + sanitizeField(windowTitleOf(w))
                   + "\t" + sanitizeField(windowAppIdOf(w)));
    }
    callDBus(SERVICE, PATH, IFACE, "Begin", lines.join("\n"), function (reply) {
        var text = reply ? String(reply) : "";
        var parts = text.split("\t");
        if (parts.length === 0 || parts[0] === "" || parts[0].indexOf(ERROR_PREFIX) === 0) {
            sessionToken = "";
            print("winwitch: 进入选择模式失败，reply=" + text);
            return;
        }
        sessionToken = parts[0];
        print("winwitch: 选择模式开始 token=" + sessionToken +
              " 映射=" + parts.slice(1).join(" "));
    });
}

// 取消：不激活任何窗口。界面按 Esc、或点了取消，都会走到这里。
function callCancel() {
    var token = sessionToken;
    sessionToken = "";
    if (token === "") {
        return;
    }
    callDBus(SERVICE, PATH, IFACE, "Cancel", token, function () {
        print("winwitch: 已取消");
    });
}

function activateWindowById(id) {
    var windows = switchableWindows();
    for (var i = 0; i < windows.length; i++) {
        if (windowIdOf(windows[i]) === id) {
            try {
                var title = windowTitleOf(windows[i]);
                workspace.activeWindow = windows[i];
                print("winwitch: 已激活 " + title);
            } catch (e) {
                print("winwitch: 激活抛错 " + e);
            }
            return true;
        }
    }
    print("winwitch: 目标窗口已不存在，忽略 " + id);
    return false;
}

// 界面已经选好了字母（把选择写进了 helper），这里只需要把它取回来并激活。
//
// 浮层自己不能激活窗口（没有权限，KWin 也没暴露按 UUID 激活的 D-Bus 接口），
// 所以只能由 KWin 来做这一步。界面在调用 Key 之后再触发本动作。
function commitSelection() {
    callDBus(SERVICE, PATH, IFACE, "TakePending", function (reply) {
        var text = reply ? String(reply) : "none";
        if (text.indexOf(ACTIVATE_PREFIX) !== 0) {
            return;
        }
        var id = text.substring(ACTIVATE_PREFIX.length);
        sessionToken = "";
        activateWindowById(id);
    });
}

// 把浮层摆到设置要求的位置。
//
// 为什么要在 KWin 侧做：Wayland 的顶层窗口没有「请求位置」这回事，客户端设的 x/y 会被
// 合成器忽略（实测：设置成 top，浮层仍出现在屏幕中央）。合成器自己才能摆窗口，
// 所以由这里读配置、算坐标、设 frameGeometry。
function overlayTargetY(position, screenHeight, height) {
    var margin = 64;
    if (position === "top") {
        return margin;
    }
    if (position === "center") {
        return Math.max(0, Math.round((screenHeight - height) / 2));
    }
    return Math.max(0, Math.round(screenHeight - height - margin));
}

function placeOverlay(w) {
    callDBus(SERVICE, PATH, IFACE, "Settings", function (reply) {
        var text = reply ? String(reply) : "";
        var position = "bottom";
        var debug = false;
        var parts = text.split(";");
        for (var i = 0; i < parts.length; i++) {
            var eq = parts[i].indexOf("=");
            if (eq > 0) {
                var key = parts[i].substring(0, eq);
                var value = parts[i].substring(eq + 1);
                if (key === "position") {
                    position = value;
                } else if (key === "debug") {
                    debug = (value === "1");
                }
            }
        }

        var geo = null;
        try {
            geo = w.output ? w.output.geometry : null;
        } catch (e) {
            geo = null;
        }
        if (!geo) {
            print("winwitch: 取不到屏幕几何，跳过定位");
            return;
        }

        var frame = w.frameGeometry;
        var x = Math.round(geo.x + (geo.width - frame.width) / 2);
        var y = geo.y + overlayTargetY(position, geo.height, frame.height);
        try {
            // 这个 KWin 里：没有 Qt 对象（Qt.rect 用不了），x/y 是只读的。
            // 唯一可行的是给 frameGeometry 赋一个 JS 对象，marshalling 会转成 QRect。
            w.frameGeometry = { x: x, y: y, width: frame.width, height: frame.height };
            print("winwitch: 浮层定位 " + position + " -> " + x + "," + y);
        } catch (e2) {
            print("winwitch: 定位抛错 " + e2);
        }

        // 每次都显式设置：浮层窗口是复用的，调试模式退出后必须把置底撤掉。
        try {
            w.keepBelow = debug;
            print("winwitch: 浮层置底 " + (debug ? "开" : "关"));
        } catch (e3) {
            print("winwitch: 置底设置失败 " + e3);
        }
    });
}

// 浮层在 Begin 之后才映射，所以被动等它出现比轮询可靠（这个 KWin 里没有定时器 API）。
function hookOverlayPlacement() {
    try {
        workspace.windowAdded.connect(function (w) {
            if (w && windowTitleOf(w) === OVERLAY_TITLE) {
                placeOverlay(w);
            }
        });
        print("winwitch: 已挂上浮层定位");
    } catch (e) {
        print("winwitch: 挂浮层定位失败 " + e);
    }
}

function init() {
    var prefix = readConfigString("shortcutPrefix", "Meta+F");

    registerShortcut(
        "WinWitch 进入选择模式",
        "显示窗口字母标签并进入选择模式",
        prefix,
        beginSelection
    );

    // 空按键序列：不占用任何组合键，因此不会与 Meta+F 产生「遮蔽」告警，
    // 也不会抢走任何用户可能用到的键。只能通过 invokeShortcut 按名字触发。
    registerShortcut(
        COMMIT_SHORTCUT,
        "提交当前选中的字母（由浮层触发，无需手动按）",
        "",
        commitSelection
    );

    // 浮层在 Begin 之后才映射，用 windowAdded 被动等它出现
    hookOverlayPlacement();

    registerShortcut(
        DEBUG_SHORTCUT,
        "调试预览：浮层置底、不抢焦点、标出「调试模式」",
        "",
        function () {
            beginSelection(true);
        }
    );

    print("winwitch: 已注册，入口 " + prefix + "，提交动作无按键");
}

// 脚本重载或 KWin 退出时不留半开状态。
function cleanup() {
    callCancel();
}

init();
