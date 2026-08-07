import QtQml

QtObject {
    id: root

    property string _mode: "apps"

    readonly property string currentMode: _mode

    readonly property string currentIcon:
        _mode === "apps" ? "system-search-symbolic"
        : _mode === "url" ? "applications-internet-symbolic"
        : _mode === "calculator" ? "accessories-calculator-symbolic"
        : _mode === "command" ? "utilities-terminal-symbolic"
        : _mode === "clipboard" ? "edit-paste-symbolic"
        : _mode === "file" ? "folder-documents-symbolic"
        : "web-browser-symbolic"

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

    function detectMode(query) {
        var q = query.trim()

        if (root.isUrlQuery(query))
            root._mode = "url"
        else if (q.charAt(0) === "=")
            root._mode = "calculator"
        else if (q.charAt(0) === ">")
            root._mode = "command"
        else if (q.charAt(0) === "?")
            root._mode = "web"
        else if (q.charAt(0) === ":")
            root._mode = "clipboard"
        else if (q.charAt(0) === "/")
            root._mode = "file"
        else
            root._mode = "apps"
    }
}
