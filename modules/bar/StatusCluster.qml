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
    implicitHeight: 30
    width: implicitWidth
    height: 30

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
        radius: 15
        color: root.centerOpen ? (clusterTap.pressed || clusterHover.hovered ? Theme.activeSurfaceHover : Theme.activeSurface)
            : (clusterTap.pressed || clusterHover.hovered ? Theme.surfaceHover : (Theme.barSegmented ? Theme.barWidgetSurface : "transparent"))
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

            width: 30
            height: 30

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
                width: 23
                height: 23

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
                    color: root.centerOpen ? Qt.rgba(1, 1, 1, 0.35) : Theme.textShadow
                }
                color: root.centerOpen ? (wifiSlot.wifiOn ? Theme.onActiveSurface : Theme.onActiveSurfaceDim)
                    : (wifiSlot.wifiOn ? Theme.icon : Theme.textMuted)
            }
        }

        // ---- Bluetooth ----------------------------------------------------
        Item {
            id: btSlot

            width: 30
            height: 30

            // State glyphs (assets/dynamic bluetooth/*): off while the radio
            // is off, connect while a device is connected, signal while
            // scanning, on otherwise. The glyph carries the state - the tint
            // is Theme.icon in every state, never dimmed.
            readonly property string glyph: {
                if (!btSvc.enabled)
                    return "bluetooth-off-svgrepo-com.svg"
                if (btSvc.anyConnected)
                    return "bluetooth-connect-svgrepo-com.svg"
                if (btSvc.scanning)
                    return "bluetooth-signal-svgrepo-com.svg"
                return "bluetooth-on-svgrepo-com.svg"
            }

            Image {
                id: btIcon

                anchors.centerIn: parent
                width: 19
                height: 19
                sourceSize.width: 44
                sourceSize.height: 44
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                visible: false

                // The set's folder name contains a space; percent-encode it
                // so the file URL is well-formed wherever the repo lives.
                source: ("file://" + Quickshell.shellPath("assets/dynamic bluetooth/" + btSlot.glyph)).replace(/ /g, "%20")
            }

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
                    color: root.centerOpen ? Qt.rgba(1, 1, 1, 0.35) : Theme.textShadow
                }
                color: root.centerOpen ? Theme.onActiveSurface : Theme.icon
            }
        }

        // ---- Volume -------------------------------------------------------
        Item {
            id: volSlot

            width: 30
            height: 30

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
                width: 21
                height: 21
                sourceSize.width: 48
                sourceSize.height: 48
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
                    color: root.centerOpen ? Qt.rgba(1, 1, 1, 0.35) : Theme.textShadow
                }
                // The off glyph carries the muted state - the tint stays
                // full-strength in both schemes, never dimmed.
                color: root.centerOpen ? Theme.onActiveSurface : Theme.icon
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
