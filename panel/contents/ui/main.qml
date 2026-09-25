import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.taskmanager as TaskManager

// 顺序源：把任务栏的窗口顺序推给字母切窗服务。
//
// 为什么必须有它：KWin 枚举窗口的顺序与任务栏图标顺序**不一致**（实测：任务栏第 0 位是
// 飞书，KWin 第 0 位是 Kate），所以只靠 KWin 无法让「A = 任务栏第一个窗口」成立。
// 而独立进程读不了任务模型（一实例化 TasksModel 就加载失败），只有面板里的组件能读。
//
// 本组件不绘制任何内容（零尺寸），只做这一件事。
PlasmoidItem {
    id: root

    // 实测值：WinIdList 给出的是与 KWin internalId 相同的 UUID，可以用来对齐。
    readonly property int winIdListRole: TaskManager.AbstractTasksModel.WinIdList

    property string lastPushed: ""

    P5Support.DataSource {
        id: orderSource

        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName) {
            orderSource.disconnectSource(sourceName);
        }
    }

    TaskManager.TasksModel {
        id: tasks
    }

    // 逐行取 WinIdList。注意不能用委托里的角色名：Qt6 下这套模型不把角色暴露成
    // 上下文属性，必须用 data(index, 角色枚举)。
    function collectOrder() {
        var ids = [];
        var count = tasks.count;
        for (var r = 0; r < count; r++) {
            var value;
            try {
                value = tasks.data(tasks.index(r, 0), root.winIdListRole);
            } catch (e) {
                continue;
            }
            if (value === undefined || value === null) {
                continue;
            }
            if (typeof value === "string") {
                if (value !== "") {
                    ids.push(value);
                }
            } else if (value.length !== undefined) {
                for (var i = 0; i < value.length; i++) {
                    ids.push(String(value[i]));
                }
            }
        }
        return ids;
    }

    function pushOrder() {
        var ids = root.collectOrder();
        if (ids.length === 0) {
            return;
        }
        // UUID 只含十六进制与短横线，逗号分隔即可，无需引号——命令是交给 shell 解释的。
        var payload = ids.join(",");
        if (payload === root.lastPushed) {
            return;
        }
        root.lastPushed = payload;
        orderSource.connectSource("qdbus6 org.clyzhi.LetterSwitch /LetterSwitch "
                                  + "org.clyzhi.LetterSwitch.Order " + payload);
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
