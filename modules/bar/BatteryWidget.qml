import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "../../components"

// Bar battery indicator, sits immediately left of DateTimeWidget. Click toggles
// a small floating Battery Popover for this screen (same PanelWindow +
// HyprlandFocusGrab pattern as NotificationCenter). Height stays 40px.
Item {
    id: root

    property var screen: null

    readonly property bool popoverOpen: BatteryService.popoverScreen === root.screen

    visible: BatteryService.available
    implicitWidth: root.visible ? (layout.implicitWidth + 20) : 0
    implicitHeight: 40

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: 8
        color: (root.popoverOpen || tap.pressed || hover.hovered) ? Theme.surfaceHover : "transparent"
    }

    Row {
        id: layout

        anchors.centerIn: parent
        spacing: 5

        IconImage {
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            source: Quickshell.iconPath(BatteryService.iconName, "battery-symbolic")
            asynchronous: true
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(BatteryService.percent) + "%"
            color: BatteryService.low ? Theme.accent : Theme.text
            font.weight: Font.DemiBold
            font.pixelSize: 13
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tap
        onTapped: BatteryService.togglePopover(root.screen)
    }

    // ---- Battery Popover ---------------------------------------------------
    PanelWindow {
        id: pop

        screen: root.screen

        readonly property bool open: BatteryService.popoverScreen === root.screen
        property bool closing: false

        visible: pop.open || pop.closing

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        anchors {
            top: true
            right: true
        }

        margins {
            top: 44
            right: 12
        }

        implicitWidth: 248
        implicitHeight: card.implicitHeight + 16

        color: "transparent"

        function close() {
            BatteryService.closePopover()
        }

        onOpenChanged: {
            if (pop.open) {
                pop.closing = false
                hideTimer.stop()
                card.forceActiveFocus()
            } else if (pop.visible) {
                pop.closing = true
                hideTimer.restart()
            }
        }

        Timer {
            id: hideTimer
            interval: 200
            onTriggered: pop.closing = false
        }

        HyprlandFocusGrab {
            windows: [pop]
            active: pop.open
            onCleared: pop.close()
        }

        Rectangle {
            id: card

            anchors.fill: parent
            anchors.margins: 8
            radius: Theme.cornerRadius
            color: Theme.background
            border.width: 1
            border.color: Theme.surfaceHover

            implicitHeight: col.implicitHeight + 32

            opacity: pop.open ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) {
                    pop.close()
                    event.accepted = true
                }
            }

            Column {
                id: col

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 16
                }
                spacing: 10

                Text {
                    text: "Battery"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Row {
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(BatteryService.percent) + "%"
                        color: BatteryService.low ? Theme.accent : Theme.text
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: BatteryService.statusText
                        color: Theme.textDim
                        font.pixelSize: 12
                    }
                }

                Repeater {
                    model: BatteryService.popoverRows

                    delegate: Row {
                        id: infoRow

                        required property var modelData

                        width: col.width

                        Text {
                            width: parent.width * 0.42
                            text: infoRow.modelData.label
                            color: Theme.textDim
                            font.pixelSize: 12
                        }

                        Text {
                            width: parent.width * 0.58
                            horizontalAlignment: Text.AlignRight
                            text: infoRow.modelData.value
                            color: Theme.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}
