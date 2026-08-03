//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import "modules/launcher"
import "modules/controllers"

ShellRoot {
    property var launcherRef: launcher

    function closeLauncher(): void {
        if (launcherRef)
            launcherRef.close()
    }

    LauncherController {
        id: launcherController
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
}
