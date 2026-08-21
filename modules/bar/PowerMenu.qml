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
    property int holdDuration: 1000

    readonly property var actions: [
        { id: "lock", label: "Lock", command: "loginctl lock-session" },
        { id: "hibernate", label: "Hibernate", command: "systemctl hibernate" },
        { id: "logout", label: "Logout", command: "loginctl terminate-user \"$USER\"" },
        { id: "shutdown", label: "Shutdown", command: "systemctl poweroff" },
        { id: "suspend", label: "Suspend", command: "systemctl suspend" },
        { id: "reboot", label: "Reboot", command: "systemctl reboot" }
    ]

    readonly property int itemWidth: Math.floor((actionsRow.width - (root.actions.length - 1) * actionsRow.spacing) / root.actions.length)
    readonly property int itemHeight: Math.max(88, Math.round(root.height - 44))

    readonly property var currentItem: actionsRepeater.itemAt(root.selectedIndex)

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

    Text {
        id: menuTitle

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }

        anchors.topMargin: 10

        text: "Hold to confirm"
        color: Theme.textMuted
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }

    Row {
        id: actionsRow

        anchors {
            top: menuTitle.bottom
            left: parent.left
            right: parent.right
        }

        anchors.topMargin: 10
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