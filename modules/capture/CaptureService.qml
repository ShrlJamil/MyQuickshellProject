pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool busy: false
    property bool barVisible: false
    property string pendingMode: ""
    property bool regionSelectActive: false
    property bool windowSelectActive: false
    property string _pendingGeometry: ""

    onBarVisibleChanged: console.log("[CaptureService] barVisible ->", root.barVisible)

    property string lastPath: ""
    property string lastTimestamp: ""
    property bool bannerVisible: false
    property bool bannerHovered: false

    signal captured(string imagePath, string timestamp)

    function openBar() {
        console.log("[CaptureService] openBar()")
        root.barVisible = true
    }

    function closeBar() {
        console.log("[CaptureService] Bar closed")
        root.barVisible = false
    }

    function triggerCapture(mode) {
        console.log("[CaptureService] triggerCapture(", mode, ")")
        root.pendingMode = mode
        root.closeBar()

        if (mode === "region") {
            root.regionSelectActive = true
            return
        }

        if (mode === "window") {
            root.windowSelectActive = true
            return
        }

        executeTimer.restart()
    }

    function captureRegion() {
        root.triggerCapture("region")
    }

    function captureFullscreen() {
        root.triggerCapture("screen")
    }

    function completeRegionSelection(geometry) {
        root.regionSelectActive = false

        if (!geometry || !/^-?\d+,-?\d+ \d+x\d+$/.test(geometry)) {
            console.log("[CaptureService] Discarding invalid region geometry:", geometry)
            return
        }

        root._pendingGeometry = geometry
        regionCaptureTimer.restart()
    }

    function cancelRegionSelection() {
        console.log("[CaptureService] Region selection cancelled")
        root.regionSelectActive = false
    }

    function completeWindowSelection(geometry) {
        root.windowSelectActive = false

        if (!geometry || !/^-?\d+,-?\d+ \d+x\d+$/.test(geometry)) {
            console.log("[CaptureService] Discarding invalid window geometry:", geometry)
            return
        }

        root._pendingGeometry = geometry
        windowCaptureTimer.restart()
    }

    function cancelWindowSelection() {
        console.log("[CaptureService] Window selection cancelled")
        root.windowSelectActive = false
    }

    function _runCapture(mode, geometry) {
        if (captureProc.running) {
            console.log("[CaptureService] Terminating lingering capture process...")
            captureProc.running = false
        }

        const envPrefix = 'export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}; export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}; '

        let cmd = envPrefix + 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim "$f" && wl-copy --type image/png < "$f" && echo "$f"'
        if (mode === "region" || mode === "window")
            cmd = envPrefix + 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim -g "' + geometry + '" "$f" && wl-copy --type image/png < "$f" && echo "$f"'

        console.log("[CaptureService] Launching command for mode:", mode)
        console.log("[CaptureService] cmd:", cmd)
        root.busy = true
        captureProc.command = ["sh", "-c", cmd]
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

    Timer {
        id: regionCaptureTimer

        interval: 120
        onTriggered: root._runCapture("region", root._pendingGeometry)
    }

    Timer {
        id: windowCaptureTimer

        interval: 120
        onTriggered: root._runCapture("window", root._pendingGeometry)
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

            console.log("[CaptureService] Process exited code:", exitCode, "status:", exitStatus)
            console.log("[CaptureService] stdout:", captureProc.stdout.text.trim())
            console.log("[CaptureService] stderr:", captureProc.stderr.text.trim())

            const out = captureProc.stdout.text.trim()
            if (exitCode === 0 && out !== "") {
                console.log("[CaptureService] Capture successful:", out)
                root.lastPath = out
                root.lastTimestamp = Qt.formatDateTime(new Date(), "hh:mm A")
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
