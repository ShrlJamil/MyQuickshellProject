pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Real-time audio spectrum from `cava` (raw / ascii mode). Singleton, consumed
// by the compact MediaPreview mini-viz in the static bar.
//
// cava runs with an inline-generated config: 26 mono bars, ascii range 0..100,
// 30 fps, auto-detected input (PipeWire / Pulse / ALSA), plus a [smoothing]
// block (autosens + light monstercat, integral 70, gravity 100) so it reacts
// quickly to quiet passages. It streams frames "v;v;...;v;\n" on stdout; each
// line becomes `bars`, a ~26-element array normalized 0..1.
//
// Silence vs offline:
//   * playing but quiet / paused audio -> cava keeps emitting frames that are
//     all (near-)zeros, so `bars` stays a live zero-filled array and consumers
//     simply retract. No special-casing, no flip back to fake animation.
//   * cava disabled / crashed / never produced -> `bars` is [] , which is the
//     signal for consumers to fall back to their own built-in animation.
Item {
    id: root

    // Newest frame, magnitudes 0..1. [] only when cava is not producing.
    property var bars: []
    readonly property int barCount: 26

    // Keep cava (and its capture stream) alive only while a consumer wants the
    // spectrum. Driven from shell.qml off the media playback state.
    property bool active: false

    onActiveChanged: if (!root.active) root.bars = []

    function _handleLine(line) {
        if (!line)
            return
        const parts = line.split(";")
        const arr = []
        for (let i = 0; i < parts.length; i++) {
            const s = parts[i]
            if (s === "" || s === "\r")
                continue
            let v = parseFloat(s)
            if (!isFinite(v) || v < 0)
                v = 0
            arr.push(v >= 100 ? 1 : v / 100)
        }
        if (arr.length === 0)
            return
        root.bars = arr
        staleTimer.restart()
    }

    Process {
        id: cavaProc

        // mktemp a config, write it line by line, then exec cava on it.
        command: ["bash", "-c",
            "CFG=$(mktemp) || exit 1; " +
            "printf '%s\\n' " +
            "'[general]' 'framerate = 30' 'bars = 26' " +
            "'[smoothing]' 'autosens = 1' 'integral = 70' 'monstercat = 1' 'waves = 0' 'gravity = 100' " +
            "'[output]' 'method = raw' 'raw_target = /dev/stdout' " +
            "'data_format = ascii' 'ascii_max_range = 100' 'channels = mono' " +
            "> \"$CFG\"; " +
            "exec cava -p \"$CFG\""]

        stdout: SplitParser {
            onRead: (line) => root._handleLine(line)
        }

        onRunningChanged: if (!running) root.bars = []
    }

    // Owns cavaProc.running: reconciles it to `active` and restarts after a
    // crash. Polling a bool every 400ms is free; `triggeredOnStart` skips the
    // first-interval delay so cava comes up promptly on unpause.
    Timer {
        interval: 400
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (root.active && !cavaProc.running)
                cavaProc.running = true
            else if (!root.active && cavaProc.running)
                cavaProc.running = false
        }
    }

    // No frame for a second -> cava stalled / gone -> let consumers fall back.
    Timer {
        id: staleTimer
        interval: 1000
        repeat: false
        onTriggered: root.bars = []
    }
}
