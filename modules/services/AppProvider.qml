import QtQuick
import Quickshell

Item {
    id: root

    visible: false

    readonly property var allApps: DesktopEntries.applications

    property string query: ""
    property var apps: []

    function matches(app, q) {
        if (q.length === 0)
            return true

        return app.name.toLowerCase().includes(q)
            || app.genericName.toLowerCase().includes(q)
            || app.execString.toLowerCase().includes(q)
            || (app.keywords && app.keywords.some(k => k.toLowerCase().includes(q)))
    }

    function refilter() {
        if (!allApps)
            return

        var q = root.query.toLowerCase()

        apps = allApps.values.filter(function(app) {
            return matches(app, q)
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