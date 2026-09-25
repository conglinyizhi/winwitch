import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.taskmanager as TaskManager

// 顺序源：把任务栏的图标顺序、应用名、图标名推给字母切窗服务。
//
// 为什么必须有它：
//   1. KWin 枚举窗口的顺序与任务栏图标顺序**不一致**（实测任务栏第 0 位是飞书，
//      KWin 第 0 位是 Kate），只靠 KWin 无法让「A = 任务栏第一个图标」成立；
//   2. 应用名与图标名要从任务模型取才准（KWin 只给 window class，取不到图标）；
//   3. 独立进程读不了任务模型——一实例化 TasksModel 就加载失败。
//
// 本组件不绘制任何内容（零尺寸），只做这一件事。
PlasmoidItem {
    id: root

    // 实测：WinIdList 给出的就是 KWin internalId，可以直接对齐。
    readonly property int winIdListRole: TaskManager.AbstractTasksModel.WinIdList

    // 展示文本用 Qt::DisplayRole。
    // 不用 Qt::DecorationRole：它返回的是 QIcon 对象，转成字符串就是 "QIcon()"，
    // 取不到图标名。图标名改从应用标识推（feishu.desktop → feishu）。
    readonly property int displayRole: 0

    // 前缀常量：length 是属性不是函数，别在用的时候现取。
    readonly property string applicationsPrefix: "applications:"

    // 图标名缓存：应用标识 → 图标名/路径。
    // 为什么不直接猜：应用标识与图标名往往不一样（org.kde.kate 的图标叫 kate），
    // 而模型的 AppIconName 角色实测返回的是展示文本。最可靠的来源是 desktop
    // 文件的 Icon=，所以每个应用只查一次，结果缓存起来。
    property var iconCache: ({})
    property var pendingIcons: ({})

    P5Support.DataSource {
        id: orderSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName) {
            orderSource.disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: iconSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            var appId = root.pendingIcons[sourceName];
            iconSource.disconnectSource(sourceName);
            if (appId === undefined) {
                return;
            }
            delete root.pendingIcons[sourceName];
            var out = data && data["stdout"] ? String(data["stdout"]) : "";
            var icon = out.trim();
            if (icon.indexOf("\n") >= 0) {
                icon = icon.split("\n")[0].trim();
            }
            if (icon !== "") {
                root.iconCache[appId] = icon;
            }
        }
    }

    TaskManager.TasksModel {
        id: tasks
    }

    // 命令是交给 shell 解释的（引擎用的是 KProcess::setShellCommand），
    // 所以载荷要整体加双引号并转义。踩过的坑：不加引号的 `|` 会被当管道，
    // 整段文本被静默截断。
    function shellQuote(text) {
        var backslash = String.fromCharCode(92);
        var dquote = String.fromCharCode(34);
        var dollar = String.fromCharCode(36);
        var backtick = String.fromCharCode(96);
        var src = String(text);
        var out = "";
        for (var i = 0; i < src.length; i++) {
            var ch = src.charAt(i);
            if (ch === backslash || ch === dquote || ch === dollar || ch === backtick) {
                out += backslash + ch;
            } else {
                out += ch;
            }
        }
        return dquote + out + dquote;
    }

    function asString(value) {
        if (value === undefined || value === null) {
            return "";
        }
        if (typeof value === "string") {
            return value;
        }
        if (value.length !== undefined) {
            return value.length > 0 ? String(value[0]) : "";
        }
        return String(value);
    }

    function roleValue(row, role) {
        try {
            return tasks.data(tasks.index(row, 0), role);
        } catch (e) {
            return undefined;
        }
    }

    function appNameRole() {
        try {
            return TaskManager.AbstractTasksModel.AppName;
        } catch (e) {
            return -1;
        }
    }

    function appIdRole() {
        try {
            return TaskManager.AbstractTasksModel.AppId;
        } catch (e) {
            return -1;
        }
    }

    // 应用图标名：由应用自己声明（desktop 文件的 Icon=），比从标识猜准得多。
    // 很多应用的图标并不叫 feishu / code，直接按标识找是找不到的。
    function appIconRole() {
        try {
            return TaskManager.AbstractTasksModel.AppIconName;
        } catch (e) {
            return -1;
        }
    }

    // 从应用标识（feishu.desktop / org.kde.dolphin）推图标名。
    function iconFromAppId(appId) {
        var name = String(appId);
        if (name.indexOf(root.applicationsPrefix) === 0) {
            name = name.substring(root.applicationsPrefix.length);
        }
        var slash = name.lastIndexOf("/");
        if (slash >= 0) {
            name = name.substring(slash + 1);
        }
        if (name.length > 8 && name.substring(name.length - 8) === ".desktop") {
            name = name.substring(0, name.length - 8);
        }
        return name;
    }

    // 应用标识里只保留安全字符，避免拼进命令时被注入。
    function safeAppId(appId) {
        var src = String(appId);
        var out = "";
        for (var i = 0; i < src.length; i++) {
            var ch = src.charAt(i);
            var code = src.charCodeAt(i);
            var isDigit = code >= 48 && code <= 57;
            var isUpper = code >= 65 && code <= 90;
            var isLower = code >= 97 && code <= 122;
            var isPunct = ch === "_" || ch === "." || ch === "-";
            if (isDigit || isUpper || isLower || isPunct) {
                out += ch;
            }
        }
        return out;
    }

    // 取应用图标名：优先缓存；没有则发一次性查询，本轮回退到按标识推的名字。
    function iconFor(appId) {
        if (appId === "") {
            return "";
        }
        if (root.iconCache[appId] !== undefined) {
            return root.iconCache[appId];
        }
        if (root.pendingIcons[appId] === undefined) {
            var file = root.safeAppId(appId);
            if (file !== "") {
                var cmd = "for d in \"$HOME/.local/share/applications\" /usr/share/applications "
                        + "/var/lib/flatpak/exports/share/applications; do "
                        + "f=$d/" + file + "; [ -f \"$f\" ] && sed -n s/^Icon=//p \"$f\" | head -1; done";
                root.pendingIcons[cmd] = appId;
                iconSource.connectSource(cmd);
            }
        }
        return root.iconFromAppId(appId);
    }

    // 每行一个位置：`<ids 逗号分隔>\t应用名\t图标名\t标题`。
    // 启动器行 ids 为空，但依然占位——helper 会为它空掉一个字母。
    function collectSlots() {
        var lines = [];
        var count = tasks.count;
        for (var r = 0; r < count; r++) {
            var ids = [];
            var rawIds = roleValue(r, root.winIdListRole);
            if (rawIds !== undefined && rawIds !== null) {
                if (typeof rawIds === "string") {
                    if (rawIds !== "") {
                        ids.push(rawIds);
                    }
                } else if (rawIds.length !== undefined) {
                    for (var i = 0; i < rawIds.length; i++) {
                        ids.push(String(rawIds[i]));
                    }
                }
            }

            var appId = asString(roleValue(r, root.appIdRole()));
            var appName = asString(roleValue(r, root.appNameRole()));
            if (appName === "") {
                appName = root.iconFromAppId(appId);
            }

            var iconName = root.iconFor(appId);

            var title = asString(roleValue(r, root.displayRole));

            lines.push(ids.join(",") + "\t" + appName + "\t" + iconName + "\t" + title);
        }
        return lines.join("\n");
    }

    // 每次都推，不做「内容没变就跳过」的去重。
    // 踩过的坑：helper 重启后之前推过的顺序就丢了，而面板以为自己推过了，
    // 于是永远不再推，字母退回 KWin 顺序（与任务栏对不上）。
    // 每秒一次调用不算什么（Status 轮询本来就是每秒四次）。
    function pushOrder() {
        var payload = root.collectSlots();
        if (payload === "") {
            return;
        }
        orderSource.connectSource("qdbus6 org.clyzhi.LetterSwitch /LetterSwitch "
                                  + "org.clyzhi.LetterSwitch.Order " + root.shellQuote(payload));
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.pushOrder()
    }

    Component.onCompleted: root.pushOrder()

    compactRepresentation: Item {
        implicitWidth: 0
        implicitHeight: 0
    }

    fullRepresentation: compactRepresentation
}
