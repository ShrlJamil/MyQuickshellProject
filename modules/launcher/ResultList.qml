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

    model: appProvider ? appProvider.apps : []

    height: appProvider && appProvider.query.length > 0
        ? Math.min(contentHeight, maxHeight)
        : 0

    Behavior on height {
        NumberAnimation {
            duration: 150
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

    function activate() {
        if (currentItem)
            currentItem.launch()
    }

    delegate: ResultItem {

        width: ListView.view.width

        entry: modelData

        title: modelData.name
        subtitle: modelData.genericName

        selected: index === ListView.view.currentIndex
    }

    Connections {
        target: appProvider

        function onAppsChanged() {
            Qt.callLater(function() {
                if (count > 0)
                    currentIndex = 0
            })
        }
    }
}
