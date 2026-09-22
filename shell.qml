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
        // preview (vs auto-expand). Gates the focus grab (Bar) + focus routing
        // (DynamicCenter/MediaPlayer) and suppresses the auto-hide timer:
        // manual is a persistent interactive surface, auto is focus-free.
        property bool mediaManual: false

        // Escape / click-outside clear `mode` -> kill the auto-hide timer in the
        // same turn so a stale tick can't fire after an early dismiss.
        onModeChanged: if (mode !== "media") mediaAutoHide.stop()
        // Manual open pins the panel: kill any auto-hide already counting.
        onMediaManualChanged: if (mediaManual) mediaAutoHide.stop()
    }

    // ---- Media: one service shared by every screen's bar preview + expanded
    // player, plus the auto-expand / auto-hide lifecycle for the "media"
    // DynamicCenter surface.
    MediaService {
        id: mediaService
        positionActive: barState.mode === "media"
    }

    // Run the cava spectrum analyzer (-> CavaService.bars, consumed by the bar
    // MediaPreview mini-viz) only while something is actually playing; pausing
    // releases its capture stream.
    Binding {
        target: CavaService
        property: "active"
        value: mediaService.playing
    }

    Timer {
        id: mediaAutoHide
        interval: 3000
        running: barState.mode === "media" && !barState.mediaManual
        onTriggered: {
            // Manual-open never auto-hides; it closes via Escape/outside-click.
            if (barState.mode === "media" && !barState.mediaManual) {
                barState.screen = null
                barState.mode = ""
            }
        }
    }

    Connections {
        target: mediaService

        // Playback started / track changed while playing -> briefly expand.
        // (MediaService only fires mediaEvent on a real paused/stopped->playing
        // transition or a track change; no need to re-check playing here, and a
        // laggy player may still report paused for a beat after the command.)
        function onMediaEvent() {
            if (barState.mode !== "" && barState.mode !== "media")
                return
            // Already pinned open by an explicit user click -> a track change
            // must NOT demote it into an auto-hiding preview.
            if (barState.mode === "media" && barState.mediaManual)
                return
            focusState.inquire()
            const screen = focusedScreen()
            if (!screen)
                return
            barState.mediaManual = false
            barState.screen = screen
            barState.mode = "media"
            mediaAutoHide.restart()
        }

        // User is interacting with the auto-expanded player -> keep it open by
        // postponing the auto-hide timer. Manual-open has no timer running.
        function onInteraction() {
            if (barState.mode === "media" && !barState.mediaManual)
                mediaAutoHide.restart()
        }
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

    Variants {
        model: Quickshell.screens.map(screen => ({ barState: barState, launcherController: launcherController, mediaService: mediaService, screen: screen }))

        delegate: Bar {}
    }

    Variants {
        model: Quickshell.screens.map(screen => ({ barState: barState, screen: screen }))

        delegate: ControlCenter {}
    }

    Variants {
        model: Quickshell.screens.map(screen => ({ screen: screen }))

        delegate: NotificationCenter {}
    }

    Variants {
        model: Quickshell.screens.map(screen => ({ screen: screen }))

        delegate: NotificationPopup {}
    }

    Variants {
        model: Quickshell.screens.map(screen => ({ screen: screen }))

        delegate: CaptureOverlay {}
    }

    Variants {
        model: Quickshell.screens.map(screen => ({ screen: screen }))

        delegate: OSD {}
    }

    ScreenshotPreview {}
}
