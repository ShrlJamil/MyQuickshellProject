import QtQuick
import "../../components"

FocusScope {
    id: root

    implicitWidth: 560
    implicitHeight: 320

    signal closeRequested()

    Keys.onEscapePressed: root.closeRequested()

    Text {
        id: title

        anchors {
            top: parent.top
            left: parent.left
            topMargin: 26
            leftMargin: 26
        }

        text: "Settings"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 20
        font.weight: Font.DemiBold
    }

    Text {
        anchors {
            top: title.bottom
            left: parent.left
            topMargin: 6
            leftMargin: 26
        }

        text: "Settings are not available yet."
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }
}
