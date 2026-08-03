//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import "modules/launcher"
import "modules/controllers"

ShellRoot {
    LauncherController {
        id: launcherController
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { launcherController.toggle() }
        function show(): void { launcherController.show() }
        function hide(): void { launcherController.hide() }
    }

    Launcher {
        launcherController: launcherController
    }
}
