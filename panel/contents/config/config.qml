// SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.plasma.configuration

// 设置页入口。Plasma 会在配置对话框里列出这里声明的分类。
ConfigModel {
    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-theme"
        source: "configGeneral.qml"
    }

    // 启动确认时间这类操作手感项归这里，别再往「外观」里塞：
    // 改它的人找的是行为，不是配色。
    ConfigCategory {
        name: i18n("Behavior")
        icon: "preferences-system"
        source: "configBehavior.qml"
    }
}
