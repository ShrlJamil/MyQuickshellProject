import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../components"

// Permanent bar resident: this screen's active Hyprland workspace as a
// "Workspace" label + accent badge with the workspace id. Moved out of
// the bottom-centre OSD on 2026-11-16 (Sahrul's call): the layout is
// the OSD's, per-screen like the OSD was - each bar tracks its own
// monitor's active workspace. Negative ids (special workspaces) are
// ignored, exactly as the OSD ignored them, so the badge keeps showing
// the last normal workspace.
//
// Switch animation (reworked 2026-11-16, Sahrul's call): the OSD's
// long carousel slide crossed the whole slot and read as clipped at
// both edges. Here the change is fade-led: the old badge fades out
// while the new one fades in, and the slide is only a slight drift
// (badgeSlot.drift px) through the centre, eased InOutCubic so the
// movement concentrates mid-travel near the rest position. The badge
// never reaches the slot edges while visible, so nothing looks cut.
Item {
    id: root

    required property var screen

    readonly property var ownMonitor: root.screen ? Hyprland.monitorFor(root.screen) : null
    readonly property int ownWorkspaceId: root.ownMonitor?.activeWorkspace?.id ?? -1

    implicitWidth: wsRow.implicitWidth
    implicitHeight: 24

    // ---- workspace digit crossfade -------------------------------------------
    property string wsDigitShown: "1"
    property bool wsFrontIsA: true
    property int wsDigitDir: 1
    property int _lastSeenWorkspaceId: -1

    function _wsDigitInit(id) {
        const s = String(id)
        const R = badgeSlot.pad
        root.wsDigitShown = s
        root.wsFrontIsA = true
        root.wsDigitDir = 1
        badgeA.numText = s
        badgeB.numText = s
        badgeA.x = R
        badgeA.opacity = 1
        badgeB.x = R
        badgeB.opacity = 0
    }

    function _wsDigitGo(id, dir) {
        const s = String(id)
        const R = badgeSlot.pad
        const D = badgeSlot.drift
        // Settle instantly to rest (covers mid-flight retriggers so a
        // stale badge can never linger), then crossfade with the
        // slight drift: out through -dir, in from +dir.
        badgeABeh.enabled = false
        badgeBBeh.enabled = false
        badgeAOpBeh.enabled = false
        badgeBOpBeh.enabled = false
        if (root.wsFrontIsA) {
            badgeA.x = R
            badgeA.opacity = 1
            badgeB.numText = s
            badgeB.x = R + dir * D
            badgeB.opacity = 0
        } else {
            badgeB.x = R
            badgeB.opacity = 1
            badgeA.numText = s
            badgeA.x = R + dir * D
            badgeA.opacity = 0
        }
        badgeABeh.enabled = true
        badgeBBeh.enabled = true
        badgeAOpBeh.enabled = true
        badgeBOpBeh.enabled = true
        if (root.wsFrontIsA) {
            badgeA.x = R - dir * D
            badgeA.opacity = 0
            badgeB.x = R
            badgeB.opacity = 1
        } else {
            badgeB.x = R - dir * D
            badgeB.opacity = 0
            badgeA.x = R
            badgeA.opacity = 1
        }
        root.wsFrontIsA = !root.wsFrontIsA
        root.wsDigitShown = s
        root.wsDigitDir = dir
    }

    function _wsSync() {
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
    }

    onOwnWorkspaceIdChanged: root._wsSync()
    Component.onCompleted: root._wsSync()

    Row {
        id: wsRow

        anchors.centerIn: parent
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Workspace"
            // Bar widget text style, same as the clock beside it
            // (the OSD original used Theme.text at 13px Bold).
            color: Theme.icon
            style: Text.Raised
            styleColor: Theme.textShadow
            font.pixelSize: 14
            font.family: Theme.fontFamily
            font.weight: Font.Black
        }

        Item {
            id: badgeSlot

            // The badges live at `pad` and only ever drift `drift` px
            // away from it while fading, so the slot is just the badge
            // plus symmetric padding; the clip is a formality now.
            readonly property int pad: 8
            readonly property real drift: 10

            width: 40 + pad * 2
            height: 24
            clip: true

            Item {
                id: badgeA

                property string numText: "1"

                width: 40
                height: 24
                x: badgeSlot.pad
                opacity: 1

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
                    font.family: Theme.fontFamily
                    font.weight: Font.Bold
                }

                Behavior on x {
                    id: badgeABeh
                    NumberAnimation { duration: 240; easing.type: Easing.InOutCubic }
                }

                Behavior on opacity {
                    id: badgeAOpBeh
                    NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
                }
            }

            Item {
                id: badgeB

                property string numText: "1"

                width: 40
                height: 24
                x: badgeSlot.pad
                opacity: 0

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
                    font.family: Theme.fontFamily
                    font.weight: Font.Bold
                }

                Behavior on x {
                    id: badgeBBeh
                    NumberAnimation { duration: 240; easing.type: Easing.InOutCubic }
                }

                Behavior on opacity {
                    id: badgeBOpBeh
                    NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
