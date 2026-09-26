// SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import org.kde.taskmanager as TaskManager

// 顺序源：把任务栏的图标顺序（含固定应用）、应用名、图标名推给WinWitch服务。
//
// 为什么必须有它：
//   1. KWin 枚举窗口的顺序与任务栏图标顺序**不一致**（实测任务栏第 0 位是固定应用，
//      KWin 第 0 位是 Kate），只靠 KWin 无法让「A = 任务栏第一个图标」成立；
//   2. **固定应用（常驻图标）必须占位**。它们在任务栏最前面，若不给它们留位置，
//      后面所有字母都会相对图标整体前移；
//   3. 应用名与图标名要从任务模型/desktop 文件取才准；
//   4. 独立进程读不了任务模型（一实例化 TasksModel 就加载失败），只有面板组件能读。
//
// 本组件不绘制任何内容（零尺寸），只做这一件事。
PlasmoidItem {
    id: root

    // 实测：WinIdList 给出的就是 KWin internalId，可以直接对齐。
    readonly property int winIdListRole: TaskManager.AbstractTasksModel.WinIdList

    // 展示文本用 Qt::DisplayRole。
    // 不用 Qt::DecorationRole：它返回 QIcon 对象，转成字符串就是 "QIcon()"。
    readonly property int displayRole: 0

    // 前缀常量：length 是属性不是函数，别在用的时候现取。
    // 浮层窗口的标题：用它把自己的界面从任务列表里排除掉。
    readonly property string overlayTitle: "WinWitch"

    readonly property string applicationsPrefix: "applications:"
    readonly property string preferredPrefix: "preferred://"

    // 任务栏配置里的固定应用列表（原样保留顺序）。
    property var launchers: []
    // preferred://X → 解析出的应用标识（异步查一次，缓存）
    property var preferredResolved: ({})
    property var pendingPreferred: ({})

    // 图标名缓存：应用标识 → 图标名/路径。
    // 为什么不直接猜：应用标识与图标名往往不一样（org.kde.kate 的图标叫 kate），
    // 而模型的 AppIconName 角色实测返回的是展示文本。最可靠的来源是 desktop
    // 文件的 Icon=，所以每个应用只查一次，结果缓存起来。
    property var iconCache: ({})
    property var pendingIcons: ({})
    // 展示名（desktop 文件里的 Name=）另有缓存，理由同图标：固定但未启动的
    // 条目没有窗口可以问，只能查 desktop 文件，查一次就记住。
    property var nameCache: ({})
    property var pendingNames: ({})

    P5Support.DataSource {
        id: orderSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName) {
            orderSource.disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: noteSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName) {
            noteSource.disconnectSource(sourceName);
        }
    }

    TaskManager.TasksModel {
        id: tasks
    }

    // 上报不去重：诊断信息必须能在清空日志之后再看到。
    function report(tag) {
        noteSource.connectSource("qdbus6 io.github.conglinyizhi.winwitch /winwitch "
                                 + "io.github.conglinyizhi.winwitch.Note order-source-" + tag);
    }

    // 命令是交给 shell 解释的（引擎用 KProcess::setShellCommand），
    // 所以载荷要整体加双引号并转义。踩过的坑：不加引号的 `|` 被当管道，整段文本被截断。
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

    function appIdRole() {
        try {
            return TaskManager.AbstractTasksModel.AppId;
        } catch (e) {
            return -1;
        }
    }

    function appNameRole() {
        try {
            return TaskManager.AbstractTasksModel.AppName;
        } catch (e) {
            return -1;
        }
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

    // 从应用标识推图标名（兜底用）。
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

    // 取应用展示名。路子与取图标完全一致：缓存 → 没命中发一次性查询 → 本轮退回标识。
    function desktopNameFor(appId) {
        if (appId === "") {
            return "";
        }
        if (root.nameCache[appId] !== undefined) {
            return root.nameCache[appId];
        }
        if (root.pendingNames[appId] === undefined) {
            var file = root.safeAppId(appId);
            if (file !== "") {
                var cmd = "for d in \"$HOME/.local/share/applications\" /usr/share/applications "
                        + "/var/lib/flatpak/exports/share/applications; do "
                        // desktop 文件里只有英文 msgid；中文译文在 gettext 的 .mo 里。
                        // 必须给完整 locale（LC_ALL=zh_CN.UTF-8），只给 LANGUAGE 取不到。
                        + "f=$d/" + file + "; [ -f \"$f\" ] && { "
                        + "n=$(sed -n s/^Name=//p \"$f\" | head -1); "
                        + "LC_ALL=" + Qt.locale().name + ".UTF-8 "
                        + "gettext -d \"$(basename \"$f\" .desktop)\" \"$n\" 2>/dev/null "
                        + "|| printf %s \"$n\"; }; done";
                root.pendingNames[cmd] = appId;
                nameSource.connectSource(cmd);
            }
        }
        return root.iconFromAppId(appId);
    }

    P5Support.DataSource {
        id: nameSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            var appId = root.pendingNames[sourceName];
            nameSource.disconnectSource(sourceName);
            if (appId === undefined) {
                return;
            }
            delete root.pendingNames[sourceName];
            var out = data && data["stdout"] ? String(data["stdout"]) : "";
            var name = out.trim().split("\n")[0].trim();
            if (name !== "") {
                root.nameCache[appId] = name;
            }
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

    P5Support.DataSource {
        id: launcherSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            launcherSource.disconnectSource(sourceName);
            var out = data && data["stdout"] ? String(data["stdout"]).trim() : "";
            if (out === "") {
                root.report("launchers-empty");
                return;
            }
            var first = out.indexOf("\n") >= 0 ? out.split("\n")[0].trim() : out;
            var list = [];
            var parts = first.split(",");
            for (var i = 0; i < parts.length; i++) {
                var item = parts[i].trim();
                if (item !== "") {
                    list.push(item);
                }
            }
            if (list.length > 0) {
                root.launchers = list;
                root.report("launchers-read-" + list.length);
            }
        }
    }

    P5Support.DataSource {
        id: preferredSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            var entry = root.pendingPreferred[sourceName];
            preferredSource.disconnectSource(sourceName);
            if (entry === undefined) {
                return;
            }
            delete root.pendingPreferred[sourceName];
            var out = data && data["stdout"] ? String(data["stdout"]).trim() : "";
            if (out !== "") {
                root.preferredResolved[entry] = out.split("\n")[0].trim();
                root.report("preferred-resolved");
            }
        }
    }

    // 从任务栏组件自己的配置里读固定应用列表（取第一个 launchers= 行）。
    function fetchLaunchers() {
        launcherSource.connectSource("sed -n s/^launchers=//p "
                                     + "\"$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc\""
                                     + " | head -1");
    }

    // preferred://X 是符号名，要解析成实际的应用标识才能与在跑窗口对上。
    function resolvePreferred(entry) {
        if (root.preferredResolved[entry] !== undefined || root.pendingPreferred[entry] !== undefined) {
            return;
        }
        var cmd = "";
        if (entry === root.preferredPrefix + "filemanager") {
            cmd = "xdg-mime query default inode/directory";
        } else if (entry === root.preferredPrefix + "browser") {
            cmd = "xdg-settings get default-web-browser";
        } else {
            // 其它符号名暂不解析；该位置会当成空位处理
            root.preferredResolved[entry] = "";
            return;
        }
        root.pendingPreferred[entry] = true;
        root.pendingPreferred[cmd] = entry;
        preferredSource.connectSource(cmd);
    }

    // 「固定但未启动」的条目：没有窗口可依附，应用名和图标只能自己带。
    // 不加这个的话，浮层只看到一个空字母位（提督截图里 A 那个位置就是）。
    function launcherMeta(entry) {
        var ids = root.appIdsForLauncher(entry);
        if (ids.length === 0) {
            return null;
        }
        var appId = ids[0];
        return { name: root.desktopNameFor(appId), icon: root.iconFor(appId) };
    }

    // 一个固定项对应哪些应用标识（小写，含 .desktop）。
    function appIdsForLauncher(entry) {
        var text = String(entry);
        if (text.indexOf(root.applicationsPrefix) === 0) {
            return [text.substring(root.applicationsPrefix.length).toLowerCase()];
        }
        if (text.indexOf(root.preferredPrefix) === 0) {
            var resolved = root.preferredResolved[text];
            if (resolved === undefined || resolved === "") {
                root.resolvePreferred(text);
                return [];
            }
            return [String(resolved).toLowerCase()];
        }
        return [];
    }

    // 逐行读任务模型，得到 {ids, appId, appName, iconName, title}。
    function collectRows() {
        var rows = [];
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

            var title = asString(roleValue(r, root.displayRole));

            // 跳过浮层自己的窗口：它是我们自己的界面，不是可切换的目标。
            // （窗口类型已经设成 Qt.Tool，正常不该出现在这里；这里是第二道保险。）
            if (title === root.overlayTitle || appName === root.overlayTitle) {
                continue;
            }

            rows.push({
                ids: ids,
                appId: appId,
                appName: appName,
                iconName: root.iconFor(appId),
                title: title
            });
        }
        return rows;
    }

    // 把模型行整理成任务栏位置。
    //
    // 任务栏把固定应用放在最前面，而公开的任务模型**没有 launchers 属性**
    // （实测 tasks.launchers === undefined，和 filterByCurrentDesktop 一样被裁掉了），
    // 所以这里自己拼：先按配置里的固定列表逐项占位（在跑的对上窗口，没在跑的留空位），
    // 剩下的窗口再按模型顺序补在后面。
    function buildSlots() {
        var rows = root.collectRows();
        var used = [];
        for (var i = 0; i < rows.length; i++) {
            used.push(false);
        }

        var ordered = [];
        // 与 ordered 一一对应：非 null 表示这是「固定未启动」的条目，元数据得自带
        var meta = [];
        for (var l = 0; l < root.launchers.length; l++) {
            var wantIds = root.appIdsForLauncher(root.launchers[l]);
            var slotIds = [];
            for (var w = 0; w < wantIds.length; w++) {
                for (var r = 0; r < rows.length; r++) {
                    if (!used[r] && rows[r].appId.toLowerCase() === wantIds[w]) {
                        used[r] = true;
                        for (var k = 0; k < rows[r].ids.length; k++) {
                            slotIds.push(rows[r].ids[k]);
                        }
                    }
                }
            }
            ordered.push(slotIds);
            // 没有对应窗口 = 固定着但没启动，这条要自己带元数据
            meta.push(slotIds.length === 0 ? root.launcherMeta(root.launchers[l]) : null);
        }

        for (var j = 0; j < rows.length; j++) {
            if (!used[j]) {
                ordered.push(rows[j].ids);
                meta.push(null);
            }
        }

        var lines = [];
        for (var s = 0; s < ordered.length; s++) {
            if (meta[s] !== null) {
                // 空窗口 ID + 自带的应用名与图标，标题留空（它没有窗口）
                lines.push("\t" + meta[s].name + "\t" + meta[s].icon + "\t");
            } else {
                lines.push(ordered[s].join(",") + "\t\t\t");
            }
        }
        return { lines: lines, rows: rows };
    }

    // 把外观配置推给 helper（浮层读不到面板组件的配置，只能这样绕一道）。
    function pushConfig() {
        var position = "bottom";
        var columns = 6;
        var showTitle = true;
        // 注意别叫 transparent：那是 QML 内置的颜色常量，会撞名
        var backgroundStyle = "translucent";
        // 启动器条目的确认等待（毫秒）。浮层用它倒计时，所以走同一条配置通道。
        var armed = 1200;
        // KWin 脚本用它决定：选到已在前台的窗口时，最小化还是只重新激活
        var minimizeActive = true;
        try {
            position = String(plasmoid.configuration.overlayPosition);
            columns = Number(plasmoid.configuration.maxColumns);
            showTitle = Boolean(plasmoid.configuration.showWindowTitle);
            backgroundStyle = String(plasmoid.configuration.backgroundStyle);
            var armedRaw = Number(plasmoid.configuration.armedMillis);
            if (armedRaw > 0) {
                armed = armedRaw;
            }
            // 布尔值要判 undefined：直接 Boolean(undefined) 会变成 false，
            // 把「没配过」误当成「关掉了」
            var minimizeRaw = plasmoid.configuration.minimizeActive;
            if (minimizeRaw !== undefined) {
                minimizeActive = Boolean(minimizeRaw);
            }
        } catch (e) {
            // 配置没读到就用默认值，不影响主流程
        }
        var text = "position=" + position
                 + ";columns=" + columns
                 + ";showTitle=" + (showTitle ? "1" : "0")
                 + ";bg=" + backgroundStyle
                 + ";armed=" + armed
                 + ";minimizeActive=" + (minimizeActive ? "1" : "0");
        // 必须加引号：命令是交给 shell 解释的，`;` 会被当成命令分隔符，
        // 结果只传过去第一段（踩过，和 `|` 被当管道同一类问题）。
        configSource.connectSource("qdbus6 io.github.conglinyizhi.winwitch /winwitch "
                                   + "io.github.conglinyizhi.winwitch.Config " + root.shellQuote(text));
    }

    // 字母表必须与 core/labels.mbt 的 default_alphabet 完全一致：
    // 字母是按槽位顺序分的，所以「字母在该串里的下标」就是槽位下标。
    readonly property string alphabet: "ASDFGHJKLQWERTYUIOPZXCVBNM"

    // 启动一个 launcher URL（形如 applications:xxx.desktop，或 preferred://filemanager）。
    // 用 KDE 自己的 kioclient；找不到才退到旧名字。命令整串走 shell，所以必须引号。
    function launchEntry(entry) {
        if (!entry) {
            return;
        }
        // 实测：kioclient exec 不接受 `applications:xxx.desktop` 这种 URL，会弹
        // 「未知应用程序文件夹」。gtk-launch 按 XDG 桌面文件名启动，正好对得上，
        // 名字从 launcher URL 里剥（去掉 applications: 前缀和 .desktop 后缀）。
        var ids = root.appIdsForLauncher(entry);
        if (ids.length > 0) {
            var name = String(ids[0]);
            if (name.length > 8 && name.substring(name.length - 8) === ".desktop") {
                name = name.substring(0, name.length - 8);
            }
            launchExec.connectSource("gtk-launch " + root.shellQuote(name));
            return;
        }
        // 解析不出桌面文件名的（比如 preferred:// 之外的怪 URL），退回按 URL 处理
        launchExec.connectSource("kioclient exec " + root.shellQuote(entry));
    }

    // helper 报出「要启动字母 X」时：取走请求，再启动对应的固定项。
    // 字母 → 槽位 → launcher，用下标对齐（字母表顺序 = 槽位顺序）。
    function handleLaunch(letter) {
        var index = root.alphabet.indexOf(letter);
        if (index < 0 || index >= root.launchers.length) {
            return;
        }
        var entry = root.launchers[index];
        takeLaunchSource.connectSource("qdbus6 io.github.conglinyizhi.winwitch /winwitch "
                                       + "io.github.conglinyizhi.winwitch.TakeLaunch");
        root.launchEntry(entry);
    }

    // 从快照里挑出 `@launch=<字母>` 那一行。
    function launchLetterFrom(text) {
        var lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("@launch=") === 0) {
                return lines[i].substring(8).trim();
            }
        }
        return "";
    }

    function pollLaunch() {
        statusSource.connectSource("qdbus6 io.github.conglinyizhi.winwitch /winwitch "
                                   + "io.github.conglinyizhi.winwitch.Status");
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: root.pollLaunch()
    }

    P5Support.DataSource {
        id: statusSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            var letter = root.launchLetterFrom(data["stdout"] || "");
            if (letter !== "") {
                root.handleLaunch(letter);
            }
            disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: takeLaunchSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: launchExec

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
        }
    }

    P5Support.DataSource {
        id: configSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName) {
            configSource.disconnectSource(sourceName);
        }
    }

    // 每次都推，不做「内容没变就跳过」的去重。
    // 踩过的坑：helper 重启后之前推过的顺序就丢了，而面板以为自己推过了，
    // 于是永远不再推，字母静默退回 KWin 顺序（与任务栏对不上）。
    function pushOrder() {
        var built = root.buildSlots();
        var rows = built.rows;
        var lines = built.lines;

        // 把应用名/图标名/标题贴到对应位置上
        for (var i = 0; i < lines.length; i++) {
            var head = lines[i].split("\t")[0];
            if (head === "") {
                continue;
            }
            var firstId = head.split(",")[0];
            for (var r = 0; r < rows.length; r++) {
                var hit = false;
                for (var k = 0; k < rows[r].ids.length; k++) {
                    if (rows[r].ids[k] === firstId) {
                        hit = true;
                        break;
                    }
                }
                if (hit) {
                    lines[i] = head + "\t" + rows[r].appName + "\t"
                             + rows[r].iconName + "\t" + rows[r].title;
                    break;
                }
            }
        }

        var payload = lines.join("\n");
        if (payload === "") {
            return;
        }
        orderSource.connectSource("qdbus6 io.github.conglinyizhi.winwitch /winwitch "
                                  + "io.github.conglinyizhi.winwitch.Order " + root.shellQuote(payload));
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.pushOrder();
            root.pushConfig();
        }
    }

    // 固定应用列表会变（用户拖进拖出），定期重读。
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.fetchLaunchers()
    }

    Component.onCompleted: {
        root.fetchLaunchers();
        root.pushOrder();
        root.pushConfig();
    }

    // 面板上的入口：一个小而淡的图标，点它直接弹出设置。
    // 本组件本身不显示状态，它只是「顺序源 + 设置入口」。
    compactRepresentation: Kirigami.Icon {
        source: "preferences-system-windows"
        opacity: hoverArea.containsMouse ? 0.9 : 0.45
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: Kirigami.Units.iconSizes.small

        MouseArea {
            id: hoverArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                var action = plasmoid.internalAction("configure");
                if (action) {
                    action.trigger();
                }
            }
        }
    }

    fullRepresentation: compactRepresentation
}
