import QtQuick
import QtQml
import Quickshell.Networking
import Quickshell.Io

Item {
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

    // Active SSID from NetworkManager via nmcli
    property string _activeSSID: ""
    
    Process {
        id: ssidProcess
        property string ifname: ""
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi", "list", "ifname", ssidProcess.ifname]
        stdout: StdioCollector { waitForEnd: true }
        onExited: {
            const output = stdout.text
            const lines = output.split("\n")
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].startsWith("yes:")) {
                    const ssid = lines[i].substring(4)
                    if (ssid !== root._activeSSID) {
                        root._activeSSID = ssid
                    }
                    break
                }
            }
        }
    }
    
    Process {
        id: connectProcess

        property string ssid: ""
        property string pass: ""
        property string ifname: ""

        command: connectProcess.ifname !== ""
            ? ["nmcli", "device", "wifi", "connect", connectProcess.ssid, "password", connectProcess.pass, "ifname", connectProcess.ifname]
            : ["nmcli", "device", "wifi", "connect", connectProcess.ssid, "password", connectProcess.pass]

        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            root.pendingNetwork = ""
            if (exitCode === 0) {
                root.failedNetwork = ""
                root.connectError = ""
                root._refreshActiveSSID()
            } else {
                const err = connectProcess.stderr.text.toLowerCase()
                root.failedNetwork = connectProcess.ssid
                root.connectError = (err.indexOf("secret") !== -1 || err.indexOf("password") !== -1 || err.indexOf("802-11-wireless-security") !== -1)
                    ? "Incorrect password"
                    : "Connection failed"
            }
            root.rebuildView()
        }
    }

    Process {
        id: hiddenProcess

        property string ssid: ""
        property string pass: ""
        property string user: ""
        property string securityType: "personal"
        property string ifname: ""

        command: {
            if (hiddenProcess.securityType === "enterprise") {
                let eargs = ["nmcli", "connection", "add", "type", "wifi", "con-name", hiddenProcess.ssid]
                if (hiddenProcess.ifname !== "") {
                    eargs.push("ifname")
                    eargs.push(hiddenProcess.ifname)
                }
                return eargs.concat([
                    "ssid", hiddenProcess.ssid,
                    "wifi-sec.key-mgmt", "wpa-eap",
                    "802-1x.eap", "peap",
                    "802-1x.phase2-auth", "mschapv2",
                    "802-1x.identity", hiddenProcess.user,
                    "802-1x.password", hiddenProcess.pass,
                    "802-11-wireless.hidden", "yes"
                ])
            }

            const args = ["nmcli", "device", "wifi", "connect", hiddenProcess.ssid]
            if (hiddenProcess.securityType === "personal") {
                args.push("password")
                args.push(hiddenProcess.pass)
            }
            args.push("hidden")
            args.push("yes")
            if (hiddenProcess.ifname !== "") {
                args.push("ifname")
                args.push(hiddenProcess.ifname)
            }
            return args
        }

        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            if (hiddenProcess.securityType === "enterprise" && exitCode === 0) {
                hiddenUpProcess.ssid = hiddenProcess.ssid
                hiddenUpProcess.running = true
                return
            }
            root.pendingNetwork = ""
            if (exitCode === 0) {
                root.failedNetwork = ""
                root.connectError = ""
                root._refreshActiveSSID()
            } else {
                const err = hiddenProcess.stderr.text.toLowerCase()
                root.failedNetwork = hiddenProcess.ssid
                root.connectError = (err.indexOf("secret") !== -1 || err.indexOf("password") !== -1 || err.indexOf("802-11-wireless-security") !== -1)
                    ? "Incorrect password"
                    : "Connection failed"
            }
            root.rebuildView()
        }
    }

    Process {
        id: hiddenUpProcess

        property string ssid: ""

        command: ["nmcli", "connection", "up", hiddenUpProcess.ssid]

        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            root.pendingNetwork = ""
            if (exitCode === 0) {
                root.failedNetwork = ""
                root.connectError = ""
                root._refreshActiveSSID()
            } else {
                const err = hiddenUpProcess.stderr.text.toLowerCase()
                root.failedNetwork = hiddenUpProcess.ssid
                root.connectError = (err.indexOf("secret") !== -1 || err.indexOf("identity") !== -1 || err.indexOf("802-1x") !== -1 || err.indexOf("password") !== -1)
                    ? "Authentication failed"
                    : "Connection failed"
            }
            root.rebuildView()
        }
    }

    Process {
        id: rescanProcess

        property string ifname: ""

        command: rescanProcess.ifname !== ""
            ? ["nmcli", "device", "wifi", "rescan", "ifname", rescanProcess.ifname]
            : ["nmcli", "device", "wifi", "rescan"]

        onExited: (exitCode, exitStatus) => {
            root.scanning = false
            scanSafetyTimer.stop()
            root.rebuildView()
        }
    }

    Process {
        id: disconnectProcess

        property string ifname: ""

        command: ["nmcli", "device", "disconnect", disconnectProcess.ifname]

        onExited: (exitCode, exitStatus) => {
            root._refreshActiveSSID()
            root.rebuildView()
        }
    }

    Timer {
        id: scanSafetyTimer

        interval: 5000
        onTriggered: root.scanning = false
    }

    Instantiator {
        id: netWatchers

        model: root.networks

        delegate: Connections {
            id: netConn

            required property var modelData

            target: netConn.modelData
            ignoreUnknownSignals: true

            function onStateChangingChanged() { root.rebuildView() }
            function onConnectedChanged() { root.rebuildView() }
            function onKnownChanged() { root.rebuildView() }
            function onConnectionFailed(reason) {
                root.failedNetwork = netConn.modelData.name
                if (root.connectError === "") root.connectError = "Connection failed"
                root.rebuildView()
                console.log("wifi connect failed for '" + netConn.modelData.name + "' reason=" + reason)
            }
        }
    }

    function _refreshActiveSSID() {
        if (!root.enabled || !root.activeDevice || !root.activeDevice.connected) {
            if (root._activeSSID !== "") root._activeSSID = ""
            return
        }
        
        ssidProcess.ifname = root.activeDevice.name
        ssidProcess.running = true
    }

    onActiveDeviceChanged: {
        if (root.activeDevice) {
            root.activeDevice.scannerEnabled = true
        }
        root._refreshActiveSSID()
    }
    
    onEnabledChanged: {
        root._refreshActiveSSID()
        root.rebuildView()
    }

    Component.onCompleted: {
        if (root.activeDevice) {
            root.activeDevice.scannerEnabled = true
        }
        root._refreshActiveSSID()
        root.rebuildView()
    }

    // Use device-level connected state as source of truth
    readonly property bool connected: root.activeDevice !== null && root.activeDevice.connected
    readonly property string connectionName: root.connected ? root._activeSSID : ""
    readonly property bool connecting: root.activeDevice !== null && root.activeDevice.state === ConnectionState.Connecting

    readonly property var networks: root.activeDevice !== null ? root.activeDevice.networks.values : []

    property var viewNetworks: []
    property string failedNetwork: ""
    property string connectError: ""
    property string pendingNetwork: ""
    property bool scanning: false

    onNetworksChanged: {
        root.rebuildView()
        if (root.scanning) {
            root.scanning = false
            scanSafetyTimer.stop()
        }
    }
    onConnectedChanged: {
        root._refreshActiveSSID()
        root.rebuildView()
    }
    onConnectionNameChanged: root.rebuildView()

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

    function connectNetwork(name, password) {
        if (!root.enabled) return
        const net = root.networkByName(name)
        if (net === null) return
        if (net.connected) return

        root.failedNetwork = ""
        root.connectError = ""

        if (net.known || net.security === WifiSecurityType.Open) {
            try {
                net.connect()
            } catch (e) {}

            root.rebuildView()
            return
        }

        if (password === undefined || password === null || String(password).length === 0) {
            root.failedNetwork = name
            root.connectError = "Password required"
            root.rebuildView()
            return
        }

        if (connectProcess.running) return

        root.pendingNetwork = name
        connectProcess.ssid = name
        connectProcess.pass = String(password)
        connectProcess.ifname = (root.activeDevice && root.activeDevice.name) ? root.activeDevice.name : ""
        connectProcess.running = true
        root.rebuildView()
    }

    function connectHiddenNetwork(ssid, password, securityType, username) {
        if (!root.enabled) return
        if (ssid === undefined || ssid === null || String(ssid).length === 0) return
        if (hiddenProcess.running || hiddenUpProcess.running) return

        root.failedNetwork = ""
        root.connectError = ""

        const name = String(ssid)
        const type = (securityType === "open" || securityType === "enterprise") ? securityType : "personal"
        const pass = (password === undefined || password === null) ? "" : String(password)
        const user = (username === undefined || username === null) ? "" : String(username)

        if (type === "personal" && pass.length === 0) {
            root.failedNetwork = name
            root.connectError = "Password required"
            root.rebuildView()
            return
        }

        if (type === "enterprise" && (user.length === 0 || pass.length === 0)) {
            root.failedNetwork = name
            root.connectError = user.length === 0 ? "Username required" : "Password required"
            root.rebuildView()
            return
        }

        root.pendingNetwork = name
        hiddenProcess.ssid = name
        hiddenProcess.pass = type === "open" ? "" : pass
        hiddenProcess.user = user
        hiddenProcess.securityType = type
        hiddenProcess.ifname = (root.activeDevice && root.activeDevice.name) ? root.activeDevice.name : ""
        hiddenProcess.running = true
        root.rebuildView()
    }

    function forgetNetwork(name) {
        if (!root.enabled) return
        const net = root.networkByName(name)
        if (net === null) return
        if (!net.known) return

        root.failedNetwork = ""
        root.connectError = ""

        try {
            net.forget()
        } catch (e) {}

        root.rebuildView()
    }

    function clearError() {
        root.failedNetwork = ""
        root.connectError = ""
    }

    function requestScan() {
        if (!root.enabled) return
        if (root.scanning) return

        root.scanning = true
        scanSafetyTimer.restart()

        if (root.activeDevice) {
            try { root.activeDevice.scannerEnabled = true } catch (e) {}
            try {
                if (typeof root.activeDevice.requestScan === "function") {
                    root.activeDevice.requestScan()
                    return
                }
            } catch (e) {}
        }

        if (rescanProcess.running) return
        rescanProcess.ifname = (root.activeDevice && root.activeDevice.name) ? root.activeDevice.name : ""
        rescanProcess.running = true
    }

    function disconnectCurrentNetwork() {
        if (!root.activeDevice) return

        const values = root.networks
        for (let i = 0; i < values.length; i++) {
            const net = values[i]
            if (net !== null && net.connected && typeof net.disconnect === "function") {
                try {
                    net.disconnect()
                } catch (e) {}
                root.rebuildView()
                return
            }
        }

        if (disconnectProcess.running) return
        disconnectProcess.ifname = root.activeDevice.name ? root.activeDevice.name : ""
        if (disconnectProcess.ifname === "") return
        disconnectProcess.running = true
    }

    function rebuildView() {
        const raw = root.networks
        const out = []

        for (let i = 0; i < raw.length; i++) {
            const net = raw[i]
            if (net === null) continue

            const percent = Math.round(net.signalStrength * 100)

            out.push({
                name: net.name,
                signal: percent,
                level: root.signalLevel(percent),
                connected: root.connected && net.name === root._activeSSID,
                known: net.known,
                secured: net.security !== WifiSecurityType.Open,
                connecting: net.stateChanging || net.name === root.pendingNetwork,
                failed: net.name === root.failedNetwork
            })
        }

        out.sort(root.compareNetworks)
        root.viewNetworks = out
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