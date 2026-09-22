import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import "../../components"

// Expanded media player, rendered as a DynamicCenter surface (no PanelWindow of
// its own). Vinyl on the left; to the right a compact vertical stack: title /
// artist, a playback controls row, and the progress / seek line directly below
// it. `active` is set true by
// DynamicCenter only while this surface is on screen, so nothing animates
// otherwise.
Item {
    id: root

    required property var mediaService
    property bool active: false
    // True when opened by clicking the bar preview (vs auto-expand). Gates all
    // focus behavior (focus flag + explicit grabs) and suppresses the 3s
    // auto-hide timer in shell.qml - auto-expand stays fully focus-free.
    property bool manual: false

    signal closeRequested()

    // hasMedia = something to display (live player OR MediaService's last-media
    // cache). Metadata below follows this; the transport controls stay bound to
    // the live `can*` flags, which are false when no real player exists, so a
    // gone player shows frozen metadata with disabled controls (never blank).
    readonly property bool hasMedia: root.mediaService && root.mediaService.hasMedia
    readonly property bool playing: root.hasMedia && root.mediaService.playing
    readonly property bool spinning: root.active && root.playing

    // narrower than the full DynamicCenter surface width
    readonly property int surfaceW: Math.min(470, width)

    // >1 live MPRIS player -> show the player-selector pill in the header gap
    // (and give the card more height for the pill + its dropdown). One/zero
    // players: still spacious, just no pill.
    readonly property bool hasSelector: root.mediaService
        && root.mediaService.players
        && root.mediaService.players.length > 1
    property bool playerMenuOpen: false
    onHasSelectorChanged: if (!root.hasSelector) root.playerMenuOpen = false

    // Natural size DynamicCenter fits its frame to. The inner content is a
    // single centred Row (vinyl + control column) - centring keeps the outer
    // left/right margins identical by construction.
    implicitWidth: 470
    implicitHeight: root.hasSelector ? 210 : 195

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

    // Focus is strictly manual-only: the flag and both explicit grabs are gated
    // on `manual`, so an auto-expand never takes keyboard focus while a manual
    // open behaves as an interactive focused surface (Escape works).
    focus: root.active && root.manual
    onActiveChanged: {
        if (root.active) {
            if (root.manual) root.forceActiveFocus()
        } else {
            root.playerMenuOpen = false
        }
    }
    onVisibleChanged: if (root.visible && root.manual) root.forceActiveFocus()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            if (root.playerMenuOpen)
                root.playerMenuOpen = false
            else
                root.closeRequested()
            event.accepted = true
        }
    }

    // Fallback: if a sub-control (a CtlButton) holds focus, the plain Keys
    // handler above won't see the press - this catches Escape regardless.
    Shortcut {
        sequence: "Escape"
        enabled: root.visible && root.active && !root.playerMenuOpen
        onActivated: root.closeRequested()
    }

    HoverHandler {
        id: surfaceHover
        onHoveredChanged: if (hovered && root.mediaService) root.mediaService.interaction()
    }

    // centred, narrower card
    Item {
        id: card
        width: root.surfaceW
        height: root.height
        anchors.horizontalCenter: parent.horizontalCenter

        // ---- background: solid surface, concave top corners, rounded bottom,
        // matching the other DynamicCenter surfaces.
        Shape {
            id: background
            anchors.fill: parent
            antialiasing: true
            asynchronous: false
            preferredRendererType: Shape.CurveRenderer

            readonly property real notchSize: 18
            readonly property real bottomRadius: Theme.cornerRadius

            ShapePath {
                fillColor: Theme.background
                strokeColor: "transparent"
                strokeWidth: 0

                startX: 0
                startY: 0

                PathCubic {
                    control1X: background.notchSize * 0.5; control1Y: 0
                    control2X: background.notchSize; control2Y: background.notchSize * 0.5
                    x: background.notchSize; y: background.notchSize
                }
                PathLine { x: background.notchSize; y: background.height - background.bottomRadius }
                PathQuad {
                    controlX: background.notchSize; controlY: background.height
                    x: background.notchSize + background.bottomRadius; y: background.height
                }
                PathLine { x: background.width - background.notchSize - background.bottomRadius; y: background.height }
                PathQuad {
                    controlX: background.width - background.notchSize; controlY: background.height
                    x: background.width - background.notchSize; y: background.height - background.bottomRadius
                }
                PathLine { x: background.width - background.notchSize; y: background.notchSize }
                PathCubic {
                    control1X: background.width - background.notchSize; control1Y: background.notchSize * 0.5
                    control2X: background.width - background.notchSize * 0.5; control2Y: 0
                    x: background.width; y: 0
                }
                PathLine { x: 0; y: 0 }
            }
        }

        // ---- player selector pill (only when >1 MPRIS player). Sits in the
        // header gap above the centred content; a tap opens playerMenu below.
        Rectangle {
            id: selectorPill

            visible: root.hasSelector
            z: 10
            anchors.horizontalCenter: parent.horizontalCenter
            y: 7
            height: 25
            // 14px horizontal padding each side + the Row's own 6px spacing.
            width: Math.min(parent.width - background.notchSize * 2 - 16,
                            selectorLabel.implicitWidth + selectorChevron.implicitWidth + 34)
            radius: 20
            color: Theme.background
            border.width: 1
            border.color: Theme.accent

            Row {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    id: selectorLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.mediaService && root.mediaService.identity.length > 0)
                        ? root.mediaService.identity : "Player"
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    id: selectorChevron
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.playerMenuOpen ? "▴" : "▾"
                    color: Theme.textDim
                    font.pixelSize: 12
                }
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    root.playerMenuOpen = !root.playerMenuOpen
                    if (root.mediaService)
                        root.mediaService.interaction()
                }
            }
        }

        // ---- content: vinyl + control column in ONE centred Row. Centring the
        // Row makes the outer left/right margins identical by construction, and
        // the fixed spacing kills the old hollow gap in the middle.
        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 26

            // vinyl disc on the left.
            Item {
                id: vinylWrap
                width: 138
                height: 138
                anchors.verticalCenter: parent.verticalCenter

                Item {
                    id: vinyl
                    width: 138
                    height: 138
                    anchors.centerIn: parent

                    Rectangle {
                        id: disc
                        anchors.fill: parent
                        radius: width / 2
                        color: "#0e0e0e"
                        border.color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1

                        Repeater {
                            model: 2
                            delegate: Rectangle {
                                required property int index
                                anchors.centerIn: parent
                                width: disc.width - 10 - index * 15
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: Qt.rgba(1, 1, 1, 0.045)
                                border.width: 1
                            }
                        }

                        // circular album artwork via layer OpacityMask (proven safe;
                        // do NOT use Quickshell.Widgets.ClippingRectangle - it
                        // SIGSEGVs on 0.3.1 with a bound-source Image child).
                        Rectangle {
                            id: label
                            anchors.centerIn: parent
                            width: disc.width * 0.62
                            height: width
                            radius: width / 2
                            color: Theme.surface

                            Image {
                                id: discArt
                                anchors.fill: parent
                                source: root.hasMedia ? root.mediaService.artwork : ""
                                sourceSize.width: 220
                                sourceSize.height: 220
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                visible: discArt.status === Image.Ready
                                layer.enabled: discArt.status === Image.Ready
                                layer.smooth: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: label.width
                                        height: label.height
                                        radius: width / 2
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: discArt.status !== Image.Ready
                                text: "♪"
                                color: Theme.textMuted
                                font.pixelSize: 22
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
                            color: Theme.background
                        }

                        // continuous rotation that survives pause (reads its own
                        // current rotation) and never resets on a track change.
                        FrameAnimation {
                            running: root.spinning
                            onTriggered: disc.rotation = (disc.rotation + frameTime * 42) % 360
                        }
                    }
                }
            }

            // control column: title / artist, then controls, then progress.
            // Fixed width; every child is centred on the column's axis.
            Column {
                width: 220
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Text {
                    width: parent.width
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: root.hasMedia ? root.mediaService.title : "Nothing playing"
                    color: Theme.text
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    width: parent.width
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    visible: text.length > 0
                    text: root.hasMedia ? root.mediaService.artist : ""
                    color: Theme.textDim
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Item { width: 1; height: 7 }

                // playback controls row: [ ⏮ ⏸/▶ ⏭ ]
                Row {
                    id: ctlRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    component CtlButton: Item {
                        id: btn
                        property string glyph: ""
                        property bool enabled: true
                        property real glyphSize: 16
                        signal triggered()

                        width: 30
                        height: 30

                        HoverHandler {
                            id: bh
                            enabled: btn.enabled
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            enabled: btn.enabled
                            onTapped: {
                                btn.triggered()
                                if (root.mediaService)
                                    root.mediaService.interaction()
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: bh.hovered ? Theme.surfaceHover : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent
                            text: btn.glyph
                            color: Theme.text
                            font.pixelSize: btn.glyphSize
                            opacity: btn.enabled ? (bh.hovered ? 1 : 0.85) : 0.3
                        }
                    }

                    CtlButton {
                        glyph: "⏮"
                        enabled: root.hasMedia && root.mediaService.canPrevious
                        onTriggered: root.mediaService.previous()
                    }
                    CtlButton {
                        glyph: root.playing ? "⏸" : "▶"
                        glyphSize: 18
                        enabled: root.hasMedia && root.mediaService.canToggle
                        onTriggered: root.mediaService.playPause()
                    }
                    CtlButton {
                        glyph: "⏭"
                        enabled: root.hasMedia && root.mediaService.canNext
                        onTriggered: root.mediaService.next()
                    }
                }

                Item { width: 1; height: 7 }

                // progress / seek line: [ 0:24 ━━●━━ 3:34 ], directly below
                // controls, centred on the same axis. Proportioned to the
                // enlarged cluster (~180-200px).
                Item {
                    id: progress
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(180, Math.round(parent.width * 0.72))
                    height: 16

                    // `ready` == a usable duration exists (live OR sticky). It
                    // gates seeking + the total-time label + a dim state - NOT
                    // whether the row renders. `effectiveLength` keeps the bar
                    // geometry alive through a browser's mid-stream length drop.
                    readonly property bool ready: root.hasMedia
                        && root.mediaService.positionSupported
                        && root.mediaService.effectiveLength > 0
                    readonly property bool seekable: progress.ready
                        && root.mediaService && root.mediaService.canSeek
                    readonly property real frac: {
                        if (!progress.ready)
                            return 0
                        const f = root.mediaService.progressFraction
                        return isFinite(f) ? Math.max(0, Math.min(1, f)) : 0
                    }

                    // While scrubbing the fill/thumb follow the pointer directly
                    // (scrubFrac), bypassing the 950ms catch-up tween, so there
                    // is zero visual lag before MPRIS confirms the new position.
                    property bool scrubbing: false
                    property real scrubFrac: 0
                    readonly property real shownFrac: {
                        const f = progress.scrubbing ? progress.scrubFrac : progress.frac
                        return isFinite(f) ? Math.max(0, Math.min(1, f)) : 0
                    }

                    // Row stays put whenever a player is active; only the fill /
                    // thumb / total-time react to whether a duration is known.
                    opacity: root.hasMedia ? (progress.ready ? 1 : 0.5) : 0

                    Text {
                        id: posLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._fmt(root.hasMedia ? root.mediaService.safePosition : 0)
                        color: Theme.textDim
                        font.pixelSize: 9
                    }
                    Text {
                        id: lenLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: progress.ready ? root._fmt(root.mediaService.effectiveLength) : "--:--"
                        color: Theme.textDim
                        font.pixelSize: 9
                    }
                    Rectangle {
                        id: track
                        anchors.left: posLabel.right
                        anchors.right: lenLabel.left
                        anchors.leftMargin: 7
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        height: 4
                        radius: 2
                        color: Theme.surface

                        Rectangle {
                            id: fill
                            height: parent.height
                            radius: 2
                            color: Theme.accent
                            visible: progress.ready
                            width: parent.width * progress.shownFrac
                            Behavior on width {
                                enabled: !progress.scrubbing
                                NumberAnimation { duration: 950; easing.type: Easing.Linear }
                            }
                        }
                        // white pill thumb, riding the fill edge. Hidden in the
                        // dim/no-duration state so the empty track reads cleanly.
                        Rectangle {
                            id: thumb
                            visible: progress.ready
                            width: progress.scrubbing ? 8 : 6
                            height: 14
                            radius: 4
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(parent.width - width, fill.width - width / 2))
                            Behavior on x {
                                enabled: !progress.scrubbing
                                NumberAnimation { duration: 950; easing.type: Easing.Linear }
                            }
                            Behavior on width { NumberAnimation { duration: 90 } }
                        }

                        // click / drag to seek
                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            anchors.topMargin: -9
                            anchors.bottomMargin: -9
                            enabled: progress.seekable
                            preventStealing: true
                            cursorShape: Qt.PointingHandCursor

                            property real _lastSec: -1

                            function _apply(mx) {
                                const w = seekArea.width
                                if (!(w > 0))
                                    return
                                const f = Math.max(0, Math.min(1, mx / w))
                                progress.scrubFrac = f
                                const targetSec = f * root.mediaService.effectiveLength
                                // skip near-duplicate D-Bus SetPosition calls
                                if (seekArea._lastSec < 0 || Math.abs(targetSec - seekArea._lastSec) >= 0.4) {
                                    root.mediaService.setPosition(targetSec)
                                    seekArea._lastSec = targetSec
                                }
                                if (root.mediaService)
                                    root.mediaService.interaction()
                            }

                            onPressed: (mouse) => {
                                progress.scrubbing = true
                                seekArea._lastSec = -1
                                seekArea._apply(mouse.x)
                            }
                            onPositionChanged: (mouse) => {
                                if (seekArea.pressed) seekArea._apply(mouse.x)
                            }
                            onReleased: (mouse) => {
                                if (progress.seekable && seekArea.width > 0) {
                                    const f = Math.max(0, Math.min(1, mouse.x / seekArea.width))
                                    root.mediaService.setPosition(f * root.mediaService.effectiveLength)
                                }
                                progress.scrubbing = false
                            }
                            onCanceled: progress.scrubbing = false
                        }
                    }
                }
            }
        }

        // ---- player selector menu -------------------------------------------
        // Click-away catcher + the pop-up list. Both gated on playerMenuOpen.
        MouseArea {
            anchors.fill: parent
            z: 55
            visible: root.playerMenuOpen
            onClicked: root.playerMenuOpen = false
        }

        Rectangle {
            id: playerMenu

            visible: root.playerMenuOpen
            z: 60

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: selectorPill.bottom
            anchors.topMargin: 4

            width: 210
            height: menuCol.implicitHeight + 8
            radius: 8
            color: Theme.background
            border.width: 1
            border.color: Theme.accent

            Column {
                id: menuCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 4
                anchors.leftMargin: 4
                anchors.rightMargin: 4

                Repeater {
                    model: root.mediaService ? root.mediaService.players : []

                    delegate: Rectangle {
                        id: playerRow
                        required property var modelData

                        width: parent.width
                        height: 28
                        radius: 6
                        readonly property bool current: root.mediaService
                            && playerRow.modelData.dbusName === root.mediaService.activeBus
                        color: rowHover.hovered ? Qt.lighter(Theme.background, 1.5)
                            : (playerRow.current ? Qt.lighter(Theme.background, 1.3) : "transparent")

                        Text {
                            anchors.left: parent.left
                            anchors.right: dot.left
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: playerRow.modelData.identity
                                + (playerRow.modelData.isRemote ? "  ·  remote" : "")
                            color: playerRow.current ? Theme.accent : Theme.text
                            font.pixelSize: 11
                            font.weight: playerRow.current ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: dot
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            visible: playerRow.modelData.playing
                            color: Theme.accent
                        }

                        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                if (root.mediaService)
                                    root.mediaService.selectPlayer(playerRow.modelData.dbusName)
                                root.playerMenuOpen = false
                            }
                        }
                    }
                }
            }
        }
    }
}
