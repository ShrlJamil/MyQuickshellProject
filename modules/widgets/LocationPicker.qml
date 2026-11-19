import QtQuick
import Quickshell
import "../../components"
import "../services"

// Location picker for the desktop weather card. Loaded lazily by
// DesktopWidgets (Loader, active only while open): nothing in this
// file exists at shell startup, and its network work - city search
// and nearby places - happens only while it is open. Picking a place
// stores it per machine via WeatherService (state dir, outside the
// repo); "Automatic (IP)" clears the choice back to IP detection.
Rectangle {
    id: root

    signal closeRequested()

    readonly property bool searching: searchInput.text.trim().length >= 2
    readonly property var shownPlaces: root.searching ? WeatherService.searchResults : WeatherService.nearbyPlaces

    width: 300
    height: Math.min(col.implicitHeight + 20, 392)
    radius: 18
    color: Theme.panelBackground
    clip: true

    Component.onCompleted: {
        WeatherService.refreshNearby()
        searchInput.forceActiveFocus()
    }

    Keys.onEscapePressed: root.closeRequested()

    Timer {
        id: debounce

        interval: 350
        onTriggered: WeatherService.searchCities(searchInput.text)
    }

    Column {
        id: col

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 10
            rightMargin: 10
            topMargin: 10
        }

        spacing: 4

        Rectangle {
            width: parent.width
            height: 34
            radius: 10
            color: Theme.backgroundSunken

            TextInput {
                id: searchInput

                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 10
                }

                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13

                onTextChanged: debounce.restart()

                Keys.onEscapePressed: root.closeRequested()
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 10
                    verticalCenter: parent.verticalCenter
                }

                visible: searchInput.text.length === 0
                text: "Search city"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }

        Rectangle {
            width: parent.width
            height: 42
            radius: 10
            color: autoHover.containsMouse ? Theme.surfaceHover : "transparent"

            Column {
                anchors {
                    left: parent.left
                    leftMargin: 8
                    verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Automatic (IP)"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                Text {
                    text: WeatherService.detectedName !== "" ? WeatherService.detectedName : "Detect from network"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            Rectangle {
                anchors {
                    right: parent.right
                    rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }

                width: 8
                height: 8
                radius: 4
                color: Theme.accent
                visible: WeatherService.locationMode === "auto"
            }

            MouseArea {
                id: autoHover

                anchors.fill: parent
                hoverEnabled: true

                onClicked: {
                    WeatherService.useAuto()
                    root.closeRequested()
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.surfaceHover
        }

        Text {
            visible: !root.searching && WeatherService.nearbyPlaces.length > 0
            text: "NEARBY"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1.1
            leftPadding: 8
            topPadding: 4
        }

        Text {
            visible: root.searching && WeatherService.searchBusy
            text: "Searching..."
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 12
            leftPadding: 8
            topPadding: 4
        }

        Text {
            visible: root.searching && !WeatherService.searchBusy && WeatherService.searchDone && WeatherService.searchResults.length === 0
            text: "No results"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 12
            leftPadding: 8
            topPadding: 4
        }

        Repeater {
            model: root.shownPlaces

            delegate: Rectangle {
                required property var modelData

                width: col.width
                height: 42
                radius: 10
                color: rowHover.containsMouse ? Theme.surfaceHover : "transparent"

                Column {
                    anchors {
                        left: parent.left
                        leftMargin: 8
                        verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: modelData.name
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }

                    Text {
                        visible: modelData.region !== ""
                        text: modelData.region
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    anchors {
                        right: parent.right
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }

                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.accent
                    visible: WeatherService.locationMode === "manual"
                        && modelData.name === WeatherService.locationName
                        && Math.abs(modelData.latitude - WeatherService.latitude) < 0.01
                }

                MouseArea {
                    id: rowHover

                    anchors.fill: parent
                    hoverEnabled: true

                    onClicked: {
                        WeatherService.usePlace(modelData.name, modelData.latitude, modelData.longitude)
                        root.closeRequested()
                    }
                }
            }
        }
    }
}
