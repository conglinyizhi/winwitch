import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami

// 任务栏（图标模式）+ 字母标签叠加层。
//
// 只负责显示：字母分配规则与 core 的 default_alphabet 一致，
// 「是否处于选择模式」由 MoonBit helper 通过 D-Bus 给出。
// 这里不比较窗口 ID，跨进程只对齐「任务顺序」这一件事。
PlasmoidItem {
    id: root

    // 与 core 中的 default_alphabet 保持一致。
    readonly property string alphabet: "ASDFGHJKLQWERTYUIOPZXCVBNM"

    property bool selecting: false
    property string sessionToken: ""
    property int pollFailures: 0
    property bool useGdbus: false

    readonly property string serviceName: "org.clyzhi.LetterSwitch"
    readonly property string objectPath: "/LetterSwitch"
    readonly property string interfaceName: "org.clyzhi.LetterSwitch"

    function labelForIndex(index) {
        if (!root.selecting) {
            return "";
        }
        if (index < 0 || index >= root.alphabet.length) {
            return "";
        }
        return root.alphabet.charAt(index);
    }

    function statusCommand() {
        if (root.useGdbus) {
            return "gdbus call --session --dest " + root.serviceName
                 + " --object-path " + root.objectPath
                 + " --method " + root.interfaceName + ".Status";
        }
        return "qdbus6 " + root.serviceName + " " + root.objectPath
             + " " + root.interfaceName + ".Status";
    }

    function applyStatus(text) {
        var line = (text || "").trim();
        // gdbus 的返回形如 ('selecting:t1:A=w1\tS=w2',)，取引号里的内容。
        var quoted = line.indexOf("'");
        if (quoted >= 0) {
            var endQuote = line.lastIndexOf("'");
            if (endQuote > quoted) {
                line = line.substring(quoted + 1, endQuote);
            }
        }
        if (line.indexOf("selecting:") === 0) {
            var rest = line.substring("selecting:".length());
            var colon = rest.indexOf(":");
            root.sessionToken = colon >= 0 ? rest.substring(0, colon) : rest;
            root.selecting = true;
            root.pollFailures = 0;
        } else if (line.indexOf("idle:") === 0) {
            root.selecting = false;
            root.sessionToken = "";
            root.pollFailures = 0;
        } else {
            root.registerPollFailure();
        }
    }

    // helper 未运行时不要刷屏，也不要永远空等：连续失败后换一次查询工具，
    // 再失败就保持空闲状态（标签隐藏是安全的默认值）。
    function registerPollFailure() {
        root.pollFailures += 1;
        if (root.pollFailures === 5 && !root.useGdbus) {
            root.useGdbus = true;
            console.warn("letterswitch: qdbus6 查询失败，改用 gdbus");
        }
    }

    function pollStatus() {
        commandSource.connectSource(root.statusCommand());
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

    TaskManager.TasksModel {
        id: tasksModel
    }

    Component.onCompleted: {
        // 这些属性在不同 Plasma 6 小版本上未必都存在，逐项确认后再设。
        if (tasksModel.filterByCurrentDesktop !== undefined) {
            tasksModel.filterByCurrentDesktop = true;
        }
        if (tasksModel.filterByActivity !== undefined) {
            tasksModel.filterByActivity = true;
        }
    }

    compactRepresentation: RowLayout {
        spacing: 0

        Repeater {
            model: tasksModel

            TaskDelegate {
                required property int index
                required property var model

                label: root.labelForIndex(index)
                labelVisible: root.selecting
                iconName: model.decoration !== undefined && model.decoration !== null
                          ? String(model.decoration) : ""
                active: model.IsActive !== undefined ? Boolean(model.IsActive) : false

                onActivateRequested: function (taskIndex) {
                    if (tasksModel.requestActivate && tasksModel.index) {
                        tasksModel.requestActivate(tasksModel.index(taskIndex, 0));
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }

    fullRepresentation: compactRepresentation
}
