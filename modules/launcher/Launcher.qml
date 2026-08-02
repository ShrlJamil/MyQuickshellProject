import QtQuick
import Quickshell

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

    LauncherView {
        anchors.centerIn: parent
    }
}
