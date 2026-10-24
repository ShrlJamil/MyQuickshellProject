pragma Singleton

import QtQuick
import Quickshell

QtObject {
    id: root

    property bool open: false
    property var screen: null

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
