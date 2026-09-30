import QtQuick
import "../services"
import "../../components"

Rectangle {
    id: root

    width: 600

    radius: 40

    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.surfaceOpacity)

    // Shared glass highlight (see ControlTile): full-bleed rect with the
    // panel's own radius (no border, so no inset is needed); falloff shaped
    // by stops. Below content.
    Rectangle {
        anchors.fill: parent
        radius: 40
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.rgba(1, 1, 1, Theme.materialHighlightOpacity)
            }
            GradientStop {
                position: 0.4
                color: "transparent"
            }
            GradientStop {
                position: 1
                color: "transparent"
            }
        }
    }

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
