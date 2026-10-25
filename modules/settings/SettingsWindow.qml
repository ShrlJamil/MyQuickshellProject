import QtQuick
import Quickshell
import "."

// Settings as a normal floating application window (xdg toplevel), NOT a
// layer-shell panel: Hyprland manages it like any other application - it
// appears in window lists, takes regular focus, and floats or tiles by his
// own window rules. There is no scrim, no fullscreen surface, no mask and
// no focus grab; the window simply exists while SettingsService.open holds.
// (To float + centre it, his Hyprland config needs a window rule matching
// this window - title "Settings", class/app_id is Quickshell's own.)
//
// Single instance for the whole shell (see shell.qml): one application
// window, not one per screen. SettingsService.screen survives only as the
// initial placement hint - the screen the opener targeted.
FloatingWindow {
    id: root

    title: "Settings"
    color: "transparent"

    screen: SettingsService.screen

    visible: SettingsService.open

    // Starting size and floor, carried over from the old centred card: the
    // Display page needs the room. implicit* applies only while the window
    // is hidden (FloatingWindow semantics), so it sets the opening size
    // without ever fighting a resize the user made through Hyprland.
    implicitWidth: 880
    implicitHeight: 560
    minimumSize: Qt.size(460, 380)

    onVisibleChanged: {
        if (root.visible) {
            settingsView.forceActiveFocus()
        } else if (SettingsService.open) {
            // Closed from the window-manager side (kill keybind, decoration
            // button): keep the service truthful, or the next toggle would
            // "hide" an already-gone window instead of opening it.
            SettingsService.hide()
        }
    }

    Shortcut {
        sequences: ["Escape"]
        onActivated: SettingsService.hide()
    }

    SettingsView {
        id: settingsView

        anchors.fill: parent
        onCloseRequested: SettingsService.hide()
    }
}
