import QtQuick
import "../../components"

// Recording indicator for the bar's right cluster: pulsing record dot,
// elapsed duration, and a stop button - the media pill's shape, but with
// no expanded surface; stopping is the only action. Present only while
// RecordService.recording; collapses to zero width when idle (the
// caffeine indicator's pattern) so the rest of the cluster never shifts.
Item {
    id: root

    visible: RecordService.recording
    width: RecordService.recording ? pillBg.width : 0
    height: 30
    clip: true

    Rectangle {
        id: pillBg

        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }

        width: content.implicitWidth + 16
        height: 30
        radius: 15
        color: Theme.backgroundInset

        Row {
            id: content

            anchors.centerIn: parent
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
                text: RecordService.durationText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
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
