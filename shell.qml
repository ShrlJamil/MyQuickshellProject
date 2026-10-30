//@ pragma UseQApplication

import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "components"
import "modules/launcher"
import "modules/controllers"
import "modules/bar"
import "modules/capture"
import "modules/display"
import "modules/services"
import "modules/settings"
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

    // The Dynamic Center surfaces (media) are
    // rendered by the full Bar, so their IPC must target the screen hosting that
    // Bar - never the focused one, or barState.screen names a screen with no Bar
    // and nothing renders. The power menu's window is standalone now, but its
    // IPC keeps this same targeting: barState.screen is the screen it renders
    // on. That screen is the persisted Primary Display, resolved
    // through DisplayService's stable identity; when the preference is internal,
    // or the preferred external is disconnected, it is the internal panel (the
    // same fallback enforcement uses). null when no internal panel exists at all,
    // so callers fall back to the focused screen.
    function barScreen() {
        const n = DisplayService.primaryMonitorName()
        if (n) {
            for (let i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === n)
                    return Quickshell.screens[i]
            }
        }
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (isInternalScreen(Quickshell.screens[i]))
                return Quickshell.screens[i]
        }
        return null
    }

    function isBarScreen(s) {
        const b = barScreen()
        return b !== null && s === b
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
        // true while the floating media player popover is open. Gates the 1 Hz
        // position tick and the popover's dismissal state.
        property bool mediaPopoverOpen: false
    }

    // ---- Media: one service shared by the bar pill and the floating player
    // popover. The popover opens only on an explicit pill click; playback /
    // track events never change shell state.
    MediaService {
        id: mediaService
        positionActive: barState.mediaPopoverOpen
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

    // User preference -> Theme: the validated border opacity from
    // PreferencesService (preferences.json) drives Theme's token. Wired
    // here at the composition root - the CavaService pattern above - so
    // components/Theme.qml needs no import of the settings module and
    // no dependency cycle can form; Theme's own 0.06 literal remains
    // the pre-service fallback and equals the service default.
    Binding {
        target: Theme
        property: "materialBorderOpacity"
        value: PreferencesService.materialBorderOpacity
    }

    // Bar background (Settings > Appearance, Stage 2): with bar
    // transparency off, the effective strip opacity is 0 - exactly the
    // long-standing look. With it on, the stored background opacity
    // becomes effective. The ternary lives here, at the single binding
    // site, so Theme.barSurfaceOpacity stays the one value every bar
    // background surface reads (strip, concave fills).
    Binding {
        target: Theme
        property: "barSurfaceOpacity"
        value: PreferencesService.barTransparency ? PreferencesService.barBackgroundOpacity : 0
    }

    // Bar layout mode (Stage 3): only "float" has a Theme token; the
    // default and (not yet implemented) segmented modes both read as
    // not-floating, so Bar.qml needs no mode string of its own.
    Binding {
        target: Theme
        property: "barFloating"
        value: PreferencesService.barLayoutMode === "float"
    }

    // Segmented bar (Stage 4): one layoutMode string drives both mode
    // tokens, so float and segmented can never be active together.
    Binding {
        target: Theme
        property: "barSegmented"
        value: PreferencesService.barLayoutMode === "segmented"
    }

    Binding {
        target: Theme
        property: "barWidgetOpacity"
        value: PreferencesService.barWidgetBackgroundOpacity
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { if (launcherController.visible) closeLauncher(); else launcherController.show() }
        function show(): void { launcherController.show() }
        function hide(): void { closeLauncher() }
    }

    IpcHandler {
        id: powerIpc

        target: "power"

        function show(): void {
            focusState.inquire()
            const screen = barScreen() || focusedScreen()
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

        // Display is a Settings page now, not a DynamicCenter surface: this
        // target opens the Settings window on the focused screen with the
        // Display category preselected, after the same barState / capture
        // housekeeping the `settings` target does. Keybinds are unchanged.
        function show(): void {
            focusState.inquire()
            const screen = focusedScreen()
            if (!screen) return
            barState.screen = null
            barState.mode = ""
            CaptureService.closeBar()
            SettingsService.categoryIndex = SettingsService.displayCategory
            SettingsService.show(screen)
        }
        function hide(): void {
            SettingsService.hide()
        }
        function toggle(): void {
            if (SettingsService.open) hide()
            else show()
        }
    }

    IpcHandler {
        target: "wallpapers"

        // Wallpapers is a Settings page now, not a DynamicCenter surface:
        // this target opens the Settings window on the focused screen with
        // the Wallpaper category preselected, after the same barState /
        // capture housekeeping the `settings` target does. Keybinds are
        // unchanged.
        function show(): void {
            focusState.inquire()
            const screen = focusedScreen()
            if (!screen) return
            barState.screen = null
            barState.mode = ""
            CaptureService.closeBar()
            SettingsService.categoryIndex = SettingsService.wallpaperCategory
            SettingsService.show(screen)
        }
        function hide(): void {
            SettingsService.hide()
        }
        function toggle(): void {
            if (SettingsService.open) hide()
            else show()
        }
    }

    IpcHandler {
        target: "mediaPreview"

        function show(): void {
            focusState.inquire()
            const screen = barScreen() || focusedScreen()
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
            const screen = barScreen() || focusedScreen()
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

        // The capture picker is a standalone floating window, not a
        // barState.mode - clear any open bar surface first so the Bar
        // window's focus grab can't shadow the picker's own input.
        function open(): void {
            console.log("[IPC] capture open")
            barState.screen = null
            barState.mode = ""
            CaptureService.openBar()
        }
        function region(): void { CaptureService.triggerCapture("region") }
        function window(): void { CaptureService.triggerCapture("window") }
        function screen(): void { CaptureService.triggerCapture("screen") }
        // instant shot of the focused screen straight to file + clipboard, no picker UI
        function fullscreen(): void { CaptureService.captureFullscreen() }
        function bar(): void {
            barState.screen = null
            barState.mode = ""
            CaptureService.openBar()
        }
    }

    IpcHandler {
        target: "record"

        // Screen recording (wf-recorder via RecordService): fullscreen on
        // the focused output with audio, to ~/Videos/Screencasts/. The bar
        // pill and the Control Center tile expose the same controls.
        function toggle(): void { RecordService.toggle() }
        function start(): void { RecordService.start() }
        function stop(): void { RecordService.stop() }
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

    IpcHandler {
        target: "settings"

        function show(): void {
            focusState.inquire()
            const screen = focusedScreen()
            if (!screen) return
            barState.screen = null
            barState.mode = ""
            CaptureService.closeBar()
            SettingsService.show(screen)
        }
        function hide(): void {
            SettingsService.hide()
        }
        function toggle(): void {
            if (SettingsService.open) hide()
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

    // Hardware split only: eDP* is the laptop panel (same convention as
    // DisplayService.layout[].internal). It is the fallback for barScreen()
    // when the Primary Display cannot be resolved from the preference.
    function isInternalScreen(s) {
        return s && s.name && s.name.indexOf("eDP") === 0
    }

    Variants {
        // Full bar on the screen that hosts the Primary Display (the other one
        // gets the DynamicIsland below). Same fallback as before: if no bar
        // screen can be resolved at all (renamed outputs), bar everywhere so no
        // monitor is ever left without one.
        model: Quickshell.screens.filter(screen => isBarScreen(screen) || barScreen() === null).map(screen => ({ barState: barState, launcherController: launcherController, mediaService: mediaService, screen: screen }))

        delegate: Bar {}
    }

    Variants {
        // Dynamic Island on the one other active monitor. Empty when the bar
        // screen could not be resolved (the bar-everywhere fallback above).
        model: Quickshell.screens.filter(screen => !isBarScreen(screen) && barScreen() !== null).map(screen => ({ mediaService: mediaService, screen: screen }))

        delegate: DynamicIsland {}
    }

    // Everything the full Bar owns or is opened from travels with it: the
    // Control Center (opened from a bar click), the Notification Center (bar
    // Date & Time) and the toast stack all live on the bar screen, exactly as
    // they used to live on the internal screen. (Capture is the exception -
    // see its all-screens Variants below.)
    Variants {
        model: Quickshell.screens.filter(screen => isBarScreen(screen) || barScreen() === null).map(screen => ({ barState: barState, screen: screen }))

        delegate: ControlCenter {
            onPowerRequested: powerIpc.show()
        }
    }

    Variants {
        model: Quickshell.screens.filter(screen => isBarScreen(screen) || barScreen() === null).map(screen => ({ screen: screen }))

        delegate: NotificationCenter {}
    }

    Variants {
        model: Quickshell.screens.filter(screen => isBarScreen(screen) || barScreen() === null).map(screen => ({ screen: screen }))

        delegate: NotificationPopup {}
    }

    Variants {
        // Capture overlay + picker live on every screen: each instance gates
        // its own visibility to the Hyprland-focused screen, so region /
        // window selection and the floating picker work on whichever monitor
        // is focused - not only the bar screen.
        model: Quickshell.screens.map(screen => ({ screen: screen }))

        delegate: CaptureOverlay {}
    }

    Variants {
        model: Quickshell.screens.map(screen => ({ screen: screen }))

        delegate: CapturePicker {}
    }

    Variants {
        // Power menu on every screen: a standalone centred modal over a
        // dimmed background. Each instance gates on barState (mode "power"
        // + its screen), which the unchanged `power` IPC target writes, so
        // it renders on the same screen the IPC targeted - just no longer
        // inside the Bar window's DynamicCenter.
        model: Quickshell.screens.map(screen => ({ barState: barState, screen: screen }))

        delegate: PowerMenuWindow {}
    }

    // Settings is ONE floating application window for the whole shell (see
    // SettingsWindow.qml) - no per-screen Variants: Hyprland places and
    // manages it like any other app, gated only by SettingsService.open.
    //
    // Fully lazy, unlike the launcher's latch: the Loader is active exactly
    // while Settings is open, so closing Settings DESTROYS the whole window
    // + view + DisplayManager tree and a closed Settings costs nothing at
    // all - no objects, no live bindings. SettingsService (the state
    // singleton: open / screen / categoryIndex) outlives the tree, so the
    // selected page survives the reload, and the Display page re-syncs on
    // every open by design (see SettingsView).
    Loader {
        id: settingsLoader

        active: SettingsService.open

        sourceComponent: SettingsWindow {}
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
