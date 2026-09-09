import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../components"

// Standalone bottom-centre OSD, one lightweight PanelWindow per screen. It is
// independent of Bar and DynamicCenter and never takes keyboard focus or input
// (empty mask -> fully click-through).
//
// Modes:
//   volume / brightness / caps  <- OSDService (global; shown on focused screen)
//   workspace                   <- this screen's own Hyprland active workspace
//                                  (reuses the model the bar already tracks)
PanelWindow {
    id: root

    required property var modelData

    screen: modelData.screen

    readonly property bool isFocused: Hyprland.focusedMonitor
        && root.modelData.screen
        && Hyprland.focusedMonitor.name === root.modelData.screen.name

    // ---- per-screen workspace OSD (ported from DynamicCenter) -----------------
    readonly property string screenName: root.modelData.screen?.name ?? ""
    readonly property var ownMonitor: root.modelData.screen ? Hyprland.monitorFor(root.modelData.screen) : null
    readonly property int ownWorkspaceId: root.ownMonitor?.activeWorkspace?.id ?? -1
    readonly property var ownWorkspaces: Hyprland.workspaces.values
        .filter(w => (w.monitor?.name ?? "") === root.screenName)
        .sort((a, b) => a.id - b.id)
    readonly property int ownWorkspaceIndex: root.ownWorkspaces.findIndex(w => w.id === root.ownWorkspaceId)

    property int _lastSeenWorkspaceId: -1
    property bool wsVisible: false

    Timer {
        id: wsTimer
        interval: 1500
        onTriggered: root.wsVisible = false
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
        root.wsVisible = true
        wsTimer.restart()
    }

    // ---- resolved mode for THIS screen --------------------------------------
    // A deliberate workspace switch wins while its window is open; otherwise the
    // global volume/brightness/caps OSD shows, on the focused screen only.
    readonly property string shownMode: root.wsVisible
        ? "workspace"
        : (OSDService.active && root.isFocused ? OSDService.mode : "")
    readonly property bool shown: root.shownMode !== ""

    property string _renderMode: "volume"
    onShownModeChanged: if (root.shownMode !== "") root._renderMode = root.shownMode

    // keep the window mapped briefly so the close animation can play out
    property bool _closing: false
    onShownChanged: {
        if (root.shown) {
            root._closing = false
            closeLatch.stop()
        } else if (root.visible) {
            root._closing = true
            closeLatch.restart()
        }
    }
    Timer {
        id: closeLatch
        interval: 240
        onTriggered: root._closing = false
    }

    visible: root.shown || root._closing

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { bottom: true }
    margins { bottom: 96 }

    implicitWidth: 480
    implicitHeight: 72
    color: "transparent"
    mask: Region {}

    // =========================== the pill ==================================
    Rectangle {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        height: 40
        width: Math.max(120, body.implicitWidth + 36)
        radius: 16
        color: Theme.background
        border.width: 1
        border.color: Theme.surfaceHover

        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            OpacityAnimator {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        transform: Translate {
            y: root.shown ? 0 : 12
            Behavior on y {
                NumberAnimation {
                    duration: root.shown ? 190 : 150
                    easing.type: root.shown ? Easing.OutCubic : Easing.InCubic
                }
            }
        }

        Item {
            id: body

            anchors.centerIn: parent
            height: 40
            implicitWidth: {
                switch (root._renderMode) {
                case "caps": return capsRow.implicitWidth
                case "workspace": return wsView.width
                default: return meterRow.implicitWidth
                }
            }

            // ---------------- volume / brightness ----------------
            Row {
                id: meterRow

                anchors.centerIn: parent
                visible: root._renderMode === "volume" || root._renderMode === "brightness"
                spacing: 10

                readonly property bool isVol: root._renderMode === "volume"
                readonly property bool muted: meterRow.isVol && OSDService.volumeMuted
                readonly property int pct: meterRow.isVol ? OSDService.volumePercent : OSDService.brightnessPercent
                readonly property real frac: Math.max(0, Math.min(1, (meterRow.muted ? 0 : meterRow.pct) / 100))

                // speaker glyph - dynamic SVG (assets/volume/), tinted by state
                Item {
                    id: volIcon

                    width: 24
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter
                    visible: meterRow.isVol

                    readonly property bool off: meterRow.muted || meterRow.pct === 0
                    readonly property string file: {
                        if (volIcon.off)
                            return "volume-off-svgrepo-com.svg"
                        if (meterRow.pct <= 33)
                            return "volume-low-svgrepo-com.svg"
                        if (meterRow.pct <= 66)
                            return "volume-medium-svgrepo-com.svg"
                        return "volume-high-svgrepo-com.svg"
                    }

                    Image {
                        id: volIconImg

                        anchors.fill: parent
                        sourceSize.width: 48
                        sourceSize.height: 48
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        mipmap: true
                        visible: false

                        source: "file://" + Quickshell.shellPath("assets/volume/" + volIcon.file)
                    }

                    ColorOverlay {
                        anchors.fill: volIconImg
                        source: volIconImg
                        color: volIcon.off ? Theme.textMuted : Theme.text
                    }
                }

                // brightness glyph - dynamic SVG (assets/brightness/), always white
                Item {
                    id: brightIcon

                    width: 24
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !meterRow.isVol

                    readonly property string file: {
                        if (meterRow.pct <= 33)
                            return "brightness-low-svgrepo-com.svg"
                        if (meterRow.pct <= 66)
                            return "brightness-medium-svgrepo-com.svg"
                        return "brightness-high-svgrepo-com.svg"
                    }

                    Image {
                        id: brightIconImg

                        anchors.fill: parent
                        sourceSize.width: 48
                        sourceSize.height: 48
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        mipmap: true
                        visible: false

                        source: "file://" + Quickshell.shellPath("assets/brightness/" + brightIcon.file)
                    }

                    ColorOverlay {
                        anchors.fill: brightIconImg
                        source: brightIconImg
                        color: Theme.text
                    }
                }

                // progress track + fill (thick, solid white over a muted track)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 120
                    height: 6
                    radius: height / 2
                    color: Theme.surfaceHover

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * meterRow.frac
                        color: Theme.text
                        Behavior on width {
                            // Brightness is driven by fast key-repeats - keep it
                            // snappier so the bar never lags the keypress.
                            NumberAnimation {
                                duration: meterRow.isVol ? 120 : 90
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                // value
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    horizontalAlignment: Text.AlignRight
                    text: meterRow.muted ? "Muted" : (meterRow.pct + "%")
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
            }

            // ---------------- caps lock ----------------
            Row {
                id: capsRow

                anchors.centerIn: parent
                visible: root._renderMode === "caps"
                spacing: 9

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: OSDService.capsOn ? Theme.accent : Theme.textMuted
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Caps Lock " + (OSDService.capsOn ? "On" : "Off")
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }

            // ---------------- workspace strip ----------------
            Item {
                id: wsView

                readonly property int slotW: 34
                readonly property int activeW: 40
                // Symmetric inner padding; `o` is how far the active pill spills
                // past its own slot on each side.
                readonly property int pad: 8
                readonly property real o: (wsView.activeW - wsView.slotW) / 2
                readonly property int viewportW: 5 * wsView.slotW
                readonly property real contentW: root.ownWorkspaces.length * wsView.slotW
                readonly property real rowX: {
                    const idx = root.ownWorkspaceIndex >= 0 ? root.ownWorkspaceIndex : 0
                    const centred = wsView.width / 2 - (idx * wsView.slotW + wsView.slotW / 2)
                    // Workspace 1 -> active pill's left edge flush at `pad`;
                    // last workspace -> pill's right edge flush at width - pad.
                    const maxX = wsView.pad + wsView.o
                    const minX = Math.min(maxX, (wsView.width - wsView.pad) - wsView.contentW - wsView.o)
                    return Math.max(minX, Math.min(maxX, centred))
                }

                anchors.centerIn: parent
                visible: root._renderMode === "workspace"
                // Tight: just the visible slots + symmetric padding + pill spill.
                width: Math.min(wsView.contentW, wsView.viewportW) + wsView.pad * 2 + wsView.o * 2
                height: 24
                clip: true

                Row {
                    y: 0
                    x: wsView.rowX
                    spacing: 0

                    Behavior on x {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }

                    Repeater {
                        model: root.ownWorkspaces

                        delegate: Item {
                            id: wsSlot

                            required property var modelData

                            width: wsView.slotW
                            height: 24

                            Rectangle {
                                anchors.centerIn: parent
                                visible: wsSlot.modelData.active
                                width: wsView.activeW
                                height: 22
                                radius: height / 2
                                color: Theme.accent
                            }
                            Text {
                                anchors.centerIn: parent
                                text: wsSlot.modelData.id
                                color: wsSlot.modelData.active ? Theme.background : Theme.textDim
                                font.pixelSize: wsSlot.modelData.active ? 12 : 11
                                font.weight: wsSlot.modelData.active ? Font.DemiBold : Font.Medium
                            }
                        }
                    }
                }
            }
        }
    }
}
