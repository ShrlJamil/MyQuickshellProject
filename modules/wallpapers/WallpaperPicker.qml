import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import "../../components"

// Wallpaper picker - a compact single-row DynamicCenter surface. A horizontal
// thumbnail strip with < / > arrows, full keyboard nav (Left/H, Right/L, Enter/
// Space to apply, Esc to close), and inline apply via Process (mirrors
// ~/.local/bin/walset-backend: awww per monitor + wallust + matugen + hyprlock
// copy + notify). Carries the concave-top-corner frame like the other surfaces.
Item {
    id: root

    signal closeRequested()

    // Kept for callers / debugging - mirrors the strip's current item.
    property int selectedIndex: -1
    property string selectedPath: ""

    readonly property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"

    // Natural size DynamicCenter fits its frame to (the carousel + arrows are
    // laid out for the standard width). Constant -> no loop.
    implicitWidth: 680
    implicitHeight: 140

    onVisibleChanged: if (root.visible) {
        root.forceActiveFocus()
        root._reloadWallpapers()
    }

    Component.onCompleted: root._reloadWallpapers()

    function _pathAt(i) {
        if (i < 0 || i >= wallModel.count)
            return ""
        const o = wallModel.get(i)
        const u = String((o && o.fileUrl) || "")
        return decodeURIComponent(u.replace(/^file:\/\//, ""))
    }

    function step(dir) {
        if (wallModel.count === 0)
            return
        const base = strip.currentIndex < 0 ? 0 : strip.currentIndex
        strip.currentIndex = Math.max(0, Math.min(wallModel.count - 1, base + dir))
    }

    function applyIndex(i) {
        const p = root._pathAt(i)
        if (p === "")
            return
        root.selectedIndex = i
        root.selectedPath = p
        strip.currentIndex = i
        wallpaperProc.img = p
        if (!wallpaperProc.running)
            wallpaperProc.running = true
        root.closeRequested()
    }

    Keys.onPressed: (event) => {
        switch (event.key) {
        case Qt.Key_Escape:
            root.closeRequested()
            event.accepted = true
            break
        case Qt.Key_Left:
        case Qt.Key_H:
            root.step(-1)
            event.accepted = true
            break
        case Qt.Key_Right:
        case Qt.Key_L:
            root.step(1)
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.applyIndex(strip.currentIndex < 0 ? 0 : strip.currentIndex)
            event.accepted = true
            break
        }
    }

    property bool _rebuilding: false

    ListModel {
        id: wallModel

        onCountChanged: if (!root._rebuilding && strip.currentIndex < 0 && wallModel.count > 0) strip.currentIndex = 0
    }

    Process {
        id: dirProc

        command: ["find", root.wallpaperDir, "-maxdepth", "1", "-type", "f", "-printf", "%f\n"]
        stdout: StdioCollector { id: dirOut; waitForEnd: true }

        onExited: (code) => {
            if (code === 0)
                root._populate(dirOut.text)
        }
    }

    function _reloadWallpapers() {
        if (!dirProc.running)
            dirProc.running = true
    }

    function _populate(text) {
        var keep = root.selectedPath
        var rows = String(text || "").split("\n")
        var items = []
        for (var i = 0; i < rows.length; i++) {
            var nm = rows[i].trim()
            if (nm.length === 0 || nm.charAt(0) === ".")
                continue
            if (!/\.(jpe?g|png|webp)$/i.test(nm))
                continue
            items.push(nm)
        }
        items.sort()
        root._rebuilding = true
        wallModel.clear()
        for (var j = 0; j < items.length; j++)
            wallModel.append({ fileUrl: "file://" + encodeURI(root.wallpaperDir + "/" + items[j]) })
        root._rebuilding = false
        if (strip.currentIndex < 0 && wallModel.count > 0)
            strip.currentIndex = 0
        if (keep !== "" && wallModel.count > 0) {
            for (var k = 0; k < wallModel.count; k++) {
                if (root._pathAt(k) === keep) {
                    strip.currentIndex = k
                    break
                }
            }
        }
    }

    // Inline wallpaper + theme apply. $1 == image path.
    Process {
        id: wallpaperProc

        property string img: ""

        command: ["bash", "-c",
            'export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}; ' +
            'export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}; ' +
            'IMAGE="$1"; ' +
            'pgrep -x awww-daemon >/dev/null || { awww-daemon & sleep 0.3; }; ' +
            'for m in $(hyprctl monitors -j | jq -r ".[].name"); do ' +
            '  awww img -o "$m" "$IMAGE" --transition-type grow --transition-pos center ' +
            '  --transition-duration 2 --transition-fps 120 --transition-bezier .43,1.19,1,.4; ' +
            'done; ' +
            'wallust run "$IMAGE" --skip-sequences; ' +
            'matugen -t scheme-tonal-spot --contrast 0.4 --prefer saturation image "$IMAGE" --source-color-index 0; ' +
            'mkdir -p "$HOME/Pictures/hyprlock" && cp "$IMAGE" "$HOME/Pictures/hyprlock/current_wallpaper.jpg"; ' +
            'notify-send "Theme Applied" "Wallpaper and theme updated successfully!" -i "$IMAGE"',
            "walset-inline", wallpaperProc.img]

        onExited: (code) => console.log("[WallpaperPicker] apply exited", code)
    }

    // ---- concave DynamicCenter frame ---------------------------------------
    Shape {
        id: background

        anchors.fill: parent
        antialiasing: true
        asynchronous: false
        vendorExtensionsEnabled: true
        preferredRendererType: Shape.CurveRenderer

        readonly property real notchSize: 18
        readonly property real bottomRadius: Theme.cornerRadius

        ShapePath {
            // Transparent: the DynamicCenter frame is the sole panel background.
            fillColor: "transparent"
            strokeColor: "transparent"
            strokeWidth: 0

            startX: 0
            startY: 0

            PathCubic {
                control1X: background.notchSize * 0.5
                control1Y: 0
                control2X: background.notchSize
                control2Y: background.notchSize * 0.5
                x: background.notchSize
                y: background.notchSize
            }
            PathLine {
                x: background.notchSize
                y: background.height - background.bottomRadius
            }
            PathQuad {
                controlX: background.notchSize
                controlY: background.height
                x: background.notchSize + background.bottomRadius
                y: background.height
            }
            PathLine {
                x: background.width - background.notchSize - background.bottomRadius
                y: background.height
            }
            PathQuad {
                controlX: background.width - background.notchSize
                controlY: background.height
                x: background.width - background.notchSize
                y: background.height - background.bottomRadius
            }
            PathLine {
                x: background.width - background.notchSize
                y: background.notchSize
            }
            PathCubic {
                control1X: background.width - background.notchSize
                control1Y: background.notchSize * 0.5
                control2X: background.width - background.notchSize * 0.5
                control2Y: 0
                x: background.width
                y: 0
            }
            PathLine {
                x: 0
                y: 0
            }
        }
    }

    // ---- single-row strip -------------------------------------------------
    Row {
        id: contentRow

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        anchors.leftMargin: 14
        anchors.rightMargin: 14

        spacing: 10

        component NavButton: Rectangle {
            property string glyph: ""
            signal activated()

            width: 30
            height: 88
            anchors.verticalCenter: parent.verticalCenter
            radius: 10
            color: navHover.hovered ? Theme.surfaceHover : "transparent"

            Text {
                anchors.centerIn: parent
                text: parent.glyph
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 22
                font.weight: Font.Bold
            }

            HoverHandler {
                id: navHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: {
                    parent.activated()
                    root.forceActiveFocus()
                }
            }
        }

        NavButton {
            glyph: "‹"
            onActivated: root.step(-1)
        }

        ListView {
            id: strip

            width: contentRow.width - 2 * (30 + contentRow.spacing)
            height: 104
            anchors.verticalCenter: parent.verticalCenter

            orientation: ListView.Horizontal
            spacing: 12
            clip: true
            model: wallModel
            currentIndex: -1

            // Recycle delegates during fast scrolling instead of churning
            // create/destroy; the per-cell Loader below drops each decoded
            // thumbnail as it leaves the carousel centre.
            reuseItems: true

            // Keep the current thumbnail centred, animated.
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 200
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: (strip.width - 164) / 2
            preferredHighlightEnd: (strip.width - 164) / 2

            onCurrentIndexChanged: {
                if (strip.currentIndex >= 0) {
                    root.selectedIndex = strip.currentIndex
                    root.selectedPath = root._pathAt(strip.currentIndex)
                }
            }

            delegate: Item {
                id: cell

                required property int index
                required property url fileUrl

                width: 170
                height: strip.height

                readonly property bool current: strip.currentIndex === cell.index

                Rectangle {
                    id: thumbCard

                    anchors.centerIn: parent
                    width: 164
                    height: 92
                    radius: 12
                    color: Theme.surfaceHover

                    // Carousel focus: the current thumbnail zooms to full size /
                    // opacity, the rest recede and dim for depth. No outline.
                    scale: cell.current ? 1.05 : 0.88
                    opacity: cell.current ? 1.0 : 0.6
                    Behavior on scale {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    // Lazy thumbnail: only the ~5 cells around the carousel
                    // centre actually decode an image; everything else keeps
                    // just the placeholder card. The Loader unloads (frees the
                    // decoded pixmap) when a cell scrolls away or is reused.
                    //
                    // Item.clip does NOT clip an Image to the corner radius - it
                    // only clips to the bounding box. Round it with a layer
                    // OpacityMask (the codebase's proven pattern; ClippingRectangle
                    // SIGSEGVs on Quickshell 0.3.1). Survives the scale animation.
                    Loader {
                        id: thumbLoader

                        anchors.fill: parent
                        asynchronous: true
                        visible: thumbLoader.status === Loader.Ready
                        active: cell.current
                            || (strip.currentIndex >= 0 && Math.abs(cell.index - strip.currentIndex) <= 2)

                        sourceComponent: Image {
                            id: thumbImg

                            anchors.fill: parent

                            source: cell.fileUrl
                            sourceSize.width: 340
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true

                            layer.enabled: thumbImg.status === Image.Ready
                            layer.smooth: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: thumbImg.width
                                    height: thumbImg.height
                                    radius: thumbCard.radius
                                }
                            }
                        }
                    }

                    HoverHandler {
                        id: thumbHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: root.applyIndex(cell.index)
                    }
                }
            }
        }

        NavButton {
            glyph: "›"
            onActivated: root.step(1)
        }
    }
}
