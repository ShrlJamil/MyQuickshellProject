pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Owner of the cross-page user preferences persisted as JSON in
// Quickshell.statePath("preferences.json") - Settings-level choices
// (Appearance first, Typography later), deliberately separate from the
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

    // ---- Appearance (schema v1) ------------------------------------------
    readonly property real defaultMaterialBorderOpacity: 0.06
    readonly property real minMaterialBorderOpacity: 0.0
    readonly property real maxMaterialBorderOpacity: 0.15

    // Strength of the outline borders on shell surfaces (Theme's
    // materialBorderOpacity). shell.qml binds this into Theme; the
    // Appearance page's slider writes it through the setter below.
    property real materialBorderOpacity: root.defaultMaterialBorderOpacity

    property bool _loaded: false
    property int _fileVersion: 1
    readonly property bool _writable: root._loaded && root._fileVersion === 1

    function _validateBorderOpacity(v) {
        if (typeof v !== "number" || !isFinite(v))
            return root.defaultMaterialBorderOpacity
        const clamped = Math.max(root.minMaterialBorderOpacity,
            Math.min(root.maxMaterialBorderOpacity, v))
        // Round to 3 decimals: the UI steps in 0.005 increments, and
        // this keeps float dust (0.06500000000000002) out of the file.
        return Math.round(clamped * 1000) / 1000
    }

    function setMaterialBorderOpacity(v) {
        root.materialBorderOpacity = root._validateBorderOpacity(v)
        if (root._writable)
            saveTimer.restart()
    }

    // Reset ONLY the Appearance preferences this service manages in
    // this schema version, back to their defaults. Nothing else in the
    // file (other sections, unknown appearance keys) is touched: the
    // commit below merges into the stored object.
    function resetAppearance() {
        root.materialBorderOpacity = root.defaultMaterialBorderOpacity
        if (root._writable)
            root._commit()
    }

    // Merge the runtime values into the stored appearance object so
    // keys this build does not know about survive the write. Assigning
    // the adapter property is what persists (see onAdapterUpdated).
    function _commit() {
        const a = (prefsAdapter.appearance && typeof prefsAdapter.appearance === "object")
            ? Object.assign({}, prefsAdapter.appearance) : {}
        a.materialBorderOpacity = root.materialBorderOpacity
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
            property var appearance: ({ materialBorderOpacity: 0.06 })
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
        const a = prefsAdapter.appearance
        const raw = (a && typeof a === "object") ? a.materialBorderOpacity : undefined
        root.materialBorderOpacity = root._validateBorderOpacity(raw)
    }
}
