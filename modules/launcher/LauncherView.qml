import QtQuick
import "../services"
import "../../components"

Rectangle {
    id: root

    width: 600

    radius: 40

    color: Theme.background

    property var appProvider

    property string preselectId: ""
    property int preselectIndex: -1

    signal closeRequested()

    SearchModeProvider {
        id: searchModeProvider
    }

    onAppProviderChanged: {
        if (appProvider)
            appProvider.searchModeProvider = searchModeProvider
    }

    function reset() {
        searchBar.text = ""
        if (appProvider) {
            appProvider.query = ""
            appProvider.commandHistoryReset()
        }
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
          searchModeProvider: searchModeProvider

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

    Connections {
        target: appProvider

        function onQueryChanged() {
            searchModeProvider.detectMode(appProvider.query)
        }

        function onClipboardRefreshStarted() {
            var apps = appProvider ? appProvider.apps : []
            var i = resultList.currentIndex
            preselectIndex = i

            if (i >= 0 && apps && i < apps.length && apps[i].app.clipId)
                preselectId = apps[i].app.clipId
            else
                preselectId = ""
        }

        function onClipboardRefreshed() {
            Qt.callLater(function() {
                var apps = appProvider ? appProvider.apps : []
                var idx = -1

                if (apps && apps.length > 0) {
                    if (preselectId && preselectId.length > 0) {
                        for (var i = 0; i < apps.length; i++) {
                            if (apps[i].app.clipId === preselectId) {
                                idx = i
                                break
                            }
                        }
                    }

                    if (idx < 0 && preselectIndex >= 0)
                        idx = Math.min(preselectIndex, apps.length - 1)

                    if (idx < 0)
                        idx = 0

                    resultList.currentIndex = idx
                    resultList.positionViewAtIndex(idx, ListView.Contain)
                } else {
                    resultList.currentIndex = -1
                }
            })
        }
    }
}
