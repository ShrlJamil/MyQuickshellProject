pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root

    property string selectedMonitor: ""
    property var layout: ({})
    property string statusMessage: ""
    property bool statusIsError: false

    // Set by the canvas while a monitor is being dragged, so a late-arriving
    // Hyprland refresh does not overwrite the in-progress edit.
    property bool suspendSync: false
    onSuspendSyncChanged: if (root.suspendSync) resyncTimer.stop()

    // ---- Instant Extend <-> Mirror toggle (Control Center tile) --------------
    // Reuses applyPreset() + applyLive() (live `hyprctl eval` + monitors.lua
    // persist) - no second mirror code path.

    // Authoritative mirror state. Hyprland DROPS a mirroring output from
    // `hyprctl monitors` (only `monitors all` shows it), so once mirrored it
    // cannot be re-derived from the live model - this flag is the source of
    // truth for the tile. Set optimistically by the toggle, rolled back if the
    // apply fails, and seeded on boot from monitors.lua.
    property bool _mirrorEngaged: false
    readonly property bool mirrorActive: root._mirrorEngaged

    // Full pre-mirror layout (every output), so toggle-off can restore exact
    // position/scale/mode AND emit a spec for the now-hidden mirroring output
    // to un-mirror it. In-memory; a shell restart mid-mirror falls back to the
    // plain extend preset on toggle-off.
    property var _extendSnapshot: null

    // Snapshot of { layout, engaged, snapshot } taken before a toggle; restored
    // wholesale if that toggle's applyLive() fails so the tile never lies. Only
    // the toggle sets this - DisplayManager's Apply is unaffected.
    property var _toggleRevert: null

    // Enabled whenever a 2nd output exists, OR a mirror is engaged (so it can be
    // switched back off even though only one output is then visible).
    readonly property bool canMirror: root._mirrorEngaged || Object.keys(root.layout).length >= 2

    property int _monCount: 0
    property bool _seededMirrorFlag: false

    Component.onCompleted: {
        root._monCount = Hyprland.monitors.values.length
        // Populate the model from live Hyprland (refreshMonitors + rebuild +
        // the resync catch-up) so the tile's state is right from the first open.
        root.syncFromHyprland()
    }

    // Hotplug: rebuild when the output count changes so `canMirror` and the
    // model track connect/disconnect. Count-gated so the churn Hyprland emits
    // after our own `hyprctl eval` (same count, stale lastIpcObject) does not
    // clobber a layout we just applied. No new polling.
    Connections {
        target: Hyprland.monitors
        function onValuesChanged() {
            const n = Hyprland.monitors.values.length
            if (n === root._monCount)
                return
            root._monCount = n
            if (!root.suspendSync)
                root.syncFromHyprland()
        }
    }

    // Extend <-> Mirror. Mirrors every other output onto the focused one;
    // toggling back restores the saved Extend layout. Live + persisted via
    // applyLive() - exactly DisplayManager's Apply path, no second writer.
    //
    // A single `hyprctl monitors all -j` (mirroring outputs are hidden from the
    // plain list / Quickshell's Hyprland.monitors, and no event fires after our
    // own `hyprctl eval`) is the authoritative read each toggle acts on. One
    // one-shot process per click - not polling.
    function toggleMirror() {
        if (monQueryProc.running)
            return
        monQueryProc.running = true
    }

    Process {
        id: monQueryProc

        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: (exitCode) => {
            let list = null
            if (exitCode === 0) {
                try {
                    list = JSON.parse(monQueryProc.stdout.text)
                } catch (e) {
                    list = null
                }
            }
            if (!list || !Array.isArray(list)) {
                root.statusIsError = true
                root.statusMessage = "Could not read displays"
                statusTimer.restart()
                return
            }
            root._toggleMirrorWith(list)
        }
    }

    // Build a working-model entry from one `hyprctl monitors all` object.
    function _monEntry(m) {
        return {
            x: m.x, y: m.y,
            width: m.width, height: m.height,
            refresh: m.refreshRate ? Math.round(m.refreshRate * 100) / 100 : 60,
            scale: m.scale || 1,
            transform: typeof m.transform === "number" ? m.transform : 0,
            disabled: !!m.disabled,
            mirrorOf: (m.mirrorOf && m.mirrorOf !== "none") ? m.mirrorOf : "",
            availableModes: m.availableModes || [],
            internal: m.name.indexOf("eDP") === 0
        }
    }

    function _toggleMirrorWith(list) {
        const full = {}
        for (let i = 0; i < list.length; i++)
            full[list[i].name] = root._monEntry(list[i])

        const fullNames = Object.keys(full).sort()
        const anyMirror = fullNames.some(n => full[n].mirrorOf)

        if (anyMirror) {
            // ---- Mirror -> Extend ---------------------------------------------
            root._toggleRevert = {
                layout: JSON.parse(JSON.stringify(root.layout)),
                engaged: root._mirrorEngaged,
                snapshot: root._extendSnapshot ? JSON.parse(JSON.stringify(root._extendSnapshot)) : null
            }

            let next
            if (root._extendSnapshot) {
                // Exact restore of the pre-mirror layout, with mirror cleared.
                next = {}
                const snapNames = Object.keys(root._extendSnapshot)
                for (let i = 0; i < snapNames.length; i++) {
                    const n = snapNames[i]
                    next[n] = Object.assign({}, root._extendSnapshot[n], { mirrorOf: "" })
                }
            } else {
                // No snapshot (booted mirrored) - un-mirror every real output and
                // lay them left-to-right so none is lost from the persisted file.
                next = {}
                let cursor = 0
                for (let i = 0; i < fullNames.length; i++) {
                    const n = fullNames[i]
                    const e = Object.assign({}, full[n], { mirrorOf: "", disabled: false, x: cursor, y: 0 })
                    next[n] = e
                    const w = e.transform === 1 || e.transform === 3 ? e.height : e.width
                    cursor += Math.max(1, Math.round((w || 1) / (e.scale || 1)))
                }
            }

            root.layout = next
            root._extendSnapshot = null
            root._mirrorEngaged = false
            root.applyLive()
            return
        }

        // ---- Extend -> Mirror -----------------------------------------------
        if (fullNames.length < 2) {
            root.statusIsError = true
            root.statusMessage = "Mirror needs 2+ displays"
            statusTimer.restart()
            return
        }
        for (let i = 0; i < fullNames.length; i++) {
            const e = full[fullNames[i]]
            if (!(e.width > 0) || !(e.height > 0)) {
                root.statusIsError = true
                root.statusMessage = "Display info not ready — try again"
                statusTimer.restart()
                return
            }
        }

        root._toggleRevert = {
            layout: JSON.parse(JSON.stringify(root.layout)),
            engaged: false,
            snapshot: root._extendSnapshot ? JSON.parse(JSON.stringify(root._extendSnapshot)) : null
        }
        root._extendSnapshot = JSON.parse(JSON.stringify(full))
        root.layout = JSON.parse(JSON.stringify(full))

        const focused = Hyprland.focusedMonitor
        const source = (focused && full[focused.name]) ? focused.name : fullNames[0]
        root.applyPreset("mirror", { source: source })
        root._mirrorEngaged = true
        root.applyLive()
    }

    function monitorNames() {
        return Object.keys(root.layout).sort()
    }

    // Quickshell's Hyprland.monitors cache is NOT refreshed after a live
    // `hyprctl keyword/eval` monitor change (Hyprland emits no event for it),
    // and only asynchronously after a reload. So force a re-query and rebuild
    // the model both now and again shortly after, once the fresh data lands.
    function syncFromHyprland() {
        Hyprland.refreshMonitors()
        root._rebuildLayout()
        resyncTimer.ticks = 0
        resyncTimer.restart()
    }

    function _rebuildLayout() {
        if (root.suspendSync)
            return

        const list = Hyprland.monitors.values
        const next = {}

        for (let i = 0; i < list.length; i++) {
            const mon = list[i]
            const ipc = mon.lastIpcObject || {}
            const name = mon.name

            next[name] = {
                x: ipc.x !== undefined ? ipc.x : mon.x,
                y: ipc.y !== undefined ? ipc.y : mon.y,
                width: ipc.width !== undefined ? ipc.width : mon.width,
                height: ipc.height !== undefined ? ipc.height : mon.height,
                refresh: ipc.refreshRate ? Math.round(ipc.refreshRate * 100) / 100 : 60,
                scale: mon.scale || 1,
                transform: typeof ipc.transform === "number" ? ipc.transform : 0,
                disabled: !!ipc.disabled,
                mirrorOf: ipc.mirrorOf && ipc.mirrorOf !== "none" ? ipc.mirrorOf : "",
                availableModes: ipc.availableModes || [],
                internal: name.indexOf("eDP") === 0
            }
        }

        if (JSON.stringify(next) === JSON.stringify(root.layout))
            return

        root.layout = next

        const names = root.monitorNames()
        if (!root.selectedMonitor || !next[root.selectedMonitor]) {
            const focused = Hyprland.focusedMonitor
            root.selectedMonitor = (focused && next[focused.name]) ? focused.name : (names[0] || "")
        }
    }

    // Catches the async monitor data that arrives after refreshMonitors() /
    // after a reload's `configreloaded`. Runs only for ~600ms after an open.
    Timer {
        id: resyncTimer

        property int ticks: 0

        interval: 120
        repeat: true
        onTriggered: {
            root._rebuildLayout()
            resyncTimer.ticks++
            if (resyncTimer.ticks >= 5)
                resyncTimer.stop()
        }
    }

    function updateMonitor(name, changes) {
        if (!root.layout[name])
            return

        const next = Object.assign({}, root.layout)
        next[name] = Object.assign({}, next[name], changes)
        root.layout = next
    }

    function setPosition(name, x, y) {
        root.updateMonitor(name, { x: Math.round(x), y: Math.round(y) })
    }

    function setScale(name, scale) {
        root.updateMonitor(name, { scale: scale })
    }

    function setTransform(name, transform) {
        root.updateMonitor(name, { transform: transform })
    }

    function setResolution(name, width, height, refresh) {
        root.updateMonitor(name, { width: width, height: height, refresh: refresh })
    }

    function setMirror(name, targetName) {
        root.updateMonitor(name, { mirrorOf: targetName, disabled: false })
    }

    function clearMirror(name) {
        root.updateMonitor(name, { mirrorOf: "" })
    }

    function overlapsVertically(a, b) {
        return Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y) > 0
    }

    function overlapsHorizontally(a, b) {
        return Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x) > 0
    }

    // Logical (Hyprland coordinate space) geometry: mode size / scale, with
    // width/height swapped for 90/270 rotation. Adjacency must be judged in this
    // space - never with raw physical resolution.
    function _rotated(m) {
        return !!m && (m.transform === 1 || m.transform === 3)
    }

    function logicalSize(name) {
        const m = root.layout[name]
        if (!m)
            return { width: 0, height: 0 }
        const w = root._rotated(m) ? m.height : m.width
        const h = root._rotated(m) ? m.width : m.height
        const s = m.scale || 1
        return { width: Math.max(1, Math.round(w / s)), height: Math.max(1, Math.round(h / s)) }
    }

    function logicalRect(name) {
        const m = root.layout[name]
        if (!m)
            return { x: 0, y: 0, width: 0, height: 0 }
        const ls = root.logicalSize(name)
        return { x: m.x, y: m.y, width: ls.width, height: ls.height }
    }

    function snapMonitor(name) {
        if (!root.layout[name])
            return

        const mon = root.logicalRect(name)
        const others = root.monitorNames().filter(n => n !== name)
        const threshold = 60

        for (let i = 0; i < others.length; i++) {
            const other = root.logicalRect(others[i])
            const overlapX = Math.min(mon.x + mon.width, other.x + other.width) - Math.max(mon.x, other.x)
            const overlapY = Math.min(mon.y + mon.height, other.y + other.height) - Math.max(mon.y, other.y)

            if (overlapX > mon.width * 0.6 && overlapY > mon.height * 0.6) {
                root.setMirror(name, others[i])
                root.setPosition(name, other.x, other.y)
                return
            }
        }

        root.clearMirror(name)

        for (let i = 0; i < others.length; i++) {
            const other = root.logicalRect(others[i])

            if (root.overlapsVertically(mon, other)) {
                if (Math.abs(mon.x - (other.x + other.width)) < threshold)
                    return root.setPosition(name, other.x + other.width, other.y)
                if (Math.abs((mon.x + mon.width) - other.x) < threshold)
                    return root.setPosition(name, other.x - mon.width, other.y)
            }

            if (root.overlapsHorizontally(mon, other)) {
                if (Math.abs(mon.y - (other.y + other.height)) < threshold)
                    return root.setPosition(name, other.x, other.y + other.height)
                if (Math.abs((mon.y + mon.height) - other.y) < threshold)
                    return root.setPosition(name, other.x, other.y - mon.height)
            }
        }
    }

    // Called when a canvas drag ends. The live drag already handled magnetic
    // edge snapping with hysteresis, so this only does an integer normalize and
    // the mirror-on-full-overlap gesture - it must NOT yank arbitrary positions
    // onto a neighbour's edge.
    function finalizeDrag(name) {
        const cur = root.layout[name]
        if (!cur)
            return

        const mon = root.logicalRect(name)
        const others = root.monitorNames().filter(n => n !== name)

        for (let i = 0; i < others.length; i++) {
            const other = root.logicalRect(others[i])
            const overlapX = Math.min(mon.x + mon.width, other.x + other.width) - Math.max(mon.x, other.x)
            const overlapY = Math.min(mon.y + mon.height, other.y + other.height) - Math.max(mon.y, other.y)

            if (overlapX > mon.width * 0.6 && overlapY > mon.height * 0.6) {
                root.setMirror(name, others[i])
                root.setPosition(name, other.x, other.y)
                return
            }
        }

        root.clearMirror(name)
        root.setPosition(name, Math.round(cur.x), Math.round(cur.y))
    }

    function applyPreset(preset, opts) {
        const names = root.monitorNames()
        if (names.length === 0)
            return

        if (preset === "extend") {
            let cursorX = 0
            for (let i = 0; i < names.length; i++) {
                root.updateMonitor(names[i], { disabled: false, mirrorOf: "", x: cursorX, y: 0 })
                cursorX += root.logicalSize(names[i]).width
            }
        } else if (preset === "mirror") {
            // Optional opts.source picks which output the rest mirror onto;
            // defaults to names[0] so the 1-arg DisplayManager calls are
            // unchanged.
            const primary = (opts && opts.source && root.layout[opts.source]) ? opts.source : names[0]
            root.updateMonitor(primary, { disabled: false, mirrorOf: "", x: 0, y: 0 })
            for (let i = 0; i < names.length; i++) {
                if (names[i] === primary)
                    continue
                root.updateMonitor(names[i], { disabled: false, mirrorOf: primary, x: 0, y: 0 })
            }
        } else if (preset === "internalOnly") {
            for (let i = 0; i < names.length; i++)
                root.updateMonitor(names[i], { disabled: !root.layout[names[i]].internal, mirrorOf: "" })
        } else if (preset === "externalOnly") {
            for (let i = 0; i < names.length; i++)
                root.updateMonitor(names[i], { disabled: root.layout[names[i]].internal, mirrorOf: "" })
        }
    }

    // Single source of truth for the "<w>x<h>@<refresh>" token used by both the
    // live apply and the persisted monitors.lua. Prefer a mode string Hyprland
    // actually advertises for the monitor so we never emit an unmatchable
    // refresh like "@59.99".
    function modeString(mon) {
        const base = mon.width + "x" + mon.height
        const wanted = mon.refresh
        const modes = mon.availableModes || []

        let best = ""
        let bestDelta = Infinity
        for (let i = 0; i < modes.length; i++) {
            const parts = String(modes[i]).split("@")
            if (parts[0] !== base)
                continue
            const hz = parseFloat(parts[1])
            if (isNaN(hz))
                continue
            const delta = Math.abs(hz - wanted)
            if (delta < bestDelta) {
                bestDelta = delta
                best = (base + "@" + parts[1]).replace(/Hz\s*$/i, "").trim()
            }
        }
        if (best !== "" && bestDelta <= 1.5)
            return best

        // Fallback: monitor exposed no matching mode. Snap near-integers to an
        // integer refresh, otherwise keep at most two decimals - never an
        // arbitrary rounding that yields values like 59.99.
        let hz = wanted
        hz = (Math.abs(hz - Math.round(hz)) < 0.05) ? Math.round(hz) : Math.round(hz * 100) / 100
        return base + "@" + hz
    }

    function cleanScale(scale) {
        return Math.round((scale || 1) * 1e6) / 1e6
    }

    // One HL.MonitorSpec table literal - { output = ..., mode = ..., ... } - used
    // verbatim by BOTH the live apply (hyprctl eval hl.monitor(...)) and the
    // persisted monitors.lua. Field names must match the hl.monitor() API:
    // never name / resolution.
    function monitorSpecLua(name) {
        const mon = root.layout[name]
        if (!mon)
            return ""

        const fields = ['output = "' + name + '"']

        if (mon.disabled) {
            fields.push("disabled = true")
            return "{ " + fields.join(", ") + " }"
        }

        fields.push('mode = "' + root.modeString(mon) + '"')
        fields.push('position = "' + mon.x + "x" + mon.y + '"')
        fields.push("scale = " + root.cleanScale(mon.scale))
        if (mon.transform)
            fields.push("transform = " + mon.transform)
        if (mon.mirrorOf)
            fields.push('mirror = "' + mon.mirrorOf + '"')

        return "{ " + fields.join(", ") + " }"
    }

    // Apply = push the layout live AND persist it. `applyProc` does the live
    // `hyprctl eval hl.monitor(...)`; on success its onExited calls
    // _persistConfig() to write the identical spec to monitors.lua. There is no
    // separate Save action - the two were always meant to happen together, and
    // splitting them let an "Applied" layout silently vanish on the next
    // Hyprland/laptop restart (which re-reads monitors.lua verbatim).
    function applyLive() {
        const names = root.monitorNames()
        if (names.length === 0)
            return

        // This Hyprland build uses the Lua config parser: `hyprctl keyword
        // monitor` is rejected ("can't work with non-legacy parsers"), so drive
        // the same hl.monitor() spec through `hyprctl eval`. Attempt every
        // monitor even if an earlier one is rejected, but exit non-zero so the
        // UI never reports "Applied" on a partial failure.
        const cmds = ["rc=0"]
        for (let i = 0; i < names.length; i++)
            cmds.push("hyprctl eval 'hl.monitor(" + root.monitorSpecLua(names[i]) + ")' || rc=1")
        cmds.push("exit $rc")

        applyProc.command = ["sh", "-c", cmds.join("\n")]
        applyProc.running = true
    }

    // Persist the current layout to ~/.config/hypr/monitors.lua so it is
    // re-applied on every `hyprctl reload` AND on a full Hyprland / laptop
    // restart - hyprland.lua does `require("monitors")` -> hl.monitor() at
    // startup. Same HL.MonitorSpec table literals as the live apply, so the
    // saved layout is byte-for-byte the one just applied. No `hyprctl reload`
    // here: the live apply already set the running state; a reload would only
    // add a redundant re-layout flash.
    function _persistConfig() {
        const names = root.monitorNames()
        const lines = ["return {"]

        for (let i = 0; i < names.length; i++)
            lines.push("    " + root.monitorSpecLua(names[i]) + ",")

        lines.push("}")
        lines.push("")

        monitorsFile.setText(lines.join("\n"))
    }

    Process {
        id: applyProc

        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }

        onExited: (exitCode) => {
            root.statusIsError = exitCode !== 0
            if (exitCode === 0) {
                // Live apply landed -> write the same layout to monitors.lua so
                // it survives reload / restart / reboot. monitorsFile.onSaved /
                // onSaveFailed finalises the status message.
                root.statusMessage = "Applying…"
                root._toggleRevert = null
                root._persistConfig()
            } else {
                // A failed Control Center mirror toggle must not leave the tile
                // claiming the wrong state - roll layout + flag + snapshot back.
                // (Only toggleMirror() arms _toggleRevert; DisplayManager's
                // Apply leaves it null and is unaffected.)
                if (root._toggleRevert) {
                    root.layout = root._toggleRevert.layout
                    root._mirrorEngaged = root._toggleRevert.engaged
                    root._extendSnapshot = root._toggleRevert.snapshot
                    root._toggleRevert = null
                }
                const raw = ((applyProc.stdout.text || "") + (applyProc.stderr.text || "")).trim()
                const errLine = raw.split("\n").filter(l => /error/i.test(l))[0]
                root.statusMessage = "Apply failed: " + (errLine || raw.split("\n").pop() || ("exit " + exitCode))
                console.warn("[DisplayService] apply failed (" + exitCode + "):\n" + raw)
                statusTimer.restart()
            }
        }
    }

    FileView {
        id: monitorsFile

        path: String(Quickshell.env("HOME")) + "/.config/hypr/monitors.lua"
        printErrors: true
        atomicWrites: true

        // On the first load, seed the mirror flag if we booted with a persisted
        // mirror (Hyprland then hides the mirroring output, so the tile state
        // can't be recovered from live monitor data).
        onLoaded: {
            if (root._seededMirrorFlag)
                return
            root._seededMirrorFlag = true
            const t = monitorsFile.text()
            if (t && /\bmirror\s*=/.test(t))
                root._mirrorEngaged = true
        }

        onSaved: {
            root.statusIsError = false
            root.statusMessage = "Applied & saved"
            statusTimer.restart()
        }

        onSaveFailed: {
            root.statusIsError = true
            root.statusMessage = "Applied live — save to monitors.lua failed"
            statusTimer.restart()
        }
    }

    Timer {
        id: statusTimer

        interval: 3000
        onTriggered: root.statusMessage = ""
    }
}
