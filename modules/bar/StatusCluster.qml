import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../components"

// Status cluster: Wi-Fi, Bluetooth and volume indicators grouped in one
// pill where the standalone Wi-Fi indicator and the Control Center button
// used to sit. The glyphs are pure status indicators; the WHOLE pill is
// the Control Center button - a click anywhere writes the same barState
// "center" toggle the old dedicated button wrote. The Wi-Fi details
// popover that used to hang off the Wi-Fi icon is gone: its information
// lives in Control Center now, which is what a click opens.
//
// The pill has a fixed width (all three slots always present, state shown
// by glyph + tint) so the bar layout never shifts as radios come and go.
Item {
    id: root

    property var barState: null
    property var screen: null

    readonly property bool centerOpen: root.barState
        && root.barState.mode === "center" && root.barState.screen === root.screen

    implicitWidth: clusterRow.implicitWidth + 16
    implicitHeight: 28
    width: implicitWidth
    height: 28

    // Own service instances, the ControlCenter pattern: both track their
    // backends (PipeWire / BlueZ) reactively, so state converges with the
    // other instances through the backend itself.
    AudioService {
        id: audioSvc
    }

    BluetoothService {
        id: btSvc

        readonly property bool anyConnected: {
            const list = btSvc.devices || []
            for (let i = 0; i < list.length; i++) {
                if (list[i] && list[i].connected)
                    return true
            }
            return false
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.centerOpen || clusterTap.pressed ? Theme.surfaceHover
            : (clusterHover.hovered ? Theme.surfaceHover : "transparent")
    }

    Row {
        id: clusterRow

        anchors.centerIn: parent
        spacing: 2

        // ---- Wi-Fi ------------------------------------------------------
        // Glyph logic transplanted unchanged from the old standalone
        // indicator (NetworkService signal levels + icon-theme names).
        Item {
            id: wifiSlot

            width: 28
            height: 28

            readonly property bool wifiOn: NetworkService.wifiEnabled
            readonly property bool online: NetworkService.connected

            readonly property string glyph: {
                if (!wifiOn)
                    return "network-wireless-disabled-symbolic"
                if (!online)
                    return "network-wireless-offline-symbolic"
                switch (NetworkService.signalLevel) {
                case 4: return "network-wireless-signal-excellent-symbolic"
                case 3: return "network-wireless-signal-good-symbolic"
                case 2: return "network-wireless-signal-ok-symbolic"
                case 1: return "network-wireless-signal-weak-symbolic"
                default: return "network-wireless-signal-none-symbolic"
                }
            }

            IconImage {
                id: wifiIcon

                anchors.centerIn: parent
                width: 22
                height: 22

                source: Quickshell.iconPath(wifiSlot.glyph, "network-wireless")
                asynchronous: true
            }

            // Idle / connected -> solid white; Wi-Fi radio disabled -> muted.
            ColorOverlay {
                anchors.fill: wifiIcon
                source: wifiIcon
                layer.enabled: true
                layer.effect: DropShadow {
                    transparentBorder: true
                    horizontalOffset: 0
                    verticalOffset: 1
                    radius: 2
                    samples: 9
                    color: Theme.textShadow
                }
                color: wifiSlot.wifiOn ? Theme.icon : Theme.textMuted
            }
        }

        // ---- Bluetooth ----------------------------------------------------
        Item {
            width: 28
            height: 28

            Image {
                id: btIcon

                anchors.centerIn: parent
                width: 18
                height: 18
                sourceSize.width: 36
                sourceSize.height: 36
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                visible: false

                source: "file://" + Quickshell.shellPath("assets/bluetooth-svgrepo-com.svg")
            }

            // Off / no adapter -> muted; on, nothing connected -> solid;
            // connected -> accent (active-state highlight).
            ColorOverlay {
                anchors.fill: btIcon
                source: btIcon
                layer.enabled: true
                layer.effect: DropShadow {
                    transparentBorder: true
                    horizontalOffset: 0
                    verticalOffset: 1
                    radius: 2
                    samples: 9
                    color: Theme.textShadow
                }
                color: !btSvc.enabled ? Theme.textMuted
                    : (btSvc.anyConnected ? Theme.accent : Theme.icon)
            }
        }

        // ---- Volume -------------------------------------------------------
        Item {
            id: volSlot

            width: 28
            height: 28

            readonly property bool silent: audioSvc.muted || audioSvc.volume <= 0

            readonly property string glyph: {
                if (silent)
                    return "volume-off-svgrepo-com.svg"
                if (audioSvc.volume < 34)
                    return "volume-low-svgrepo-com.svg"
                if (audioSvc.volume < 67)
                    return "volume-medium-svgrepo-com.svg"
                return "volume-high-svgrepo-com.svg"
            }

            Image {
                id: volIcon

                anchors.centerIn: parent
                width: 20
                height: 20
                sourceSize.width: 40
                sourceSize.height: 40
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                visible: false

                source: "file://" + Quickshell.shellPath("assets/volume/" + volSlot.glyph)
            }

            ColorOverlay {
                anchors.fill: volIcon
                source: volIcon
                layer.enabled: true
                layer.effect: DropShadow {
                    transparentBorder: true
                    horizontalOffset: 0
                    verticalOffset: 1
                    radius: 2
                    samples: 9
                    color: Theme.textShadow
                }
                color: volSlot.silent ? Theme.textMuted : Theme.icon
            }
        }
    }

    HoverHandler {
        id: clusterHover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: clusterTap

        onTapped: {
            if (root.centerOpen) {
                root.barState.screen = null
                root.barState.mode = ""
            } else {
                root.barState.screen = root.screen
                root.barState.mode = "center"
            }
        }
    }
}
