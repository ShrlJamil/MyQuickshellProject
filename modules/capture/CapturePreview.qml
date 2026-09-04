import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "."
import "../../components"

PanelWindow {
    id: root

    readonly property bool shown: CaptureService.bannerVisible

    visible: root.shown || banner.opacity > 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        right: true
    }

    margins {
        top: 52
        right: 12
    }

    implicitWidth: 344
    implicitHeight: 84

    color: "transparent"
    focusable: false

    mask: Region { item: banner }

    Rectangle {
        id: banner

        anchors.fill: parent

        radius: Theme.cornerRadius
        color: Theme.background
        border.width: 1
        border.color: Theme.accent

        opacity: root.shown ? 1 : 0
        x: root.shown ? 0 : 44

        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on x {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            id: bannerHover

            onHoveredChanged: CaptureService.bannerHovered = bannerHover.hovered
        }

        MouseArea {
            anchors.fill: parent

            cursorShape: Qt.PointingHandCursor

            onClicked: CaptureService.copyPath()
        }

        Rectangle {
            id: thumb

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12

            width: 60
            height: 60
            radius: 8
            clip: true
            color: Theme.surface

            Image {
                id: thumbImg

                anchors.fill: parent

                source: CaptureService.lastPath !== "" ? "file://" + CaptureService.lastPath : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false

                layer.enabled: true
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: thumbImg.width
                        height: thumbImg.height
                        radius: 8
                    }
                }
            }
        }

        Column {
            anchors.left: thumb.right
            anchors.right: actions.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 10

            spacing: 3

            Text {
                width: parent.width
                elide: Text.ElideRight

                text: "Screenshot Captured"
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                elide: Text.ElideMiddle

                text: {
                    const p = CaptureService.lastPath
                    const i = p.lastIndexOf("/")
                    return i >= 0 ? p.substring(i + 1) : p
                }
                color: Theme.textMuted
                font.pixelSize: 11
            }
        }

        Row {
            id: actions

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 12

            spacing: 4

            MouseArea {
                width: 30
                height: 30
                cursorShape: Qt.PointingHandCursor

                onClicked: CaptureService.openLast()

                Rectangle {
                    anchors.fill: parent

                    radius: 8
                    color: openHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"
                }

                HoverHandler {
                    id: openHover
                }

                IconImage {
                    anchors.centerIn: parent

                    width: 16
                    height: 16

                    source: Quickshell.iconPath("document-open-symbolic", "document-open")
                    asynchronous: true
                }
            }

            MouseArea {
                width: 30
                height: 30
                cursorShape: Qt.PointingHandCursor

                onClicked: CaptureService.deleteLast()

                Rectangle {
                    anchors.fill: parent

                    radius: 8
                    color: deleteHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"
                }

                HoverHandler {
                    id: deleteHover
                }

                IconImage {
                    anchors.centerIn: parent

                    width: 16
                    height: 16

                    source: Quickshell.iconPath("user-trash-symbolic", "user-trash")
                    asynchronous: true
                }
            }
        }
    }
}
