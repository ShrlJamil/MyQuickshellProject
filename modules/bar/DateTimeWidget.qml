import QtQuick
import Quickshell
import "../../components"

// Bar date & time. Click toggles the Notification Center for this screen.
// Shows a small dot badge while there are notifications. Height stays 40px.
Item {
    id: root

    property var screen: null

    readonly property bool centerOpen: NotificationService.centerScreen === root.screen

    implicitWidth: layout.implicitWidth + 24
    implicitHeight: 36

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        radius: 15
        color: root.centerOpen ? ((tap.pressed || hover.hovered) ? Theme.activeSurfaceHover : Theme.activeSurface)
            : ((tap.pressed || hover.hovered) ? Theme.surfaceHover : (Theme.barSegmented ? Theme.barWidgetSurface : "transparent"))
    }

    Row {
        id: layout

        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // e.g. "Tue 2 Apr, 17:23"
            text: Qt.formatDateTime(clock.date, "ddd d MMM, HH:mm")
            color: root.centerOpen ? Theme.onActiveSurface : Theme.icon
            style: Text.Raised
            styleColor: root.centerOpen ? Qt.rgba(1, 1, 1, 0.35) : Theme.textShadow
            font.family: Theme.fontFamily
            font.weight: Font.Black
            font.pixelSize: 14
        }
    }

    // Notification badge — visible while count > 0, independent of DND.
    Rectangle {
        visible: NotificationService.count > 0
        width: 7
        height: 7
        radius: height / 2
        color: root.centerOpen ? Theme.onActiveSurface : Theme.accent

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 4
        anchors.topMargin: 7
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tap
        onTapped: NotificationService.toggleCenter(root.screen)
    }
}
