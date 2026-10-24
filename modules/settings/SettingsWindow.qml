import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../components"
import "."

PanelWindow {
    id: root

    required property var modelData

    readonly property ShellScreen targetScreen: modelData.screen
    readonly property bool open: SettingsService.open && SettingsService.screen === root.targetScreen

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

        Rectangle {
            id: card

            anchors.centerIn: parent
            width: settingsView.implicitWidth
            height: settingsView.implicitHeight
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
