import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
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

        // Custom SVG battery glyph (assets/best-battery-icon/*). Deliberately
        // NOT Quickshell.iconPath / UPower.iconName - the Qt icon theme (Kora)
        // renders those poorly. Unified single-glyph set: the charging state is
        // baked into its own glyph, so this is one Image + ColorOverlay, no
        // separate flash overlay. Enlarged (38x28) to read as prominently as the
        // Control Center bar button; still comfortably inside the 40px bar.
        Item {
            id: iconBox

            anchors.verticalCenter: parent.verticalCenter
            width: 38
            implicitWidth: 38
            height: 28

            // Charging and critically-low both read as "attention" -> accent.
            readonly property bool attention: BatteryService.charging || BatteryService.low

            readonly property string batteryFile: {
                if (BatteryService.charging)
                    return "battery-charging-svgrepo-com.svg"
                const p = BatteryService.percent
                if (BatteryService.full || p >= 90)
                    return "battery-full-svgrepo-com.svg"
                if (p >= 65)
                    return "battery-75-svgrepo-com.svg"
                if (p >= 35)
                    return "battery-half-svgrepo-com.svg"
                if (p >= 15)
                    return "battery-low-svgrepo-com.svg"
                return "battery-empty-svgrepo-com.svg"
            }

            Image {
                id: battImg

                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 76
                sourceSize.height: 56
                asynchronous: true
                smooth: true
                mipmap: true
                visible: false

                // Safe fallback glyph, never the icon theme.
                property bool failed: false
                source: "file://" + Quickshell.shellPath("assets/best-battery-icon/"
                    + (battImg.failed ? "battery-75-svgrepo-com.svg" : iconBox.batteryFile))
                onStatusChanged: if (status === Image.Error) battImg.failed = true
            }

            ColorOverlay {
                anchors.fill: battImg
                source: battImg
                color: iconBox.attention ? Theme.accent : Theme.text

                // Subtle fade, fires only while the Image reloads on a
                // threshold cross, never while idle.
                opacity: battImg.status === Image.Ready ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(BatteryService.percent) + "%"
            color: BatteryService.low ? Theme.accent : Theme.text
            font.family: Theme.fontFamily
            font.weight: Font.Black
            font.pixelSize: 15
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

        // Sit the popover directly beneath the battery widget. root.parent is the
        // bar's content item, whose width is the monitor's logical width, so
        // (parent.width - widget right edge) is the widget's distance from the
        // screen's right edge; the popover's horizontal centre then tracks the
        // widget's centre, clamped to stay on-screen.
        readonly property real widgetFromRight: root.parent
            ? Math.max(0, root.parent.width - (root.x + root.width))
            : 12
        readonly property real centeredRight:
            pop.widgetFromRight + root.width / 2 - pop.implicitWidth / 2

        anchors {
            top: true
            right: true
        }

        // top: just below the 40px bar with a clean 8px gap (no overlap).
        margins {
            top: 40
            right: Math.max(8, Math.round(pop.centeredRight))
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

            // Snappy scale-fade from directly under the bar icon.
            transformOrigin: Item.Top
            opacity: pop.open ? 1 : 0
            scale: pop.open ? 1 : 0.85
            Behavior on opacity {
                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
            }
            Behavior on scale {
                NumberAnimation { duration: 120; easing.type: Easing.OutBack }
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
