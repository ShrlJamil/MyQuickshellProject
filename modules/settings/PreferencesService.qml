pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Owner of the cross-page user preferences persisted as JSON in
// Quickshell.statePath("preferences.json") - Settings-level choices
// (the Bar and Typography sections today), deliberately separate from the
// generated palette.json (Wallust output, never user data) and from the
// per-module state files (display-preferences.json, wallpaper-state
// .json), which keep their own owners.
//
// Same persistence pattern as DisplayService / WallpaperService:
// FileView + JsonAdapter, one load funnel for the loaded and failed
// cases, defaults for anything missing, atomic writes. Consumers read
// the VALIDATED properties below - never the adapter - so this service
// is the single source of truth and the file only ever holds values
// that passed validation here.
//
// Schema version policy: version 1 is the only known version. A file
// with any other version is left completely untouched (it may belong
// to a newer build) and the runtime runs on defaults; writes resume
// only for files this build understands. New fields are additive and
// land with their own defaults, so older files keep working.
Item {
    id: root

    // ---- Bar (schema v1, additive) ----------------------------------------
    // Stage 1: state and persistence only. NOTHING consumes these yet -
    // the values are stored ahead of the visual stages (transparency,
    // Float, Segmented), and the defaults describe the bar exactly as
    // it renders today (no strip background, opaque widget fills), so
    // landing this section changes no pixel on screen.
    readonly property string defaultBarLayoutMode: "default"
    readonly property bool defaultBarTransparency: false
    readonly property real defaultBarBackgroundOpacity: 0.85
    readonly property real defaultBarWidgetBackgroundOpacity: 1.0

    property string barLayoutMode: root.defaultBarLayoutMode
    property bool barTransparency: root.defaultBarTransparency
    property real barBackgroundOpacity: root.defaultBarBackgroundOpacity
    property real barWidgetBackgroundOpacity: root.defaultBarWidgetBackgroundOpacity

    // ---- Typography (schema v1, additive) ------------------------------
    // The one typeface choice: shell.qml binds Theme.fontFamily to it,
    // so every text element in the shell follows the pick. The default
    // is the typeface the shell shipped with.
    readonly property string defaultFontFamily: "Inter"

    property string fontFamily: root.defaultFontFamily

    // ---- Appearance (schema v1, additive) ------------------------------
    // Dark mode: shell.qml binds Theme.darkMode to it. The default is
    // the dark shell the design shipped with; false is the light shell.
    readonly property bool defaultDarkMode: true

    property bool darkMode: root.defaultDarkMode

    property bool _loaded: false
    property int _fileVersion: 1
    readonly property bool _writable: root._loaded && root._fileVersion === 1

    // Bar validators and setters: same contract as the Appearance one -
    // anything unusable falls back to the field's default, numbers are
    // clamped to 0..1 and rounded to 3 decimals, and a write is only
    // ever scheduled once a known-version file has loaded.
    function _validateLayoutMode(v) {
        if (v === "default" || v === "float" || v === "segmented")
            return v
        return root.defaultBarLayoutMode
    }

    function _validateBarOpacity(v, fallback) {
        if (typeof v !== "number" || !isFinite(v))
            return fallback
        const clamped = Math.max(0, Math.min(1, v))
        return Math.round(clamped * 1000) / 1000
    }

    function setBarLayoutMode(v) {
        root.barLayoutMode = root._validateLayoutMode(v)
        if (root._writable)
            saveTimer.restart()
    }

    function setBarTransparency(v) {
        root.barTransparency = (typeof v === "boolean") ? v : root.defaultBarTransparency
        if (root._writable)
            saveTimer.restart()
    }

    function setBarBackgroundOpacity(v) {
        root.barBackgroundOpacity = root._validateBarOpacity(v, root.defaultBarBackgroundOpacity)
        if (root._writable)
            saveTimer.restart()
    }

    function setBarWidgetBackgroundOpacity(v) {
        root.barWidgetBackgroundOpacity = root._validateBarOpacity(v, root.defaultBarWidgetBackgroundOpacity)
        if (root._writable)
            saveTimer.restart()
    }

    // A family name is usable when it is a non-empty string of sane
    // length; anything else falls back to the default. Whether the
    // family is actually installed is the picker's concern (it only
    // offers installed families); Qt falls back silently otherwise.
    function _validateFontFamily(v) {
        if (typeof v !== "string")
            return root.defaultFontFamily
        const t = v.trim()
        if (t.length === 0 || t.length > 64)
            return root.defaultFontFamily
        return t
    }

    function setFontFamily(v) {
        root.fontFamily = root._validateFontFamily(v)
        if (root._writable)
            saveTimer.restart()
    }

    function _validateDarkMode(v) {
        return (typeof v === "boolean") ? v : root.defaultDarkMode
    }

    function setDarkMode(v) {
        root.darkMode = root._validateDarkMode(v)
        if (root._writable)
            saveTimer.restart()
        // Dark Mode phase 2 (GTK): mirror the mode to the system via
        // the bundled scripts/theme-mode.sh - it sets the portal
        // color-scheme and swaps in the dark/light counterpart of
        // whatever GTK theme is active (derived from the theme's own
        // name and verified installed, never hardcoded). The script
        // is idempotent; fire-and-forget.
        themeModeProc.command = [Quickshell.shellPath("scripts/theme-mode.sh"), root.darkMode ? "dark" : "light"]
        themeModeProc.running = true
    }

    Process {
        id: themeModeProc
    }

    // Merge the runtime values into the stored section objects so keys
    // this build does not know about survive the write: sections are
    // merged from their stored objects plus the current runtime values,
    // then assigned back. Assigning an adapter property is what persists
    // (see onAdapterUpdated).
    function _commit() {
        const b = (prefsAdapter.bar && typeof prefsAdapter.bar === "object")
            ? Object.assign({}, prefsAdapter.bar) : {}
        b.layoutMode = root.barLayoutMode
        b.transparency = root.barTransparency
        b.backgroundOpacity = root.barBackgroundOpacity
        b.widgetBackgroundOpacity = root.barWidgetBackgroundOpacity
        prefsAdapter.bar = b
        const t = (prefsAdapter.typography && typeof prefsAdapter.typography === "object")
            ? Object.assign({}, prefsAdapter.typography) : {}
        t.fontFamily = root.fontFamily
        prefsAdapter.typography = t
        const a = (prefsAdapter.appearance && typeof prefsAdapter.appearance === "object")
            ? Object.assign({}, prefsAdapter.appearance) : {}
        a.darkMode = root.darkMode
        prefsAdapter.appearance = a
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: root._commit()
    }

    FileView {
        id: prefsFile

        path: Quickshell.statePath("preferences.json")
        printErrors: false
        atomicWrites: true

        onLoaded: root._onPrefsLoaded()
        onLoadFailed: (error) => root._onPrefsLoaded()
        onAdapterUpdated: writeAdapter()
        onSaveFailed: (error) => console.warn("[PreferencesService] preferences.json save failed: " + error)

        JsonAdapter {
            id: prefsAdapter

            property int version: 1
            property var bar: ({ layoutMode: "default", transparency: false, backgroundOpacity: 0.85, widgetBackgroundOpacity: 1.0 })
            property var typography: ({ fontFamily: "Inter" })
            property var appearance: ({ darkMode: true })
        }
    }

    // Single funnel, run once, whichever way the load went: a missing
    // or corrupt file leaves the adapter at its declared defaults,
    // which are exactly the fallbacks validated below.
    function _onPrefsLoaded() {
        if (root._loaded)
            return
        root._loaded = true
        const ver = prefsAdapter.version
        root._fileVersion = (typeof ver === "number" && isFinite(ver)) ? Math.floor(ver) : 1
        if (root._fileVersion !== 1) {
            console.warn("[PreferencesService] preferences.json version " + root._fileVersion
                + " is not supported by this build; using defaults, file left untouched")
            return
        }
        const b = (prefsAdapter.bar && typeof prefsAdapter.bar === "object")
            ? prefsAdapter.bar : {}
        root.barLayoutMode = root._validateLayoutMode(b.layoutMode)
        root.barTransparency = (typeof b.transparency === "boolean")
            ? b.transparency : root.defaultBarTransparency
        root.barBackgroundOpacity = root._validateBarOpacity(b.backgroundOpacity,
            root.defaultBarBackgroundOpacity)
        root.barWidgetBackgroundOpacity = root._validateBarOpacity(b.widgetBackgroundOpacity,
            root.defaultBarWidgetBackgroundOpacity)
        const t = (prefsAdapter.typography && typeof prefsAdapter.typography === "object")
            ? prefsAdapter.typography : {}
        root.fontFamily = root._validateFontFamily(t.fontFamily)
        const a = (prefsAdapter.appearance && typeof prefsAdapter.appearance === "object")
            ? prefsAdapter.appearance : {}
        root.darkMode = root._validateDarkMode(a.darkMode)
    }
}
