import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../components"

// Standalone power menu: a full-screen Overlay PanelWindow per screen that
// floats the PowerMenu card at the centre over a dimmed background. It
// replaces the DynamicCenter-hosted "power" surface, so the menu no longer
// depends on the Bar window or its focus grab.
//
// State is unchanged: the `power` IPC target (and the user's keybinds that
// call it) still writes barState.mode / barState.screen, and this window
// renders when barState names "power" on its screen - the same targeting
// as before (the bar screen). Closing writes the same two fields back,
// exactly like the IPC hide().
//
// The window never unmaps (visible stays true); `menuOpen` gates the
// content, the input mask, focusable and the focus grab instead - the
// persistently-mapped pattern the Bar window and DynamicIsland use, whose
// grabs hold (see CapturePicker for the full rationale). While closed the
// mask region is empty, so the full-screen surface never eats input.
PanelWindow {
    id: root

    required property var modelData

    readonly property var barState: modelData.barState

    screen: modelData.screen

    readonly property bool menuOpen: root.barState.mode === "power" && root.barState.screen === root.screen

    visible: true

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-power-menu"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // No keyboardFocus override: default (None) + the grab below is the
    // focus recipe every working standalone window in this shell uses.

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    focusable: root.menuOpen

    mask: Region { item: root.menuOpen ? content : null }

    function closeMenu() {
        root.barState.screen = null
        root.barState.mode = ""
    }

    onMenuOpenChanged: {
        // Same focus choreography the DynamicCenter host used: fresh
        // selection state, then hand the menu item keyboard focus so its
        // Keys handlers (arrows / hold shortcuts / Esc) are live the moment
        // the grab delivers seat focus to this window.
        if (root.menuOpen) {
            powerMenu.reset()
            powerMenu.forceActiveFocus()
        }
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.menuOpen

        onCleared: {
            // Guarded like the other popovers: a programmatic close flips
            // `active` off itself and must not re-enter.
            if (!root.menuOpen)
                return
            root.closeMenu()
        }
    }

    Item {
        id: content

        anchors.fill: parent
        opacity: root.menuOpen ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        // Dimmed background. Clicking it dismisses the menu (the scrim is
        // part of THIS window, so its clicks land here; the grab's cleared
        // signal covers focus leaving the window entirely).
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeMenu()
            }
        }

        Rectangle {
            id: card

            anchors.centerIn: parent
            width: Math.min(powerMenu.implicitWidth, root.width * 0.9)
            height: powerMenu.implicitHeight
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

            // Absorb clicks on the card's gaps so they do not fall through
            // to the scrim and dismiss the menu mid-aim.
            MouseArea {
                anchors.fill: parent
            }

            PowerMenu {
                id: powerMenu

                anchors.fill: parent
                onCloseRequested: root.closeMenu()
            }
        }
    }
}
