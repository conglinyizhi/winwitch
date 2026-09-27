// SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
// SPDX-License-Identifier: GPL-3.0-or-later

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

    title: i18n("Behavior")

    readonly property var configSource: (typeof plasmoid !== "undefined" && plasmoid)
                                        ? plasmoid.configuration
                                        : ({})

    property int cfg_armedMillis: page.configSource.armedMillis || 1200
    // 判 undefined 而不是用 ||：布尔默认值会被 false 绕过
    property bool cfg_minimizeActive: page.configSource.minimizeActive === undefined
                                      ? true
                                      : page.configSource.minimizeActive
    // 下面两项默认值一正一反，都按 undefined 判断：
    // 自动关闭默认开（失去焦点就该收），按键宽限默认关（它会改变手感）。
    property bool cfg_closeOnFocusLoss: page.configSource.closeOnFocusLoss === undefined
                                        ? true
                                        : page.configSource.closeOnFocusLoss
    property bool cfg_keyGuardEnabled: page.configSource.keyGuardEnabled === undefined
                                       ? false
                                       : page.configSource.keyGuardEnabled
    property int cfg_keyGuardMillis: page.configSource.keyGuardMillis || 300

    Kirigami.FormLayout {
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Selecting the foreground window:")

            text: i18n("Minimize it")
            checked: page.cfg_minimizeActive
            onToggled: page.cfg_minimizeActive = checked

            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("When off, selecting the foreground window just brings it back to front")
        }

        QQC2.SpinBox {
            id: armedSpin

            Kirigami.FormData.label: i18n("Launch confirm time:")

            from: 300
            to: 5000
            stepSize: 100
            editable: true
            value: page.cfg_armedMillis
            textFromValue: function (value) {
                return i18n("%1 ms", value);
            }
            valueFromText: function (text) {
                return parseInt(text, 10) || page.cfg_armedMillis;
            }

            // 只在用户真的动了控件时回写，初始化那一下不回写
            onValueModified: page.cfg_armedMillis = value

            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("A pinned app that isn't running needs a second press within this time")
        }

        QQC2.Label {
            text: i18n("Apps that aren't running need two presses")
            wrapMode: Text.WordWrap
            opacity: 0.7
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("On focus loss:")

            text: i18n("Close automatically")
            checked: page.cfg_closeOnFocusLoss
            onToggled: page.cfg_closeOnFocusLoss = checked
        }

        QQC2.CheckBox {
            id: keyGuardBox

            Kirigami.FormData.label: i18n("Ignore keys after opening:")

            text: i18n("Enable")
            checked: page.cfg_keyGuardEnabled
            onToggled: page.cfg_keyGuardEnabled = checked

            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("The overlay appears while your hands are still on the keyboard; this keeps the next key from being taken as a choice")
        }

        QQC2.SpinBox {
            id: keyGuardSpin

            Kirigami.FormData.label: i18n("Ignore duration:")

            from: 50
            to: 2000
            stepSize: 50
            editable: true
            enabled: page.cfg_keyGuardEnabled
            value: page.cfg_keyGuardMillis
            textFromValue: function (value) {
                return i18n("%1 ms", value);
            }
            valueFromText: function (text) {
                return parseInt(text, 10) || page.cfg_keyGuardMillis;
            }
            onValueModified: page.cfg_keyGuardMillis = value
        }
    }
}
