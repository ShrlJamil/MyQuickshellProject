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
// Modes: volume / brightness / caps <- OSDService (global; shown on the
// focused screen). The workspace indicator moved to the bar on
// 2026-11-16 (modules/bar/WorkspaceIndicator.qml, same format).
PanelWindow {
    id: root

    required property var modelData

    screen: modelData.screen

    readonly property bool isFocused: Hyprland.focusedMonitor
        && root.modelData.screen
        && Hyprland.focusedMonitor.name === root.modelData.screen.name

    // ---- resolved mode for THIS screen --------------------------------------
    // A deliberate workspace switch wins while its window is open; otherwise the
    // global volume/brightness/caps OSD shows, on the focused screen only.
    readonly property string shownMode: OSDService.active && root.isFocused ? OSDService.mode : ""
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
        radius: height / 2
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.moduleSurfaceOpacity)
        border.width: 1
        border.color: Theme.surfaceHover

        // Shared glass highlight (see ControlTile): inset by the 1px border
        // so the peak never paints over the border stroke; radius reduced
        // to match. Falloff shaped by stops. Below content.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
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
                    font.family: Theme.fontFamily
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
                    font.family: Theme.fontFamily
                    font.weight: Font.DemiBold
                }
            }

        }
    }
}
