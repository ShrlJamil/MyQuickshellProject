import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../../components"
import "../capture"
import "../display"

Item {
    id: root

    property string activeSurface: "idle"
    signal closeRequested()

    property var screen: null

    anchors.horizontalCenter: parent.horizontalCenter
    y: 40
    width: parent.width
    clip: true

    readonly property real surfaceWidth: Math.min(680, parent.width * 0.85)

    property bool surfaceVisible: activeSurface !== "idle"
    property string _lastSurface: "power"

    property int workspaceId: -1
    property bool workspaceVisible: false
    property int _lastSeenWorkspaceId: -1

    readonly property bool workspaceShown: root.workspaceVisible && root.activeSurface === "idle"
    readonly property string screenName: root.screen?.name ?? ""
    readonly property var ownMonitor: root.screen ? Hyprland.monitorFor(root.screen) : null
    readonly property int ownWorkspaceId: ownMonitor?.activeWorkspace?.id ?? -1
    readonly property var ownWorkspaces: Hyprland.workspaces.values.filter(w => (w.monitor?.name ?? "") === root.screenName)

    function triggerWorkspace(id) {
        root.workspaceId = id
        if (root.activeSurface === "idle") {
            root._lastSurface = "workspace"
            root.workspaceVisible = true
            workspaceTimer.restart()
        }
    }

    readonly property int contentHeight: root.activeSurface === "capture"
        ? (captureBarSurface.implicitHeight > 0 ? captureBarSurface.implicitHeight : 64)
        : root.activeSurface === "display"
        ? (displaySurface.implicitHeight > 0 ? displaySurface.implicitHeight : 500)
        : powerMenuSurface.implicitHeight
    readonly property int targetHeight: (root.activeSurface === "power" || root.activeSurface === "capture" || root.activeSurface === "display") ? contentHeight : root.workspaceVisible ? workspaceSurface.implicitHeight : 0
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

    Timer {
        id: workspaceTimer
        interval: 1500
        onTriggered: root.workspaceVisible = false
    }

    onOwnWorkspaceIdChanged: {
        if (root.ownWorkspaceId < 0)
            return
        if (root._lastSeenWorkspaceId < 0) {
            root._lastSeenWorkspaceId = root.ownWorkspaceId
            return
        }
        if (root.ownWorkspaceId === root._lastSeenWorkspaceId)
            return
        root._lastSeenWorkspaceId = root.ownWorkspaceId
        root.triggerWorkspace(root.ownWorkspaceId)
    }

    Item {
        id: surfaceWrapper

        anchors.horizontalCenter: parent.horizontalCenter
        width: root.surfaceWidth
        clip: true
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
                PropertyChanges {
                    target: surfaceWrapper
                    y: (root.activeSurface === "display" || root._lastSurface === "display")
                        ? -surfaceWrapper.height : -80
                }
            },
            State {
                name: "visible"
                PropertyChanges { target: surfaceWrapper; y: 0 }
            }
        ]

        transitions: [
            Transition {
                to: "visible"
                NumberAnimation { property: "y"; duration: root.activeSurface === "display" ? 300 : 220; easing.type: Easing.OutCubic }
            },
            Transition {
                to: "hidden"
                NumberAnimation { property: "y"; duration: root._lastSurface === "display" ? 220 : 160; easing.type: Easing.InCubic }
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
            visible: root.activeSurface === "capture" || (root.allocatedHeight > 0 && root._lastSurface === "capture")
        }

        DisplayManager {
            id: displaySurface
            width: parent.width
            visible: root.activeSurface === "display" || (root.allocatedHeight > 0 && root._lastSurface === "display")
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

    Item {
        id: workspaceSurface

        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(workspacePillRow.implicitWidth + 48, 420)
        implicitHeight: 64
        height: 64
        visible: root.workspaceShown || (root.allocatedHeight > 0 && root._lastSurface === "workspace")
        state: root.workspaceShown ? "visible" : "hidden"

        states: [
            State {
                name: "hidden"
                PropertyChanges { target: workspaceSurface; y: -80 }
            },
            State {
                name: "visible"
                PropertyChanges { target: workspaceSurface; y: 0 }
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

        Shape {
            id: workspaceBackground

            anchors.fill: parent
            antialiasing: true
            asynchronous: false
            vendorExtensionsEnabled: true
            preferredRendererType: Shape.CurveRenderer

            readonly property real notchSize: 18
            readonly property real bottomRadius: Theme.cornerRadius

            ShapePath {
                fillColor: Theme.background
                strokeColor: "transparent"
                strokeWidth: 0

                startX: 0
                startY: 0

                PathCubic {
                    control1X: workspaceBackground.notchSize * 0.5
                    control1Y: 0
                    control2X: workspaceBackground.notchSize
                    control2Y: workspaceBackground.notchSize * 0.5
                    x: workspaceBackground.notchSize
                    y: workspaceBackground.notchSize
                }

                PathLine {
                    x: workspaceBackground.notchSize
                    y: workspaceBackground.height - workspaceBackground.bottomRadius
                }

                PathQuad {
                    controlX: workspaceBackground.notchSize
                    controlY: workspaceBackground.height
                    x: workspaceBackground.notchSize + workspaceBackground.bottomRadius
                    y: workspaceBackground.height
                }

                PathLine {
                    x: workspaceBackground.width - workspaceBackground.notchSize - workspaceBackground.bottomRadius
                    y: workspaceBackground.height
                }

                PathQuad {
                    controlX: workspaceBackground.width - workspaceBackground.notchSize
                    controlY: workspaceBackground.height
                    x: workspaceBackground.width - workspaceBackground.notchSize
                    y: workspaceBackground.height - workspaceBackground.bottomRadius
                }

                PathLine {
                    x: workspaceBackground.width - workspaceBackground.notchSize
                    y: workspaceBackground.notchSize
                }

                PathCubic {
                    control1X: workspaceBackground.width - workspaceBackground.notchSize
                    control1Y: workspaceBackground.notchSize * 0.5
                    control2X: workspaceBackground.width - workspaceBackground.notchSize * 0.5
                    control2Y: 0
                    x: workspaceBackground.width
                    y: 0
                }

                PathLine {
                    x: 0
                    y: 0
                }
            }
        }

        Row {
            id: workspacePillRow

            anchors.centerIn: parent
            spacing: 12

            Repeater {
                model: root.ownWorkspaces

                delegate: Rectangle {
                    width: numberText.implicitWidth + 16
                    height: 24
                    radius: height / 2
                    color: modelData.active ? Theme.accent : "transparent"

                    Text {
                        id: numberText

                        anchors.centerIn: parent
                        text: modelData.id
                        color: modelData.active ? Theme.background : Theme.textDim
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
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

        if (root.activeSurface !== "idle") {
            root.workspaceVisible = false
            workspaceTimer.stop()
        }
    }
}
