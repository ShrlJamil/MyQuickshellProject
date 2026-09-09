pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// System summary for the bar's Arch logo popover (fastfetch-style). Cheap
// one-shot reads - /proc/uptime, /proc/meminfo, `uname -rm` - refreshed once a
// minute and on demand when the popover opens. Same Process + StdioCollector
// pattern as BrightnessService; no persistent device poll.
Item {
    id: root

    // Whole seconds since boot (first field of /proc/uptime).
    property real seconds: 0
    // `uname -r` / `uname -m`.
    property string kernel: ""
    property string arch: ""
    // "5.2 GiB / 15.3 GiB" (used / total).
    property string memory: ""

    readonly property string os: "Arch Linux" + (root.arch.length ? " " + root.arch : "")

    // "3 hours, 15 mins" / "2 days, 4 hours" / "less than a minute".
    readonly property string pretty: {
        const total = Math.floor(root.seconds)
        if (total <= 0)
            return "less than a minute"
        const d = Math.floor(total / 86400)
        const h = Math.floor((total % 86400) / 3600)
        const m = Math.floor((total % 3600) / 60)
        let parts = []
        if (d > 0)
            parts.push(d + (d === 1 ? " day" : " days"))
        if (h > 0)
            parts.push(h + (h === 1 ? " hour" : " hours"))
        // Minutes only matter below the day scale.
        if (m > 0 && d === 0)
            parts.push(m + (m === 1 ? " min" : " mins"))
        if (parts.length === 0)
            return "less than a minute"
        return parts.join(", ")
    }

    function refresh() {
        if (!uptimeProc.running)
            uptimeProc.running = true
        if (!unameProc.running)
            unameProc.running = true
        if (!memProc.running)
            memProc.running = true
    }

    Process {
        id: uptimeProc

        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const first = parseFloat(uptimeProc.stdout.text.trim().split(/\s+/)[0])
            if (!isNaN(first))
                root.seconds = first
        }
    }

    Process {
        id: unameProc

        command: ["uname", "-rm"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const parts = unameProc.stdout.text.trim().split(/\s+/)
            if (parts[0])
                root.kernel = parts[0]
            if (parts[1])
                root.arch = parts[1]
        }
    }

    Process {
        id: memProc

        command: ["cat", "/proc/meminfo"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const lines = memProc.stdout.text.split("\n")
            let totalKb = 0
            let availKb = 0
            let freeKb = 0
            for (let i = 0; i < lines.length; i++) {
                const l = lines[i]
                if (l.indexOf("MemTotal:") === 0)
                    totalKb = parseInt(l.replace(/[^0-9]/g, ""), 10)
                else if (l.indexOf("MemAvailable:") === 0)
                    availKb = parseInt(l.replace(/[^0-9]/g, ""), 10)
                else if (l.indexOf("MemFree:") === 0)
                    freeKb = parseInt(l.replace(/[^0-9]/g, ""), 10)
            }
            // MemAvailable is the honest "free" figure; fall back to MemFree on
            // ancient kernels that don't export it.
            const unusedKb = availKb > 0 ? availKb : freeKb
            if (totalKb > 0) {
                const usedKb = Math.max(0, totalKb - unusedKb)
                const gib = (kb) => (kb / 1048576).toFixed(1)
                root.memory = gib(usedKb) + " / " + gib(totalKb) + " GiB"
            }
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Populate os / kernel / memory / uptime immediately at shell start, so the
    // popover never opens onto blank values.
    Component.onCompleted: root.refresh()
}
