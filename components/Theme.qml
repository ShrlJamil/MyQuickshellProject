pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false

    property color background: "#000000"
    property color surface: "#313244"

    // Elevation ladder above `surface`, DERIVED from it by default (tint
    // toward white, fixed factors - the ordering can never invert, whatever
    // the palette). The wallust template also emits both tiers (from the
    // same color0 base as `surface`); when palette.json provides them,
    // applyPalette() replaces the derivation with the generated values.
    property color surfaceRaised: root.tint(root.surface, 0.07)
    property color surfaceOverlay: root.tint(root.surface, 0.14)

    // Bar widgets' ACTIVE (open-state) fill: `surface` with its saturation
    // pulled down, so an opened bar widget reads calmer than the raw
    // palette surface. Pure QML derivation (no palette key). Hover fills
    // are deliberately NOT routed through this - surfaceHover stays as-is.
    property color surfaceDesaturated: root.desaturate(root.surface, 0.4)

    // Downward shades of `background` for recessed layering (tiles that sit
    // darker than their panel): backgroundSunken is one step down (panel
    // backdrops), backgroundInset one step further, derived FROM
    // backgroundSunken so the ordering can never invert.
    property color backgroundSunken: root.darken(root.background, 0.15)
    property color backgroundInset: root.darken(root.backgroundSunken, 0.18)

    property color surfaceHover: Qt.rgba(1, 1, 1, 0.05)
    property color text: "#ffffff"
    property color textDim: "#a6adc8"
    property color textMuted: "#888888"
    property color accent: "#89b4fa"
    property color activeTile: "#c4c9d1"

    // Raw wallust palette, mirrored 1:1 and UNFILTERED (color0-15 +
    // cursor). Reserved for future use: nothing consumes these yet; they
    // exist so a later feature can build on the true palette colours
    // without a template/Theme change first. Do not "clean up" as unused.
    property color color0: "#000000"
    property color color1: "#000000"
    property color color2: "#000000"
    property color color3: "#000000"
    property color color4: "#000000"
    property color color5: "#000000"
    property color color6: "#000000"
    property color color7: "#000000"
    property color color8: "#000000"
    property color color9: "#000000"
    property color color10: "#000000"
    property color color11: "#000000"
    property color color12: "#000000"
    property color color13: "#000000"
    property color color14: "#000000"
    property color color15: "#000000"
    property color cursor: "#000000"

    // Surface opacity by layer: every module surface is fully opaque, the bar
    // strip is fully transparent. (There is deliberately no palette-driven
    // translucency token: this design has no transparent module surfaces.)
    property real moduleSurfaceOpacity: 1
    property real barSurfaceOpacity: 0

    // Active/ON-state icon color (white, constant across wallpapers so icons
    // stay readable). Sourced from the Wallust palette (`icon`).
    property color icon: "#F2F4F5"

    // Material prototype (static bar only): ultra-subtle directional top
    // highlight + bottom edge key over the blurred backdrop. Neutral white at
    // single-digit opacities.
    property real materialHighlightOpacity: 0
    property real materialBorderOpacity: 0.06

    // Slight raised shadow under bar text (Text.Raised styleColor): dark at
    // moderate alpha, just enough to separate light text from bright
    // wallpapers or windows without looking like an outline. Constant, not
    // palette-driven — a shadow is dark in any theme.
    property color textShadow: Qt.rgba(0, 0, 0, 0.6)

    // UI text typeface (`font.family: Theme.fontFamily` on Text elements).
    // "Inter" must be installed on the system (it is not bundled in this
    // repo); if it is missing, Qt silently falls back to another sans.
    // NEVER apply this to icon glyphs (symbol strings, media-control glyphs)
    // - those keep their own family / system fallback so the symbols resolve.
    readonly property string fontFamily: "Inter"

    readonly property real cornerRadius: 22

    // Mix a colour toward white by factor f (0 = unchanged, 1 = white).
    // Used for the derived elevation tiers; mixing toward white keeps the
    // hue family while guaranteeing a lightness step on any base colour.
    function tint(c, f) {
        return Qt.rgba(c.r + (1 - c.r) * f, c.g + (1 - c.g) * f, c.b + (1 - c.b) * f, c.a)
    }

    // Scale a colour's HSL saturation down by factor f (0 = unchanged,
    // 1 = fully grey), keeping hue and lightness.
    function desaturate(c, f) {
        return Qt.hsla(c.hslHue, c.hslSaturation * (1 - f), c.hslLightness, c.a)
    }

    // Mix a colour toward black by factor f (0 = unchanged, 1 = black).
    function darken(c, f) {
        return Qt.rgba(c.r * (1 - f), c.g * (1 - f), c.b * (1 - f), c.a)
    }

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
            property string surfaceRaised: ""
            property string surfaceOverlay: ""
            property string text: ""
            property string textDim: ""
            property string textMuted: ""
            property string accent: ""
            property string activeTile: ""
            property string icon: ""
            property string color0: ""
            property string color1: ""
            property string color2: ""
            property string color3: ""
            property string color4: ""
            property string color5: ""
            property string color6: ""
            property string color7: ""
            property string color8: ""
            property string color9: ""
            property string color10: ""
            property string color11: ""
            property string color12: ""
            property string color13: ""
            property string color14: ""
            property string color15: ""
            property string cursor: ""
        }
    }

    function applyPalette() {
        if (paletteAdapter.background) root.background = paletteAdapter.background
        if (paletteAdapter.surface) root.surface = paletteAdapter.surface
        if (paletteAdapter.surfaceRaised) root.surfaceRaised = paletteAdapter.surfaceRaised
        if (paletteAdapter.surfaceOverlay) root.surfaceOverlay = paletteAdapter.surfaceOverlay
        if (paletteAdapter.text) root.text = paletteAdapter.text
        if (paletteAdapter.textDim) root.textDim = paletteAdapter.textDim
        if (paletteAdapter.textMuted) root.textMuted = paletteAdapter.textMuted
        if (paletteAdapter.accent) root.accent = paletteAdapter.accent
        if (paletteAdapter.activeTile) root.activeTile = paletteAdapter.activeTile
        if (paletteAdapter.icon) root.icon = paletteAdapter.icon
        if (paletteAdapter.color0) root.color0 = paletteAdapter.color0
        if (paletteAdapter.color1) root.color1 = paletteAdapter.color1
        if (paletteAdapter.color2) root.color2 = paletteAdapter.color2
        if (paletteAdapter.color3) root.color3 = paletteAdapter.color3
        if (paletteAdapter.color4) root.color4 = paletteAdapter.color4
        if (paletteAdapter.color5) root.color5 = paletteAdapter.color5
        if (paletteAdapter.color6) root.color6 = paletteAdapter.color6
        if (paletteAdapter.color7) root.color7 = paletteAdapter.color7
        if (paletteAdapter.color8) root.color8 = paletteAdapter.color8
        if (paletteAdapter.color9) root.color9 = paletteAdapter.color9
        if (paletteAdapter.color10) root.color10 = paletteAdapter.color10
        if (paletteAdapter.color11) root.color11 = paletteAdapter.color11
        if (paletteAdapter.color12) root.color12 = paletteAdapter.color12
        if (paletteAdapter.color13) root.color13 = paletteAdapter.color13
        if (paletteAdapter.color14) root.color14 = paletteAdapter.color14
        if (paletteAdapter.color15) root.color15 = paletteAdapter.color15
        if (paletteAdapter.cursor) root.cursor = paletteAdapter.cursor
    }

    Connections {
        target: paletteAdapter

        function onAdapterUpdated() {
            root.applyPalette()
        }
    }
}
