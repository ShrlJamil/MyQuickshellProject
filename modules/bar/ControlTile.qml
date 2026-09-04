import QtQuick
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    property string label: ""
    property string iconSource: ""
    property bool active: false
    property bool round: false

    readonly property real cornerRadius: root.round ? Math.min(root.width, root.height) / 2 : 22
    readonly property real radius: root.cornerRadius

    readonly property real iconSlotSize: root.round ? Math.max(26, Math.round(Math.min(root.width, root.height) * 0.4)) : 34
    readonly property real iconSize: root.round ? Math.max(22, Math.round(Math.min(root.width, root.height) * 0.34)) : 30
    readonly property int labelPixelSize: root.round ? Math.max(9, Math.min(12, Math.round(Math.min(root.width, root.height) * 0.12))) : 12

    Rectangle {
        id: tile

        anchors.fill: parent

        radius: root.cornerRadius
        border.width: 0
        border.color: "transparent"
        color: {
            if (root.active)
                return hover.hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
            return hover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background
        }

        HoverHandler {
            id: hover

            cursorShape: Qt.PointingHandCursor
        }

        Item {
            anchors.centerIn: parent

            width: root.iconSlotSize
            height: root.iconSlotSize

            IconImage {
                anchors.centerIn: parent

                width: root.iconSize
                height: root.iconSize

                source: root.iconSource
                asynchronous: true
                visible: root.iconSource !== ""
            }
        }
    }
}