import QtQuick
import "../../components"

// Minimal (detached) form of the recording pill, Dynamic Island
// style: just the pulsing record dot in a small round circle, shown
// in recording's own slot while media is the expanded activity
// during simultaneous activity. Tapping it expands recording in
// this same slot while media shrinks in its own slot - positions
// never trade (ActivityIsland owns the state).
Item {
    id: root

    signal activateRequested()

    // Set by ActivityIsland while its pill is wider than 30 px.
    // At 30 px the pill and this circle are the same image - a
    // round circle with the same centred content - so the pill
    // cutting out and this circle cutting in is invisible. The
    // width term only dissolves this circle's own exit (when the
    // activity itself ends and it shrinks away to nothing).
    property bool covered: false

    opacity: root.covered ? 0 : Math.min(1, root.width / 16)

    // Set by ActivityIsland while media is expanded.
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
        anchors.centerIn: parent
        // Scales with the circle while it morphs, like the media
        // minimal's artwork: a fixed-size dot in a narrower circle
        // was sliced into a sliver by the clip.
        width: Math.max(0, Math.min(9, root.width - 20))
        height: width
        radius: width / 2
        color: "#E5484D"

        SequentialAnimation on opacity {
            running: RecordService.recording
            loops: Animation.Infinite

            NumberAnimation {
                to: 0.3
                duration: 700
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 1.0
                duration: 700
                easing.type: Easing.InOutSine
            }
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
