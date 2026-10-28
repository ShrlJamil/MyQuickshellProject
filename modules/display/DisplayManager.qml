import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import "."
import "../../components"

Item {
    id: root

    // Natural size from the DynamicCenter era (the monitor-arrangement canvas
    // genuinely needs the full standard width), kept as a hint only: the host
    // (the Settings window's Display page) sizes this item explicitly.
    implicitWidth: 680
    implicitHeight: 500
    clip: true

    // Raised by Cancel so the host (the Settings window) tears the page down.
    signal closeRequested()

    // Local Settings surface tokens, set by the host (SettingsView) so this
    // page stays monochrome-dark regardless of the global Wallust palette.
    // Text, accent and hover tokens keep following the global theme.
    property color settingsBackground: "#0A0A0A"
    property color settingsSurface: "#141414"
    property color settingsSurfaceRaised: "#1E1E1E"
    property color settingsSurfaceOverlay: "#2A2A2A"

    readonly property var selectedInfo: DisplayService.layout[DisplayService.selectedMonitor]

    // Cancel: throw away un-applied local edits and close. No `hyprctl eval`, no
    // monitors.lua write, no reload - just rebuild the model straight from the
    // live Hyprland state (which, with nothing Applied, is exactly the config
    // that was active before editing) and dismiss the panel.
    function cancelEdits() {
        DisplayService.suspendSync = false
        DisplayService.syncFromHyprland()
        root.closeRequested()
    }

    // Label for the primary-display dropdown: the human name of whichever
    // monitor currently holds the primary preference - or the saved
    // external's label while that display is disconnected (the internal
    // panel holds the origin meanwhile; see DisplayService).
    function primaryDisplayLabel() {
        const names = DisplayService.monitorNames()
        if (DisplayService.primaryKind === "external") {
            if (DisplayService.preferredExternalPresent()) {
                for (let i = 0; i < names.length; i++)
                    if (DisplayService.isPreferredExternal(names[i]))
                        return DisplayService.humanName(names[i])
            }
            return DisplayService.savedExternalLabel()
        }
        for (let i = 0; i < names.length; i++) {
            const info = DisplayService.layout[names[i]]
            if (info && info.internal)
                return DisplayService.humanName(names[i])
        }
        return ""
    }

    // ---- Logical geometry (Hyprland coordinate space) -----------------------
    // Hyprland positions monitors in LOGICAL pixels: mode size / scale, with
    // width/height swapped for 90/270 rotation. The canvas must draw rectangles
    // in this same space so that "edges touch" on screen == "edges touch" in
    // Hyprland (no forced overlap needed for pointer transitions).
    function isRotated(info) {
        return !!info && (info.transform === 1 || info.transform === 3)
    }

    function logicalW(info) {
        if (!info)
            return 0
        const base = root.isRotated(info) ? info.height : info.width
        return Math.max(1, Math.round(base / (info.scale || 1)))
    }

    function logicalH(info) {
        if (!info)
            return 0
        const base = root.isRotated(info) ? info.width : info.height
        return Math.max(1, Math.round(base / (info.scale || 1)))
    }

    function monitorRect(info) {
        return { x: info.x, y: info.y, w: root.logicalW(info), h: root.logicalH(info) }
    }

    function computeBounds() {
        const names = DisplayService.monitorNames()
        if (names.length === 0)
            return { minX: 0, minY: 0, maxX: 1920, maxY: 1080 }

        // Always include the (0,0) origin so the origin marker stays on-canvas
        // and the viewport does not jump around while a monitor is dragged.
        let minX = 0, minY = 0, maxX = 0, maxY = 0
        for (let i = 0; i < names.length; i++) {
            const m = DisplayService.layout[names[i]]
            if (!m)
                continue
            minX = Math.min(minX, m.x)
            minY = Math.min(minY, m.y)
            maxX = Math.max(maxX, m.x + root.logicalW(m))
            maxY = Math.max(maxY, m.y + root.logicalH(m))
        }
        return { minX: minX, minY: minY, maxX: maxX, maxY: maxY }
    }

    readonly property var bounds: root.computeBounds()
    readonly property real boundW: Math.max(1, root.bounds.maxX - root.bounds.minX)
    readonly property real boundH: Math.max(1, root.bounds.maxY - root.bounds.minY)
    readonly property real canvasPad: 20

    // One uniform pixels-per-logical-unit factor for every monitor - never a
    // per-monitor fit. DP that is 1.5x wider logically is 1.5x wider on canvas.
    readonly property real canvasScale: Math.max(0.0001, Math.min(
        (canvasArea.width - root.canvasPad * 2) / root.boundW,
        (canvasArea.height - root.canvasPad * 2) / root.boundH))
    readonly property real canvasOffsetX: root.canvasPad + (canvasArea.width - root.canvasPad * 2 - root.boundW * root.canvasScale) / 2 - root.bounds.minX * root.canvasScale
    readonly property real canvasOffsetY: root.canvasPad + (canvasArea.height - root.canvasPad * 2 - root.boundH * root.canvasScale) / 2 - root.bounds.minY * root.canvasScale

    // While dragging, freeze the viewport transform so the block tracks the
    // pointer 1:1 and only jumps when a snap actually engages.
    property bool dragging: false
    property real _frozenScale: 0
    property real _frozenOffX: 0
    property real _frozenOffY: 0
    readonly property real viewScale: (root.dragging && root._frozenScale > 0) ? root._frozenScale : root.canvasScale
    readonly property real viewOffX: root.dragging ? root._frozenOffX : root.canvasOffsetX
    readonly property real viewOffY: root.dragging ? root._frozenOffY : root.canvasOffsetY

    function logicalToCanvasX(lx) { return root.viewOffX + lx * root.viewScale }
    function logicalToCanvasY(ly) { return root.viewOffY + ly * root.viewScale }

    // Magnetic snap, measured in screen pixels so it feels the same at any zoom.
    // Hysteresis: engage within snapPx, hold until releasePx, then free again.
    // Kept to a whisper (2/3 px): the magnets - edge adjacency AND edge
    // alignment (tops/bottoms, lefts/rights) - only catch a near-exact
    // miss; anything stronger glues the block to a neighbour and, with
    // the latch flapping at the boundary, makes it visibly shake.
    readonly property real snapPx: 2
    readonly property real releasePx: 3
    // Logical coordinate a snap is currently engaged on (NaN = free) - persists
    // across drag moves so the pointer can travel without re-latching.
    property real _snapEngagedX: NaN
    property real _snapEngagedY: NaN

    // Nearest edge-adjacency / edge-alignment candidate on one axis.
    // Returns { value, guide, distPx } or null when there is no other monitor.
    function _nearestSnap(axis, name, raw, selfW, selfH) {
        const names = DisplayService.monitorNames()
        let best = null

        for (let i = 0; i < names.length; i++) {
            if (names[i] === name)
                continue
            const o = DisplayService.layout[names[i]]
            if (!o || o.disabled)
                continue

            const op = axis === "x" ? o.x : o.y
            const os = axis === "x" ? root.logicalW(o) : root.logicalH(o)
            const ss = axis === "x" ? selfW : selfH

            // [candidate self position, guide-line coordinate]
            const cands = [
                [op + os, op + os],   // self.near  -> other.far  (adjacency)
                [op - ss, op],        // self.far   -> other.near  (adjacency)
                [op, op],             // near edges aligned
                [op + os - ss, op + os] // far edges aligned
            ]
            for (let k = 0; k < cands.length; k++) {
                const distPx = Math.abs(raw - cands[k][0]) * root.viewScale
                if (!best || distPx < best.distPx)
                    best = { value: cands[k][0], guide: cands[k][1], distPx: distPx }
            }
        }
        return best
    }

    // Per-axis magnetic resolve with hysteresis. `engaged` is the currently
    // latched logical value (or NaN). Returns { pos, guide, engaged }.
    function _resolveAxis(axis, name, raw, selfW, selfH, engaged) {
        const snap = root._nearestSnap(axis, name, raw, selfW, selfH)

        if (!isNaN(engaged)) {
            const holdPx = Math.abs(raw - engaged) * root.viewScale
            // Still latched? Let a clearly-closer candidate steal the latch.
            if (snap && snap.distPx <= root.snapPx && snap.value !== engaged && snap.distPx < holdPx)
                return { pos: snap.value, guide: snap.guide, engaged: snap.value }
            if (holdPx <= root.releasePx)
                return { pos: engaged, guide: engaged, engaged: engaged }
            return { pos: raw, guide: NaN, engaged: NaN } // released
        }

        if (snap && snap.distPx <= root.snapPx)
            return { pos: snap.value, guide: snap.guide, engaged: snap.value }
        return { pos: raw, guide: NaN, engaged: NaN }
    }

    // Free drag with magnetic assistance. rawX/rawY follow the pointer exactly;
    // a snap only overrides the committed candidate position, never the pointer.
    function applyDragSnap(name, rawX, rawY) {
        const self = DisplayService.layout[name]
        if (!self)
            return

        const w = root.logicalW(self)
        const h = root.logicalH(self)

        const rx = root._resolveAxis("x", name, rawX, w, h, root._snapEngagedX)
        const ry = root._resolveAxis("y", name, rawY, w, h, root._snapEngagedY)

        root._snapEngagedX = rx.engaged
        root._snapEngagedY = ry.engaged

        DisplayService.setPosition(name, Math.round(rx.pos), Math.round(ry.pos))
    }

    onVisibleChanged: {
        if (root.visible) {
            DisplayService.syncFromHyprland()
            // Take focus so Esc lands here and the bar's HyprlandFocusGrab is
            // armed for click-outside dismiss.
            root.forceActiveFocus()
        }
    }

    // Esc discards un-applied edits and closes (matches the Cancel button).
    Keys.onShortcutOverride: (e) => {
        if (e.key === Qt.Key_Escape) {
            root.cancelEdits()
            e.accepted = true
        }
    }

    // Window-level backstop for when a child control (canvas / resolution
    // combo) holds focus instead of the root.
    Shortcut {
        sequences: ["Escape"]
        enabled: root.visible
        onActivated: root.cancelEdits()
    }

    // ---- Page layout --------------------------------------------------------
    // App-style settings page sharing the Wallpaper page's layout pattern:
    // a pinned header (title only - the page must read without explanation)
    // over a divider, then a scrolling content column, with the action
    // footer pinned below it. Content sections: arrangement card,
    // selected-monitor + display-mode row, selected-monitor card with
    // labelled rows. All
    // state and actions still go through DisplayService exactly as before -
    // this is presentation only.

    // Page header - same title metrics and placement as the Wallpaper page.
    Text {
        id: pageTitle

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 10
            leftMargin: 10
            rightMargin: 10
        }

        text: "Display"
        color: Theme.text
        font.pixelSize: 18
        font.family: Theme.fontFamily
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: headerDivider

        anchors {
            top: pageTitle.bottom
            left: parent.left
            right: parent.right
            topMargin: 14
            leftMargin: 10
            rightMargin: 10
        }

        height: 1
        color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
    }

    Flickable {
        id: flick

        anchors {
            top: headerDivider.bottom
            left: parent.left
            right: parent.right
            bottom: actionFooter.top
            topMargin: 14
        }

        contentWidth: width
        contentHeight: contentColumn.y + contentColumn.height + 16
        clip: true

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: contentColumn

            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }

            width: Math.max(280, Math.min(flick.width - 20, 980))
            spacing: 14

            // Arrangement card: title + the drag canvas. The canvas is kept
            // deliberately plain - no grid, no origin crosshair - so the
            // monitor blocks are the only thing drawn.
            Rectangle {
                id: arrangementCard

                width: parent.width
                height: 238
                radius: 14
                color: settingsSurface
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)

                Text {
                    anchors {
                        top: parent.top
                        left: parent.left
                        topMargin: 12
                        leftMargin: 16
                    }
                    text: "Arrangement"
                    color: Theme.text
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                    font.weight: Font.DemiBold
                }

                Item {
                    id: canvasArea

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: 10
                        rightMargin: 10
                        topMargin: 38
                        bottomMargin: 10
                    }
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        visible: DisplayService.monitorNames().length === 0
                        text: "No monitors detected"
                        color: Theme.textMuted
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }

                    Repeater {
                        model: DisplayService.monitorNames()

                        delegate: Rectangle {
                            id: monBlock

                            required property string modelData
                            readonly property var info: DisplayService.layout[monBlock.modelData]
                            readonly property bool selected: DisplayService.selectedMonitor === monBlock.modelData

                            x: monBlock.info ? root.logicalToCanvasX(monBlock.info.x) : 0
                            y: monBlock.info ? root.logicalToCanvasY(monBlock.info.y) : 0
                            width: monBlock.info ? Math.max(22, root.logicalW(monBlock.info) * root.viewScale) : 22
                            height: monBlock.info ? Math.max(22, root.logicalH(monBlock.info) * root.viewScale) : 22

                            radius: 8
                            opacity: monBlock.info && monBlock.info.disabled ? 0.35 : 1
                            color: monBlock.selected ? settingsSurfaceOverlay : settingsSurfaceRaised
                            border.width: monBlock.selected ? 2 : 1
                            border.color: monBlock.selected ? Theme.accent : Theme.surfaceHover

                            // Animate re-layout, but never while this canvas is being
                            // dragged - there the block must track the pointer exactly.
                            Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on y { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 2

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: monBlock.modelData
                                    color: monBlock.selected ? Theme.accent : Theme.text
                                    font.pixelSize: 12
                                    font.family: Theme.fontFamily
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: monBlock.info !== undefined
                                    text: monBlock.info
                                        ? (root.logicalW(monBlock.info) + "×" + root.logicalH(monBlock.info) + (monBlock.info.mirrorOf ? " (mirror)" : ""))
                                        : ""
                                    color: Theme.textMuted
                                    font.pixelSize: 10
                                    font.family: Theme.fontFamily
                                }
                            }

                            MouseArea {
                                id: dragArea

                                anchors.fill: parent

                                // Without this the page's Flickable steals
                                // the gesture mid-drag and the whole column
                                // (the rows under the card included) scrolls
                                // along under the pointer.
                                preventStealing: true

                                property real pressCanvasX: 0
                                property real pressCanvasY: 0
                                property real origX: 0
                                property real origY: 0

                                onPressed: (mouse) => {
                                    DisplayService.selectedMonitor = monBlock.modelData
                                    DisplayService.suspendSync = true
                                    root._frozenScale = root.canvasScale
                                    root._frozenOffX = root.canvasOffsetX
                                    root._frozenOffY = root.canvasOffsetY
                                    root._snapEngagedX = NaN
                                    root._snapEngagedY = NaN
                                    root.dragging = true
                                    const cp = dragArea.mapToItem(canvasArea, mouse.x, mouse.y)
                                    dragArea.pressCanvasX = cp.x
                                    dragArea.pressCanvasY = cp.y
                                    dragArea.origX = monBlock.info.x
                                    dragArea.origY = monBlock.info.y
                                }

                                onPositionChanged: (mouse) => {
                                    // Pointer tracked in CANVAS coordinates,
                                    // never block-relative ones: the block
                                    // moves to the committed (possibly
                                    // snapped) position, and block-relative
                                    // readings feed that movement back into
                                    // the input - around a latched edge the
                                    // block shook from exactly that loop.
                                    const cp = dragArea.mapToItem(canvasArea, mouse.x, mouse.y)
                                    const s = root.viewScale
                                    const dx = (cp.x - dragArea.pressCanvasX) / s
                                    const dy = (cp.y - dragArea.pressCanvasY) / s
                                    root.applyDragSnap(monBlock.modelData, dragArea.origX + dx, dragArea.origY + dy)
                                }

                                onReleased: {
                                    root.dragging = false
                                    root._snapEngagedX = NaN
                                    root._snapEngagedY = NaN
                                    // Integer normalize + mirror-on-full-overlap only -
                                    // does not yank arbitrary positions onto an edge.
                                    DisplayService.finalizeDrag(monBlock.modelData)
                                    DisplayService.suspendSync = false
                                }
                            }
                        }
                    }

                    Text {
                        visible: root.dragging && root.selectedInfo !== undefined
                        anchors { left: parent.left; bottom: parent.bottom; margins: 6 }
                        text: root.selectedInfo
                            ? (root.selectedInfo.x + " × " + root.selectedInfo.y)
                            : ""
                        color: Theme.accent
                        font.pixelSize: 10
                        font.family: Theme.fontFamily
                        font.weight: Font.DemiBold
                    }
                }
            }

            // Selected monitor + display-mode row, directly under the
            // arrangement card: the selected monitor's name on the left,
            // the display-mode menu trigger on the right. The layout
            // presets (Extend / Mirror / Internal Only / External Only)
            // used to be a segmented control here; they are momentary
            // commands (DisplayService keeps no "current preset" state to
            // show on the trigger), so they now live in modePopup, which
            // opens centred on this row's trigger instead of dropping down.
            Item {
                width: parent.width
                height: 36

                Text {
                    anchors {
                        left: parent.left
                        right: modeBox.left
                        verticalCenter: parent.verticalCenter
                        rightMargin: 12
                    }
                    text: "Selected Monitor: " + DisplayService.selectedMonitor
                    color: Theme.text
                    font.pixelSize: 13
                    font.family: Theme.fontFamily
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    visible: root.selectedInfo !== undefined
                }

                Rectangle {
                    id: modeBox

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    // Same width as the menu it opens (modePopup binds its
                    // width to this box), so the centred menu's edges line
                    // up with the button's and nothing spills past the
                    // content's right edge. The fill is a raised tier, not
                    // settingsBackground: on the same-valued page
                    // background the button was nearly invisible.
                    width: 200
                    height: 32
                    radius: 8
                    color: modeMouse.containsMouse ? settingsSurfaceOverlay : settingsSurfaceRaised
                    border.width: modeMouse.containsMouse ? 1 : 0
                    border.color: Theme.accent

                    Text {
                        id: modeLabel

                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 12
                        }
                        text: "Display Mode"
                        color: Theme.text
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }

                    IconImage {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            rightMargin: 10
                        }
                        width: 14
                        height: 14
                        source: Quickshell.iconPath("pan-down-symbolic", "go-down-symbolic")
                        asynchronous: true
                    }

                    MouseArea {
                        id: modeMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            // Centre the menu on this button: same width,
                            // left edges aligned, vertically centred on the
                            // button - it appears in place over the trigger
                            // instead of dropping down below it.
                            const p = modeBox.mapToItem(root, 0, 0)
                            modePopup.x = p.x
                            modePopup.y = p.y + modeBox.height / 2 - modePopup.implicitHeight / 2
                            modePopup.open()
                        }
                    }
                }
            }

            // Selected-monitor card: labelled rows, label on the left and the
            // control right-aligned, hairline dividers between rows.
            Rectangle {
                id: monitorCard

                width: parent.width
                height: monitorColumn.implicitHeight + 28
                radius: 14
                color: settingsSurface
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
                visible: root.selectedInfo !== undefined

                Column {
                    id: monitorColumn

                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        topMargin: 14
                        leftMargin: 16
                        rightMargin: 16
                    }
                    spacing: 0

                    // Primary display preference. Hyprland has no native
                    // primary-output property, so this selects which display
                    // should sit at logical (0,0); it is stored in
                    // DisplayService (statePath) and enforced in Extend mode
                    // only. A disconnected saved external stays selectable
                    // state shown as an unavailable entry, and the internal
                    // panel keeps the origin meanwhile.
                    Item {
                        width: parent.width
                        height: 42

                        Text {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            text: "Primary display"
                            color: Theme.textMuted
                            font.pixelSize: 12
                            font.family: Theme.fontFamily
                        }

                        Rectangle {
                            id: primaryBox

                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            width: 250
                            height: 32
                            radius: 8
                            color: settingsBackground
                            border.width: primaryMouse.containsMouse ? 1 : 0
                            border.color: Theme.accent

                            Text {
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 12
                                }
                                text: root.primaryDisplayLabel()
                                color: Theme.text
                                font.pixelSize: 12
                                font.family: Theme.fontFamily
                            }

                            IconImage {
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: 10
                                }
                                width: 14
                                height: 14
                                source: Quickshell.iconPath("pan-down-symbolic", "go-down-symbolic")
                                asynchronous: true
                            }

                            MouseArea {
                                id: primaryMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: primaryPopup.open()
                            }

                            Popup {
                                id: primaryPopup

                                y: primaryBox.height + 4
                                width: primaryBox.width
                                padding: 4

                                implicitHeight: Math.min(200, primaryList.contentHeight + primaryList.footerItem.height + 8)

                                background: Rectangle {
                                    radius: 8
                                    color: settingsSurfaceRaised
                                    border.width: 1
                                    border.color: settingsSurfaceOverlay
                                }

                                contentItem: ListView {
                                    id: primaryList

                                    clip: true
                                    implicitHeight: contentHeight
                                    model: DisplayService.monitorNames()

                                    delegate: ItemDelegate {
                                        id: primaryDelegate

                                        required property string modelData
                                        readonly property var info: DisplayService.layout[primaryDelegate.modelData]
                                        readonly property bool active: primaryDelegate.info
                                            ? (primaryDelegate.info.internal
                                                ? DisplayService.primaryKind === "internal"
                                                : DisplayService.isPreferredExternal(primaryDelegate.modelData))
                                            : false

                                        width: primaryList.width
                                        height: 30

                                        contentItem: Text {
                                            leftPadding: 8
                                            text: DisplayService.humanName(primaryDelegate.modelData)
                                            color: primaryDelegate.active ? Theme.accent : Theme.text
                                            font.pixelSize: 11
                                            font.family: Theme.fontFamily
                                            font.weight: primaryDelegate.active ? Font.DemiBold : Font.Normal
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        background: Rectangle {
                                            radius: 6
                                            color: primaryDelegate.hovered ? settingsSurfaceRaised : "transparent"
                                        }

                                        onClicked: {
                                            if (primaryDelegate.info && primaryDelegate.info.internal)
                                                DisplayService.setPrimaryInternal()
                                            else
                                                DisplayService.setPrimaryExternal(primaryDelegate.modelData)
                                            primaryPopup.close()
                                        }
                                    }

                                    footer: ItemDelegate {
                                        id: savedPrimaryDelegate

                                        visible: DisplayService.primaryKind === "external" && !DisplayService.preferredExternalPresent()
                                        enabled: false

                                        width: primaryList.width
                                        height: savedPrimaryDelegate.visible ? 30 : 0

                                        contentItem: Text {
                                            leftPadding: 8
                                            text: DisplayService.savedExternalLabel() + " (unavailable)"
                                            color: Theme.accent
                                            font.pixelSize: 11
                                            font.family: Theme.fontFamily
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        background: Rectangle {
                                            color: "transparent"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
                    }

                    Item {
                        width: parent.width
                        height: 42

                        Text {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            text: "Resolution"
                            color: Theme.textMuted
                            font.pixelSize: 12
                            font.family: Theme.fontFamily
                        }

                        Rectangle {
                            id: resolutionBox

                            readonly property string labelText: root.selectedInfo
                                ? (root.selectedInfo.width + "x" + root.selectedInfo.height + "@" + root.selectedInfo.refresh + "Hz")
                                : ""

                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            width: 250
                            height: 32
                            radius: 8
                            color: settingsBackground
                            border.width: resolutionMouse.containsMouse ? 1 : 0
                            border.color: Theme.accent

                            Text {
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 12
                                }
                                text: resolutionBox.labelText
                                color: Theme.text
                                font.pixelSize: 12
                                font.family: Theme.fontFamily
                            }

                            IconImage {
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: 10
                                }
                                width: 14
                                height: 14
                                source: Quickshell.iconPath("pan-down-symbolic", "go-down-symbolic")
                                asynchronous: true
                            }

                            MouseArea {
                                id: resolutionMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: resolutionPopup.open()
                            }

                            Popup {
                                id: resolutionPopup

                                y: resolutionBox.height + 4
                                width: resolutionBox.width
                                padding: 4

                                implicitHeight: Math.min(200, modeList.contentHeight + 8)

                                background: Rectangle {
                                    radius: 8
                                    color: settingsSurfaceRaised
                                    border.width: 1
                                    border.color: settingsSurfaceOverlay
                                }

                                contentItem: ListView {
                                    id: modeList

                                    clip: true
                                    implicitHeight: contentHeight
                                    model: root.selectedInfo ? root.selectedInfo.availableModes : []

                                    delegate: ItemDelegate {
                                        id: modeDelegate

                                        required property string modelData

                                        width: modeList.width
                                        height: 30

                                        contentItem: Text {
                                            leftPadding: 8
                                            text: modeDelegate.modelData
                                            color: Theme.text
                                            font.pixelSize: 11
                                            font.family: Theme.fontFamily
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        background: Rectangle {
                                            radius: 6
                                            color: modeDelegate.hovered ? settingsSurfaceRaised : "transparent"
                                        }

                                        onClicked: {
                                            const parts = modeDelegate.modelData.split("@")
                                            const dims = parts[0].split("x")
                                            const refresh = parseFloat(parts[1])
                                            DisplayService.setResolution(DisplayService.selectedMonitor, parseInt(dims[0]), parseInt(dims[1]), refresh)
                                            resolutionPopup.close()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
                    }

                    Item {
                        width: parent.width
                        height: 42

                        Text {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            text: "Scale"
                            color: Theme.textMuted
                            font.pixelSize: 12
                            font.family: Theme.fontFamily
                        }

                        Row {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 6

                            Repeater {
                                model: [1.0, 1.25, 1.5, 2.0]

                                delegate: Rectangle {
                                    id: scalePill

                                    required property real modelData
                                    readonly property bool active: root.selectedInfo ? root.selectedInfo.scale === scalePill.modelData : false

                                    width: 44
                                    height: 28
                                    radius: 10
                                    color: scalePill.active ? Theme.accent : settingsBackground

                                    TapHandler {
                                        onTapped: DisplayService.setScale(DisplayService.selectedMonitor, scalePill.modelData)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: scalePill.modelData.toFixed(2).replace(/0+$/, "").replace(/\.$/, "")
                                        color: scalePill.active ? settingsBackground : Theme.text
                                        font.pixelSize: 11
                                        font.family: Theme.fontFamily
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
                    }

                    Item {
                        width: parent.width
                        height: 42

                        Text {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            text: "Rotation"
                            color: Theme.textMuted
                            font.pixelSize: 12
                            font.family: Theme.fontFamily
                        }

                        Row {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 6

                            Repeater {
                                model: [0, 1, 2, 3]

                                delegate: Rectangle {
                                    id: transformPill

                                    required property int modelData
                                    readonly property bool active: root.selectedInfo ? root.selectedInfo.transform === transformPill.modelData : false

                                    width: 44
                                    height: 28
                                    radius: 10
                                    color: transformPill.active ? Theme.accent : settingsBackground

                                    TapHandler {
                                        onTapped: DisplayService.setTransform(DisplayService.selectedMonitor, transformPill.modelData)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: (transformPill.modelData * 90) + "°"
                                        color: transformPill.active ? settingsBackground : Theme.text
                                        font.pixelSize: 11
                                        font.family: Theme.fontFamily
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 26

                        Text {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            text: root.selectedInfo
                                ? ("Logical " + root.logicalW(root.selectedInfo) + "×" + root.logicalH(root.selectedInfo)
                                   + "   •   Position " + root.selectedInfo.x + "×" + root.selectedInfo.y)
                                : ""
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontFamily
                        }
                    }
                }
            }
        }
    }

    // Display-mode menu: the layout presets as a popup centred on its
    // trigger (modeBox, in the row under the arrangement card) - same
    // width as the button, appearing in place over it instead of dropping
    // down. Its x/y are set by the trigger's click handler on open.
    // Picking a row applies the preset immediately, like the old
    // segmented control.
    Popup {
        id: modePopup

        width: modeBox.width
        padding: 4

        background: Rectangle {
            radius: 8
            color: settingsSurfaceRaised
            border.width: 1
            border.color: settingsSurfaceOverlay
        }

        contentItem: Column {
            spacing: 2

            Repeater {
                model: [
                    { label: "Extend", preset: "extend" },
                    { label: "Mirror", preset: "mirror" },
                    { label: "Internal Only", preset: "internalOnly" },
                    { label: "External Only", preset: "externalOnly" }
                ]

                delegate: Rectangle {
                    id: modeRow

                    required property var modelData

                    width: modePopup.width - 8
                    height: 32
                    radius: 6
                    color: modeRowHover.hovered ? settingsSurfaceOverlay : "transparent"

                    HoverHandler {
                        id: modeRowHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: {
                            DisplayService.applyPreset(modeRow.modelData.preset)
                            modePopup.close()
                        }
                    }

                    Text {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 8
                        }
                        text: modeRow.modelData.label
                        color: Theme.text
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }
                }
            }
        }
    }

    // Action footer, pinned below the scroll area and aligned with the
    // content column: status message on the left, Cancel (discard un-applied
    // edits + close) and Apply (apply live + persist to monitors.lua) on the
    // right.
    Item {
        id: actionFooter

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: (root.width - contentColumn.width) / 2
            rightMargin: (root.width - contentColumn.width) / 2
            bottomMargin: 10
        }
        height: 40

        Rectangle {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: 1
            color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
        }

        Text {
            id: statusText

            anchors {
                left: parent.left
                bottom: parent.bottom
            }
            height: 30
            verticalAlignment: Text.AlignVCenter
            text: DisplayService.statusMessage
            color: DisplayService.statusIsError ? Theme.accent : Theme.textMuted
            font.pixelSize: 11
            font.family: Theme.fontFamily
        }

        Row {
            anchors {
                right: parent.right
                bottom: parent.bottom
            }
            spacing: 8

            Rectangle {
                id: cancelButton

                width: 90
                height: 30
                radius: 8
                color: settingsBackground
                border.width: 1
                border.color: Theme.accent

                TapHandler {
                    onTapped: root.cancelEdits()
                }

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.accent
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                    font.weight: Font.DemiBold
                }
            }

            Rectangle {
                id: applyButton

                width: 90
                height: 30
                radius: 8
                color: Theme.accent

                TapHandler {
                    onTapped: DisplayService.applyLive()
                }

                Text {
                    anchors.centerIn: parent
                    text: "Apply"
                    color: settingsBackground
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
