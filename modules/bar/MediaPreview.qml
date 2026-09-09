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
    visible: root.active

    implicitHeight: 30
    implicitWidth: row.implicitWidth

    readonly property int coverSize: 28
    readonly property int textMax: 210

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
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

                Text {
                    id: titleText
                    text: root.active ? root.mediaService.title : ""
                    color: Theme.text
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
                width: Math.min(implicitWidth, root.textMax)
                text: root.active ? root.mediaService.artist : ""
                color: Theme.textDim
                font.pixelSize: 10
                elide: Text.ElideRight
                maximumLineCount: 1
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

                        Rectangle {
                            width: parent.width
                            radius: width / 2
                            color: Theme.accent
                            anchors.bottom: parent.bottom
                            height: Math.max(2, viz.barMax * cell.level)
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
