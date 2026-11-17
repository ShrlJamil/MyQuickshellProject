import QtQuick
import Quickshell.Io

// Power profile switcher: reads and sets the active power profile
// through tlpctl, the client of the TLP profile daemon (tlp-pd), which
// exposes the standard D-Bus power-profiles API — switching needs no
// root. The platform defines exactly three profiles: performance,
// balanced, power-saver. Charger plug/unplug auto-switching is TLP's
// own configuration (TLP_AUTO_SWITCH et al. in /etc/tlp.conf); this
// service only mirrors the current profile and sets it on request.
// On a machine without a profile daemon, tlpctl never answers and
// `available` stays false, so the panel can say so instead of lying.
Item {
    id: root

    property string profile: ""
    property bool available: false

    readonly property var profiles: [
        { "id": "performance", "name": "Performance", "icon": "power-profile-performance-symbolic", "iconAlt": "power-profile-performance" },
        { "id": "balanced", "name": "Balanced", "icon": "power-profile-balanced-symbolic", "iconAlt": "power-profile-balanced" },
        { "id": "power-saver", "name": "Power Saver", "icon": "power-profile-power-saver-symbolic", "iconAlt": "power-profile-power-saver" }
    ]

    function refresh() {
        if (!checkProc.running) checkProc.running = true
    }

    function setProfile(id) {
        if (setProc.running || id === root.profile) return
        setProc.command = ["tlpctl", "set", id]
        setProc.running = true
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: root.refresh()
    }

    Process {
        id: checkProc

        command: ["tlpctl", "get"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const value = checkProc.stdout.text.trim()
            if (value === "performance" || value === "balanced" || value === "power-saver") {
                root.profile = value
                root.available = true
            }
        }
    }

    Process {
        id: setProc

        command: ["true"]

        onExited: root.refresh()
    }
}
