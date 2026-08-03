import QtQuick
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    property var entry
    property string title: ""
    property string subtitle: ""
    property bool selected: false

    signal activated(var entry)

    height: 64

    radius: 18

    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: {
            root.activated(root.entry)
        }
    }

    color:
    selected
    ? "#313244"
    : hover.hovered
        ? Qt.rgba(1,1,1,0.05)
        : "transparent"
    scale: selected ? 1.01 : 1.0

    Behavior on color {
        ColorAnimation {
            duration: 100
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: 100
        }
    }



    Row {
        anchors.fill: parent
        anchors.margins: 10

        spacing: 12

        IconImage {
            width: 40
            height: 40

            source: Quickshell.iconPath(entry.icon, "application-x-executable")

            asynchronous: true
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            spacing: 2

            Text {
                text: root.title
                color: "white"
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            Text {
                visible: text.length > 0
                text: root.subtitle
                color: "#a6adc8"
                font.pixelSize: 13
                opacity: 0.75
            }
        }
    }
}
