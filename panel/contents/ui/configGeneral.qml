import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// 外观设置。
//
// 用 KCM.SimpleKCM 而不是自己写标题：页面标题、四周留白、滚动都由 KCM 框架渲染，
// 这样与 Plasma 内置的配置页（比如「键盘快捷键」）视觉一致。
// 之前手写 Kirigami.Heading，字号粗细和留白都对不上，就是这个原因。
//
// 这几项都由浮层消费，所以本组件会把它们推给 helper，再由浮层读走：
// 设置页 → 面板组件 → helper(Config) → 快照里的 @config 行 → 浮层。
KCM.SimpleKCM {
    id: page

    title: "外观"

    property alias cfg_overlayPosition: positionBox.currentValue
    property alias cfg_maxColumns: columnsBox.value
    property alias cfg_showWindowTitle: titleBox.checked

    Kirigami.FormLayout {
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
}
