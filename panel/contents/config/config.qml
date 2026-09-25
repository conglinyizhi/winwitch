import QtQuick
import org.kde.plasma.configuration

// 设置页入口。Plasma 会在配置对话框里列出这里声明的分类。
ConfigModel {
    ConfigCategory {
        name: "外观"
        icon: "preferences-desktop-theme"
        source: "configGeneral.qml"
    }
}
