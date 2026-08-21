import QtQuick
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    property string label: ""
    property string iconSource: ""
    property real value: 0.5
    property real from: 0
    property real to: 1
    property real knobRadius: 7

    readonly property real clampedFraction: root.to !== root.from ? Math.max(0, Math.min(1, (root.value - root.from) / (root.to - root.from))) : 0

    Item {
        id: iconSlot

        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }

        width: 28
        height: 28

        IconImage {
            anchors.centerIn: parent

            width: 24
            height: 24

            source: root.iconSource
            asynchronous: true
            visible: root.iconSource !== ""
        }
    }

    Rectangle {
        id: track

        anchors {
            left: iconSlot.right
            right: parent.right
            verticalCenter: parent.verticalCenter
        }

        anchors.leftMargin: 10

        height: 6
        radius: 3
        color: Qt.lighter(Theme.surface, 1.35)

        Rectangle {
            id: fill

            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }

            width: track.width * root.clampedFraction

            radius: 3
            color: Theme.accent
        }

        Rectangle {
            id: knob

            anchors.verticalCenter: track.verticalCenter

            x: Math.max(0, Math.min(track.width - root.knobRadius * 2, fill.width - root.knobRadius))

            visible: fill.width > 2

            width: root.knobRadius * 2
            height: root.knobRadius * 2
            radius: root.knobRadius
            color: Theme.text
        }

        MouseArea {
            id: dragArea

            anchors.fill: parent

            cursorShape: Qt.PointingHandCursor

            onPressed: root.setFromPointer(mouse.x)
            onPositionChanged: if (dragArea.pressed) root.setFromPointer(mouse.x)
        }
    }

    function setFromPointer(px) {
        const range = root.to - root.from
        const f = Math.max(0, Math.min(1, px / track.width))
        root.value = root.from + f * range
    }
}