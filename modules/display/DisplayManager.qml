import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import "."
import "../../components"

Item {
    id: root

    // Natural size DynamicCenter fits its frame to (the monitor-arrangement
    // canvas genuinely needs the full standard width). Constant -> no loop.
    implicitWidth: 680
    width: parent ? parent.width : 460
    implicitHeight: 500
    height: root.implicitHeight
    clip: true

    // Raised by Cancel so the host (DynamicCenter -> Bar) tears the surface down.
    signal closeRequested()

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
    readonly property real snapPx: 8
    readonly property real releasePx: 12
    property real snapGuideX: NaN
    property real snapGuideY: NaN
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
        root.snapGuideX = rx.guide
        root.snapGuideY = ry.guide

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

    Shape {
        id: background

        anchors.fill: parent
        antialiasing: true
        asynchronous: false
        vendorExtensionsEnabled: true
        preferredRendererType: Shape.CurveRenderer

        readonly property real notchSize: 18
        readonly property real bottomRadius: Theme.cornerRadius

        ShapePath {
            // Transparent: the DynamicCenter frame is the sole panel background.
            fillColor: "transparent"
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

    Column {
        id: contentColumn

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: 16
        }

        width: parent.width - 96
        spacing: 16

        Rectangle {
            id: canvasArea

            width: parent.width
            height: 190
            radius: Theme.cornerRadius
            color: Theme.surface
            clip: true

            Text {
                anchors.centerIn: parent
                visible: DisplayService.monitorNames().length === 0
                text: "No monitors detected"
                color: Theme.textMuted
                font.pixelSize: 12
            }

            // Subtle grid + origin, drawn in logical coordinate space.
            Canvas {
                id: gridCanvas

                anchors.fill: parent

                property real vScale: root.viewScale
                property real vOffX: root.viewOffX
                property real vOffY: root.viewOffY
                readonly property real step: 256   // logical units between grid lines

                onVScaleChanged: requestPaint()
                onVOffXChanged: requestPaint()
                onVOffYChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()

                    const b = root.bounds
                    ctx.lineWidth = 1
                    ctx.strokeStyle = String(Theme.text)
                    ctx.globalAlpha = 0.06

                    const x0 = Math.floor(b.minX / step) * step
                    for (let gx = x0; gx <= b.maxX + step; gx += step) {
                        const cx = Math.round(root.logicalToCanvasX(gx)) + 0.5
                        ctx.beginPath()
                        ctx.moveTo(cx, 0)
                        ctx.lineTo(cx, height)
                        ctx.stroke()
                    }
                    const y0 = Math.floor(b.minY / step) * step
                    for (let gy = y0; gy <= b.maxY + step; gy += step) {
                        const cy = Math.round(root.logicalToCanvasY(gy)) + 0.5
                        ctx.beginPath()
                        ctx.moveTo(0, cy)
                        ctx.lineTo(width, cy)
                        ctx.stroke()
                    }

                    // Origin (0,0) crosshair.
                    const ox = root.logicalToCanvasX(0)
                    const oy = root.logicalToCanvasY(0)
                    ctx.globalAlpha = 0.5
                    ctx.strokeStyle = String(Theme.accent)
                    ctx.beginPath()
                    ctx.moveTo(ox - 6, oy)
                    ctx.lineTo(ox + 6, oy)
                    ctx.moveTo(ox, oy - 6)
                    ctx.lineTo(ox, oy + 6)
                    ctx.stroke()
                }
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
                    color: monBlock.selected ? Qt.lighter(Theme.background, 1.4) : Theme.background
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
                        }
                    }

                    MouseArea {
                        id: dragArea

                        anchors.fill: parent

                        property real pressX: 0
                        property real pressY: 0
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
                            dragArea.pressX = mouse.x
                            dragArea.pressY = mouse.y
                            dragArea.origX = monBlock.info.x
                            dragArea.origY = monBlock.info.y
                        }

                        onPositionChanged: (mouse) => {
                            const s = root.viewScale
                            const dx = (mouse.x - dragArea.pressX) / s
                            const dy = (mouse.y - dragArea.pressY) / s
                            root.applyDragSnap(monBlock.modelData, dragArea.origX + dx, dragArea.origY + dy)
                        }

                        onReleased: {
                            root.dragging = false
                            root.snapGuideX = NaN
                            root.snapGuideY = NaN
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

            // Snap guide overlay - only visible mid-drag while a snap is engaged.
            Rectangle {
                visible: root.dragging && !isNaN(root.snapGuideX)
                width: 1
                height: canvasArea.height
                x: root.logicalToCanvasX(root.snapGuideX)
                y: 0
                color: Theme.accent
                opacity: 0.9
            }

            Rectangle {
                visible: root.dragging && !isNaN(root.snapGuideY)
                width: canvasArea.width
                height: 1
                x: 0
                y: root.logicalToCanvasY(root.snapGuideY)
                color: Theme.accent
                opacity: 0.9
            }

            Text {
                visible: root.dragging && root.selectedInfo !== undefined
                anchors { left: parent.left; bottom: parent.bottom; margins: 6 }
                text: root.selectedInfo
                    ? (root.selectedInfo.x + " × " + root.selectedInfo.y)
                    : ""
                color: Theme.accent
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }

        Row {
            spacing: 8

            Repeater {
                model: [
                    { label: "Extend", preset: "extend" },
                    { label: "Mirror", preset: "mirror" },
                    { label: "Internal Only", preset: "internalOnly" },
                    { label: "External Only", preset: "externalOnly" }
                ]

                delegate: Rectangle {
                    id: presetPill

                    required property var modelData

                    width: presetLabel.implicitWidth + 24
                    height: 32
                    radius: height / 2
                    color: presetHover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background

                    HoverHandler {
                        id: presetHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: DisplayService.applyPreset(presetPill.modelData.preset)
                    }

                    Text {
                        id: presetLabel
                        anchors.centerIn: parent
                        text: presetPill.modelData.label
                        color: Theme.text
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: 8
            visible: root.selectedInfo !== undefined

            Text {
                text: DisplayService.selectedMonitor
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.textMuted
                font.pixelSize: 10
                text: root.selectedInfo
                    ? (root.selectedInfo.width + "×" + root.selectedInfo.height
                       + " @ " + root.selectedInfo.refresh + "Hz   •   Scale " + root.selectedInfo.scale
                       + "\nLogical " + root.logicalW(root.selectedInfo) + "×" + root.logicalH(root.selectedInfo)
                       + "   •   Position " + root.selectedInfo.x + "×" + root.selectedInfo.y)
                    : ""
            }

            Rectangle {
                id: resolutionBox

                readonly property string labelText: root.selectedInfo
                    ? (root.selectedInfo.width + "x" + root.selectedInfo.height + "@" + root.selectedInfo.refresh + "Hz")
                    : ""

                width: parent.width
                height: 34
                radius: 8
                color: Theme.background
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
                        color: Qt.lighter(Theme.background, 1.5)
                        border.width: 1
                        border.color: Qt.lighter(Theme.background, 1.6)
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
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                radius: 6
                                color: modeDelegate.hovered ? Qt.lighter(Theme.background, 1.7) : "transparent"
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

            Row {
                spacing: 6

                Repeater {
                    model: [1.0, 1.25, 1.5, 2.0]

                    delegate: Rectangle {
                        id: scalePill

                        required property real modelData
                        readonly property bool active: root.selectedInfo ? root.selectedInfo.scale === scalePill.modelData : false

                        width: 44
                        height: 28
                        radius: 8
                        color: scalePill.active ? Theme.accent : Theme.background

                        TapHandler {
                            onTapped: DisplayService.setScale(DisplayService.selectedMonitor, scalePill.modelData)
                        }

                        Text {
                            anchors.centerIn: parent
                            text: scalePill.modelData.toFixed(2).replace(/0+$/, "").replace(/\.$/, "")
                            color: scalePill.active ? Theme.background : Theme.text
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Repeater {
                    model: [0, 1, 2, 3]

                    delegate: Rectangle {
                        id: transformPill

                        required property int modelData
                        readonly property bool active: root.selectedInfo ? root.selectedInfo.transform === transformPill.modelData : false

                        width: 44
                        height: 28
                        radius: 8
                        color: transformPill.active ? Theme.accent : Theme.background

                        TapHandler {
                            onTapped: DisplayService.setTransform(DisplayService.selectedMonitor, transformPill.modelData)
                        }

                        Text {
                            anchors.centerIn: parent
                            text: (transformPill.modelData * 90) + "°"
                            color: transformPill.active ? Theme.background : Theme.text
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }

    }

    // Action bar, left-aligned with the content column. Apply (apply live +
    // persist to monitors.lua) and Cancel (discard un-applied edits + close).
    Row {
        id: actionFooter

        anchors {
            bottom: parent.bottom
            left: parent.left
            leftMargin: 48
            bottomMargin: 16
        }

        spacing: 8

        Rectangle {
            id: applyButton

            width: 90
            height: 34
            radius: 8
            color: Theme.accent

            TapHandler {
                onTapped: DisplayService.applyLive()
            }

            Text {
                anchors.centerIn: parent
                text: "Apply"
                color: Theme.background
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            id: cancelButton

            width: 90
            height: 34
            radius: 8
            color: Theme.background
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
                font.weight: Font.DemiBold
            }
        }

        Text {
            id: statusText

            anchors.verticalCenter: parent.verticalCenter
            text: DisplayService.statusMessage
            color: DisplayService.statusIsError ? Theme.accent : Theme.textMuted
            font.pixelSize: 11
        }
    }
}
