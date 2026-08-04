import QtQuick

Rectangle {
    id: root

    width: parent ? parent.width : 640

    property real resultsHeight: 0

    height: resultsHeight
    visible: resultsHeight > 0

    radius: 30

    color: "#252536"

    border.width: 1
    border.color: "#3d3d55"

}
