import QtQuick
import Quickshell.Io

Item {
    id: root

    property int volume: 0
    property bool muted: false
    property bool micMuted: false
    property var sinks: []

    property int _target: -1

    function setVolume(v) {
        root._target = Math.max(0, Math.min(100, Math.round(v)))
        root.volume = root._target
        applyTimer.restart()
    }

    function toggleMute() {
        if (muteProc.running) return
        muteProc.running = true
    }

    function toggleMicMute() {
        if (micMuteProc.running) return
        micMuteProc.running = true
    }

    function setDefaultSink(sinkId) {
        if (setDefaultProc.running) return
        if (sinkId === undefined || sinkId === null) return

        setDefaultProc.sinkId = sinkId
        setDefaultProc.running = true
    }

    function refresh() {
        if (!sinksProc.running) sinksProc.running = true
        if (!queryProc.running) queryProc.running = true
    }

    Timer {
        id: applyTimer

        interval: 45
        onTriggered: {
            if (root._target < 0 || setProc.running) return
            setProc.level = root._target / 100
            setProc.running = true
        }
    }

    Timer {
        id: pollTimer

        interval: 1500
        repeat: true
        running: true
        onTriggered: {
            if (!queryProc.running && root._target < 0) queryProc.running = true
            if (!micQueryProc.running) micQueryProc.running = true
            if (!sinksProc.running) sinksProc.running = true
        }
    }

    Process {
        id: setProc

        property real level: 0

        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", setProc.level.toFixed(2)]

        onExited: root._target = -1
    }

    Process {
        id: muteProc

        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]

        onExited: queryProc.running = true
    }

    Process {
        id: queryProc

        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const t = queryProc.stdout.text
            const m = t.match(/Volume:\s*([0-9.]+)/)
            if (m && root._target < 0) root.volume = Math.round(parseFloat(m[1]) * 100)
            root.muted = t.indexOf("MUTED") !== -1
        }
    }

    Process {
        id: micMuteProc

        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]

        onExited: micQueryProc.running = true
    }

    Process {
        id: micQueryProc

        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: root.micMuted = micQueryProc.stdout.text.indexOf("MUTED") !== -1
    }

    Process {
        id: sinksProc

        command: ["wpctl", "status"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const lines = sinksProc.stdout.text.split("\n")
            const out = []
            let inSinks = false

            for (let i = 0; i < lines.length; i++) {
                const line = lines[i]
                if (line.indexOf("Sinks:") !== -1) {
                    inSinks = true
                    continue
                }
                if (!inSinks) continue
                if (line.indexOf("Sources:") !== -1 || line.indexOf("Filters:") !== -1) break

                const m = line.match(/(\*)?\s*(\d+)\.\s+(.+?)\s+\[vol:\s*([0-9.]+)/)
                if (!m) continue
                out.push({
                    id: parseInt(m[2], 10),
                    name: m[3].trim(),
                    description: m[3].trim(),
                    isDefault: m[1] === "*",
                    volume: Math.round(parseFloat(m[4]) * 100)
                })
            }

            root.sinks = out
        }
    }

    Process {
        id: setDefaultProc

        property int sinkId: 0

        command: ["wpctl", "set-default", "" + setDefaultProc.sinkId]

        onExited: {
            queryProc.running = true
            sinksProc.running = true
        }
    }

    Component.onCompleted: {
        queryProc.running = true
        micQueryProc.running = true
        sinksProc.running = true
    }
}
