import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "."
import "../../components"

// Floating capture picker: a standalone bottom-centre PanelWindow, one
// instance per screen, shown only on the Hyprland-focused screen. It
// replaces the old DynamicCenter-hosted picker, so capture can be invoked
// on any monitor - not just the bar screen - and no longer depends on
// barState / the Bar window's focus grab.
//
// CaptureBar owns the buttons and hotkeys (R / W / F / Esc). This window
// owns placement, framing and dismissal: Esc / Cancel run through
// CaptureBar -> CaptureService.closeBar(), a click outside clears the
// focus grab below, which also closes the picker.
PanelWindow {
    id: root

    required property var modelData

    screen: modelData.screen

    readonly property bool isFocusedScreen: modelData.screen
        && Hyprland.focusedMonitor
        && modelData.screen.name === Hyprland.focusedMonitor.name

    visible: CaptureService.barVisible && root.isFocusedScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-capture-picker"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { bottom: true }
    margins { bottom: 16 }

    // Card (460x64) plus 16px of breathing room on every side so the drop
    // shadow is not clipped by the surface edge (MediaPlayerPopover pattern).
    implicitWidth: 492
    implicitHeight: 96

    color: "transparent"
    focusable: true

    // Input only on the card itself; the padding ring stays click-through.
    mask: Region { item: frame }

    HyprlandFocusGrab {
        windows: [root]
        active: root.visible

        onCleared: {
            // Guarded like the other popovers: a programmatic close flips
            // `active` off itself and must not re-enter.
            if (!CaptureService.barVisible)
                return
            CaptureService.closeBar()
        }
    }

    Rectangle {
        id: frame

        anchors.centerIn: parent
        width: 460
        height: 64
        radius: 18
        color: Theme.background
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)

        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            horizontalOffset: 0
            verticalOffset: 4
            radius: 16
            samples: 25
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        CaptureBar {
            anchors.centerIn: parent
        }
    }
}
