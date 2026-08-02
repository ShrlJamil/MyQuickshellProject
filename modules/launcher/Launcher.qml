import QtQuick
import Quickshell
import "../services"

PanelWindow {
    id: root

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

    AppProvider {
        id: appProvider
    }

    LauncherView {
        anchors.centerIn: parent

        appProvider: appProvider

        onCloseRequested: {
            root.visible = false
        }
    }
}
