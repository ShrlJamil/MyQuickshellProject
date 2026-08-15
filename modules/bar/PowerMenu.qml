import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    property int selectedIndex: 0
    property bool stubActions: false
    property bool showError: false

    signal closeRequested()

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested()
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            root.selectedIndex = (root.selectedIndex + 1) % 3
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            root.selectedIndex = (root.selectedIndex + 2) % 3
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateSelected()
            event.accepted = true
        }
    }

    function reset() {
        root.selectedIndex = 0
        root.showError = false
    }

    function activateSelected() {
        switch (root.selectedIndex) {
        case 0:
            runLock()
            break
        case 1:
            runReboot()
            break
        case 2:
            runShutdown()
            break
        }
    }

    function runLock() {
        if (root.stubActions) {
            console.log("[PowerMenu:stub] would run: loginctl lock-session")
            root.closeRequested()
            return
        }
        lockProc.exec(["loginctl", "lock-session"])
    }

    function runReboot() {
        if (root.stubActions) {
            console.log("[PowerMenu:stub] would run: systemctl reboot")
            root.closeRequested()
            return
        }
        Quickshell.execDetached(["systemctl", "reboot"])
        root.closeRequested()
    }

    function runShutdown() {
        if (root.stubActions) {
            console.log("[PowerMenu:stub] would run: systemctl poweroff")
            root.closeRequested()
            return
        }
        Quickshell.execDetached(["systemctl", "poweroff"])
        root.closeRequested()
    }

    Process {
        id: lockProc

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) root.closeRequested()
            else root.showError = true
        }
    }

    Text {
        id: menuTitle

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }

        anchors.topMargin: 20

        text: "Power Menu"
        color: Theme.textMuted
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Column {
        id: menuCol

        anchors {
            top: menuTitle.bottom
            left: parent.left
            right: parent.right
        }

        anchors.topMargin: 12
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        spacing: 8

        Rectangle {
            id: lockRow

            width: parent.width
            height: 52
            radius: 10
            color: lockHover.hovered || root.selectedIndex === 0 ? Theme.surfaceHover : "transparent"

            IconImage {
                id: lockIcon

                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }

                anchors.leftMargin: 14

                source: Quickshell.iconPath("system-lock-screen", "system-lock-screen")
                asynchronous: true
            }

            Text {
                anchors {
                    left: lockIcon.right
                    verticalCenter: parent.verticalCenter
                }

                anchors.leftMargin: 14

                text: "Lock"
                color: Theme.text
                font.pixelSize: 14
            }

            HoverHandler {
                id: lockHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: root.runLock()
            }
        }

        Rectangle {
            id: rebootRow

            width: parent.width
            height: 52
            radius: 10
            color: rebootHover.hovered || root.selectedIndex === 1 ? Theme.surfaceHover : "transparent"

            IconImage {
                id: rebootIcon

                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }

                anchors.leftMargin: 14

                source: Quickshell.iconPath("system-reboot", "view-refresh")
                asynchronous: true
            }

            Text {
                anchors {
                    left: rebootIcon.right
                    verticalCenter: parent.verticalCenter
                }

                anchors.leftMargin: 14

                text: "Reboot"
                color: Theme.text
                font.pixelSize: 14
            }

            HoverHandler {
                id: rebootHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: root.runReboot()
            }
        }

        Rectangle {
            id: shutdownRow

            width: parent.width
            height: 52
            radius: 10
            color: shutdownHover.hovered || root.selectedIndex === 2 ? Theme.surfaceHover : "transparent"

            IconImage {
                id: shutdownIcon

                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }

                anchors.leftMargin: 14

                source: Quickshell.iconPath("system-shutdown", "system-shutdown")
                asynchronous: true
            }

            Text {
                anchors {
                    left: shutdownIcon.right
                    verticalCenter: parent.verticalCenter
                }

                anchors.leftMargin: 14

                text: "Shutdown"
                color: Theme.text
                font.pixelSize: 14
            }

            HoverHandler {
                id: shutdownHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: root.runShutdown()
            }
        }
    }

    Text {
        id: errorHint

        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }

        anchors.bottomMargin: 16

        visible: root.showError

        text: "Lock failed"
        color: Theme.textMuted
        font.pixelSize: 12
    }
}