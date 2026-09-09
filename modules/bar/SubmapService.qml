pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Active Hyprland submap name ("" when not in a submap). Quickshell 0.3.1 has no
// Hyprland.submap property, so track it off the socket2 `submap>>` event. Empty
// data (a bare `submap>>`) means the submap was reset.
Item {
    id: root

    property string current: ""

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "submap")
                root.current = (event.data || "").trim()
        }
    }
}
