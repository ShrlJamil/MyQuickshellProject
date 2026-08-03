import QtQuick
import Quickshell

Item {
    id: root

    visible: false

    readonly property var allApps: DesktopEntries.applications

    property string query: ""
    property var apps: []

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
            score += 300

        if (firstPos === 0 || isSeparator(tl.charAt(firstPos - 1)))
            score += 150

        if (acronym(target).toLowerCase().startsWith(ql))
            score += 400

        return { score: score, positions: positions }
    }

    function appScore(app, q) {
        var best = -1
        var bestField = ""
        var bestPositions = []

        var r = score(q, app.name)
        if (r.score >= 0) {
            var s = r.score * 100
            if (s > best) {
                best = s
                bestField = "name"
                bestPositions = r.positions
            }
        }

        r = score(q, app.genericName)
        if (r.score >= 0) {
            s = r.score * 40
            if (s > best) {
                best = s
                bestField = "genericName"
                bestPositions = r.positions
            }
        }

        r = score(q, app.execString)
        if (r.score >= 0) {
            s = r.score * 10
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
                    s = r.score * 20
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

    function refilter() {
        if (!allApps)
            return

        var q = root.query.toLowerCase()

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

                scored.push({
                    score: m.score,
                    index: i,
                    app: values[i],
                    titlePositions: titlePositions,
                    subtitlePositions: subtitlePositions
                })
            }
        }

        scored.sort(function(a, b) {
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