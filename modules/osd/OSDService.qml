pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Single source of truth for the standalone bottom-centre OSD.
//
// Drives three modes here: "volume", "brightness", "caps". The workspace OSD is
// inherently per-monitor and lives in OSD.qml (it reuses the same Hyprland
// workspace model the bar already tracks - no duplicated IPC).
//
// Cost model:
//  - Volume  : 100% native Quickshell.Services.Pipewire. PwNodeAudio.volume /
//              .muted are reactive; zero polling.
//  - Brightness / Caps Lock : Quickshell 0.3.1 exposes NO native backlight or
//              caps-lock state, and sysfs attribute writes do not raise inotify
//              events (FileView.watchChanges never fires for them). One shared
//              1 Hz reload of two tiny sysfs files is the lightest reliable
//              mechanism - it is the OSD system's entire idle cost.
Item {
    id: root

    // "" | "volume" | "brightness" | "caps"
    property string mode: ""
    readonly property bool active: root.mode !== ""

    property int _hideMs: 1600
    function _show(m, ms) {
        root._hideMs = ms
        root.mode = m
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: root._hideMs
        onTriggered: root.mode = ""
    }

    // ===================== VOLUME - native Pipewire (reactive) =====================
    readonly property var sinkNode: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sinkNode ? [root.sinkNode] : [] }
    readonly property var sinkAudio: (root.sinkNode && root.sinkNode.audio) ? root.sinkNode.audio : null

    readonly property int volumePercent: root.sinkAudio ? Math.round(root.sinkAudio.volume * 100) : 0
    readonly property bool volumeMuted: root.sinkAudio ? root.sinkAudio.muted : false

    property bool _volPrimed: false
    property int _volLast: -1
    property bool _mutedLast: false

    function _onVol() {
        if (!root.sinkAudio)
            return
        const p = root.volumePercent
        const m = root.volumeMuted
        if (!root._volPrimed) {
            root._volPrimed = true
            root._volLast = p
            root._mutedLast = m
            return
        }
        if (p === root._volLast && m === root._mutedLast)
            return
        root._volLast = p
        root._mutedLast = m
        root._show("volume", 1500)
    }

    Connections {
        target: root.sinkAudio
        ignoreUnknownSignals: true
        function onVolumesChanged() { root._onVol() }
        function onMutedChanged() { root._onVol() }
    }

    // Default-sink swap: re-prime so the new device's level does not pop an OSD.
    onSinkAudioChanged: root._volPrimed = false

    // ================= BRIGHTNESS + CAPS LOCK - sysfs, one 1 Hz poll =================
    property string _blDir: ""
    property string _capsPath: ""
    property int _blMax: 0
    property int _blRaw: -1
    property bool _blPrimed: false
    property bool capsOn: false
    property bool _capsPrimed: false

    readonly property int brightnessPercent: (root._blMax > 0 && root._blRaw >= 0)
        ? Math.max(1, Math.min(100, Math.round(root._blRaw * 100 / root._blMax)))
        : 0

    // Brightness key -> optimistic UI, then apply. Called from the "brightness"
    // IpcHandler (Hyprland's XF86MonBrightness* keys route here). The OSD shows
    // and the bar/icon jump on this frame; `brightnessctl` runs detached and a
    // short-delay sysfs re-read reconciles the exact value.
    readonly property int _blStepPercent: 10
    function brightnessStep(dir) {
        const d = dir >= 0 ? 1 : -1
        const arg = root._blStepPercent + (d > 0 ? "%+" : "%-")

        if (root._blMax > 0 && root._blRaw >= 0) {
            const step = Math.max(1, Math.round(root._blMax * root._blStepPercent / 100))
            const minRaw = Math.max(1, Math.round(root._blMax * 0.05))
            root._blRaw = Math.max(minRaw, Math.min(root._blMax, root._blRaw + d * step))
            root._blPrimed = true
            root._show("brightness", 1500)
        }

        Quickshell.execDetached(d > 0
            ? ["brightnessctl", "set", arg]
            : ["brightnessctl", "set", arg, "--min-value=5"])

        blReconcile.restart()
    }

    // Pull the true hardware value a beat after the last keypress so any drift
    // from rapid relative steps is corrected.
    Timer {
        id: blReconcile
        interval: 200
        onTriggered: if (root._blDir !== "") blFile.reload()
    }

    // One-shot device discovery (no hardcoded paths, no ongoing process).
    Process {
        id: pathProbe
        command: ["sh", "-c",
            "for d in /sys/class/backlight/*/; do [ -e \"$d/actual_brightness\" ] && printf 'BL %s\\n' \"$d\" && break; done; "
            + "for f in /sys/class/leds/*::capslock/brightness; do [ -e \"$f\" ] && printf 'CAPS %s\\n' \"$f\" && break; done"]
        stdout: StdioCollector { id: pathOut; waitForEnd: true }
        onExited: {
            const lines = (pathOut.text || "").trim().split("\n")
            for (let i = 0; i < lines.length; i++) {
                const ln = lines[i]
                if (ln.indexOf("BL ") === 0)
                    root._blDir = ln.slice(3).trim()
                else if (ln.indexOf("CAPS ") === 0)
                    root._capsPath = ln.slice(5).trim()
            }
            if (root._blDir !== "") {
                blMaxFile.reload()
                blFile.reload()
            }
            if (root._capsPath !== "")
                capsFile.reload()
        }
    }

    Component.onCompleted: pathProbe.running = true

    Timer {
        id: sysfsPoll
        interval: 1000
        repeat: true
        running: root._blDir !== "" || root._capsPath !== ""
        onTriggered: {
            if (root._blDir !== "")
                blFile.reload()
            if (root._capsPath !== "")
                capsFile.reload()
        }
    }

    FileView {
        id: blMaxFile
        path: root._blDir !== "" ? root._blDir + "max_brightness" : ""
        printErrors: false
        onLoaded: root._blMax = parseInt(blMaxFile.text().trim(), 10) || 0
    }

    FileView {
        id: blFile
        path: root._blDir !== "" ? root._blDir + "actual_brightness" : ""
        printErrors: false
        onLoaded: {
            const v = parseInt(blFile.text().trim(), 10)
            if (isNaN(v) || v === root._blRaw)
                return
            root._blRaw = v
            if (!root._blPrimed) {
                root._blPrimed = true
                return
            }
            root._show("brightness", 1500)
        }
    }

    FileView {
        id: capsFile
        path: root._capsPath
        printErrors: false
        onLoaded: {
            const on = parseInt(capsFile.text().trim(), 10) === 1
            if (root._capsPrimed && on === root.capsOn)
                return
            root.capsOn = on
            if (!root._capsPrimed) {
                root._capsPrimed = true
                return
            }
            root._show("caps", 1400)
        }
    }

    // Event-driven Caps Lock: one persistent python-evdev watcher over every
    // *-event-kbd node prints a single `toggle` line per physical press.
    // Exactly one instance (constant running, never restarted) - if it dies,
    // the 1 Hz sysfs poll above keeps working as the fallback.
    Process {
        id: capsWatch
        command: ["python3", Quickshell.shellPath("scripts/caps-watch.py")]
        running: true
        stdout: SplitParser {
            onRead: (line) => root._onCapsToggle(line)
        }
    }

    function _onCapsToggle(line) {
        if ((line || "").trim() !== "toggle")
            return
        // Not yet synced from sysfs: let the file read establish truth.
        if (!root._capsPrimed) {
            capsFile.reload()
            return
        }
        // Primary trigger: flip locally and show. The poll then reads the
        // same state and stays silent - no double popup, no debounce timer.
        root.capsOn = !root.capsOn
        root._show("caps", 1400)
    }
}
