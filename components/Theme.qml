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
        }
    }

    function applyPalette() {
        if (paletteAdapter.background) root.background = paletteAdapter.background
        if (paletteAdapter.surface) root.surface = paletteAdapter.surface
        if (paletteAdapter.text) root.text = paletteAdapter.text
        if (paletteAdapter.textDim) root.textDim = paletteAdapter.textDim
        if (paletteAdapter.textMuted) root.textMuted = paletteAdapter.textMuted
        if (paletteAdapter.accent) root.accent = paletteAdapter.accent
    }

    Connections {
        target: paletteAdapter

        function onAdapterUpdated() {
            root.applyPalette()
        }
    }
}