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

    // Which side of the fill edge the icon / value label sit on, from
    // their actual geometry: the fill's right edge is fillClip.width,
    // and an element counts as on the (light) fill once that edge passes
    // the element's centre - so its foreground must flip dark there.
    readonly property bool _iconOnFill: fillClip.width >= root.edgeInset + 14
    readonly property bool _labelOnFill: fillClip.width >= valueLabel.x + valueLabel.width - valueLabel.contentWidth / 2

    implicitHeight: 48

    // Horizontal inset for the icon / value label inside the row body.
    property real edgeInset: 16

    // Progress: fills the row's full height, drawn directly on the
    // section background from ControlCenter, which serves as the track
    // (its idle/hover tones show through wherever the progress has not
    // reached). The left end keeps a 10px radius; the right end is
    // clipped SQUARE. Width derives from the knob position, holding a
    // constant 4px gap between the progress end and the knob.
    Item {
        id: fillClip

        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }

        width: Math.max(0, knob.x - 4)
        clip: true

        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }

            width: fillClip.width + 10
            radius: 10
            color: Theme.activeSurface
        }
    }

    // Whole-row drag/click surface. Declared before the icon slot so the
    // icon's own MouseArea (mute etc.) still wins inside its slot; every
    // other point of the row, including both ends, slides.
    MouseArea {
        id: dragArea

        anchors.fill: parent

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
            // On the light fill the glyph flips dark; a caller-dimmed
            // glyph (muted volume) flips to the DIM dark instead, so
            // the muted distinction survives on both surfaces.
            color: root._iconOnFill
                ? (root.iconColor === Theme.textMuted ? Theme.onActiveSurfaceDim : Theme.onActiveSurface)
                : root.iconColor
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
        color: root._labelOnFill ? Theme.onActiveSurfaceDim : Theme.textMuted
        font.pixelSize: 11
        font.family: Theme.fontFamily
        font.weight: Font.DemiBold
    }

    // Slim VERTICAL thumb: a thin rounded bar, taller than the full-
    // height progress (54 vs 48), so it protrudes ~3px above and below
    // the row; no ancestor clips, so the protrusion renders. Centred on
    // the value position and clamped inside the row at both extremes.
    Rectangle {
        id: knob

        anchors.verticalCenter: parent.verticalCenter

        width: 5
        height: 54
        radius: 2.5
        color: Theme.onActiveSurface

        x: Math.max(4, Math.min(root.width - width - 4, root.width * root.clampedFraction - width / 2))
    }

    function _apply(px) {
        const f = root.width > 0 ? Math.max(0, Math.min(1, px / root.width)) : 0
        root._pending = root.from + f * (root.to - root.from)
        root.moved(Math.round(root._pending))
    }
}
