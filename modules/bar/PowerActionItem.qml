import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    property string actionId: ""
    property string label: ""
    property string iconSource: ""
    property bool selected: false
    property int holdDuration: 1000
    property bool isHolding: false
    property real progress: 0

    signal actionRequested(string actionId)

    function startHold() {
        if (root.isHolding || root.progress >= 1) return
        root.isHolding = true
        returnAnim.stop()
        holdAnim.from = root.progress
        holdAnim.duration = Math.max(1, Math.round((1 - root.progress) * root.holdDuration))
        holdAnim.start()
    }

    function cancelHold() {
        if (!root.isHolding || root.progress >= 1) return
        root.isHolding = false
        holdAnim.stop()
        returnAnim.from = root.progress
        returnAnim.duration = Math.round(root.progress * 200)
        returnAnim.start()
    }

    function finishHold() {
        if (!root.isHolding) return
        root.isHolding = false
        holdAnim.stop()
        root.progress = 1
        root.actionRequested(root.actionId)
    }

    function reset() {
        holdAnim.stop()
        returnAnim.stop()
        root.isHolding = false
        root.progress = 0
    }

    Item {
        id: visual

        anchors.fill: parent

        Rectangle {
            id: tileBase

            anchors.fill: parent

            radius: 12
            clip: true
            color: root.selected || hover.hovered || root.isHolding ? Theme.surfaceHover : "transparent"

            Rectangle {
                id: progressFill

                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }

                width: parent.width * root.progress
                radius: parent.radius

                visible: root.isHolding || root.progress > 0

                color: Theme.accent
                opacity: 0.35
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            width: parent.width - 28
            spacing: 20

            Item {
                width: parent.width
                height: 44

                Image {
                    id: iconImage

                    anchors.centerIn: parent

                    width: 26
                    height: 26

                    source: root.iconSource
                    sourceSize.width: 64
                    sourceSize.height: 64
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: false
                }

                ColorOverlay {
                    anchors.fill: iconImage

                    source: iconImage
                    color: "white"
                    visible: root.iconSource !== ""
                }
            }

            Text {
                width: parent.width

                text: root.label
                color: Theme.text
                font.pixelSize: 12
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor

        onHoveredChanged: {
            if (root.isHolding && !hover.hovered) root.cancelHold()
        }
    }

    TapHandler {
        id: tap

        onPressedChanged: {
            if (tap.pressed) root.startHold()
            else root.cancelHold()
        }

        onCanceled: root.cancelHold()
    }

    NumberAnimation {
        id: holdAnim

        target: root
        property: "progress"
        to: 1

        easing.type: Easing.Linear

        onFinished: root.finishHold()
    }

    NumberAnimation {
        id: returnAnim

        target: root
        property: "progress"
        to: 0

        duration: 200
        easing.type: Easing.OutCubic

        onFinished: root.progress = 0
    }
}