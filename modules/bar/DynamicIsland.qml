import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects
import "../services"
import "../../components"

// Dynamic Island for the EXTERNAL monitor only. ONE PanelWindow / ONE surface /
// ONE pill, two sizes: collapsed (clock-only or compact media row) and expanded
// (a taller AND wider media player inside the SAME pill). Click the media row
// to open; collapse via the chevron, Escape, click-outside, or losing the
// track. Driven by the global MediaService.
//
// Diagonal growth: width and height are two plain declarative Behavior
// animations with identical duration/easing on the SAME Rectangle, and the pill
// is anchored top + horizontalCenter, so both dimensions start on the same
// frame, end together, the top edge never moves, and the left/right edges
// expand symmetrically. No SequentialAnimation, no scale substitute, no second
// surface.
//
// Overlay, never push: the Wayland surface is allocated once for the tallest
// state and never resizes at runtime (no per-frame layer-shell resize) and
// reserves no work area at all. It starts hidden and shows only when the
// pointer reaches the top-centre trigger; the pill just fades and slides.
// Only the pill Rectangle inside the surface grows; `clip` reveals its content
// top-down as it does. The input Region covers the trigger plus the shown pill.
PanelWindow {
    id: root

    required property var modelData

    readonly property var mediaService: modelData.mediaService

    screen: modelData.screen

    anchors {
        top: true
        left: true
        right: true
    }

    color: "transparent"

    // Stay above ordinary tiled windows while expanded.
    WlrLayershell.layer: WlrLayer.Top

    // ---- geometry ----------------------------------------------------------
    readonly property int collapsedH: 32
    readonly property int topMargin: 6
    readonly property int expandedH: 156
    // Surface allocation for the tallest state + the 6px top/bottom margins.
    readonly property int surfaceH: expandedH + 2 * topMargin
    // Responsive, capped to sensible horizontal margins on any monitor.
    readonly property real expandedW: Math.max(340, Math.min(480, root.width - 48))

    // Constant at runtime: the surface is allocated for the expanded height up
    // front and never resizes, so there is no per-frame layer-shell resize (and
    // no resize glitch on fractional-scale outputs).
    implicitHeight: root.surfaceH
    // Never reserves work area: the island only overlays windows, so the
    // workspace geometry is identical whether it is shown or hidden.
    exclusiveZone: 0

    focusable: root.expanded

    // Input follows the hit area only: the top-centre trigger while hidden, and
    // the trigger plus the pill once shown. The rest of the window stays
    // click-through. An empty Region would give the compositor a zero-area
    // input region and swallow all clicks.
    mask: hitMask
    Region { id: hitMask; item: hitArea }

    Item {
        id: hitArea

        y: 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.revealed ? Math.max(root.triggerWidth, pill.width) : root.triggerWidth
        height: root.revealed ? pill.y + pill.height : root.triggerHeight
    }

    Item {
        id: triggerHoverArea

        y: 0
        width: root.triggerWidth
        height: root.triggerHeight
        anchors.horizontalCenter: parent.horizontalCenter

        HoverHandler { id: triggerHover }
    }

    readonly property bool pointerInside: triggerHover.hovered || pillHover.hovered

    onPointerInsideChanged: {
        if (root.pointerInside) {
            hideTimer.stop()
            root.revealed = true
        } else if (!root.expanded) {
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: 500
        onTriggered: if (!root.expanded && !root.pointerInside) root.revealed = false
    }

    // Focus grab arms on expand only: a click outside clears it and collapses.
    // Gated on `root.expanded` so it can never interfere with normal pointer
    // input while collapsed.
    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        active: root.expanded
        onCleared: if (root.expanded) root.expanded = false
    }

    // Keyboard fallback: the grab gives the window focus; this catches Escape
    // regardless of which child holds active focus.
    Shortcut {
        sequence: "Escape"
        enabled: root.expanded
        onActivated: root.expanded = false
    }

    readonly property bool hasMedia: root.mediaService && root.mediaService.hasMedia
    readonly property bool playing: root.hasMedia && root.mediaService.playing
    // A valid track keeps the media layout even while paused; losing the track
    // (or session) falls back to the clock. Title is the anchor, so a missing
    // artwork alone never drops back to clock mode.
    readonly property bool mediaMode: root.hasMedia && root.mediaService.title.length > 0
    // Combined "title - artist" string; single value alone when the other is
    // missing, never a dangling separator.
    readonly property string metaString: {
        const t = root.hasMedia ? root.mediaService.title : ""
        const a = root.hasMedia ? root.mediaService.artist : ""
        if (t.length > 0 && a.length > 0) return t + " - " + a
        return t.length > 0 ? t : a
    }

    // Expanded state: opened only by clicking the media row (never by playback
    // events). The pill grows to a fixed, content-independent size, so track
    // changes never oscillate it.
    property bool expanded: false
    // Auto-hide state: the surface is always mapped (so the trigger can take
    // pointer input) but the pill is invisible until the pointer reaches the
    // top-centre trigger. `expanded` always keeps it shown.
    property bool revealed: false
    readonly property int triggerWidth: 220
    readonly property int triggerHeight: 12
    // Losing the track collapses instead of showing an empty pill. Pause and
    // track changes keep mediaMode true, so they never collapse.
    onMediaModeChanged: if (!root.mediaMode) root.expanded = false
    // Give the pill active focus on open so its Keys handler (Escape) works.
    onExpandedChanged: {
        if (root.expanded) {
            hideTimer.stop()
            pill.forceActiveFocus()
        } else if (!pillHover.hovered) {
            hideTimer.restart()
        }
    }

    // Ticks the shared 1 Hz position timer while expanded (shell.qml only
    // drives positionActive for eDP). Owned here, so it clears itself.
    Binding {
        target: root.mediaService
        when: root.mediaService !== null
        property: "islandPositionActive"
        value: root.expanded
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    function _fmt(sec) {
        // NaN / Infinity / null / negative -> 0:00 (never "NaN:NaN").
        if (sec === null || sec === undefined || !isFinite(sec) || sec < 0)
            sec = 0
        const s = Math.floor(sec)
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const r = s % 60
        const mm = (h > 0 && m < 10) ? "0" + m : "" + m
        return (h > 0 ? h + ":" : "") + mm + ":" + (r < 10 ? "0" + r : r)
    }

    Rectangle {
        id: pill

        anchors.top: parent.top
        anchors.topMargin: root.topMargin
        anchors.horizontalCenter: parent.horizontalCenter

        // The two animated dimensions. Same duration + easing, both triggered
        // by the same `root.expanded` flip, so they change on the same frame
        // and finish together; a mid-flight retarget (rapid track changes,
        // repeated clicks) just re-targets cleanly, no duplicate loops. Height
        // grows downward from the fixed top anchor; width stays centred.
        height: root.expanded ? root.expandedH : root.collapsedH
        width: root.expanded ? root.expandedW
            : root.mediaMode ? mediaRow.implicitWidth + 28
            : Math.max(clockRow.implicitWidth + 48, 130)

        Behavior on width {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        // Adaptive: collapsed stays a true 16px capsule (half the fixed
        // collapsed height 32); expanded becomes a normal 28px rounded
        // rectangle instead of a giant 78px capsule. Both branches are
        // constants, so a single Behavior cross-fades them over the same
        // 300ms/OutCubic as width and height. Radius intentionally does not
        // read the animating `height`, so it cannot fight or lag the resize.
        radius: root.expanded ? 28 : root.collapsedH / 2

        Behavior on radius {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        opacity: root.revealed ? 1 : 0
        transform: Translate {
            y: root.revealed ? 0 : -4

            Behavior on y {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }
        Behavior on opacity {
            NumberAnimation { duration: root.revealed ? 150 : 180; easing.type: Easing.OutCubic }
        }

        // Active focus while expanded so the Keys handler below receives Escape.
        focus: root.expanded
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.expanded = false
                event.accepted = true
            }
        }

        // Reveal the taller content top-down as the pill grows; the collapsed
        // content can never spill past the rounded capsule.
        clip: true

        // Hover tracking for the whole pill (collapsed media row AND expanded
        // player). This is what `pointerInside` reads: without it, hovering the
        // pill body never counted as "inside", so the pill hid 500 ms after the
        // pointer left the 12 px trigger strip even while it was being aimed at,
        // and the collapse path below could never restart the hide timer.
        // Hover-only: it never steals taps from the rows/buttons below it.
        HoverHandler { id: pillHover }

        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.moduleSurfaceOpacity)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)

        // Shared material top light: full-bleed (inset by the 1px border) with
        // the pill's own capsule radius, so it can never paint outside the
        // silhouette (a short rect's radius is clamped to half its height,
        // which desynchronises it from the pill and leaves a stray outline).
        // The falloff is shaped by the stops, not by a clipped rect height.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: pill.radius - 1
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(1, 1, 1, Theme.materialHighlightOpacity)
                }
                GradientStop {
                    position: 0.4
                    color: "transparent"
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }

        // ---- state A: clock only --------------------------------------
        Row {
            id: clockRow

            anchors.centerIn: parent
            visible: !root.mediaMode

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: Theme.text
                font.family: Theme.fontFamily
                font.weight: Font.Bold
                font.pixelSize: 13
            }
        }

        // ---- state B: compact media preview (collapsed) ----------------
        // Artwork left, combined "title - artist" metadata middle, mini
        // visualizer right. Metadata swaps update in place. Long metadata
        // scrolls as a seamless two-copy loop; fitting text stays still.
        // Only the text moves - never the pill, art, or viz.
        Row {
            id: mediaRow

            anchors.centerIn: parent
            visible: root.mediaMode && !root.expanded
            spacing: 10
            onVisibleChanged: if (visible) metaScroll.x = 0

            // Opens the expanded pill. Playback controls live far away from
            // this handler (expanded row / eDP player), never under it.
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: if (!root.expanded) root.expanded = true }

            // Album cover. Rounded via layer OpacityMask (same proven pattern
            // as MediaPreview - never ClippingRectangle, it SIGSEGVs with a
            // bound-source Image child). Missing art shows the ♪ fallback.
            Rectangle {
                id: cover
                width: 24
                height: 24
                radius: 6
                clip: true
                color: Theme.surface
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    id: art
                    anchors.fill: parent
                    source: root.hasMedia ? root.mediaService.artwork : ""
                    sourceSize.width: 48
                    sourceSize.height: 48
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: art.status === Image.Ready
                    layer.enabled: art.status === Image.Ready
                    layer.smooth: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: cover.width
                            height: cover.height
                            radius: cover.radius
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: "♪"
                    color: Theme.textMuted
                    font.pixelSize: 12
                }
            }

            Item {
                id: metaView
                width: Math.min(metaSingle.implicitWidth, 200)
                height: metaSingle.implicitHeight
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                onOverflowChanged: if (!overflow) metaScroll.x = 0

                readonly property bool overflow: metaSingle.implicitWidth > metaView.width + 0.5
                readonly property real loopDist: metaSingle.implicitWidth + metaSep.implicitWidth

                Text {
                    id: metaSingle
                    visible: false
                    text: root.metaString
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    id: metaSep
                    visible: false
                    text: "   •   "
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    id: metaScroll
                    text: root.metaString + (metaView.overflow ? metaSep.text + root.metaString : "")
                    color: root.playing ? Theme.text : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    maximumLineCount: 1
                    x: 0
                    onTextChanged: metaScroll.x = 0
                    SequentialAnimation on x {
                        running: metaView.overflow && root.mediaMode && !root.expanded && root.revealed
                        loops: Animation.Infinite
                        PauseAnimation { duration: 1200 }
                        NumberAnimation {
                            to: -metaView.loopDist
                            duration: Math.max(900, metaView.loopDist * 22)
                            easing.type: Easing.Linear
                        }
                        PauseAnimation { duration: 800 }
                        ScriptAction { script: metaScroll.x = 0 }
                    }
                }
            }

            // Mini visualizer. Same data source and shaping as MediaPreview:
            // shared CavaService taps, accent bars, 2px baseline that the
            // 60ms Behavior eases down to whenever audio is paused/offline.
            Item {
                id: viz
                width: 16
                height: 24
                anchors.verticalCenter: parent.verticalCenter

                readonly property bool live: root.playing
                readonly property real barMax: 12
                readonly property var spec: CavaService.bars
                readonly property var taps: [1, 8, 16]
                readonly property real gain: 1.6

                Row {
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: 3

                        delegate: Item {
                            id: cell
                            required property int index
                            width: 3
                            height: viz.barMax
                            anchors.verticalCenter: parent.verticalCenter

                            readonly property int tap: viz.taps[cell.index]
                            readonly property real level: (viz.live && viz.spec && viz.spec.length > cell.tap)
                                ? Math.max(0, Math.min(1, viz.spec[cell.tap] * viz.gain))
                                : 0

                            Rectangle {
                                width: parent.width
                                radius: width / 2
                                color: Theme.accent
                                anchors.bottom: parent.bottom
                                height: Math.max(2, viz.barMax * cell.level)
                                Behavior on height {
                                    NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- state C: expanded media player (same pill, grown) --------
        // Anchored to the pill's left/right/top so it tracks the animated width
        // (content re-flows horizontally) while the top-down clip reveals it as
        // the pill grows downward. Nothing here can collapse the pill; only the
        // chevron, Escape, and click-outside do.
        Item {
            id: expandedContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.expandedH
            visible: root.expanded

            // Album artwork (larger), with the same ♪ fallback.
            Rectangle {
                id: coverX
                x: 24
                y: 18
                width: 88
                height: 88
                radius: 14
                clip: true
                color: Theme.surface

                Image {
                    id: artX
                    anchors.fill: parent
                    source: root.hasMedia ? root.mediaService.artwork : ""
                    sourceSize.width: 176
                    sourceSize.height: 176
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: artX.status === Image.Ready
                    layer.enabled: artX.status === Image.Ready
                    layer.smooth: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: coverX.width
                            height: coverX.height
                            radius: coverX.radius
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: artX.status !== Image.Ready
                    text: "♪"
                    color: Theme.textMuted
                    font.pixelSize: 26
                }
            }

            // Explicit collapse affordance, top-right, clear of the metadata.
            Item {
                id: collapseBtn
                width: 28
                height: 28
                anchors.right: parent.right
                anchors.rightMargin: 16
                y: 18

                HoverHandler { id: collapseHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.expanded = false }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: collapseHover.hovered ? Theme.surfaceHover : "transparent"
                }
                Text {
                    anchors.centerIn: parent
                    text: "▴"
                    color: collapseHover.hovered ? Theme.text : Theme.textDim
                    font.pixelSize: 16
                }
            }

            Column {
                id: infoCol

                anchors.left: coverX.right
                anchors.leftMargin: 22
                anchors.right: collapseBtn.left
                anchors.rightMargin: 14
                y: 20
                spacing: 5

                Text {
                    width: parent.width
                    text: root.hasMedia ? root.mediaService.title : ""
                    color: root.playing ? Theme.text : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    width: parent.width
                    text: root.hasMedia ? root.mediaService.artist : ""
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Transport (left) + compact player selector chips (right).
                Item {
                    id: controlsRow
                    width: parent.width
                    height: 36

                    component CtlBtn: Item {
                        id: ctl
                        property string glyph: ""
                        property bool enabled: true
                        property real glyphSize: 16
                        signal triggered()

                        width: 36
                        height: 36

                        HoverHandler {
                            id: ctlHover
                            enabled: ctl.enabled
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            enabled: ctl.enabled
                            onTapped: ctl.triggered()
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: ctlHover.hovered ? Theme.surfaceHover : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent
                            text: ctl.glyph
                            color: Theme.text
                            font.pixelSize: ctl.glyphSize
                            opacity: ctl.enabled ? (ctlHover.hovered ? 1 : 0.85) : 0.3
                        }
                    }

                    Row {
                        id: ctlRow
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        CtlBtn {
                            glyph: "⏮"
                            enabled: root.hasMedia && root.mediaService.canPrevious
                            onTriggered: root.mediaService.previous()
                        }
                        CtlBtn {
                            glyph: root.playing ? "⏸" : "▶"
                            glyphSize: 18
                            enabled: root.hasMedia && root.mediaService.canToggle
                            onTriggered: root.mediaService.playPause()
                        }
                        CtlBtn {
                            glyph: "⏭"
                            enabled: root.hasMedia && root.mediaService.canNext
                            onTriggered: root.mediaService.next()
                        }
                    }

                    // Inline selector (only with >1 live player): one chip per
                    // player, the active one accent-outlined. Lives entirely
                    // inside the panel, so it needs no dropdown, no second
                    // surface, and no input-region change.
                    Row {
                        id: playerChips
                        anchors.left: ctlRow.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        clip: true
                        visible: root.mediaService && root.mediaService.players
                            && root.mediaService.players.length > 1

                        Repeater {
                            model: playerChips.visible ? root.mediaService.players : []

                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool current: root.mediaService
                                    && chip.modelData.dbusName === root.mediaService.activeBus

                                width: Math.min(chipLabel.implicitWidth + 18, 110)
                                height: 22
                                radius: 11
                                color: chipHover.hovered ? Theme.surfaceHover
                                    : (chip.current
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                        : Theme.surface)
                                border.width: 1
                                border.color: chip.current ? Theme.accent : "transparent"

                                Text {
                                    id: chipLabel
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    text: chip.modelData.identity + (chip.modelData.isRemote ? " · r" : "")
                                    color: chip.current ? Theme.accent : Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: if (root.mediaService)
                                        root.mediaService.selectPlayer(chip.modelData.dbusName)
                                }
                            }
                        }
                    }
                }

                // Seek / progress line with current + total time. Same
                // MediaService calls and 950ms catch-up tween as MediaPlayer.
                Item {
                    id: seekRow
                    width: parent.width
                    height: 16

                    readonly property bool ready: root.hasMedia
                        && root.mediaService.positionSupported
                        && root.mediaService.effectiveLength > 0
                    readonly property bool seekable: seekRow.ready
                        && root.mediaService.canSeek
                    readonly property real frac: {
                        if (!seekRow.ready)
                            return 0
                        const f = root.mediaService.progressFraction
                        return isFinite(f) ? Math.max(0, Math.min(1, f)) : 0
                    }

                    // While scrubbing the fill follows the pointer directly,
                    // bypassing the catch-up tween (zero visual lag).
                    property bool scrubbing: false
                    property real scrubFrac: 0
                    readonly property real shownFrac: {
                        const f = seekRow.scrubbing ? seekRow.scrubFrac : seekRow.frac
                        return isFinite(f) ? Math.max(0, Math.min(1, f)) : 0
                    }

                    opacity: root.hasMedia ? (seekRow.ready ? 1 : 0.5) : 0

                    Text {
                        id: posLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._fmt(root.hasMedia ? root.mediaService.safePosition : 0)
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                    Text {
                        id: lenLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: seekRow.ready ? root._fmt(root.mediaService.effectiveLength) : "--:--"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Rectangle {
                        id: track
                        anchors.left: posLabel.right
                        anchors.right: lenLabel.left
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: 4
                        radius: 2
                        color: Theme.surface

                        Rectangle {
                            id: fill
                            height: parent.height
                            radius: 2
                            color: Theme.accent
                            visible: seekRow.ready
                            width: parent.width * seekRow.shownFrac
                            Behavior on width {
                                enabled: !seekRow.scrubbing
                                NumberAnimation { duration: 950; easing.type: Easing.Linear }
                            }
                        }

                        Rectangle {
                            id: thumb
                            visible: seekRow.ready
                            width: seekRow.scrubbing ? 8 : 6
                            height: 14
                            radius: 4
                            color: Theme.icon
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(parent.width - width, fill.width - width / 2))
                            Behavior on x {
                                enabled: !seekRow.scrubbing
                                NumberAnimation { duration: 950; easing.type: Easing.Linear }
                            }
                            Behavior on width { NumberAnimation { duration: 90 } }
                        }

                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            anchors.topMargin: -8
                            anchors.bottomMargin: -8
                            enabled: seekRow.seekable
                            preventStealing: true
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            function _apply(mx) {
                                const w = seekArea.width
                                if (!(w > 0))
                                    return
                                const f = Math.max(0, Math.min(1, mx / w))
                                seekRow.scrubFrac = f
                                root.mediaService.setPosition(f * root.mediaService.effectiveLength)
                            }

                            onPressed: (mouse) => {
                                seekRow.scrubbing = true
                                seekArea._apply(mouse.x)
                            }
                            onPositionChanged: (mouse) => {
                                if (pressed)
                                    seekArea._apply(mouse.x)
                            }
                            onReleased: (mouse) => {
                                if (seekRow.seekable && seekArea.width > 0) {
                                    const f = Math.max(0, Math.min(1, mouse.x / seekArea.width))
                                    root.mediaService.setPosition(f * root.mediaService.effectiveLength)
                                }
                                seekRow.scrubbing = false
                            }
                        }
                    }
                }
            }
        }
    }
}
