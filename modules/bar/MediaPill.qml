import QtQuick
import Qt5Compat.GraphicalEffects
import "../../components"

Item {
    id: root

    required property var mediaService

    signal activateRequested()

    readonly property bool active: root.mediaService && root.mediaService.hasMedia

    property bool show: false

    readonly property int pillHeight: 26
    readonly property int artworkSize: 18
    readonly property int padH: 8
    readonly property int artGap: 6
    readonly property int maxTextWidth: 168
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

    visible: root.show
    implicitWidth: root.padH * 2 + root.artworkSize + root.artGap + textView.width
    implicitHeight: root.pillHeight
    width: implicitWidth
    height: implicitHeight

    HoverHandler {
        enabled: root.show
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.show
        onTapped: root.activateRequested()
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.surface
    }

    Rectangle {
        id: artwork

        width: root.artworkSize
        height: root.artworkSize
        radius: width / 2
        color: Theme.background

        anchors.left: parent.left
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
            color: Theme.textMuted
            font.pixelSize: 10
        }
    }

    Item {
        id: textView

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
            color: Theme.text
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
