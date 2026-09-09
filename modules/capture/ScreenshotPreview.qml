import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."
import "../../components"

// Minimal floating screenshot thumbnail, bottom-right corner. Pure image - no
// text, no header, no close button. Click -> xdg-open + dismiss. Auto-dismiss
// after 3.5s with a fade + slide-out. Replaces the old CapturePreview banner.
PanelWindow {
    id: root

    readonly property bool shown: CaptureService.bannerVisible
    readonly property string filePath: CaptureService.lastPath

    // keep the surface mapped through the fade/slide-out
    property bool closing: false
    visible: root.shown || root.closing

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        bottom: true
        right: true
    }

    margins {
        bottom: 24
        right: 24
    }

    implicitWidth: 180
    implicitHeight: 112

    color: "transparent"
    focusable: false

    mask: Region { item: frame }

    onShownChanged: {
        if (root.shown) {
            root.closing = false
            closeLatch.stop()
            hideTimer.restart()
        } else if (root.visible) {
            root.closing = true
            closeLatch.restart()
        }
    }

    // single-shot 3.5s auto-dismiss
    Timer {
        id: hideTimer
        interval: 3500
        onTriggered: CaptureService.bannerVisible = false
    }
    // window stays mapped while the exit animation plays
    Timer {
        id: closeLatch
        interval: 280
        onTriggered: root.closing = false
    }

    Process { id: openProc }

    Rectangle {
        id: frame

        anchors.fill: parent

        radius: Theme.cornerRadius
        color: Theme.background
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        transform: Translate {
            x: root.shown ? 0 : 32
            Behavior on x {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
        }

        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            horizontalOffset: 0
            verticalOffset: 4
            radius: 16
            samples: 25
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        Image {
            id: shot

            anchors.fill: parent
            anchors.margins: 1

            source: root.filePath !== "" ? "file://" + root.filePath : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false

            layer.enabled: true
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: shot.width
                    height: shot.height
                    radius: Theme.cornerRadius - 1
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                if (root.filePath !== "") {
                    openProc.command = ["xdg-open", root.filePath]
                    openProc.running = true
                }
                CaptureService.bannerVisible = false
            }
        }
    }
}
