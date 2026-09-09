pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Io

// Read-only Wi-Fi status for the bar's Wi-Fi indicator + popover. Mostly native
// Quickshell.Networking (NetworkManager / iwd backend); two tiny shell reads
// fill gaps the 0.3.1 QML API doesn't expose (`ip` for the local IPv4, `nmcli`
// for the AP band). The richer WifiService (modules/bar/WifiService.qml) still
// owns scanning and connect/disconnect for the Control Center.
Item {
    id: root

    readonly property bool wifiEnabled: Networking.wifiEnabled

    // Connected Wi-Fi device first, else the first Wi-Fi device as a fallback.
    readonly property var activeDevice: {
        const values = Networking.devices.values
        let current = null
        let fallback = null
        for (let i = 0; i < values.length; i++) {
            const d = values[i]
            if (d.type !== DeviceType.Wifi)
                continue
            if (d.connected) {
                current = d
                break
            }
            if (fallback === null)
                fallback = d
        }
        return current !== null ? current : fallback
    }

    readonly property bool connected: root.activeDevice !== null && root.activeDevice.connected
    readonly property string interfaceName: root.activeDevice ? (root.activeDevice.name || "") : ""

    // Local IPv4 for the active interface. activeDevice.address on this build
    // reports the hardware (MAC) address, so resolve it from `ip` instead. "" =
    // not connected / unknown (the popover renders that as "-").
    property string ipAddress: ""

    // The WifiNetwork the active device is currently associated with.
    readonly property var _activeNetwork: {
        if (!root.connected || !root.activeDevice)
            return null
        const nets = root.activeDevice.networks.values
        for (let i = 0; i < nets.length; i++) {
            if (nets[i] && nets[i].connected)
                return nets[i]
        }
        return null
    }

    readonly property string ssid: {
        if (!root.wifiEnabled)
            return "Wi-Fi Off"
        if (!root.connected)
            return "Disconnected"
        return (root._activeNetwork && root._activeNetwork.name)
            ? root._activeNetwork.name : "Connected"
    }

    // 0-100. signalStrength is a 0..1 double.
    readonly property int signalStrength: root._activeNetwork
        ? Math.round(root._activeNetwork.signalStrength * 100) : 0

    // 0 (none) .. 4 (excellent) - drives the bar glyph.
    readonly property int signalLevel: {
        if (!root.connected)
            return 0
        const s = root.signalStrength
        if (s >= 75) return 4
        if (s >= 50) return 3
        if (s >= 25) return 2
        if (s > 0) return 1
        return 0
    }

    // Band of the associated AP ("5 GHz" / "2.4 GHz" / "6 GHz"), or "" when not
    // connected / unknown. No native frequency in Quickshell.Networking 0.3.1, so
    // this is a small nmcli read refreshed on connect + every 20s while up.
    property string frequency: ""

    function toggleWifi() {
        Networking.wifiEnabled = !Networking.wifiEnabled
    }

    // Re-resolve IP + band. Called on connect / interface change, on a slow
    // timer while up, and publicly.
    function refresh() {
        if (root.connected && root.wifiEnabled) {
            if (!ipProc.running)
                ipProc.running = true
            if (!freqProc.running)
                freqProc.running = true
        } else {
            root.ipAddress = ""
            root.frequency = ""
        }
    }

    Process {
        id: ipProc

        // One address per line: "3: wlan0    inet 192.168.1.6/24 brd ... "
        command: ["ip", "-4", "-o", "addr", "show", "scope", "global"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const want = root.interfaceName
            const lines = ipProc.stdout.text.split("\n")
            let found = ""
            for (let i = 0; i < lines.length; i++) {
                const l = lines[i]
                const m = l.match(/\binet\s+(\d+\.\d+\.\d+\.\d+)/)
                if (!m)
                    continue
                // Prefer the active interface; otherwise take the first global v4.
                if (want.length > 0 && l.indexOf(" " + want + " ") !== -1) {
                    found = m[1]
                    break
                }
                if (found.length === 0)
                    found = m[1]
            }
            root.ipAddress = found
        }
    }

    Process {
        id: freqProc

        command: ["nmcli", "-t", "-f", "IN-USE,FREQ", "device", "wifi"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            let band = ""
            const lines = freqProc.stdout.text.split("\n")
            for (let i = 0; i < lines.length; i++) {
                const l = lines[i]
                if (l.length === 0 || l[0] !== "*")
                    continue
                // "*:5180 MHz"  -> everything after the first ":" is the freq.
                const mhz = parseInt(l.substring(l.indexOf(":") + 1).replace(/[^0-9]/g, ""), 10)
                if (!isNaN(mhz) && mhz > 0) {
                    if (mhz >= 5925) band = "6 GHz"
                    else if (mhz >= 4900) band = "5 GHz"
                    else band = "2.4 GHz"
                }
                break
            }
            root.frequency = band
        }
    }

    onConnectedChanged: root.refresh()
    onInterfaceNameChanged: root.refresh()

    Timer {
        interval: 20000
        repeat: true
        running: root.connected
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Keep the scanner alive so signalStrength / the associated network stay
    // fresh (mirrors WifiService).
    function _enableScanner() {
        if (root.activeDevice) {
            try {
                root.activeDevice.scannerEnabled = true
            } catch (e) {}
        }
    }

    onActiveDeviceChanged: root._enableScanner()
    Component.onCompleted: root._enableScanner()
}
