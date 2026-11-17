import QtQuick
import Qt5Compat.GraphicalEffects
import "../../components"

// Minimal (detached) form of the media pill, Dynamic Island style:
// just the track artwork in a small round circle, shown in media's
// own slot while recording is the expanded activity during
// simultaneous activity. Tapping it expands media in this same
// slot while recording shrinks in its own slot - positions never
// trade (ActivityIsland owns the state).
Item {
    id: root

    required property var mediaService

    signal activateRequested()

    readonly property bool active: root.mediaService && root.mediaService.hasMedia

    // Set by ActivityIsland while its pill is wider than 30 px.
    // At 30 px the pill and this circle are the same image - a
    // round circle with the same centred content - so the pill
    // cutting out and this circle cutting in is invisible. The
    // width term only dissolves this circle's own exit (when the
    // activity itself ends and it shrinks away to nothing).
    property bool covered: false

    opacity: root.covered ? 0 : Math.min(1, root.width / 16)

    // Set by ActivityIsland while recording is expanded.
    property bool show: false

    // Own-width animation like the pills (recipe mirrored from the
    // top-centre DynamicIsland.qml): the background fills the item
    // with radius height/2, so it morphs capsule-to-circle and back
    // without ever showing a squared edge. Visible latches until
    // the shrink lands.
    visible: root.show || root.width > 0.5
    width: root.show ? 30 : 0
    height: 30
    clip: true

    Behavior on width {
        // Growing is faster than shrinking: the circle must be at
        // its full 30 px under the pill by the time the pill's
        // shrink reaches 30 px (~125 ms in), ready for the
        // invisible handover.
        NumberAnimation { duration: root.show ? 150 : 300; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.backgroundInset
    }

    Rectangle {
        id: artwork

        anchors.centerIn: parent
        // Scales with the circle while it morphs: at a fixed 22 px
        // the artwork was wider than the still-growing circle and
        // got sliced by its clip into a squarish blob (the residual
        // mirror on the media shrink, 2026-11-17).
        width: Math.max(0, Math.min(22, root.width - 8))
        height: width
        radius: width / 2
        color: Theme.surface

        Image {
            id: art

            anchors.fill: parent
            source: root.active ? root.mediaService.artwork : ""
            sourceSize.width: 44
            sourceSize.height: 44
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: art.status === Image.Ready
            layer.enabled: art.status === Image.Ready
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: artwork.width
                    height: artwork.height
                    radius: artwork.width / 2
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: "\u266a"
            color: Theme.textMuted
            style: Text.Raised
            styleColor: Theme.textShadow
            font.pixelSize: Math.min(10, artwork.width)
        }
    }

    HoverHandler {
        enabled: root.show
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.show
        onTapped: root.activateRequested()
    }
}
