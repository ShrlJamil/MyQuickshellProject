import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

// Power profile switcher: bound directly to the native D-Bus
// power-profiles API through Quickshell's PowerProfiles singleton.
// On this machine the interface (net.hadess.PowerProfiles, also
// reachable as org.freedesktop.UPower.PowerProfiles) is owned by
// tlp-pd; its ActiveProfile property is readable, writable and emits
// change notifications, so this service spawns NO polling processes
// and runs NO timers - the previous build polled `tlpctl get` every
// 2 s and set profiles through `tlpctl set`.
// The platform defines exactly three profiles: performance, balanced,
// power-saver. Charger plug/unplug auto-switching stays TLP's own
// configuration (TLP_AUTO_SWITCH et al. in /etc/tlp.conf); this
// service only mirrors the current profile and sets it on request.
// `available` comes from a one-shot bus probe at startup, repeated
// whenever refresh() is called (the panel calls it when it opens):
// if no daemon owns the bus name, the panel can say so instead of
// lying.
Item {
    id: root

    // D-Bus enum mirrored into the string API the panel consumes.
    property string profile: root._name(PowerProfiles.profile)
    property bool available: false

    readonly property var profiles: [
        { "id": "performance", "name": "Performance", "icon": "power-profile-performance-symbolic", "iconAlt": "power-profile-performance" },
        { "id": "balanced", "name": "Balanced", "icon": "power-profile-balanced-symbolic", "iconAlt": "power-profile-balanced" },
        { "id": "power-saver", "name": "Power Saver", "icon": "power-profile-power-saver-symbolic", "iconAlt": "power-profile-power-saver" }
    ]

    function _name(e) {
        if (e === PowerProfile.Performance)
            return "performance"
        if (e === PowerProfile.Balanced)
            return "balanced"
        return "power-saver"
    }

    function refresh() {
        if (!probeProc.running)
            probeProc.running = true
    }

    function setProfile(id) {
        if (id === root.profile)
            return
        PowerProfiles.profile = id === "performance" ? PowerProfile.Performance
            : id === "balanced" ? PowerProfile.Balanced
            : PowerProfile.PowerSaver
    }

    Process {
        id: probeProc

        command: ["busctl", "--system", "--no-pager", "status", "net.hadess.PowerProfiles"]

        onExited: (exitCode) => {
            root.available = exitCode === 0
        }
    }

    Component.onCompleted: root.refresh()
}
