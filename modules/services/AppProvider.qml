import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false

    readonly property var allApps: DesktopEntries.applications

    readonly property real halfLifeDays: 21
    readonly property real capAmount: 10
    readonly property real boostTolerance: 0.05
    readonly property real maxRelativeBoost: 0.10
    readonly property real usageSaturation: 5

    readonly property real execPenalty: 150
    readonly property real genericPenalty: 300
    readonly property real keywordPenalty: 450
    readonly property real minFieldScore: 10

    readonly property string searchFallbackId: "search-the-web"
    readonly property string urlFallbackId: "open-url"
    readonly property string webSearchId: "web-search"
    readonly property string calculatorResultId: "calculator-result"
    readonly property string commandEntryId: "command"
    readonly property string clipboardEntryId: "clipboard"
    readonly property string fileEntryId: "file"

    readonly property var commandActions: [
        {
            id: "lock",
            title: "Lock Screen",
            subtitle: "Session",
            icon: "system-lock-screen-symbolic",
            aliases: ["lock", "lockscreen", "lock-screen"],
            execute: function() { root.executeCommandAction("lock") }
        },
        {
            id: "logout",
            title: "Log Out",
            subtitle: "Session",
            icon: "system-log-out-symbolic",
            aliases: ["logout", "signout", "exit"],
            execute: function() { root.executeCommandAction("logout") }
        },
        {
            id: "suspend",
            title: "Suspend",
            subtitle: "Power",
            icon: "media-playback-pause-symbolic",
            aliases: ["sleep", "suspend"],
            execute: function() { root.executeCommandAction("suspend") }
        },
        {
            id: "reboot",
            title: "Restart System",
            subtitle: "Power",
            icon: "system-reboot-symbolic",
            aliases: ["reboot", "restart"],
            execute: function() { root.executeCommandAction("reboot") }
        },
        {
            id: "shutdown",
            title: "Shut Down",
            subtitle: "Power",
            icon: "system-shutdown-symbolic",
            aliases: ["shutdown", "poweroff", "halt"],
            execute: function() { root.executeCommandAction("shutdown") }
        }
    ]

    readonly property var commandActionCommands: ({
        "lock": ["loginctl", "lock-session"],
        "logout": ["hyprctl", "dispatch", "exit"],
        "suspend": ["systemctl", "suspend"],
        "reboot": ["systemctl", "reboot"],
        "shutdown": ["systemctl", "poweroff"]
    })

    readonly property string terminalExecutable: "kitty"
    readonly property var terminalArguments: ["fish", "-C"]

    property var commandHistory: []
    property int commandHistoryCursor: -1
    property bool commandHistoryNavActive: false
    property string commandHistoryDraft: ""

    property string query: ""
    property var searchModeProvider
    property var apps: []
    property string lastMode: "apps"

    readonly property string searchEngine: "https://www.google.com/search?q="

    FileView {
        id: historyFile

        path: Quickshell.statePath("launcher-history.json")

        printErrors: false
        watchChanges: true

        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            var e = historyAdapter.entries
            if (e && e["*"] === undefined) {
                var now = Math.floor(Date.now() / 1000)
                var bucket = {}
                for (var id in e) {
                    var cnt = e[id]
                    if (typeof cnt === "number" && cnt > 0)
                        bucket[id] = { amount: cnt, last: now }
                }
                historyAdapter.entries = { "*": bucket }
            }
            root.refilter()
        }

        JsonAdapter {
            id: historyAdapter

            property var entries: ({})
        }
    }

    Process {
        id: commandProcess
    }

    property var clipboardCache: []
    property bool clipboardLoaded: false
    property bool clipboardBusy: false
    property bool clipboardRefreshing: false
    property bool clipboardWatchActive: false

    property var filePaths: []
    property bool fileLoaded: false
    property bool fileBusy: false

    property int fileScanGen: 0
    property int fileScanCursor: 0
    property var fileScanTop: []
    property string fileScanQuery: ""
    property var fileScanPaths: []

    readonly property int fileChunkSize: 500

    readonly property int fileResultLimit: 250
    readonly property string fileIcon: "folder-documents-symbolic"
    readonly property var fileExecute: function() {}

    readonly property var fileRoots: root.resolveFileRoots()

    readonly property string clipboardDbPath: root.resolveClipboardDb()

    signal clipboardDeleted(var clipId)
    signal clipboardRefreshStarted()
    signal clipboardRefreshed()

    Timer {
        id: fileScanTimer

        interval: 1
        repeat: false
        running: false

        onTriggered: root.fileScanStep()
    }

    FileView {
        id: clipboardWatcher

        // Only bind the real path while clipboard mode is active. FileView reads
        // the whole file at `path` into memory (data + UTF-16 text) on load, and
        // the cliphist DB is tens of MB of binary (images). Keeping it unset at
        // idle avoids ~170 MB RSS; the actual entries come from `cliphist list`,
        // this FileView is only a change tripwire.
        path: root.clipboardWatchActive ? root.clipboardDbPath : ""
        watchChanges: root.clipboardWatchActive
        blockWrites: true
        printErrors: false

        onFileChanged: {
            root.clipboardDatabaseChanged()
        }
    }

    Process {
        id: cliphistProcess

        command: ["cliphist", "list"]

        stdout: StdioCollector {
            id: clipstdout
        }

        onExited: function(exitCode) {
            if (exitCode === 0 || !root.clipboardBusy)
                return

            if (root.clipboardRefreshing) {
                root.clipboardRefreshing = false
                root.clipboardBusy = false
                console.warn("cliphist list failed during live refresh")
                root.clipboardRefreshed()
                return
            }

            root.clipboardCache = []
            root.clipboardLoaded = true
            root.clipboardBusy = false
            root.refilter()
        }

        onRunningChanged: {
            if (root.clipboardBusy && !cliphistProcess.running) {
                var wasRefreshing = root.clipboardRefreshing
                root.clipboardCache = root.parseCliphist(clipstdout.text)
                root.clipboardLoaded = true
                root.clipboardRefreshing = false
                root.clipboardBusy = false
                root.refilter()
                if (wasRefreshing)
                    root.clipboardRefreshed()
            }
        }
    }

    Process {
        id: clipdecodeProcess

        stdout: StdioCollector {
            id: clipdecoded
        }

        onExited: function(exitCode) {
            if (exitCode === 0)
                Quickshell.clipboardText = clipdecoded.text
            else
                console.warn("Failed to decode cliphist entry")
        }
    }

    Process {
        id: clipwipeProcess

        command: ["cliphist", "wipe"]

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                console.warn("Failed to wipe clipboard history")
                return
            }

            root.clipboardCache = []
            root.clipboardLoaded = true
            root.clipboardBusy = false
            root.refilter()
        }
    }

    property var clipdeletePending: undefined

    Process {
        id: clipdeleteProcess

        command: ["cliphist", "delete"]
        stdinEnabled: true

        onStarted: {
            if (root.clipdeletePending !== undefined) {
                clipdeleteProcess.write(root.clipdeletePending + "\n")
                clipdeleteProcess.stdinEnabled = false
            }
        }

        onExited: function(exitCode) {
            var clipId = root.clipdeletePending
            root.clipdeletePending = undefined

            if (exitCode !== 0) {
                console.warn("Failed to delete cliphist entry " + clipId)
                return
            }

            root.removeClipboardEntry(clipId)
        }

        onRunningChanged: {
            if (root.clipdeletePending !== undefined && !clipdeleteProcess.running) {
                root.clipdeletePending = undefined
                console.warn("cliphist delete failed to start")
            }
        }
    }

    Process {
        id: fileProcess

        stdout: StdioCollector {
            id: fileStdout
        }

        onExited: function(exitCode) {
            if (exitCode === 0 || !root.fileBusy)
                return

            root.filePaths = []
            root.fileLoaded = true
            root.fileBusy = false
            root.refilter()
        }

        onRunningChanged: {
            if (root.fileBusy && !fileProcess.running) {
                root.filePaths = root.parseFd(fileStdout.text)
                root.fileLoaded = true
                root.fileBusy = false
                root.refilter()
            }
        }
    }

    function isAlphaNum(c) {
        return (c >= "a" && c <= "z")
            || (c >= "A" && c <= "Z")
            || (c >= "0" && c <= "9")
    }

    function isLower(c) {
        return c >= "a" && c <= "z"
    }

    function isUpper(c) {
        return c >= "A" && c <= "Z"
    }

    function isSeparator(c) {
        return c === " " || c === "-" || c === "_" || c === "." || c === "/"
    }

    function acronym(target) {
        var result = []

        for (var i = 0; i < target.length; i++) {
            var c = target.charAt(i)
            var prev = i > 0 ? target.charAt(i - 1) : ""

            var wordStart = i === 0
                || !isAlphaNum(prev)
                || (isLower(prev) && isUpper(c))

            if (wordStart && isAlphaNum(c))
                result.push(c.toUpperCase())
        }

        return result.join("")
    }

    function score(q, target) {
        if (q.length === 0)
            return { score: 0, positions: [] }

        var ql = q.toLowerCase()
        var tl = target.toLowerCase()

        var qi = 0
        var lastPos = -1
        var firstPos = -1
        var score = 0
        var positions = []

        for (var ti = 0; ti < tl.length && qi < ql.length; ti++) {
            if (tl.charAt(ti) === ql.charAt(qi)) {
                score += 10
                if (lastPos >= 0)
                    score -= ti - lastPos - 1
                if (firstPos < 0)
                    firstPos = ti
                lastPos = ti
                positions.push(ti)
                qi++
            }
        }

        if (qi < ql.length)
            return { score: -1, positions: [] }

        score -= firstPos

        if (tl.startsWith(ql))
            score += 450

        if (firstPos === 0 || isSeparator(tl.charAt(firstPos - 1)))
            score += 150

        if (acronym(target).toLowerCase().startsWith(ql))
            score += 300

        return { score: score, positions: positions }
    }

    function appScore(app, q) {
        var best = -1
        var bestField = ""
        var bestPositions = []

        var r = score(q, app.name)
        if (r.score >= 0) {
            var s = r.score
            if (s > best) {
                best = s
                bestField = "name"
                bestPositions = r.positions
            }
        }

        r = score(q, app.genericName)
        if (r.score >= 0) {
            s = Math.max(r.score - root.genericPenalty, root.minFieldScore)
            if (s > best) {
                best = s
                bestField = "genericName"
                bestPositions = r.positions
            }
        }

        r = score(q, app.execString)
        if (r.score >= 0) {
            s = Math.max(r.score - root.execPenalty, root.minFieldScore)
            if (s > best) {
                best = s
                bestField = "execString"
                bestPositions = r.positions
            }
        }

        if (app.keywords) {
            for (var j = 0; j < app.keywords.length; j++) {
                r = score(q, app.keywords[j])
                if (r.score >= 0) {
                    s = Math.max(r.score - root.keywordPenalty, root.minFieldScore)
                    if (s > best) {
                        best = s
                        bestField = "keywords"
                        bestPositions = r.positions
                    }
                }
            }
        }

        return { score: best, field: bestField, positions: bestPositions }
    }

    function relatedQueries(query) {
        var result = []
        var entries = historyAdapter ? historyAdapter.entries : undefined
        if (!entries)
            return result

        var q = query.toLowerCase()

        for (var key in entries) {
            if (key === "*")
                continue
            if (key.startsWith(q) || q.startsWith(key)) {
                var delta = Math.abs(key.length - q.length)
                result.push({ key: key, delta: delta })
            }
        }

        result.sort(function(a, b) {
            return a.delta - b.delta
        })

        return result
    }

    function usageBoost(id, query, fuzzyScore, topFuzzy) {
        if (!historyAdapter || !historyAdapter.entries)
            return 0

        var q = query || ""
        if (q.length === 0)
            return 0

        if (!fuzzyScore || fuzzyScore <= 0 || !topFuzzy || topFuzzy <= 0)
            return 0

        var gap = (topFuzzy - fuzzyScore) / topFuzzy
        if (gap > root.boostTolerance)
            return 0

        var now = Date.now() / 1000
        var best = 0

        var related = root.relatedQueries(q)
        for (var i = 0; i < related.length; i++) {
            var r = related[i]
            var bucket = historyAdapter.entries[r.key]
            var rec = bucket ? bucket[id] : undefined
            if (!rec)
                continue

            var days = Math.max(0, (now - rec.last) / 86400)
            var effective = rec.amount * Math.pow(0.5, days / root.halfLifeDays)
            effective /= (r.delta + 1)

            if (effective > best)
                best = effective
        }

        var gbucket = historyAdapter.entries["*"]
        var grec = gbucket ? gbucket[id] : undefined
        if (grec) {
            var gdays = Math.max(0, (now - grec.last) / 86400)
            var globalVal = grec.amount * Math.pow(0.5, gdays / root.halfLifeDays)
            if (globalVal > best)
                best = globalVal
        }

        if (best <= 0)
            return 0

        var factor = root.maxRelativeBoost * Math.min(best / root.usageSaturation, 1)
        return fuzzyScore * factor
    }

    function recordLaunch(entry, query) {
        if (!entry || !entry.id || !historyAdapter)
            return
        if (entry.id === root.searchFallbackId)
            return
        if (entry.id === root.urlFallbackId)
            return
        if (entry.id === root.webSearchId)
            return
        if (entry.id === root.calculatorResultId)
            return
        if (entry.id === root.commandEntryId)
            return
        if (root.searchModeProvider
            && root.searchModeProvider.currentMode === "clipboard")
            return
        if (root.searchModeProvider
            && root.searchModeProvider.currentMode === "file")
            return

        var q = query || ""
        q = q.trim().toLowerCase()
        var bucketKey = q.length > 0 ? q : "*"

        var updated = {}
        var current = historyAdapter.entries

        for (var k in current)
            updated[k] = current[k]

        var bucket = updated[bucketKey]
        var newBucket = {}

        if (bucket) {
            for (var id in bucket)
                newBucket[id] = { amount: bucket[id].amount, last: bucket[id].last }
        }

        var now = Math.floor(Date.now() / 1000)
        var existing = newBucket[entry.id]

        if (existing) {
            var days = Math.max(0, (now - existing.last) / 86400)
            var decayed = existing.amount * Math.pow(0.5, days / root.halfLifeDays)
            existing.amount = Math.min(decayed + 1, root.capAmount)
            existing.last = now
        } else {
            newBucket[entry.id] = { amount: 1, last: now }
        }

        updated[bucketKey] = newBucket
        historyAdapter.entries = updated
    }

    function isUrlQuery(query) {
        var q = query.trim()

        if (/\s/.test(q))
            return false

        if (q.charAt(0) === "?")
            return false

        if (/^https?:\/\//i.test(q))
            return true

        if (/^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}([/:?#].*)?$/.test(q))
            return true

        if (/^localhost([/:?#].*)?$/.test(q))
            return true

        if (/^(\d{1,3}\.){3}\d{1,3}([/:?#].*)?$/.test(q))
            return true

        return false
    }

    function urlFallbackEntry(query) {
        var q = query.trim()
        var url = q

        if (!/^https?:\/\//i.test(url))
            url = "https://" + url

        return {
            app: {
                id: root.urlFallbackId,
                name: 'Open "' + q + '"',
                subtitle: "Open URL in default browser",
                genericName: "",
                icon: "applications-internet",
                execute: function() {
                    Qt.openUrlExternally(url)
                }
            },
            titlePositions: [],
            subtitlePositions: [],
            score: 0
        }
    }

    function searchFallbackEntry(query) {
        var q = query.trim()

        return {
            app: {
                id: root.searchFallbackId,
                name: 'Search the web for "' + q + '"',
                subtitle: "Open in default browser",
                genericName: "Open in default browser",
                icon: "search",
                execute: function() {
                    Qt.openUrlExternally(
                        root.searchEngine + encodeURIComponent(q)
                    )
                }
            },
            titlePositions: [],
            subtitlePositions: [],
            score: 0
        }
    }

    function webSearchEntry(query) {
        var q = query.trim()

        if (q.charAt(0) === "?")
            q = q.substring(1)

        q = q.trim()

        return {
            app: {
                id: root.webSearchId,
                name: 'Search Google for "' + q + '"',
                subtitle: "Open in default browser",
                genericName: "",
                icon: "google",
                execute: function() {
                    Qt.openUrlExternally(
                        root.searchEngine + encodeURIComponent(q)
                    )
                }
            },
            titlePositions: [],
            subtitlePositions: [],
            score: 0
        }
    }

    function calculatorEntry(query) {
        var q = query.trim()

        if (q.charAt(0) === "=")
            q = q.substring(1)

        q = q.trim()

        var parsed = root.evaluateCalc(q)

        if (parsed.state === "empty")
            return null

        if (parsed.state === "incomplete")
            return {
                app: {
                    id: root.calculatorResultId,
                    name: "Continue typing…",
                    subtitle: "Calculator",
                    genericName: "",
                    icon: "accessories-calculator-symbolic",
                    execute: function() {}
                },
                titlePositions: [],
                subtitlePositions: [],
                score: 0
            }

        if (parsed.state === "invalid")
            return {
                app: {
                    id: root.calculatorResultId,
                    name: "Invalid expression",
                    subtitle: "Calculator",
                    genericName: "",
                    icon: "accessories-calculator-symbolic",
                    execute: function() {}
                },
                titlePositions: [],
                subtitlePositions: [],
                score: 0
            }

        return {
            app: {
                id: root.calculatorResultId,
                name: root.formatCalcResult(parsed.value),
                subtitle: "Copy result to clipboard",
                genericName: "",
                icon: "accessories-calculator-symbolic",
                execute: function() {
                    Quickshell.clipboardText = root.formatCalcResult(parsed.value)
                }
            },
            titlePositions: [],
            subtitlePositions: [],
            score: 0
        }
    }

    function evaluateCalc(expr) {
        var input = expr
        var pos = 0

        function skipWs() {
            while (pos < input.length && /\s/.test(input.charAt(pos)))
                pos++
        }

        function parseExpr() {
            var value = parseTerm()

            while (true) {
                skipWs()
                var c = input.charAt(pos)

                if (c === "+") {
                    pos++
                    value = value + parseTerm()
                } else if (c === "-") {
                    pos++
                    value = value - parseTerm()
                } else
                    break
            }

            return value
        }

        function parseTerm() {
            var value = parseFactor()

            while (true) {
                skipWs()
                var c = input.charAt(pos)

                if (c === "*") {
                    pos++
                    value = value * parseFactor()
                } else if (c === "/") {
                    pos++
                    value = value / parseFactor()
                } else if (c === "%") {
                    pos++
                    value = value % parseFactor()
                } else
                    break
            }

            return value
        }

        function parseFactor() {
            skipWs()
            var c = input.charAt(pos)

            if (c === "-") {
                pos++
                return -parseFactor()
            }

            if (c === "+") {
                pos++
                return parseFactor()
            }

            if (c === "(") {
                pos++
                var v = parseExpr()
                skipWs()

                if (input.charAt(pos) !== ")")
                    return NaN

                pos++
                return v
            }

            var start = pos

            while (pos < input.length && /[0-9.]/.test(input.charAt(pos)))
                pos++

            var num = input.substring(start, pos)

            if (!/^(\d+\.?\d*|\.\d+)$/.test(num))
                return NaN

            return parseFloat(num)
        }

        var result = parseExpr()
        skipWs()

        if (input.length === 0)
            return { state: "empty", value: null }

        if (pos >= input.length && !isNaN(result) && isFinite(result))
            return { state: "success", value: result }

        if (!/^[0-9+\-*/%().\s]*$/.test(input))
            return { state: "invalid", value: null }

        if (root.isIncompleteExpr(input))
            return { state: "incomplete", value: null }

        return { state: "invalid", value: null }
    }

    function isIncompleteExpr(input) {
        var open = 0
        var close = 0

        for (var i = 0; i < input.length; i++) {
            var c = input.charAt(i)

            if (c === "(")
                open++
            else if (c === ")")
                close++
        }

        if (close > open)
            return false

        if (/[+\-*/%(]/.test(input.charAt(input.length - 1)))
            return true

        return open > close
    }

    function formatCalcResult(value) {
        var rounded = Math.round(value * 1e10) / 1e10
        return String(rounded)
    }

    function recordCommand(command) {
        var cmd = (command !== undefined && command !== null) ? String(command).trim() : ""
        if (cmd.length === 0)
            return

        if (root.commandHistory.length > 0
            && root.commandHistory[root.commandHistory.length - 1] === cmd)
            return

        root.commandHistory = root.commandHistory.concat([cmd])
        root.commandHistoryReset()
    }

    function commandHistoryReset() {
        root.commandHistoryCursor = -1
        root.commandHistoryNavActive = false
        root.commandHistoryDraft = ""
    }

    function commandHistoryPrevious(current) {
        var cur = (current !== undefined && current !== null) ? String(current).trim() : ""

        if (root.commandHistory.length === 0)
            return cur

        if (!root.commandHistoryNavActive) {
            root.commandHistoryNavActive = true
            root.commandHistoryCursor = root.commandHistory.length - 1
            root.commandHistoryDraft = cur
            return root.commandHistory[root.commandHistoryCursor]
        }

        root.commandHistoryCursor = Math.max(0, root.commandHistoryCursor - 1)
        return root.commandHistory[root.commandHistoryCursor]
    }

    function commandHistoryNext(current) {
        var cur = (current !== undefined && current !== null) ? String(current).trim() : ""

        if (root.commandHistory.length === 0 || !root.commandHistoryNavActive)
            return cur

        if (root.commandHistoryCursor >= root.commandHistory.length - 1) {
            var draft = root.commandHistoryDraft
            root.commandHistoryReset()
            return draft
        }

        root.commandHistoryCursor = Math.min(root.commandHistory.length - 1, root.commandHistoryCursor + 1)
        return root.commandHistory[root.commandHistoryCursor]
    }

    function launchInTerminal(command) {
        if (!command || command.length === 0)
            return

        commandProcess.command = [root.terminalExecutable].concat(root.terminalArguments).concat([command])
        commandProcess.running = true
    }

    function executeCommandAction(actionId) {
        var command = root.commandActionCommands[actionId]
        if (!command)
            return

        commandProcess.command = command
        commandProcess.running = true
    }

    function findCommandAction(command) {
        var q = command.trim().toLowerCase()

        for (var i = 0; i < root.commandActions.length; i++) {
            var a = root.commandActions[i]

            for (var j = 0; j < a.aliases.length; j++) {
                if (a.aliases[j] === q)
                    return a
            }
        }

        return null
    }

    function commandEntry(query) {
        var q = query.trim()

        if (q.charAt(0) === ">")
            q = q.substring(1)

        q = q.trim()

        if (q.length === 0)
            return null

        var action = root.findCommandAction(q)

        if (action)
            return {
                app: {
                    id: root.commandEntryId,
                    name: action.title,
                    subtitle: action.subtitle,
                    genericName: "",
                    icon: action.icon,
                    execute: function() { root.recordCommand(q); action.execute() }
                },
                titlePositions: [],
                subtitlePositions: [],
                score: 0
            }

        return {
            app: {
                id: root.commandEntryId,
                name: 'Run "' + q + '"',
                subtitle: "Run in terminal",
                genericName: "",
                icon: "utilities-terminal-symbolic",
                execute: function() { root.recordCommand(q); root.launchInTerminal(q) }
            },
            titlePositions: [],
            subtitlePositions: [],
            score: 0
        }
    }

    function parseCliphist(data) {
        var result = []
        var lines = data.split("\n")

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            if (line.length === 0)
                continue

            var idx = line.indexOf("\t")
            var clipId = idx >= 0 ? line.substring(0, idx) : line
            var content = idx >= 0 ? line.substring(idx + 1) : line

            if (content.length === 0)
                continue

            result.push({
                app: root.makeClipboardApp(clipId, content, root.formatClipboardPreview(content)),
                titlePositions: [],
                subtitlePositions: [],
                score: 0
            })
        }

        return result
    }

    function resolveClipboardDb() {
        var xdg = Quickshell.env("XDG_CACHE_HOME")
        var base = (xdg && xdg.length > 0)
            ? xdg
            : (Quickshell.env("HOME") + "/.cache")

        return base + "/cliphist/db"
    }

    function resolveFileRoots() {
        var home = Quickshell.env("HOME") || ""
        var roots = []

        var xdgConfig = Quickshell.env("XDG_CONFIG_HOME")
        roots.push((xdgConfig && xdgConfig.length > 0)
            ? xdgConfig
            : home + "/.config")

        roots.push(home + "/Projects")
        roots.push(home + "/Documents")
        roots.push(home + "/Downloads")

        return roots
    }

    function fileBasename(path) {
        var idx = path.lastIndexOf("/")
        return idx >= 0 ? path.substring(idx + 1) : path
    }

    function fileParentPath(path) {
        var idx = path.lastIndexOf("/")
        return idx >= 0 ? path.substring(0, idx) : ""
    }

    function parseFd(data) {
        var result = []
        var lines = data.split("\n")

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line.length === 0)
                continue

            result.push(line)
        }

        return result
    }

    function makeFileApp(path, name, parent) {
        return {
            id: root.fileEntryId + ":" + path,
            path: path,
            name: name,
            subtitle: parent,
            genericName: parent,
            icon: root.fileIcon,
            execute: root.fileExecute
        }
    }

    function makeFileResult(path, query, entryScore) {
        var name = root.fileBasename(path)
        var parent = root.fileParentPath(path)

        var tp = score(query, name)
        var subtitlePositions = []

        var sp = score(query, parent)
        if (sp.score > 0)
            subtitlePositions = sp.positions

        return {
            app: root.makeFileApp(path, name, parent),
            titlePositions: tp.score > 0 ? tp.positions : [],
            subtitlePositions: subtitlePositions,
            score: entryScore
        }
    }

    function fileScoresBefore(a, b) {
        if (a.e !== b.e)
            return a.e > b.e
        if (a.s !== b.s)
            return a.s > b.s
        return a.i < b.i
    }

    function fileTopInsert(top, score, index, exact) {
        var item = { s: score, i: index, e: exact ? 1 : 0 }

        if (top.length >= root.fileResultLimit) {
            if (!root.fileScoresBefore(item, top[top.length - 1]))
                return

            top[top.length - 1] = item
            var k = top.length - 1
            while (k > 0 && root.fileScoresBefore(top[k], top[k - 1])) {
                var tmp = top[k - 1]
                top[k - 1] = top[k]
                top[k] = tmp
                k--
            }
            return
        }

        var pos = 0
        while (pos < top.length && root.fileScoresBefore(top[pos], item))
            pos++
        top.splice(pos, 0, item)
    }

    function fileScanStart(fq) {
        root.fileScanGen++
        root.fileScanCursor = 0
        root.fileScanTop = []
        root.fileScanQuery = fq
        root.fileScanPaths = root.filePaths
        fileScanTimer.start()
    }

    function fileScanStep() {
        var gen = root.fileScanGen
        var fq = root.fileScanQuery
        var paths = root.fileScanPaths
        var n = paths.length
        var end = Math.min(root.fileScanCursor + root.fileChunkSize, n)
        var fTop = root.fileScanTop

        for (var i = root.fileScanCursor; i < end; i++) {
            var fPath = paths[i]
            var fName = root.fileBasename(fPath)
            var fRes = score(fq, fName)
            if (fRes.score < 0)
                fRes = score(fq, fPath)
            if (fRes.score > 0)
                root.fileTopInsert(fTop, fRes.score, i, String(fName).trim().toLowerCase() === fq)
        }

        root.fileScanCursor = end

        if (gen !== root.fileScanGen)
            return

        if (end >= n) {
            root.fileScanFinish()
            return
        }

        fileScanTimer.start()
    }

    function fileScanFinish() {
        var fq = root.fileScanQuery
        var paths = root.fileScanPaths
        var fTop = root.fileScanTop

        if (fTop.length === 0) {
            apps = [root.noFileMatchEntry()]
            return
        }

        var fApps = []
        for (var ti = 0; ti < fTop.length; ti++)
            fApps.push(root.makeFileResult(paths[fTop[ti].i], fq, fTop[ti].s))
        apps = fApps
    }

    function fileScanCancel() {
        fileScanTimer.stop()
        root.fileScanGen++
    }

    function loadFileIndex() {
        if (root.fileBusy || root.fileLoaded)
            return

        root.fileBusy = true
        fileProcess.command = ["fd", "--type", "f", "."].concat(root.fileRoots)
        fileProcess.running = true
    }

    function runCliphist() {
        if (root.clipboardBusy || root.clipboardLoaded)
            return

        root.clipboardBusy = true
        cliphistProcess.running = true
    }

    function clipboardDatabaseChanged() {
        if (!root.clipboardWatchActive || root.clipboardBusy)
            return

        root.clipboardRefreshing = true
        root.clipboardBusy = true
        root.clipboardRefreshStarted()
        cliphistProcess.running = true
    }

    function makeClipboardApp(clipId, content, preview) {
        return {
            id: clipId,
            clipId: clipId,
            clipContent: content,
            name: preview,
            subtitle: "Clipboard",
            genericName: "Clipboard",
            icon: "edit-paste-symbolic",
            execute: function() { root.copyClipboardEntry(clipId) }
        }
    }

    function formatClipboardPreview(text) {
        if (!text)
            return text

        if (/^\[\[ binary/.test(text.trim()))
            return text

        var preview = text
            .replace(/\r\n/g, "\n")
            .replace(/\r/g, "\n")
            .split("\n")
            .map(function(line) { return line.trim() })
            .filter(function(line) { return line.length > 0 })
            .join(" ↵ ")

        preview = preview.replace(/\t/g, " ")
        preview = preview.replace(/\s+/g, " ")
        preview = preview.trim()

        if (preview.length > 100) {
            var cut = preview.substring(0, 100)
            var lastSpace = cut.lastIndexOf(" ")
            if (lastSpace > 0)
                cut = cut.substring(0, lastSpace)
            preview = cut + "…"
        }

        return preview
    }

    function copyClipboardEntry(clipId) {
        if (!clipId || clipId.length === 0)
            return

        clipdecodeProcess.command = ["cliphist", "decode", String(clipId)]
        clipdecodeProcess.running = true
    }

    function deleteClipboardEntry(clipId) {
        if (!clipId || clipId.length === 0)
            return
        if (root.clipdeletePending !== undefined)
            return

        root.clipdeletePending = String(clipId)
        clipdeleteProcess.stdinEnabled = true
        clipdeleteProcess.running = true
    }

    function wipeClipboardHistory() {
        if (clipwipeProcess.running)
            return
        clipwipeProcess.running = true
    }

    function removeClipboardEntry(clipId) {
        var updated = []

        for (var i = 0; i < root.clipboardCache.length; i++) {
            if (root.clipboardCache[i].app.clipId !== clipId)
                updated.push(root.clipboardCache[i])
        }

        root.clipboardCache = updated
        root.refilter()
        root.clipboardDeleted(clipId)
    }

    function noClipboardEntry() {
        return {
            app: {
                id: root.clipboardEntryId,
                name: "Clipboard History",
                subtitle: "No clipboard entries",
                genericName: "",
                icon: "edit-paste-symbolic",
                execute: function() {}
            },
            titlePositions: [],
            subtitlePositions: [],
            score: 0
        }
    }

    function fileEntry() {
        return {
            app: {
                id: root.fileEntryId,
                name: "File Search",
                subtitle: "No files found",
                genericName: "",
                icon: "folder-documents-symbolic",
                execute: function() {}
            },
            titlePositions: [],
            subtitlePositions: [],
            score: 0
        }
    }

    function noFileMatchEntry() {
        return {
            app: {
                id: root.fileEntryId,
                name: "File Search",
                subtitle: "No matching files",
                genericName: "",
                icon: "folder-documents-symbolic",
                execute: function() {}
            },
            titlePositions: [],
            subtitlePositions: [],
            score: 0
        }
    }

    function noMatchClipboardEntry() {
        return {
            app: {
                id: root.clipboardEntryId,
                name: "Clipboard History",
                subtitle: "No matching clipboard entries",
                genericName: "",
                icon: "edit-paste-symbolic",
                execute: function() {}
            },
            titlePositions: [],
            subtitlePositions: [],
            score: 0
        }
    }

    function refilter() {
        if (!allApps)
            return

        root.fileScanCancel()

        var q = root.query.trim().toLowerCase()

        if (root.searchModeProvider
            && root.searchModeProvider.currentMode === "web") {
            apps = [root.webSearchEntry(root.query)]
            return
        }

        if (root.searchModeProvider
            && root.searchModeProvider.currentMode === "calculator") {
            var calcEntry = root.calculatorEntry(root.query)
            apps = calcEntry ? [calcEntry] : []
            return
        }

        if (root.searchModeProvider
            && root.searchModeProvider.currentMode === "command") {
            var cmdEntry = root.commandEntry(root.query)
            apps = cmdEntry ? [cmdEntry] : []
            return
        }

        if (root.searchModeProvider
            && root.searchModeProvider.currentMode === "file") {
            root.loadFileIndex()

            if (root.filePaths.length === 0) {
                apps = [root.fileEntry()]
                return
            }

            var fq = root.query.trim()
            if (fq.charAt(0) === "/")
                fq = fq.substring(1)
            fq = fq.trim().toLowerCase()

            if (fq.length === 0) {
                var fAll = []
                var fAllCount = Math.min(root.fileResultLimit, root.filePaths.length)
                for (var fa = 0; fa < fAllCount; fa++)
                    fAll.push(root.makeFileResult(root.filePaths[fa], "", 0))
                apps = fAll
                return
            }

            root.fileScanStart(fq)
            return
        }

        if (root.searchModeProvider
            && root.searchModeProvider.currentMode === "clipboard") {
            root.runCliphist()

            if (root.clipboardCache.length === 0) {
                apps = [root.noClipboardEntry()]
                return
            }

            var cq = root.query.trim()
            if (cq.charAt(0) === ":")
                cq = cq.substring(1)
            cq = cq.trim().toLowerCase()

            if (cq.length === 0) {
                apps = root.clipboardCache
                return
            }

            var cScored = []

            for (var i = 0; i < root.clipboardCache.length; i++) {
                var cRes = score(cq, root.clipboardCache[i].app.name)
                if (cRes.score > 0) {
                    var cExact = String(root.clipboardCache[i].app.name)
                        .trim().toLowerCase() === cq

                    cScored.push({
                        fuzzy: cRes.score,
                        index: i,
                        app: root.clipboardCache[i].app,
                        titlePositions: cRes.positions,
                        subtitlePositions: [],
                        isExact: cExact
                    })
                }
            }

            for (var j = 0; j < cScored.length; j++)
                cScored[j].score = cScored[j].fuzzy

            cScored.sort(function(a, b) {
                if (a.isExact !== b.isExact)
                    return a.isExact ? -1 : 1
                if (a.score !== b.score)
                    return b.score - a.score
                return a.index - b.index
            })

            if (cScored.length === 0) {
                apps = [root.noMatchClipboardEntry()]
                return
            }

            apps = cScored.map(function(x) {
                return {
                    app: x.app,
                    titlePositions: x.titlePositions,
                    subtitlePositions: x.subtitlePositions,
                    score: x.score
                }
            })
            return
        }

        if (q.length === 0) {
            var all = allApps.values
            var empty = []

            for (var e = 0; e < all.length; e++)
                empty.push({ app: all[e], titlePositions: [], subtitlePositions: [], score: 0 })

            apps = empty
            return
        }

        var values = allApps.values
        var scored = []
        var topFuzzy = 0

        for (var i = 0; i < values.length; i++) {
            var m = appScore(values[i], q)
            if (m.score > 0) {
                var titlePositions = []
                var subtitlePositions = []

                var rn = score(q, values[i].name)
                if (rn.score > 0)
                    titlePositions = rn.positions

                var rg = score(q, values[i].genericName)
                if (rg.score > 0)
                    subtitlePositions = rg.positions

                if (m.score > topFuzzy)
                    topFuzzy = m.score

                var isExact = values[i].name.trim().toLowerCase() === q

                scored.push({
                    fuzzy: m.score,
                    index: i,
                    app: values[i],
                    titlePositions: titlePositions,
                    subtitlePositions: subtitlePositions,
                    isExact: isExact
                })
            }
        }

        for (var j = 0; j < scored.length; j++) {
            var c = scored[j]
            c.score = c.fuzzy + root.usageBoost(c.app.id, root.query, c.fuzzy, topFuzzy)
        }

        scored.sort(function(a, b) {
            if (a.isExact !== b.isExact)
                return a.isExact ? -1 : 1
            if (a.score !== b.score)
                return b.score - a.score
            return a.index - b.index
        })

        if (scored.length === 0) {
            if (root.isUrlQuery(root.query))
                apps = [root.urlFallbackEntry(root.query)]
            else
                apps = [root.searchFallbackEntry(root.query)]
        } else
            apps = scored.map(function(x) {
                return {
                    app: x.app,
                    titlePositions: x.titlePositions,
                    subtitlePositions: x.subtitlePositions,
                    score: x.score
                }
            })

    }

    onQueryChanged: {
        var newMode = "apps"
        if (root.searchModeProvider) {
            root.searchModeProvider.detectMode(root.query)
            newMode = root.searchModeProvider.currentMode
        }

        if (root.lastMode === "clipboard" && newMode !== "clipboard") {
            root.clipboardLoaded = false
            root.clipboardCache = []
        }

        root.clipboardWatchActive = newMode === "clipboard"
        root.lastMode = newMode
        root.refilter()
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.refilter()
        }
    }
}
