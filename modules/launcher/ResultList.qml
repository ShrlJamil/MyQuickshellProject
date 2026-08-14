import QtQuick
import QtQuick.Controls

ListView {
    id: root

    anchors {
        top: parent.top
        left: parent.left
        right: parent.right
    }

    clip: true
    spacing: 6

    currentIndex: 0

    property var appProvider
    property int maxHeight: 360

    property int deletePendingIndex: -1

    signal activated(var entry)

    model: appProvider ? appProvider.apps : []

    height: appProvider && appProvider.query.length > 0
        ? Math.min(contentHeight, maxHeight)
        : 0

    Behavior on height {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }

    function next() {
        if (count === 0)
            return

        if (currentIndex < 0)
            currentIndex = 0
        else
            currentIndex = Math.min(currentIndex + 1, count - 1)

        positionViewAtIndex(currentIndex, ListView.Contain)
    }

    function previous() {
        if (count === 0)
            return

        if (currentIndex < 0)
            currentIndex = 0
        else
            currentIndex = Math.max(currentIndex - 1, 0)

        positionViewAtIndex(currentIndex, ListView.Contain)
    }

    function activate(entry, index) {
        if (!entry)
            return

        if (index >= 0)
            currentIndex = index

        entry.execute()
        if (appProvider)
            appProvider.recordLaunch(entry, appProvider.query)
        root.activated(entry)
    }

    function activateCurrent() {
        if (appProvider && appProvider.query.trim().length === 0)
            return

        if (appProvider && appProvider.apps.length === 0)
            return

        if (currentItem)
            activate(currentItem.entry, currentIndex)
    }

    delegate: ResultItem {

        width: ListView.view.width

        entry: modelData.app

        title: modelData.app.name
        subtitle: modelData.app.genericName

        titlePositions: modelData.titlePositions
        subtitlePositions: modelData.subtitlePositions

        selected: index === ListView.view.currentIndex

        onActivated: {
            root.activate(entry, index)
        }
    }

    Connections {
        target: appProvider

        function onAppsChanged() {
            Qt.callLater(function() {
                var idx = root.deletePendingIndex
                root.deletePendingIndex = -1

                if (count > 0) {
                    if (idx >= 0)
                        idx = Math.min(idx, count - 1)
                    else
                        idx = 0

                    root.currentIndex = idx
                    root.positionViewAtIndex(idx, ListView.Contain)
                }
            })
        }

        function onClipboardDeleted(clipId) {
            root.deletePendingIndex = root.currentIndex
        }
    }
}
