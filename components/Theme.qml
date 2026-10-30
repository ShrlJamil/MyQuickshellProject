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
    // Same treatment: parsed, but the icon colour is derived from the
    // seed (see `icon` below), not taken from the palette's constant.
    property color _palIcon: "#F2F4F5"
    // Palette text colours, retained as anchors only: the public text
    // tokens are DERIVED from the seed (see below), so their contrast
    // against the derived surfaces is set by the recipe, not by however
    // the template happened to filter color7/color8 for this wallpaper.
    property color _palText: "#ffffff"
    property color _palTextDim: "#a6adc8"
    property color _palTextMuted: "#888888"

    // ---- Tonal recipe (THE tuning knobs) ----------------------------------
    // Seed hue: the accent's hue; fall back to the background's, then to a
    // calm blue. Achromatic colours report hue -1 and are skipped.
    readonly property real _seedHue: root._palAccent.hslHue >= 0 ? root._palAccent.hslHue
        : (root._palBackground.hslHue >= 0 ? root._palBackground.hslHue : 0.62)
    readonly property real _seedSat: root._palAccent.hslSaturation
    // Neutral chroma: a solid echo of the seed (over half its saturation,
    // capped) - dark here means a DEEPER SHADE OF THE WALLPAPER'S COLOUR
    // (dark blue from a blue wallpaper), never near-black grey. The floor
    // (0.22) guarantees the tint is always present, even for a pale seed.
    readonly property real _neutralSat: Math.max(0.22, Math.min(0.42, root._seedSat * 0.55))
    // Base tone: the palette background's lightness, clamped into a dark
    // register - raised in Tahap 2 ([0.09, 0.15]) so surfaces have room
    // to actually show the seed's colour instead of collapsing to black,
    // while a bright-ish palette still cannot lift the whole shell.
    readonly property real _baseL: Math.max(0.09, Math.min(0.15, root._palBackground.hslLightness))
    // Container (ON-state) chroma: over half the seed's, capped muted.
    readonly property real _containerSat: Math.max(0.10, Math.min(0.38, root._seedSat * 0.55))
    // Text chroma: a quieter slice of the neutral saturation - text
    // carries the seed's hue family without becoming coloured itself.
    readonly property real _textSat: Math.min(root._neutralSat, 0.25)
    // Active-state chroma: most of the seed's saturation, so the light
    // active surface clearly carries the wallpaper's colour (never a
    // milky neutral). Achromatic seeds get a near-neutral 0.05 instead:
    // with no seed hue to carry, the fallback hue must not tint the
    // active scheme blue.
    readonly property real _activeSat: root._seedSat < 0.05 ? 0.05
        : Math.max(0.40, Math.min(0.85, root._seedSat * 0.9))

    function _tone(lightness) {
        return Qt.hsla(root._seedHue, root._neutralSat, lightness, 1)
    }

    // ---- Semantic surface tokens (derived) --------------------------------
    property color background: root._tone(root._baseL)
    property color surface: root._tone(root._baseL + 0.045)
    property color surfaceRaised: root._tone(root._baseL + 0.085)
    property color surfaceOverlay: root._tone(root._baseL + 0.125)
    // Sunken is the Control Center tiles' idle tone (its only consumer):
    // anchored to the panel step (panel lightness - 0.035) with slightly
    // quieter saturation (x0.85), so idle tiles sit just under the panel
    // - part of its family, slightly recessed, never separate dark
    // blocks.
    property color backgroundSunken: Qt.hsla(root._panelHue, root._panelSat * 0.85, root._baseL + 0.095, 1)
    property color backgroundInset: root._tone(root._baseL * 0.58)

    // Control Center panel family: the CC surfaces get their own hue and
    // saturation so the panel reads as the wallpaper's family in a calm
    // steel register, not a muted teal-grey. Saturation keeps 70% of the
    // seed's (the global neutral keeps 55%): enough for the hue to stay
    // identifiable at the panel's lifted lightness, low enough to stay
    // muted - at the neutral rate the channels converge toward grey and
    // an azure seed's high green channel takes over the read. The hue
    // correction is conditional: only seeds in the cyan/azure band
    // (175-215 deg) are pulled toward 210 deg - the royal-blue pole of a
    // blue palette (color5/color6) - by at most 9 deg; every other hue
    // passes through untouched, and achromatic seeds keep the neutral
    // behaviour exactly.
    readonly property real _panelSat: root._seedSat < 0.05
        ? root._neutralSat
        : Math.max(0.24, Math.min(0.50, root._seedSat * 0.7))
    readonly property real _panelHue: {
        if (root._seedSat < 0.05) return root._seedHue
        var hDeg = root._seedHue * 360
        if (hDeg < 175 || hDeg > 215) return root._seedHue
        var shift = Math.max(0, Math.min(210 - hDeg, 9))
        return (hDeg + shift) / 360
    }
    function _panelTone(lightness) {
        return Qt.hsla(root._panelHue, root._panelSat, lightness, 1)
    }

    // The CC panel is the family's lightness anchor at base + 0.13 - a
    // lifted, muted steel surface well above the shell background - and
    // the internal steps re-derive from it: hover +0.045 over the panel,
    // raised +0.085, overlay +0.120 (idle tiles anchor separately, just
    // under the panel; see backgroundSunken). Only Control Center (panel,
    // detail panels, tiles, sliders) consumes these; other modules keep
    // the global tones above.
    property color panelBackground: root._panelTone(root._baseL + 0.130)
    property color panelSurface: root._panelTone(root._baseL + 0.175)
    property color panelRaised: root._panelTone(root._baseL + 0.215)
    property color panelOverlay: root._panelTone(root._baseL + 0.250)

    // Legacy alias of `surface`. (Bar widgets' open-state fill used this
    // until they moved to the light active scheme - activeSurface and
    // friends; nothing consumes it now.)
    property color surfaceDesaturated: root.surface

    // ON-state tile fill: the seed's muted container tone, anchored
    // RELATIVE to the base tone (+0.17) so its jump from the surrounding
    // surfaces is the same for every wallpaper.
    property color activeTile: Qt.hsla(root._seedHue, root._containerSat, root._baseL + 0.17, 1)
    // Its hover: the same container one tone step up.
    property color activeTileHover: Qt.hsla(root._seedHue, root._containerSat, root._baseL + 0.21, 1)

    // Light ACTIVE scheme (Control Center): an active control is a LIGHT
    // seed surface with DARK seed foreground - the inverse polarity of
    // the dark container above. Lightness levels are fixed by the recipe
    // (verified >= 7:1 for the main foreground and >= 4.5:1 for the dim
    // one across blue/orange/purple/pale/achromatic/yellow/green seeds);
    // hover DARKENS, as a light surface must.
    property color activeSurface: Qt.hsla(root._seedHue, root._activeSat, 0.80, 1)
    property color activeSurfaceHover: Qt.hsla(root._seedHue, root._activeSat, 0.76, 1)
    // The vivid seed colour itself at the active saturation - mid-tone,
    // so it reads on BOTH the light active surface and the dark shell
    // (the slider knob straddles the two).
    property color activeAccent: Qt.hsla(root._seedHue, root._activeSat, 0.55, 1)
    property color onActiveSurface: Qt.hsla(root._seedHue, Math.min(root._activeSat, 0.55), 0.12, 1)
    property color onActiveSurfaceDim: Qt.hsla(root._seedHue, root._activeSat * 0.85, 0.28, 1)

    // Accent passes through from the palette (his template already tunes
    // it). Text colours do NOT: they are derived from the seed at fixed
    // lightness levels, so their contrast against the derived surfaces
    // holds for every wallpaper.
    property color accent: root._palAccent

    property color surfaceHover: Qt.rgba(1, 1, 1, 0.05)
    property color text: Qt.hsla(root._seedHue, root._textSat, 0.92, 1)
    property color textDim: Qt.hsla(root._seedHue, root._textSat, 0.74, 1)
    property color textMuted: Qt.hsla(root._seedHue, root._textSat, 0.66, 1)

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

    // Surface opacity by layer: every module surface is fully opaque.
    // (There is deliberately no palette-driven translucency token: this
    // design has no transparent module surfaces.)
    property real moduleSurfaceOpacity: 1
    // User-adjustable (Settings > Appearance): shell.qml binds this token
    // to PreferencesService.barTransparency / barBackgroundOpacity
    // (preferences.json) - 0 while transparency is off, the stored
    // background opacity while it is on. The literal here is only the
    // fallback before that binding lands and matches the default
    // (transparency off) - do not tune the value here.
    property real barSurfaceOpacity: 0

    // Bar layout (Settings > Appearance, Stage 3): shell.qml binds
    // barFloating to PreferencesService.barLayoutMode === "float". The
    // float insets live here because Bar, DynamicCenter and the bar
    // popovers all offset by them; the literal false matches the
    // service default layoutMode ("default") - do not tune here.
    property bool barFloating: false
    readonly property real barFloatInsetX: 12
    readonly property real barFloatInsetTop: 8

    // Segmented bar (Stage 4): shell.qml binds barSegmented to
    // PreferencesService.barLayoutMode === "segmented" and
    // barWidgetOpacity to barWidgetBackgroundOpacity. barWidgetSurface
    // is the fill for the widget backgrounds segmented mode ADDS (the
    // widgets whose base state is transparent today); it must only be
    // used behind a barSegmented condition - widgets with permanent
    // fills (MediaPill, RecordPill) never read it, in any mode.
    property bool barSegmented: false
    property real barWidgetOpacity: 1
    readonly property color barWidgetSurface: Qt.rgba(backgroundInset.r, backgroundInset.g, backgroundInset.b, barWidgetOpacity)

    // Icon colour: NOT a neutral white - the seed (accent) mixed 65%
    // toward white, so icons are a white that clearly carries the
    // wallpaper's own colour family instead of a milky generic white
    // (Material You's on-surface idea). Still reads as "white" anywhere.
    property color icon: root.tint(root._palAccent, 0.65)

    // Material prototype (static bar only): ultra-subtle directional top
    // highlight + bottom edge key over the blurred backdrop. Neutral white at
    // single-digit opacities.
    property real materialHighlightOpacity: 0
    // User-adjustable (Settings > Appearance): shell.qml binds this token
    // to PreferencesService.materialBorderOpacity (preferences.json). The
    // literal here is only the fallback before that binding lands and
    // matches the service default - do not tune the value here.
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
        if (paletteAdapter.text) root._palText = paletteAdapter.text
        if (paletteAdapter.textDim) root._palTextDim = paletteAdapter.textDim
        if (paletteAdapter.textMuted) root._palTextMuted = paletteAdapter.textMuted
        if (paletteAdapter.accent) root._palAccent = paletteAdapter.accent
        if (paletteAdapter.activeTile) root._palActiveTile = paletteAdapter.activeTile
        if (paletteAdapter.icon) root._palIcon = paletteAdapter.icon
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
