import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects
import "../../components"
import "../services"

// Desktop weather card, minimalist: location on top, one big
// temperature, condition at the bottom. Data comes from
// WeatherService (one fetch every 30 minutes); the card itself has
// no timers, no animations and no effects beyond one tinted icon,
// so it repaints only when the data changes.
Rectangle {
    id: root

    signal activated()

    width: height
    radius: 22
    color: Qt.rgba(Theme.panelBackground.r, Theme.panelBackground.g, Theme.panelBackground.b, 0.92)

    // Location, top.
    Row {
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: 16
            topMargin: 14
        }

        spacing: 5

        Text {
            text: WeatherService.locationName
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.Black
        }

        Item {
            width: 11
            height: 11
            anchors.top: parent.top
            anchors.topMargin: 2

            Image {
                id: locArrow

                anchors.fill: parent
                source: "file://" + Quickshell.shellPath("assets/weather-location-arrow.svg")
                sourceSize.width: 22
                sourceSize.height: 22
                fillMode: Image.PreserveAspectFit
                visible: false
            }

            ColorOverlay {
                anchors.fill: locArrow
                source: locArrow
                visible: locArrow.status === Image.Ready
                color: Theme.textDim
            }
        }
    }

    // Big temperature, under the location.
    Text {
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: 16
            topMargin: 40
        }

        text: WeatherService.available ? WeatherService.temperature + "°" : "--°"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 54
        font.weight: Font.Light
    }

    // Condition, bottom: icon + label, with today's range under it.
    Column {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 16
            rightMargin: 16
            bottomMargin: 14
        }

        spacing: 3

        Row {
            spacing: 7

            Item {
                width: 24
                height: 24

                Image {
                    id: condIcon

                    anchors.fill: parent
                    source: WeatherService.iconName !== "" ? "file://" + Quickshell.shellPath("assets/" + WeatherService.iconName + ".svg") : ""
                    sourceSize.width: 48
                    sourceSize.height: 48
                    fillMode: Image.PreserveAspectFit
                    visible: false
                }

                ColorOverlay {
                    anchors.fill: condIcon
                    source: condIcon
                    visible: condIcon.status === Image.Ready
                    color: Theme.text
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                text: WeatherService.available ? WeatherService.condition : "Loading"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 14
            }
        }

        Row {
            spacing: 10
            visible: WeatherService.available

            Text {
                text: "High " + WeatherService.highToday + "°"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            Text {
                text: "Low " + WeatherService.lowToday + "°"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onClicked: root.activated()
    }
}
