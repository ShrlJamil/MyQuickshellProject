//@ pragma UseQApplication

import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules/launcher"
import "modules/controllers"
import "modules/bar"
import "modules/capture"

ShellRoot {
    property var launcherRef: launcher

    function closeLauncher(): void {
        if (launcherRef)
            launcherRef.close()
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

    CaptureService {
        id: captureService
    }

    QtObject {
        id: barState

        property string mode: ""
        property ShellScreen screen: null
        property bool barEnabled: false
    }

    IpcHandler {
        target: "bar"

        function enable(): void { barState.barEnabled = true }
        function disable(): void { barState.barEnabled = false }
        function toggle(): void { barState.barEnabled = !barState.barEnabled }
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
        target: "capture"

        function open(): void { captureService.openBar() }
        function region(): void { captureService.triggerCapture("region") }
        function window(): void { captureService.triggerCapture("window") }
        function screen(): void { captureService.triggerCapture("screen") }
        function bar(): void { captureService.openBar() }
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

    Launcher {
        id: launcher
        launcherController: launcherController
    }

    Variants {
        model: Quickshell.screens.map(screen => ({ barState: barState, launcherController: launcherController, captureService: captureService, screen: screen }))

        delegate: Bar {}
    }

    Variants {
        model: Quickshell.screens.map(screen => ({ barState: barState, captureService: captureService, screen: screen }))

        delegate: ControlCenter {}
    }

    CapturePreview {
        captureService: captureService
    }
}