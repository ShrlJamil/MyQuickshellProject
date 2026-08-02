import QtQuick
import QtQuick.Controls

TextField {
    id: searchField

    width: parent.width
    height: 46

    property var resultList

    placeholderText: "Search ..."
    placeholderTextColor: "#888888"

    font.pixelSize: 18

    color: "#ffffff"

    focus: true

    selectByMouse: true

    Keys.onDownPressed: {
        if (resultList)
            resultList.next()
    }

    Keys.onUpPressed: {
        if (resultList)
            resultList.previous()
    }

    background: Rectangle {
        radius: 14

        color: "transparent"

    }

    Keys.onPressed: (event) => {
      console.log("SearchBar:", event.key)
    }
}
