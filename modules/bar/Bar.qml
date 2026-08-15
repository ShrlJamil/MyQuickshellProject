import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import "../../components"

PanelWindow {
    id: root

    required property var modelData

    readonly property var barState: modelData.barState
    readonly property var launcherController: modelData.launcherController

    screen: modelData.screen

    property bool active: barState.mode !== "" && barState.screen === root.screen
    property real openHeight: 320

    implicitHeight: openHeight

    anchors {
        top: true
        left: true
        right: true
    }

    color: "transparent"

    exclusiveZone: 40
    focusable: active

    mask: menuMask

    onActiveChanged: {
        if (root.active) {
            powerMenu.reset()
            powerMenu.forceActiveFocus()
        }
    }

    Region {
        id: menuMask

        item: menuBox
        radius: 24
    }

    HyprlandFocusGrab {
        id: focusGrab

        windows: [root]
        active: root.active

        onCleared: {
            barState.screen = null
            barState.mode = ""
        }
    }

    Rectangle {
        id: background

        width: root.active ? 360 : parent.width
        radius: root.active ? 24 : 0
        height: root.active ? root.openHeight : 40

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }

        color: Theme.background

        Behavior on width {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Behavior on radius {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Item {
            id: menuBox

            opacity: root.active ? 1 : 0

            anchors.fill: parent

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutQuad
                }
            }

            PowerMenu {
                id: powerMenu

                anchors.fill: parent

                onCloseRequested: {
                    barState.screen = null
                    barState.mode = ""
                }
            }
        }

        Item {
            id: barContent

            opacity: root.active ? 0 : 1

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }

            height: 40

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutQuad
                }
            }

            Item {
                id: leftSlot

                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }

                anchors.leftMargin: 8

                width: 36
                height: 36

                Rectangle {
                    id: launcherButton

                    anchors.fill: parent

                    radius: 10
                    color: launcherTap.pressed ? Theme.surfaceHover : (launcherHover.hovered ? Theme.surfaceHover : "transparent")

                    HoverHandler {
                        id: launcherHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        id: launcherTap

                        onTapped: root.launcherController.toggle()
                    }

                    IconImage {
                        id: launcherIcon

                        anchors.centerIn: parent

                        source: Quickshell.iconPath("system-search", "application-x-executable")
                        asynchronous: true
                    }
                }
            }

            SystemClock {
                id: clock

                precision: SystemClock.Minutes
            }

            Text {
                anchors.centerIn: parent

                text: Qt.formatDateTime(clock.date, "hh:mm")
                color: Theme.text
                font.weight: Font.DemiBold
                font.pixelSize: 14
            }

            Item {
                id: rightSlot

                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }

                anchors.rightMargin: 8

                width: 36
                height: 36
            }
        }
    }
}
