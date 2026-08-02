import QtQuick

Rectangle {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool selected: false

    width: parent ? parent.width : 500
    height: 58

    radius: 10

    color: selected ? "#313244" : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: 12

        spacing: 14

        Rectangle {
            width: 34
            height: 34
            radius: 8
            color: "#fab387"
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            spacing: 2

            Text {
                text: root.title
                color: "white"
                font.pixelSize: 16
            }

            Text {
                text: root.subtitle
                color: "#a6adc8"
                font.pixelSize: 12
            }
        }
    }
}
