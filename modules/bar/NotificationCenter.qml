import QtQuick
import Quickshell
import Quickshell.Io
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

    // Lock the panel's top edge 1:1 under the real bar strip via an async
    // `hyprctl -j layers` probe (identical mechanism to ControlCenter) instead
    // of a hardcoded offset. Any missing / implausible result falls back to the
    // fixed default so the window can never fly off-screen.
    readonly property real barStripHeight: 40
    readonly property real barGap: 8
    readonly property int barTopMarginDefault: 48
    // Max the probe may move the panel off the default before its result is
    // treated as garbage (stale / incomplete JSON) and discarded.
    readonly property int barTopMarginMaxDelta: 120
    property int topMargin: root.barTopMarginDefault
    property int barSurfaceTop: 0

    // Span from just under the bar to near the bottom edge, so the panel is
    // almost full-height. Height comes from the top+bottom anchors against the
    // real panel geometry — never a hardcoded screen resolution.
    anchors {
        top: true
        right: true
        bottom: true
    }

    // top is probed (see below); bottom leaves an aesthetic breathing gap
    // balanced with the right inset so the panel reads as floating.
    margins {
        top: root.topMargin
        right: 12
        bottom: 20
    }

    implicitWidth: 380

    function probeBarSurface() {
        if (!barProbe.running) barProbe.running = true
    }

    function updateBarSurface() {
        // topMargin is written ONLY here. Runs off an async process, so a stale
        // or incomplete result must never fling the window off-screen - any
        // implausible value falls back to the fixed default.
        const def = root.barTopMarginDefault
        try {
            const layers = JSON.parse(barProbe.stdout.text)
            const mon = layers[root.screen.name]
            if (mon == null || mon.levels == null) {
                root.topMargin = def
                return
            }

            root.barSurfaceTop = 0

            for (const key of Object.keys(mon.levels)) {
                const arr = mon.levels[key]
                if (!Array.isArray(arr)) continue

                const level = parseInt(key, 10)

                for (const surf of arr) {
                    if (surf.namespace !== "quickshell" || surf.pid !== Quickshell.processId) continue
                    if (level === 2) root.barSurfaceTop = surf.y
                }
            }

            // Only shift when the bar's own strip surface was actually located,
            // and only by a small sane amount; otherwise keep the default.
            if (root.barSurfaceTop > 0) {
                const target = root.barSurfaceTop + root.barStripHeight + root.barGap
                const screenY = root.screen.y ? root.screen.y : 0
                const candidate = Math.max(8, target - screenY)
                root.topMargin = (Math.abs(candidate - def) <= root.barTopMarginMaxDelta) ? candidate : def
            } else {
                root.topMargin = def
            }
        } catch (e) {
            root.topMargin = def
        }
    }

    Process {
        id: barProbe

        command: ["hyprctl", "-j", "layers"]

        stdout: StdioCollector {
            waitForEnd: true
        }

        onExited: root.updateBarSurface()
    }

    Component.onCompleted: root.probeBarSurface()

    color: "transparent"

    function close() {
        NotificationService.closeCenter()
    }

    onOpenChanged: {
        if (root.open) {
            root.closing = false
            hideTimer.stop()
            root.probeBarSurface()
            panel.forceActiveFocus()
        } else if (root.visible) {
            root.closing = true
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        // Keep the window mapped just past the ~110ms scale-fade close.
        interval: 140
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
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.surfaceOpacity)
        border.width: 1
        border.color: Theme.surfaceHover

        // Fast scale-fade from the bar's top-right corner + a tiny -8px drift.
        // No full-height slide.
        opacity: 0
        scale: 0.92
        transformOrigin: Item.TopRight

        transform: Translate {
            id: drift

            y: -8
        }

        states: State {
            name: "open"
            when: root.open

            PropertyChanges {
                target: panel
                opacity: 1
                scale: 1
            }

            PropertyChanges {
                target: drift
                y: 0
            }
        }

        transitions: [
            Transition {
                from: ""
                to: "open"

                ParallelAnimation {
                    NumberAnimation { target: panel; property: "opacity"; duration: 150; easing.type: Easing.OutQuad }
                    NumberAnimation { target: panel; property: "scale"; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: drift; property: "y"; duration: 160; easing.type: Easing.OutCubic }
                }
            },

            Transition {
                from: "open"
                to: ""

                ParallelAnimation {
                    NumberAnimation { target: panel; property: "opacity"; duration: 100; easing.type: Easing.InQuad }
                    NumberAnimation { target: panel; property: "scale"; duration: 110; easing.type: Easing.InCubic }
                    NumberAnimation { target: drift; property: "y"; duration: 110; easing.type: Easing.InCubic }
                }
            }
        ]

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

            interactive: true
            acceptedButtons: Qt.NoButton

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

                    // Generic actions — text only, no card/border/fill. Hover
                    // only recolours the label. Same data & semantics as the
                    // popup; still runs the existing invokeAction(...).
                    Flow {
                        width: parent.width
                        spacing: 16
                        topPadding: 4
                        visible: notifCard.actionItems.length > 0
                            || (replyWidget.available && !replyWidget.replyMode)

                        // Reply as a generic action: identical metrics/style
                        // to the delegates after this; opens the input below.
                        Text {
                            id: replyActLabel

                            visible: replyWidget.available && !replyWidget.replyMode
                            width: replyActLabel.implicitWidth
                            height: 28
                            verticalAlignment: Text.AlignVCenter
                            text: "Reply"
                            color: replyActHover.hovered ? Theme.accent : Theme.text
                            font.pixelSize: 11
                            elide: Text.ElideRight

                            HoverHandler {
                                id: replyActHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: replyWidget.replyMode = true
                            }
                        }

                        Repeater {
                            model: notifCard.actionItems

                            delegate: Text {
                                id: centerActLabel

                                required property var modelData

                                width: Math.min(implicitWidth, notifCard.width - 28)
                                height: 28
                                verticalAlignment: Text.AlignVCenter
                                text: centerActLabel.modelData.action.text
                                color: centerActHover.hovered ? Theme.accent : Theme.text
                                font.pixelSize: 11
                                elide: Text.ElideRight

                                HoverHandler {
                                    id: centerActHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    gesturePolicy: TapHandler.ReleaseWithinBounds
                                    onTapped: NotificationService.invokeAction(
                                        notifCard.modelData.id, centerActLabel.modelData.index)
                                }
                            }
                        }
                    }

                    // Generic inline-reply affordance — same widget & semantics
                    // as the popup. Visible only when hasInlineReply. The
                    // collapsed button is hidden here (showAffordance: false);
                    // Reply is rendered as the first item of the actions Flow
                    // above, same style as generic actions. The expanded input
                    // form lives here, below the whole action row.
                    NotificationReply {
                        id: replyWidget
                        width: parent.width
                        showAffordance: false
                        notifId: notifCard.modelData.id
                        notification: notifCard.modelData.notification
                    }
                }
            }
        }
    }
}
