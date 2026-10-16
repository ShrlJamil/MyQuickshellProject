//@ pragma UseQApplication

import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules/launcher"
import "modules/controllers"
import "modules/bar"
import "modules/capture"
import "modules/services"
import "modules/osd"

ShellRoot {
    function closeLauncher(): void {
        if (launcherLoader.item)
            launcherLoader.item.close()
        else
            launcherController.hide()
    }

    function focusedScreen() {
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === focusState.focusedName)
                return Quickshell.screens[i]
        }
        if (Quickshell.screens.length > 0) return Quickshell.screens[0]
        return null
    }

    QtObject {
        id: focusState

        property string focusedName: ""

        function inquire(): void {
            const fm = Hyprland.focusedMonitor
            if (fm && fm.name) focusState.focusedName = fm.name
        }
    }

    Component.onCompleted: {
        Hyprland.focusedMonitorChanged.connect(() => focusState.inquire())
        Hyprland.rawEvent.connect(event => {
            if (event.name === "focusedmon") {
                const parts = event.data.split(",")
                if (parts.length === 2) focusState.focusedName = parts[1].trim()
            }
        })
        focusState.inquire()
    }

    LauncherController {
        id: launcherController
    }

    QtObject {
        id: barState

        property string mode: ""
        property ShellScreen screen: null
        // true when "media" mode was opened by the user clicking the bar
        // preview. All "media" opens are manual (click-to-expand); there is no
        // auto-expand. Gates the focus grab (Bar) + focus routing
        // (DynamicCenter/MediaPlayer).
        property bool mediaManual: false
    }

    // ---- Media: one service shared by every screen's bar preview + expanded
    // player. The "media" DynamicCenter surface opens only via an explicit
    // user click (MediaPreview.activateRequested); playback / track events
    // never change barState.
    MediaService {
        id: mediaService
        positionActive: barState.mode === "media"
    }

    // Own AudioService for the volume keybind IPC below. ControlCenter keeps
    // its own per-window instance; both track PipeWire reactively, so volume
    // and mute converge through the backend with no wpctl involved.
    AudioService {
        id: audioService
    }

    // Run the cava spectrum analyzer (-> CavaService.bars, consumed by the bar
    // MediaPreview mini-viz) only while something is actually playing; pausing
    // releases its capture stream.
    Binding {
        target: CavaService
        property: "active"
        value: mediaService.playing
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { if (launcherController.visible) closeLauncher(); else launcherController.show() }
        function show(): void { launcherController.show() }
        function hide(): void { closeLauncher() }
    }

    IpcHandler {
        target: "power"

        function show(): void {
            focusState.inquire()
            const screen = focusedScreen()
            if (!screen) return
            if (barState.mode === "power" && barState.screen === screen) return
            barState.screen = screen
            barState.mode = "power"
            // Force the capture picker / its input grab down (it lives outside
            // barState.mode). After the mode set so activeSurface goes
            // capture->power directly, with no transient idle flicker.
            CaptureService.closeBar()
        }
        function hide(): void {
            barState.screen = null
            barState.mode = ""
        }
        function toggle(): void {
            if (barState.mode === "power") hide()
            else show()
        }
    }

    IpcHandler {
        target: "display"

        function show(): void {
            focusState.inquire()
            const screen = focusedScreen()
            if (!screen) return
            if (barState.mode === "display" && barState.screen === screen) return
            barState.screen = screen
            barState.mode = "display"
            CaptureService.closeBar()
        }
        function hide(): void {
            barState.screen = null
            barState.mode = ""
        }
        function toggle(): void {
            if (barState.mode === "display") hide()
            else show()
        }
    }

    IpcHandler {
        target: "wallpapers"

        function show(): void {
            focusState.inquire()
            const screen = focusedScreen()
            if (!screen) return
            if (barState.mode === "wallpapers" && barState.screen === screen) return
            barState.screen = screen
            barState.mode = "wallpapers"
            CaptureService.closeBar()
        }
        function hide(): void {
            barState.screen = null
            barState.mode = ""
        }
        function toggle(): void {
            if (barState.mode === "wallpapers") hide()
            else show()
        }
    }

    IpcHandler {
        target: "mediaPreview"

        function show(): void {
            focusState.inquire()
            const screen = focusedScreen()
            if (!screen) return
            if (barState.mode === "mediaPreview" && barState.screen === screen) return
            barState.screen = screen
            barState.mode = "mediaPreview"
        }
        function hide(): void {
            barState.screen = null
            barState.mode = ""
        }
        function toggle(): void {
            if (barState.mode === "mediaPreview") hide()
            else show()
        }
    }

    IpcHandler {
        target: "mediaCompact"

        function show(): void {
            focusState.inquire()
            const screen = focusedScreen()
            if (!screen) return
            if (barState.mode === "mediaCompact" && barState.screen === screen) return
            barState.screen = screen
            barState.mode = "mediaCompact"
        }
        function hide(): void {
            barState.screen = null
            barState.mode = ""
        }
        function toggle(): void {
            if (barState.mode === "mediaCompact") hide()
            else show()
        }
    }

    IpcHandler {
        target: "volume"

        // Relative steps off the reactive backend value; AudioService clamps
        // and writes natively via PipeWire (no wpctl anywhere in this path).
        function up(): void { audioService.setVolume(audioService.volume + 5) }
        function down(): void { audioService.setVolume(audioService.volume - 5) }
    }

    IpcHandler {
        target: "brightness"

        // Hyprland's XF86MonBrightness* keys call these; OSDService updates the
        // OSD optimistically on this frame, then runs brightnessctl detached.
        function up(): void { OSDService.brightnessStep(1) }
        function down(): void { OSDService.brightnessStep(-1) }
    }

    IpcHandler {
        target: "capture"

        // Capture is not a barState.mode - clear any open surface first so
        // DynamicCenter.activeSurface can resolve to "capture" and the picker
        // renders instead of being shadowed by e.g. an open Power Menu.
        function open(): void {
            console.log("[IPC] capture open")
            barState.screen = null
            barState.mode = ""
            CaptureService.openBar()
        }
        function region(): void { CaptureService.triggerCapture("region") }
        function window(): void { CaptureService.triggerCapture("window") }
        function screen(): void { CaptureService.triggerCapture("screen") }
        // instant full-screen shot straight to file + clipboard, no CaptureBar UI
        function fullscreen(): void { CaptureService.captureFullscreen() }
        function bar(): void {
            barState.screen = null
            barState.mode = ""
            CaptureService.openBar()
        }
    }

    IpcHandler {
        target: "center"

        function show(): void {
            focusState.inquire()
            const screen = focusedScreen()
            if (!screen) return
            if (barState.mode === "center" && barState.screen === screen) return
            barState.screen = screen
            barState.mode = "center"
            CaptureService.closeBar()
        }
        function hide(): void {
            barState.screen = null
            barState.mode = ""
        }
        function toggle(): void {
            if (barState.mode === "center") hide()
            else show()
        }
    }

    // The launcher pulls in AppProvider + Quickshell's DesktopEntries scan
    // (all .desktop files + every app icon decoded). It is only shown on
    // demand, so it is not created at shell startup: the Loader stays inactive
    // until the first open, then latches active for the rest of the session so
    // reopening is instant. Search/usage state lives in a state file, so it is
    // unaffected either way.
    Loader {
        id: launcherLoader

        // Alias the controller in the Loader's own scope so the binding below
        // is an unambiguous object reference. Assigning `launcherController:
        // launcherController` directly inside the delegate resolves to the
        // delegate's own (still unset) required property, not this id.
        property var controller: launcherController

        active: false

        sourceComponent: Launcher {
            launcherController: launcherLoader.controller
        }
    }

    Connections {
        target: launcherController
        function onVisibleChanged() {
            if (launcherController.visible)
                launcherLoader.active = true
        }
    }

    // External-monitor Dynamic Island. Internal = eDP* (same convention as
    // DisplayService.layout[].internal); everything else is external. If no
    // screen matches (renamed outputs), fall back to full bars everywhere so
    // no monitor is ever left without a bar.
    function isInternalScreen(s) {
        return s && s.name && s.name.indexOf("eDP") === 0
    }

    Variants {
        // Full bar on internal screens only (external ones get DynamicIsland
        // below). Same fallback: if nothing matches eDP*, bar everywhere.
        model: Quickshell.screens.filter(screen => isInternalScreen(screen) || !Quickshell.screens.some(isInternalScreen)).map(screen => ({ barState: barState, launcherController: launcherController, mediaService: mediaService, screen: screen }))

        delegate: Bar {}
    }

    Variants {
        model: Quickshell.screens.filter(screen => !isInternalScreen(screen) && Quickshell.screens.some(isInternalScreen)).map(screen => ({ mediaService: mediaService, screen: screen }))

        delegate: DynamicIsland {}
    }

    Variants {
        model: Quickshell.screens.filter(screen => isInternalScreen(screen) || !Quickshell.screens.some(isInternalScreen)).map(screen => ({ barState: barState, screen: screen }))

        delegate: ControlCenter {}
    }

    Variants {
        model: Quickshell.screens.filter(screen => isInternalScreen(screen) || !Quickshell.screens.some(isInternalScreen)).map(screen => ({ screen: screen }))

        delegate: NotificationCenter {}
    }

    Variants {
        model: Quickshell.screens.filter(screen => isInternalScreen(screen) || !Quickshell.screens.some(isInternalScreen)).map(screen => ({ screen: screen }))

        delegate: NotificationPopup {}
    }

    Variants {
        model: Quickshell.screens.filter(screen => isInternalScreen(screen) || !Quickshell.screens.some(isInternalScreen)).map(screen => ({ screen: screen }))

        delegate: CaptureOverlay {}
    }

    Variants {
        // OSD stays on every screen by design: the volume/brightness/caps
        // overlay renders on the focused screen only (see OSD.qml isFocused),
        // so filtering it to internal would hide it whenever an external
        // monitor is focused. Lightweight click-through window; only one ever
        // shows at a time, never a duplicate.
        model: Quickshell.screens.map(screen => ({ screen: screen }))

        delegate: OSD {}
    }

    ScreenshotPreview {}
}
