import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "../../components"

// Standalone floating panel (one per screen) opened from the bar's Date & Time.
// Top: a visual month calendar. Below: the notification list with Clear all and
// Do Not Disturb. Not part of DynamicCenter.
PanelWindow {
    id: root

    required property var modelData

    screen: modelData.screen

    readonly property bool open: NotificationService.centerScreen === modelData.screen
    property bool closing: false

    visible: root.open || root.closing

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        right: true
    }

    margins {
        top: 48
        right: 12
    }

    implicitWidth: 380
    implicitHeight: 560

    color: "transparent"

    function close() {
        NotificationService.closeCenter()
    }

    onOpenChanged: {
        if (root.open) {
            root.closing = false
            hideTimer.stop()
            panel.forceActiveFocus()
        } else if (root.visible) {
            root.closing = true
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: 200
        onTriggered: root.closing = false
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: root.close()
    }

    Rectangle {
        id: panel

        anchors.fill: parent
        anchors.margins: 8
        radius: Theme.cornerRadius
        color: Theme.background
        border.width: 1
        border.color: Theme.surfaceHover

        opacity: root.open ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            }
        }

        // ---- Calendar --------------------------------------------------------
        Column {
            id: calendar

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 16
            }
            spacing: 8

            // First day of the displayed month.
            property var view: {
                const d = new Date()
                return new Date(d.getFullYear(), d.getMonth(), 1)
            }
            readonly property var today: new Date()
            readonly property int vYear: calendar.view.getFullYear()
            readonly property int vMonth: calendar.view.getMonth()
            readonly property int firstWeekday: new Date(calendar.vYear, calendar.vMonth, 1).getDay()
            readonly property int daysInMonth: new Date(calendar.vYear, calendar.vMonth + 1, 0).getDate()
            readonly property real cell: Math.floor(width / 7)

            function shift(months) {
                calendar.view = new Date(calendar.vYear, calendar.vMonth + months, 1)
            }
            function resetToday() {
                const d = new Date()
                calendar.view = new Date(d.getFullYear(), d.getMonth(), 1)
            }

            Row {
                width: parent.width
                height: 24

                Text {
                    id: prevBtn
                    width: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: "‹"
                    color: prevHover.hovered ? Theme.text : Theme.textDim
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                    HoverHandler { id: prevHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: calendar.shift(-1) }
                }

                Text {
                    width: parent.width - prevBtn.width - nextBtn.width - todayBtn.width
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(calendar.view, "MMMM yyyy")
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    id: todayBtn
                    width: 44
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Today"
                    color: todayHover.hovered ? Theme.accent : Theme.textDim
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    HoverHandler { id: todayHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: calendar.resetToday() }
                }

                Text {
                    id: nextBtn
                    width: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: "›"
                    color: nextHover.hovered ? Theme.text : Theme.textDim
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                    HoverHandler { id: nextHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: calendar.shift(1) }
                }
            }

            Row {
                width: parent.width
                Repeater {
                    model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                    delegate: Text {
                        required property var modelData
                        width: calendar.cell
                        height: 20
                        text: modelData
                        color: Theme.textMuted
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Grid {
                width: parent.width
                columns: 7

                Repeater {
                    model: 42

                    delegate: Item {
                        id: dayCell
                        required property int index

                        width: calendar.cell
                        height: calendar.cell

                        readonly property int dayNum: index - calendar.firstWeekday + 1
                        readonly property bool inMonth: dayNum >= 1 && dayNum <= calendar.daysInMonth
                        readonly property bool isToday: inMonth
                            && calendar.vYear === calendar.today.getFullYear()
                            && calendar.vMonth === calendar.today.getMonth()
                            && dayNum === calendar.today.getDate()

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) - 6
                            height: width
                            radius: height / 2
                            color: dayCell.isToday ? Theme.accent : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            text: dayCell.inMonth ? dayCell.dayNum : ""
                            color: dayCell.isToday ? Theme.background
                                : dayCell.inMonth ? Theme.text : Theme.textMuted
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }

        Rectangle {
            id: divider
            anchors {
                top: calendar.bottom
                left: parent.left
                right: parent.right
                topMargin: 14
                leftMargin: 16
                rightMargin: 16
            }
            height: 1
            color: Theme.surfaceHover
        }

        // ---- Notifications header ------------------------------------------
        Item {
            id: notifHeader
            anchors {
                top: divider.bottom
                left: parent.left
                right: parent.right
                topMargin: 12
                leftMargin: 16
                rightMargin: 16
            }
            height: 20

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: Theme.text
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: NotificationService.count > 0
                text: "Clear all"
                color: clearHover.hovered ? Theme.text : Theme.textDim
                font.pixelSize: 12
                HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: NotificationService.clearAll() }
            }
        }

        // ---- Do Not Disturb ---------------------------------------------------
        Item {
            id: dndRow
            anchors {
                top: notifHeader.bottom
                left: parent.left
                right: parent.right
                topMargin: 10
                leftMargin: 16
                rightMargin: 16
            }
            height: 22

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Do Not Disturb"
                color: Theme.textDim
                font.pixelSize: 12
            }

            Rectangle {
                id: dndSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 20
                radius: height / 2
                color: NotificationService.doNotDisturb ? Theme.accent : Theme.surface

                Rectangle {
                    width: 16
                    height: 16
                    radius: height / 2
                    color: Theme.text
                    y: 2
                    x: NotificationService.doNotDisturb ? parent.width - width - 2 : 2
                    Behavior on x {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: NotificationService.toggleDnd() }
            }
        }

        // ---- List / empty state ---------------------------------------------
        Text {
            anchors {
                top: dndRow.bottom
                left: parent.left
                right: parent.right
                topMargin: 28
            }
            visible: NotificationService.count === 0
            text: "No notifications"
            color: Theme.textMuted
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
        }

        ListView {
            id: notifList

            anchors {
                top: dndRow.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: 12
                leftMargin: 16
                rightMargin: 16
                bottomMargin: 16
            }

            clip: true
            spacing: 8
            visible: NotificationService.count > 0
            model: NotificationService.list

            delegate: Rectangle {
                id: notifCard

                required property var modelData

                // Generic actions as {action, index} pairs, original index kept,
                // empty-text actions dropped. Same semantics as the popup.
                readonly property var actionItems: {
                    const src = notifCard.modelData.actions
                    if (!src)
                        return []
                    const out = []
                    for (let i = 0; i < src.length; i++) {
                        const a = src[i]
                        if (a && a.text && a.text.length > 0)
                            out.push({ "action": a, "index": i })
                    }
                    return out
                }

                width: notifList.width
                height: cardCol.implicitHeight + 20
                radius: 12
                color: cardHover.hovered ? Qt.lighter(Theme.surface, 1.15) : Theme.surface

                HoverHandler { id: cardHover }

                IconImage {
                    id: cardIcon
                    anchors {
                        left: parent.left
                        top: parent.top
                        margins: 10
                    }
                    width: 24
                    height: 24
                    asynchronous: true
                    source: {
                        const ic = notifCard.modelData.appIcon
                        if (ic && ic.charAt(0) === "/")
                            return "file://" + ic
                        return Quickshell.iconPath(ic || notifCard.modelData.appName.toLowerCase(),
                                                  "dialog-information")
                    }
                }

                Text {
                    id: dismissBtn
                    anchors {
                        right: parent.right
                        top: parent.top
                        margins: 8
                    }
                    text: "✕"
                    color: dismissHover.hovered ? Theme.text : Theme.textMuted
                    font.pixelSize: 12
                    HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: NotificationService.dismiss(notifCard.modelData.id) }
                }

                Column {
                    id: cardCol
                    anchors {
                        left: cardIcon.right
                        right: dismissBtn.left
                        top: parent.top
                        leftMargin: 10
                        rightMargin: 8
                        topMargin: 10
                    }
                    spacing: 2

                    Row {
                        width: parent.width
                        spacing: 6

                        Text {
                            text: notifCard.modelData.appName
                            color: Theme.textDim
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, parent.width - timeText.width - 6)
                        }

                        Text {
                            id: timeText
                            text: Qt.formatDateTime(notifCard.modelData.time, "hh:mm")
                            color: Theme.textMuted
                            font.pixelSize: 10
                        }
                    }

                    Text {
                        width: parent.width
                        visible: notifCard.modelData.summary.length > 0
                        text: notifCard.modelData.summary
                        color: Theme.text
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width
                        visible: notifCard.modelData.body.length > 0
                        text: notifCard.modelData.body
                        color: Theme.textDim
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 3
                        textFormat: Text.PlainText
                    }

                    // Generic inline-reply affordance — same widget & semantics
                    // as the popup. Visible only when hasInlineReply.
                    NotificationReply {
                        width: parent.width
                        notifId: notifCard.modelData.id
                        notification: notifCard.modelData.notification
                    }

                    // Generic action buttons — same data & semantics as the popup.
                    Flow {
                        width: parent.width
                        spacing: 6
                        topPadding: 4
                        visible: notifCard.actionItems.length > 0

                        Repeater {
                            model: notifCard.actionItems

                            delegate: Rectangle {
                                id: centerActBtn

                                required property var modelData

                                implicitWidth: Math.min(centerActLabel.implicitWidth + 20,
                                                        notifCard.width - 28)
                                implicitHeight: 28
                                radius: 8
                                clip: true
                                color: centerActHover.hovered ? Qt.lighter(Theme.surface, 1.25)
                                                              : Qt.lighter(Theme.surface, 1.1)

                                Text {
                                    id: centerActLabel
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, centerActBtn.width - 12)
                                    text: centerActBtn.modelData.action.text
                                    color: Theme.text
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                HoverHandler {
                                    id: centerActHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    gesturePolicy: TapHandler.ReleaseWithinBounds
                                    onTapped: NotificationService.invokeAction(
                                        notifCard.modelData.id, centerActBtn.modelData.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
