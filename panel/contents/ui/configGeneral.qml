import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// 外观设置。
//
// 这几项都由浮层消费，所以本组件会把它们推给 helper，再由浮层读走：
// 设置页 → 面板组件 → helper(Config) → 快照里的 @config 行 → 浮层。
// 浮层是独立进程，读不到面板组件的配置，只能这样绕一道。
Item {
    id: page

    property alias cfg_overlayPosition: positionBox.currentValue
    property alias cfg_maxColumns: columnsBox.value
    property alias cfg_showWindowTitle: titleBox.checked

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.gridUnit

        // 配置对话框不会替我们加标题，自己写一个，和「关于」页对齐
        Kirigami.Heading {
            level: 2
            text: "外观"
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.ComboBox {
                id: positionBox

                Kirigami.FormData.label: "浮层位置"
                textRole: "text"
                valueRole: "value"
                model: [
                    { value: "bottom", text: "屏幕底部居中" },
                    { value: "center", text: "屏幕中央" },
                    { value: "top", text: "屏幕顶部居中" }
                ]
            }

            QQC2.SpinBox {
                id: columnsBox

                Kirigami.FormData.label: "最多几列"
                from: 1
                to: 8
            }

            QQC2.CheckBox {
                id: titleBox

                Kirigami.FormData.label: "显示窗口标题"
                text: "在应用名下面显示窗口标题"
            }
        }

        // 把表单顶到上方
        Item {
            Layout.fillHeight: true
        }
    }
}
