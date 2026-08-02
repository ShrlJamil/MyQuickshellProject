import QtQuick
Rectangle {
    id: root

    width: 600

    radius: 22

    color: "#1e1e2e"

    border.width: 1
    border.color: "#44475a"

    property var appProvider

    signal closeRequested()

    implicitHeight: content.implicitHeight + 32

    Column {
        id: content

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right

            margins: 16
        }

        spacing: 12

        SearchBar {
          id: searchBar

          resultList: resultList
          appProvider: root.appProvider

          onActivated: {
            resultList.activate()
            searchBar.text = ""
            root.closeRequested()
          }

          onCloseRequested: {
            searchBar.text = ""
            root.closeRequested()
          }
        }

        ResultContainer {

            visible: searchBar.text.length > 0

            opacity: visible ? 1 : 0

            id: resultContainer

            ResultList {
                id: resultList
                appProvider: root.appProvider
            }

        }
    }
}
