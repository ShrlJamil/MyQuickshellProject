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

    readonly property real iconSlotSize: root.round ? Math.max(26, Math.round(Math.min(root.width, root.height) * 0.4)) : 34
    readonly property real iconSize: root.round ? Math.max(22, Math.round(Math.min(root.width, root.height) * 0.34)) : 30
    readonly property int labelPixelSize: root.round ? Math.max(9, Math.min(12, Math.round(Math.min(root.width, root.height) * 0.12))) : 12

    Rectangle {
        id: tile

        anchors.fill: parent

        radius: root.cornerRadius
        border.color: root.active ? Theme.accent : "transparent"
        border.width: 1
        color: hover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background

        HoverHandler {
            id: hover

            cursorShape: Qt.PointingHandCursor
        }

        Column {
            anchors.centerIn: parent

            width: parent.width - (root.round ? (root.labelPixelSize * 0.5) * 7 : 0)

            spacing: root.round ? 5 : 6

            Item {
                anchors.horizontalCenter: parent.horizontalCenter

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

            Text {
                anchors.horizontalCenter: parent.horizontalCenter

                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight

                text: root.label
                color: Theme.text
                font.pixelSize: root.labelPixelSize
                font.weight: Font.DemiBold
            }
        }
    }
}