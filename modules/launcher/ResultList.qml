import QtQuick

ListView {
    id: root

    anchors.fill: parent

    clip: true
    spacing: 6

    focus: true

    currentIndex: 0

    model: [
        {
            title: "Firefox",
            subtitle: "Web Browser"
        },
        {
            title: "Kitty",
            subtitle: "Terminal"
        },
        {
            title: "Files",
            subtitle: "File Manager"
        },
        {
            title: "Visual Studio Code",
            subtitle: "Editor"
        }
    ]

    function next() {
        currentIndex = Math.min(currentIndex + 1, count - 1)
        positionViewAtIndex(currentIndex, ListView.Contain)

        console.log("Current:", currentIndex)
    }

    function previous() {
        currentIndex = Math.max(currentIndex - 1, 0)
        positionViewAtIndex(currentIndex, ListView.Contain)
    }

    delegate: ResultItem {

        width: ListView.view.width

        title: modelData.title
        subtitle: modelData.subtitle

        selected: index === ListView.view.currentIndex
    }

    Keys.onPressed: (event) => {

        console.log("KEY:", event.key)

        switch(event.key) {

        case Qt.Key_Down:

            currentIndex = Math.min(currentIndex + 1, count - 1)
            positionViewAtIndex(currentIndex, ListView.Contain)
            event.accepted = true
            break

        case Qt.Key_Up:

            currentIndex = Math.max(currentIndex - 1, 0)
            positionViewAtIndex(currentIndex, ListView.Contain)
            event.accepted = true
            break
        }
    }
}
