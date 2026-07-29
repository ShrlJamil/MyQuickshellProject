import QtQuick
import Quickshell

PanelWindow {
    id: root

    implicitWidth: 1920
    implicitHeight: 1080

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    aboveWindows: true
    focusable: true

    color: "transparent"

    Rectangle {
        width: 700
        height: 450

        anchors.centerIn: parent

        radius: 20
        color: "#1e1e2e"

        border.width: 1
        border.color: "#44475a"

        Text {
            anchors.centerIn: parent
            text: "Hello Quickshell!"
            color: "white"
            font.pixelSize: 30
        }
    }
}
