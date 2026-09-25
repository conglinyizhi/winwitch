import QtQuick
import org.kde.kirigami as Kirigami

// 单个窗口图标 + 右上角字母标签。
//
// 标签只占叠加层，不参与布局：图标位置与尺寸与没有标签时完全一致，
// 因此选择模式开关不会让任务栏重新排布。
Item {
    id: delegate

    required property int index
    required property string label
    required property bool labelVisible
    required property string iconName
    required property bool active

    signal activateRequested(int index)

    implicitWidth: Math.round(Kirigami.Units.iconSizes.medium * 1.2)
    implicitHeight: Math.round(Kirigami.Units.iconSizes.medium * 1.2)

    Rectangle {
        id: highlight

        anchors.fill: parent
        anchors.margins: 1
        radius: 3
        color: delegate.active ? Kirigami.Theme.highlightColor : "transparent"
        opacity: delegate.active ? 0.35 : 0
    }

    Image {
        id: icon

        anchors.centerIn: parent
        width: Math.round(parent.height * 0.72)
        height: width
        source: delegate.iconName === "" ? "" : "image://icon/" + delegate.iconName
        sourceSize.width: width
        sourceSize.height: height
        smooth: true
    }

    // 字母标签：贴着图标右上角。
    Rectangle {
        id: badge

        visible: delegate.labelVisible && delegate.label !== ""
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 0
        anchors.topMargin: 0
        width: Math.max(badgeText.implicitWidth + 6, 14)
        height: Math.max(badgeText.implicitHeight + 2, 14)
        radius: 3
        color: "#f5c542"
        border.width: 1
        border.color: "#8a6d1a"

        Text {
            id: badgeText

            anchors.centerIn: parent
            text: delegate.label
            color: "#1a1a1a"
            font.bold: true
            font.pixelSize: Math.round(badge.height * 0.68)
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: delegate.activateRequested(delegate.index)
    }
}
