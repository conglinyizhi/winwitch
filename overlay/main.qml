import QtQuick
import QtQuick.Window
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// 字母切窗 · 浮层
//
// 独立进程，不是面板组件：选择模式期间浮出一排卡片，说明「这个字母对应哪个窗口」
// （字母 + 图标 + 应用名 + 窗口标题），结束后消失。
// 用 qml6 运行：qml6 /path/to/main.qml
//
// 刻意没有自动超时：退出只靠 Esc 或选中某个字母。之前加过 8 秒兜底，提督明确不要。
Window {
    id: overlay

    // 选择模式期间要收键盘，所以窗口必须能拿焦点；不显示时它只是个隐藏窗口，
    // 不会干扰任何东西。
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: "字母切窗"

    property bool selecting: false
    property string token: ""
    // 每行 { letter, title, appName, iconName }
    property var rows: []

    readonly property string serviceName: "org.clyzhi.LetterSwitch"
    readonly property string objectPath: "/LetterSwitch"
    readonly property string interfaceName: "org.clyzhi.LetterSwitch"
    readonly property string selectingPrefix: "selecting:"
    readonly property string idlePrefix: "idle:"

    readonly property int cardWidth: Math.round(Kirigami.Units.gridUnit * 12)
    readonly property int cardHeight: Math.round(Kirigami.Units.gridUnit * 2.6)
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

            // 明细行：字母、应用名、图标名、窗口标题
            var parsed = [];
            for (var j = 1; j < lines.length; j++) {
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

                        // 图标名可能是主题名，也可能是绝对路径（desktop 文件里直接写的文件），
                        // 后者要转成 URL 才能被 Icon 加载。
                        Kirigami.Icon {
                            width: card.height - Kirigami.Units.smallSpacing
                            height: width
                            source: overlay.iconSource(card.modelData.iconName)
                            fallback: "application-x-executable"
                        }

                        Column {
                            width: overlay.cardWidth - card.height
                                   - Kirigami.Units.smallSpacing * 3
                            anchors.verticalCenter: parent.verticalCenter

                            // 应用名：这是「这是什么程序」，放显眼位置
                            Text {
                                width: parent.width
                                text: card.modelData.appName !== ""
                                      ? card.modelData.appName
                                      : card.modelData.title
                                color: "#ffffff"
                                elide: Text.ElideRight
                                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.85)
                                font.bold: true
                            }

                            // 窗口标题：次要信息，缺省不占位
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: (card.modelData.appName !== "" && card.modelData.appName !== card.modelData.title)
                                      ? card.modelData.title : ""
                                color: Qt.rgba(1, 1, 1, 0.62)
                                elide: Text.ElideRight
                                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.68)
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
