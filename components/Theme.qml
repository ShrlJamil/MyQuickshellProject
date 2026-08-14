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

    readonly property string palettePath: Quickshell.configPath("palette.json")

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