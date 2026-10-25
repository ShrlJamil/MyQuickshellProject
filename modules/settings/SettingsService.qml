pragma Singleton

import QtQuick
import Quickshell

QtObject {
    id: root

    property bool open: false
    property var screen: null

    // Selected category, owned here rather than by SettingsView so IPC
    // callers can open the window on a specific page (the `display` target
    // in shell.qml relies on this). displayCategory must match the position
    // of "Display" in SettingsView.categories.
    property int categoryIndex: 0
    readonly property int displayCategory: 2

    function show(target) {
        if (target)
            root.screen = target
        root.open = true
    }

    function hide() {
        root.open = false
    }

    function toggle(target) {
        if (root.open) {
            root.hide()
            return
        }
        root.show(target)
    }
}
