import QtQuick
import "../../components"
import "../services"

// Desktop month calendar, minimalist: month name in the accent
// colour, weekday initials, a plain date grid, today in an accent
// circle. All date facts come from CalendarService - the same
// singleton the Notification Center reads - so nothing is computed
// twice. Fully static: it repaints only when the day rolls over.
Rectangle {
    id: root

    readonly property int cell: 24
    // Monday-first lead blanks (CalendarService reports Sunday-first).
    readonly property int leadBlanks: (CalendarService.firstWeekday + 6) % 7

    width: height
    height: 200
    radius: 22
    color: Qt.rgba(Theme.panelBackground.r, Theme.panelBackground.g, Theme.panelBackground.b, 0.92)

    Column {
        id: col

        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: 10
        }

        spacing: 3

        Text {
            text: CalendarService.monthName.toUpperCase()
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Black
            font.letterSpacing: 1.1
        }

        Row {
            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]

                delegate: Text {
                    required property var modelData

                    width: root.cell
                    height: 13
                    text: modelData
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Grid {
            columns: 7

            Repeater {
                model: 42

                delegate: Item {
                    id: dayCell

                    required property int index

                    width: root.cell
                    height: root.cell

                    readonly property int dayNum: index - root.leadBlanks + 1
                    readonly property bool inMonth: dayNum >= 1 && dayNum <= CalendarService.daysInMonth
                    readonly property bool isToday: inMonth && dayNum === CalendarService.date

                    Rectangle {
                        anchors.centerIn: dateText
                        width: 21
                        height: 21
                        radius: 10.5
                        color: dayCell.isToday ? Theme.accent : "transparent"
                    }

                    Text {
                        id: dateText

                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }

                        text: dayCell.inMonth ? dayCell.dayNum : ""
                        color: dayCell.isToday ? Theme.background : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
