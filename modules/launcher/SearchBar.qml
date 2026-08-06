import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell

Rectangle {
    id: root

    width: parent.width
    height: 42

    radius: 14

    color: "transparent"

    property var resultList
    property var appProvider
    property var searchModeProvider
    property string modeIconName: searchModeProvider ? searchModeProvider.currentIcon : "system-search-symbolic"
    property string text: ""

    signal activated()
    signal closeRequested()

    function deleteSelectedClipboard() {
        if (!resultList || !appProvider)
            return

        if (searchModeProvider && searchModeProvider.currentMode !== "clipboard")
            return

        if (resultList.count === 0 || resultList.currentIndex < 0)
            return

        var entry = resultList.currentItem ? resultList.currentItem.entry : null
        if (!entry)
            return

        var clipId = entry.clipId
        if (!clipId || clipId.length === 0)
            return

        appProvider.deleteClipboardEntry(clipId)
    }

    onTextChanged: {
        if (searchField)
            searchField.text = root.text
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        spacing: 12

        IconImage {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24

            source: Quickshell.iconPath(root.modeIconName, "edit-find")

            asynchronous: true

            opacity: 0.8
        }

        TextField {
            id: searchField

            Layout.fillWidth: true
            Layout.fillHeight: true

            placeholderText: "Search"
            placeholderTextColor: "#888888"

            font.pixelSize: 24

            color: "#ffffff"

            focus: true

            selectByMouse: true

            onTextChanged: {
                root.text = searchField.text
                if (appProvider)
                    appProvider.query = searchField.text
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
                case Qt.Key_Delete:
                    if (searchModeProvider && searchModeProvider.currentMode === "clipboard") {
                        root.deleteSelectedClipboard()
                        event.accepted = true
                    }
                    break
                case Qt.Key_Escape:
                    event.accepted = true
                    closeRequested()
                    break
                }
            }

            background: Item {}
        }
    }
}
