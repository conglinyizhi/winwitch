import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// 字母条：显示当前选择模式下可用的字母。
//
// 刻意只显示「字母」，不显示「字母对应哪个窗口」。KWin 枚举窗口的顺序与
// 任务栏模型的手工排序未必一致，硬把它们对应起来会显示错误的映射；
// 精确到图标的标签要由替代任务栏的组件来做。
PlasmoidItem {
    id: root

    property bool selecting: false
    property string token: ""
    property var letters: []

    readonly property string serviceName: "org.clyzhi.LetterSwitch"
    readonly property string objectPath: "/LetterSwitch"
    readonly property string interfaceName: "org.clyzhi.LetterSwitch"

    property int pollFailures: 0
    property bool useGdbus: false

    function statusCommand() {
        if (root.useGdbus) {
            return "gdbus call --session --dest " + root.serviceName
                 + " --object-path " + root.objectPath
                 + " --method " + root.interfaceName + ".Status";
        }
        return "qdbus6 " + root.serviceName + " " + root.objectPath
             + " " + root.interfaceName + ".Status";
    }

    // 从 `selecting:<token>:A=w1\tS=w2` 里取出 token 与字母序列。
    function applyStatus(raw) {
        var line = (raw || "").trim();
        // gdbus 的返回形如 ('selecting:t1:A=w1',)，取出引号内的内容。
        var firstQuote = line.indexOf("'");
        if (firstQuote >= 0) {
            var lastQuote = line.lastIndexOf("'");
            if (lastQuote > firstQuote) {
                line = line.substring(firstQuote + 1, lastQuote);
            }
        }

        if (line.indexOf("idle:") === 0) {
            root.pollFailures = 0;
            root.setIdle();
            return;
        }
        if (line.indexOf("selecting:") !== 0) {
            root.pollFailures += 1;
            if (root.pollFailures === 5 && !root.useGdbus) {
                root.useGdbus = true;
                console.warn("letterswitch: qdbus6 查询失败，改用 gdbus");
            }
            return;
        }

        root.pollFailures = 0;
        var rest = line.substring("selecting:".length());
        var colon = rest.indexOf(":");
        var assignment = "";
        if (colon >= 0) {
            root.token = rest.substring(0, colon);
            assignment = rest.substring(colon + 1);
        } else {
            root.token = rest;
        }

        var found = [];
        var parts = assignment.split("\t");
        for (var i = 0; i < parts.length; i++) {
            var eq = parts[i].indexOf("=");
            if (eq > 0) {
                found.push(parts[i].substring(0, eq));
            }
        }
        root.letters = found;
        root.selecting = true;
    }

    function setIdle() {
        root.selecting = false;
        root.token = "";
        root.letters = [];
    }

    function pollStatus() {
        commandSource.connectSource(root.statusCommand());
    }

    // 点字母等于触发对应的 KWin 快捷键，激活逻辑只保留在 KWin 那一侧。
    function activateLetter(letter) {
        commandSource.connectSource(
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
            root.applyStatus(out);
        }
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: root.pollStatus()
    }

    compactRepresentation: RowLayout {
        spacing: 2

        // 空闲时留一个很淡的图标，既能看出组件在哪，也不抢视线。
        Kirigami.Icon {
            visible: !root.selecting
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: "preferences-system-windows"
            opacity: 0.35
        }

        Repeater {
            model: root.selecting ? root.letters : []

            Rectangle {
                id: chip

                required property string modelData

                Layout.preferredWidth: Math.max(chipText.implicitWidth + 8, 16)
                Layout.preferredHeight: Math.max(chipText.implicitHeight + 2, 16)
                radius: 3
                color: chipArea.containsMouse ? "#ffd977" : "#f5c542"
                border.width: 1
                border.color: "#8a6d1a"

                Behavior on color {
                    ColorAnimation {
                        duration: 80
                    }
                }

                Text {
                    id: chipText

                    anchors.centerIn: parent
                    text: chip.modelData
                    color: "#1a1a1a"
                    font.bold: true
                    font.pixelSize: Math.round(parent.height * 0.68)
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

    toolTipMainText: "字母切窗"
    toolTipSubText: root.selecting
        ? "选择中：按字母切换窗口，Esc 取消"
        : "空闲。按 Meta+F 进入选择模式"
}
