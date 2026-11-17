import QtQuick
import "../../components"

// Recording indicator for the bar's activity island: pulsing record
// dot, elapsed duration, and a stop button - the media pill's shape,
// but with no expanded surface; stopping is the only action. Present
// while RecordService.recording. ActivityIsland drives forceHidden
// to yield to the minimal circle while media holds the full pill.
Item {
    id: root

    // Set by ActivityIsland while media holds the full pill during a
    // recording: the pill yields to RecordMinimal until media ends.
    property bool forceHidden: false

    readonly property bool shown: RecordService.recording && !root.forceHidden

    // The pill animates its own width (ActivityIsland grow/shrink):
    // the background fills the item, so the rounded end stays rounded
    // at every width instead of being sliced by a parent's clip.
    // Visible latches until the shrink lands, so the animation out
    // is seen at all.
    visible: root.shown || root.width > 0.5
    width: root.shown ? pillBg.implicitWidth : 0
    height: 30
    clip: true

    Behavior on width {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    // Same 30 px handover as the media pill: at 30 px the pill
    // is a round circle showing only the record dot, centred
    // like the minimal's (see the content margin below), so it
    // cuts out exactly as the minimal cuts in.
    opacity: (!root.shown && root.width <= 30) ? 0 : Math.min(1, root.width / 16)

    // The timer and stop button dissolve as the pill collapses
    // toward minimal size instead of being sliced by the
    // narrowing clip; the dot stays, like the media artwork.
    readonly property real contentOpacity: Math.max(0, Math.min(1, (root.width - 30) / 15))

    Rectangle {
        id: pillBg

        anchors.fill: parent

        implicitWidth: content.implicitWidth + 16
        radius: height / 2
        color: Theme.backgroundInset

        Row {
            id: content

            // Left-anchored with an 8 px inset (identical to the old
            // centred layout at rest, since the pill is exactly the
            // content width + 16): during the width animation the
            // dot leads and the pill grows out from under it. The
            // inset eases to 10.5 as the pill collapses to 30 px,
            // centring the dot exactly where the minimal's dot sits
            // for the invisible handover.
            anchors {
                left: parent.left
                leftMargin: 8 + 2.5 * Math.max(0, Math.min(1, (45 - root.width) / 15))
                verticalCenter: parent.verticalCenter
            }
            spacing: 7

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 9
                height: 9
                radius: 4.5
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

            Text {
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.contentOpacity
                text: RecordService.durationText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.contentOpacity
                width: 22
                height: 22

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: stopHover.hovered ? Theme.surfaceHover : "transparent"
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 9
                    height: 9
                    radius: 2
                    color: Theme.text
                }

                HoverHandler {
                    id: stopHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: RecordService.stop()
                }
            }
        }
    }
}
