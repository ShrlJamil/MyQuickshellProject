import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    property string label: ""
    property string iconSource: ""
    // Colour a local file: SVG glyph is tinted to (theme icons draw as-is).
    property color iconColor: Theme.icon

    // A local `file:` SVG is a solid #000 glyph -> Image + ColorOverlay so it
    // tints; a Quickshell.iconPath theme icon already arrives coloured.
    readonly property bool _localIcon: root.iconSource.startsWith("file:")
    property real value: 0
    property real from: 0
    property real to: 100
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

    // Inner horizontal padding so the icon / track / value sit clear of the
    // curved ends of the pill background they're drawn on. 28px clears the
    // full-pill (radius 50) arc into the flat centre band.
    property real edgeInset: 28

    Item {
        id: iconSlot

        anchors {
            left: parent.left
            leftMargin: root.edgeInset
            verticalCenter: parent.verticalCenter
        }

        width: 28
        height: 28

        // theme icon (already coloured)
        IconImage {
            anchors.centerIn: parent

            width: 22
            height: 22

            source: root._localIcon ? "" : root.iconSource
            asynchronous: true
            visible: !root._localIcon && root.iconSource !== ""
        }

        // custom solid-#000 SVG, tinted to iconColor
        Image {
            id: sliderSvg

            anchors.centerIn: parent

            width: 22
            height: 22

            source: root._localIcon ? root.iconSource : ""
            sourceSize.width: 44
            sourceSize.height: 44
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            visible: false
        }

        ColorOverlay {
            anchors.fill: sliderSvg
            source: sliderSvg
            visible: root._localIcon && sliderSvg.status === Image.Ready
            color: root.iconColor
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
            rightMargin: root.edgeInset
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
        anchors.rightMargin: root.rightText !== "" ? 12 : root.edgeInset

        height: 10
        radius: 5
        color: Theme.surface

        Rectangle {
            id: fill

            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }

            width: track.width * root.clampedFraction
            radius: track.radius
            color: Theme.accent
        }

        // Horizontal pill thumb, centred on the track, clamped so it never
        // clips past either end.
        Rectangle {
            id: knob

            anchors.verticalCenter: track.verticalCenter

            width: 22
            height: 12
            radius: 6
            color: Theme.icon

            x: Math.max(0, Math.min(track.width - width, fill.width - width / 2))
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
