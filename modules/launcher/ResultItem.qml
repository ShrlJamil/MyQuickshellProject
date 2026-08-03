import QtQuick
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    property var entry
    property string title: ""
    property string subtitle: ""
    property var titlePositions: []
    property var subtitlePositions: []
    property bool selected: false

    signal activated(var entry)

    function rich(text, positions) {
        var out = ""

        for (var i = 0; i < text.length; i++) {
            var c = text.charAt(i)
            var escaped = c === "&" ? "&amp;"
                : c === "<" ? "&lt;"
                : c === ">" ? "&gt;"
                : c === "\"" ? "&quot;"
                : c === "'" ? "&#39;"
                : c

            if (positions.indexOf(i) >= 0)
                out += '<font color="#89b4fa">' + escaped + "</font>"
            else
                out += escaped
        }

        return out
    }

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
                text: root.rich(root.title, root.titlePositions)
                textFormat: Text.RichText
                color: "white"
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            Text {
                visible: text.length > 0
                text: root.rich(root.subtitle, root.subtitlePositions)
                textFormat: Text.RichText
                color: "#a6adc8"
                font.pixelSize: 13
                opacity: 0.75
            }
        }
    }
}
