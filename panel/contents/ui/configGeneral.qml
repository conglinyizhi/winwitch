import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// 外观设置。
//
// 用 KCM.SimpleKCM 而不是自己写标题：页面标题、四周留白、滚动都由 KCM 框架渲染，
// 这样与 Plasma 内置的配置页（比如「键盘快捷键」）视觉一致。
//
// 这几项都由浮层消费，所以本组件会把它们推给 helper，再由浮层读走：
// 设置页 → 面板组件 → helper(Config) → 快照里的 @config 行 → 浮层。
//
// 控件为什么不直接绑 cfg_<键>：框架把配置值赋给 cfg_<键> 的时机不保证，
// 而且控件自己初始化时会先跑到第 0 项——早期版本用
// `onCurrentIndexChanged: cfg_x = currentValue` 回写，初始化那一下就把配置里的值
// 冲成了列表第一项（位置被冲成 bottom，背景被冲成默认值，保存时那一项还会被当成
// 默认值删掉）。所以显示一律读 plasmoid.configuration（任何时候都是真值），
// 只在用户真的动了控件时才回写 cfg_<键>，保存交给框架。
KCM.SimpleKCM {
    id: page

    title: "外观"

    // 配置读取入口。脱离 Plasma 单独加载（检查脚本会这么干）时退化成空对象，
    // 所以这里用 typeof 判断而不是直接引用，避免 ReferenceError。
    readonly property var configSource: (typeof plasmoid !== "undefined" && plasmoid)
                                        ? plasmoid.configuration
                                        : ({})

    // 框架赋值的目标，保存时读的就是它们。初值取配置真值，两者一致。
    property string cfg_overlayPosition: page.configSource.overlayPosition || ""
    property int cfg_maxColumns: page.configSource.maxColumns || 6
    property bool cfg_showWindowTitle: page.configSource.showWindowTitle === undefined
                                       ? true
                                       : page.configSource.showWindowTitle
    property string cfg_backgroundStyle: page.configSource.backgroundStyle || "translucent"

    // 按值找下拉项下标；值对不上（配置里是空或旧值）就落到第一项。
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
            currentIndex: page.indexOfValue(positionBox, page.configSource.overlayPosition)
            onActivated: page.cfg_overlayPosition = currentValue
        }

        QQC2.SpinBox {
            id: columnsBox

            Kirigami.FormData.label: "最多列数"
            from: 1
            to: 8
            value: page.configSource.maxColumns
            onValueModified: page.cfg_maxColumns = value
        }

        QQC2.CheckBox {
            id: titleBox

            Kirigami.FormData.label: "显示窗口标题"
            text: "在应用名下面显示窗口标题"
            checked: page.configSource.showWindowTitle
            onToggled: page.cfg_showWindowTitle = checked
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
            currentIndex: page.indexOfValue(styleBox, page.configSource.backgroundStyle)
            onActivated: page.cfg_backgroundStyle = currentValue
        }
    }
}
