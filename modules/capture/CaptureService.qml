import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool busy: false
    property bool barVisible: false
    property string pendingMode: ""
    property string lastPath: ""
    property string lastTimestamp: ""
    property bool bannerVisible: false
    property bool bannerHovered: false

    signal captured(string imagePath, string timestamp)

    readonly property string _base: 'd="$HOME/Pictures/Screenshots"; mkdir -p "$d"; f="$d/Screenshot_$(date +%Y%m%d_%H%M%S).png"; '
    readonly property string _regionScript: root._base + 'g=$(slurp) && [ -n "$g" ] && grim -g "$g" "$f" && wl-copy --type image/png < "$f" && echo "$f"'
    readonly property string _windowScript: root._base + 'g=$(slurp -f "%x,%y %wx%h") && [ -n "$g" ] && grim -g "$g" "$f" && wl-copy --type image/png < "$f" && echo "$f"'
    readonly property string _fullScript: root._base + 'grim "$f" && wl-copy --type image/png < "$f" && echo "$f"'

    function openBar() {
        console.log("[CaptureService] Bar opened")
        root.barVisible = true
    }

    function closeBar() {
        console.log("[CaptureService] Bar closed")
        root.barVisible = false
    }

    function triggerCapture(mode) {
        console.log("[CaptureService] triggerCapture(", mode, ")")
        root.pendingMode = mode
        root.barVisible = false
        executeTimer.restart()
    }

    function captureRegion() {
        root.triggerCapture("region")
    }

    function captureFullscreen() {
        root.triggerCapture("screen")
    }

    function _runCapture(mode) {
        if (root.busy) return
        console.log("[CaptureService] _runCapture() mode =", mode)
        root.busy = true

        let script = root._fullScript
        if (mode === "region") script = root._regionScript
        else if (mode === "window") script = root._windowScript

        captureProc.command = ["bash", "-c", script]
        captureProc.running = true
    }

    function copyLast() {
        if (root.lastPath === "") return
        root._run(["bash", "-c", 'wl-copy --type image/png < "$1"', "_", root.lastPath])
    }

    function copyPath() {
        if (root.lastPath === "") return
        root._run(["bash", "-c", 'printf "%s" "$1" | wl-copy', "_", root.lastPath])
    }

    function openLast() {
        if (root.lastPath === "") return
        root._run(["xdg-open", root.lastPath])
    }

    function deleteLast() {
        if (root.lastPath === "") return
        root._run(["rm", "-f", root.lastPath])
        root.bannerVisible = false
        root.lastPath = ""
    }

    function dismissBanner() {
        root.bannerVisible = false
    }

    function _run(cmd) {
        if (actionProc.running) return
        actionProc.command = cmd
        actionProc.running = true
    }

    Timer {
        id: executeTimer

        interval: 250
        onTriggered: root._runCapture(root.pendingMode)
    }

    Process {
        id: captureProc

        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }

        onRunningChanged: {
            if (captureProc.running)
                console.log("[CaptureService] capture process started, mode =", root.pendingMode)
        }

        onExited: (exitCode, exitStatus) => {
            root.busy = false
            const p = captureProc.stdout.text.trim()
            console.log("[CaptureService] process exited: code =", exitCode, "path =", JSON.stringify(p), "stderr =", JSON.stringify(captureProc.stderr.text.trim()))

            if (exitCode === 0 && p !== "") {
                root.lastPath = p
                root.lastTimestamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss")
                root.bannerVisible = true
                root.captured(root.lastPath, root.lastTimestamp)
            }
        }
    }

    Process {
        id: actionProc

        command: ["true"]
    }

    Timer {
        id: dismissTimer

        interval: 5000
        running: root.bannerVisible && !root.bannerHovered
        onTriggered: root.bannerVisible = false
    }
}
