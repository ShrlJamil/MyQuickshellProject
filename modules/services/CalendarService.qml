pragma Singleton

import QtQuick
import Quickshell

// Calendar facts with exactly one owner: the Notification Center
// calendar and the desktop calendar widget both read from here, so
// the month math exists once. "today" refreshes itself via a single
// one-shot timer armed for just after midnight - no polling anywhere.
Item {
    id: root

    property var today: new Date()

    readonly property int year: root.today.getFullYear()
    readonly property int month: root.today.getMonth()
    readonly property int date: root.today.getDate()
    readonly property int daysInMonth: new Date(root.year, root.month + 1, 0).getDate()
    // Weekday of the 1st, Sunday = 0 (JS getDay semantics - the same
    // convention the Notification Center grid has always used).
    readonly property int firstWeekday: new Date(root.year, root.month, 1).getDay()
    readonly property string monthName: Qt.formatDate(root.today, "MMMM")
    readonly property string monthYear: Qt.formatDate(root.today, "MMMM yyyy")

    function _msPastMidnight() {
        const n = new Date()
        const m = new Date(n.getFullYear(), n.getMonth(), n.getDate() + 1, 0, 0, 5)
        return m - n
    }

    Timer {
        id: dayTimer

        running: true

        onTriggered: {
            root.today = new Date()
            dayTimer.interval = root._msPastMidnight()
            dayTimer.restart()
        }
    }

    Component.onCompleted: dayTimer.interval = root._msPastMidnight()
}
