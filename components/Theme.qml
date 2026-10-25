pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ============================================================================
// MATERIAL-YOU TONAL EXPERIMENT (2026-10-25, on top of baseline-2026-10-25-v2)
//
// The semantic surface colours are no longer taken verbatim from the
// palette. Instead the palette supplies two ANCHORS - `background` (the
// wallpaper's dark tone) and `accent` (the wallpaper's key colour, the
// "seed") - and every surface is a tonal step derived from them, the way
// Material You builds its scheme from a source colour:
//
//   * One neutral hue family for everything: the seed's hue, at a heavily
//     compressed saturation (chroma cap below). Surfaces stop clashing
//     because they are the same colour at different tones.
//   * Tone steps are absolute lightness offsets from the (clamped) palette
//     background, so the ladder's ORDER can never invert per wallpaper.
//   * The overall register is deliberately DARK and MUTED: the base tone
//     is clamped low and every saturation is capped - nothing gets dense
//     or vivid, even from a saturated wallpaper.
//   * `activeTile` is the seed's "container" tone (muted seed fill at
//     tone ~0.30) instead of a near-white grey.
//
// Tuning lives in the recipe block right below the anchors - all factors
// in one place. The palette contract is unchanged: palette.json keys land
// on the `_pal*` anchors (and the direct tokens), never on the derived
// tokens. If the experiment is rejected, the pre-experiment Theme is the
// one in baseline-2026-10-25-v2.
// ============================================================================

Item {
    id: root

    visible: false

    // ---- Palette anchors (written ONLY by applyPalette) -------------------
    property color _palBackground: "#000000"
    property color _palSurface: "#313244"
    property color _palAccent: "#89b4fa"
    // Parsed for compatibility; the tonal recipe currently derives
    // activeTile from the seed instead of using the palette's value.
    property color _palActiveTile: "#c4c9d1"

    // ---- Tonal recipe (THE tuning knobs) ----------------------------------
    // Seed hue: the accent's hue; fall back to the background's, then to a
    // calm blue. Achromatic colours report hue -1 and are skipped.
    readonly property real _seedHue: root._palAccent.hslHue >= 0 ? root._palAccent.hslHue
        : (root._palBackground.hslHue >= 0 ? root._palBackground.hslHue : 0.62)
    readonly property real _seedSat: root._palAccent.hslSaturation
    // Neutral chroma: a solid echo of the seed (over half its saturation,
    // capped) - dark here means a DEEPER SHADE OF THE WALLPAPER'S COLOUR
    // (dark blue from a blue wallpaper), never near-black grey. HSL at low
    // lightness needs this much saturation for the tint to stay visible.
    readonly property real _neutralSat: Math.max(0.12, Math.min(0.45, root._seedSat * 0.55))
    // Base tone: the palette background's lightness, clamped into a dark
    // register so a bright-ish palette cannot lift the whole shell.
    readonly property real _baseL: Math.max(0.05, Math.min(0.11, root._palBackground.hslLightness))
    // Container (ON-state) chroma: over half the seed's, capped muted.
    readonly property real _containerSat: Math.max(0.10, Math.min(0.38, root._seedSat * 0.55))

    function _tone(lightness) {
        return Qt.hsla(root._seedHue, root._neutralSat, lightness, 1)
    }

    // ---- Semantic surface tokens (derived) --------------------------------
    property color background: root._tone(root._baseL)
    property color surface: root._tone(root._baseL + 0.05)
    property color surfaceRaised: root._tone(root._baseL + 0.095)
    property color surfaceOverlay: root._tone(root._baseL + 0.14)
    property color backgroundSunken: root._tone(root._baseL * 0.70)
    property color backgroundInset: root._tone(root._baseL * 0.52)

    // Bar widgets' ACTIVE (open-state) fill = the neutral container tone,
    // same as `surface`: one family everywhere. (Pre-experiment this was a
    // desaturated raw surface; the tonal ladder makes that a no-op.)
    property color surfaceDesaturated: root.surface

    // ON-state tile fill: the seed's muted container tone.
    property color activeTile: Qt.hsla(root._seedHue, root._containerSat, 0.30, 1)
    // Its hover: the same container one tone step up.
    property color activeTileHover: Qt.hsla(root._seedHue, root._containerSat, 0.34, 1)

    // Accent passes through from the palette (his template already tunes
    // it); text colours likewise stay palette-direct below.
    property color accent: root._palAccent

    property color surfaceHover: Qt.rgba(1, 1, 1, 0.05)
    property color text: "#ffffff"
    property color textDim: "#a6adc8"
    property color textMuted: "#888888"

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
        if (paletteAdapter.background) root._palBackground = paletteAdapter.background
        if (paletteAdapter.surface) root._palSurface = paletteAdapter.surface
        // surfaceRaised / surfaceOverlay palette keys are still parsed but
        // the tonal recipe derives both tiers; they land nowhere for now.
        if (paletteAdapter.text) root.text = paletteAdapter.text
        if (paletteAdapter.textDim) root.textDim = paletteAdapter.textDim
        if (paletteAdapter.textMuted) root.textMuted = paletteAdapter.textMuted
        if (paletteAdapter.accent) root._palAccent = paletteAdapter.accent
        if (paletteAdapter.activeTile) root._palActiveTile = paletteAdapter.activeTile
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
