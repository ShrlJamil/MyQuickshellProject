import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

Item {
    id: root

    property int volume: 0
    property bool muted: false
    property bool micMuted: false
    property var sinks: []

    property int _target: -1

    // Native PipeWire tracking (same pattern as OSDService): the backend is
    // the source of truth for volume/muted; wpctl is no longer used here.
    readonly property var sinkNode: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sinkNode ? [root.sinkNode] : [] }
    readonly property var sinkAudio: (root.sinkNode && root.sinkNode.audio) ? root.sinkNode.audio : null

    Connections {
        target: root.sinkAudio
        ignoreUnknownSignals: true
        function onVolumesChanged() {
            if (root.sinkAudio && root._target < 0)
                root.volume = Math.round(root.sinkAudio.volume * 100)
        }
        function onMutedChanged() {
            if (root.sinkAudio)
                root.muted = root.sinkAudio.muted
        }
    }

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
        if (!micQueryProc.running) micQueryProc.running = true
        if (!sinksProc.running) sinksProc.running = true
    }

    Timer {
        id: applyTimer

        interval: 45
        onTriggered: {
            if (root._target < 0)
                return
            // Native write (0..1 float); no process. Kept off when no sink so
            // a later setVolume retries instead of dropping the request.
            if (root.sinkAudio) {
                root.sinkAudio.volume = root._target / 100
                root._target = -1
            }
        }
    }

    Timer {
        id: pollTimer

        interval: 1500
        repeat: true
        running: true
        onTriggered: {
            if (!micQueryProc.running) micQueryProc.running = true
            if (!sinksProc.running) sinksProc.running = true
        }
    }

    Process {
        id: muteProc

        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
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
            sinksProc.running = true
        }
    }

    Component.onCompleted: {
        micQueryProc.running = true
        sinksProc.running = true
    }
}
