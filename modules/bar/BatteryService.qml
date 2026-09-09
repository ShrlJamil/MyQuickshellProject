pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Battery data + Battery Popover open-state, for the bar's BatteryWidget.
//
// PRIMARY source: Quickshell.Services.UPower (native, reactive) - percentage,
// state, changeRate (W), energy / energyCapacity, timeToEmpty / timeToFull,
// iconName, healthPercentage where supported.
//
// EXTRA telemetry: Quickshell 0.3.1 has no generic D-Bus binding for QML, so the
// UPowerDevice wrapper does not expose Voltage / Temperature / ChargeCycles /
// EnergyFullDesign / Capacity. We read those straight off the UPower D-Bus
// object with `busctl get-property` (a one-shot D-Bus client call via
// Quickshell.Io.Process - NOT `upower -i` scraping, NOT sysfs, NOT a poll
// timer). The call is re-run only when the native UPower service signals a
// change (energy / state / rate / percentage / onBattery), so it tracks
// UPower's own push cadence.
Item {
    id: root

    // UPower's aggregate battery (a laptop's BAT0, or a composite of several).
    readonly property UPowerDevice device: UPower.displayDevice

    readonly property bool available: !!device && device.ready && device.isPresent

    // ---- Physical battery for per-cell telemetry (never the AC adapter) -------
    // Aggregate data stays on `device` (displayDevice); voltage/temperature/
    // cycles/design-capacity are physical and come from one real battery.
    readonly property var physBattery: {
        const list = UPower.devices ? UPower.devices.values : []
        for (let i = 0; i < list.length; i++) {
            const d = list[i]
            if (d && d.type === UPowerDeviceType.Battery && d.powerSupply)
                return d
        }
        return null
    }
    readonly property string dbusPath: (physBattery && physBattery.nativePath)
        ? "/org/freedesktop/UPower/devices/battery_" + physBattery.nativePath
        : ""

    // Quickshell's UPowerDevice.percentage / healthPercentage are 0..1 fractions.
    readonly property real percent: root.available ? device.percentage * 100 : 0
    readonly property int state: available ? device.state : UPowerDeviceState.Unknown

    readonly property bool charging: root.state === UPowerDeviceState.Charging
                                     || root.state === UPowerDeviceState.PendingCharge
    readonly property bool discharging: root.state === UPowerDeviceState.Discharging
                                        || root.state === UPowerDeviceState.PendingDischarge
    readonly property bool full: root.state === UPowerDeviceState.FullyCharged

    // AC connected. UPower.onBattery is true only while running from battery.
    readonly property bool pluggedIn: !UPower.onBattery

    // Low = actually draining and getting close to empty. Uses Theme.accent in
    // the widget (no new palette).
    readonly property bool low: root.available && root.discharging && root.percent <= 15

    // Freedesktop icon name straight from UPower - already reflects level +
    // charging state (battery-good-symbolic, battery-low-charging-symbolic, ...).
    readonly property string iconName: (root.available && device.iconName)
                                       ? device.iconName : "battery-symbolic"

    // changeRate is the power in/out in watts (UPower EnergyRate). Sign varies
    // between versions, so take the magnitude and derive direction from `state`.
    readonly property real powerWatts: root.available ? Math.abs(device.changeRate) : 0
    readonly property bool hasPower: root.powerWatts > 0.05

    readonly property real energyWh: root.available ? device.energy : 0
    readonly property bool hasEnergy: root.available && root.energyWh > 0

    // ---- Extra telemetry from the UPower D-Bus object (see header) -----------
    // Raw values written by dbusProc. NaN = not yet read / call failed.
    property real _voltage: NaN
    property real _temperature: NaN
    property real _chargeCycles: NaN
    property real _energyFull: NaN
    property real _energyFullDesign: NaN
    property real _capacity: NaN

    // Voltage (V) - reported directly by UPower, never calculated.
    readonly property real voltage: (!isNaN(root._voltage) && root._voltage > 0) ? root._voltage : NaN
    readonly property bool hasVoltage: !isNaN(root.voltage)

    // Battery temperature (deg C). UPower reports 0 when there is no sensor.
    readonly property real temperature: (!isNaN(root._temperature) && root._temperature > 0) ? root._temperature : NaN
    readonly property bool hasTemperature: !isNaN(root.temperature)

    // Charge cycle count. UPower reports -1 when unknown/not applicable.
    readonly property int chargeCycles: (!isNaN(root._chargeCycles) && root._chargeCycles >= 1)
                                        ? Math.round(root._chargeCycles) : -1
    readonly property bool hasChargeCycles: root.chargeCycles >= 1

    // Capacity (Wh). Full = last full-charge capacity; Design = when new.
    readonly property real energyFull: !isNaN(root._energyFull) && root._energyFull > 0
        ? root._energyFull
        : (root.available && device.energyCapacity > 0 ? device.energyCapacity : NaN)
    readonly property bool hasEnergyFull: !isNaN(root.energyFull)
    readonly property real energyFullDesign: (!isNaN(root._energyFullDesign) && root._energyFullDesign > 0)
                                             ? root._energyFullDesign : NaN
    readonly property bool hasEnergyFullDesign: !isNaN(root.energyFullDesign)

    // Health: prefer Quickshell's own healthPercentage; otherwise UPower's
    // D-Bus `Capacity` (last-full / design). NaN when neither is available.
    readonly property bool _nativeHealth: root.available && device.healthSupported
                                          && device.healthPercentage > 0
    readonly property real healthPercent: root._nativeHealth
        ? device.healthPercentage * 100
        : (!isNaN(root._capacity) && root._capacity > 0 ? root._capacity : NaN)
    readonly property bool hasHealth: !isNaN(root.healthPercent)

    // Estimated current = |power| / voltage. NOT a hardware current sensor -
    // UPower Device has no Current property. Labelled "Estimated current".
    readonly property real estimatedCurrentA: (root.hasPower && root.hasVoltage)
                                              ? (root.powerWatts / root.voltage) : NaN
    readonly property bool hasEstimatedCurrent: !isNaN(root.estimatedCurrentA)

    // Seconds. UPower reports whichever direction is relevant; 0 when unknown.
    readonly property real timeRemainingSec: root.charging ? (root.available ? device.timeToFull : 0)
                                                           : (root.available ? device.timeToEmpty : 0)
    readonly property bool hasTimeRemaining: root.timeRemainingSec > 0

    readonly property string statusText: {
        if (!root.available)
            return "No battery"
        if (root.charging)
            return "Charging"
        if (root.full)
            return "Fully charged"
        if (root.pluggedIn)
            return "Plugged in"
        return "On battery"
    }

    // Rows for the popover - only entries whose data is actually valid.
    // (never null / undefined / NaN / 0-means-unavailable / -1 sentinels)
    readonly property var popoverRows: {
        const rows = []

        if (root.hasPower)
            rows.push({
                label: root.charging ? "Charging power" : "Power draw",
                value: root.powerWatts.toFixed(1) + " W"
            })
        if (root.hasVoltage)
            rows.push({ label: "Voltage", value: root.voltage.toFixed(1) + " V" })
        if (root.hasEstimatedCurrent)
            rows.push({ label: "Estimated current", value: root.formatCurrent(root.estimatedCurrentA) })
        if (root.hasTemperature)
            rows.push({ label: "Temperature", value: Math.round(root.temperature) + " °C" })

        if (root.hasEnergy)
            rows.push({ label: "Energy", value: root.energyWh.toFixed(1) + " Wh" })
        if (root.hasEnergyFull)
            rows.push({ label: "Full capacity", value: root.energyFull.toFixed(1) + " Wh" })
        if (root.hasEnergyFullDesign)
            rows.push({ label: "Design capacity", value: root.energyFullDesign.toFixed(1) + " Wh" })

        if (root.hasHealth)
            rows.push({ label: "Health", value: Math.round(root.healthPercent) + "%" })
        if (root.hasChargeCycles)
            rows.push({ label: "Cycles", value: String(root.chargeCycles) })

        if (root.hasTimeRemaining)
            rows.push({
                label: root.charging ? "Time to full" : "Time remaining",
                value: root.formatDuration(root.timeRemainingSec)
            })
        return rows
    }

    function formatDuration(sec) {
        if (!sec || sec <= 0)
            return ""
        const mins = Math.round(sec / 60)
        const h = Math.floor(mins / 60)
        const m = mins % 60
        return h > 0 ? (h + "h " + m + "m") : (m + "m")
    }

    function formatCurrent(amps) {
        return amps >= 1 ? (amps.toFixed(2) + " A") : (Math.round(amps * 1000) + " mA")
    }

    // ---- UPower D-Bus telemetry fetch --------------------------------------
    // One `busctl get-property` call reads all six extra props at once. Fired on
    // startup and whenever the native UPower service reports a battery change -
    // no interval timer, no persistent subprocess.
    function _refetchTelemetry() {
        const path = root.dbusPath
        if (path === "" || dbusProc.running)
            return
        // Build the command at call time - a static binding can evaluate while
        // dbusPath is still "" (UPower.devices not populated yet) and fail.
        dbusProc.command = [
            "busctl", "--system", "--json=short", "get-property",
            "org.freedesktop.UPower", path, "org.freedesktop.UPower.Device",
            "Voltage", "Temperature", "ChargeCycles", "EnergyFull", "EnergyFullDesign", "Capacity"
        ]
        dbusProc.running = true
    }

    Process {
        id: dbusProc

        stdout: StdioCollector { id: dbusOut; waitForEnd: true }

        onExited: (code) => {
            if (code !== 0)
                return
            const lines = (dbusOut.text || "").trim().split("\n").filter(l => l.length > 0)
            if (lines.length < 6)
                return
            const num = (s) => {
                try {
                    const v = JSON.parse(s).data
                    return typeof v === "number" ? v : NaN
                } catch (e) {
                    return NaN
                }
            }
            root._voltage = num(lines[0])
            root._temperature = num(lines[1])
            root._chargeCycles = num(lines[2])
            root._energyFull = num(lines[3])
            root._energyFullDesign = num(lines[4])
            root._capacity = num(lines[5])
        }
    }

    onDbusPathChanged: root._refetchTelemetry()
    Component.onCompleted: root._refetchTelemetry()

    Connections {
        target: UPower.devices
        function onValuesChanged() { root._refetchTelemetry() }
    }

    Connections {
        target: UPower.displayDevice
        function onEnergyChanged() { root._refetchTelemetry() }
        function onStateChanged() { root._refetchTelemetry() }
        function onChangeRateChanged() { root._refetchTelemetry() }
        function onPercentageChanged() { root._refetchTelemetry() }
    }

    Connections {
        target: UPower
        function onOnBatteryChanged() { root._refetchTelemetry() }
    }

    // ---- Battery Popover open state (one per screen, mirrors NotificationService) ----
    property var popoverScreen: null

    function togglePopover(screen) {
        root.popoverScreen = (root.popoverScreen === screen) ? null : screen
    }

    function closePopover() {
        root.popoverScreen = null
    }
}
