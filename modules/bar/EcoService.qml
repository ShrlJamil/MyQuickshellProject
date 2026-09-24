pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"

// Eco Mode: reduces Hyprland GPU/compositor load (blur + shadow off) and makes
// QML surfaces opaque. Snapshot-apply-restore over runtime `hyprctl eval`
// only: no config file edits, no `hyprctl reload`, no persistence across shell
// restarts (OFF by default).
//
// Transport: the compositor runs the Lua config parser, which rejects
// `hyprctl keyword` ("non-legacy parsers. Use eval."). Blur + shadow go out as
// ONE combined `hyprctl eval 'hl.config(...)'` through a tracked Process with
// bounded retries (no parallel blur/shadow processes, no polling).
// QML surface opacity (Theme.surfaceOpacity) is snapshotted imperatively
// before apply and forced to 1.0 while eco is on, then restored (no binding,
// no cycle: EcoService -> Theme one-way).
// Caveat: Wallust applyPalette rewrites surfaceOpacity on palette change, so
// a wallpaper switch mid-eco restores translucency until the next toggle.
Item {
    id: root

    property bool ecoMode: false

    readonly property var _keys: ["decoration:blur:enabled", "decoration:shadow:enabled"]

    property var _snap: ({})
    property bool _haveSnap: false
    property int _readIdx: -1
    property int _readPass: 0
    property real _surfSnap: -1

    property int _triesLeft: 0
    property bool _writePending: false

    function toggle() {
        if (root.ecoMode) {
            root.ecoMode = false
            if (root._haveSnap) {
                root._restore()
            } else if (!readProc.running) {
                root._startRead()
            }
        } else {
            root.ecoMode = true
            root._surfSnap = Theme.surfaceOpacity
            if (root._haveSnap) {
                root._applyEco()
            } else if (!readProc.running) {
                root._startRead()
            }
        }
    }

    function _startRead() {
        root._readPass = 0
        root._readIdx = 0
        readProc.command = ["hyprctl", "-j", "getoption", root._keys[0]]
        readProc.running = true
    }

    function _snapValid() {
        return typeof root._snap[root._keys[0]] === "boolean"
            && typeof root._snap[root._keys[1]] === "boolean"
    }

    function _applyEco() {
        Theme.surfaceOpacity = 1.0
        root._requestWrite()
    }

    function _restore() {
        if (root._surfSnap >= 0)
            Theme.surfaceOpacity = root._surfSnap
        root._requestWrite()
    }

    // One combined eval for both keys: fewer processes, no inter-key race.
    // Values always derive from LIVE ecoMode (+ validated snapshot for OFF),
    // so a stale completion can never overwrite the final state.
    function _evalFor() {
        const b = root.ecoMode ? false : root._snap[root._keys[0]]
        const s = root.ecoMode ? false : root._snap[root._keys[1]]
        return "hl.config({ decoration = { blur = { enabled = " + (b ? "true" : "false")
            + " }, shadow = { enabled = " + (s ? "true" : "false") + " } } })"
    }

    function _requestWrite() {
        if (writeProc.running) {
            root._writePending = true
            return
        }
        root._writePending = false
        retryTimer.stop()
        root._triesLeft = 2
        root._doWrite()
    }

    function _doWrite() {
        if (!root.ecoMode && !root._haveSnap)
            return
        writeProc.command = ["hyprctl", "eval", root._evalFor()]
        writeProc.running = true
    }

    Process {
        id: readProc

        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const t = readProc.stdout.text.trim()
            if (t.charAt(0) === "{") {
                const obj = JSON.parse(t)
                if (obj && typeof obj.bool === "boolean")
                    root._snap[obj.option] = obj.bool
            }
            root._readIdx++
            if (root._readIdx < root._keys.length) {
                readProc.command = ["hyprctl", "-j", "getoption", root._keys[root._readIdx]]
                readProc.running = true
            } else if (!root._snapValid() && root._readPass < 1) {
                root._readPass++
                root._readIdx = 0
                readProc.command = ["hyprctl", "-j", "getoption", root._keys[0]]
                readProc.running = true
            } else {
                root._readIdx = -1
                if (!root._snapValid()) {
                    console.error("[EcoService] snapshot unreadable, hypr restore/apply skipped")
                    return
                }
                root._haveSnap = true
                if (root.ecoMode)
                    root._applyEco()
                else
                    root._restore()
            }
        }
    }

    Process {
        id: writeProc

        onExited: function (exitCode) {
            if (exitCode === 0) {
                if (root._writePending)
                    root._requestWrite()
                return
            }
            if (root._writePending) {
                root._requestWrite()
                return
            }
            if (root._triesLeft > 0) {
                root._triesLeft--
                retryTimer.restart()
                return
            }
            console.error("[EcoService] hypr eval failed, eco state may not match tile")
        }
    }

    Timer {
        id: retryTimer

        interval: 400
        repeat: false
        onTriggered: root._doWrite()
    }
}
