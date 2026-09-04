import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    required property var captureService

    implicitWidth: 440
    implicitHeight: 64
    width: 440
    height: 64

    Component.onCompleted: console.log("[CaptureBar] Component loaded inside DynamicCenter")

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter

        width: parent.width
        height: 56

        radius: Theme.cornerRadius
        color: Theme.background
        border.width: 1
        border.color: Theme.accent

        y: (root.captureService && root.captureService.barVisible) ? 4 : -root.implicitHeight

        Behavior on y {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
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
                    color: btnMouse.containsMouse ? Qt.lighter(Theme.background, 1.35) : Theme.background

                    MouseArea {
                        id: btnMouse

                        anchors.fill: parent

                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            console.log("[CaptureBar] Clicked mode:", btn.modelData.mode)
                            if (btn.modelData.mode === "cancel")
                                root.captureService.closeBar()
                            else
                                root.captureService.triggerCapture(btn.modelData.mode)
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
}
