import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../../components"
import "../capture"
import "../display"
import "../wallpapers"

Item {
    id: root

    property string activeSurface: "idle"
    signal closeRequested()

    property var screen: null
    property var mediaService: null
    property bool mediaManual: false

    // True while the expanded media surface exists on screen, including its
    // slide-out animation tail - used by Bar to keep the bar MediaPreview
    // hidden until the surface is fully gone (no overlap/flicker).
    readonly property bool mediaSurfacePresent: root.activeSurface === "media"
        || root._prevSurface === "media"
        || (root.allocatedHeight > 0 && root._lastSurface === "media")

    anchors.horizontalCenter: parent.horizontalCenter
    y: 40
    width: parent.width
    clip: true

    property bool surfaceVisible: activeSurface !== "idle"
    property string _lastSurface: "power"

    // The surface being switched AWAY from during a direct surface->surface
    // morph. Kept non-empty for the duration of the 280ms height morph so the
    // outgoing surface stays mounted + painted underneath (no see-through gap on
    // a shrink) and cross-fades out. Empty on open / close.
    property string _prevSurface: ""

    // ---- Universal content-driven sizing --------------------------------
    // The frame just fits whatever the active surface reports as its own
    // natural size. Each surface (PowerMenu, DisplayManager, WallpaperPicker,
    // CaptureBar, MediaPlayer) owns its implicitWidth / implicitHeight - no
    // per-mode magic numbers live here anymore.
    readonly property Item _activeItem: {
        switch (root.activeSurface) {
        case "power": return powerMenuSurface
        case "display": return displaySurface
        case "wallpapers": return wallpaperSurface
        case "capture": return captureBarSurface
        case "media": return mediaPlayerSurface
        default: return null
        }
    }

    // Never exceed 85% of the monitor / 680px - the outer cap that keeps the
    // panel sane on any screen and the fallback when a surface reports nothing.
    readonly property real maxWidth: Math.min(680, parent.width * 0.85)
    readonly property real surfaceWidth: root.maxWidth   // kept for callers

    readonly property real targetWidth: (root._activeItem && root._activeItem.implicitWidth > 0)
        ? Math.min(root._activeItem.implicitWidth, root.maxWidth)
        : root.maxWidth
    readonly property int targetHeight: (root._activeItem && root._activeItem.implicitHeight > 0)
        ? root._activeItem.implicitHeight : 0

    property real allocatedWidth: root.maxWidth
    property int allocatedHeight: 0

    readonly property int gap: 0
    implicitHeight: allocatedHeight
    height: implicitHeight

    // Morph the frame height ONLY on a direct surface->surface switch:
    // _lastSurface / activeSurface both non-idle, AND the panel is already open
    // (allocatedHeight > 0 - the assignment in onTargetHeightChanged is read
    // against the OLD value, so this is still 0 on the opening frame -> snap +
    // pure slide-in; and targetHeight is 0 on close -> snap + pure slide-out).
    Behavior on allocatedHeight {
        enabled: root._lastSurface !== "idle" && root.activeSurface !== "idle"
            && root.allocatedHeight > 0 && root.targetHeight > 0
        NumberAnimation {
            duration: 180
            easing.type: Easing.InOutCubic
            onFinished: root._prevSurface = ""
        }
    }

    // Width morph, same gating as the height morph: enabled only on a direct
    // surface->surface switch (panel already open). Declared BEFORE
    // onTargetHeightChanged so that on the opening frame it still sees the old
    // allocatedHeight (0) -> disabled -> width snaps, no morph on open.
    Behavior on allocatedWidth {
        enabled: root._lastSurface !== "idle" && root.activeSurface !== "idle"
            && root.allocatedHeight > 0
        NumberAnimation { duration: 180; easing.type: Easing.InOutCubic }
    }

    onTargetWidthChanged: {
        // Only track while a surface is active; on close the width is reset by
        // hideTimer once the panel is fully gone (avoids "widen while sliding
        // out").
        if (root.activeSurface !== "idle")
            root.allocatedWidth = root.targetWidth
    }

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
        onTriggered: {
            root.allocatedHeight = 0
            root.allocatedWidth = root.maxWidth
        }
    }

    // Fallback clear for _prevSurface: the morph NumberAnimation's onFinished is
    // the normal path, but this covers the case where it never runs (e.g. two
    // surfaces of identical height -> no-op assign, no animation). Restarted
    // from onActiveSurfaceChanged whenever _prevSurface is set.
    Timer {
        id: prevSurfaceLatch
        interval: 200
        onTriggered: root._prevSurface = ""
    }

    Item {
        id: surfaceWrapper

        anchors.horizontalCenter: parent.horizontalCenter
        // Frame width tracks the animated per-mode width (morphs on a switch,
        // snaps on open). Stays horizontally centred as it narrows.
        width: root.allocatedWidth
        clip: true

        // Content box tracks the animated clip height exactly, so the outgoing
        // (possibly taller) surface always fills the frame while it shrinks -
        // no divergence, no transparent strip. Per-surface opacity below does
        // the cross-dissolve.
        height: root.allocatedHeight

        state: root.activeSurface === "idle" ? "hidden" : "visible"

        states: [
            State {
                name: "hidden"
                PropertyChanges {
                    target: surfaceWrapper
                    // Display slides its whole height. Use displaySurface's own
                    // implicitHeight directly (valid even while hidden, and
                    // correct on both open and close) - NOT surfaceWrapper.height
                    // (== allocatedHeight, still 0 when this transition starts on
                    // open) and NOT targetHeight (0 while activeSurface is idle).
                    y: (root.activeSurface === "display" || root._lastSurface === "display")
                        ? -displaySurface.implicitHeight : -80
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

        // Single unified frame background: one Shape, anchored 1:1 to
        // surfaceWrapper, drawing the concave top notches + rounded bottom in one
        // path. Morphs with the wrapper (a brief 1-frame re-tessellation on a
        // size change is the accepted trade-off for a clean, hole-free frame).
        Shape {
            id: frameBackground

            anchors.fill: parent
            antialiasing: true
            asynchronous: false
            vendorExtensionsEnabled: true
            preferredRendererType: Shape.CurveRenderer
            z: -1

            readonly property real notchSize: 18
            readonly property real bottomRadius: Theme.cornerRadius

            ShapePath {
                fillColor: Theme.background
                strokeColor: "transparent"
                strokeWidth: 0

                startX: 0
                startY: 0

                PathCubic {
                    control1X: frameBackground.notchSize * 0.5
                    control1Y: 0
                    control2X: frameBackground.notchSize
                    control2Y: frameBackground.notchSize * 0.5
                    x: frameBackground.notchSize
                    y: frameBackground.notchSize
                }
                PathLine {
                    x: frameBackground.notchSize
                    y: frameBackground.height - frameBackground.bottomRadius
                }
                PathQuad {
                    controlX: frameBackground.notchSize
                    controlY: frameBackground.height
                    x: frameBackground.notchSize + frameBackground.bottomRadius
                    y: frameBackground.height
                }
                PathLine {
                    x: frameBackground.width - frameBackground.notchSize - frameBackground.bottomRadius
                    y: frameBackground.height
                }
                PathQuad {
                    controlX: frameBackground.width - frameBackground.notchSize
                    controlY: frameBackground.height
                    x: frameBackground.width - frameBackground.notchSize
                    y: frameBackground.height - frameBackground.bottomRadius
                }
                PathLine {
                    x: frameBackground.width - frameBackground.notchSize
                    y: frameBackground.notchSize
                }
                PathCubic {
                    control1X: frameBackground.width - frameBackground.notchSize
                    control1Y: frameBackground.notchSize * 0.5
                    control2X: frameBackground.width - frameBackground.notchSize * 0.5
                    control2Y: 0
                    x: frameBackground.width
                    y: 0
                }
                PathLine {
                    x: 0
                    y: 0
                }
            }
        }

        // Shared per-surface show/fade rules:
        //   visible  = active | prev (switch linger) | closing linger
        //   opacity  = 1 while active or closing-linger, else 0
        //   Behavior = only runs while _prevSurface is set (a live switch), so
        //              open / close never fade - they're the pure y slide.
        PowerMenu {
            id: powerMenuSurface
            width: parent.width
            visible: root.activeSurface === "power" || root._prevSurface === "power"
                || (root.allocatedHeight > 0 && root._lastSurface === "power")
            opacity: (root.activeSurface === "power"
                || (root.activeSurface === "idle" && root.allocatedHeight > 0 && root._lastSurface === "power")) ? 1 : 0
            Behavior on opacity {
                enabled: root._prevSurface !== ""
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            onCloseRequested: root.closeRequested()
        }

        CaptureBar {
            id: captureBarSurface
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.activeSurface === "capture" || root._prevSurface === "capture"
                || (root.allocatedHeight > 0 && root._lastSurface === "capture")
            opacity: (root.activeSurface === "capture"
                || (root.activeSurface === "idle" && root.allocatedHeight > 0 && root._lastSurface === "capture")) ? 1 : 0
            Behavior on opacity {
                enabled: root._prevSurface !== ""
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
        }

        DisplayManager {
            id: displaySurface
            width: parent.width
            visible: root.activeSurface === "display" || root._prevSurface === "display"
                || (root.allocatedHeight > 0 && root._lastSurface === "display")
            opacity: (root.activeSurface === "display"
                || (root.activeSurface === "idle" && root.allocatedHeight > 0 && root._lastSurface === "display")) ? 1 : 0
            Behavior on opacity {
                enabled: root._prevSurface !== ""
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            onCloseRequested: root.closeRequested()
        }

        WallpaperPicker {
            id: wallpaperSurface
            width: parent.width
            visible: root.activeSurface === "wallpapers" || root._prevSurface === "wallpapers"
                || (root.allocatedHeight > 0 && root._lastSurface === "wallpapers")
            opacity: (root.activeSurface === "wallpapers"
                || (root.activeSurface === "idle" && root.allocatedHeight > 0 && root._lastSurface === "wallpapers")) ? 1 : 0
            Behavior on opacity {
                enabled: root._prevSurface !== ""
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            onCloseRequested: root.closeRequested()
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

        MediaPlayer {
            id: mediaPlayerSurface
            width: parent.width
            mediaService: root.mediaService
            manual: root.mediaManual
            active: root.activeSurface === "media"
            visible: root.activeSurface === "media" || root._prevSurface === "media"
                || (root.allocatedHeight > 0 && root._lastSurface === "media")
            opacity: (root.activeSurface === "media"
                || (root.activeSurface === "idle" && root.allocatedHeight > 0 && root._lastSurface === "media")) ? 1 : 0
            Behavior on opacity {
                enabled: root._prevSurface !== ""
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            onCloseRequested: root.closeRequested()
        }
    }

    onActiveSurfaceChanged: {
        console.log("[DynamicCenter] Active surface changed to:", root.activeSurface)

        // Capture runs outside barState.mode; entering any other real surface
        // must force it down so its latched barVisible / input grab can't shadow
        // the incoming mode. Safe + loop-free: barState.mode has already won the
        // activeSurface binding by the time this fires, so clearing barVisible
        // doesn't re-evaluate to a different surface.
        if (root.activeSurface !== "capture" && root.activeSurface !== "idle"
            && CaptureService.barVisible) {
            CaptureService.closeBar()
        }

        // Direct surface->surface switch while already open: remember the
        // outgoing surface so it lingers + cross-fades during the height morph.
        // Cleared by the morph NumberAnimation's onFinished (see above).
        if (root._lastSurface !== "idle" && root.activeSurface !== "idle"
            && root._lastSurface !== root.activeSurface && root.allocatedHeight > 0) {
            root._prevSurface = root._lastSurface
            prevSurfaceLatch.restart()
        } else if (root.activeSurface === "idle") {
            // Closing - no linger, drop any half-finished switch state.
            root._prevSurface = ""
            prevSurfaceLatch.stop()
        }

        if (root.activeSurface !== "idle")
            root._lastSurface = root.activeSurface

        if (root.activeSurface === "power") {
            powerMenuSurface.reset()
            powerMenuSurface.forceActiveFocus()
        } else if (root.activeSurface === "wallpapers") {
            wallpaperSurface.forceActiveFocus()
        } else if (root.activeSurface === "capture") {
            captureBarSurface.forceActiveFocus()
        } else if (root.activeSurface === "display") {
            // Arms the bar's HyprlandFocusGrab so Esc + click-outside dismiss
            // work (DisplayManager has no PanelWindow / grab of its own).
            displaySurface.forceActiveFocus()
        } else if (root.activeSurface === "media") {
            // Same story - no grab of its own. Focus here + the bar's
            // surfaceActive (true for auto-expand too now) let Esc / click
            // outside close it before the 4s auto-hide.
            mediaPlayerSurface.forceActiveFocus()
        }
    }
}
