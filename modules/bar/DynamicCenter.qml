import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../components"
import "../capture"

Item {
    id: root

    property string activeSurface: "idle"
    property var captureService: null
    signal closeRequested()

    anchors.horizontalCenter: parent.horizontalCenter
    y: 40
    width: parent.width
    clip: true

    readonly property real surfaceWidth: Math.min(680, parent.width * 0.85)

    property bool surfaceVisible: activeSurface !== "idle"
    property string _lastSurface: "power"

    readonly property int contentHeight: root.activeSurface === "capture"
        ? (captureBarSurface.implicitHeight > 0 ? captureBarSurface.implicitHeight : 64)
        : powerMenuSurface.implicitHeight
    readonly property int targetHeight: (root.activeSurface === "power" || root.activeSurface === "capture") ? contentHeight : 0
    property int allocatedHeight: 0

    readonly property int gap: 0
    implicitHeight: allocatedHeight
    height: implicitHeight

    onTargetHeightChanged: {
        if (targetHeight > 0) {
            hideTimer.stop()
            allocatedHeight = targetHeight + gap
        } else if (allocatedHeight > 0) {
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: 200
        onTriggered: root.allocatedHeight = 0
    }

    Item {
        id: surfaceWrapper

        anchors.horizontalCenter: parent.horizontalCenter
        width: root.surfaceWidth
        implicitHeight: powerMenuSurface.visible ? powerMenuSurface.implicitHeight
            : captureBarSurface.visible ? captureBarSurface.implicitHeight
            : displaySurface.visible ? displaySurface.implicitHeight
            : mediaPreviewSurface.visible ? mediaPreviewSurface.implicitHeight
            : mediaCompactSurface.visible ? mediaCompactSurface.implicitHeight
            : 0
        height: implicitHeight
        state: root.activeSurface === "idle" ? "hidden" : "visible"

        states: [
            State {
                name: "hidden"
                PropertyChanges { target: surfaceWrapper; y: -80 }
            },
            State {
                name: "visible"
                PropertyChanges { target: surfaceWrapper; y: 0 }
            }
        ]

        transitions: [
            Transition {
                to: "visible"
                NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic }
            },
            Transition {
                to: "hidden"
                NumberAnimation { property: "y"; duration: 160; easing.type: Easing.InCubic }
            }
        ]

        PowerMenu {
            id: powerMenuSurface
            width: parent.width
            visible: root.activeSurface === "power" || (root.allocatedHeight > 0 && root._lastSurface === "power")
            onCloseRequested: root.closeRequested()
        }

        CaptureBar {
            id: captureBarSurface
            anchors.horizontalCenter: parent.horizontalCenter
            captureService: root.captureService
            visible: root.activeSurface === "capture" || (root.allocatedHeight > 0 && root._lastSurface === "capture")
        }

        Item {
            id: displaySurface
            width: parent.width
            visible: root.activeSurface === "display"
        }

        Item {
            id: mediaPreviewSurface
            width: parent.width
            visible: root.activeSurface === "mediaPreview"
        }

        Item {
            id: mediaCompactSurface
            width: parent.width
            visible: root.activeSurface === "mediaCompact"
        }
    }

    onActiveSurfaceChanged: {
        console.log("[DynamicCenter] Active surface changed to:", root.activeSurface)

        if (root.activeSurface !== "idle")
            root._lastSurface = root.activeSurface

        if (root.activeSurface === "power") {
            powerMenuSurface.reset()
            powerMenuSurface.forceActiveFocus()
        }
    }
}
