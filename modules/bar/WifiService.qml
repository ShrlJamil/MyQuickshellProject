import QtQml
import Quickshell.Networking

QtObject {
    id: root

    readonly property bool enabled: Networking.wifiEnabled
    readonly property bool hardwareEnabled: Networking.wifiHardwareEnabled

    readonly property var activeDevice: {
        const values = Networking.devices.values
        let current = null
        let fallback = null

        for (let i = 0; i < values.length; i++) {
            const device = values[i]
            if (device.type !== DeviceType.Wifi) continue
            if (device.connected) {
                current = device
                break
            }
            if (fallback === null) fallback = device
        }

        return current !== null ? current : fallback
    }

    readonly property var activeNetwork: {
        const device = root.activeDevice
        if (device === null) return null

        const values = device.networks.values
        for (let i = 0; i < values.length; i++) {
            const network = values[i]
            if (network.connected) return network
        }

        return null
    }

    readonly property bool connected: root.activeNetwork !== null
    readonly property string connectionName: root.activeNetwork !== null ? root.activeNetwork.name : ""
    readonly property bool connecting: root.activeDevice !== null && root.activeDevice.state === ConnectionState.Connecting

    readonly property var networks: root.activeDevice !== null ? root.activeDevice.networks.values : []

    property var viewNetworks: []
    property string failedNetwork: ""

    onNetworksChanged: root.rebuildView()
    onEnabledChanged: root.rebuildView()
    onConnectedChanged: root.rebuildView()
    onConnectionNameChanged: root.rebuildView()

    Component.onCompleted: root.rebuildView()

    function toggle() {
        Networking.wifiEnabled = !root.enabled
    }

    function networkByName(name) {
        const values = root.networks
        for (let i = 0; i < values.length; i++) {
            const net = values[i]
            if (net !== null && net.name === name) return net
        }
        return null
    }

    function connectNetwork(name) {
        if (!root.enabled) return
        const net = root.networkByName(name)
        if (net === null) return
        if (net.connected) return
        if (!net.known && net.security !== WifiSecurityType.Open) return

        try {
            net.connect()
        } catch (e) {}

        root.ensureFailureSignal(net, name)
        root.rebuildView()
    }

    function forgetNetwork(name) {
        if (!root.enabled) return
        const net = root.networkByName(name)
        if (net === null) return
        if (!net.known) return

        try {
            net.forget()
        } catch (e) {}

        root.rebuildView()
    }

    function ensureFailureSignal(net, name) {
        if (net.__failedHandler !== undefined) {
            net.connectionFailed.disconnect(net.__failedHandler)
        }

        const handler = function(reason) {
            root.failedNetwork = name
            root.rebuildView()
            console.log("wifi connect failed for '" + name + "' reason=" + reason)
        }

        net.__failedHandler = handler
        net.connectionFailed.connect(handler)
    }

    function ensureReactive(net) {
        if (net === null || net === undefined) return
        if (net.__refresh !== undefined) return

        const refresh = function() { root.rebuildView() }

        net.__refresh = refresh
        net.stateChangingChanged.connect(refresh)
        net.connectedChanged.connect(refresh)
        net.knownChanged.connect(refresh)
    }

    function rebuildView() {
        const raw = root.networks
        const out = []

        for (let i = 0; i < raw.length; i++) {
            const net = raw[i]
            if (net === null) continue

            root.ensureReactive(net)

            const percent = Math.round(net.signalStrength * 100)

            out.push({
                name: net.name,
                signal: percent,
                level: root.signalLevel(percent),
                connected: net.connected,
                known: net.known,
                secured: net.security !== WifiSecurityType.Open,
                connecting: net.stateChanging,
                failed: net.name === root.failedNetwork
            })
        }

        out.sort(root.compareNetworks)
        root.viewNetworks = out
        root.failedNetwork = ""
    }

    function signalLevel(strength) {
        if (strength >= 75) return 4
        if (strength >= 50) return 3
        if (strength >= 25) return 2
        if (strength > 0) return 1
        return 0
    }

    function compareNetworks(a, b) {
        const groupA = a.connected ? 0 : (a.known ? 1 : 2)
        const groupB = b.connected ? 0 : (b.known ? 1 : 2)
        if (groupA !== groupB) return groupA - groupB
        if (a.signal !== b.signal) return b.signal - a.signal
        const na = a.name.toLowerCase()
        const nb = b.name.toLowerCase()
        if (na < nb) return -1
        if (na > nb) return 1
        return 0
    }
}
