import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "."

PanelWindow {
    id: root

    required property var modelData

    readonly property ShellScreen targetScreen: modelData.screen
    readonly property bool open: SettingsService.open && SettingsService.screen === root.targetScreen

    readonly property real cardWidth: Math.max(460, Math.min(920, (root.targetScreen ? root.targetScreen.width : 1440) - 140))
    readonly property real cardHeight: Math.max(380, Math.min(620, (root.targetScreen ? root.targetScreen.height : 900) - 140))

    screen: root.targetScreen

    visible: true

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-settings"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    focusable: root.open

    mask: Region { item: root.open ? content : null }

    onOpenChanged: if (root.open) settingsView.forceActiveFocus()

    Shortcut {
        sequences: ["Escape"]
        enabled: root.open
        onActivated: SettingsService.hide()
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.open

        onCleared: {
            if (!root.open)
                return
            SettingsService.hide()
        }
    }

    Item {
        id: content

        anchors.fill: parent
        opacity: root.open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)

            MouseArea {
                anchors.fill: parent
                onClicked: SettingsService.hide()
            }
        }

        Item {
            id: card

            anchors.centerIn: parent
            width: root.cardWidth
            height: root.cardHeight

            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                horizontalOffset: 0
                verticalOffset: 6
                radius: 20
                samples: 25
                color: Qt.rgba(0, 0, 0, 0.5)
            }

            MouseArea {
                anchors.fill: parent
            }

            SettingsView {
                id: settingsView

                anchors.fill: parent
                onCloseRequested: SettingsService.hide()
            }
        }
    }
}
