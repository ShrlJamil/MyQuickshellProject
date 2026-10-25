pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The wallpaper core behind the Settings Wallpaper page - the single
// owner of all wallpaper logic (the DynamicCenter carousel that used to
// share it has been removed). Owns the collection scan of
// ~/Pictures/Wallpapers, imports, the selection, the last-applied
// wallpaper, a persistent apply history, and the apply pipeline itself.
//
// The pipeline is orchestrated stepwise in QML - one Process per step,
// exit code checked before continuing - instead of the old single
// inline `bash -c` script: a failed step stops the chain, no success
// notification is sent, and the active wallpaper / history are only
// updated after EVERY step succeeded. In particular, if `awww` already
// changed the on-screen image but a theme step fails afterwards, the
// status says so honestly instead of claiming success.
//
// Applies never run concurrently: a request made while one is running
// is kept as a one-deep, latest-wins pending request and starts when
// the current pipeline finishes (the old picker silently dropped it).
Item {
    id: root

    readonly property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string hyprlockDir: Quickshell.env("HOME") + "/Pictures/hyprlock"
    readonly property string hyprlockPath: root.hyprlockDir + "/current_wallpaper.jpg"
    readonly property int historyLimit: 20

    // The collection. Roles: fileUrl (url), filePath (string), fileName.
    readonly property ListModel wallpapers: wallModel

    // ---- state -------------------------------------------------------------
    property string selectedPath: ""
    property string activePath: ""          // last SUCCESSFULLY applied (persisted)
    property var history: []                // successfully applied paths, newest first (persisted)

    // idle | importing | applying | success | error
    property string status: "idle"
    property string statusMessage: ""
    readonly property bool busy: root.status === "importing" || root.status === "applying"

    signal scanFinished()
    signal importFinished(bool success, string path)
    signal applyFinished(bool success, string path)

    property bool _scanned: false
    property bool _stateLoaded: false
    property string _selectAfterScan: ""
    property string _pendingPath: ""

    // ---- small helpers -------------------------------------------------------
    function fileNameOf(path) {
        const i = String(path || "").lastIndexOf("/")
        return i >= 0 ? String(path).substring(i + 1) : String(path || "")
    }

    function urlForPath(path) {
        return "file://" + encodeURI(path)
    }

    function pathFromUrl(url) {
        return decodeURIComponent(String(url || "").replace(/^file:\/\//, ""))
    }

    function _containsPath(path) {
        for (let i = 0; i < wallModel.count; i++)
            if (wallModel.get(i).filePath === path)
                return true
        return false
    }

    function _nameTaken(name) {
        for (let i = 0; i < wallModel.count; i++)
            if (wallModel.get(i).fileName === name)
                return true
        return false
    }

    function pathAt(index) {
        if (index < 0 || index >= wallModel.count)
            return ""
        return wallModel.get(index).filePath || ""
    }

    function indexOfPath(path) {
        for (let i = 0; i < wallModel.count; i++)
            if (wallModel.get(i).filePath === path)
                return i
        return -1
    }

    function select(path) {
        if (path && root._containsPath(path))
            root.selectedPath = path
    }

    function _setSuccess(message) {
        root.status = "success"
        root.statusMessage = message
    }

    function _setError(message) {
        root.status = "error"
        root.statusMessage = message
    }

    function _errLine(collector) {
        const raw = String((collector && collector.text) || "").trim()
        if (!raw)
            return ""
        const lines = raw.split("\n")
        const last = lines[lines.length - 1].trim()
        return last.length > 140 ? last.substring(0, 140) + "…" : last
    }

    // ---- collection scan ------------------------------------------------------
    ListModel {
        id: wallModel
    }

    Process {
        id: dirProc

        command: ["find", root.wallpaperDir, "-maxdepth", "1", "-type", "f", "-printf", "%T@ %f\n"]
        stdout: StdioCollector { id: dirOut; waitForEnd: true }

        onExited: (code) => {
            if (code === 0)
                root._populate(dirOut.text)
            else
                root.scanFinished()
        }
    }

    function reload() {
        if (!dirProc.running)
            dirProc.running = true
    }

    function _populate(text) {
        // Rows are "<mtime-epoch> <name>" (find %T@). Split only at the
        // FIRST space so names containing spaces survive intact.
        const rows = String(text || "").split("\n")
        const items = []
        for (let i = 0; i < rows.length; i++) {
            const sp = rows[i].indexOf(" ")
            if (sp < 0)
                continue
            const ts = parseFloat(rows[i].substring(0, sp))
            const nm = rows[i].substring(sp + 1)
            if (nm.length === 0 || nm.charAt(0) === ".")
                continue
            if (!/\.(jpe?g|png|webp)$/i.test(nm))
                continue
            items.push({ name: nm, mtime: isNaN(ts) ? 0 : ts })
        }
        // Newest first - a fresh import (a copy gets a fresh mtime) lands
        // at the top. The name breaks mtime ties so bulk-copied files
        // still get one deterministic order.
        items.sort((a, b) => (b.mtime - a.mtime) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
        wallModel.clear()
        for (let j = 0; j < items.length; j++) {
            const p = root.wallpaperDir + "/" + items[j].name
            wallModel.append({ fileUrl: root.urlForPath(p), filePath: p, fileName: items[j].name })
        }
        root._scanned = true

        if (root.selectedPath && !root._containsPath(root.selectedPath))
            root.selectedPath = ""
        if (root._selectAfterScan) {
            const want = root._selectAfterScan
            root._selectAfterScan = ""
            root.select(want)
        }
        root._validatePersisted()
        root.scanFinished()
    }

    // ---- persistence ------------------------------------------------------------
    // statePath("wallpaper-state.json"): { version, activePath, history[] }.
    // Metadata only - never image data. Missing/corrupt files degrade to
    // defaults via the same onLoaded/onLoadFailed funnel DisplayService uses.
    FileView {
        id: stateFile

        path: Quickshell.statePath("wallpaper-state.json")
        printErrors: false
        atomicWrites: true

        onLoaded: root._onStateLoaded()
        onLoadFailed: (error) => root._onStateLoaded()
        onAdapterUpdated: writeAdapter()
        onSaveFailed: (error) => console.warn("[WallpaperService] wallpaper-state.json save failed: " + error)

        JsonAdapter {
            id: stateAdapter

            property int version: 1
            property string activePath: ""
            property var history: []
        }
    }

    function _onStateLoaded() {
        if (root._stateLoaded)
            return
        root._stateLoaded = true
        root.activePath = String(stateAdapter.activePath || "")
        const h = stateAdapter.history
        root.history = Array.isArray(h) ? h.filter(p => typeof p === "string" && p.length > 0).slice(0, root.historyLimit) : []
        root._validatePersisted()
    }

    function _saveState() {
        stateAdapter.activePath = root.activePath
        stateAdapter.history = root.history
    }

    // Drop persisted entries whose files no longer exist. Only runs once
    // BOTH the state file and the first scan have landed, so a slow scan
    // can never wipe a valid history.
    function _validatePersisted() {
        if (!root._stateLoaded || !root._scanned)
            return
        let changed = false
        const kept = root.history.filter(p => root._containsPath(p))
        if (kept.length !== root.history.length) {
            root.history = kept
            changed = true
        }
        if (root.activePath && !root._containsPath(root.activePath)) {
            root.activePath = ""
            changed = true
        }
        if (changed)
            root._saveState()
    }

    // ---- import -------------------------------------------------------------------
    property string _importSrc: ""
    property string _importDest: ""

    // Copy a user-picked image into the collection. Returns false when the
    // request was rejected up front (busy, bad type). A file already inside
    // the collection is never copied again; a same-name collision is
    // resolved by content hash: identical -> select the existing file,
    // different -> import under a unique "name-N.ext" instead of
    // overwriting anything.
    function importFile(sourcePath) {
        if (root.busy || !sourcePath)
            return false
        const name = root.fileNameOf(sourcePath)
        if (!/\.(jpe?g|png|webp)$/i.test(name)) {
            root._setError("Import failed: unsupported file type (" + name + ")")
            return false
        }

        // Already inside the collection folder (top level)?
        const prefix = root.wallpaperDir + "/"
        if (sourcePath.indexOf(prefix) === 0 && sourcePath.indexOf("/", prefix.length) < 0) {
            if (root._nameTaken(name)) {
                root.select(sourcePath)
                root._setSuccess("Already in your collection")
                root.importFinished(true, sourcePath)
            } else {
                root._selectAfterScan = sourcePath
                root.reload()
                root._setSuccess("Already in your collection")
                root.importFinished(true, sourcePath)
            }
            root._drainPending()
            return true
        }

        root.status = "importing"
        root.statusMessage = "Importing " + name + "…"
        root._importSrc = sourcePath

        if (root._nameTaken(name)) {
            shaProc.command = ["sha256sum", sourcePath, root.wallpaperDir + "/" + name]
            shaProc.running = true
        } else {
            root._importDest = root.wallpaperDir + "/" + name
            importMkdirProc.running = true
        }
        return true
    }

    function _uniqueDestFor(name) {
        const dot = name.lastIndexOf(".")
        const base = dot > 0 ? name.substring(0, dot) : name
        const ext = dot > 0 ? name.substring(dot) : ""
        for (let n = 2; n < 100; n++) {
            const candidate = base + "-" + n + ext
            if (!root._nameTaken(candidate))
                return root.wallpaperDir + "/" + candidate
        }
        return root.wallpaperDir + "/" + name
    }

    Process {
        id: shaProc

        stdout: StdioCollector { id: shaOut; waitForEnd: true }

        onExited: (code) => {
            const existing = root.wallpaperDir + "/" + root.fileNameOf(root._importSrc)
            let identical = false
            if (code === 0) {
                const lines = String(shaOut.text || "").trim().split("\n")
                if (lines.length >= 2) {
                    const h1 = lines[0].split(/\s+/)[0]
                    const h2 = lines[1].split(/\s+/)[0]
                    identical = h1 && h1 === h2
                }
            }
            // A failed hash run cannot prove identity -> treat as different
            // and import under a unique name rather than overwriting.
            if (identical) {
                root._importSrc = ""
                root.select(existing)
                root._setSuccess("Already in your collection — identical file")
                root.importFinished(true, existing)
                root._drainPending()
            } else {
                root._importDest = root._uniqueDestFor(root.fileNameOf(root._importSrc))
                importMkdirProc.running = true
            }
        }
    }

    Process {
        id: importMkdirProc

        command: ["mkdir", "-p", root.wallpaperDir]

        onExited: (code) => {
            if (code !== 0) {
                root._importSrc = ""
                root._setError("Import failed: could not create the Wallpapers folder")
                root.importFinished(false, "")
                root._drainPending()
                return
            }
            importCpProc.command = ["cp", "--", root._importSrc, root._importDest]
            importCpProc.running = true
        }
    }

    Process {
        id: importCpProc

        stderr: StdioCollector { id: importCpErr; waitForEnd: true }

        onExited: (code) => {
            const dest = root._importDest
            root._importSrc = ""
            root._importDest = ""
            if (code !== 0) {
                const err = root._errLine(importCpErr)
                root._setError("Import failed: could not copy the file" + (err ? " (" + err + ")" : ""))
                root.importFinished(false, "")
                root._drainPending()
                return
            }
            root._selectAfterScan = dest
            root.reload()
            root._setSuccess("Imported " + root.fileNameOf(dest))
            root.importFinished(true, dest)
            root._drainPending()
        }
    }

    // ---- apply pipeline -------------------------------------------------------------
    property string _applyImg: ""
    property var _monitors: []
    property int _monIndex: 0
    property bool _imageApplied: false

    // Start (or queue) an apply. Returns false only for an invalid target.
    function apply(path) {
        if (!path || !root._containsPath(path)) {
            root._setError("Apply failed: that file is not in the collection")
            return false
        }
        if (root.busy) {
            // One-deep, latest-wins: never run two pipelines at once, and
            // never silently drop the newest request either.
            root._pendingPath = path
            return true
        }
        root._startApply(path)
        return true
    }

    function _drainPending() {
        if (!root._pendingPath || root.busy)
            return
        const p = root._pendingPath
        root._pendingPath = ""
        if (root._containsPath(p))
            root._startApply(p)
    }

    function _startApply(path) {
        root.status = "applying"
        root.statusMessage = "Applying " + root.fileNameOf(path) + "…"
        root._applyImg = path
        root._monitors = []
        root._monIndex = 0
        root._imageApplied = false
        daemonCheckProc.running = true
    }

    function _failApply(step, errText) {
        let msg = "Apply failed at " + step + (errText ? ": " + errText : "")
        if (root._imageApplied)
            msg += " — the wallpaper image itself was already changed on screen, but the theme steps did not complete."
        const img = root._applyImg
        root._applyImg = ""
        root._setError(msg)
        root.applyFinished(false, img)
        root._drainPending()
    }

    function _succeedApply() {
        const img = root._applyImg
        root._applyImg = ""
        root.activePath = img
        root.history = [img].concat(root.history.filter(p => p !== img)).slice(0, root.historyLimit)
        root._saveState()
        root._setSuccess("Applied " + root.fileNameOf(img))
        root.applyFinished(true, img)
        root._drainPending()
    }

    // Step 1: awww-daemon present?
    Process {
        id: daemonCheckProc

        command: ["pgrep", "-x", "awww-daemon"]

        onExited: (code) => {
            if (code === 0)
                monitorsProc.running = true
            else
                daemonStartProc.running = true
        }
    }

    // Step 1b: start it (awww-daemon forks; the launcher process exits).
    Process {
        id: daemonStartProc

        command: ["awww-daemon"]
        stderr: StdioCollector { id: daemonErr; waitForEnd: true }

        onExited: (code) => {
            if (code !== 0)
                root._failApply("awww-daemon (start)", root._errLine(daemonErr) || "not found or failed to start")
            else
                daemonSettleTimer.start()
        }
    }

    Timer {
        id: daemonSettleTimer

        interval: 300
        onTriggered: monitorsProc.running = true
    }

    // Step 2: monitor list (hyprctl JSON parsed in QML - no jq).
    Process {
        id: monitorsProc

        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector { id: monitorsOut; waitForEnd: true }
        stderr: StdioCollector { id: monitorsErr; waitForEnd: true }

        onExited: (code) => {
            if (code !== 0) {
                root._failApply("hyprctl monitors", root._errLine(monitorsErr))
                return
            }
            let names = []
            try {
                const arr = JSON.parse(monitorsOut.text || "[]")
                for (let i = 0; i < arr.length; i++)
                    if (arr[i] && arr[i].name)
                        names.push(String(arr[i].name))
            } catch (e) {
                names = []
            }
            if (names.length === 0) {
                root._failApply("hyprctl monitors", "no monitors reported")
                return
            }
            root._monitors = names
            root._monIndex = 0
            root._stepAwww()
        }
    }

    // Step 3: awww img, one monitor at a time. Transition: a diagonal
    // wipe - verified against the awww man page (doc/awww-img.1.scd):
    // `wipe` is the directional sweep whose angle --transition-angle
    // controls (degrees; 0 = right-to-left, 90 = top-to-bottom), and 45
    // is both its default and the diagonal. 0.4s at 60fps keeps it short
    // but smooth (the 30fps default would give a 0.4s wipe only ~12
    // frames). The old grow tuning (pos + overshoot bezier + 120fps)
    // goes away entirely.
    function _stepAwww() {
        awwwProc.command = ["awww", "img", "-o", root._monitors[root._monIndex], root._applyImg,
            "--transition-type", "wipe", "--transition-angle", "45",
            "--transition-duration", "0.4", "--transition-fps", "60"]
        awwwProc.running = true
    }

    Process {
        id: awwwProc

        stderr: StdioCollector { id: awwwErr; waitForEnd: true }

        onExited: (code) => {
            if (code !== 0) {
                root._imageApplied = root._monIndex > 0
                root._failApply("awww (" + root._monitors[root._monIndex] + ")", root._errLine(awwwErr))
                return
            }
            root._monIndex++
            if (root._monIndex < root._monitors.length) {
                root._stepAwww()
            } else {
                root._imageApplied = true
                wallustProc.command = ["wallust", "run", root._applyImg, "--skip-sequences"]
                wallustProc.running = true
            }
        }
    }

    // Step 4: wallust.
    Process {
        id: wallustProc

        stderr: StdioCollector { id: wallustErr; waitForEnd: true }

        onExited: (code) => {
            if (code !== 0) {
                root._failApply("wallust", root._errLine(wallustErr))
                return
            }
            matugenProc.command = ["matugen", "-t", "scheme-tonal-spot", "--contrast", "0.4",
                "--prefer", "saturation", "image", root._applyImg, "--source-color-index", "0"]
            matugenProc.running = true
        }
    }

    // Step 5: matugen.
    Process {
        id: matugenProc

        stderr: StdioCollector { id: matugenErr; waitForEnd: true }

        onExited: (code) => {
            if (code !== 0) {
                root._failApply("matugen", root._errLine(matugenErr))
                return
            }
            lockMkdirProc.running = true
        }
    }

    // Step 6: hyprlock copy (folder first, then the copy itself).
    Process {
        id: lockMkdirProc

        command: ["mkdir", "-p", root.hyprlockDir]

        onExited: (code) => {
            if (code !== 0) {
                root._failApply("hyprlock folder", "")
                return
            }
            lockCpProc.command = ["cp", "--", root._applyImg, root.hyprlockPath]
            lockCpProc.running = true
        }
    }

    Process {
        id: lockCpProc

        stderr: StdioCollector { id: lockCpErr; waitForEnd: true }

        onExited: (code) => {
            if (code !== 0) {
                root._failApply("hyprlock copy", root._errLine(lockCpErr))
                return
            }
            notifyProc.command = ["notify-send", "Theme Applied", "Wallpaper and theme updated successfully!", "-i", root._applyImg]
            notifyProc.running = true
        }
    }

    // Step 7: success notification - only reached when every required
    // step passed. Its own failure is non-fatal (the apply is real).
    Process {
        id: notifyProc

        onExited: (code) => {
            if (code !== 0)
                console.warn("[WallpaperService] notify-send failed (" + code + ")")
            root._succeedApply()
        }
    }

    Component.onCompleted: root.reload()
}
