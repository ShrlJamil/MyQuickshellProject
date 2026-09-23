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
    // close animation tail - used by Bar to keep the bar MediaPreview
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
        case "power": return powerLoader.item
        case "display": return displayLoader.item
        case "wallpapers": return wallpaperLoader.item
        case "capture": return captureLoader.item
        case "media": return mediaLoader.item
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

    // Height reveal: open grows 0 -> target, close shrinks target -> 0, and a
    // direct surface->surface switch morphs between heights. The top edge
    // never moves (surfaceWrapper.y is permanently 0); the wrapper clip
    // reveals the static-size content as the frame grows. Durations mirror the
    // old slide: 220 OutCubic open / 160 InCubic close (display 300 / 220),
    // 180 InOutCubic switch. Conditions are stable mid-flight: _prevSurface is
    // set only during a live switch, activeSurface only flips on open/close.
    Behavior on allocatedHeight {
        NumberAnimation {
            duration: {
                if (root._prevSurface !== "")
                    return 180
                if (root.activeSurface === "idle")
                    return root._lastSurface === "display" ? 220 : 160
                return root.activeSurface === "display" ? 300 : 220
            }
            easing.type: {
                if (root._prevSurface !== "")
                    return Easing.InOutCubic
                if (root.activeSurface === "idle")
                    return Easing.InCubic
                return Easing.OutCubic
            }
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

    // Content materialization for the height reveal. Surfaces fade in while
    // the frame grows (no sliced-content flash at open) and fade out fast at
    // close start so the shrink reads clean; a live switch keeps its 150ms
    // crossfade. Used by every Loader item's opacity Behavior below.
    function _contentFadeDuration() {
        if (root._prevSurface !== "")
            return 150
        if (root.targetHeight === 0)
            return 90
        return 140
    }

    onTargetWidthChanged: {
        // Only track while a surface is active; on close the width is reset by
        // hideTimer once the panel is fully gone (avoids "widen while closing").
        if (root.activeSurface !== "idle")
            root.allocatedWidth = root.targetWidth
    }

    onTargetHeightChanged: {
        if (targetHeight > 0) {
            hideTimer.stop()
            allocatedHeight = targetHeight + gap
        } else if (allocatedHeight > 0) {
            // Shrink visibly to 0 through the Behavior above (160ms, 220 for
            // display) - hideTimer below only resets width + re-zeroes safely.
            allocatedHeight = 0
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        // Past the longest close shrink (220ms display) so the timer never
        // cuts the visible animation with a snap.
        interval: 250
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

        // y is permanently 0: open/close is a top-anchored height reveal driven
        // by the allocatedHeight Behavior above, never a slide.
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
            // Notch interpolation factor: 0 at zero height (flat top) -> 1 once
            // the frame is tall enough to contain the full 18px notch. Purely
            // derived from the animated height, so open/close stay symmetric
            // with no threshold snap, timer, or extra animation.
            // Notch reveal progress, purely derived from the animated height.
            // Open/active: flat below 32px, full notch at/above 56px. Close
            // (idle): full notch down to 48px, flat at/below 24px. No timer,
            // no animation, symmetric by height except the open/close bands.
            readonly property real notchRevealT: {
                const h = frameBackground.height
                if (root.activeSurface === "idle")
                    return Math.max(0, Math.min(1, (h - 24) / 24))
                return Math.max(0, Math.min(1, (h - 32) / 24))
            }
            // Integer pixel notch {0..18}: single source for every animated notch
            // coordinate (mirrored both sides) so joins land on whole pixels.
            readonly property int notchPx: Math.round(frameBackground.notchSize * frameBackground.notchRevealT)

            ShapePath {
                fillColor: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.surfaceOpacity)
                strokeColor: "transparent"
                strokeWidth: 0

                startX: 0
                startY: 0

                PathCubic {
                    control1X: frameBackground.notchPx / 2
                    control1Y: 0
                    control2X: frameBackground.notchPx
                    control2Y: frameBackground.notchPx / 2
                    x: frameBackground.notchPx
                    y: frameBackground.notchPx
                }
                PathLine {
                    x: frameBackground.notchPx
                    y: frameBackground.height - frameBackground.bottomRadius
                }
                PathQuad {
                    controlX: frameBackground.notchPx
                    controlY: frameBackground.height
                    x: frameBackground.notchPx + frameBackground.bottomRadius
                    y: frameBackground.height
                }
                PathLine {
                    x: frameBackground.width - frameBackground.notchPx - frameBackground.bottomRadius
                    y: frameBackground.height
                }
                PathQuad {
                    controlX: frameBackground.width - frameBackground.notchPx
                    controlY: frameBackground.height
                    x: frameBackground.width - frameBackground.notchPx
                    y: frameBackground.height - frameBackground.bottomRadius
                }
                PathLine {
                    x: frameBackground.width - frameBackground.notchPx
                    y: frameBackground.notchPx
                }
                PathCubic {
                    control1X: frameBackground.width - frameBackground.notchPx
                    control1Y: frameBackground.notchPx / 2
                    control2X: frameBackground.width - frameBackground.notchPx / 2
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
        //
        // Each surface lives behind a latched Loader: nothing is instantiated
        // at startup; the first open creates it synchronously (no async pop,
        // geometry valid on the opening frame) and it stays loaded afterwards.
        // Loader.active honors the existing visibility conditions plus a
        // one-way load latch (see below) - the mode remains solely
        // `activeSurface` (+ the transient `_prevSurface`/`_lastSurface`).
        Loader {
            id: powerLoader
            width: parent.width
            active: root._powerLatched || root.activeSurface === "power" || root._prevSurface === "power"
                || (root.allocatedHeight > 0 && root._lastSurface === "power")
            sourceComponent: PowerMenu {
                width: parent.width
                visible: root.activeSurface === "power" || root._prevSurface === "power"
                    || (root.allocatedHeight > 0 && root._lastSurface === "power")
                opacity: root.activeSurface === "power" ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root._contentFadeDuration()
                        easing.type: Easing.OutCubic
                    }
                }
                onCloseRequested: root.closeRequested()
            }
            onLoaded: if (root.activeSurface === "power") root._focusSurface("power")
        }

        Loader {
            id: captureLoader
            anchors.horizontalCenter: parent.horizontalCenter
            active: root._captureLatched || root.activeSurface === "capture" || root._prevSurface === "capture"
                || (root.allocatedHeight > 0 && root._lastSurface === "capture")
            sourceComponent: CaptureBar {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.activeSurface === "capture" || root._prevSurface === "capture"
                    || (root.allocatedHeight > 0 && root._lastSurface === "capture")
                opacity: root.activeSurface === "capture" ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root._contentFadeDuration()
                        easing.type: Easing.OutCubic
                    }
                }
            }
            onLoaded: if (root.activeSurface === "capture") root._focusSurface("capture")
        }

        Loader {
            id: displayLoader
            width: parent.width
            active: root._displayLatched || root.activeSurface === "display" || root._prevSurface === "display"
                || (root.allocatedHeight > 0 && root._lastSurface === "display")
            sourceComponent: DisplayManager {
                width: parent.width
                visible: root.activeSurface === "display" || root._prevSurface === "display"
                    || (root.allocatedHeight > 0 && root._lastSurface === "display")
                opacity: root.activeSurface === "display" ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root._contentFadeDuration()
                        easing.type: Easing.OutCubic
                    }
                }
                onCloseRequested: root.closeRequested()
            }
            onLoaded: if (root.activeSurface === "display") root._focusSurface("display")
        }

        Loader {
            id: wallpaperLoader
            width: parent.width
            active: root._wallpapersLatched || root.activeSurface === "wallpapers" || root._prevSurface === "wallpapers"
                || (root.allocatedHeight > 0 && root._lastSurface === "wallpapers")
            sourceComponent: WallpaperPicker {
                width: parent.width
                visible: root.activeSurface === "wallpapers" || root._prevSurface === "wallpapers"
                    || (root.allocatedHeight > 0 && root._lastSurface === "wallpapers")
                opacity: root.activeSurface === "wallpapers" ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root._contentFadeDuration()
                        easing.type: Easing.OutCubic
                    }
                }
                onCloseRequested: root.closeRequested()
            }
            onLoaded: if (root.activeSurface === "wallpapers") root._focusSurface("wallpapers")
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

        Loader {
            id: mediaLoader
            width: parent.width
            active: root._mediaLatched || root.activeSurface === "media" || root._prevSurface === "media"
                || (root.allocatedHeight > 0 && root._lastSurface === "media")
            sourceComponent: MediaPlayer {
                width: parent.width
                mediaService: root.mediaService
                manual: root.mediaManual
                active: root.activeSurface === "media"
                visible: root.activeSurface === "media" || root._prevSurface === "media"
                    || (root.allocatedHeight > 0 && root._lastSurface === "media")
                opacity: root.activeSurface === "media" ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root._contentFadeDuration()
                        easing.type: Easing.OutCubic
                    }
                }
                onCloseRequested: root.closeRequested()
            }
            onLoaded: if (root.activeSurface === "media" && root.mediaManual) root._focusSurface("media")
        }
    }

    // One-way load latches: set when a surface first becomes active, never
    // cleared. These are load-lifecycle flags, not mode state - the mode
    // remains solely `activeSurface` (+ `_prevSurface`/`_lastSurface`).
    property bool _powerLatched: false
    property bool _captureLatched: false
    property bool _displayLatched: false
    property bool _wallpapersLatched: false
    property bool _mediaLatched: false

    function _surfaceItem(name) {
        switch (name) {
        case "power": return powerLoader.item
        case "capture": return captureLoader.item
        case "display": return displayLoader.item
        case "wallpapers": return wallpaperLoader.item
        case "media": return mediaLoader.item
        default: return null
        }
    }

    function _focusSurface(name) {
        var it = root._surfaceItem(name)
        if (!it)
            return
        if (name === "power" && it.reset)
            it.reset()
        it.forceActiveFocus()
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
            root._powerLatched = true
            root._focusSurface("power")
        } else if (root.activeSurface === "wallpapers") {
            root._wallpapersLatched = true
            root._focusSurface("wallpapers")
        } else if (root.activeSurface === "capture") {
            root._captureLatched = true
            root._focusSurface("capture")
        } else if (root.activeSurface === "display") {
            root._displayLatched = true
            // Arms the bar's HyprlandFocusGrab so Esc + click-outside dismiss
            // work (DisplayManager has no PanelWindow / grab of its own).
            root._focusSurface("display")
        } else if (root.activeSurface === "media") {
            root._mediaLatched = true
            // Manual open only: route focus so Escape works. Auto-expand never
            // takes focus and relies on the 3s auto-hide timer instead.
            if (root.mediaManual) root._focusSurface("media")
        }
    }
}
