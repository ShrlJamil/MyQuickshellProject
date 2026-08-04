import QtQuick
import QtQuick.Controls

TextField {
    id: searchField

    width: parent.width
    height: 42

    property var resultList
    property var appProvider

    signal activated()
    signal closeRequested()

    placeholderText: "Search"
    placeholderTextColor: "#888888"

    font.pixelSize: 24

    color: "#ffffff"

    focus: true

    selectByMouse: true

    onTextChanged: {
        if (appProvider)
            appProvider.query = text
    }

    Keys.onPressed: (event) => {
        switch (event.key) {
        case Qt.Key_Down:
            if (resultList)
                resultList.next()
            event.accepted = true
            break
        case Qt.Key_Up:
            if (resultList)
                resultList.previous()
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            event.accepted = true
            activated()
            break
        case Qt.Key_Escape:
            event.accepted = true
            closeRequested()
            break
        }
    }

    background: Rectangle {
        radius: 14

        color: "transparent"
    }
}
