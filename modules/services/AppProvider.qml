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

    property string query: ""
    property var apps: []

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
        var result = ""

        for (var i = 0; i < target.length; i++) {
            var c = target.charAt(i)
            var prev = i > 0 ? target.charAt(i - 1) : ""

            var wordStart = i === 0
                || !isAlphaNum(prev)
                || (isLower(prev) && isUpper(c))

            if (wordStart && isAlphaNum(c))
                result += c.toUpperCase()
        }

        return result
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

    function refilter() {
        if (!allApps)
            return

        var q = root.query.trim().toLowerCase()

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

        apps = scored.map(function(x) {
            return {
                app: x.app,
                titlePositions: x.titlePositions,
                subtitlePositions: x.subtitlePositions,
                score: x.score
            }
        })

    }

    onQueryChanged: refilter()

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.refilter()
        }
    }
}
