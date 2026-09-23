import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Widgets
import "../../components"

Item {
    id: root

    property string label: ""
    property string iconSource: ""
    property bool active: false
    property bool round: false

    // Opt-in radius override (e.g. a full pill on a non-round tile). Negative =
    // use the default (min-dimension/2 when `round`, else 22).
    property real radiusOverride: -1

    // Theme-icon sources (Quickshell.iconPath) already arrive coloured and are
    // drawn as-is. A local `file:` SVG is a solid #000 glyph, so it goes through
    // an Image + ColorOverlay instead and tints with the tile's active state.
    readonly property bool _localIcon: root.iconSource.startsWith("file:")

    readonly property real cornerRadius: root.radiusOverride >= 0 ? root.radiusOverride
        : root.round ? Math.min(root.width, root.height) / 2 : 22
    readonly property real radius: root.cornerRadius

    readonly property real iconSlotSize: root.round ? Math.max(26, Math.round(Math.min(root.width, root.height) * 0.4)) : 34
    readonly property real iconSize: root.round ? Math.max(22, Math.round(Math.min(root.width, root.height) * 0.34)) : 30
    readonly property int labelPixelSize: root.round ? Math.max(9, Math.min(12, Math.round(Math.min(root.width, root.height) * 0.12))) : 12

    Rectangle {
        id: tile

        anchors.fill: parent

        radius: root.cornerRadius
        border.width: 0
        border.color: "transparent"
        // Active  -> light muted (Theme.activeTile) surface, Theme.accent contents.
        // Inactive -> standard dark surface (Theme.background).
        color: {
            // Active tiles are solid state surfaces: no surfaceOpacity alpha.
            // Inactive tiles stay translucent material.
            if (root.active)
                return hover.hovered ? Qt.darker(Theme.activeTile, 1.06) : Theme.activeTile
            const c = hover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background
            return Qt.rgba(c.r, c.g, c.b, Theme.surfaceOpacity)
        }

        HoverHandler {
            id: hover

            cursorShape: Qt.PointingHandCursor
        }

        Item {
            anchors.centerIn: parent

            width: root.iconSlotSize
            height: root.iconSlotSize

            // ---- theme icon (already coloured) ----
            IconImage {
                anchors.centerIn: parent

                width: root.iconSize
                height: root.iconSize

                source: root._localIcon ? "" : root.iconSource
                asynchronous: true
                visible: !root._localIcon && root.iconSource !== ""
            }

            // ---- custom solid-#000 SVG, tinted to follow the tile state ----
            Image {
                id: svgIcon

                anchors.centerIn: parent

                width: root.iconSize
                height: root.iconSize

                source: root._localIcon ? root.iconSource : ""
                sourceSize.width: root.iconSize * 2
                sourceSize.height: root.iconSize * 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                visible: false
            }

            ColorOverlay {
                anchors.fill: svgIcon
                source: svgIcon
                visible: root._localIcon && svgIcon.status === Image.Ready
                color: root.active ? Theme.accent : Theme.icon
            }
        }
    }
}
