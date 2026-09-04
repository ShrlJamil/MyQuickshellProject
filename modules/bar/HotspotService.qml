import QtQuick
import Quickshell.Io

Item {
    id: root

    property bool enabled: false
    property bool secured: true
    property string ssid: ""
    property string password: ""
    property int clientCount: 0

    property string _dev: ""

    readonly property string _routeArgs: "ipv4.never-default yes ipv6.never-default yes connection.autoconnect-priority 0 connection.zone trusted ipv4.method shared ipv6.method ignore"

    readonly property string _startScript:
        'dev="$1"; ssid="$2"; psk="$3"; '
        + 'if ! nmcli -t -f NAME connection show | grep -qx Hotspot; then '
        + 'if [ -n "$psk" ]; then '
        + 'nmcli connection add type wifi mode ap con-name Hotspot ifname "$dev" ssid "$ssid" ' + root._routeArgs + ' 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$psk"; '
        + 'else '
        + 'nmcli connection add type wifi mode ap con-name Hotspot ifname "$dev" ssid "$ssid" ' + root._routeArgs + '; '
        + 'fi; fi; '
        + 'nmcli connection modify Hotspot ' + root._routeArgs + '; '
        + 'nmcli connection up Hotspot'

    readonly property string _configScript:
        'ssid="$1"; psk="$2"; sec="$3"; dev="$4"; '
        + 'if nmcli -t -f NAME connection show | grep -qx Hotspot; then '
        + 'nmcli connection modify Hotspot 802-11-wireless.ssid "$ssid"; '
        + 'if [ "$sec" = "1" ]; then '
        + 'nmcli connection modify Hotspot 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$psk"; '
        + 'else '
        + 'nmcli connection modify Hotspot 802-11-wireless-security.key-mgmt none; '
        + 'fi; '
        + 'nmcli connection modify Hotspot ' + root._routeArgs + '; '
        + 'if nmcli -t -f NAME connection show --active | grep -qx Hotspot; then nmcli connection down Hotspot; nmcli connection up Hotspot; fi; '
        + 'else '
        + 'if [ "$sec" = "1" ]; then '
        + 'nmcli connection add type wifi mode ap con-name Hotspot ifname "$dev" ssid "$ssid" ' + root._routeArgs + ' 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$psk"; '
        + 'else '
        + 'nmcli connection add type wifi mode ap con-name Hotspot ifname "$dev" ssid "$ssid" ' + root._routeArgs + '; '
        + 'fi; '
        + 'nmcli connection modify Hotspot ' + root._routeArgs + '; '
        + 'fi'

    function toggleHotspot() {
        if (actionProc.running) return

        if (root.enabled) {
            actionProc.args = ["nmcli", "connection", "down", "Hotspot"]
        } else {
            actionProc.args = ["bash", "-c", root._startScript, "_",
                root._dev,
                root.ssid !== "" ? root.ssid : "Hotspot",
                root.password.length >= 8 ? root.password : ""]
        }

        actionProc.running = true
    }

    function updateConfiguration(newSsid, newPassword, isSecured) {
        if (actionProc.running) return
        if (newSsid === undefined || newSsid === null || String(newSsid).length === 0) return

        actionProc.args = ["bash", "-c", root._configScript, "_",
            String(newSsid),
            (newPassword === undefined || newPassword === null) ? "" : String(newPassword),
            isSecured ? "1" : "0",
            root._dev]
        actionProc.running = true
    }

    function updateStatus() {
        if (activeProc.running) return
        activeProc.running = true
    }

    Process {
        id: devProc

        command: ["bash", "-c", "nmcli -t -f DEVICE,TYPE device | awk -F: '$2==\"wifi\"{print $1; exit}'"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            root._dev = devProc.stdout.text.trim()
            root.updateStatus()
        }
    }

    Process {
        id: activeProc

        command: ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const lines = activeProc.stdout.text.split("\n")
            let on = false
            let dev = root._dev

            for (let i = 0; i < lines.length; i++) {
                const parts = lines[i].split(":")
                if (parts.length < 2) continue
                if (parts[0].toLowerCase() === "hotspot") {
                    on = true
                    if (parts.length >= 3 && parts[2] !== "") dev = parts[2]
                    break
                }
            }

            root.enabled = on
            detailProc.running = true

            if (on && dev !== "") {
                clientProc.dev = dev
                clientProc.running = true
            } else {
                root.clientCount = 0
            }
        }
    }

    Process {
        id: detailProc

        command: ["nmcli", "-t", "-f", "802-11-wireless.ssid,802-11-wireless-security.psk,802-11-wireless-security.key-mgmt", "connection", "show", "Hotspot", "--show-secrets"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const lines = detailProc.stdout.text.split("\n")
            let sawKeyMgmt = false
            let isSecured = false

            for (let i = 0; i < lines.length; i++) {
                const idx = lines[i].indexOf(":")
                if (idx < 0) continue
                const key = lines[i].substring(0, idx)
                const val = lines[i].substring(idx + 1)
                if (key === "802-11-wireless.ssid") root.ssid = val
                else if (key === "802-11-wireless-security.psk") root.password = val
                else if (key === "802-11-wireless-security.key-mgmt") {
                    sawKeyMgmt = true
                    isSecured = val === "wpa-psk" || val === "sae"
                }
            }

            root.secured = sawKeyMgmt ? isSecured : true
        }
    }

    Process {
        id: clientProc

        property string dev: ""

        command: ["bash", "-c", "iw dev " + clientProc.dev + " station dump 2>/dev/null | grep -c '^Station' || true"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const n = parseInt(clientProc.stdout.text.trim(), 10)
            root.clientCount = isNaN(n) ? 0 : n
        }
    }

    Process {
        id: actionProc

        property var args: []

        command: actionProc.args

        onExited: root.updateStatus()
    }

    Component.onCompleted: devProc.running = true
}
