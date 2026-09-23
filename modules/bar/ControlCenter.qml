import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Bluetooth
import "../../components"
import "../capture"
import "../display"
import "../services"

PanelWindow {
    id: root

    required property var modelData

    readonly property var barState: modelData.barState

    screen: modelData.screen

    property bool open: barState.mode === "center" && barState.screen === modelData.screen
    property bool closing: false
    property bool pendingCaptureOpen: false
    property bool pendingColorPick: false
    property bool wifiPanelOpen: false
    property bool bluetoothPanelOpen: false
    property bool hotspotPanelOpen: false
    property bool audioOutputPanelOpen: false

    visible: root.open || root.closing

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        right: true
    }

    readonly property real barStripHeight: 40
    readonly property real barGap: 8
    readonly property int barTopMarginDefault: 48
    // Largest amount the async bar probe is allowed to move the panel away from
    // the default before its result is treated as garbage (stale/incomplete
    // hyprctl JSON) and discarded.
    readonly property int barTopMarginMaxDelta: 120
    property int topMargin: root.barTopMarginDefault
    property int barSurfaceTop: 0

    margins {
        top: root.topMargin
        right: 12
    }

    color: "transparent"

    readonly property real colWidth: 210
    readonly property real colGap: 12
    readonly property real wifiHeight: 100
    readonly property real circleSize: 100
    readonly property real circleGap: 10
    readonly property real rowGap: 10
    readonly property real mediaHeight: 210
    readonly property real focusHeight: 100
    readonly property real sliderHeight: 100
    readonly property real tilesHeight: root.wifiHeight + root.rowGap + root.circleSize + root.rowGap + root.focusHeight
    readonly property real contentHeight: root.tilesHeight + root.rowGap + root.sliderHeight + root.rowGap + root.sliderHeight + root.rowGap + root.circleSize

    implicitWidth: root.colWidth * 2 + root.colGap
    implicitHeight: root.contentHeight

    focusable: root.visible

    onVisibleChanged: {
        if (root.visible) {
            root.probeBarSurface()
            // Refresh the monitor model so the Mirror Screen tile shows the real
            // current state (one-shot, same call DisplayManager makes on open).
            DisplayService.syncFromHyprland()
            content.forceActiveFocus()
        } else if (root.pendingCaptureOpen) {
            root.pendingCaptureOpen = false
            console.log("[ControlCenter] Fully unmapped, opening CaptureBar now")
            CaptureService.openBar()
        } else if (root.pendingColorPick) {
            root.pendingColorPick = false
            // Spawn only once the panel is fully unmapped so hyprpicker's
            // overlay/grab doesn't fight the closing Control Center surface.
            hyprpickerProc.running = true
        }
    }

    Component.onCompleted: root.probeBarSurface()

    function probeBarSurface() {
        if (!barProbe.running) barProbe.running = true
    }

    function updateBarSurface() {
        // The panel Y is `screen.y + topMargin`; topMargin is written ONLY here.
        // This runs off an async `hyprctl -j layers` process, so a stale or
        // incomplete result must never fling the window off-screen - any
        // implausible value falls back to the fixed default.
        const def = root.barTopMarginDefault
        try {
            const layers = JSON.parse(barProbe.stdout.text)
            const mon = layers[root.screen.name]
            if (mon == null || mon.levels == null) {
                root.topMargin = def
                return
            }

            root.barSurfaceTop = 0

            for (const key of Object.keys(mon.levels)) {
                const arr = mon.levels[key]
                if (!Array.isArray(arr)) continue

                const level = parseInt(key, 10)

                for (const surf of arr) {
                    if (surf.namespace !== "quickshell" || surf.pid !== Quickshell.processId) continue
                    if (level === 2) root.barSurfaceTop = surf.y
                }
            }

            // Only shift when the bar's own strip surface was actually located,
            // and only by a small sane amount; otherwise keep the default.
            if (root.barSurfaceTop > 0) {
                const target = root.barSurfaceTop + root.barStripHeight + root.barGap
                const screenY = root.screen.y ? root.screen.y : 0
                const candidate = Math.max(8, target - screenY)
                root.topMargin = (Math.abs(candidate - def) <= root.barTopMarginMaxDelta) ? candidate : def
            } else {
                root.topMargin = def
            }
        } catch (e) {
            root.topMargin = def
        }
    }

    Process {
        id: barProbe

        command: ["hyprctl", "-j", "layers"]

        stdout: StdioCollector {
            waitForEnd: true
        }

        onExited: root.updateBarSurface()
    }

    // Color picker: hyprpicker copies the HEX to the clipboard (-a), then a
    // toast on success. A non-zero exit (Esc / cancel) fires no notification.
    Process {
        id: hyprpickerProc

        command: ["hyprpicker", "-a", "-f", "hex"]

        onExited: (exitCode) => {
            if (exitCode === 0)
                pickNotifyProc.running = true
        }
    }

    Process {
        id: pickNotifyProc

        command: ["notify-send", "Color Picker", "Color code copied to clipboard"]
    }

    function close() {
        barState.screen = null
        barState.mode = ""

        if (root.open) {
            root.closing = true
            hideTimer.restart()
        }
    }

    function wifiStatusText(net) {
        if (net === null || net === undefined) return ""
        if (net.connected) return "Connected"
        if (net.connecting) return "Connecting…"
        if (net.failed) return wifiService.connectError !== "" ? wifiService.connectError : "Connection failed"
        if (!net.known && net.secured) return "Password required"
        return (net.secured ? "Secured · " : "Open · ") + net.signal + "%"
    }

    onOpenChanged: {
        if (root.open) {
            root.closing = false
            hideTimer.stop()
        } else {
            root.wifiPanelOpen = false
            root.bluetoothPanelOpen = false
            root.hotspotPanelOpen = false
            root.audioOutputPanelOpen = false
            wifiPanel.promptSsid = ""
            wifiPanel.menuSsid = ""
            wifiPanel.addOpen = false
        }
    }

    Timer {
        id: hideTimer

        // Keep the window mapped just past the ~110ms scale-fade close.
        interval: 140
        onTriggered: root.closing = false
    }

    HyprlandFocusGrab {
        id: focusGrab

        windows: [root]
        active: root.visible

        onCleared: root.close()
    }

    WifiService {
        id: wifiService
    }

    BluetoothService {
        id: bluetoothService
    }

    HotspotService {
        id: hotspotService
    }

    AudioService {
        id: audioService
    }

    BrightnessService {
        id: brightnessService
    }

    MprisService {
        id: mprisService
    }

    NightLightService {
        id: nightLightService
    }

    Item {
        id: content

        anchors.fill: parent

        // Fast scale-fade from the bar trigger's corner (top-right, matching the
        // panel anchor) + a tiny -8px drift. No full-height slide.
        opacity: 0
        scale: 0.92
        transformOrigin: Item.TopRight

        transform: Translate {
            id: drift

            y: -8
        }

        states: [
            State {
                name: "open"

                when: root.open

                PropertyChanges {
                    target: content
                    opacity: 1
                    scale: 1
                }

                PropertyChanges {
                    target: drift
                    y: 0
                }
            }
        ]

        transitions: [
            Transition {
                from: ""
                to: "open"

                ParallelAnimation {
                    NumberAnimation {
                        target: content
                        property: "opacity"
                        duration: 150
                        easing.type: Easing.OutQuad
                    }

                    NumberAnimation {
                        target: content
                        property: "scale"
                        duration: 160
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        target: drift
                        property: "y"
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
            },

            Transition {
                from: "open"
                to: ""

                ParallelAnimation {
                    NumberAnimation {
                        target: content
                        property: "opacity"
                        duration: 100
                        easing.type: Easing.InQuad
                    }

                    NumberAnimation {
                        target: content
                        property: "scale"
                        duration: 110
                        easing.type: Easing.InCubic
                    }

                    NumberAnimation {
                        target: drift
                        property: "y"
                        duration: 110
                        easing.type: Easing.InCubic
                    }
                }
            }
        ]

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                if (root.wifiPanelOpen) root.wifiPanelOpen = false
                else root.close()
                event.accepted = true
            }
        }

        Row {
            id: columns

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }

            height: root.tilesHeight

            spacing: root.colGap

            Column {
                id: leftColumn

                width: root.colWidth

                spacing: root.rowGap

                Rectangle {
                    id: wifiTile

                    readonly property bool wifiOn: wifiService.enabled

                    width: parent.width
                    height: root.wifiHeight

                    // Full pill. The outer capsule ALWAYS stays dark - only the
                    // inner wifiActiveCircle reflects the on/off state.
                    radius: height / 2
                    color: {
                        const c = wifiHover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background
                        return Qt.rgba(c.r, c.g, c.b, Theme.surfaceOpacity)
                    }

                    HoverHandler {
                        id: wifiHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }

                        // Inner padding: clear the full-pill (radius 50) arc.
                        // Left is +4 over the right so the 46px circle's left
                        // gap optically matches its top/bottom arc margin.
                        anchors.leftMargin: 22
                        anchors.rightMargin: 26

                        spacing: 25

                        Item {
                            // Slot matches the enlarged circle so the Row lays
                            // the status column out to its right. Sits flush at
                            // the Row's left (leftMargin 26), i.e. centered in
                            // the capsule's left arc.
                            width: 64
                            height: 64

                            Rectangle {
                                id: wifiActiveCircle

                                anchors.centerIn: parent

                                width: 64
                                height: 64
                                radius: width / 2
                                // ON -> light muted tile, OFF -> subtle dark surface.
                                color: wifiTile.wifiOn ? Theme.activeTile : Theme.surfaceHover
                            }

                            IconImage {
                                id: wifiIcon

                                anchors.centerIn: parent

                                width: 46
                                height: 46

                                source: Quickshell.iconPath("network-wireless-symbolic", "network-wireless")
                                asynchronous: true
                            }

                            // network-wireless-symbolic is a monochrome glyph;
                            // overlay it so it reads as accent on the light ON
                            // circle and as Theme.text when OFF.
                            ColorOverlay {
                                anchors.fill: wifiIcon
                                source: wifiIcon
                                color: wifiTile.wifiOn ? Theme.accent : Theme.icon
                            }

                            MouseArea {
                                anchors.centerIn: parent

                                width: 60
                                height: 60
                                cursorShape: Qt.PointingHandCursor

                                onClicked: wifiService.toggle()
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter

                            width: parent.parent.width - 64 - 12

                            spacing: 2

                            Text {
                                width: parent.width
                                elide: Text.ElideRight

                                text: "Wi-Fi"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideRight

                                text: {
                                    if (!wifiService.enabled) return "Off"
                                    if (wifiService.connected) return wifiService.connectionName
                                    return "Not connected"
                                }

                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }

                    MouseArea {
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            bottom: parent.bottom
                        }

                        // Clear the enlarged 64px toggle circle (Row leftMargin
                        // 26 + 64) so tapping the circle toggles Wi-Fi rather
                        // than opening the panel.
                        anchors.leftMargin: 90
                        anchors.rightMargin: 14

                        cursorShape: Qt.PointingHandCursor

                        onClicked: root.wifiPanelOpen = true
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter

                    spacing: root.circleGap

                    ControlTile {
                        id: bluetoothTile

                        width: root.circleSize
                        height: root.circleSize

                        round: true
                        active: bluetoothService.enabled
                        label: "Bluetooth"
                        iconSource: "file://" + Quickshell.shellPath("assets/bluetooth-svgrepo-com.svg")

                        MouseArea {
                            anchors.fill: parent

                            cursorShape: Qt.PointingHandCursor

                            onClicked: root.bluetoothPanelOpen = true
                        }
                    }

                    ControlTile {
                        id: hotspotTile

                        width: root.circleSize
                        height: root.circleSize

                        round: true
                        active: hotspotService.enabled
                        label: "Mobile"
                        iconSource: "file://" + Quickshell.shellPath("assets/wifi-tethering.svg")

                        MouseArea {
                            anchors.fill: parent

                            cursorShape: Qt.PointingHandCursor

                            onClicked: root.hotspotPanelOpen = true
                        }
                    }
                }

                ControlTile {
                    id: focusTile

                    width: root.colWidth
                    height: root.focusHeight

                    // Full pill, matching the Wi-Fi tile.
                    radiusOverride: height / 2

                    // "Focus" == Do Not Disturb: suppresses notification toasts
                    // (history still recorded). Bound straight to
                    // NotificationService.doNotDisturb. Icon + label are drawn by
                    // the Row below; ControlTile just supplies the tile
                    // background, active fill and hover state.
                    label: "Focus"
                    active: NotificationService.doNotDisturb

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Item {
                            width: 20
                            height: 20
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: focusIconImg

                                anchors.fill: parent
                                sourceSize.width: 40
                                sourceSize.height: 40
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                                mipmap: true
                                visible: false

                                source: "file://" + Quickshell.shellPath("assets/bell-off-svgrepo-com.svg")
                            }

                            ColorOverlay {
                                anchors.fill: focusIconImg
                                source: focusIconImg
                                color: focusTile.active ? Theme.accent : Theme.icon

                                Behavior on color {
                                    ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter

                            text: "Focus"
                            color: focusTile.active ? Theme.accent : Theme.text
                            font.family: Theme.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: 13

                            Behavior on color {
                                ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: NotificationService.toggleDnd()
                    }
                }
            }

            Column {
                id: rightColumn

                width: root.colWidth

                spacing: root.rowGap

                Rectangle {
                    id: mediaTile

                    width: parent.width
                    height: root.mediaHeight

                // Elevated (softer, still rectangular - not a pill).
                radius: 29
                color: {
                    const c = mediaHover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background
                    return Qt.rgba(c.r, c.g, c.b, Theme.surfaceOpacity)
                }

                HoverHandler {
                    id: mediaHover

                    cursorShape: Qt.PointingHandCursor
                }

                MouseArea {
                    anchors.fill: parent

                    cursorShape: Qt.PointingHandCursor

                    onClicked: mprisService.raise()
                }

                Rectangle {
                    id: mediaArt

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: 18
                    anchors.leftMargin: 18

                    width: 80
                    height: 80
                    radius: 16
                    clip: true
                    color: Theme.surface

                    Image {
                        id: mediaArtImage

                        anchors.fill: parent

                        source: mprisService.artUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        visible: mprisService.artUrl !== "" && mediaArtImage.status === Image.Ready

                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: mediaArtImage.width
                                height: mediaArtImage.height
                                radius: mediaArt.radius
                            }
                        }
                    }

                    IconImage {
                        anchors.centerIn: parent

                        width: 36
                        height: 36

                        source: Quickshell.iconPath("multimedia-player-symbolic", "applications-multimedia")
                        asynchronous: true
                        visible: !mediaArtImage.visible
                    }
                }

                Column {
                    id: mediaInfo

                    anchors.top: mediaArt.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: 10
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18

                    spacing: 3

                    Text {
                        width: parent.width
                        elide: Text.ElideRight

                        text: mprisService.trackTitle !== "" ? mprisService.trackTitle : "Nothing playing"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight

                        visible: mprisService.trackArtist !== ""
                        text: mprisService.trackArtist
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                Row {
                    id: mediaControls

                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    anchors.horizontalCenter: parent.horizontalCenter

                    spacing: 24

                    MouseArea {
                        width: 32
                        height: 32
                        enabled: mprisService.canPrev
                        cursorShape: Qt.PointingHandCursor

                        onClicked: mprisService.previous()

                        HoverHandler {
                            id: mediaPrevHover
                        }

                        IconImage {
                            anchors.centerIn: parent

                            width: 20
                            height: 20
                            opacity: !mprisService.canPrev ? 0.3 : (mediaPrevHover.hovered ? 1 : 0.8)

                            source: Quickshell.iconPath("media-skip-backward-symbolic", "media-skip-backward")
                            asynchronous: true
                        }
                    }

                    MouseArea {
                        width: 32
                        height: 32
                        enabled: mprisService.canToggle
                        cursorShape: Qt.PointingHandCursor

                        onClicked: mprisService.playPause()

                        HoverHandler {
                            id: mediaPlayHover
                        }

                        IconImage {
                            anchors.centerIn: parent

                            width: 26
                            height: 26
                            opacity: !mprisService.canToggle ? 0.3 : (mediaPlayHover.hovered ? 1 : 0.9)

                            source: mprisService.isPlaying
                                ? Quickshell.iconPath("media-playback-pause-symbolic", "media-playback-pause")
                                : Quickshell.iconPath("media-playback-start-symbolic", "media-playback-start")
                            asynchronous: true
                        }
                    }

                    MouseArea {
                        width: 32
                        height: 32
                        enabled: mprisService.canNext
                        cursorShape: Qt.PointingHandCursor

                        onClicked: mprisService.next()

                        HoverHandler {
                            id: mediaNextHover
                        }

                        IconImage {
                            anchors.centerIn: parent

                            width: 20
                            height: 20
                            opacity: !mprisService.canNext ? 0.3 : (mediaNextHover.hovered ? 1 : 0.8)

                            source: Quickshell.iconPath("media-skip-forward-symbolic", "media-skip-forward")
                            asynchronous: true
                        }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter

                spacing: root.circleGap

                // Caffeine - paired with Mirror Screen in the round-tiles row.
                // Native Wayland idle-inhibit lives on the Bar; this tile is
                // just the toggle. See CaffeineService.qml.
                ControlTile {
                    id: caffeineTile

                    width: root.circleSize
                    height: root.circleSize

                    round: true
                    label: "Caffeine"
                    active: CaffeineService.enabled
                    iconSource: "file://" + Quickshell.shellPath("assets/coffee-svgrepo-com.svg")

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: CaffeineService.toggle()
                    }
                }

                ControlTile {
                    id: mirrorTile

                    width: root.circleSize
                    height: root.circleSize

                    round: true
                    // Instant Extend <-> Mirror toggle - reuses DisplayService's
                    // applyPreset + applyLive (live + persist). Does NOT open the
                    // Display Manager. Active style follows the real mirror state.
                    label: "Mirror Screen"
                    active: DisplayService.mirrorActive
                    iconSource: "file://" + Quickshell.shellPath("assets/display-mode.svg")
                    opacity: DisplayService.canMirror ? 1 : 0.4

                    MouseArea {
                        anchors.fill: parent

                        enabled: DisplayService.canMirror
                        cursorShape: Qt.PointingHandCursor

                        onClicked: DisplayService.toggleMirror()
                    }
                }
            }
        }
    }

    Rectangle {
        id: displayTile

            anchors {
                left: parent.left
                right: parent.right
                top: columns.bottom
            }

            anchors.topMargin: root.rowGap

            height: root.sliderHeight

            // Full pill.
            radius: height / 2
            color: {
                const c = displayHover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background
                return Qt.rgba(c.r, c.g, c.b, Theme.surfaceOpacity)
            }

            HoverHandler {
                id: displayHover

                cursorShape: Qt.PointingHandCursor
            }

            Text {
                id: displayLabel

                anchors {
                    left: parent.left
                    top: parent.top
                }

                // Larger than the slider's 28px edgeInset below: this label sits
                // near the top of the pill where the radius-50 arc cuts in.
                anchors.leftMargin: 36
                anchors.topMargin: 16

                text: "Brightness"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            ControlSlider {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: displayLabel.bottom
                    bottom: parent.bottom
                }

                // Horizontal inset is owned by ControlSlider.edgeInset (16px)
                // so track / icon / value all align with the title above.
                anchors.leftMargin: 0
                anchors.rightMargin: 0
                anchors.topMargin: 8
                anchors.bottomMargin: 12

                iconSource: {
                    if (brightnessService.brightness < 34)
                        return "file://" + Quickshell.shellPath("assets/brightness/brightness-low-svgrepo-com.svg")
                    if (brightnessService.brightness < 67)
                        return "file://" + Quickshell.shellPath("assets/brightness/brightness-medium-svgrepo-com.svg")
                    return "file://" + Quickshell.shellPath("assets/brightness/brightness-high-svgrepo-com.svg")
                }
                from: 0
                to: 100
                value: brightnessService.brightness
                rightText: brightnessService.brightness + "%"

                onMoved: (v) => brightnessService.setBrightness(v)
            }
        }

        Rectangle {
            id: soundTile

            anchors {
                left: parent.left
                right: parent.right
                top: displayTile.bottom
            }

            anchors.topMargin: root.rowGap

            height: root.sliderHeight

            // Full pill.
            radius: height / 2
            color: {
                const c = soundHover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background
                return Qt.rgba(c.r, c.g, c.b, Theme.surfaceOpacity)
            }

            HoverHandler {
                id: soundHover

                cursorShape: Qt.PointingHandCursor
            }

            Text {
                id: soundLabel

                anchors {
                    left: parent.left
                    top: parent.top
                }

                // Larger than the slider's 28px edgeInset below: this label sits
                // near the top of the pill where the radius-50 arc cuts in.
                anchors.leftMargin: 36
                anchors.topMargin: 16

                text: "Volume"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            ControlSlider {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: soundLabel.bottom
                    bottom: parent.bottom
                }

                // Horizontal inset is owned by ControlSlider.edgeInset (16px)
                // so track / icon / value all align with the title above.
                anchors.leftMargin: 0
                anchors.rightMargin: 0
                anchors.topMargin: 8
                anchors.bottomMargin: 12

                iconSource: {
                    if (audioService.muted || audioService.volume === 0)
                        return "file://" + Quickshell.shellPath("assets/volume/volume-off-svgrepo-com.svg")
                    if (audioService.volume < 34)
                        return "file://" + Quickshell.shellPath("assets/volume/volume-low-svgrepo-com.svg")
                    if (audioService.volume < 67)
                        return "file://" + Quickshell.shellPath("assets/volume/volume-medium-svgrepo-com.svg")
                    return "file://" + Quickshell.shellPath("assets/volume/volume-high-svgrepo-com.svg")
                }
                // dim the glyph when muted / silent, matching the OSD
                iconColor: (audioService.muted || audioService.volume === 0) ? Theme.textMuted : Theme.icon
                from: 0
                to: 100
                value: audioService.volume
                rightText: audioService.muted ? "Muted" : (audioService.volume + "%")

                onMoved: (v) => audioService.setVolume(v)
                onIconActivated: audioService.toggleMute()
            }
        }

        Row {
            anchors {
                top: soundTile.bottom
                horizontalCenter: parent.horizontalCenter
            }

            anchors.topMargin: root.rowGap

            height: root.circleSize

            spacing: root.circleGap

            ControlTile {
                id: screenCaptureTile

                property bool pulse: false

                width: root.circleSize
                height: root.circleSize

                round: true
                active: screenCaptureTile.pulse
                label: "Capture"
                iconSource: "file://" + Quickshell.shellPath("assets/capture.svg")

                Timer {
                    id: capturePulseTimer

                    interval: 200
                    onTriggered: screenCaptureTile.pulse = false
                }

                MouseArea {
                    anchors.fill: parent

                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        console.log("[Tile Click] Capture tile pressed")
                        screenCaptureTile.pulse = true
                        capturePulseTimer.restart()
                        root.pendingCaptureOpen = true
                        root.close()
                    }
                }
            }

            ControlTile {
                id: nightLightTile

                width: root.circleSize
                height: root.circleSize

                round: true
                active: nightLightService.active
                label: "Night Light"
                // Local solid-fill SVG so it uses the same ColorOverlay/tint
                // path (and active inversion) as Mic / Output.
                iconSource: "file://" + Quickshell.shellPath("assets/moon-svgrepo-com.svg")

                MouseArea {
                    anchors.fill: parent

                    cursorShape: Qt.PointingHandCursor

                    onClicked: nightLightService.toggle()
                }
            }

            ControlTile {
                id: colorPickerTile

                width: root.circleSize
                height: root.circleSize

                round: true
                active: hyprpickerProc.running
                label: "Color Picker"
                iconSource: "file://" + Quickshell.shellPath("assets/picker-svgrepo-com.svg")

                MouseArea {
                    anchors.fill: parent

                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        root.pendingColorPick = true
                        root.close()
                    }
                }
            }

            ControlTile {
                id: audioOutputTile

                width: root.circleSize
                height: root.circleSize

                round: true
                active: root.audioOutputPanelOpen
                label: "Output"
                iconSource: "file://" + Quickshell.shellPath("assets/media-output.svg")

                MouseArea {
                    anchors.fill: parent

                    cursorShape: Qt.PointingHandCursor

                    onClicked: root.audioOutputPanelOpen = true
                }
            }
        }
    }

    Rectangle {
        id: wifiPanel

        readonly property var originTile: wifiTile
        readonly property point originPos: (drift.y, root.open, wifiPanel.originTile)
            ? wifiPanel.originTile.mapToItem(wifiPanel.parent, 0, 0)
            : Qt.point(0, 0)

        z: 10
        color: Theme.background
        clip: true

        x: root.wifiPanelOpen ? 0 : wifiPanel.originPos.x
        y: root.wifiPanelOpen ? 0 : wifiPanel.originPos.y
        width: root.wifiPanelOpen ? parent.width : wifiPanel.originTile.width
        height: root.wifiPanelOpen ? parent.height : wifiPanel.originTile.height
        radius: root.wifiPanelOpen ? 22 : wifiPanel.originTile.radius
        opacity: root.wifiPanelOpen ? 1 : 0

        enabled: root.wifiPanelOpen
        visible: wifiPanel.opacity > 0

        // Freeze the position tween while the sub-panel is open: x/y are pinned
        // to 0 then, and leaving the Behavior live lets a transient bad
        // originPos (mapToItem re-evaluated every drift frame) animate the panel
        // off toward a wrong coordinate. Size/opacity still animate the reveal.
        Behavior on x {
            enabled: !root.wifiPanelOpen
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: !root.wifiPanelOpen
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on radius {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        property string promptSsid: ""
        property string menuSsid: ""
        property bool addOpen: false
        property bool addSecured: true
        property string addSecurityType: "personal"
        readonly property var menuNet: {
            if (wifiPanel.menuSsid === "") return null
            const list = wifiService.viewNetworks
            for (let i = 0; i < list.length; i++)
                if (list[i].name === wifiPanel.menuSsid) return list[i]
            return null
        }

        onVisibleChanged: {
            if (!wifiPanel.visible) {
                wifiPanel.promptSsid = ""
                wifiPanel.menuSsid = ""
                wifiPanel.addOpen = false
                wifiService.clearError()
            } else {
                wifiService.requestScan()
            }
        }

        onAddOpenChanged: {
            if (wifiPanel.addOpen) {
                wifiService.clearError()
                ssidInput.forceActiveFocus()
            } else {
                ssidInput.text = ""
                usernameInput.text = ""
                hiddenPasswordInput.text = ""
                securityCombo.currentIndex = 0
                wifiPanel.addSecured = true
                wifiPanel.addSecurityType = "personal"
                wifiService.clearError()
            }
        }

        Timer {
            id: wifiRescanTimer

            interval: 12000
            repeat: true
            running: root.wifiPanelOpen
            onTriggered: wifiService.requestScan()
        }

        Item {
            id: wifiPanelContent

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            anchors.margins: 14

            opacity: root.wifiPanelOpen ? 1 : 0
            visible: wifiPanelContent.opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Item {
                id: wifiHeader

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }

                height: 32

                MouseArea {
                    id: backButton

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    width: 32
                    height: 32
                    cursorShape: Qt.PointingHandCursor

                    onClicked: root.wifiPanelOpen = false

                    Rectangle {
                        anchors.fill: parent

                        radius: 16
                        color: backHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"
                    }

                    HoverHandler {
                        id: backHover
                    }

                    IconImage {
                        anchors.centerIn: parent

                        width: 18
                        height: 18

                        source: Quickshell.iconPath("go-previous-symbolic", "go-previous")
                        asynchronous: true
                    }
                }

                Text {
                    anchors.left: backButton.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter

                    text: "Wi-Fi"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: rescanButton

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    width: 32
                    height: 32
                    enabled: wifiService.enabled && !wifiService.scanning
                    cursorShape: Qt.PointingHandCursor

                    onClicked: wifiService.requestScan()

                    Rectangle {
                        anchors.fill: parent

                        radius: 16
                        color: rescanHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"
                    }

                    HoverHandler {
                        id: rescanHover
                    }

                    IconImage {
                        id: rescanIcon

                        anchors.centerIn: parent

                        width: 18
                        height: 18
                        opacity: wifiService.scanning ? 0.4 : 1

                        source: Quickshell.iconPath("view-refresh-symbolic", "view-refresh")
                        asynchronous: true

                        RotationAnimation {
                            id: rescanSpin

                            target: rescanIcon
                            running: wifiService.scanning
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite

                            onRunningChanged: if (!rescanSpin.running) rescanIcon.rotation = 0
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: wifiHeader.bottom
                anchors.topMargin: 12

                text: {
                    if (!wifiService.enabled) return "Wi-Fi is Off"
                    if (wifiService.scanning) return "Scanning for networks…"
                    return "No networks found"
                }
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: 12
                visible: wifiService.viewNetworks.length === 0
            }

            ListView {
                id: wifiList

                anchors {
                    top: wifiHeader.bottom
                    left: parent.left
                    right: parent.right
                    bottom: addRow.top
                }

                anchors.topMargin: 8
                anchors.bottomMargin: 8

                clip: true
                spacing: 4
                visible: wifiService.viewNetworks.length > 0
                model: wifiService.viewNetworks

                delegate: Item {
                    id: row

                    required property var modelData

                    readonly property var net: row.modelData
                    readonly property string ssid: row.net ? row.net.name : ""
                    readonly property bool netConnected: row.net ? row.net.connected : false
                    readonly property bool promptOpen: row.ssid !== "" && wifiPanel.promptSsid === row.ssid
                    readonly property bool menuOpen: row.ssid !== "" && wifiPanel.menuSsid === row.ssid
                    readonly property bool showPrompt: row.promptOpen && !row.netConnected

                    width: wifiList.width
                    height: rowCard.height + (row.showPrompt ? promptBox.height + 6 : 0)

                    onNetConnectedChanged: {
                        if (row.netConnected && wifiPanel.promptSsid === row.ssid)
                            wifiPanel.promptSsid = ""
                        if (!row.netConnected && wifiPanel.menuSsid === row.ssid)
                            wifiPanel.menuSsid = ""
                    }

                    onPromptOpenChanged: {
                        if (row.promptOpen) {
                            passwordField.text = ""
                            passwordField.forceActiveFocus()
                        }
                    }

                    Rectangle {
                        id: rowCard

                        width: parent.width
                        height: 52
                        radius: 14
                        color: rowHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"

                        HoverHandler {
                            id: rowHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        Row {
                            anchors.fill: parent

                            anchors.leftMargin: 12
                            anchors.rightMargin: row.netConnected ? 44 : 12

                            spacing: 10

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter

                                width: 28
                                height: 28

                                source: {
                                    switch (row.net ? row.net.level : -1) {
                                    case 4: return Quickshell.iconPath("network-wireless-signal-excellent-symbolic", "network-wireless-signal-excellent")
                                    case 3: return Quickshell.iconPath("network-wireless-signal-good-symbolic", "network-wireless-signal-good")
                                    case 2: return Quickshell.iconPath("network-wireless-signal-ok-symbolic", "network-wireless-signal-ok")
                                    case 1: return Quickshell.iconPath("network-wireless-signal-weak-symbolic", "network-wireless-signal-weak")
                                    default: return Quickshell.iconPath("network-wireless-signal-none-symbolic", "network-wireless-signal-none")
                                    }
                                }

                                asynchronous: true
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter

                                width: parent.width - 28 - 10

                                spacing: 2

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight

                                    text: row.net ? row.net.name : ""
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: row.net && row.net.connected ? Font.DemiBold : Font.Normal
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight

                                    text: root.wifiStatusText(row.net)
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }

                        }

                        MouseArea {
                            anchors.fill: parent

                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor

                            onClicked: (mouse) => {
                                if (row.net === null || row.net === undefined) return
                                if (mouse.button === Qt.RightButton) {
                                    if (row.net.known) wifiService.forgetNetwork(row.net.name)
                                    return
                                }
                                if (row.netConnected) {
                                    wifiPanel.promptSsid = ""
                                    wifiPanel.menuSsid = row.menuOpen ? "" : row.ssid
                                    return
                                }
                                if (row.net.secured && !row.net.known) {
                                    wifiService.clearError()
                                    wifiPanel.menuSsid = ""
                                    wifiPanel.promptSsid = row.net.name
                                } else {
                                    wifiPanel.promptSsid = ""
                                    wifiPanel.menuSsid = ""
                                    wifiService.connectNetwork(row.net.name)
                                }
                            }
                        }

                        Item {
                            id: moreButton

                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter

                            width: 28
                            height: 28
                            visible: row.netConnected

                            Rectangle {
                                anchors.fill: parent

                                radius: 14
                                color: moreHover.hovered ? Qt.lighter(Theme.background, 1.5) : "transparent"
                            }

                            HoverHandler {
                                id: moreHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            IconImage {
                                anchors.centerIn: parent

                                width: 18
                                height: 18

                                source: Quickshell.iconPath("view-more-symbolic", "open-menu-symbolic")
                                asynchronous: true
                            }

                            MouseArea {
                                anchors.fill: parent

                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    wifiPanel.promptSsid = ""
                                    wifiPanel.menuSsid = row.menuOpen ? "" : row.ssid
                                }
                            }
                        }
                    }

                    Item {
                        id: promptBox

                        anchors.top: rowCard.bottom
                        anchors.topMargin: 6
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        height: 66
                        visible: row.showPrompt

                        Column {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right

                            spacing: 8

                            Rectangle {
                                width: parent.width
                                height: 34

                                radius: 8
                                color: Qt.lighter(Theme.background, 1.3)
                                border.width: passwordField.activeFocus ? 1 : 0
                                border.color: Theme.accent

                                TextField {
                                    id: passwordField

                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10

                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password
                                    passwordCharacter: "•"

                                    placeholderText: "Password"
                                    placeholderTextColor: Theme.textMuted
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12

                                    selectByMouse: true

                                    background: Rectangle {
                                        color: "transparent"
                                    }

                                    onAccepted: {
                                        if (passwordField.text.length > 0)
                                            wifiService.connectNetwork(row.ssid, passwordField.text)
                                    }

                                    Keys.onPressed: (event) => {
                                        if (event.key === Qt.Key_Escape) {
                                            wifiService.clearError()
                                            wifiPanel.promptSsid = ""
                                            content.forceActiveFocus()
                                            event.accepted = true
                                        }
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                height: 24

                                spacing: 12

                                Text {
                                    width: parent.width - connectAction.width - cancelAction.width - 24
                                    height: parent.height
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight

                                    text: {
                                        if (row.net && row.net.connecting) return "Connecting…"
                                        if (wifiService.failedNetwork === row.ssid && wifiService.connectError !== "") return wifiService.connectError
                                        return ""
                                    }
                                    color: wifiService.failedNetwork === row.ssid && !(row.net && row.net.connecting) ? Theme.accent : Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                Text {
                                    id: cancelAction

                                    height: parent.height
                                    verticalAlignment: Text.AlignVCenter

                                    text: "Cancel"
                                    color: cancelHover.hovered ? Theme.text : Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12

                                    HoverHandler {
                                        id: cancelHover

                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    MouseArea {
                                        anchors.fill: parent

                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: {
                                            wifiService.clearError()
                                            wifiPanel.promptSsid = ""
                                            content.forceActiveFocus()
                                        }
                                    }
                                }

                                Text {
                                    id: connectAction

                                    height: parent.height
                                    verticalAlignment: Text.AlignVCenter

                                    readonly property bool ready: passwordField.text.length > 0 && !(row.net && row.net.connecting)

                                    text: "Connect"
                                    color: connectAction.ready ? Theme.accent : Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold

                                    MouseArea {
                                        anchors.fill: parent

                                        enabled: connectAction.ready
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: wifiService.connectNetwork(row.ssid, passwordField.text)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: addRow

                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                z: 5
                height: 36
                radius: 12
                visible: wifiService.enabled
                color: addRowHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"

                HoverHandler {
                    id: addRowHover

                    cursorShape: Qt.PointingHandCursor
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    spacing: 10

                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter

                        width: 18
                        height: 18

                        source: Quickshell.iconPath("list-add-symbolic", "list-add")
                        asynchronous: true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter

                        text: "Add Hidden Network…"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    anchors.fill: parent

                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        wifiPanel.menuSsid = ""
                        wifiPanel.promptSsid = ""
                        wifiPanel.addOpen = true
                    }
                }
            }
        }

        MouseArea {
            id: menuBackdrop

            anchors.fill: parent

            z: 20
            visible: wifiPanel.menuSsid !== ""

            onClicked: wifiPanel.menuSsid = ""
        }

        RectangularGlow {
            visible: menuPopup.visible
            anchors.fill: menuPopup
            z: menuPopup.z
            glowRadius: 16
            spread: 0.35
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32)
            cornerRadius: menuPopup.radius + glowRadius
        }

        Rectangle {
            id: menuPopup

            z: 21
            visible: wifiPanel.menuSsid !== ""

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 14
            anchors.topMargin: 52

            width: 184
            height: menuPopupColumn.height + 12

            // Separation from the dark list comes from the crisp accent hairline
            // plus the outer RectangularGlow behind it; fill stays Theme.background.
            radius: 10
            color: Theme.background
            border.width: 1
            border.color: Theme.accent

            Column {
                id: menuPopupColumn

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 6
                anchors.leftMargin: 6
                anchors.rightMargin: 6

                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 6
                    color: popupDisconnectHover.hovered ? Qt.lighter(Theme.background, 1.5) : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    HoverHandler {
                        id: popupDisconnectHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter

                        text: "Disconnect"
                        color: popupDisconnectHover.hovered ? Theme.accent : Theme.text
                        Behavior on color { ColorAnimation { duration: 100 } }
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            wifiService.disconnectCurrentNetwork()
                            wifiPanel.menuSsid = ""
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 6
                    visible: wifiPanel.menuNet && wifiPanel.menuNet.known
                    color: popupForgetHover.hovered ? Qt.lighter(Theme.background, 1.5) : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    HoverHandler {
                        id: popupForgetHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter

                        text: "Forget Network"
                        color: popupForgetHover.hovered ? Theme.accent : Theme.text
                        Behavior on color { ColorAnimation { duration: 100 } }
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            wifiService.forgetNetwork(wifiPanel.menuSsid)
                            wifiPanel.menuSsid = ""
                        }
                    }
                }
            }
        }

        MouseArea {
            id: addBackdrop

            anchors.fill: parent

            z: 22
            visible: wifiPanel.addOpen

            onClicked: wifiPanel.addOpen = false

            // Scrim: darken the network list behind the input dialog.
            Rectangle {
                anchors.fill: parent
                color: "#90000000"
            }
        }

        RectangularGlow {
            visible: addNetworkModal.visible
            anchors.fill: addNetworkModal
            z: addNetworkModal.z
            glowRadius: 18
            spread: 0.35
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32)
            cornerRadius: addNetworkModal.radius + glowRadius
        }

        Rectangle {
            id: addNetworkModal

            z: 23
            visible: wifiPanel.addOpen

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 58

            width: 300
            height: addModalColumn.implicitHeight + 28

            Behavior on height {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            // Dialog card: Theme.background fill, crisp accent hairline, an outer
            // RectangularGlow for lift, floating over the scrim (addBackdrop).
            radius: 10
            color: Theme.background
            border.width: 1
            border.color: Theme.accent

            Column {
                id: addModalColumn

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 14
                anchors.leftMargin: 14
                anchors.rightMargin: 14

                spacing: 10

                Text {
                    text: "Add Hidden Network"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    width: parent.width
                    height: 34

                    radius: 8
                    color: Qt.lighter(Theme.background, 1.5)
                    border.width: ssidInput.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    TextField {
                        id: ssidInput

                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10

                        verticalAlignment: TextInput.AlignVCenter

                        placeholderText: "Network name (SSID)"
                        placeholderTextColor: Theme.textMuted
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 12

                        selectByMouse: true

                        background: Rectangle {
                            color: "transparent"
                        }

                        onAccepted: {
                            if (securityCombo.currentIndex === 1 && usernameInput.text.length === 0)
                                usernameInput.forceActiveFocus()
                            else if (wifiPanel.addSecured && hiddenPasswordInput.text.length === 0)
                                hiddenPasswordInput.forceActiveFocus()
                            else if (addConnectAction.ready)
                                wifiService.connectHiddenNetwork(ssidInput.text, hiddenPasswordInput.text, wifiPanel.addSecurityType, usernameInput.text)
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                wifiPanel.addOpen = false
                                content.forceActiveFocus()
                                event.accepted = true
                            }
                        }
                    }
                }

                ComboBox {
                    id: securityCombo

                    width: parent.width
                    height: 34

                    font.family: Theme.fontFamily
                    font.pixelSize: 12

                    model: ["WPA/WPA2/WPA3 Personal", "WPA/WPA2/WPA3 Enterprise", "None / Open"]
                    currentIndex: 0

                    onCurrentIndexChanged: {
                        wifiPanel.addSecurityType = securityCombo.currentIndex === 2 ? "open"
                            : securityCombo.currentIndex === 1 ? "enterprise"
                            : "personal"
                        wifiPanel.addSecured = securityCombo.currentIndex !== 2
                        if (securityCombo.currentIndex !== 1)
                            usernameInput.text = ""
                        if (securityCombo.currentIndex === 2)
                            hiddenPasswordInput.text = ""
                    }

                    background: Rectangle {
                        radius: 8
                        color: Qt.lighter(Theme.background, 1.5)
                        border.width: securityCombo.activeFocus || securityCombo.popup.visible ? 1 : 0
                        border.color: Theme.accent
                    }

                    contentItem: Text {
                        leftPadding: 10
                        rightPadding: securityCombo.indicator.width + 6

                        text: securityCombo.displayText
                        color: Theme.text
                        font: securityCombo.font
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    indicator: IconImage {
                        x: securityCombo.width - width - 10
                        y: (securityCombo.height - height) / 2

                        width: 14
                        height: 14

                        source: Quickshell.iconPath("pan-down-symbolic", "go-down-symbolic")
                        asynchronous: true
                    }

                    delegate: ItemDelegate {
                        width: securityCombo.width
                        height: 32

                        highlighted: securityCombo.highlightedIndex === index

                        contentItem: Text {
                            leftPadding: 6

                            text: modelData
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        background: Rectangle {
                            radius: 6
                            color: highlighted ? Qt.lighter(Theme.background, 1.7) : "transparent"
                        }
                    }

                    popup: Popup {
                        y: securityCombo.height + 4
                        width: securityCombo.width
                        padding: 4

                        implicitHeight: contentItem.implicitHeight + 8

                        background: Rectangle {
                            radius: 10
                            color: Theme.background
                            border.width: 1
                            border.color: Theme.accent
                        }

                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: securityCombo.popup.visible ? securityCombo.delegateModel : null
                            currentIndex: securityCombo.highlightedIndex
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 34

                    visible: securityCombo.currentIndex === 1

                    radius: 8
                    color: Qt.lighter(Theme.background, 1.5)
                    border.width: usernameInput.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    TextField {
                        id: usernameInput

                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10

                        verticalAlignment: TextInput.AlignVCenter

                        placeholderText: "Username"
                        placeholderTextColor: Theme.textMuted
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 12

                        selectByMouse: true

                        background: Rectangle {
                            color: "transparent"
                        }

                        onAccepted: hiddenPasswordInput.forceActiveFocus()

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                wifiPanel.addOpen = false
                                content.forceActiveFocus()
                                event.accepted = true
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 34

                    visible: securityCombo.currentIndex !== 2

                    radius: 8
                    color: Qt.lighter(Theme.background, 1.5)
                    border.width: hiddenPasswordInput.activeFocus ? 1 : 0
                    border.color: Theme.accent

                    TextField {
                        id: hiddenPasswordInput

                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10

                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "•"

                        placeholderText: "Password"
                        placeholderTextColor: Theme.textMuted
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 12

                        selectByMouse: true

                        background: Rectangle {
                            color: "transparent"
                        }

                        onAccepted: {
                            if (addConnectAction.ready)
                                wifiService.connectHiddenNetwork(ssidInput.text, hiddenPasswordInput.text, wifiPanel.addSecurityType, usernameInput.text)
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                wifiPanel.addOpen = false
                                content.forceActiveFocus()
                                event.accepted = true
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 24

                    spacing: 12

                    Text {
                        width: parent.width - addConnectAction.width - addCancelAction.width - 24
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight

                        text: {
                            if (wifiService.pendingNetwork !== "" && wifiService.pendingNetwork === ssidInput.text) return "Connecting…"
                            return wifiService.connectError
                        }
                        color: wifiService.connectError !== "" ? Theme.accent : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    Text {
                        id: addCancelAction

                        height: parent.height
                        verticalAlignment: Text.AlignVCenter

                        text: "Cancel"
                        color: addCancelHover.hovered ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 12

                        HoverHandler {
                            id: addCancelHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        MouseArea {
                            anchors.fill: parent

                            cursorShape: Qt.PointingHandCursor

                            onClicked: wifiPanel.addOpen = false
                        }
                    }

                    Text {
                        id: addConnectAction

                        height: parent.height
                        verticalAlignment: Text.AlignVCenter

                        readonly property bool ready: ssidInput.text.length > 0
                            && (securityCombo.currentIndex !== 1 || usernameInput.text.length > 0)
                            && (!wifiPanel.addSecured || hiddenPasswordInput.text.length > 0)

                        text: "Connect"
                        color: addConnectAction.ready ? Theme.accent : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold

                        MouseArea {
                            anchors.fill: parent

                            enabled: addConnectAction.ready
                            cursorShape: Qt.PointingHandCursor

                            onClicked: wifiService.connectHiddenNetwork(ssidInput.text, hiddenPasswordInput.text, wifiPanel.addSecurityType, usernameInput.text)
                        }
                    }
                }
            }

            Connections {
                target: wifiService

                enabled: wifiPanel.addOpen

                function onConnectionNameChanged() {
                    if (wifiPanel.addOpen && ssidInput.text.length > 0 && wifiService.connectionName === ssidInput.text)
                        wifiPanel.addOpen = false
                }
            }
        }
    }

    Rectangle {
        id: bluetoothPanel

        readonly property var originTile: bluetoothTile
        readonly property point originPos: (drift.y, root.open, bluetoothPanel.originTile)
            ? bluetoothPanel.originTile.mapToItem(bluetoothPanel.parent, 0, 0)
            : Qt.point(0, 0)

        z: 11
        color: Theme.background
        clip: true

        x: root.bluetoothPanelOpen ? 0 : bluetoothPanel.originPos.x
        y: root.bluetoothPanelOpen ? 0 : bluetoothPanel.originPos.y
        width: root.bluetoothPanelOpen ? parent.width : bluetoothPanel.originTile.width
        height: root.bluetoothPanelOpen ? parent.height : bluetoothPanel.originTile.height
        radius: root.bluetoothPanelOpen ? 22 : bluetoothPanel.originTile.radius
        opacity: root.bluetoothPanelOpen ? 1 : 0

        enabled: root.bluetoothPanelOpen
        visible: bluetoothPanel.opacity > 0

        property string menuAddr: ""
        readonly property var menuDevice: bluetoothPanel.menuAddr !== "" ? bluetoothService.deviceByAddress(bluetoothPanel.menuAddr) : null

        // The Bluetooth tile is NOT at the panel's top-left (unlike the Wi-Fi
        // tile), so x/y MUST tween on open/close for the panel to morph out of
        // and back into the tile. `enabled: root.open` runs that tween while the
        // Control Center is up, but snaps during the CC's own open/close slide
        // so x/y never chase the origin tile as `content` drifts away.
        Behavior on x {
            enabled: root.open
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: root.open
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on radius {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        onVisibleChanged: {
            if (!bluetoothPanel.visible) {
                bluetoothPanel.menuAddr = ""
                bluetoothService.stopScan()
            } else {
                bluetoothService.requestScan()
            }
        }

        Item {
            id: bluetoothPanelContent

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            anchors.margins: 14

            opacity: root.bluetoothPanelOpen ? 1 : 0
            visible: bluetoothPanelContent.opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Item {
                id: btHeader

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }

                height: 32

                MouseArea {
                    id: btBackButton

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    width: 32
                    height: 32
                    cursorShape: Qt.PointingHandCursor

                    onClicked: root.bluetoothPanelOpen = false

                    Rectangle {
                        anchors.fill: parent

                        radius: 16
                        color: btBackHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"
                    }

                    HoverHandler {
                        id: btBackHover
                    }

                    IconImage {
                        anchors.centerIn: parent

                        width: 18
                        height: 18

                        source: Quickshell.iconPath("go-previous-symbolic", "go-previous")
                        asynchronous: true
                    }
                }

                Text {
                    anchors.left: btBackButton.right
                    anchors.leftMargin: 8
                    anchors.right: btPowerToggle.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter

                    text: "Bluetooth"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: btRescan

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    width: 32
                    height: 32
                    enabled: bluetoothService.enabled && !bluetoothService.scanning
                    cursorShape: Qt.PointingHandCursor

                    onClicked: bluetoothService.requestScan()

                    Rectangle {
                        anchors.fill: parent

                        radius: 16
                        color: btRescanHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"
                    }

                    HoverHandler {
                        id: btRescanHover
                    }

                    IconImage {
                        id: btRescanIcon

                        anchors.centerIn: parent

                        width: 18
                        height: 18
                        opacity: bluetoothService.scanning ? 0.4 : 1

                        source: Quickshell.iconPath("view-refresh-symbolic", "view-refresh")
                        asynchronous: true

                        RotationAnimation {
                            id: btRescanSpin

                            target: btRescanIcon
                            running: bluetoothService.scanning
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite

                            onRunningChanged: if (!btRescanSpin.running) btRescanIcon.rotation = 0
                        }
                    }
                }

                Rectangle {
                    id: btPowerToggle

                    z: 2

                    anchors.right: btRescan.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    width: 44
                    height: 24
                    radius: 12
                    color: bluetoothService.enabled ? Theme.accent : Theme.surface
                    border.width: 1
                    border.color: bluetoothService.enabled ? "transparent" : Qt.rgba(1, 1, 1, 0.2)

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        y: 3
                        x: bluetoothService.enabled ? parent.width - width - 3 : 3
                        color: bluetoothService.enabled ? Theme.background : Theme.textMuted

                        Behavior on x {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: bluetoothService.togglePower()
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: btHeader.bottom
                anchors.topMargin: 12

                text: {
                    if (!bluetoothService.enabled) return "Bluetooth is Off"
                    if (bluetoothService.scanning) return "Scanning for devices…"
                    return "No devices found"
                }
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: 12
                visible: bluetoothService.devices.length === 0
            }

            ListView {
                id: btList

                anchors {
                    top: btHeader.bottom
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                anchors.topMargin: 8

                clip: true
                spacing: 4
                visible: bluetoothService.devices.length > 0
                model: bluetoothService.devices

                delegate: Rectangle {
                    id: btRow

                    required property var modelData

                    readonly property var dev: btRow.modelData
                    readonly property string addr: btRow.dev ? btRow.dev.address : ""
                    // transient BlueZ states - block the row action while in flight
                    readonly property bool btBusy: btRow.dev
                        && (btRow.dev.state === BluetoothDeviceState.Connecting
                            || btRow.dev.state === BluetoothDeviceState.Disconnecting)

                    width: btList.width
                    height: 52
                    radius: 14
                    color: btRowHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"

                    HoverHandler {
                        id: btRowHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    Row {
                        anchors.fill: parent

                        anchors.leftMargin: 12
                        anchors.rightMargin: btRowActions.width + 20

                        spacing: 10

                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter

                            width: 26
                            height: 26

                            source: Quickshell.iconPath(btRow.dev ? btRow.dev.icon : "bluetooth", "bluetooth")
                            asynchronous: true
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter

                            width: parent.width - 26 - 10

                            spacing: 2

                            Text {
                                width: parent.width
                                elide: Text.ElideRight

                                text: btRow.dev ? btRow.dev.name : ""
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: btRow.dev && btRow.dev.connected ? Font.DemiBold : Font.Normal
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideRight

                                text: {
                                    if (!btRow.dev) return ""
                                    if (btRow.dev.state === BluetoothDeviceState.Connecting) return "Connecting…"
                                    if (btRow.dev.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
                                    if (btRow.dev.connected) return "Connected"
                                    if (btRow.dev.paired) return "Paired"
                                    return "Available"
                                }
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            if (btRow.btBusy) return
                            if (btRow.dev && btRow.dev.paired && !btRow.dev.connected)
                                bluetoothService.connectDevice(btRow.addr)
                        }
                    }

                    Row {
                        id: btRowActions

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter

                        spacing: 10

                        // Fixed slots so a device connecting (battery cluster
                        // appearing) or the action label changing length never
                        // reflows the name column - btRowActions.width is constant.
                        //
                        // Battery cluster: [level glyph] [NN%], unified
                        // single-glyph set from assets/best-battery-icon/ (the
                        // charging state is baked into its own glyph, so there is
                        // no separate flash overlay), tinted via ColorOverlay
                        // (the SVGs are solid #000). The cell is a fixed 52px
                        // wide regardless of contents.
                        Item {
                            id: btBatteryCell

                            anchors.verticalCenter: parent.verticalCenter
                            width: 52
                            height: 20

                            readonly property bool hasBattery: btRow.dev && btRow.dev.batteryAvailable
                            readonly property int pct: btBatteryCell.hasBattery
                                ? Math.round(btRow.dev.battery * 100)   // battery is a 0.0-1.0 double
                                : 0
                            // Quickshell.Bluetooth's BluetoothDevice exposes no
                            // charge-state signal, so a BT peripheral never
                            // reports charging; kept for parity with the system
                            // battery mapping, lights up the instant it is true.
                            readonly property bool charging: false

                            readonly property string levelFile: {
                                if (btBatteryCell.charging) return "battery-charging-svgrepo-com.svg"
                                const p = btBatteryCell.pct
                                if (p >= 90) return "battery-full-svgrepo-com.svg"
                                if (p >= 65) return "battery-75-svgrepo-com.svg"
                                if (p >= 35) return "battery-half-svgrepo-com.svg"
                                if (p >= 15) return "battery-low-svgrepo-com.svg"
                                return "battery-empty-svgrepo-com.svg"
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                visible: btBatteryCell.hasBattery

                                Item {
                                    width: 22
                                    height: 18
                                    anchors.verticalCenter: parent.verticalCenter

                                    Image {
                                        id: btLevelImg
                                        anchors.fill: parent
                                        visible: false
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                        sourceSize.width: 44
                                        sourceSize.height: 36
                                        source: "file://" + Quickshell.shellPath("assets/best-battery-icon/" + btBatteryCell.levelFile)
                                    }
                                    ColorOverlay {
                                        anchors.fill: btLevelImg
                                        source: btLevelImg
                                        color: btBatteryCell.charging ? Theme.accent : Theme.textMuted
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    horizontalAlignment: Text.AlignRight
                                    text: btBatteryCell.pct + "%"
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }
                        }

                        Text {
                            id: btActionText

                            anchors.verticalCenter: parent.verticalCenter

                            width: 66
                            horizontalAlignment: Text.AlignRight
                            text: {
                                if (!btRow.dev) return ""
                                if (btRow.dev.connected) return "Disconnect"
                                if (btRow.dev.paired) return "Connect"
                                return "Pair"
                            }
                            color: btActionHover.hovered ? Theme.text : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            opacity: btRow.btBusy ? 0.35 : 1

                            HoverHandler {
                                id: btActionHover

                                enabled: !btRow.btBusy
                                cursorShape: Qt.PointingHandCursor
                            }

                            MouseArea {
                                anchors.fill: parent

                                enabled: !btRow.btBusy
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    if (!btRow.dev) return
                                    if (btRow.dev.connected) bluetoothService.disconnectDevice(btRow.addr)
                                    else if (btRow.dev.paired) bluetoothService.connectDevice(btRow.addr)
                                    else bluetoothService.pairDevice(btRow.addr)
                                }
                            }
                        }

                        Item {
                            anchors.verticalCenter: parent.verticalCenter

                            width: 22
                            height: 22
                            visible: btRow.dev && btRow.dev.paired

                            IconImage {
                                anchors.centerIn: parent

                                width: 16
                                height: 16

                                source: Quickshell.iconPath("view-more-symbolic", "open-menu-symbolic")
                                asynchronous: true
                            }

                            MouseArea {
                                anchors.fill: parent

                                cursorShape: Qt.PointingHandCursor

                                onClicked: bluetoothPanel.menuAddr = bluetoothPanel.menuAddr === btRow.addr ? "" : btRow.addr
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            id: btMenuBackdrop

            anchors.fill: parent

            z: 20
            visible: bluetoothPanel.menuAddr !== ""

            onClicked: bluetoothPanel.menuAddr = ""
        }

        RectangularGlow {
            visible: btMenuPopup.visible
            anchors.fill: btMenuPopup
            z: btMenuPopup.z
            glowRadius: 16
            spread: 0.35
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32)
            cornerRadius: btMenuPopup.radius + glowRadius
        }

        Rectangle {
            id: btMenuPopup

            z: 21
            visible: bluetoothPanel.menuAddr !== ""

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 14
            anchors.topMargin: 52

            width: 180
            height: btMenuColumn.height + 12

            // Separation from the dark list comes from the crisp accent hairline
            // plus the outer RectangularGlow behind it; fill stays Theme.background.
            radius: 10
            color: Theme.background
            border.width: 1
            border.color: Theme.accent

            Column {
                id: btMenuColumn

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 6
                anchors.leftMargin: 6
                anchors.rightMargin: 6

                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 6
                    color: btTrustHover.hovered ? Qt.lighter(Theme.background, 1.5) : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    HoverHandler {
                        id: btTrustHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter

                        text: "Trust Device"
                        color: btTrustHover.hovered ? Theme.accent : Theme.text
                        Behavior on color { ColorAnimation { duration: 100 } }
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter

                        text: (bluetoothPanel.menuDevice && bluetoothPanel.menuDevice.trusted) ? "✓" : ""
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            if (bluetoothPanel.menuDevice)
                                bluetoothService.setTrusted(bluetoothPanel.menuAddr, !bluetoothPanel.menuDevice.trusted)
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 6
                    color: btForgetHover.hovered ? Qt.lighter(Theme.background, 1.5) : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    HoverHandler {
                        id: btForgetHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter

                        text: "Forget Device"
                        color: btForgetHover.hovered ? Theme.accent : Theme.text
                        Behavior on color { ColorAnimation { duration: 100 } }
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            bluetoothService.forgetDevice(bluetoothPanel.menuAddr)
                            bluetoothPanel.menuAddr = ""
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: hotspotPanel

        readonly property var originTile: hotspotTile
        readonly property point originPos: (drift.y, root.open, hotspotPanel.originTile)
            ? hotspotPanel.originTile.mapToItem(hotspotPanel.parent, 0, 0)
            : Qt.point(0, 0)

        z: 12
        color: Theme.background
        clip: true

        x: root.hotspotPanelOpen ? 0 : hotspotPanel.originPos.x
        y: root.hotspotPanelOpen ? 0 : hotspotPanel.originPos.y
        width: root.hotspotPanelOpen ? parent.width : hotspotPanel.originTile.width
        height: root.hotspotPanelOpen ? parent.height : hotspotPanel.originTile.height
        radius: root.hotspotPanelOpen ? 22 : hotspotPanel.originTile.radius
        opacity: root.hotspotPanelOpen ? 1 : 0

        enabled: root.hotspotPanelOpen
        visible: hotspotPanel.opacity > 0

        property bool revealPassword: false

        // The Hotspot tile isn't at the panel's top-left, so x/y must tween on
        // open/close to morph out of / back into the tile. `enabled: root.open`
        // runs that tween while the CC is up, but snaps during the CC's own
        // slide so x/y never chase the origin tile as `content` drifts. (See
        // bluetoothPanel.)
        Behavior on x {
            enabled: root.open
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: root.open
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on radius {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        onVisibleChanged: {
            if (!hotspotPanel.visible) {
                hotspotPanel.revealPassword = false
            } else {
                hsSsidField.text = hotspotService.ssid
                hsPasswordField.text = hotspotService.password
                hsSecurityCombo.currentIndex = hotspotService.secured ? 0 : 1
                hotspotService.updateStatus()
            }
        }

        Timer {
            id: hsRefreshTimer

            interval: 6000
            repeat: true
            running: root.hotspotPanelOpen
            onTriggered: hotspotService.updateStatus()
        }

        Connections {
            target: hotspotService

            enabled: root.hotspotPanelOpen

            function onSsidChanged() {
                if (!hsSsidField.activeFocus) hsSsidField.text = hotspotService.ssid
            }
            function onPasswordChanged() {
                if (!hsPasswordField.activeFocus) hsPasswordField.text = hotspotService.password
            }
            function onSecuredChanged() {
                hsSecurityCombo.currentIndex = hotspotService.secured ? 0 : 1
            }
        }

        Item {
            id: hotspotPanelContent

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            anchors.margins: 14

            opacity: root.hotspotPanelOpen ? 1 : 0
            visible: hotspotPanelContent.opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Item {
                id: hsHeader

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }

                height: 32

                MouseArea {
                    id: hsBackButton

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    width: 32
                    height: 32
                    cursorShape: Qt.PointingHandCursor

                    onClicked: root.hotspotPanelOpen = false

                    Rectangle {
                        anchors.fill: parent

                        radius: 16
                        color: hsBackHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"
                    }

                    HoverHandler {
                        id: hsBackHover
                    }

                    IconImage {
                        anchors.centerIn: parent

                        width: 18
                        height: 18

                        source: Quickshell.iconPath("go-previous-symbolic", "go-previous")
                        asynchronous: true
                    }
                }

                Text {
                    anchors.left: hsBackButton.right
                    anchors.leftMargin: 8
                    anchors.right: hsPowerToggle.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter

                    text: "Mobile Hotspot"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: hsPowerToggle

                    z: 2

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    width: 44
                    height: 24
                    radius: 12
                    color: hotspotService.enabled ? Theme.accent : Theme.surface
                    border.width: 1
                    border.color: hotspotService.enabled ? "transparent" : Qt.rgba(1, 1, 1, 0.2)

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        y: 3
                        x: hotspotService.enabled ? parent.width - width - 3 : 3
                        color: hotspotService.enabled ? Theme.background : Theme.textMuted

                        Behavior on x {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: hotspotService.toggleHotspot()
                    }
                }
            }

            Column {
                anchors {
                    top: hsHeader.bottom
                    left: parent.left
                    right: parent.right
                }

                anchors.topMargin: 18

                spacing: 14

                Column {
                    width: parent.width

                    spacing: 4

                    Text {
                        text: "Network name"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    Rectangle {
                        width: parent.width
                        height: 34

                        radius: 8
                        // Dark fill, always-on accent hairline to define the bounds.
                        color: Theme.background
                        border.width: 1
                        border.color: Theme.accent

                        TextField {
                            id: hsSsidField

                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10

                            verticalAlignment: TextInput.AlignVCenter

                            placeholderText: "Hotspot name"
                            placeholderTextColor: Theme.textMuted
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 12

                            selectByMouse: true

                            background: Rectangle {
                                color: "transparent"
                            }
                        }
                    }
                }

                Column {
                    width: parent.width

                    spacing: 4

                    Text {
                        text: "Security"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    ComboBox {
                        id: hsSecurityCombo

                        width: parent.width
                        height: 34

                        font.family: Theme.fontFamily
                        font.pixelSize: 12

                        model: ["WPA2/WPA3 Personal", "None / Open"]
                        currentIndex: 0

                        background: Rectangle {
                            radius: 8
                            // Match the SSID / password fields: dark fill, always-on
                            // accent hairline.
                            color: Theme.background
                            border.width: 1
                            border.color: Theme.accent
                        }

                        contentItem: Text {
                            leftPadding: 10
                            rightPadding: hsSecurityCombo.indicator.width + 6

                            text: hsSecurityCombo.displayText
                            color: Theme.text
                            font: hsSecurityCombo.font
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        indicator: IconImage {
                            x: hsSecurityCombo.width - width - 10
                            y: (hsSecurityCombo.height - height) / 2

                            width: 14
                            height: 14

                            source: Quickshell.iconPath("pan-down-symbolic", "go-down-symbolic")
                            asynchronous: true
                        }

                        delegate: ItemDelegate {
                            width: hsSecurityCombo.width
                            height: 32

                            highlighted: hsSecurityCombo.highlightedIndex === index

                            contentItem: Text {
                                leftPadding: 6

                                text: modelData
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            background: Rectangle {
                                radius: 6
                                color: highlighted ? Qt.lighter(Theme.surface, 1.3) : "transparent"
                            }
                        }

                        popup: Popup {
                            y: hsSecurityCombo.height + 4
                            width: hsSecurityCombo.width
                            padding: 4

                            implicitHeight: contentItem.implicitHeight + 8

                            background: Rectangle {
                                radius: 10
                                color: Theme.background
                                border.width: 1
                                border.color: Theme.accent
                            }

                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: hsSecurityCombo.popup.visible ? hsSecurityCombo.delegateModel : null
                                currentIndex: hsSecurityCombo.highlightedIndex
                            }
                        }
                    }
                }

                Column {
                    width: parent.width

                    spacing: 4
                    visible: hsSecurityCombo.currentIndex === 0

                    Text {
                        text: "Password"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    Rectangle {
                        width: parent.width
                        height: 34

                        radius: 8
                        // Dark fill, always-on accent hairline to define the bounds.
                        color: Theme.background
                        border.width: 1
                        border.color: Theme.accent

                        TextField {
                            id: hsPasswordField

                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: hsRevealButton.width + 20

                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: hotspotPanel.revealPassword ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "•"

                            placeholderText: "Password"
                            placeholderTextColor: Theme.textMuted
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 12

                            selectByMouse: true

                            background: Rectangle {
                                color: "transparent"
                            }
                        }

                        Text {
                            id: hsRevealButton

                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter

                            text: hotspotPanel.revealPassword ? "Hide" : "Show"
                            color: hsRevealHover.hovered ? Theme.text : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold

                            HoverHandler {
                                id: hsRevealHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            MouseArea {
                                anchors.fill: parent

                                cursorShape: Qt.PointingHandCursor

                                onClicked: hotspotPanel.revealPassword = !hotspotPanel.revealPassword
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 26

                    spacing: 12

                    Text {
                        width: parent.width - hsSaveButton.width - 12
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight

                        text: hotspotService.enabled
                            ? hotspotService.clientCount + (hotspotService.clientCount === 1 ? " device connected" : " devices connected")
                            : "Hotspot is Off"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    Text {
                        id: hsSaveButton

                        height: parent.height
                        verticalAlignment: Text.AlignVCenter

                        readonly property bool ready: hsSsidField.text.length > 0
                            && (hsSecurityCombo.currentIndex !== 0 || hsPasswordField.text.length >= 8)

                        text: "Apply"
                        color: hsSaveButton.ready ? Theme.accent : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold

                        MouseArea {
                            anchors.fill: parent

                            enabled: hsSaveButton.ready
                            cursorShape: Qt.PointingHandCursor

                            onClicked: hotspotService.updateConfiguration(hsSsidField.text, hsPasswordField.text, hsSecurityCombo.currentIndex === 0)
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: audioOutputPanel

        readonly property var originTile: audioOutputTile
        readonly property point originPos: (drift.y, root.open, audioOutputPanel.originTile)
            ? audioOutputPanel.originTile.mapToItem(audioOutputPanel.parent, 0, 0)
            : Qt.point(0, 0)

        z: 13
        color: Theme.background
        clip: true

        x: root.audioOutputPanelOpen ? 0 : audioOutputPanel.originPos.x
        y: root.audioOutputPanelOpen ? 0 : audioOutputPanel.originPos.y
        width: root.audioOutputPanelOpen ? parent.width : audioOutputPanel.originTile.width
        height: root.audioOutputPanelOpen ? parent.height : audioOutputPanel.originTile.height
        radius: root.audioOutputPanelOpen ? 22 : audioOutputPanel.originTile.radius
        opacity: root.audioOutputPanelOpen ? 1 : 0

        enabled: root.audioOutputPanelOpen
        visible: audioOutputPanel.opacity > 0

        // x/y tween so the panel morphs out of / back into the Output tile;
        // `enabled: root.open` snaps them during the CC's own open/close slide so
        // they don't chase the origin tile as `content` drifts. (See bluetoothPanel.)
        Behavior on x {
            enabled: root.open
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: root.open
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on radius {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        onVisibleChanged: {
            if (audioOutputPanel.visible) audioService.refresh()
        }

        Item {
            id: audioOutputContent

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            anchors.margins: 14

            opacity: root.audioOutputPanelOpen ? 1 : 0
            visible: audioOutputContent.opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Item {
                id: aoHeader

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }

                height: 32

                MouseArea {
                    id: aoBackButton

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    width: 32
                    height: 32
                    cursorShape: Qt.PointingHandCursor

                    onClicked: root.audioOutputPanelOpen = false

                    Rectangle {
                        anchors.fill: parent

                        radius: 16
                        color: aoBackHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"
                    }

                    HoverHandler {
                        id: aoBackHover
                    }

                    IconImage {
                        anchors.centerIn: parent

                        width: 18
                        height: 18

                        source: Quickshell.iconPath("go-previous-symbolic", "go-previous")
                        asynchronous: true
                    }
                }

                Text {
                    anchors.left: aoBackButton.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter

                    text: "Audio Output"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: aoHeader.bottom
                anchors.topMargin: 12

                visible: audioService.sinks.length === 0
                text: "No output devices"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            ListView {
                id: aoList

                anchors {
                    top: aoHeader.bottom
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                anchors.topMargin: 8

                clip: true
                spacing: 4
                visible: audioService.sinks.length > 0
                model: audioService.sinks

                delegate: Rectangle {
                    id: aoRow

                    required property var modelData

                    readonly property var sink: aoRow.modelData

                    width: aoList.width
                    height: 52
                    radius: 14
                    color: aoRowHover.hovered || (aoRow.sink && aoRow.sink.isDefault)
                        ? Qt.lighter(Theme.background, 1.35)
                        : "transparent"

                    HoverHandler {
                        id: aoRowHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    Row {
                        anchors.fill: parent

                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        spacing: 10

                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter

                            width: 24
                            height: 24

                            source: Quickshell.iconPath("audio-speakers-symbolic", "audio-speakers")
                            asynchronous: true
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter

                            width: parent.width - 24 - 10 - (aoCheck.visible ? aoCheck.width + 10 : 0)
                            elide: Text.ElideRight

                            text: aoRow.sink ? aoRow.sink.description : ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: aoRow.sink && aoRow.sink.isDefault ? Font.DemiBold : Font.Normal
                        }
                    }

                    IconImage {
                        id: aoCheck

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter

                        width: 18
                        height: 18
                        visible: aoRow.sink && aoRow.sink.isDefault

                        source: Quickshell.iconPath("object-select-symbolic", "emblem-default")
                        asynchronous: true
                    }

                    MouseArea {
                        anchors.fill: parent

                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            if (aoRow.sink) audioService.setDefaultSink(aoRow.sink.id)
                        }
                    }
                }
            }
        }
    }
}
