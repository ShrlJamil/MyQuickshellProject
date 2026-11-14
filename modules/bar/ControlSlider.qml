import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Widgets
import "../../components"

// Slider card content, reference form: a header row (icon + label on
// the left, the value text on the right) over a thick pill slider.
// The caller (a ControlCenter tile) provides the card surface; this
// item only draws the header and the slider on top of it.
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

    implicitHeight: 84

    // Horizontal inset for the header and the slider inside the card.
    property real edgeInset: 16

    Column {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }

        anchors.leftMargin: root.edgeInset
        anchors.rightMargin: root.edgeInset
        spacing: 10

        // Header: icon (clickable - the sound card mutes through it)
        // and label on the left, the value text on the right.
        Item {
            width: parent.width
            height: 20

            Row {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }

                spacing: 8

                Item {
                    width: 20
                    height: 20
                    visible: root.iconSource !== ""

                    IconImage {
                        anchors.centerIn: parent

                        width: 18
                        height: 18

                        source: root._localIcon ? "" : root.iconSource
                        asynchronous: true
                        visible: !root._localIcon
                    }

                    Image {
                        id: headerSvg

                        anchors.centerIn: parent

                        width: 18
                        height: 18

                        source: root._localIcon ? root.iconSource : ""
                        sourceSize.width: 36
                        sourceSize.height: 36
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        visible: false
                    }

                    ColorOverlay {
                        anchors.fill: headerSvg
                        source: headerSvg
                        visible: root._localIcon && headerSvg.status === Image.Ready
                        color: root.iconColor
                    }

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.iconActivated()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter

                    text: root.label
                    color: Theme.text
                    font.pixelSize: 13
                    font.family: Theme.fontFamily
                    font.weight: Font.DemiBold
                }
            }

            Text {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }

                text: root.rightText
                color: Theme.textMuted
                font.pixelSize: 12
                font.family: Theme.fontFamily
                font.weight: Font.DemiBold
            }
        }

        // The pill slider: track, accent fill, and the slim thumb
        // at the fill's edge. Dragging or clicking anywhere on the
        // row sets the value; the wheel steps it.
        Item {
            id: sliderRow

            width: parent.width
            height: 26

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }

                height: 26
                radius: 13
                color: Theme.panelSurface
            }

            // Accent fill: the left end keeps the track's radius,
            // the right end is clipped SQUARE where the thumb stands
            // (the pre-layout styling) - the inner rect runs one
            // radius past the clip, so its rounded right end is cut.
            Item {
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }

                // Ends 4px before the thumb, the pre-layout gap.
                width: Math.max(0, knob.x - 4)
                clip: true

                Rectangle {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }

                    width: parent.width + 13
                    height: 26
                    radius: 13
                    color: Theme.activeSurface
                }
            }

            // Slim vertical thumb, the pre-layout design: a thin
            // rounded bar taller than the track (32 vs 26), so it
            // protrudes ~3px above and below the pill; no ancestor
            // clips, so the protrusion renders.
            Rectangle {
                id: knob

                anchors.verticalCenter: parent.verticalCenter

                width: 5
                height: 32
                radius: 2.5
                color: Theme.activeSurface

                x: Math.max(2, Math.min(parent.width - width - 2, parent.width * root.clampedFraction - width / 2))
            }

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
        }
    }

    function _apply(px) {
        const w = sliderRow.width
        const f = w > 0 ? Math.max(0, Math.min(1, px / w)) : 0
        root._pending = root.from + f * (root.to - root.from)
        root.moved(Math.round(root._pending))
    }
}

