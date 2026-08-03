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

    function reset() {
        searchBar.text = ""
        if (appProvider)
            appProvider.query = ""
        resultList.currentIndex = 0
    }

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
            resultList.activateCurrent()
          }

          onCloseRequested: {
            root.closeRequested()
          }
        }

        ResultContainer {
            id: resultContainer

            resultsHeight: resultList.height

            ResultList {
                id: resultList
                appProvider: root.appProvider

                onActivated: {
                  root.closeRequested()
                }
            }
        }
    }
}
