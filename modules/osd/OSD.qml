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
    // ---- workspace digit slider -------------------------------------------
    // Minimal "Workspace N" indicator: static label + sliding badge. Only the
    // badge (accent pill + digit, moving as one unit) animates, giving an
    // infinite-carousel feel. Direction follows the id delta at switch time
    // (+1 = ids increasing, new badge enters from the right).
    property string wsDigitShown: "1"
    property bool wsFrontIsA: true
    property int wsDigitDir: 1

    function _wsDigitInit(id) {
        const s = String(id)
        const R = badgeSlot.pad
        root.wsDigitShown = s
        root.wsFrontIsA = true
        root.wsDigitDir = 1
        badgeA.numText = s
        badgeB.numText = s
        badgeA.x = R
        badgeB.x = R + badgeSlot.span
    }

    function _wsDigitGo(id, dir) {
        const s = String(id)
        const W = badgeSlot.span
        const R = badgeSlot.pad
        // Settle instantly to rest (covers mid-flight retriggers so a stale
        // badge can never linger), then animate old-out / new-in.
        badgeABeh.enabled = false
        badgeBBeh.enabled = false
        if (root.wsFrontIsA) {
            badgeA.x = R
            badgeB.numText = s
            badgeB.x = R + dir * W
        } else {
            badgeB.x = R
            badgeA.numText = s
            badgeA.x = R + dir * W
        }
        badgeABeh.enabled = true
        badgeBBeh.enabled = true
        if (root.wsFrontIsA) {
            badgeA.x = R - dir * W
            badgeB.x = R
        } else {
            badgeB.x = R - dir * W
            badgeA.x = R
        }
        root.wsFrontIsA = !root.wsFrontIsA
        root.wsDigitShown = s
        root.wsDigitDir = dir
    }

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
            root._wsDigitInit(root.ownWorkspaceId)
            return
        }
        if (root.ownWorkspaceId === root._lastSeenWorkspaceId)
            return
        root._wsDigitGo(root.ownWorkspaceId, root.ownWorkspaceId >= root._lastSeenWorkspaceId ? 1 : -1)
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
        Behavior on width {
            NumberAnimation {
                duration: 130
                easing.type: Easing.OutCubic
            }
        }
        radius: 16
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.surfaceOpacity)
        border.width: 1
        border.color: Theme.surfaceHover

        // Shared glass highlight (see ControlTile): inset by the 1px border
        // so the peak never paints over the border stroke; radius reduced
        // to match. Falloff shaped by stops. Below content.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 15
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(1, 1, 1, Theme.materialHighlightOpacity)
                }
                GradientStop {
                    position: 0.4
                    color: "transparent"
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }

        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            OpacityAnimator {
                duration: root.shown ? 130 : 100
                easing.type: root.shown ? Easing.OutCubic : Easing.InCubic
            }
        }

        transform: Translate {
            y: root.shown ? 0 : 8
            Behavior on y {
                NumberAnimation {
                    duration: root.shown ? 140 : 110
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

                // speaker glyph - dynamic SVG (assets/volume/), tinted Theme.icon
                // (glyph itself still swaps by level/mute state)
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
                        color: Theme.icon
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
                        color: Theme.icon
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

            // ---------------- workspace label ----------------
            Item {
                id: wsView

                anchors.centerIn: parent
                visible: root._renderMode === "workspace"
                width: wsRow.implicitWidth
                height: 24

                Row {
                    id: wsRow

                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Workspace"
                        color: Theme.text
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }

                    Item {
                        id: badgeSlot

                        // Slide travel stays 54px; symmetric 8px padding each
                        // side keeps the badge clear of the wrapper edge.
                        // Rest position is `pad`; park/fade derive from these.
                        readonly property int pad: 8
                        readonly property real span: 54

                        width: 40 + pad * 2
                        height: 24
                        clip: true

                        Item {
                            id: badgeA

                            property string numText: "1"

                            width: 40
                            height: 24
                            x: badgeSlot.pad
                            // Fade near the slot edge so the round badge never
                            // shows a straight clip cut mid-slide; 1 at rest.
                            opacity: 1 - Math.min(1, Math.abs(x - badgeSlot.pad) / (badgeSlot.span / 2))

                            Rectangle {
                                anchors.centerIn: parent
                                width: 40
                                height: 22
                                radius: height / 2
                                color: Theme.accent
                            }

                            Text {
                                anchors.centerIn: parent
                                text: badgeA.numText
                                color: Theme.background
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            Behavior on x {
                                id: badgeABeh
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        }

                        Item {
                            id: badgeB

                            property string numText: "1"

                            width: 40
                            height: 24
                            x: badgeSlot.pad + badgeSlot.span
                            opacity: 1 - Math.min(1, Math.abs(x - badgeSlot.pad) / (badgeSlot.span / 2))

                            Rectangle {
                                anchors.centerIn: parent
                                width: 40
                                height: 22
                                radius: height / 2
                                color: Theme.accent
                            }

                            Text {
                                anchors.centerIn: parent
                                text: badgeB.numText
                                color: Theme.background
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            Behavior on x {
                                id: badgeBBeh
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }
        }
    }
}
