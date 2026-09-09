import QtQuick
import Quickshell.Bluetooth

// Native BlueZ binding (D-Bus). No bluetoothctl, no Process, no bash/awk, no
// polling timers. A thin adapter over Quickshell.Bluetooth that keeps the small
// API ControlCenter already consumes:
//   enabled / scanning / devices
//   togglePower() / requestScan() / stopScan()
//   connectDevice() / disconnectDevice() / pairDevice() / forgetDevice()
//   setTrusted() / deviceByAddress()
//
// `devices` holds the live BluetoothDevice objects themselves (address, name,
// icon, state, connected, paired, trusted, batteryAvailable, battery, each with
// its own *Changed signal), so rows update reactively with zero refresh logic.
Item {
    id: root

    // null until BlueZ enumeration completes (async), so every read is guarded.
    readonly property var adapter: Bluetooth.defaultAdapter

    readonly property bool available: root.adapter !== null
    readonly property bool enabled: root.adapter ? root.adapter.enabled : false
    readonly property bool scanning: root.adapter ? root.adapter.discovering : false

    // Re-evaluated only when the set of devices changes; per-device property
    // changes are picked up by the bindings in the delegates.
    readonly property var devices: {
        const src = Bluetooth.devices ? Bluetooth.devices.values : []
        const list = []
        for (let i = 0; i < src.length; i++)
            if (src[i] && src[i].address)
                list.push(src[i])
        list.sort(root._compare)
        return list
    }

    function _compare(a, b) {
        const ga = a.connected ? 0 : (a.paired ? 1 : 2)
        const gb = b.connected ? 0 : (b.paired ? 1 : 2)
        if (ga !== gb)
            return ga - gb
        const na = (a.name || a.address).toLowerCase()
        const nb = (b.name || b.address).toLowerCase()
        return na < nb ? -1 : (na > nb ? 1 : 0)
    }

    function deviceByAddress(address) {
        const src = Bluetooth.devices ? Bluetooth.devices.values : []
        for (let i = 0; i < src.length; i++)
            if (src[i] && src[i].address === address)
                return src[i]
        return null
    }

    // ---- adapter power / discovery ----
    function togglePower() {
        if (root.adapter)
            root.adapter.enabled = !root.adapter.enabled
    }

    function requestScan() {
        if (root.adapter && root.adapter.enabled)
            root.adapter.discovering = true
    }

    function stopScan() {
        if (root.adapter)
            root.adapter.discovering = false
    }

    // ---- device actions ----
    function connectDevice(address) {
        const d = root.deviceByAddress(address)
        if (d)
            d.connect()
    }

    function disconnectDevice(address) {
        const d = root.deviceByAddress(address)
        if (d)
            d.disconnect()
    }

    function pairDevice(address) {
        const d = root.deviceByAddress(address)
        if (d)
            d.pair()
    }

    function forgetDevice(address) {
        const d = root.deviceByAddress(address)
        if (d)
            d.forget()
    }

    function setTrusted(address, value) {
        const d = root.deviceByAddress(address)
        if (d)
            d.trusted = value
    }
}
