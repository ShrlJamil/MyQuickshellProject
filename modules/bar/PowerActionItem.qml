import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    property string actionId: ""
    property string label: ""
    property string iconSource: ""
    property string shortcutKey: ""
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

            // High-contrast hover: subtle outline so the focused tile pops
            // against the dark menu background.
            readonly property bool active: root.selected || hover.hovered || root.isHolding
            border.width: tileBase.active ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.15)

            Rectangle {
                id: progressFill

                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }

                width: parent.width * root.progress

                readonly property bool full: root.progress >= 0.999

                // Left edge hugs the frame's 12px corners; the advancing right
                // edge stays a flat 90 line until the fill is complete, then it
                // rounds too so the full bar seals cleanly inside the frame.
                radius: parent.radius
                topRightRadius: progressFill.full ? parent.radius : 0
                bottomRightRadius: progressFill.full ? parent.radius : 0

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
                    color: Theme.text
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

        // Hold-shortcut hint, tucked in the corner so it never disturbs the
        // centred icon + label.
        Text {
            anchors {
                top: parent.top
                right: parent.right
                topMargin: 8
                rightMargin: 10
            }

            visible: root.shortcutKey !== ""
            text: root.shortcutKey.toUpperCase()
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
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