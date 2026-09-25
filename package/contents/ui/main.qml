import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// 字母条：显示当前选择模式下可用的字母。
//
// 只显示「字母」，不显示「字母对应哪个窗口」：KWin 枚举窗口的顺序与任务栏模型的
// 手工排序未必一致，硬对应会显示错误映射。精确到图标的标签要由替代任务栏的组件做。
PlasmoidItem {
    id: root

    property bool selecting: false
    property string token: ""
    property var letters: []

    readonly property string serviceName: "io.github.conglinyizhi.winwitch"
    readonly property string objectPath: "/winwitch"
    readonly property string interfaceName: "io.github.conglinyizhi.winwitch"

    // "selecting:" 共 10 个字符
    readonly property int selectingPrefixLength: 10

    // 选择模式的兜底时长。KWin 侧的定时器在本机表现不稳定，所以界面侧另设看门狗，
    // 只要组件在跑，选择模式就不会永久停住。
    readonly property int selectionTimeoutMs: 8000
    property double selectingSince: 0

    readonly property int chipHeight: Kirigami.Units.iconSizes.small
    readonly property int chipFontSize: Math.max(10, Math.round(chipHeight * 0.62))

    property int pollFailures: 0
    property bool useGdbus: false
    // 加载标记：面板上跑的到底是哪一版，看一眼 helper 日志就知道
    property bool announced: false

    function statusCommand() {
        if (root.useGdbus) {
            return "gdbus call --session --dest " + root.serviceName
                 + " --object-path " + root.objectPath
                 + " --method " + root.interfaceName + ".Status";
        }
        return "qdbus6 " + root.serviceName + " " + root.objectPath
             + " " + root.interfaceName + ".Status";
    }

    function cancelCommand() {
        return "qdbus6 " + root.serviceName + " " + root.objectPath
             + " " + root.interfaceName + ".Cancel " + root.token;
    }

    // 界面 → helper 的上报：面板里的 console 既不保证进 journal，也不保证不抛错，
    // 所以日志统一走 helper。文本不含空格与引号，避免命令被拆错。
    function report(text) {
        noteSource.connectSource("qdbus6 " + root.serviceName + " " + root.objectPath
                                 + " " + root.interfaceName + ".Note " + text);
    }

    // 超时兜底：不等 KWin 的定时器，界面自己决定什么时候收手。
    function watchdogCancel() {
        var t = root.token;
        root.selectingSince = 0;
        if (t !== "") {
            actionSource.connectSource("qdbus6 " + root.serviceName + " " + root.objectPath
                                       + " " + root.interfaceName + ".Cancel " + t);
        }
    }

    function applyStatus(raw) {
        var text = (raw || "").trim();

        // gdbus 返回形如 ('selecting:t1:A=w1',)，取出引号内的内容。
        var firstQuote = text.indexOf("'");
        if (firstQuote >= 0) {
            var lastQuote = text.lastIndexOf("'");
            if (lastQuote > firstQuote) {
                text = text.substring(firstQuote + 1, lastQuote);
            }
        }

        // 快照可能带明细行（字母\ttitle\tapp_id）；这个组件只关心状态行。
        var newline = text.indexOf("\n");
        var line = newline >= 0 ? text.substring(0, newline) : text;

        var isSelecting = line.indexOf("selecting:") === 0;
        var isIdle = line.indexOf("idle:") === 0;

        if (isSelecting || isIdle) {
            root.pollFailures = 0;
            if (!root.announced) {
                root.announced = true;
                root.report("strip-loaded-build5");
            }
        }

        if (isSelecting) {
            var rest = line.substring(root.selectingPrefixLength);
            var colon = rest.indexOf(":");
            var assignment = "";
            if (colon >= 0) {
                root.token = rest.substring(0, colon);
                assignment = rest.substring(colon + 1);
            } else {
                root.token = rest;
            }

            var found = [];
            // qdbus6 输出真实制表符；gdbus 的 GVariant 文本会把制表符转义成字面的 \t
            // （两个字符）。两种都归一化后再切分。
            var normalized = assignment.replace(/\\t/g, "\t");
            var parts = normalized.split("\t");
            for (var i = 0; i < parts.length; i++) {
                var eq = parts[i].indexOf("=");
                if (eq > 0) {
                    found.push(parts[i].substring(0, eq));
                }
            }

            var wasSelecting = root.selecting;
            root.letters = found;
            root.selecting = true;
            if (!wasSelecting) {
                root.selectingSince = Date.now();
                root.report("strip-selecting-token=" + root.token + "-letters=" + found.join(""));
            }
            return;
        }

        if (isIdle) {
            var wasIdle = !root.selecting;
            root.selecting = false;
            root.token = "";
            root.letters = [];
            root.selectingSince = 0;
            if (!wasIdle) {
                root.report("strip-idle");
            }
            return;
        }

        // 既不是 idle 也不是 selecting：命令没跑起来，或者输出不是我们认识的格式。
        root.pollFailures += 1;
        if (root.pollFailures === 5) {
            root.report("strip-poll-failed-raw=" + (line === "" ? "empty" : line));
            if (!root.useGdbus) {
                root.useGdbus = true;
                root.report("strip-switch-to-gdbus");
            }
        }
        if (root.pollFailures >= 20) {
            root.pollFailures = 0;
        }
    }

    function pollStatus() {
        commandSource.connectSource(root.statusCommand());
    }

    // 点字母等于触发对应的 KWin 快捷键，激活逻辑只保留在 KWin 那一侧。
    function activateLetter(letter) {
        actionSource.connectSource(
            "qdbus6 org.kde.kglobalaccel /component/kwin "
            + "org.kde.kglobalaccel.Component.invokeShortcut \"WinWitch " + letter + "\"");
    }

    P5Support.DataSource {
        id: commandSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            var out = data && data["stdout"] ? data["stdout"] : "";
            commandSource.disconnectSource(sourceName);
            root.applyStatus(out);
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
        onTriggered: root.pollStatus()
    }

    // 看门狗：每秒检查一次，选择模式超时就自己撤。
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (!root.selecting) {
                root.selectingSince = 0;
                return;
            }
            if (root.selectingSince === 0) {
                root.selectingSince = Date.now();
                return;
            }
            if (Date.now() - root.selectingSince > root.selectionTimeoutMs) {
                root.report("strip-watchdog-timeout");
                root.watchdogCancel();
            }
        }
    }

    compactRepresentation: Row {
        spacing: 2

        // 空闲时留一个很淡的图标，既能看出组件在哪，也不抢视线。
        Kirigami.Icon {
            visible: !root.selecting
            width: root.chipHeight
            height: root.chipHeight
            source: "preferences-system-windows"
            opacity: 0.35
        }

        Repeater {
            model: root.selecting ? root.letters : []

            Rectangle {
                id: chip

                required property string modelData

                width: Math.max(chipText.implicitWidth + 8, root.chipHeight)
                height: root.chipHeight
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
                    font.pixelSize: root.chipFontSize
                }

                MouseArea {
                    id: chipArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activateLetter(chip.modelData)
                }
            }
        }
    }

    fullRepresentation: compactRepresentation

    toolTipMainText: "WinWitch"
    toolTipSubText: root.selecting
        ? "选择中：" + root.letters.join(" ") + "　按字母切换窗口，Esc 取消"
        : "空闲。按 Meta+F 进入选择模式"
}
