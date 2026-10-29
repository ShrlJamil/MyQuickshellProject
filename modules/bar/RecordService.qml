pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Screen recording for the Control Center's record tile. The tile
// (and the `record` IPC target) drives wf-recorder directly: fullscreen
// on the focused output, with the default audio device, saved as an MP4
// under ~/Videos/screencast/.
//
// The recorder is a direct child process on purpose: stopping sends it
// SIGINT, wf-recorder's "stop and finalize" signal, so the file stays a
// valid MP4 (terminating a shell wrapper instead would orphan the
// recorder and lose the file). One consequence of plain Process
// semantics: a Quickshell config reload kills the recorder mid-take.
Item {
    id: root

    readonly property string recordDir: Quickshell.env("HOME") + "/Videos/screencast"

    property bool recording: false
    property int elapsedSeconds: 0
    property string currentFile: ""

    // m:ss under an hour, h:mm:ss beyond it.
    readonly property string durationText: {
        const s = root.elapsedSeconds
        const pad = (n) => String(n).padStart(2, "0")
        const m = Math.floor(s / 60)
        if (m < 60)
            return m + ":" + pad(s % 60)
        return Math.floor(m / 60) + ":" + pad(m % 60) + ":" + pad(s % 60)
    }

    // Validated focused-output name for -o; "" lets wf-recorder pick.
    property string _output: ""
    property bool _stopping: false

    function toggle() {
        if (root.recording)
            root.stop()
        else
            root.start()
    }

    function start() {
        if (root.recording || recProc.running || mkdirProc.running)
            return
        const now = new Date()
        const pad = (n) => String(n).padStart(2, "0")
        const stamp = now.getFullYear() + pad(now.getMonth() + 1) + pad(now.getDate())
            + "_" + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds())
        root.currentFile = root.recordDir + "/Recording_" + stamp + ".mp4"
        root._stopping = false
        // Focused output snapshot, validated like CaptureService's screen
        // mode (output names are compositor-generated; the pattern is
        // defence-in-depth even though no shell string is built here).
        const fm = Hyprland.focusedMonitor
        const name = (fm && typeof fm.name === "string") ? fm.name : ""
        root._output = /^[A-Za-z0-9._-]+$/.test(name) ? name : ""
        mkdirProc.running = true
    }

    function stop() {
        if (!root.recording)
            return
        root._stopping = true
        recProc.signal(2) // SIGINT: stop + finalize
    }

    function _notify(title, body) {
        notifyProc.command = ["notify-send", "-a", "Screencast", "-t", "4000", title, body]
        notifyProc.running = true
    }

    function _fileName() {
        const parts = root.currentFile.split("/")
        return parts[parts.length - 1]
    }

    Process {
        id: mkdirProc

        command: ["mkdir", "-p", root.recordDir]

        onExited: (code) => {
            if (code !== 0) {
                root._notify("Screencast failed", "Could not create " + root.recordDir)
                return
            }
            const args = ["wf-recorder"]
            if (root._output !== "")
                args.push("-o", root._output)
            args.push("-a", "-f", root.currentFile)
            recProc.command = args
            recProc.running = true
        }
    }

    Process {
        id: recProc

        onStarted: {
            root.recording = true
            root.elapsedSeconds = 0
            root._notify("Screencast recording", root._fileName())
        }

        onExited: (code) => {
            const wasRecording = root.recording
            root.recording = false
            if (root._stopping) {
                root._stopping = false
                root._notify("Screencast saved", root._fileName() + " · " + root.durationText)
            } else if (wasRecording && code !== 0) {
                root._notify("Screencast failed", "wf-recorder exited with code " + code)
            }
        }
    }

    Process {
        id: notifyProc
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.elapsedSeconds++
    }
}
