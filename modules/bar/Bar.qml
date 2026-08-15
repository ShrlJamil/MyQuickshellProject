import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../components"

PanelWindow {
    id: root

    required property var modelData

    readonly property var barState: modelData.barState
    readonly property var launcherController: modelData.launcherController

    screen: modelData.screen

    property bool active: barState.mode !== "" && barState.screen === root.screen
    property real openHeight: 160

    implicitHeight: active ? openHeight : 40

    anchors {
        top: true
        left: true
        right: true
    }

    color: "transparent"

    exclusiveZone: 40
    focusable: active

    mask: active ? menuMask : null

    Region {
        id: menuMask

        item: menuBox
    }

    Rectangle {
        id: background

        width: parent.width

        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            bottom: parent.bottom
        }

        radius: 0
        color: Theme.background

        Item {
            id: menuBox

            visible: root.active

            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }

            implicitWidth: 0
            implicitHeight: 0
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
