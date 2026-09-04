import QtQuick
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    property string label: ""
    property string iconSource: ""
    property real value: 0
    property real from: 0
    property real to: 100
    property real knobRadius: 8
    property string rightText: ""

    signal moved(int value)
    signal iconActivated()

    property bool _active: false
    property real _pending: 0

    readonly property real _shown: root._active ? root._pending : root.value
    readonly property real clampedFraction: root.to !== root.from
        ? Math.max(0, Math.min(1, (root._shown - root.from) / (root.to - root.from)))
        : 0

    implicitHeight: 28

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

            width: 22
            height: 22

            source: root.iconSource
            asynchronous: true
            visible: root.iconSource !== ""
        }

        MouseArea {
            anchors.fill: parent

            cursorShape: Qt.PointingHandCursor

            onClicked: root.iconActivated()
        }
    }

    Text {
        id: valueLabel

        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }

        width: 46
        horizontalAlignment: Text.AlignRight

        visible: root.rightText !== ""
        text: root.rightText
        color: Theme.textMuted
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: track

        anchors {
            left: iconSlot.right
            right: root.rightText !== "" ? valueLabel.left : parent.right
            verticalCenter: parent.verticalCenter
        }

        anchors.leftMargin: 12
        anchors.rightMargin: root.rightText !== "" ? 12 : 0

        height: 6
        radius: 3
        color: Theme.surface

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
            width: root.knobRadius * 2
            height: root.knobRadius * 2
            radius: root.knobRadius
            color: Theme.text
        }

        MouseArea {
            id: dragArea

            anchors.fill: parent
            anchors.topMargin: -10
            anchors.bottomMargin: -10

            cursorShape: Qt.PointingHandCursor

            onPressed: (mouse) => {
                root._active = true
                root._apply(mouse.x)
            }

            onPositionChanged: (mouse) => {
                if (dragArea.pressed) root._apply(mouse.x)
            }

            onReleased: root._active = false
            onCanceled: root._active = false

            onWheel: (wheel) => {
                const step = wheel.angleDelta.y > 0 ? 5 : -5
                const nv = Math.max(root.from, Math.min(root.to, root.value + step))
                root.moved(Math.round(nv))
            }
        }
    }

    function _apply(px) {
        const f = Math.max(0, Math.min(1, px / track.width))
        root._pending = root.from + f * (root.to - root.from)
        root.moved(Math.round(root._pending))
    }
}
