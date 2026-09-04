import QtQuick
import Quickshell.Io

Item {
    id: root

    property bool enabled: false
    property bool scanning: false
    property var devices: []

    property bool _refreshing: false

    function togglePower() {
        powerProc.mode = root.enabled ? "off" : "on"
        powerProc.running = true
    }

    function requestScan() {
        if (!root.enabled) return
        if (root.scanning) return
        root.scanning = true
        scanSafety.restart()
        scanProc.running = true
    }

    function refresh() {
        if (root._refreshing) return
        root._refreshing = true
        devicesProc.running = true
    }

    function connectDevice(address) {
        root._runAction(["bluetoothctl", "connect", String(address)])
    }

    function disconnectDevice(address) {
        root._runAction(["bluetoothctl", "disconnect", String(address)])
    }

    function pairDevice(address) {
        const a = String(address)
        root._runAction(["bash", "-c", "bluetoothctl pair " + a + " && bluetoothctl trust " + a])
    }

    function forgetDevice(address) {
        root._runAction(["bluetoothctl", "remove", String(address)])
    }

    function deviceByAddress(address) {
        for (let i = 0; i < root.devices.length; i++)
            if (root.devices[i].address === address) return root.devices[i]
        return null
    }

    function _runAction(args) {
        if (!args || args.length === 0) return
        if (actionProc.running) return
        actionProc.args = args
        actionProc.running = true
    }

    Process {
        id: powerCheck

        command: ["bluetoothctl", "show"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const m = powerCheck.stdout.text.match(/Powered:\s*(yes|no)/)
            root.enabled = m ? m[1] === "yes" : false
            if (root.enabled) root.refresh()
            else root.devices = []
        }
    }

    Process {
        id: powerProc

        property string mode: "on"

        command: ["bluetoothctl", "power", powerProc.mode]

        onExited: powerCheck.running = true
    }

    Process {
        id: scanProc

        command: ["bluetoothctl", "--timeout", "10", "scan", "on"]

        onExited: {
            root.scanning = false
            scanSafety.stop()
            root.refresh()
        }
    }

    Timer {
        id: scanSafety

        interval: 12000
        onTriggered: root.scanning = false
    }

    Process {
        id: devicesProc

        command: ["bash", "-c", "bluetoothctl devices | awk '{print $2}' | while read -r a; do bluetoothctl info \"$a\"; echo '===ENTRY==='; done"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            root._parse(devicesProc.stdout.text)
            root._refreshing = false
        }
    }

    Process {
        id: actionProc

        property var args: []

        command: actionProc.args

        onExited: root.refresh()
    }

    function _parse(text) {
        const blocks = String(text).split("===ENTRY===")
        const out = []

        for (let i = 0; i < blocks.length; i++) {
            const b = blocks[i]
            const am = b.match(/Device\s+([0-9A-Fa-f:]{17})/)
            if (!am) continue

            const nm = b.match(/Name:\s*([^\n\r]+)/)
            const cm = b.match(/Connected:\s*(yes|no)/)
            const pm = b.match(/Paired:\s*(yes|no)/)
            const im = b.match(/Icon:\s*([^\n\r]+)/)
            const rm = b.match(/RSSI:\s*(-?\d+)/)

            out.push({
                address: am[1],
                name: nm ? nm[1].trim() : am[1],
                connected: cm ? cm[1] === "yes" : false,
                paired: pm ? pm[1] === "yes" : false,
                icon: im ? im[1].trim() : "bluetooth",
                rssi: rm ? parseInt(rm[1], 10) : 0
            })
        }

        out.sort(root._compare)
        root.devices = out
    }

    function _compare(a, b) {
        const ga = a.connected ? 0 : (a.paired ? 1 : 2)
        const gb = b.connected ? 0 : (b.paired ? 1 : 2)
        if (ga !== gb) return ga - gb
        if (a.rssi !== b.rssi) return b.rssi - a.rssi
        const na = a.name.toLowerCase()
        const nb = b.name.toLowerCase()
        return na < nb ? -1 : na > nb ? 1 : 0
    }

    Component.onCompleted: powerCheck.running = true
}
