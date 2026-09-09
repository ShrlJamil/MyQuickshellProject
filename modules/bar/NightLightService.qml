import QtQuick
import Quickshell.Io

Item {
    id: root

    property bool active: false
    property int temperature: 4500

    function toggle() {
        if (toggleProc.running) return

        if (root.active) {
            toggleProc.command = ["pkill", "-x", "hyprsunset"]
        } else {
            toggleProc.command = ["bash", "-c", "hyprsunset -t " + root.temperature + " >/dev/null 2>&1 &"]
        }

        toggleProc.running = true
    }

    Timer {
        id: pollTimer

        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!checkProc.running) checkProc.running = true
        }
    }

    Process {
        id: checkProc

        command: ["pgrep", "-x", "hyprsunset"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: root.active = checkProc.stdout.text.trim() !== ""
    }

    Process {
        id: toggleProc

        command: ["true"]

        onExited: checkProc.running = true
    }
}
