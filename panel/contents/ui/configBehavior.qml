import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// 行为设置：操作手感相关的项，与外观无关。
//
// 冷却时长由浮层消费，路径与外观项相同：
// 设置页 → 面板组件 → helper(Config) → 快照的 @config 行 → 浮层。
//
// 控件的读写规则见 configGeneral.qml 顶部注释：不要直接绑 cfg_<键>，
// 显示读 plasmoid.configuration，只在用户真的动了控件时才回写。
KCM.SimpleKCM {
    id: page

    title: "行为"

    readonly property var configSource: (typeof plasmoid !== "undefined" && plasmoid)
                                        ? plasmoid.configuration
                                        : ({})

    property int cfg_armedMillis: page.configSource.armedMillis || 1200
    // 判 undefined 而不是用 ||：布尔默认值会被 false 绕过
    property bool cfg_minimizeActive: page.configSource.minimizeActive === undefined
                                      ? true
                                      : page.configSource.minimizeActive

    Kirigami.FormLayout {
        QQC2.CheckBox {
            Kirigami.FormData.label: "选到已在前台的窗口："

            text: "最小化它"
            checked: page.cfg_minimizeActive
            onToggled: page.cfg_minimizeActive = checked

            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: "关掉的话，选到已在前台的窗口只是把它重新带到前台"
        }

        QQC2.SpinBox {
            id: armedSpin

            Kirigami.FormData.label: "启动器确认时间："

            from: 300
            to: 5000
            stepSize: 100
            editable: true
            value: page.cfg_armedMillis
            textFromValue: function (value) {
                return value + " 毫秒";
            }
            valueFromText: function (text) {
                return parseInt(text, 10) || page.cfg_armedMillis;
            }

            // 只在用户真的动了控件时回写，初始化那一下不回写
            onValueModified: page.cfg_armedMillis = value

            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: "固定但未启动的应用，第一次按下后等这么久；期间再按一次才启动"
        }

        QQC2.Label {
            text: "固定但没在运行的应用要按两次才启动，这里是两次之间的等待时间。"
            wrapMode: Text.WordWrap
            opacity: 0.7
        }
    }
}
