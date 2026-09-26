import QtQuick
import org.kde.plasma.configuration

// 设置页入口。Plasma 会在配置对话框里列出这里声明的分类。
ConfigModel {
    ConfigCategory {
        name: "外观"
        icon: "preferences-desktop-theme"
        source: "configGeneral.qml"
    }

    // 冷却时长这类操作手感项归这里，别再往「外观」里塞：
    // 改它的人找的是行为，不是配色。
    ConfigCategory {
        name: "行为"
        icon: "preferences-system"
        source: "configBehavior.qml"
    }
}
