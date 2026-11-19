import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import "../../components"

PanelWindow {
    id: root

    required property var mediaService
    property real anchorCenter: 0
    property bool open: false
    property bool closing: false

    signal dismissRequested()

    readonly property real screenWidth: root.screen ? root.screen.width : 1920
    readonly property bool hasMedia: root.mediaService && root.mediaService.hasMedia
    readonly property bool playing: root.hasMedia && root.mediaService.playing
    readonly property bool hasSelector: root.mediaService
        && root.mediaService.players
        && root.mediaService.players.length > 1

    // Player-selector dropdown state, mirroring MediaPlayer's
    // selector pill + menu (and the DynamicIsland's).
    property bool playerMenuOpen: false
    onHasSelectorChanged: if (!root.hasSelector) root.playerMenuOpen = false

    visible: root.open || root.closing

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        right: true
    }

    margins {
        // 44 = strip (36) + gap (8) from the screen top; float adds the
        // strip's top inset so the gap below the strip stays 8.
        top: 44 + (Theme.barFloating ? Theme.barFloatInsetTop : 0)
        // anchorCenter arrives in bar-content coordinates; float insets
        // the content, so shift into screen coordinates by the inset.
        right: Math.max(8, Math.min(root.screenWidth - (root.anchorCenter + (Theme.barFloating ? Theme.barFloatInsetX : 0)) - root.implicitWidth / 2,
            root.screenWidth - root.implicitWidth - 8))
    }

    implicitWidth: card.width + 16
    implicitHeight: card.height + 16

    color: "transparent"

    onOpenChanged: {
        if (root.open) {
            root.playerMenuOpen = false
            root.closing = false
            hideTimer.stop()
            card.forceActiveFocus()
        } else {
            root.closing = true
            hideTimer.restart()
        }
    }

    onHasMediaChanged: if (!root.hasMedia && root.open) root.dismissRequested()

    Timer {
        id: hideTimer
        interval: 170
        onTriggered: root.closing = false
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: {
            if (!root.open)
                return
            root.dismissRequested()
        }
    }

    function _fmt(sec) {
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
        id: card

        anchors.centerIn: parent
        radius: Theme.cornerRadius
        color: Qt.rgba(Theme.panelBackground.r, Theme.panelBackground.g, Theme.panelBackground.b, Theme.moduleSurfaceOpacity)
        border.width: 1
        border.color: Theme.surfaceHover

        width: 420
        height: 236

        Shortcut {
            sequence: "Escape"
            enabled: root.open
            onActivated: root.dismissRequested()
        }

        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.open ? 110 : 140
                easing.type: Easing.OutCubic
            }
        }

        transform: Translate {
            x: root.open ? 0 : 6
            y: root.open ? 0 : -6

            Behavior on x {
                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
            }
        }

        HoverHandler {
            onHoveredChanged: if (hovered && root.mediaService) root.mediaService.interaction()
        }

        Item {
            id: body

            anchors.fill: parent
            anchors.margins: 18

            Row {
                id: header

                width: parent.width
                spacing: 14

                Rectangle {
                    id: artwork

                    width: 116
                    height: 116
                    radius: 16
                    color: Theme.panelSurface

                    Image {
                        id: art

                        anchors.fill: parent
                        source: root.hasMedia ? root.mediaService.artwork : ""
                        sourceSize.width: 232
                        sourceSize.height: 232
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        visible: art.status === Image.Ready
                        layer.enabled: art.status === Image.Ready
                        layer.smooth: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: artwork.width
                                height: artwork.height
                                radius: artwork.radius
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: "\u266a"
                        color: Theme.textMuted
                        font.pixelSize: 30
                    }
                }

                Column {
                    id: infoCol
                    width: header.width - artwork.width - header.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        text: root.hasMedia ? (root.mediaService.title || "Nothing playing") : "Nothing playing"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width
                        visible: text.length > 0
                        text: root.hasMedia ? (root.mediaService.artist || "") : ""
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width
                        visible: text.length > 0
                        text: root.hasMedia ? (root.mediaService.album || "") : ""
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Item {
                        id: selectorSlot
                        width: parent.width
                        height: root.hasSelector ? 22 : 0
                        clip: true

                        // Player selector dropdown pill, mirroring
                        // MediaPlayer's selector pill in the bar (the
                        // menu itself lives at body level, below).
                        Rectangle {
                            id: selectorPill

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(selectorLabel.implicitWidth + selectorChevron.implicitWidth + 30,
                                            parent.width)
                            height: 22
                            visible: root.hasSelector
                            radius: 11
                            color: pillHover.hovered ? Theme.surfaceHover : Theme.background

                            Row {
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    id: selectorLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, selectorPill.width - 44)
                                    text: (root.mediaService && root.mediaService.identity.length > 0)
                                        ? root.mediaService.identity : "Player"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: selectorChevron
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.playerMenuOpen ? "\u25b4" : "\u25be"
                                    color: Theme.textDim
                                    font.pixelSize: 10
                                }
                            }

                            HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    root.playerMenuOpen = !root.playerMenuOpen
                                    if (root.mediaService)
                                        root.mediaService.interaction()
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: progress

                anchors.top: header.bottom
                anchors.topMargin: 14
                width: parent.width
                height: 16

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

                property bool scrubbing: false
                property real scrubFrac: 0
                readonly property real shownFrac: {
                    const f = progress.scrubbing ? progress.scrubFrac : progress.frac
                    return isFinite(f) ? Math.max(0, Math.min(1, f)) : 0
                }

                opacity: root.hasMedia ? (progress.ready ? 1 : 0.5) : 0

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
                    text: progress.ready ? root._fmt(root.mediaService.effectiveLength) : "--:--"
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
                    color: Theme.panelSurface

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

                    Rectangle {
                        id: thumb

                        visible: progress.ready
                        width: progress.scrubbing ? 8 : 6
                        height: 14
                        radius: 4
                        color: Theme.icon
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(parent.width - width, fill.width - width / 2))

                        Behavior on x {
                            enabled: !progress.scrubbing
                            NumberAnimation { duration: 950; easing.type: Easing.Linear }
                        }
                        Behavior on width { NumberAnimation { duration: 90 } }
                    }

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

            Row {
                id: controls

                anchors.top: progress.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                component CtlButton: Item {
                    id: btn

                    property string glyph: ""
                    property bool available: true
                    property real glyphSize: 18

                    signal triggered()

                    width: 34
                    height: 34

                    HoverHandler {
                        id: btnHover
                        enabled: btn.available
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        enabled: btn.available
                        onTapped: {
                            btn.triggered()
                            if (root.mediaService)
                                root.mediaService.interaction()
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: btnHover.hovered ? Theme.surfaceHover : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: btn.glyph
                        color: Theme.text
                        font.pixelSize: btn.glyphSize
                        opacity: btn.available ? (btnHover.hovered ? 1 : 0.85) : 0.3
                    }
                }

                CtlButton {
                    glyph: "\u23ee"
                    available: root.hasMedia && root.mediaService.canPrevious
                    onTriggered: root.mediaService.previous()
                }

                CtlButton {
                    width: 40
                    height: 40
                    glyph: root.playing ? "\u23f8" : "\u25b6"
                    glyphSize: 22
                    available: root.hasMedia && root.mediaService.canToggle
                    onTriggered: root.mediaService.playPause()
                }

                CtlButton {
                    glyph: "\u23ed"
                    available: root.hasMedia && root.mediaService.canNext
                    onTriggered: root.mediaService.next()
                }
            }

            // Click-away catcher for the open player menu (mirrors
            // MediaPlayer): covers the whole card body.
            MouseArea {
                anchors.fill: parent
                z: 55
                visible: root.playerMenuOpen
                onClicked: root.playerMenuOpen = false
            }

            // Player selector menu, dropping down from the selector
            // pill in the header (mirrors MediaPlayer). Positioned
            // by bindings because the pill lives in the header's
            // info column.
            Rectangle {
                id: playerMenu

                visible: root.playerMenuOpen
                z: 60
                x: header.x + infoCol.x + selectorSlot.x + selectorPill.x
                y: header.y + infoCol.y + selectorSlot.y + selectorPill.y + selectorPill.height + 4
                width: Math.min(210, body.width)
                height: menuCol.implicitHeight + 8
                radius: 8
                color: Theme.background

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
                            color: rowHover.hovered ? Theme.surfaceRaised
                                : (playerRow.current ? Theme.surface : "transparent")

                            Text {
                                anchors.left: parent.left
                                anchors.right: dot.left
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: playerRow.modelData.identity
                                    + (playerRow.modelData.isRemote ? "  \u00b7  remote" : "")
                                color: playerRow.current ? Theme.accent : Theme.text
                                font.pixelSize: 11
                                font.family: Theme.fontFamily
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
}
