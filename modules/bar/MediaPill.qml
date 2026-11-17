import QtQuick
import Qt5Compat.GraphicalEffects
import "../../components"

Item {
    id: root

    required property var mediaService

    signal activateRequested()

    readonly property bool active: root.mediaService && root.mediaService.hasMedia

    property bool show: false

    // True while the media popover is open: the pill wears the light
    // active scheme like the bar's other open-state widgets.
    property bool popoverOpen: false

    readonly property int pillHeight: 30
    readonly property int artworkSize: 22
    // 4 px: the artwork (22 px in the 30 px pill) then sits
    // concentric with the pill's left cap - the same inset the
    // minimal circle has - snug to the left as Sahrul asked on
    // 2026-11-17 (normal mode; the shrink path is unaffected
    // because its handover already centred the artwork at 4).
    readonly property int padH: 4
    readonly property int artGap: 6
    readonly property int maxTextWidth: 115
    readonly property real scrollSpeed: 22

    readonly property string trackText: {
        if (!root.active)
            return ""
        const t = root.mediaService.title || ""
        const a = root.mediaService.artist || ""
        if (t.length > 0 && a.length > 0)
            return t + " \u00b7 " + a
        return t.length > 0 ? t : a
    }

    // The pill animates its own width (ActivityIsland grow/shrink):
    // the background fills the item, so the rounded end stays rounded
    // at every width instead of being sliced by a parent's clip.
    // Visible latches until the shrink lands, so the animation out
    // is seen at all.
    visible: root.show || root.width > 0.5
    implicitWidth: root.padH * 2 + root.artworkSize + root.artGap + textView.width
    implicitHeight: root.pillHeight
    width: root.show ? root.implicitWidth : 0
    height: implicitHeight
    clip: true

    Behavior on width {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    // A shrink hands over to the slot's minimal at exactly
    // 30 px: by then the pill IS the minimal - a round circle
    // showing the artwork, centred exactly like the minimal's
    // (see the artwork margin below) - so the pill cuts out and
    // the minimal cuts in with no visible change. Above 30 px
    // the pill is fully itself; a grow fades in over 16 px.
    opacity: (!root.show && root.width <= 30) ? 0 : Math.min(1, root.width / 16)

    // The TITLE dissolves as the pill collapses toward minimal
    // size (it would otherwise be sliced by the narrowing clip
    // for the whole shrink tail). The artwork does NOT dissolve:
    // it is the form's identity and stays visible into the
    // 30 px handover circle.
    readonly property real contentOpacity: Math.max(0, Math.min(1, (root.width - 30) / 15))

    HoverHandler {
        id: hoverHandler

        enabled: root.show
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler

        enabled: root.show
        onTapped: root.activateRequested()
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.popoverOpen ? ((tapHandler.pressed || hoverHandler.hovered) ? Theme.activeSurfaceHover : Theme.activeSurface)
            : Theme.backgroundInset
    }

    Rectangle {
        id: artwork

        width: root.artworkSize
        height: root.artworkSize
        radius: width / 2
        color: root.popoverOpen ? Qt.rgba(Theme.onActiveSurface.r, Theme.onActiveSurface.g, Theme.onActiveSurface.b, 0.15) : Theme.surface

        anchors.left: parent.left
        // padH IS the centred inset (4), so the artwork sits
        // exactly where the minimal's centred artwork sits at
        // every width - the 30 px handover needs no easing.
        anchors.leftMargin: root.padH
        anchors.verticalCenter: parent.verticalCenter

        Image {
            id: art

            anchors.fill: parent
            source: root.active ? root.mediaService.artwork : ""
            sourceSize.width: root.artworkSize * 2
            sourceSize.height: root.artworkSize * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: art.status === Image.Ready
            layer.enabled: art.status === Image.Ready
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: artwork.width
                    height: artwork.height
                    radius: artwork.width / 2
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: "\u266a"
            color: root.popoverOpen ? Theme.onActiveSurfaceDim : Theme.textMuted
            style: Text.Raised
            styleColor: root.popoverOpen ? Qt.rgba(1, 1, 1, 0.35) : Theme.textShadow
            font.pixelSize: 10
        }
    }

    Item {
        id: textView

        opacity: root.contentOpacity

        width: Math.min(metric.implicitWidth, root.maxTextWidth)
        height: metric.implicitHeight
        clip: true

        anchors.left: artwork.right
        anchors.leftMargin: root.artGap
        anchors.verticalCenter: parent.verticalCenter

        readonly property bool overflow: metric.implicitWidth > textView.width + 0.5
        readonly property real loopDist: metric.implicitWidth + separator.implicitWidth

        onOverflowChanged: if (!overflow) marquee.x = 0

        Text {
            id: metric

            visible: false
            text: root.trackText
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        Text {
            id: separator

            visible: false
            text: "   \u00b7   "
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        Text {
            id: marquee

            text: root.trackText + (textView.overflow ? separator.text + root.trackText : "")
            color: root.popoverOpen ? Theme.onActiveSurface : Theme.text
            style: Text.Raised
            styleColor: root.popoverOpen ? Qt.rgba(1, 1, 1, 0.35) : Theme.textShadow
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            maximumLineCount: 1
            x: 0

            onTextChanged: marquee.x = 0

            SequentialAnimation on x {
                running: textView.overflow && root.show
                loops: Animation.Infinite
                PauseAnimation { duration: 1200 }
                NumberAnimation {
                    to: -textView.loopDist
                    duration: Math.max(900, textView.loopDist / root.scrollSpeed * 1000)
                    easing.type: Easing.Linear
                }
                PauseAnimation { duration: 800 }
                ScriptAction { script: marquee.x = 0 }
            }
        }
    }
}
