import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../services"
import "../controllers"

PanelWindow {
    id: root

    required property var launcherController

    visible: launcherController.visible

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    exclusiveZone: 0
    aboveWindows: true
    focusable: true

    function close() {
        launcherView.reset()
        launcherController.hide()
    }

    mask: Region {
        item: visible ? launcherView : null
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.visible

        onCleared: {
            if (launcherController.visible)
                root.close()
        }
    }

    AppProvider {
        id: appProvider
    }

    LauncherView {
        id: launcherView

        anchors.centerIn: parent

        appProvider: appProvider

        onCloseRequested: {
            root.close()
        }
    }
}
