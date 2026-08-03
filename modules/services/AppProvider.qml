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
            return 0

        var ql = q.toLowerCase()
        var tl = target.toLowerCase()

        var qi = 0
        var lastPos = -1
        var firstPos = -1
        var score = 0

        for (var ti = 0; ti < tl.length && qi < ql.length; ti++) {
            if (tl.charAt(ti) === ql.charAt(qi)) {
                score += 10
                if (lastPos >= 0)
                    score -= ti - lastPos - 1
                if (firstPos < 0)
                    firstPos = ti
                lastPos = ti
                qi++
            }
        }

        if (qi < ql.length)
            return -1

        score -= firstPos

        if (tl.startsWith(ql))
            score += 300

        if (firstPos === 0 || isSeparator(tl.charAt(firstPos - 1)))
            score += 150

        if (acronym(target).toLowerCase().startsWith(ql))
            score += 400

        return score
    }

    function appScore(app, q) {
        var best = -1
        var s = score(q, app.name)
        if (s >= 0)
            s *= 100
        if (s > best)
            best = s

        s = score(q, app.genericName)
        if (s >= 0)
            s *= 40
        if (s > best)
            best = s

        s = score(q, app.execString)
        if (s >= 0)
            s *= 10
        if (s > best)
            best = s

        if (app.keywords) {
            for (var j = 0; j < app.keywords.length; j++) {
                var ks = score(q, app.keywords[j])
                if (ks >= 0)
                    ks *= 20
                if (ks > best)
                    best = ks
            }
        }

        return best
    }

    function refilter() {
        if (!allApps)
            return

        var q = root.query.toLowerCase()

        if (q.length === 0) {
            apps = allApps.values
            return
        }

        var values = allApps.values
        var scored = []

        for (var i = 0; i < values.length; i++) {
            var s = appScore(values[i], q)
            if (s > 0)
                scored.push({ score: s, index: i, app: values[i] })
        }

        scored.sort(function(a, b) {
            if (a.score !== b.score)
                return b.score - a.score
            return a.index - b.index
        })

        apps = scored.map(function(x) {
            return x.app
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