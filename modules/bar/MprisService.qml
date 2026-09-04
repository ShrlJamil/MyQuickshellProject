import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root

    readonly property var player: {
        const list = Mpris.players.values
        if (!list || list.length === 0) return null
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].isPlaying) return list[i]
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].canControl) return list[i]
        return list[0]
    }

    readonly property bool hasPlayer: root.player !== null

    property string trackTitle: ""
    property string trackArtist: ""
    property string artUrl: ""

    readonly property int playbackState: root.player ? root.player.playbackState : MprisPlaybackState.Stopped
    readonly property bool isPlaying: root.player ? root.player.isPlaying : false
    readonly property real length: (root.player && root.player.lengthSupported) ? root.player.length : 0

    readonly property bool canNext: root.player ? root.player.canGoNext : false
    readonly property bool canPrev: root.player ? root.player.canGoPrevious : false
    readonly property bool canToggle: root.player ? root.player.canTogglePlaying : false
    readonly property bool canRaisePlayer: root.player ? root.player.canRaise : false

    property real position: 0

    function _sync() {
        if (!root.hasPlayer) {
            root.trackTitle = ""
            root.trackArtist = ""
            root.artUrl = ""
            return
        }

        const p = root.player
        const t = p.trackTitle || ""
        if (t.length > 0) {
            root.trackTitle = t
            root.trackArtist = p.trackArtist || ""
            root.artUrl = p.trackArtUrl || ""
        }
    }

    onPlayerChanged: root._sync()

    Connections {
        target: root.player
        enabled: root.hasPlayer
        ignoreUnknownSignals: true

        function onTrackTitleChanged() { root._sync() }
        function onTrackArtistChanged() { root._sync() }
        function onTrackArtUrlChanged() { root._sync() }
        function onPostTrackChanged() { root._sync() }
        function onMetadataChanged() { root._sync() }
    }

    Component.onCompleted: root._sync()

    function playPause() {
        if (root.player && root.player.canTogglePlaying) root.player.togglePlaying()
    }

    function next() {
        if (root.player && root.player.canGoNext) root.player.next()
    }

    function previous() {
        if (root.player && root.player.canGoPrevious) root.player.previous()
    }

    function raise() {
        if (root.player && root.player.canRaise) root.player.raise()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.hasPlayer
        triggeredOnStart: true
        onTriggered: root.position = (root.player && root.player.positionSupported) ? root.player.position : 0
    }
}
