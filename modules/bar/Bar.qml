import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Qt5Compat.GraphicalEffects
import "../../components"
import "../capture"
import "../services"

PanelWindow {
    id: root

    required property var modelData

    readonly property var barState: modelData.barState
    readonly property var launcherController: modelData.launcherController
    readonly property var mediaService: modelData.mediaService

    readonly property bool mediaExpanded: barState.screen === root.screen && barState.mode === "media"

    screen: modelData.screen

    // Static bar: always on, from the moment quickshell starts. No IPC gate.
    visible: true

    property bool centerOpen: barState.mode === "center" && barState.screen === root.screen
    readonly property bool isCaptureActive: CaptureService.barVisible
        && root.screen
        && Hyprland.focusedMonitor
        && root.screen.name === Hyprland.focusedMonitor.name
    // `mediaExpanded` (auto-expand OR manual) now arms the focus grab so Escape
    // and click-outside dismiss the preview early; `mediaManual` no longer gates
    // this, only the 4s auto-hide timer in shell.qml.
    property bool surfaceActive: (barState.screen === root.screen && (barState.mode === "power" || barState.mode === "display" || barState.mode === "wallpapers" || barState.mode === "mediaPreview" || barState.mode === "mediaCompact")) || root.isCaptureActive
        || root.mediaExpanded

    onIsCaptureActiveChanged: console.log("[Bar] isCaptureActive ->", root.isCaptureActive, "screen =", (root.screen ? root.screen.name : "null"))

    readonly property int fixedHeight: 540

    implicitHeight: root.fixedHeight

    anchors {
        top: true
        left: true
        right: true
    }

    color: "transparent"

    exclusiveZone: 40
    focusable: root.surfaceActive

    mask: (root.surfaceActive || root.mediaExpanded) ? activeMask : idleMask
    Region { id: idleMask; item: barContent }
    Region {
        id: activeMask
        item: barContent
        Region { item: dynamicCenter }
    }

    HyprlandFocusGrab {
        id: focusGrab

        windows: [root]
        active: root.surfaceActive

        onCleared: {
            if (!root.surfaceActive)
                return
            // The capture selection overlay is a separate top-layer surface; it
            // legitimately takes focus while the CaptureBar picker is still up
            // (openBar's default region mode). That focus hand-off is not a user
            // dismiss - let the overlay / picker Esc / Cancel own the teardown.
            if (root.isCaptureActive
                && (CaptureService.regionSelectActive || CaptureService.windowSelectActive))
                return
            barState.screen = null
            barState.mode = ""
            CaptureService.closeBar()
        }
    }

    // Native Wayland idle-inhibit (zwp_idle_inhibit_manager_v1), attached to the
    // always-visible bar surface. This is what actually stops hypridle from
    // blanking / locking the screen while Caffeine is on; CaffeineService's
    // systemd-inhibit handles the logind auto-suspend side. Harmless to have one
    // per monitor - each is idempotent and released when `enabled` clears.
    IdleInhibitor {
        window: root
        enabled: CaffeineService.enabled
    }

    Rectangle {
        id: barContent

        x: 0
        y: 0
        width: parent.width
        height: 40
        clip: true
        z: 999

        color: Theme.background

        // Arch Linux logo, pinned to the very left edge. Click toggles a
        // fastfetch-style system summary popover (see archPop below).
        Item {
            id: archSlot

            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }

            // Bar left outer padding (mirrors dateTime's right padding).
            anchors.leftMargin: 8

            width: 32
            height: 32

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: archTap.pressed || archHover.hovered || archPop.open ? Theme.surfaceHover : "transparent"
            }

            Image {
                id: archImg

                anchors.centerIn: parent
                width: 20
                height: 20
                sourceSize.width: 40
                sourceSize.height: 40
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                visible: false

                source: "file://" + Quickshell.shellPath("assets/arch.svg")
            }

            ColorOverlay {
                anchors.fill: archImg
                source: archImg
                color: Theme.text
            }

            HoverHandler {
                id: archHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                id: archTap

                onTapped: {
                    if (archPop.open) {
                        archPop.open = false
                    } else {
                        UptimeService.refresh()
                        archPop.open = true
                    }
                }
            }

            // Fastfetch-style system summary. Same PanelWindow + focus-grab
            // pattern as BatteryWidget's popover: floats just below the bar,
            // dismisses on click-away or Esc, never steals the bar's surface.
            PanelWindow {
                id: archPop

                screen: root.screen

                property bool open: false
                property bool closing: false

                visible: archPop.open || archPop.closing

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

                anchors {
                    top: true
                    left: true
                }

                // Sit directly beneath the Arch icon: 40px bar + 4px gap, and
                // the icon's own left inset.
                margins {
                    top: 44
                    left: 10
                }

                implicitWidth: card.implicitWidth + 16
                implicitHeight: card.implicitHeight + 16

                color: "transparent"

                onOpenChanged: {
                    if (archPop.open) {
                        archPop.closing = false
                        hideTimer.stop()
                        card.forceActiveFocus()
                    } else if (archPop.visible) {
                        archPop.closing = true
                        hideTimer.restart()
                    }
                }

                Timer {
                    id: hideTimer
                    interval: 200
                    onTriggered: archPop.closing = false
                }

                HyprlandFocusGrab {
                    windows: [archPop]
                    active: archPop.open
                    onCleared: archPop.open = false
                }

                Rectangle {
                    id: card

                    anchors.fill: parent
                    anchors.margins: 8
                    radius: Theme.cornerRadius
                    color: Theme.background
                    border.width: 1
                    border.color: Theme.surfaceHover

                    // Fixed width keeps the key column at x=70 and lets each
                    // value Text elide instead of stretching the card.
                    implicitWidth: 240
                    implicitHeight: infoCol.implicitHeight + 28

                    // Snappy scale-fade from directly under the Arch icon.
                    transformOrigin: Item.Top
                    opacity: archPop.open ? 1 : 0
                    scale: archPop.open ? 1 : 0.85
                    Behavior on opacity {
                        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            archPop.open = false
                            event.accepted = true
                        }
                    }

                    // Structured column: header + divider + key/value rows.
                    // Keys are a fixed-width Theme.accent (Bold) gutter; values
                    // are Theme.text (Medium 12px) and elide on overflow.
                    Column {
                        id: infoCol

                        x: 14
                        y: 14
                        width: parent.width - 28
                        spacing: 8

                        Row {
                            width: parent.width
                            spacing: 8

                            Item {
                                width: 16
                                height: 16
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    id: hdrArchImg

                                    anchors.fill: parent
                                    source: "file://" + Quickshell.shellPath("assets/arch.svg")
                                    sourceSize.width: 32
                                    sourceSize.height: 32
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    visible: false
                                }

                                ColorOverlay {
                                    anchors.fill: hdrArchImg
                                    source: hdrArchImg
                                    color: Theme.text
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "System Overview"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: 14
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Theme.surfaceHover
                        }

                        Repeater {
                            model: ["OS", "Kernel", "Uptime", "WM", "Shell", "Memory"]

                            delegate: Row {
                                id: infoRow

                                required property string modelData

                                width: infoCol.width

                                Text {
                                    width: 70
                                    text: infoRow.modelData
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: 12
                                }

                                Text {
                                    width: parent.width - 70
                                    elide: Text.ElideRight
                                    text: {
                                        switch (infoRow.modelData) {
                                        case "OS": return UptimeService.os
                                        case "Kernel": return UptimeService.kernel
                                        case "Uptime": return UptimeService.pretty
                                        case "WM": return "Hyprland"
                                        case "Shell": return "Quickshell"
                                        case "Memory": return UptimeService.memory
                                        }
                                        return ""
                                    }
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.weight: Font.Medium
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }

        Row {
            id: activeWindowRow

            readonly property string rawAppId: ToplevelManager.activeToplevel?.appId ?? ""
            readonly property string displayName: {
                if (rawAppId.length === 0)
                    return "Desktop"
                let names = {
                    "code": "VS Code",
                    "code-url-handler": "VS Code",
                    "code-oss": "VS Code",
                    "ghostty": "Ghostty",
                    "com.mitchellh.ghostty": "Ghostty",
                    "org.gnome.Nautilus": "Files",
                    "org.gnome.nautilus": "Files",
                    "google-chrome": "Chrome",
                    "chrome": "Chrome",
                    "chromium": "Chrome",
                    "firefox": "Firefox",
                    "kitty": "Kitty"
                }
                if (names[rawAppId] !== undefined)
                    return names[rawAppId]
                let lower = rawAppId.toLowerCase()
                if (names[lower] !== undefined)
                    return names[lower]
                let parts = rawAppId.split(".")
                let name = parts[parts.length - 1]
                return name.charAt(0).toUpperCase() + name.slice(1)
            }

            // Icon name resolution chain. A window's app_id / class is often not
            // a literal icon-theme name (case, wrapper suffixes, StartupWMClass
            // remaps, reverse-DNS ids), so: known aliases first, then a set of
            // sanitized candidates each run through theme + desktop-entry lookups
            // - every candidate verified via iconPath(name, true) ("" on miss).
            function resolveWindowIcon(appId) {
                if (!appId || appId.length === 0)
                    return Quickshell.iconPath("application-x-executable", "computer")

                const cleanId = appId.trim()

                // 0. Known class aliases -> ordered list of real icon names.
                const aliases = {
                    "code": ["vscode", "com.visualstudio.code", "code"],
                    "code-url-handler": ["vscode", "com.visualstudio.code", "code"],
                    "VS Code": ["vscode", "com.visualstudio.code", "code"],
                    "Code": ["vscode", "com.visualstudio.code", "code"],
                    "vscodium": ["vscodium", "com.vscodium.codium"],
                    "Google-chrome": ["google-chrome", "google-chrome-stable"],
                    "chrome": ["google-chrome", "google-chrome-stable"],
                    "Brave-browser": ["brave-browser"],
                    "jetbrains-idea": ["intellij-idea-ultimate", "idea"],
                    "jetbrains-studio": ["android-studio"]
                }
                if (aliases[cleanId]) {
                    for (let a = 0; a < aliases[cleanId].length; a++) {
                        const aliasPath = Quickshell.iconPath(aliases[cleanId][a], true)
                        if (aliasPath) return aliasPath
                    }
                }

                // Strip common wrapper suffixes (code-url-handler -> code).
                const strippedId = cleanId.replace(/-url-handler$/i, "").replace(/\.desktop$/i, "")

                const candidates = [cleanId, strippedId, cleanId.toLowerCase(), strippedId.toLowerCase()]
                for (let i = 0; i < candidates.length; i++) {
                    const c = candidates[i]
                    if (!c) continue

                    // theme lookup
                    let path = Quickshell.iconPath(c, true)
                    if (path) return path

                    // desktop entry heuristic (StartupWMClass mismatches)
                    let entry = DesktopEntries.heuristicLookup(c)
                    if (entry && entry.icon) {
                        path = Quickshell.iconPath(entry.icon, true)
                        if (path) return path
                    }

                    // desktop entry by id
                    entry = DesktopEntries.byId(c)
                    if (entry && entry.icon) {
                        path = Quickshell.iconPath(entry.icon, true)
                        if (path) return path
                    }

                    // reverse-DNS last segment (org.kde.dolphin -> dolphin)
                    const parts = c.split(".")
                    if (parts.length > 1) {
                        path = Quickshell.iconPath(parts[parts.length - 1], true)
                        if (path) return path
                    }
                }

                // generic terminal fallback
                return Quickshell.iconPath("application-x-executable", "computer")
            }

            anchors {
                left: archSlot.right
                verticalCenter: parent.verticalCenter
            }

            anchors.leftMargin: 10

            spacing: activeWindowIcon.visible ? 6 : 0

            IconImage {
                id: activeWindowIcon

                visible: activeWindowRow.rawAppId.length > 0
                width: visible ? 16 : 0
                height: 16
                anchors.verticalCenter: parent.verticalCenter

                source: activeWindowRow.resolveWindowIcon(activeWindowRow.rawAppId)
                asynchronous: true
            }

            Text {
                id: activeWindowTitle

                width: Math.min(implicitWidth, 180)
                anchors.verticalCenter: parent.verticalCenter

                text: activeWindowRow.displayName
                elide: Text.ElideRight
                maximumLineCount: 1
                // Match the DateTimeWidget clock text exactly.
                color: Theme.text
                font.family: Theme.fontFamily
                font.weight: Font.Black
                font.pixelSize: 14
            }
        }

        // Hyprland submap indicator (e.g. RESIZE). Only present while a submap
        // is active; sits just right of the active window title.
        Rectangle {
            id: submapPill

            anchors {
                left: activeWindowRow.right
                verticalCenter: parent.verticalCenter
            }
            anchors.leftMargin: 8

            visible: SubmapService.current !== ""

            // Pill: 8px horizontal / 2px vertical padding around the label.
            implicitWidth: submapText.implicitWidth + 16
            implicitHeight: submapText.implicitHeight + 4
            width: implicitWidth
            height: implicitHeight

            radius: 8
            color: Theme.accent

            Text {
                id: submapText

                anchors.centerIn: parent
                text: SubmapService.current.toUpperCase()
                color: Theme.background
                font.family: Theme.fontFamily
                font.weight: Font.Bold
                font.pixelSize: 11
            }
        }

        Text {
            id: holdLabel

            anchors.centerIn: parent
            visible: root.isCaptureActive
                || (barState.screen === root.screen && (barState.mode === "power" || barState.mode === "display" || barState.mode === "wallpapers" || barState.mode === "mediaPreview" || barState.mode === "mediaCompact"))
            text: root.isCaptureActive ? "Capture Mode"
                : barState.mode === "power" ? "Power Menu"
                : barState.mode === "display" ? "Display"
                : barState.mode === "wallpapers" ? "Wallpapers"
                : (barState.mode === "mediaPreview" || barState.mode === "mediaCompact") ? "Media"
                : ""
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.Bold
        }

        MediaPreview {
            id: mediaPreview

            anchors.centerIn: parent
            // hidden on every screen while media is expanded; and, on the
            // screen that hosts the surface, kept hidden through the slide-out
            // tail (mediaSurfacePresent) so the two never overlap/flicker.
            visible: !holdLabel.visible && root.mediaService && root.mediaService.hasMedia
                && barState.mode !== "media"
                && !dynamicCenter.mediaSurfacePresent

            mediaService: root.mediaService

            onActivateRequested: {
                barState.mediaManual = true
                barState.screen = root.screen
                barState.mode = "media"
            }
        }

        Item {
            id: rightSlot

            // Sits just left of the clock, which is pinned to the bar's far edge.
            anchors {
                right: dateTime.left
                verticalCenter: parent.verticalCenter
            }

            anchors.rightMargin: 8

            width: 36
            height: 36

            Rectangle {
                id: centerButton

                anchors.fill: parent

                radius: 10
                color: root.centerOpen || centerTap.pressed ? Theme.surfaceHover : (centerHover.hovered ? Theme.surfaceHover : "transparent")

                HoverHandler {
                    id: centerHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: centerTap

                    onTapped: {
                        if (root.centerOpen) {
                            barState.screen = null
                            barState.mode = ""
                        } else {
                            barState.screen = root.screen
                            barState.mode = "center"
                        }
                    }
                }

                IconImage {
                    id: centerIcon

                    anchors.centerIn: parent

                    width: 20
                    height: 20

                    source: "file://" + Quickshell.shellPath("assets/controls-symbolic.svg")
                    asynchronous: true
                }
            }
        }

        DateTimeWidget {
            id: dateTime

            screen: root.screen

            // Far-right edge of the bar.
            anchors {
                verticalCenter: parent.verticalCenter
                right: parent.right
            }
            anchors.rightMargin: 8
        }

        BatteryWidget {
            id: battery

            screen: root.screen

            anchors {
                verticalCenter: parent.verticalCenter
                right: rightSlot.left
            }
            anchors.rightMargin: 4
        }

        // Caffeine indicator - only present while CaffeineService.enabled.
        // Collapses to zero width when off so nothing else in the bar shifts
        // (battery/wifi stay anchored independently). Click toggles.
        Item {
            id: caffeineIndicator

            anchors {
                verticalCenter: parent.verticalCenter
                right: micIndicator.left
            }
            // Uniform 4px inter-indicator gap (0 while collapsed).
            anchors.rightMargin: CaffeineService.enabled ? 4 : 0

            visible: CaffeineService.enabled
            width: CaffeineService.enabled ? 28 : 0
            implicitWidth: width
            height: 28

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: caffeineTap.pressed || caffeineHover.hovered ? Theme.surfaceHover : "transparent"
            }

            Image {
                id: caffeineIndicatorImg

                anchors.centerIn: parent
                width: 20
                height: 20
                sourceSize.width: 40
                sourceSize.height: 40
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                visible: false

                source: "file://" + Quickshell.shellPath("assets/coffee-svgrepo-com.svg")
            }

            ColorOverlay {
                anchors.fill: caffeineIndicatorImg
                source: caffeineIndicatorImg
                color: Theme.text
            }

            HoverHandler {
                id: caffeineHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                id: caffeineTap

                onTapped: CaffeineService.toggle()
            }
        }

        // System tray (StatusNotifierItem hosts - Tailscale, OBS, ...). Sits
        // left of the status indicators; empty (zero-width) when nothing is
        // registered.
        Row {
            id: systemTrayRow

            anchors {
                verticalCenter: parent.verticalCenter
                right: caffeineIndicator.left
            }
            anchors.rightMargin: 4

            spacing: 4

            Repeater {
                model: SystemTray.items

                delegate: Item {
                    id: trayItem

                    required property var modelData

                    width: 28
                    height: 28

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: trayMouse.containsMouse ? Theme.surfaceHover : "transparent"
                    }

                    IconImage {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        smooth: true
                        asynchronous: true

                        source: trayItem.modelData.icon
                    }

                    MouseArea {
                        id: trayMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                // Anchor the item's own context menu just below
                                // the icon (coords are window-relative; barContent
                                // sits at 0,0 in root).
                                const p = trayItem.mapToItem(barContent,
                                    trayItem.width / 2, trayItem.height)
                                trayItem.modelData.display(root, p.x, p.y)
                            } else {
                                trayItem.modelData.activate()
                            }
                        }
                    }
                }
            }
        }

        // Microphone mute - sits just left of the Wi-Fi indicator. Click
        // toggles the default PipeWire source mute; glyph swaps on/off.
        Item {
            id: micIndicator

            anchors {
                verticalCenter: parent.verticalCenter
                right: wifiIndicator.left
            }
            anchors.rightMargin: 4

            width: 28
            height: 28

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: micTap.pressed || micHover.hovered ? Theme.surfaceHover : "transparent"
            }

            Image {
                id: micIndicatorImg

                anchors.centerIn: parent
                width: 16
                height: 16
                sourceSize.width: 40
                sourceSize.height: 40
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                visible: false

                source: "file://" + Quickshell.shellPath(
                    MicService.muted ? "assets/mic-0ff.svg" : "assets/mic-on.svg")
            }

            ColorOverlay {
                anchors.fill: micIndicatorImg
                source: micIndicatorImg
                color: Theme.text
            }

            HoverHandler {
                id: micHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                id: micTap

                onTapped: MicService.toggleMute()
            }
        }

        // Wi-Fi status - sits just left of the battery. Click opens a small
        // details card (SSID / IP / signal / interface).
        Item {
            id: wifiIndicator

            anchors {
                verticalCenter: parent.verticalCenter
                right: battery.left
            }
            anchors.rightMargin: 4

            width: 28
            height: 28

            readonly property bool wifiOn: NetworkService.wifiEnabled
            readonly property bool online: NetworkService.connected

            readonly property string glyph: {
                if (!wifiIndicator.wifiOn)
                    return "network-wireless-disabled-symbolic"
                if (!wifiIndicator.online)
                    return "network-wireless-offline-symbolic"
                switch (NetworkService.signalLevel) {
                case 4: return "network-wireless-signal-excellent-symbolic"
                case 3: return "network-wireless-signal-good-symbolic"
                case 2: return "network-wireless-signal-ok-symbolic"
                case 1: return "network-wireless-signal-weak-symbolic"
                default: return "network-wireless-signal-none-symbolic"
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: wifiBarTap.pressed || wifiBarHover.hovered || wifiPop.open
                    ? Theme.surfaceHover : "transparent"
            }

            IconImage {
                id: wifiBarIcon

                anchors.centerIn: parent
                width: 22
                height: 22

                source: Quickshell.iconPath(wifiIndicator.glyph, "network-wireless")
                asynchronous: true
            }

            // Idle / connected -> solid white; Wi-Fi radio disabled -> muted.
            // Accent is reserved for active-state highlights elsewhere.
            ColorOverlay {
                anchors.fill: wifiBarIcon
                source: wifiBarIcon
                color: wifiIndicator.wifiOn ? Theme.text : Theme.textMuted
            }

            HoverHandler {
                id: wifiBarHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                id: wifiBarTap

                onTapped: wifiPop.open = !wifiPop.open
            }

            // Details card. Same PanelWindow + focus-grab pattern as archPop /
            // BatteryWidget's popover; centred under the icon, dismisses on
            // click-away or Esc.
            PanelWindow {
                id: wifiPop

                screen: root.screen

                property bool open: false
                property bool closing: false

                visible: wifiPop.open || wifiPop.closing

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

                anchors {
                    top: true
                    right: true
                }

                readonly property real widgetFromRight: wifiIndicator.parent
                    ? Math.max(0, wifiIndicator.parent.width - (wifiIndicator.x + wifiIndicator.width))
                    : 12
                readonly property real centeredRight:
                    wifiPop.widgetFromRight + wifiIndicator.width / 2 - wifiPop.implicitWidth / 2

                margins {
                    top: 44
                    right: Math.max(8, Math.round(wifiPop.centeredRight))
                }

                implicitWidth: wifiCard.implicitWidth + 16
                implicitHeight: wifiCard.implicitHeight + 16

                color: "transparent"

                onOpenChanged: {
                    if (wifiPop.open) {
                        wifiPop.closing = false
                        wifiHideTimer.stop()
                        wifiCard.forceActiveFocus()
                    } else if (wifiPop.visible) {
                        wifiPop.closing = true
                        wifiHideTimer.restart()
                    }
                }

                Timer {
                    id: wifiHideTimer
                    interval: 200
                    onTriggered: wifiPop.closing = false
                }

                HyprlandFocusGrab {
                    windows: [wifiPop]
                    active: wifiPop.open
                    onCleared: wifiPop.open = false
                }

                Rectangle {
                    id: wifiCard

                    anchors.fill: parent
                    anchors.margins: 8
                    radius: Theme.cornerRadius
                    color: Theme.background
                    border.width: 1
                    border.color: Theme.surfaceHover

                    implicitWidth: 250
                    implicitHeight: wifiInfoCol.implicitHeight + 28

                    // Snappy scale-fade from directly under the Wi-Fi icon.
                    transformOrigin: Item.Top
                    opacity: wifiPop.open ? 1 : 0
                    scale: wifiPop.open ? 1 : 0.85
                    Behavior on opacity {
                        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            wifiPop.open = false
                            event.accepted = true
                        }
                    }

                    Column {
                        id: wifiInfoCol

                        x: 14
                        y: 14
                        width: parent.width - 28
                        spacing: 8

                        // Header: connection dot + SSID (left), Wi-Fi on/off
                        // switch (right).
                        Item {
                            width: parent.width
                            height: 22

                            Rectangle {
                                id: wifiHdrDot

                                width: 9
                                height: 9
                                radius: 4.5
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                color: NetworkService.connected ? Theme.accent : Theme.textMuted
                            }

                            Text {
                                anchors.left: wifiHdrDot.right
                                anchors.leftMargin: 8
                                anchors.right: wifiToggle.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight

                                text: "Wi-Fi Network"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: 13
                            }

                            Rectangle {
                                id: wifiToggle

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                height: 22
                                radius: height / 2
                                color: NetworkService.wifiEnabled ? Theme.accent : Theme.surfaceHover
                                Behavior on color {
                                    ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                                }

                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: NetworkService.wifiEnabled ? parent.width - width - 3 : 3
                                    color: Theme.text
                                    Behavior on x {
                                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                    }
                                }

                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    onTapped: NetworkService.toggleWifi()
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Theme.surfaceHover
                        }

                        Repeater {
                            model: ["SSID", "Status", "IP Address", "Signal", "Interface", "Frequency"]

                            delegate: Row {
                                id: wifiRow

                                required property string modelData

                                width: wifiInfoCol.width

                                Text {
                                    width: 84
                                    text: wifiRow.modelData
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: 12
                                }

                                Text {
                                    width: parent.width - 84
                                    elide: Text.ElideRight
                                    text: {
                                        switch (wifiRow.modelData) {
                                        case "SSID":
                                            return (NetworkService.connected && NetworkService.ssid)
                                                ? NetworkService.ssid : "—"
                                        case "Status":
                                            return !NetworkService.wifiEnabled ? "Disabled"
                                                : NetworkService.connected ? "Connected" : "Disconnected"
                                        case "IP Address":
                                            return NetworkService.ipAddress || "—"
                                        case "Signal":
                                            return NetworkService.connected
                                                ? NetworkService.signalStrength + "%" : "—"
                                        case "Interface":
                                            return NetworkService.interfaceName || "—"
                                        case "Frequency":
                                            return NetworkService.frequency || "—"
                                        }
                                        return ""
                                    }
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.weight: Font.Medium
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    DynamicCenter {
        id: dynamicCenter

        screen: root.screen
        mediaService: root.mediaService
        mediaManual: barState.mediaManual
        anchors.horizontalCenter: parent.horizontalCenter
        activeSurface: barState.screen === root.screen && (barState.mode === "power" || barState.mode === "display" || barState.mode === "wallpapers" || barState.mode === "mediaPreview" || barState.mode === "mediaCompact" || barState.mode === "media")
            ? barState.mode
            : root.isCaptureActive ? "capture" : "idle"
    }

    Connections {
        target: dynamicCenter

        onCloseRequested: {
            barState.screen = null
            barState.mode = ""
            CaptureService.closeBar()
        }
    }
}
