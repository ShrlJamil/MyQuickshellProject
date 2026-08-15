import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../components"

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
                out += '<font color="' + Theme.accent + '">' + escaped + "</font>"
            else
                out += escaped
        }

        return out
    }

    height: 64

    radius: 22

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
    ? Theme.surface
    : hover.hovered
        ? Theme.surfaceHover
        : "transparent"
    Behavior on color {
        ColorAnimation {
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
                color: Theme.text
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            Text {
                visible: text.length > 0
                text: root.rich(root.subtitle, root.subtitlePositions)
                textFormat: Text.RichText
                color: Theme.textDim
                font.pixelSize: 13
                opacity: 0.75
            }
        }
    }
}
