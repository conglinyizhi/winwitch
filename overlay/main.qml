import QtQuick
import QtQuick.Window
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// 字母切窗 · 浮层
//
// 独立进程，不是面板组件：选择模式期间浮出一排卡片，每张卡片说明
// 「这个字母对应哪个窗口」（字母 + 图标 + 标题），结束后消失。
// 用 qml6 运行：qml6 /path/to/main.qml
Window {
    id: overlay

    // 不抢焦点：否则浮层一出现就把当前窗口的焦点拿走，接着按字母会打到浮层上。
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    title: "字母切窗"

    property bool selecting: false
    property string token: ""
    // 每行 { letter, title, appId }
    property var rows: []

    readonly property string serviceName: "org.clyzhi.LetterSwitch"
    readonly property string objectPath: "/LetterSwitch"
    readonly property string interfaceName: "org.clyzhi.LetterSwitch"
    readonly property string selectingPrefix: "selecting:"
    readonly property string idlePrefix: "idle:"

    // 兜底时长。KWin 脚本里的 callLater 实测会漏触发，所以看门狗放在这里。
    readonly property int selectionTimeoutMs: 8000
    property double selectingSince: 0

    readonly property int cardWidth: Math.round(Kirigami.Units.gridUnit * 11)
    readonly property int cardHeight: Math.round(Kirigami.Units.gridUnit * 2.2)
    readonly property int cardSpacing: Math.round(Kirigami.Units.smallSpacing)
    readonly property int cardPadding: Kirigami.Units.smallSpacing * 2

    // 每行最多放几张卡片，避免宽屏上排成一条长龙。
    readonly property int maxColumns: Math.max(1, Math.min(6,
        Math.floor((screen.width * 0.7) / (cardWidth + cardSpacing))))
    readonly property int columns: Math.max(1, Math.min(maxColumns, rows.length))
    readonly property int gridWidth: columns * cardWidth + (columns - 1) * cardSpacing

    property int pollFailures: 0
    property bool useGdbus: false
    property bool announced: false

    visible: overlay.selecting && overlay.rows.length > 0
    width: gridWidth + cardPadding * 2
    height: grid.implicitHeight + cardPadding * 2

    // 默认放在当前屏幕底部中间（任务栏上方）。要换位置改这两行即可。
    x: Math.round((screen.width - width) / 2)
    y: Math.round(screen.height - height - Kirigami.Units.gridUnit * 4)

    function statusCommand() {
        if (overlay.useGdbus) {
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

    function watchdogCancel() {
        var t = overlay.token;
        overlay.selectingSince = 0;
        if (t !== "") {
            actionSource.connectSource("qdbus6 " + overlay.serviceName + " " + overlay.objectPath
                                       + " " + overlay.interfaceName + ".Cancel " + t);
        }
    }

    // 解析快照：第一行状态，其余每行 `字母\ttitle\tapp_id`。
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
            var parts = assignment.replace(/\\t/g, "\t").split("\t");
            for (var i = 0; i < parts.length; i++) {
                var eq = parts[i].indexOf("=");
                if (eq > 0) {
                    letters.push(parts[i].substring(0, eq));
                }
            }

            // 明细行：字母、标题、应用标识
            var parsed = [];
            for (var j = 1; j < lines.length; j++) {
                var row = lines[j].split("\t");
                if (row.length >= 1 && row[0] !== "") {
                    parsed.push({
                        letter: row[0],
                        title: row.length > 1 ? row[1] : "",
                        appId: row.length > 2 ? row[2] : ""
                    });
                }
            }
            // helper 没给明细时，至少把字母显示出来
            if (parsed.length === 0) {
                for (var k = 0; k < letters.length; k++) {
                    parsed.push({ letter: letters[k], title: "", appId: "" });
                }
            }

            var wasSelecting = overlay.selecting;
            overlay.rows = parsed;
            overlay.selecting = true;
            if (!wasSelecting) {
                overlay.selectingSince = Date.now();
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
            overlay.selectingSince = 0;
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

    function pollStatus() {
        commandSource.connectSource(overlay.statusCommand());
    }

    // 点卡片等于触发对应的 KWin 快捷键，激活逻辑只留在 KWin 那一侧。
    function activateLetter(letter) {
        actionSource.connectSource(
            "qdbus6 org.kde.kglobalaccel /component/kwin "
            + "org.kde.kglobalaccel.Component.invokeShortcut \"字母切窗 " + letter + "\"");
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

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (!overlay.selecting) {
                overlay.selectingSince = 0;
                return;
            }
            if (overlay.selectingSince === 0) {
                overlay.selectingSince = Date.now();
                return;
            }
            if (Date.now() - overlay.selectingSince > overlay.selectionTimeoutMs) {
                overlay.report("overlay-watchdog-timeout");
                overlay.watchdogCancel();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.smallSpacing
        color: Qt.rgba(0.09, 0.09, 0.11, 0.94)
        border.width: 1
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
                        anchors.margins: Math.round(Kirigami.Units.smallSpacing * 0.75)
                        spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

                        // 字母
                        Rectangle {
                            width: card.height - Kirigami.Units.smallSpacing
                            height: width
                            radius: 3
                            color: cardArea.containsMouse ? "#ffd977" : "#f5c542"
                            border.width: 1
                            border.color: "#8a6d1a"

                            Text {
                                anchors.centerIn: parent
                                text: card.modelData.letter
                                color: "#1a1a1a"
                                font.bold: true
                                font.pixelSize: Math.round(parent.height * 0.62)
                            }
                        }

                        // 应用图标
                        Kirigami.Icon {
                            width: card.height - Kirigami.Units.smallSpacing
                            height: width
                            source: card.modelData.appId !== ""
                                    ? card.modelData.appId
                                    : "application-x-executable"
                        }

                        // 窗口标题
                        Text {
                            width: overlay.cardWidth - card.height * 2
                                   - Kirigami.Units.smallSpacing * 3
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.modelData.title
                            color: "#f0f0f0"
                            elide: Text.ElideRight
                            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.8)
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
