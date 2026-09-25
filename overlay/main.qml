import QtQuick
import QtQuick.Window
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// 字母切窗 · 浮层
//
// 独立进程，不是面板组件：选择模式期间在屏幕上浮出一排字母，结束后消失。
// 只显示字母，不显示字母对应哪个窗口——KWin 枚举窗口的顺序与任务栏手工排序
// 未必一致，硬对应会给出错误映射。
//
// 用 qml6 运行：qml6 /path/to/main.qml
Window {
    id: overlay

    // 不抢焦点：否则浮层一出现就把当前窗口的焦点拿走，接着按字母会打到浮层上。
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    title: "字母切窗"

    property bool selecting: false
    property string token: ""
    property var letters: []

    readonly property string serviceName: "org.clyzhi.LetterSwitch"
    readonly property string objectPath: "/LetterSwitch"
    readonly property string interfaceName: "org.clyzhi.LetterSwitch"
    readonly property int selectingPrefixLength: 10

    // 兜底时长。KWin 脚本里的 callLater 实测会漏触发，所以看门狗放在这里。
    readonly property int selectionTimeoutMs: 8000
    property double selectingSince: 0

    readonly property int chipHeight: Math.round(Kirigami.Units.gridUnit * 1.7)
    readonly property int cardPadding: Kirigami.Units.smallSpacing * 2

    property int pollFailures: 0
    property bool useGdbus: false
    property bool announced: false

    // 只有真的有字母要显示时才出现，避免闪一个空框
    visible: overlay.selecting && overlay.letters.length > 0
    width: Math.max(row.implicitWidth + cardPadding * 2, 1)
    height: Math.max(row.implicitHeight + cardPadding * 2, 1)

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

    // 独立进程没有面板的 console 限制，但日志仍统一走 helper，方便一处排查。
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

    function applyStatus(raw) {
        var line = (raw || "").trim();

        var firstQuote = line.indexOf("'");
        if (firstQuote >= 0) {
            var lastQuote = line.lastIndexOf("'");
            if (lastQuote > firstQuote) {
                line = line.substring(firstQuote + 1, lastQuote);
            }
        }

        var isSelecting = line.indexOf("selecting:") === 0;
        var isIdle = line.indexOf("idle:") === 0;

        if (isSelecting || isIdle) {
            overlay.pollFailures = 0;
            if (!overlay.announced) {
                overlay.announced = true;
                overlay.report("overlay-ready");
            }
        }

        if (isSelecting) {
            var rest = line.substring(overlay.selectingPrefixLength);
            var colon = rest.indexOf(":");
            var assignment = "";
            if (colon >= 0) {
                overlay.token = rest.substring(0, colon);
                assignment = rest.substring(colon + 1);
            } else {
                overlay.token = rest;
            }

            var found = [];
            // qdbus6 输出真实制表符；gdbus 的 GVariant 文本会把制表符转义成字面的 \t
            var normalized = assignment.replace(/\\t/g, "\t");
            var parts = normalized.split("\t");
            for (var i = 0; i < parts.length; i++) {
                var eq = parts[i].indexOf("=");
                if (eq > 0) {
                    found.push(parts[i].substring(0, eq));
                }
            }

            var wasSelecting = overlay.selecting;
            overlay.letters = found;
            overlay.selecting = true;
            if (!wasSelecting) {
                overlay.selectingSince = Date.now();
                overlay.report("overlay-selecting-token=" + overlay.token
                               + "-letters=" + found.join(""));
            }
            return;
        }

        if (isIdle) {
            var wasIdle = !overlay.selecting;
            overlay.selecting = false;
            overlay.token = "";
            overlay.letters = [];
            overlay.selectingSince = 0;
            if (!wasIdle) {
                overlay.report("overlay-idle");
            }
            return;
        }

        overlay.pollFailures += 1;
        if (overlay.pollFailures === 5) {
            overlay.report("overlay-poll-failed-raw=" + (line === "" ? "empty" : line));
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

    // 点字母等于触发对应的 KWin 快捷键，激活逻辑只留在 KWin 那一侧。
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

        Row {
            id: row

            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: overlay.letters

                Rectangle {
                    id: chip

                    required property string modelData

                    width: Math.max(chipText.implicitWidth + Kirigami.Units.smallSpacing * 2,
                                    overlay.chipHeight)
                    height: overlay.chipHeight
                    radius: 3
                    color: chipArea.containsMouse ? "#ffd977" : "#f5c542"
                    border.width: 1
                    border.color: "#8a6d1a"

                    Text {
                        id: chipText

                        anchors.centerIn: parent
                        text: chip.modelData
                        color: "#1a1a1a"
                        font.bold: true
                        font.pixelSize: Math.round(overlay.chipHeight * 0.58)
                    }

                    MouseArea {
                        id: chipArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: overlay.activateLetter(chip.modelData)
                    }
                }
            }
        }
    }
}
