pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default audio-source (microphone) mute state for the bar's mic indicator.
// 100% native Quickshell.Services.Pipewire - reactive, no wpctl/Process. The
// Control Center's AudioService keeps its own wpctl path; this is independent.
Item {
    id: root

    readonly property var srcNode: Pipewire.defaultAudioSource
    PwObjectTracker { objects: root.srcNode ? [root.srcNode] : [] }

    readonly property var srcAudio: (root.srcNode && root.srcNode.audio) ? root.srcNode.audio : null

    readonly property bool available: root.srcAudio !== null
    readonly property bool muted: root.srcAudio ? root.srcAudio.muted : false

    function toggleMute() {
        if (root.srcAudio)
            root.srcAudio.muted = !root.srcAudio.muted
    }

    function setMuted(v) {
        if (root.srcAudio)
            root.srcAudio.muted = !!v
    }
}
