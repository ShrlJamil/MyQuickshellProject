import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Single source of truth for the media UI (persistent bar preview + expanded
// DynamicCenter player). Wraps the native Quickshell.Services.Mpris singleton.
// No subprocess, no polling except a 1 Hz position tick that only runs while a
// consumer asks for it (positionActive) and something is actually playing.
Item {
    id: root

    visible: false

    // ---------------------------------------------------------------- players
    readonly property var _players: Mpris.players ? Mpris.players.values : []

    // Explicit user lock (an MPRIS dbusName). Empty -> automatic selection.
    // Cleared automatically when that player disappears (see _pruneSelection).
    property string _selectedBus: ""

    // Lightweight, UI-facing view of every live player for a selector dropdown.
    readonly property var players: {
        const list = root._players
        const out = []
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (!p)
                continue
            out.push({
                dbusName: p.dbusName || "",
                identity: p.identity || p.dbusName || "Player",
                playing: p.playbackState === MprisPlaybackState.Playing,
                isRemote: root._isRemote(p)
            })
        }
        return out
    }

    // The live MprisPlayer currently driving the UI (or null), and its bus name
    // so a selector can mark the active row.
    readonly property var activePlayer: root.player
    readonly property string activeBus: root.player ? (root.player.dbusName || "") : ""

    // Lock the UI to one player. "" (or a gone player) returns to auto-select.
    function selectPlayer(busName) {
        root._selectedBus = busName || ""
        root.interaction()
    }

    // Drop a stale lock once the chosen player is gone from the bus.
    function _pruneSelection() {
        if (root._selectedBus.length === 0)
            return
        const list = root._players
        for (let i = 0; i < list.length; i++)
            if (list[i] && (list[i].dbusName || "") === root._selectedBus)
                return
        root._selectedBus = ""
    }

    // A "remote" player is one proxied from another device (phone via KDE
    // Connect). Detected purely from MPRIS metadata - KDE Connect namespaces its
    // bus name under org.mpris.MediaPlayer2.kdeconnect.* and sets DesktopEntry to
    // org.kde.kdeconnect.app. Everything else is a local ("laptop") player. This
    // is NOT per-app logic (no Spotify/VLC/... special-casing).
    function _isRemote(p) {
        if (!p)
            return false
        if ((p.dbusName || "").indexOf(".kdeconnect.") !== -1)
            return true
        if ((p.desktopEntry || "") === "org.kde.kdeconnect.app")
            return true
        return false
    }

    // App-agnostic active-player selection, laptop-first:
    //   1. a local player that is playing
    //   2. any player that is playing (incl. phone / KDE Connect)
    //   3. a local player that can be controlled (e.g. paused Spotify)
    //   4. any controllable player
    //   5. whatever exists
    // When nothing is playing the display falls back to `lastMedia`; a non-null
    // `player` here is still wanted so the controls can drive a paused player.
    readonly property var player: {
        const list = root._players
        if (!list || list.length === 0)
            return null
        // Explicit user lock wins as long as that player is still on the bus.
        if (root._selectedBus.length > 0)
            for (let i = 0; i < list.length; i++)
                if (list[i] && (list[i].dbusName || "") === root._selectedBus)
                    return list[i]
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].playbackState === MprisPlaybackState.Playing && !root._isRemote(list[i]))
                return list[i]
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].playbackState === MprisPlaybackState.Playing)
                return list[i]
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].canControl && !root._isRemote(list[i]))
                return list[i]
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].canControl)
                return list[i]
        return list[0] || null
    }

    // A real, controllable MPRIS player is present right now.
    readonly property bool hasPlayer: root.player !== null

    // ------------------------------------------------- last-media cache
    // Runtime-only (never persisted). Holds the last successfully resolved track
    // so the bar / expanded player keep showing something when the player
    // pauses, stops, or the MPRIS player disappears entirely. This is DISPLAY
    // state only - it is metadata, NOT a cached player object. Controls always
    // follow `root.player` / the live `can*` flags, never this cache.
    property var lastMedia: null

    // Live player currently exposes real (non-empty) track metadata.
    readonly property bool _hasLive: root.player !== null && root._rawTitle.length > 0

    // Something is available to display (live player or cache).
    readonly property bool hasMedia: root._hasLive || root.lastMedia !== null

    function _snapshotMedia() {
        const p = root.player
        if (!p)
            return
        const t = p.trackTitle || ""
        if (t.length === 0)
            return
        root.lastMedia = {
            identity: p.identity || "",
            dbusName: p.dbusName || "",
            title: t,
            artist: p.trackArtist || "",
            album: p.trackAlbum || "",
            artUrl: p.trackArtUrl || "",
            length: (p.lengthSupported && isFinite(p.length) && p.length > 0) ? p.length : 0,
            position: (p.positionSupported && isFinite(p.position) && p.position >= 0) ? p.position : 0,
            isRemote: root._isRemote(p)
        }
    }

    // Cache lifecycle: a paused/stopped player KEEPS its cached media, but once
    // the player object itself is gone from Mpris.players.values the cache for
    // that player is dropped so the UI is allowed to go empty again. This is
    // driven by the actual player set, never by isPlaying. If some other player
    // is still around, Auto selection just picks it as it does now.
    function _pruneCache() {
        if (!root.lastMedia)
            return
        const list = root._players
        const dn = root.lastMedia.dbusName || ""
        const id = root.lastMedia.identity || ""
        let present = false
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (!p)
                continue
            if (dn.length > 0) {
                if ((p.dbusName || "") === dn) { present = true; break }
            } else if (id.length > 0 && (p.identity || "") === id) {
                present = true
                break
            }
        }
        if (!present) {
            root.lastMedia = null
            root._trackKey = ""
            root._prevPlaying = false
            root._primed = false
        }
    }

    Connections {
        target: Mpris.players
        ignoreUnknownSignals: true
        function onValuesChanged() {
            root._pruneSelection()
            root._pruneCache()
        }
    }

    // Every access below goes through `root.player ? ...` (not `hasPlayer`) so
    // that a single binding evaluation is null-safe even if the computed
    // `player` flips to null between the guard and the property read (which
    // happens the instant the last MPRIS player disappears).

    // ------------------------------------------------------------- metadata
    readonly property int playbackState: root.player ? root.player.playbackState : MprisPlaybackState.Stopped
    readonly property bool playing: root.player ? (root.player.playbackState === MprisPlaybackState.Playing) : false

    readonly property string _rawTitle: root.player ? (root.player.trackTitle || "") : ""
    readonly property string _rawArtist: root.player ? (root.player.trackArtist || "") : ""
    readonly property string _rawAlbum: root.player ? (root.player.trackAlbum || "") : ""

    // Resolved display metadata: live player when it has real metadata,
    // otherwise the last-media cache. Never blank while `hasMedia` is true.
    readonly property string title: root._hasLive
        ? root._rawTitle
        : (root.lastMedia ? root.lastMedia.title : "")
    readonly property string artist: root._hasLive
        ? (root._rawArtist.length > 0 ? root._rawArtist : "Unknown artist")
        : (root.lastMedia ? root.lastMedia.artist : "")
    readonly property string album: root._hasLive
        ? root._rawAlbum
        : (root.lastMedia ? root.lastMedia.album : "")
    readonly property string artwork: root._hasLive
        ? (root.player.trackArtUrl || "")
        : (root.lastMedia ? root.lastMedia.artUrl : "")
    readonly property string identity: root.player
        ? (root.player.identity || "")
        : (root.lastMedia ? root.lastMedia.identity : "")

    // Hidden artwork prefetch: starts fetching/decoding the current artwork
    // URL even while no preview is open, so a later intro can show it
    // immediately. Shares Qt Quick's image cache with the display Image
    // (same URL + same 56px sourceSize as the bar preview art), so a hit
    // means zero extra decode there. Single slot bound to the resolved URL:
    // same-string assignments never reload, stale replies can't overwrite a
    // newer URL, and "" requests nothing. Zero size, invisible: no layout,
    // stacking, or input impact.
    Image {
        visible: false
        width: 0
        height: 0
        asynchronous: true
        cache: true
        sourceSize.width: 56
        sourceSize.height: 56
        source: root.artwork || ""
    }

    // ---------------------------------------------------------- capabilities
    readonly property bool canPlay: root.player ? root.player.canPlay : false
    readonly property bool canPause: root.player ? root.player.canPause : false
    readonly property bool canToggle: root.player ? root.player.canTogglePlaying : false
    readonly property bool canNext: root.player ? root.player.canGoNext : false
    readonly property bool canPrevious: root.player ? root.player.canGoPrevious : false
    readonly property bool canSeek: root.player ? root.player.canSeek : false

    // --------------------------------------------------------- position/length
    // Cache-aware: a frozen length/position from lastMedia keeps the progress
    // bar from vanishing the instant a player disappears (display state only).
    readonly property bool lengthSupported: root._hasLive
        ? (root.player.lengthSupported && isFinite(root.player.length) && root.player.length > 0)
        : (root.lastMedia ? (isFinite(root.lastMedia.length) && root.lastMedia.length > 0) : false)
    readonly property real length: root._hasLive
        ? ((root.player.lengthSupported && isFinite(root.player.length) && root.player.length > 0) ? root.player.length : 0)
        : (root.lastMedia && isFinite(root.lastMedia.length) ? Math.max(0, root.lastMedia.length) : 0)
    readonly property bool positionSupported: root._hasLive
        ? root.player.positionSupported
        : (root.lastMedia ? (isFinite(root.lastMedia.length) && root.lastMedia.length > 0) : false)

    // Live-ish position. MPRIS only emits positionChanged on seek/discontinuity,
    // so consumers that show a moving progress bar set positionActive = true and
    // we tick once a second while playing.
    property real position: 0
    property bool positionActive: false
    // Set by the DP-1 Dynamic Island while its expanded player is open, via a
    // Binding it owns (shell.qml only ever writes positionActive, so the two
    // never fight). Same 1 Hz tick, no new timer.
    property bool islandPositionActive: false

    // Fully sanitized progress values - always finite, non-negative, in range.
    // Long-media MPRIS players (browsers) sometimes report length as 0, NaN or
    // Infinity mid-stream; consumers should bind these, never raw length/position.
    readonly property real safeLength: (isFinite(root.length) && root.length > 0) ? root.length : 0
    readonly property real safePosition: (isFinite(root.position) && root.position >= 0) ? root.position : 0

    // Sticky duration: browsers drop mpris:length to 0 mid-stream (buffering,
    // resolution switch). Remember the last good value for THIS track so the
    // progress bar geometry never collapses. Cleared only on a real track
    // change (see _evaluate).
    property real lastValidLength: 0
    onSafeLengthChanged: if (root.safeLength > 0) root.lastValidLength = root.safeLength

    // What consumers should use for progress math: the live length, or the
    // sticky fallback. 0 only for genuine no-duration media (live streams).
    readonly property real effectiveLength: root.safeLength > 0 ? root.safeLength : root.lastValidLength

    readonly property real progressFraction: root.effectiveLength > 0
        ? Math.max(0, Math.min(1, root.safePosition / root.effectiveLength))
        : 0

    function _syncPosition() {
        if (root.player && root.player.positionSupported) {
            const p = root.player.position
            root.position = (isFinite(p) && p >= 0) ? p : 0
            // keep the cached position roughly current (no extra timer - this
            // rides the existing 1 Hz tick) so a frozen progress bar after the
            // player disappears starts from the right place.
            if (root.lastMedia)
                root.lastMedia.position = root.position
        } else if (root.lastMedia && isFinite(root.lastMedia.position)) {
            root.position = Math.max(0, root.lastMedia.position)
        } else {
            root.position = 0
        }
    }

    Timer {
        id: positionTimer
        interval: 1000
        repeat: true
        running: (root.positionActive || root.islandPositionActive) && root.playing && root.positionSupported
        triggeredOnStart: true
        onTriggered: root._syncPosition()
    }

    // ------------------------------------------------------------- actions
    function playPause() {
        if (root.player && root.player.canTogglePlaying)
            root.player.togglePlaying()
    }
    function next() {
        if (root.player && root.player.canGoNext)
            root.player.next()
    }
    function previous() {
        if (root.player && root.player.canGoPrevious)
            root.player.previous()
    }
    // Absolute seek. Quickshell's MprisPlayer.position is a writable double in
    // SECONDS (write -> MPRIS SetPosition), not microseconds. Also nudge the
    // local `position` immediately so a progress bar reads the new spot without
    // waiting for the async positionChanged round-trip.
    function setPosition(seconds) {
        if (!root.player || !root.player.canSeek || !isFinite(seconds))
            return
        const s = Math.max(0, Math.min(seconds, root.safeLength > 0 ? root.safeLength : seconds))
        root.player.position = s
        root.position = s
        if (root.lastMedia)
            root.lastMedia.position = s
    }

    // ------------------------------------------------- player events
    // Fired when the user touches the player UI. Kept for future consumers;
    // nothing in the shell auto-expands or auto-hides off it.
    signal interaction()

    property string _trackKey: ""
    property bool _prevPlaying: false
    property bool _primed: false

    // Stable track identity for consumers (MPRIS trackid when available,
    // title/artist/album fallback). Changes only when the track itself
    // changes - never on position, pause/play, or same-track metadata edits.
    readonly property string trackKey: root._trackKey

    property string _stickyKey: ""
    property string _stickyTitle: ""
    property string _stickyCombo: ""

    function _currentTrackKey() {
        if (!root.player) {
            root._stickyKey = ""
            root._stickyTitle = ""
            root._stickyCombo = ""
            return ""
        }
        const m = root.player.metadata
        let id = ""
        if (m && m["mpris:trackid"] !== undefined && m["mpris:trackid"] !== null)
            id = String(m["mpris:trackid"])
        const combo = root._rawTitle + "" + root._rawArtist + "" + root._rawAlbum
        const title = root._rawTitle
        // A usable trackid always wins and refreshes the sticky identity.
        if (id.length > 0) {
            root._stickyKey = id
            root._stickyTitle = title
            root._stickyCombo = combo
            return id
        }
        // No trackid: the title anchors the identity. Pause/stop commonly thin
        // (dropped id, emptied artist/album) or clear the surrounding metadata
        // while the title stays put - that must not look like a new track.
        // Only a genuinely different non-empty title adopts a new identity.
        if (title.length > 0 && root._stickyTitle.length > 0 && title === root._stickyTitle)
            return root._stickyKey
        if (title.length === 0)
            return root._stickyKey
        root._stickyKey = combo
        root._stickyTitle = title
        root._stickyCombo = combo
        return combo
    }

    function _evaluate() {
        if (!root.player) {
            // Keep root.lastMedia untouched - it is the fallback display state.
            root._trackKey = ""
            root._prevPlaying = false
            root._primed = false
            root._stickyKey = ""
            root._stickyTitle = ""
            root._stickyCombo = ""
            return
        }

        const key = root._currentTrackKey()
        const nowPlaying = root.playing

        // Refresh the display cache from the live player on every evaluation
        // (playback / track / metadata change). Guarded internally: only stores
        // when the player actually has a non-empty title, so a stop that clears
        // metadata does not wipe the cache.
        root._snapshotMedia()

        // First observation of a (new) player: snapshot only. State below is
        // display bookkeeping (track key, sticky duration) only - it never
        // triggers any expand.
        if (!root._primed) {
            root._trackKey = key
            root._prevPlaying = nowPlaying
            root._primed = true
            return
        }

        // A real track change invalidates the sticky duration cache so the next
        // track can't inherit the previous one's length.
        if (key.length > 0 && key !== root._trackKey)
            root.lastValidLength = 0

        root._trackKey = key
        root._prevPlaying = nowPlaying
    }

    onPlayerChanged: {
        root._syncPosition()
        root._evaluate()
    }

    Component.onCompleted: {
        root._syncPosition()
        root._evaluate()
    }

    Connections {
        target: root.player
        enabled: root.player !== null
        ignoreUnknownSignals: true

        function onPlaybackStateChanged() { root._evaluate() }
        function onIsPlayingChanged() { root._evaluate() }
        function onTrackChanged() { root._evaluate() }
        function onPostTrackChanged() { root._evaluate() }
        function onMetadataChanged() { root._evaluate() }
        function onPositionChanged() { root._syncPosition() }
        function onLengthChanged() { root._syncPosition() }
    }
}
