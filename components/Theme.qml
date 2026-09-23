pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false

    property color background: "#000000"
    property color surface: "#313244"
    property color surfaceHover: Qt.rgba(1, 1, 1, 0.05)
    property color text: "#ffffff"
    property color textDim: "#a6adc8"
    property color textMuted: "#888888"
    property color accent: "#89b4fa"
    property color activeTile: "#c4c9d1"
    property color border: "#45475a"

    // Shared translucent-surface opacity, sourced from the Wallust-generated
    // palette (`surfaceOpacity`, 0.5 in the template). Consumed by the static
    // bar, DynamicCenter frame, ControlCenter panels, and OSD backgrounds.
    // Falls back to 1 (fully opaque) while no palette provides it.
    property real surfaceOpacity: 1

    // Active/ON-state icon color (white, constant across wallpapers so icons
    // stay readable). Sourced from the Wallust palette (`icon`).
    property color icon: "#F2F4F5"

    // Material prototype (static bar only): ultra-subtle directional top
    // highlight + bottom edge key over the blurred backdrop. Neutral white at
    // single-digit opacities; the surfaceOpacity tint does the heavy lifting.
    property real materialHighlightOpacity: 0.05
    property real materialBorderOpacity: 0.06

    // UI text typeface (`font.family: Theme.fontFamily` on Text elements).
    // "Google Sans Flex" is the variable-font build of Google Sans installed on
    // this system; plain "Google Sans" is not a registered family and would
    // silently fall back to Noto Sans. NEVER apply this to icon glyphs
    // (Nerd Font / symbol strings) - those keep their own family.
    readonly property string fontFamily: "Google Sans Flex"

    readonly property real cornerRadius: 22

    readonly property string palettePath: Quickshell.shellPath("palette.json")

    FileView {
        id: paletteFile

        path: root.palettePath

        watchChanges: true
        printErrors: false

        onFileChanged: reload()

        onLoaded: root.applyPalette()

        JsonAdapter {
            id: paletteAdapter

            property string background: ""
            property string surface: ""
            property string text: ""
            property string textDim: ""
            property string textMuted: ""
            property string accent: ""
            property string activeTile: ""
            property string border: ""
            property string icon: ""
            property real surfaceOpacity: 0
        }
    }

    function applyPalette() {
        if (paletteAdapter.background) root.background = paletteAdapter.background
        if (paletteAdapter.surface) root.surface = paletteAdapter.surface
        if (paletteAdapter.text) root.text = paletteAdapter.text
        if (paletteAdapter.textDim) root.textDim = paletteAdapter.textDim
        if (paletteAdapter.textMuted) root.textMuted = paletteAdapter.textMuted
        if (paletteAdapter.accent) root.accent = paletteAdapter.accent
        if (paletteAdapter.activeTile) root.activeTile = paletteAdapter.activeTile
        if (paletteAdapter.border) root.border = paletteAdapter.border
        if (paletteAdapter.icon) root.icon = paletteAdapter.icon
        if (paletteAdapter.surfaceOpacity > 0) root.surfaceOpacity = paletteAdapter.surfaceOpacity
    }

    Connections {
        target: paletteAdapter

        function onAdapterUpdated() {
            root.applyPalette()
        }
    }
}