import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    property int selectedIndex: 0
    property bool stubActions: false
    property bool showError: false
    property int holdDuration: 1000

    readonly property var actions: [
        { id: "lock", label: "Lock", command: "loginctl lock-session", icon: "assets/lock-svgrepo-com.svg" },
        { id: "hibernate", label: "Hibernate", command: "systemctl hibernate", icon: "assets/moon-sleep-svgrepo-com.svg" },
        { id: "logout", label: "Logout", command: "loginctl terminate-user \"$USER\"", icon: "assets/logout-svgrepo-com.svg" },
        { id: "shutdown", label: "Shutdown", command: "systemctl poweroff", icon: "assets/power-material-svgrepo-com.svg" },
        { id: "suspend", label: "Suspend", command: "systemctl suspend", icon: "assets/moon-svgrepo-com.svg" },
        { id: "reboot", label: "Reboot", command: "systemctl reboot", icon: "assets/system-reboot-svgrepo-com.svg" }
    ]

    readonly property int itemWidth: Math.floor((actionsRow.width - (root.actions.length - 1) * actionsRow.spacing) / root.actions.length)
    readonly property int itemHeight: 128

    readonly property var currentItem: actionsRepeater.itemAt(root.selectedIndex)

    implicitHeight: actionsRow.y + actionsRow.height + 30 + (root.showError ? errorHint.height + 8 : 0)

    signal closeRequested()

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested()
            event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            root.selectedIndex = (root.selectedIndex + root.actions.length - 1) % root.actions.length
            event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            root.selectedIndex = (root.selectedIndex + 1) % root.actions.length
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.currentItem) root.currentItem.startHold()
            event.accepted = true
        }
    }

    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.currentItem) root.currentItem.cancelHold()
            event.accepted = true
        }
    }

    function reset() {
        root.selectedIndex = 0
        root.showError = false
        for (let i = 0; i < actionsRepeater.count; i++) {
            const item = actionsRepeater.itemAt(i)
            if (item) item.reset()
        }
    }

    function executeCommand(actionId) {
        if (root.stubActions) {
            console.log("[PowerMenu:stub] would run: " + root.commandFor(actionId))
            root.closeRequested()
            return
        }
        switch (actionId) {
        case "lock":
            lockProc.exec(["loginctl", "lock-session"])
            break
        case "hibernate":
            Quickshell.execDetached(["systemctl", "hibernate"])
            root.closeRequested()
            break
        case "logout":
            Quickshell.execDetached(["bash", "-c", "loginctl terminate-user \"$USER\""])
            root.closeRequested()
            break
        case "shutdown":
            Quickshell.execDetached(["systemctl", "poweroff"])
            root.closeRequested()
            break
        case "suspend":
            Quickshell.execDetached(["systemctl", "suspend"])
            root.closeRequested()
            break
        case "reboot":
            Quickshell.execDetached(["systemctl", "reboot"])
            root.closeRequested()
            break
        }
    }

    function commandFor(actionId) {
        for (let i = 0; i < root.actions.length; i++) {
            if (root.actions[i].id === actionId) return root.actions[i].command
        }
        return ""
    }

    Process {
        id: lockProc

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) root.closeRequested()
            else root.showError = true
        }
    }

    Shape {
        id: background

        anchors.fill: parent
        antialiasing: true
        asynchronous: false
        vendorExtensionsEnabled: true
        preferredRendererType: Shape.CurveRenderer

        readonly property real notchSize: 18
        readonly property real bottomRadius: 16

        ShapePath {
            fillColor: Theme.background
            strokeColor: "transparent"
            strokeWidth: 0

            startX: 0
            startY: 0

            PathCubic {
                control1X: background.notchSize * 0.5
                control1Y: 0
                control2X: background.notchSize
                control2Y: background.notchSize * 0.5
                x: background.notchSize
                y: background.notchSize
            }

            PathLine {
                x: background.notchSize
                y: background.height - background.bottomRadius
            }

            PathQuad {
                controlX: background.notchSize
                controlY: background.height
                x: background.notchSize + background.bottomRadius
                y: background.height
            }

            PathLine {
                x: background.width - background.notchSize - background.bottomRadius
                y: background.height
            }

            PathQuad {
                controlX: background.width - background.notchSize
                controlY: background.height
                x: background.width - background.notchSize
                y: background.height - background.bottomRadius
            }

            PathLine {
                x: background.width - background.notchSize
                y: background.notchSize
            }

            PathCubic {
                control1X: background.width - background.notchSize
                control1Y: background.notchSize * 0.5
                control2X: background.width - background.notchSize * 0.5
                control2Y: 0
                x: background.width
                y: 0
            }

            PathLine {
                x: 0
                y: 0
            }
        }
    }

    Row {
        id: actionsRow

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }

        anchors.topMargin: 20
        anchors.leftMargin: 24
        anchors.rightMargin: 24

        spacing: 10

        Repeater {
            id: actionsRepeater

            model: root.actions

            delegate: PowerActionItem {
                width: root.itemWidth
                height: root.itemHeight

                actionId: modelData.id
                label: modelData.label
                iconSource: "file://" + Quickshell.shellPath(modelData.icon)
                selected: root.selectedIndex === index

                onActionRequested: (id) => root.executeCommand(id)
            }
        }
    }

    Text {
        id: errorHint

        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }

        anchors.bottomMargin: 5

        visible: root.showError

        text: "Lock failed"
        color: Theme.textMuted
        font.pixelSize: 12
    }
}