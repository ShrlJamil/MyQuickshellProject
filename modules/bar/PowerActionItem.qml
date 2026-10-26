import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    property string actionId: ""
    property string label: ""
    property string iconSource: ""
    property string shortcutKey: ""
    property bool selected: false

    signal actionRequested(string actionId)

    Item {
        id: visual

        anchors.fill: parent

        Rectangle {
            id: tileBase

            anchors.fill: parent

            radius: 12
            clip: true
            // Selected wears the light active scheme (dark foreground
            // below); hover on the dark card stays the white overlay.
            color: root.selected ? (hover.hovered ? Theme.activeSurfaceHover : Theme.activeSurface)
                : (hover.hovered ? Theme.surfaceHover : "transparent")

            // Subtle outline so a hovered tile pops against the dark menu
            // background. The selected tile needs none - its light fill
            // is the signal.
            border.width: hover.hovered && !root.selected ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            width: parent.width - 28
            spacing: 20

            Item {
                width: parent.width
                height: 44

                Image {
                    id: iconImage

                    anchors.centerIn: parent

                    width: 26
                    height: 26

                    source: root.iconSource
                    sourceSize.width: 64
                    sourceSize.height: 64
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: false
                }

                ColorOverlay {
                    anchors.fill: iconImage

                    source: iconImage
                    color: root.selected ? Theme.onActiveSurface : Theme.text
                    visible: root.iconSource !== ""
                }
            }

            Text {
                width: parent.width

                text: root.label
                color: root.selected ? Theme.onActiveSurface : Theme.text
                font.pixelSize: 12
                font.family: Theme.fontFamily
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        // Shortcut hint, tucked in the corner so it never disturbs the
        // centred icon + label.
        Text {
            anchors {
                top: parent.top
                right: parent.right
                topMargin: 8
                rightMargin: 10
            }

            visible: root.shortcutKey !== ""
            text: root.shortcutKey.toUpperCase()
            color: root.selected ? Theme.onActiveSurfaceDim : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
        }
    }

    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor

        onClicked: root.actionRequested(root.actionId)
    }
}
