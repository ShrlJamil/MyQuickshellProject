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
    readonly property real iconSize: root.round ? Math.max(22, Math.round(Math.min(root.width, root.height) * 0.35)) : 30
    readonly property int labelPixelSize: root.round ? 13 : 12

    Rectangle {
        id: tile

        anchors.fill: parent

        radius: root.cornerRadius
        border.width: 0
        border.color: "transparent"
        // Active  -> LIGHT seed surface (Theme.activeSurface) with dark
        // seed foreground (glyph + label flip to onActiveSurface).
        // Inactive -> sunken panel tone; hover lifts to panelSurface.
        color: {
            // Active tiles are solid state surfaces: no surfaceOpacity alpha.
            // Inactive tiles stay translucent material.
            if (root.active)
                return hover.hovered ? Theme.activeSurfaceHover : Theme.activeSurface
            const c = hover.hovered ? Theme.panelSurface : Theme.backgroundSunken
            return Qt.rgba(c.r, c.g, c.b, Theme.moduleSurfaceOpacity)
        }

        HoverHandler {
            id: hover

            cursorShape: Qt.PointingHandCursor
        }

        // Shared glass highlight: same language as the static bar top light
        // (soft vertical falloff, never a hard line). Full-bleed rect with
        // the tile's own corner radius (a short rect would have its radius
        // clamped to half its height); the 40%-to-transparent stops shape
        // the falloff instead. Peak alpha comes from the shared
        // Theme.materialHighlightOpacity token; static (hover already lifts
        // the base fill above).
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
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

        Item {
            id: iconSlot

            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter

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
                color: root.active ? Theme.onActiveSurface : Theme.icon
            }
        }

        // Label right of the icon: horizontal tile layout. (The `label`
        // property was carried unused through the icon-only pill phase;
        // it renders here now.)
        Text {
            anchors.left: iconSlot.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter

            text: root.label
            color: root.active ? Theme.onActiveSurface : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: root.labelPixelSize
            font.weight: Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
            visible: root.label !== ""
        }
    }
}
