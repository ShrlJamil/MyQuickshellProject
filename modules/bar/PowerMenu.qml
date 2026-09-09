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

    // `key` is the press-and-hold shortcut (see indexForQtKey below).
    readonly property var actions: [
        { id: "lock", label: "Lock", command: "hyprlock", icon: "assets/lock-svgrepo-com.svg", key: "l" },
        { id: "hibernate", label: "Hibernate", command: "systemctl hibernate", icon: "assets/moon-sleep-svgrepo-com.svg", key: "h" },
        { id: "logout", label: "Logout", command: "hyprctl dispatch exit", icon: "assets/logout-svgrepo-com.svg", key: "e" },
        { id: "shutdown", label: "Shutdown", command: "systemctl poweroff", icon: "assets/power-material-svgrepo-com.svg", key: "s" },
        { id: "suspend", label: "Suspend", command: "systemctl suspend", icon: "assets/moon-svgrepo-com.svg", key: "u" },
        { id: "reboot", label: "Restart", command: "systemctl reboot", icon: "assets/system-reboot-svgrepo-com.svg", key: "r" }
    ]

    readonly property int itemWidth: Math.floor((actionsRow.width - (root.actions.length - 1) * actionsRow.spacing) / root.actions.length)
    readonly property int itemHeight: 128

    // Inner padding between the panel card edges and the tile grid. Vertical
    // spacing (top 20 / bottom 30) is intentionally kept as-is; the sides get
    // extra breathing room.
    readonly property int contentMarginTop: 20
    readonly property int contentMarginBottom: 30
    readonly property int contentMarginSide: 32

    readonly property var currentItem: actionsRepeater.itemAt(root.selectedIndex)

    // Natural size DynamicCenter fits its frame to. Constant (not derived from
    // `width`) so it can't feed a binding loop through the frame.
    implicitWidth: 680
    implicitHeight: actionsRow.y + actionsRow.height + root.contentMarginBottom + (root.showError ? errorHint.height + 8 : 0)

    signal closeRequested()

    // Map a Qt key code to an action index, or -1. Logout answers to both e/x.
    function indexForQtKey(qtKey) {
        let wantId = ""
        switch (qtKey) {
        case Qt.Key_S: wantId = "shutdown"; break
        case Qt.Key_R: wantId = "reboot"; break
        case Qt.Key_H: wantId = "hibernate"; break
        case Qt.Key_U: wantId = "suspend"; break
        case Qt.Key_L: wantId = "lock"; break
        case Qt.Key_E:
        case Qt.Key_X: wantId = "logout"; break
        default: return -1
        }
        for (let i = 0; i < root.actions.length; i++) {
            if (root.actions[i].id === wantId) return i
        }
        return -1
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested()
            event.accepted = true
            return
        }
        // Held keys auto-repeat; the hold animation is already running, ignore.
        if (event.isAutoRepeat) {
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            root.selectedIndex = (root.selectedIndex + root.actions.length - 1) % root.actions.length
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            root.selectedIndex = (root.selectedIndex + 1) % root.actions.length
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.currentItem) root.currentItem.startHold()
            event.accepted = true
            return
        }
        // Press-and-hold shortcut: select that tile and start its hold fill.
        const idx = root.indexForQtKey(event.key)
        if (idx >= 0) {
            root.selectedIndex = idx
            const item = actionsRepeater.itemAt(idx)
            if (item) item.startHold()
            event.accepted = true
        }
    }

    Keys.onReleased: (event) => {
        if (event.isAutoRepeat) {
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.currentItem) root.currentItem.cancelHold()
            event.accepted = true
            return
        }
        // Releasing the shortcut key before 100% aborts that tile's fill.
        const idx = root.indexForQtKey(event.key)
        if (idx >= 0) {
            const item = actionsRepeater.itemAt(idx)
            if (item) item.cancelHold()
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
            lockProc.exec(["hyprlock"])
            break
        case "hibernate":
            Quickshell.execDetached(["systemctl", "hibernate"])
            root.closeRequested()
            break
        case "logout":
            Quickshell.execDetached(["hyprctl", "dispatch", "exit"])
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

        anchors.topMargin: root.contentMarginTop
        anchors.leftMargin: root.contentMarginSide
        anchors.rightMargin: root.contentMarginSide

        spacing: 10

        Repeater {
            id: actionsRepeater

            model: root.actions

            delegate: PowerActionItem {
                width: root.itemWidth
                height: root.itemHeight

                actionId: modelData.id
                label: modelData.label
                shortcutKey: modelData.key
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