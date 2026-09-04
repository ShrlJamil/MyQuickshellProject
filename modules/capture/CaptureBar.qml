import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import "."
import "../../components"

Item {
    id: root

    implicitWidth: 460
    implicitHeight: 64
    width: 460
    height: 64

    onVisibleChanged: console.log("[CaptureBar] visible ->", root.visible)

    Shape {
        id: card

        anchors.fill: parent
        antialiasing: true
        asynchronous: false
        vendorExtensionsEnabled: true
        preferredRendererType: Shape.CurveRenderer

        readonly property real notchSize: 18
        readonly property real bottomRadius: Theme.cornerRadius

        ShapePath {
            fillColor: Theme.background
            strokeColor: "transparent"
            strokeWidth: 0

            startX: 0
            startY: 0

            PathCubic {
                control1X: card.notchSize * 0.5
                control1Y: 0
                control2X: card.notchSize
                control2Y: card.notchSize * 0.5
                x: card.notchSize
                y: card.notchSize
            }

            PathLine {
                x: card.notchSize
                y: card.height - card.bottomRadius
            }

            PathQuad {
                controlX: card.notchSize
                controlY: card.height
                x: card.notchSize + card.bottomRadius
                y: card.height
            }

            PathLine {
                x: card.width - card.notchSize - card.bottomRadius
                y: card.height
            }

            PathQuad {
                controlX: card.width - card.notchSize
                controlY: card.height
                x: card.width - card.notchSize
                y: card.height - card.bottomRadius
            }

            PathLine {
                x: card.width - card.notchSize
                y: card.notchSize
            }

            PathCubic {
                control1X: card.width - card.notchSize
                control1Y: card.notchSize * 0.5
                control2X: card.width - card.notchSize * 0.5
                control2Y: 0
                x: card.width
                y: 0
            }

            PathLine {
                x: 0
                y: 0
            }
        }
    }

    Row {
        anchors.centerIn: parent

        spacing: 6

        Repeater {
            model: [
                { icon: "screenshot-region-symbolic", fallback: "select-rectangular", label: "Region", mode: "region" },
                { icon: "window-symbolic", fallback: "preferences-system-windows", label: "Window", mode: "window" },
                { icon: "video-display-symbolic", fallback: "video-display", label: "Screen", mode: "screen" },
                { icon: "window-close-symbolic", fallback: "window-close", label: "Cancel", mode: "cancel" }
            ]

            delegate: Rectangle {
                id: btn

                required property var modelData

                width: 100
                height: 46
                radius: 12
                color: Theme.background

                MouseArea {
                    id: btnMouse

                    anchors.fill: parent

                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        if (btn.modelData.mode === "cancel") {
                            CaptureService.closeBar()
                        } else {
                            console.log("[CaptureBar] Action triggered:", btn.modelData.mode)
                            CaptureService.triggerCapture(btn.modelData.mode)
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent

                    spacing: 3

                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter

                        width: 20
                        height: 20

                        source: Quickshell.iconPath(btn.modelData.icon, btn.modelData.fallback)
                        asynchronous: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: btn.modelData.label
                        color: btnMouse.containsMouse ? Theme.accent : Theme.text
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
