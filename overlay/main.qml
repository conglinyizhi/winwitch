import QtQuick
import QtQuick.Window
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// WinWitch · 浮层
//
// 独立进程，不是面板组件：选择模式期间浮出一排卡片，说明「这个字母对应哪个窗口」
// （字母 + 图标 + 应用名 + 窗口标题），结束后消失。
// 用 qml6 运行：qml6 /path/to/main.qml
//
// 刻意没有自动超时：退出只靠 Esc 或选中某个字母。之前加过 8 秒兜底，提督明确不要。
Window {
    id: overlay

    // 选择模式期间要收键盘，所以窗口必须能拿焦点；不显示时它只是个隐藏窗口。
    //
    // 用 Qt.Tool 而不是 Qt.Window：浮层自己绝不能出现在任务栏/任务列表里，
    // 否则它会作为一个「可切换窗口」混进来占一个字母（用户实测发现过）。
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: "WinWitch"

    property bool selecting: false
    property string token: ""
    // 每行 { letter, title, appName, iconName }
    property var rows: []

    readonly property string serviceName: "io.github.conglinyizhi.winwitch"
    readonly property string objectPath: "/winwitch"
    readonly property string interfaceName: "io.github.conglinyizhi.winwitch"
    readonly property string selectingPrefix: "selecting:"
    readonly property string idlePrefix: "idle:"

    readonly property int cardWidth: Math.round(Kirigami.Units.gridUnit * 13)
    readonly property int cardHeight: Math.round(Kirigami.Units.gridUnit * 3.1)
    readonly property int cardMargin: Math.round(Kirigami.Units.smallSpacing * 1.2)
    readonly property int iconSize: cardHeight - cardMargin * 2
    readonly property int badgeSize: Math.round(Kirigami.Units.gridUnit * 1.1)
    readonly property int cardSpacing: Math.round(Kirigami.Units.smallSpacing)
    readonly property int cardPadding: Kirigami.Units.smallSpacing * 2

    // 每行最多放几张卡片，避免宽屏上排成一条长龙。
    readonly property int maxColumns: Math.max(1, Math.min(
        Math.min(overlay.maxColumnsSetting, 8),
        Math.floor((screen.width * 0.7) / (cardWidth + cardSpacing))))
    readonly property int columns: Math.max(1, Math.min(maxColumns, rows.length))
    readonly property int gridWidth: columns * cardWidth + (columns - 1) * cardSpacing

    // 外观配置，由面板组件经 helper 中转（快照里的 @config 行）。
    property string positionSetting: "bottom"
    property int maxColumnsSetting: 6
    property bool showWindowTitle: true
    property bool transparentBackground: false

    property int pollFailures: 0
    property bool useGdbus: false
    property bool announced: false

    visible: overlay.selecting && overlay.rows.length > 0
    width: gridWidth + cardPadding * 2
    height: grid.implicitHeight + cardPadding * 2

    // 位置由设置决定（bottom / center / top）。
    x: Math.round((screen.width - width) / 2)
    y: {
        if (overlay.positionSetting === "center") {
            return Math.round((screen.height - height) / 2);
        }
        if (overlay.positionSetting === "top") {
            return Math.round(Kirigami.Units.gridUnit * 4);
        }
        return Math.round(screen.height - height - Kirigami.Units.gridUnit * 4);
    }

    // 进入选择模式时抢焦点收键盘；退出时窗口隐藏，焦点自然还回去。
    onSelectingChanged: {
        if (overlay.selecting) {
            overlay.requestActivate();
            keyCatcher.forceActiveFocus();
        }
    }

    // 图标名归一化：绝对路径要当文件 URL 处理。
    function iconSource(name) {
        if (!name || name === "") {
            return "application-x-executable";
        }
        var text = String(name);
        if (text.charAt(0) === "/") {
            return "file://" + text;
        }
        return text;
    }

    function statusCommand() {        if (overlay.useGdbus) {
            return "gdbus call --session --dest " + overlay.serviceName
                 + " --object-path " + overlay.objectPath
                 + " --method " + overlay.interfaceName + ".Status";
        }
        return "qdbus6 " + overlay.serviceName + " " + overlay.objectPath
             + " " + overlay.interfaceName + ".Status";
    }

    // 日志统一走 helper：独立进程里 console 的输出去向不稳，落到一个文件更好查。
    function report(text) {
        noteSource.connectSource("qdbus6 " + overlay.serviceName + " " + overlay.objectPath
                                 + " " + overlay.interfaceName + ".Note " + text);
    }

    // 取消：不激活任何窗口。
    function cancelSelection() {
        report("overlay-escape");
        var t = overlay.token;
        if (t !== "") {
            actionSource.connectSource("qdbus6 " + overlay.serviceName + " " + overlay.objectPath
                                       + " " + overlay.interfaceName + ".Cancel " + t);
        }
    }

    // 解析快照：第一行状态，其余每行 `字母\t应用名\t图标名\t标题`。
    function applyStatus(raw) {
        var text = (raw || "").trim();

        // gdbus 的返回形如 ('...',)，且会把制表符与换行转义成字面量。先还原再切分。
        var quote = text.indexOf("'");
        if (quote >= 0) {
            var lastQuote = text.lastIndexOf("'");
            if (lastQuote > quote) {
                text = text.substring(quote + 1, lastQuote);
            }
        }
        text = text.replace(/\\n/g, "\n").replace(/\\t/g, "\t");

        var lines = text.split("\n");
        var head = (lines[0] || "").trim();

        var isSelecting = head.indexOf(overlay.selectingPrefix) === 0;
        var isIdle = head.indexOf(overlay.idlePrefix) === 0;

        if (isSelecting || isIdle) {
            overlay.pollFailures = 0;
            if (!overlay.announced) {
                overlay.announced = true;
                overlay.report("overlay-ready");
            }
        }

        if (isSelecting) {
            var rest = head.substring(overlay.selectingPrefix.length);
            var colon = rest.indexOf(":");
            var assignment = "";
            if (colon >= 0) {
                overlay.token = rest.substring(0, colon);
                assignment = rest.substring(colon + 1);
            } else {
                overlay.token = rest;
            }

            var letters = [];
            var parts = assignment.split("\t");
            for (var i = 0; i < parts.length; i++) {
                var eq = parts[i].indexOf("=");
                if (eq > 0) {
                    letters.push(parts[i].substring(0, eq));
                }
            }

            // 明细行：字母、应用名、图标名、窗口标题。
            // 另有一行 @config=... 承载外观配置，不是窗口。
            var parsed = [];
            for (var j = 1; j < lines.length; j++) {
                if (lines[j].indexOf("@config=") === 0) {
                    overlay.applyConfig(lines[j].substring("@config=".length));
                    continue;
                }
                var row = lines[j].split("\t");
                if (row.length >= 1 && row[0] !== "") {
                    parsed.push({
                        letter: row[0],
                        appName: row.length > 1 ? row[1] : "",
                        iconName: row.length > 2 ? row[2] : "",
                        title: row.length > 3 ? row[3] : ""
                    });
                }
            }
            // helper 没给明细时，至少把字母显示出来
            if (parsed.length === 0) {
                for (var k = 0; k < letters.length; k++) {
                    parsed.push({ letter: letters[k], appName: "", iconName: "", title: "" });
                }
            }

            var wasSelecting = overlay.selecting;
            overlay.rows = parsed;
            overlay.selecting = true;
            if (!wasSelecting) {
                overlay.report("overlay-selecting-token=" + overlay.token
                               + "-letters=" + letters.join(""));
            }
            return;
        }

        if (isIdle) {
            var wasIdle = !overlay.selecting;
            overlay.selecting = false;
            overlay.token = "";
            overlay.rows = [];
            if (!wasIdle) {
                overlay.report("overlay-idle");
            }
            return;
        }

        overlay.pollFailures += 1;
        if (overlay.pollFailures === 5) {
            overlay.report("overlay-poll-failed-raw=" + (head === "" ? "empty" : head));
            if (!overlay.useGdbus) {
                overlay.useGdbus = true;
                overlay.report("overlay-switch-to-gdbus");
            }
        }
        if (overlay.pollFailures >= 20) {
            overlay.pollFailures = 0;
        }
    }

    // 解析 `键=值;键=值` 形式的外观配置。
    function applyConfig(text) {
        var parts = String(text).split(";");
        for (var i = 0; i < parts.length; i++) {
            var eq = parts[i].indexOf("=");
            if (eq <= 0) {
                continue;
            }
            var key = parts[i].substring(0, eq);
            var value = parts[i].substring(eq + 1);
            if (key === "position") {
                overlay.positionSetting = value;
            } else if (key === "columns") {
                var n = parseInt(value, 10);
                if (!isNaN(n) && n >= 1) {
                    overlay.maxColumnsSetting = n;
                }
            } else if (key === "showTitle") {
                overlay.showWindowTitle = (value === "1");
            } else if (key === "transparent") {
                overlay.transparentBackground = (value === "1");
            }
        }
    }

    function pollStatus() {
        commandSource.connectSource(overlay.statusCommand());
    }

    // 选中一个字母（键盘按键或点击卡片都走这里）。
    //
    // 浮层自己不能激活窗口：KWin 没有暴露「按 UUID 激活」的 D-Bus 接口。
    // 所以分两步：先把选择写进 helper，再触发 KWin 那个无按键的「提交」动作，
    // 由 KWin 把窗口取回来激活。
    function activateLetter(letter) {
        var t = overlay.token;
        if (t === "") {
            return;
        }
        chooseSource.connectSource("qdbus6 " + overlay.serviceName + " "
                                   + overlay.objectPath + " " + overlay.interfaceName
                                   + ".Key " + t + ":" + letter);
    }

    // 第二步：让 KWin 去取（这个动作没有按键，因此不占用也不会遮蔽任何组合键）。
    function commitSelection() {
        actionSource.connectSource(
            "qdbus6 org.kde.kglobalaccel /component/kwin "
            + "org.kde.kglobalaccel.Component.invokeShortcut \"WinWitch 提交选择\"");
    }

    P5Support.DataSource {
        id: chooseSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName) {
            chooseSource.disconnectSource(sourceName);
            // 选择已经写进 helper，接着让 KWin 取走
            overlay.commitSelection();
        }
    }

    P5Support.DataSource {
        id: commandSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            var out = data && data["stdout"] ? data["stdout"] : "";
            commandSource.disconnectSource(sourceName);
            overlay.applyStatus(out);
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

    P5Support.DataSource {
        id: actionSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName) {
            actionSource.disconnectSource(sourceName);
        }
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: overlay.pollStatus()
    }

    // 键盘接收：选择模式期间浮层持有焦点，字母落到这里而不是当前窗口。
    Item {
        id: keyCatcher

        anchors.fill: parent
        focus: true

        Keys.onPressed: function (event) {
            if (!overlay.selecting) {
                return;
            }
            if (event.key === Qt.Key_Escape) {
                overlay.cancelSelection();
                event.accepted = true;
                return;
            }
            var text = event.text ? String(event.text).toUpperCase() : "";
            if (text.length === 1 && text >= "A" && text <= "Z") {
                overlay.activateLetter(text);
                event.accepted = true;
            }
        }
    }

    // 浮层底色。开了「背景色透明」就只留卡片（卡片自己还有半透明底，仍可读）。
    Rectangle {
        anchors.fill: parent
        radius: overlay.transparentBackground ? 0 : Kirigami.Units.smallSpacing
        color: overlay.transparentBackground
               ? "transparent"
               : Qt.rgba(0.09, 0.09, 0.11, 0.94)
        border.width: overlay.transparentBackground ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.16)

        Flow {
            id: grid

            x: overlay.cardPadding
            y: overlay.cardPadding
            width: overlay.gridWidth
            spacing: overlay.cardSpacing

            Repeater {
                model: overlay.rows

                Rectangle {
                    id: card

                    required property var modelData

                    width: overlay.cardWidth
                    height: overlay.cardHeight
                    radius: 4
                    color: cardArea.containsMouse
                           ? Qt.rgba(1, 1, 1, 0.14)
                           : Qt.rgba(1, 1, 1, 0.06)

                    Row {
                        anchors.fill: parent
                        anchors.margins: overlay.cardMargin
                        spacing: overlay.cardSpacing

                        // 图标 + 右上角的字母徽标（徽标压在图标角上，不另占一列）
                        Item {
                            id: iconBox

                            width: overlay.iconSize
                            height: overlay.iconSize

                            Kirigami.Icon {
                                anchors.fill: parent
                                // 图标名可能是主题名，也可能是绝对路径（desktop 文件里直接写的文件），
                                // 后者要转成 URL 才能被 Icon 加载。
                                source: overlay.iconSource(card.modelData.iconName)
                                fallback: "application-x-executable"
                            }

                            Rectangle {
                                id: badge

                                width: Math.max(badgeText.implicitWidth
                                                + Kirigami.Units.smallSpacing, overlay.badgeSize)
                                height: Math.max(badgeText.implicitHeight + 2, overlay.badgeSize)
                                radius: 3
                                color: cardArea.containsMouse ? "#ffd977" : "#f5c542"
                                border.width: 1
                                border.color: "#8a6d1a"

                                // 贴图标右上角，略微外移一点，读起来像挂在角上
                                anchors.right: parent.right
                                anchors.rightMargin: -Math.round(width * 0.3)
                                anchors.top: parent.top
                                anchors.topMargin: -Math.round(height * 0.3)

                                Text {
                                    id: badgeText

                                    anchors.centerIn: parent
                                    text: card.modelData.letter
                                    color: "#1a1a1a"
                                    font.bold: true
                                    font.pixelSize: Math.round(badge.height * 0.62)
                                }
                            }
                        }

                        Column {
                            width: overlay.cardWidth - overlay.iconSize
                                   - overlay.cardMargin * 2 - overlay.cardSpacing
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            // 大标题：应用名，先说「这是什么程序」
                            Text {
                                width: parent.width
                                text: card.modelData.appName !== ""
                                      ? card.modelData.appName
                                      : card.modelData.title
                                color: "#ffffff"
                                elide: Text.ElideRight
                                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.9)
                                font.bold: true
                            }

                            // 小标题：窗口标题，用来区分同一应用的多个窗口
                            Text {
                                width: parent.width
                                visible: overlay.showWindowTitle && text !== ""
                                text: (card.modelData.appName !== ""
                                       && card.modelData.appName !== card.modelData.title)
                                      ? card.modelData.title : ""
                                color: Qt.rgba(1, 1, 1, 0.6)
                                elide: Text.ElideRight
                                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.7)
                            }
                        }
                    }

                    MouseArea {
                        id: cardArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: overlay.activateLetter(card.modelData.letter)
                    }
                }
            }
        }
    }
}
