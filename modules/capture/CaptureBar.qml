import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import "."
import "../../components"

Item {
    id: root

    implicitWidth: 460
    implicitHeight: 64
    width: 460
    height: 64

    // Take keyboard focus while shown so Esc lands here even without a pointer
    // move (the host CapturePicker window is focusable while the picker is up).
    // Imperative only - no static `focus: true` that could contend with other
    // surfaces while hidden.
    onVisibleChanged: {
        console.log("[CaptureBar] visible ->", root.visible)
        if (root.visible)
            root.forceActiveFocus()
    }

    // Picker hotkeys: R region / W window / F fullscreen (screen) / Esc cancel.
    // Region/window selection then has its own Esc handling in CaptureOverlay.
    Keys.onPressed: (event) => {
        switch (event.key) {
        case Qt.Key_Escape:
            CaptureService.closeBar()
            event.accepted = true
            break
        case Qt.Key_R:
            CaptureService.triggerCapture("region")
            event.accepted = true
            break
        case Qt.Key_W:
            CaptureService.triggerCapture("window")
            event.accepted = true
            break
        case Qt.Key_F:
        case Qt.Key_S:
            CaptureService.triggerCapture("screen")
            event.accepted = true
            break
        }
    }

    // Window-level backup: fires even if the item above never gained focus.
    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        context: Qt.WindowShortcut
        onActivated: CaptureService.closeBar()
    }

    Row {
        anchors.centerIn: parent

        spacing: 6

        Repeater {
            model: [
                { svg: "assets/screen-capture/selection-fill.svg", icon: "screenshot-region-symbolic", fallback: "select-rectangular", label: "Region", mode: "region" },
                { svg: "assets/screen-capture/window-alt.svg", icon: "window-symbolic", fallback: "preferences-system-windows", label: "Window", mode: "window" },
                { svg: "assets/screen-capture/fullscreen.svg", icon: "video-display-symbolic", fallback: "video-display", label: "Screen", mode: "screen" },
                { svg: "assets/screen-capture/close-square-svgrepo-com.svg", icon: "window-close-symbolic", fallback: "window-close", label: "Cancel", mode: "cancel" }
            ]

            delegate: Rectangle {
                id: btn

                required property var modelData

                width: 100
                height: 46
                radius: 12
                color: "transparent"

                MouseArea {
                    id: btnMouse

                    anchors.fill: parent

                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        if (btn.modelData.mode === "cancel") {
                            CaptureService.closeBar()
                        } else {
                            console.log("[CaptureBar] Action triggered:", btn.modelData.mode)
                            CaptureService.triggerCapture(btn.modelData.mode)
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent

                    spacing: 3

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter

                        // Optical balance: the fullscreen glyph reads heavier than
                        // the region/window ones at the same box size, so shave 1px
                        // off just that one.
                        readonly property int opticalSize:
                            (btn.modelData.mode === "screen" || btn.modelData.mode === "fullscreen") ? 19 : 20

                        width: opticalSize
                        height: opticalSize

                        // theme icon (already coloured) for rows with no custom svg
                        IconImage {
                            anchors.fill: parent
                            source: btn.modelData.svg ? "" : Quickshell.iconPath(btn.modelData.icon, btn.modelData.fallback)
                            asynchronous: true
                            visible: !btn.modelData.svg
                        }

                        // custom solid-#000 svg, tinted like the label
                        Image {
                            id: capImg
                            anchors.fill: parent
                            source: btn.modelData.svg ? "file://" + Quickshell.shellPath(btn.modelData.svg) : ""
                            sourceSize.width: 40
                            sourceSize.height: 40
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: capImg
                            source: capImg
                            visible: !!btn.modelData.svg && capImg.status === Image.Ready
                            color: btnMouse.containsMouse ? Theme.accent : Theme.text
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: btn.modelData.label
                        color: btnMouse.containsMouse ? Theme.accent : Theme.text
                        font.pixelSize: 11
                        font.family: Theme.fontFamily
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
