import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "."
import "../../components"

PanelWindow {
    id: root

    required property var modelData

    readonly property var targetScreen: modelData.screen
    readonly property bool isFocusedScreen: targetScreen
        && Hyprland.focusedMonitor
        && targetScreen.name === Hyprland.focusedMonitor.name

    readonly property var _monitor: root.targetScreen ? Hyprland.monitorFor(root.targetScreen) : null
    property var hoveredWindow: null

    screen: targetScreen
    visible: (CaptureService.regionSelectActive || CaptureService.windowSelectActive) && root.isFocusedScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // Standalone selection (no picker) needs OnDemand focus for its own Esc
    // handler. When the CaptureBar picker is up (openBar's default region mode)
    // the overlay must NOT request keyboard focus: Hyprland would hand an
    // OnDemand layer focus on map, pulling it off the Bar window (tripping that
    // window's focus-grab) AND delivering it stray keystrokes from whatever the
    // user was typing. The picker owns Esc/Cancel in that mode.
    WlrLayershell.keyboardFocus: CaptureService.barVisible
        ? WlrKeyboardFocus.None
        : WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    focusable: !CaptureService.barVisible

    onVisibleChanged: {
        if (root.visible) {
            selectionArea.reset()
            root.hoveredWindow = null
            if (CaptureService.windowSelectActive)
                Hyprland.refreshToplevels()
            // Only claim keyboard focus when running without the picker; with the
            // picker up the Bar window keeps focus (see keyboardFocus above).
            if (!CaptureService.barVisible)
                overlayRoot.forceActiveFocus()
        }
    }

    function activeToplevelGeometry() {
        const mon = root._monitor
        const active = Hyprland.activeToplevel
        const ipc = active ? active.lastIpcObject : null
        if (!mon || !ipc || !ipc.at || !ipc.size || ipc.monitor !== mon.id)
            return null

        return { x: ipc.at[0], y: ipc.at[1], w: ipc.size[0], h: ipc.size[1], appId: ipc.class || "Unknown", focusHistoryID: 0 }
    }

    function updateHovered(px, py) {
        root.hoveredWindow = root.findHoveredWindow(px, py) || root.activeToplevelGeometry()
    }

    function findHoveredWindow(px, py) {
        const mon = root._monitor
        if (!mon)
            return null

        const list = Hyprland.toplevels.values
        let best = null

        for (let i = 0; i < list.length; i++) {
            const ipc = list[i].lastIpcObject
            if (!ipc || !ipc.at || !ipc.size || ipc.hidden)
                continue
            if (ipc.monitor !== mon.id)
                continue
            if (!ipc.workspace || ipc.workspace.id !== (mon.activeWorkspace ? mon.activeWorkspace.id : -1))
                continue

            const x = ipc.at[0]
            const y = ipc.at[1]
            const w = ipc.size[0]
            const h = ipc.size[1]

            if (px < x || px >= x + w || py < y || py >= y + h)
                continue

            const fh = ipc.focusHistoryID !== undefined ? ipc.focusHistoryID : 9999
            if (!best || fh < best.focusHistoryID)
                best = { x: x, y: y, w: w, h: h, appId: ipc.class || "Unknown", focusHistoryID: fh }
        }

        return best
    }

    Process {
        id: cursorPosProc

        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: (exitCode) => {
            if (exitCode !== 0 || !CaptureService.windowSelectActive)
                return

            try {
                const pos = JSON.parse(cursorPosProc.stdout.text)
                if (typeof pos.x === "number" && typeof pos.y === "number")
                    root.updateHovered(pos.x, pos.y)
            } catch (e) {}
        }
    }

    Timer {
        id: cursorPollTimer

        interval: 33
        repeat: true
        running: CaptureService.windowSelectActive && root.visible
        onTriggered: {
            if (!cursorPosProc.running)
                cursorPosProc.running = true
        }
    }

    Item {
        id: overlayRoot

        anchors.fill: parent
        focus: true

        // Esc cancels the active selection immediately (and, as a catch-all,
        // tears down the capture bar too).
        Keys.onEscapePressed: (event) => {
            if (CaptureService.regionSelectActive)
                CaptureService.cancelRegionSelection()
            else if (CaptureService.windowSelectActive)
                CaptureService.cancelWindowSelection()
            else
                CaptureService.closeBar()
            event.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.background
            opacity: 0.35
        }

        MouseArea {
            id: selectionArea

            anchors.fill: parent
            // cursor is enforced window-wide by `cursorLayer` (top of the
            // stack) - a MouseArea.cursorShape here would lose the window's
            // cursor-resolution race to a higher sibling.
            hoverEnabled: true
            enabled: CaptureService.regionSelectActive

            property bool selecting: false
            property real startX: 0
            property real startY: 0
            property real curX: 0
            property real curY: 0

            readonly property real selLeft: Math.min(selectionArea.startX, selectionArea.curX)
            readonly property real selTop: Math.min(selectionArea.startY, selectionArea.curY)
            readonly property real selWidth: Math.abs(selectionArea.curX - selectionArea.startX)
            readonly property real selHeight: Math.abs(selectionArea.curY - selectionArea.startY)

            function reset() {
                selectionArea.selecting = false
                selectionArea.startX = 0
                selectionArea.startY = 0
                selectionArea.curX = 0
                selectionArea.curY = 0
            }

            onPressed: (mouse) => {
                selectionArea.selecting = true
                selectionArea.startX = mouse.x
                selectionArea.startY = mouse.y
                selectionArea.curX = mouse.x
                selectionArea.curY = mouse.y
            }

            onPositionChanged: (mouse) => {
                if (!selectionArea.selecting)
                    return
                selectionArea.curX = Math.max(0, Math.min(mouse.x, root.width))
                selectionArea.curY = Math.max(0, Math.min(mouse.y, root.height))
            }

            onReleased: {
                if (!selectionArea.selecting)
                    return
                selectionArea.selecting = false

                const left = Math.round(selectionArea.selLeft)
                const top = Math.round(selectionArea.selTop)
                const w = Math.round(selectionArea.selWidth)
                const h = Math.round(selectionArea.selHeight)

                if (w < 2 || h < 2) {
                    CaptureService.cancelRegionSelection()
                    return
                }

                const screenX = Math.round((root.targetScreen ? root.targetScreen.x : 0) + left)
                const screenY = Math.round((root.targetScreen ? root.targetScreen.y : 0) + top)

                CaptureService.completeRegionSelection(screenX + "," + screenY + " " + w + "x" + h)
            }
        }

        Rectangle {
            id: selectionRect

            visible: selectionArea.selWidth > 0 && selectionArea.selHeight > 0

            x: selectionArea.selLeft
            y: selectionArea.selTop
            width: selectionArea.selWidth
            height: selectionArea.selHeight

            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
            border.width: 2
            border.color: Theme.accent
        }

        Rectangle {
            id: dimensionLabel

            readonly property string labelText: Math.round(selectionArea.selWidth) + " × " + Math.round(selectionArea.selHeight)
            readonly property real labelWidth: dimensionText.implicitWidth + 16
            readonly property real labelHeight: dimensionText.implicitHeight + 8

            visible: selectionRect.visible

            width: dimensionLabel.labelWidth
            height: dimensionLabel.labelHeight
            radius: 8
            color: Theme.background
            border.width: 1
            border.color: Theme.accent

            x: Math.min(Math.max(selectionRect.x, 0), root.width - dimensionLabel.labelWidth)
            y: selectionRect.y + selectionRect.height + 8 <= root.height - dimensionLabel.labelHeight
                ? selectionRect.y + selectionRect.height + 8
                : Math.max(selectionRect.y - dimensionLabel.labelHeight - 8, 0)

            Text {
                id: dimensionText

                anchors.centerIn: parent

                text: dimensionLabel.labelText
                color: Theme.text
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: windowHoverArea

            anchors.fill: parent
            hoverEnabled: true
            // cursor enforced by `cursorLayer` below (not here - see selectionArea)
            enabled: CaptureService.windowSelectActive

            onPositionChanged: (mouse) => {
                root.updateHovered(
                    (root.targetScreen ? root.targetScreen.x : 0) + mouse.x,
                    (root.targetScreen ? root.targetScreen.y : 0) + mouse.y)
            }

            onClicked: {
                if (!root.hoveredWindow)
                    return

                const g = root.hoveredWindow
                CaptureService.completeWindowSelection(g.x + "," + g.y + " " + g.w + "x" + g.h)
            }
        }

        Rectangle {
            id: windowHighlight

            readonly property var geo: root.hoveredWindow

            visible: CaptureService.windowSelectActive && windowHighlight.geo !== null

            x: windowHighlight.geo ? windowHighlight.geo.x - (root.targetScreen ? root.targetScreen.x : 0) : 0
            y: windowHighlight.geo ? windowHighlight.geo.y - (root.targetScreen ? root.targetScreen.y : 0) : 0
            width: windowHighlight.geo ? windowHighlight.geo.w : 0
            height: windowHighlight.geo ? windowHighlight.geo.h : 0

            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
            border.width: 2
            border.color: Theme.accent
        }

        Rectangle {
            id: windowBadge

            readonly property string labelText: windowHighlight.geo
                ? windowHighlight.geo.appId + " — " + windowHighlight.geo.w + " × " + windowHighlight.geo.h
                : ""
            readonly property real labelWidth: windowBadgeText.implicitWidth + 16
            readonly property real labelHeight: windowBadgeText.implicitHeight + 8

            visible: windowHighlight.visible

            width: windowBadge.labelWidth
            height: windowBadge.labelHeight
            radius: 8
            color: Theme.background
            border.width: 1
            border.color: Theme.accent

            x: Math.min(Math.max(windowHighlight.x, 0), root.width - windowBadge.labelWidth)
            y: windowHighlight.y - windowBadge.labelHeight - 8 >= 0
                ? windowHighlight.y - windowBadge.labelHeight - 8
                : windowHighlight.y + windowHighlight.height + 8

            Text {
                id: windowBadgeText

                anchors.centerIn: parent

                text: windowBadge.labelText
                color: Theme.text
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }

        // ---- window-wide cursor enforcement --------------------------------
        // Declared last so it is the top-most item in the stack, and uses a
        // (non-grabbing, non-consuming) HoverHandler so every MouseArea above
        // still gets its press/drag/hover. Qt's window cursor resolution picks
        // the top-most hovered item that declares a cursor, so this wins
        // outright - no sibling MouseArea can revert it to the arrow.
        Item {
            id: cursorLayer
            anchors.fill: parent
            z: 999

            HoverHandler {
                cursorShape: CaptureService.regionSelectActive
                    ? Qt.CrossCursor
                    : (CaptureService.windowSelectActive ? Qt.PointingHandCursor : Qt.ArrowCursor)
            }
        }
    }
}
