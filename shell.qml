//@ pragma UseQApplication

import QtQml
import Quickshell
import Quickshell.Io
import "modules/launcher"
import "modules/controllers"
import "modules/bar"

ShellRoot {
    property var launcherRef: launcher

    function closeLauncher(): void {
        if (launcherRef)
            launcherRef.close()
    }

    LauncherController {
        id: launcherController
    }

    QtObject {
        id: barState

        property string mode: ""
        property ShellScreen screen: null
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { if (launcherController.visible) closeLauncher(); else launcherController.show() }
        function show(): void { launcherController.show() }
        function hide(): void { closeLauncher() }
    }

    Launcher {
        id: launcher
        launcherController: launcherController
    }

    Variants {
        model: Quickshell.screens.map(screen => ({ barState: barState, launcherController: launcherController, screen: screen }))

        delegate: Bar {}
    }
}
