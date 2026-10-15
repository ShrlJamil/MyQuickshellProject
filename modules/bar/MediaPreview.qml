import QtQuick
import Qt5Compat.GraphicalEffects
import "../services"
import "../../components"

// Persistent, compact media state that lives in the centre of the 40px static
// bar whenever a player is active. Never opens the DynamicCenter on its own;
// a click asks the parent to open the expanded player.
//
// Uses the resolved media state from MediaService (which falls back to its
// runtime last-media cache) - it does NOT pick an MPRIS player itself.
Item {
    id: root

    required property var mediaService

    signal activateRequested()

    // hasMedia (not hasPlayer): stay visible on the last track while the player
    // is paused / stopped / gone.
    readonly property bool active: root.mediaService && root.mediaService.hasMedia
    readonly property bool playing: root.active && root.mediaService.playing

    property bool show: false
    property bool _present: false
    // Artwork travel progress, derived from the live artwork offset - the
    // single driver for the content reveal below. 0 at the staged start pose
    // (left edge flush with the preview's right edge, clear of the content),
    // 1 once the artwork rests in its slot.
    readonly property real _startX: Math.max(0, row.implicitWidth)
    readonly property real apart: root._startX <= 0 ? 1
        : Math.max(0, Math.min(1, 1 - coverShift.x / root._startX)
        )
    function _band(p, lo, span) {
        return Math.max(0, Math.min(1, (p - lo) / span))
    }
    visible: root._present
    opacity: root.show ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: root.show ? 0 : 200
            easing.type: Easing.InCubic
            onFinished: if (!root.show) root._present = false
        }
    }
    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: root.show ? 1 : 0.6
        yScale: 1
        Behavior on xScale {
            NumberAnimation {
                duration: root.show ? 0 : 200
                easing.type: Easing.InCubic
                onFinished: if (!root.show) root._present = false
            }
        }
    }
    onShowChanged: {
        if (root.show) {
            root._present = true
            enterAnim.stop()
            coverShift.x = root._startX
            cover.opacity = 0
            enterAnim.restart()
        } else {
            enterAnim.stop()
        }
    }
    Component.onCompleted: {
        if (root.show) {
            root._present = true
            coverShift.x = root._startX
            cover.opacity = 0
            enterAnim.restart()
        }
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: coverShift; property: "x"; from: root._startX; to: 0; duration: 900; easing.type: Easing.OutQuart }
        NumberAnimation { target: cover; property: "opacity"; from: 0; to: 1; duration: 130; easing.type: Easing.OutCubic }
    }

    implicitHeight: 30
    implicitWidth: row.implicitWidth

    readonly property int coverSize: 28
    readonly property int textMax: 210

    HoverHandler {
        id: hover
        enabled: root.show
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.show
        onTapped: root.activateRequested()
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: 8
        color: hover.hovered ? Theme.surfaceHover : "transparent"
    }

    Row {
        id: row
        anchors.centerIn: parent
        // a little breathing room: cover | title/artist | mini viz
        spacing: 12

        // ---- album cover --------------------------------------------------
        // Rounded via a layer OpacityMask on the Image itself (Item.clip only
        // clips to the bounding rect, not the radius). NOT
        // Quickshell.Widgets.ClippingRectangle - that SIGSEGVs on 0.3.1 with a
        // bound-source Image.
        Rectangle {
            id: cover
            width: root.coverSize
            height: root.coverSize
            radius: 6
            clip: true
            color: Theme.surface
            anchors.verticalCenter: parent.verticalCenter
            // Top layer within the row: the travelling artwork occludes the
            // content it vacates, reading as a curtain reveal. Same stacking
            // context (Row), so no hierarchy change is needed.
            // Constantly opaque: the artwork is fully visible from frame one;
            // `apart` only drives the reveal of the content behind it.
            z: 1
            transform: Translate { id: coverShift }

            Image {
                id: art
                anchors.fill: parent
                source: root.active ? root.mediaService.artwork : ""
                sourceSize.width: root.coverSize * 2
                sourceSize.height: root.coverSize * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: art.status === Image.Ready
                layer.enabled: art.status === Image.Ready
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: cover.width
                        height: cover.height
                        radius: cover.radius
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: "♪"
                color: Theme.textMuted
                font.pixelSize: 14
            }
        }

        // ---- title + artist -----------------------------------------------
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Item {
                id: titleClip
                width: Math.min(titleText.implicitWidth, root.textMax)
                height: titleText.implicitHeight
                clip: true
                opacity: root._band(root.apart, 0.35, 0.30)
                transform: Translate {
                    id: titleShift
                    x: (1 - root._band(root.apart, 0.35, 0.30)) * 20
                }

                Text {
                    id: titleText
                    text: root.active ? root.mediaService.title : ""
                    color: Theme.icon
                    font.pixelSize: 12
                    font.weight: Font.DemiBold

                    readonly property bool overflow: implicitWidth > titleClip.width + 0.5
                    readonly property real scrollDistance: Math.max(0, implicitWidth - titleClip.width)

                    x: 0
                    onOverflowChanged: if (!overflow) x = 0

                    SequentialAnimation on x {
                        running: titleText.overflow
                        loops: Animation.Infinite
                        PauseAnimation { duration: 1400 }
                        NumberAnimation {
                            to: -titleText.scrollDistance
                            duration: Math.max(400, titleText.scrollDistance * 20)
                            easing.type: Easing.InOutSine
                        }
                        PauseAnimation { duration: 1400 }
                        NumberAnimation {
                            to: 0
                            duration: Math.max(400, titleText.scrollDistance * 16)
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            Text {
                id: artistText
                width: Math.min(implicitWidth, root.textMax)
                text: root.active ? root.mediaService.artist : ""
                color: Theme.icon
                font.pixelSize: 10
                elide: Text.ElideRight
                maximumLineCount: 1
                opacity: root._band(root.apart, 0.55, 0.30)
                transform: Translate {
                    id: artistShift
                    x: (1 - root._band(root.apart, 0.55, 0.30)) * 16
                }
            }
        }

        // ---- 3-bar mini visualizer --------------------------------------
        // Driven by the shared CavaService spectrum: low / mid / high taps.
        // When cava is offline or audio is paused the taps read 0 and the bars
        // ease down to their 2px baseline.
        Item {
            id: viz
            width: 16
            height: root.coverSize
            anchors.verticalCenter: parent.verticalCenter
            opacity: root._band(root.apart, 0.10, 0.30)
            transform: Translate {
                id: vizShift
                x: (1 - root._band(root.apart, 0.10, 0.30)) * 14
            }

            readonly property bool live: root.playing
            readonly property real barMax: 14
            readonly property var spec: CavaService.bars
            // bass / low-mid / treble bins out of the 26-bar frame
            readonly property var taps: [1, 8, 16]
            // extra sensitivity boost for the tiny bars - clamped at 1.0
            readonly property real gain: 1.6

            Row {
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: 3

                    delegate: Item {
                        id: cell
                        required property int index
                        width: 3
                        height: viz.barMax
                        anchors.verticalCenter: parent.verticalCenter

                        readonly property int tap: viz.taps[cell.index]
                        readonly property real level: (viz.live && viz.spec && viz.spec.length > cell.tap)
                            ? Math.max(0, Math.min(1, viz.spec[cell.tap] * viz.gain))
                            : 0
                        readonly property real enterK: root._band(root.apart, 0.10 + cell.index * 0.08, 0.25)

                        Rectangle {
                            id: bar
                            width: parent.width
                            radius: width / 2
                            color: Theme.accent
                            anchors.bottom: parent.bottom
                            height: Math.max(2, viz.barMax * cell.level)
                            transform: Scale {
                                origin.y: viz.barMax
                                yScale: 0.15 + 0.85 * cell.enterK
                            }
                            Behavior on height {
                                NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }
            }
        }
    }
}
