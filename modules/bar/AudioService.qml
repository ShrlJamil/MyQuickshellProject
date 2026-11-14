import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

Item {
    id: root

    property bool micMuted: false
    property var sinks: []

    property int _target: -1

    // Native PipeWire tracking (same pattern as OSDService): the backend is
    // the source of truth for volume/muted; wpctl is no longer used here.
    readonly property var sinkNode: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sinkNode ? [root.sinkNode] : [] }
    readonly property var sinkAudio: (root.sinkNode && root.sinkNode.audio) ? root.sinkNode.audio : null

    // Live bindings, NOT signal-fed copies: these read the backend
    // directly, so they are correct the moment this service is created -
    // including right after a config reload, where the C++ PipeWire
    // registry kept its values and no volumesChanged signal ever fires
    // to prime a copy (the old copy sat at 0 until the next real change,
    // and the volume keys then stepped from that stale 0 and wrote it
    // to the real sink). While a local write is in flight (_target >= 0)
    // the requested value is shown until the backend acknowledges it.
    readonly property int volume: root._target >= 0 ? root._target
        : (root.sinkAudio ? Math.round(root.sinkAudio.volume * 100) : 0)
    readonly property bool muted: root.sinkAudio ? root.sinkAudio.muted : false

    Connections {
        target: root.sinkAudio
        ignoreUnknownSignals: true
        function onVolumesChanged() {
            // A write is acknowledged once the backend lands on the
            // requested value, within the device's own volume step.
            if (root._target >= 0 && root.sinkAudio
                    && Math.abs(Math.round(root.sinkAudio.volume * 100) - root._target) <= 1) {
                root._target = -1
                ackTimer.stop()
            }
        }
    }

    function setVolume(v) {
        root._target = Math.max(0, Math.min(100, Math.round(v)))
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
            // _target stays set until the backend acknowledges the value
            // (see the Connections above); ackTimer is the fallback if an
            // exact acknowledgement never arrives.
            if (root.sinkAudio) {
                root.sinkAudio.volume = root._target / 100
                ackTimer.restart()
            }
        }
    }

    Timer {
        id: ackTimer

        interval: 800
        onTriggered: root._target = -1
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
