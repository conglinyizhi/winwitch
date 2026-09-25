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

    // 下拉框不能用 property alias 指到 ComboBox.currentValue：那是控件内部属性，
    // 别名解析不到，KCM 加载时会报 Setting initial properties failed，
    // 整页的值既读不出也存不进（症状就是「设置项改了没反应」）。
    // 照 KDE 自家设置页（kclock）的写法：普通属性 + onCurrentIndexChanged 回写。
    property string cfg_overlayPosition
    property string cfg_backgroundStyle
    property alias cfg_maxColumns: columnsBox.value
    property alias cfg_showWindowTitle: titleBox.checked

    // 按值找下拉项下标；找不到就落到第一项。
    function indexOfValue(box, value) {
        for (var i = 0; i < box.model.length; i++) {
            if (box.model[i].value === value) {
                return i;
            }
        }
        return 0;
    }

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
            onCurrentIndexChanged: page.cfg_overlayPosition = currentValue
            Component.onCompleted: currentIndex = page.indexOfValue(positionBox,
                                                                    page.cfg_overlayPosition)
        }

        QQC2.SpinBox {
            id: columnsBox

            Kirigami.FormData.label: "最多列数"
            from: 1
            to: 8
        }

        QQC2.CheckBox {
            id: titleBox

            Kirigami.FormData.label: "显示窗口标题"
            text: "在应用名下面显示窗口标题"
        }

        QQC2.ComboBox {
            id: styleBox

            Kirigami.FormData.label: "背景风格"
            textRole: "text"
            valueRole: "value"
            model: [
                { value: "translucent", text: "半透明（能透出桌面）" },
                { value: "opaque", text: "完全不透明" }
            ]
            onCurrentIndexChanged: page.cfg_backgroundStyle = currentValue
            Component.onCompleted: currentIndex = page.indexOfValue(styleBox,
                                                                    page.cfg_backgroundStyle)
        }
    }
}
