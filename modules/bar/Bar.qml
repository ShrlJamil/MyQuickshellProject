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

        width: parent.width
        radius: 0
        height: 40

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }

        color: Theme.background

        states: [
            State {
                name: "idle"

                when: !root.active

                PropertyChanges {
                    target: background
                    width: background.parent.width
                    height: 40
                    radius: 0
                }

                PropertyChanges {
                    target: menuBox
                    opacity: 0
                }

                PropertyChanges {
                    target: barContent
                    opacity: 1
                }
            },
            State {
                name: "active"

                when: root.active

                PropertyChanges {
                    target: background
                    width: 360
                    height: root.openHeight
                    radius: 24
                }

                PropertyChanges {
                    target: menuBox
                    opacity: 1
                }

                PropertyChanges {
                    target: barContent
                    opacity: 0
                }
            }
        ]

        transitions: [
            Transition {
                from: "idle"
                to: "active"

                ParallelAnimation {
                    SequentialAnimation {
                        PauseAnimation { duration: 0 }

                        NumberAnimation {
                            target: background
                            property: "width"
                            duration: 260
                            easing.type: Easing.OutCubic
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 140 }

                        NumberAnimation {
                            target: background
                            property: "height"
                            duration: 320
                            easing.type: Easing.OutCubic
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 10 }

                        NumberAnimation {
                            target: background
                            property: "radius"
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 0 }

                        NumberAnimation {
                            target: barContent
                            property: "opacity"
                            duration: 190
                            easing.type: Easing.OutQuad
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 160 }

                        NumberAnimation {
                            target: menuBox
                            property: "opacity"
                            duration: 220
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            },
            Transition {
                from: "active"
                to: "idle"

                ParallelAnimation {
                    SequentialAnimation {
                        PauseAnimation { duration: 0 }

                        NumberAnimation {
                            target: background
                            property: "height"
                            duration: 260
                            easing.type: Easing.OutCubic
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 140 }

                        NumberAnimation {
                            target: background
                            property: "width"
                            duration: 320
                            easing.type: Easing.OutCubic
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 20 }

                        NumberAnimation {
                            target: background
                            property: "radius"
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 0 }

                        NumberAnimation {
                            target: menuBox
                            property: "opacity"
                            duration: 190
                            easing.type: Easing.OutQuad
                        }
                    }

                    SequentialAnimation {
                        PauseAnimation { duration: 140 }

                        NumberAnimation {
                            target: barContent
                            property: "opacity"
                            duration: 220
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }
        ]

        Item {
            id: menuBox

            opacity: 0

            anchors.fill: parent

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

            opacity: 1

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }

            height: 40

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
