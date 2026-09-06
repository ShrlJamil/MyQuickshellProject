import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../components"
import "../capture"

PanelWindow {
    id: root

    required property var modelData

    readonly property var barState: modelData.barState
    readonly property var launcherController: modelData.launcherController

    screen: modelData.screen

    visible: barState.barEnabled

    property bool centerOpen: barState.mode === "center" && barState.screen === root.screen
    readonly property bool isCaptureActive: CaptureService.barVisible
        && root.screen
        && Hyprland.focusedMonitor
        && root.screen.name === Hyprland.focusedMonitor.name
    property bool surfaceActive: (barState.screen === root.screen && (barState.mode === "power" || barState.mode === "display" || barState.mode === "mediaPreview" || barState.mode === "mediaCompact")) || root.isCaptureActive

    onIsCaptureActiveChanged: console.log("[Bar] isCaptureActive ->", root.isCaptureActive, "screen =", (root.screen ? root.screen.name : "null"))

    readonly property int fixedHeight: 540

    implicitHeight: root.fixedHeight

    anchors {
        top: true
        left: true
        right: true
    }

    color: "transparent"

    exclusiveZone: 40
    focusable: root.surfaceActive

    mask: root.surfaceActive ? activeMask : idleMask
    Region { id: idleMask; item: barContent }
    Region {
        id: activeMask
        item: barContent
        Region { item: dynamicCenter }
    }

    HyprlandFocusGrab {
        id: focusGrab

        windows: [root]
        active: root.surfaceActive

        onCleared: {
            if (!root.surfaceActive)
                return
            barState.screen = null
            barState.mode = ""
            CaptureService.closeBar()
        }
    }

    Rectangle {
        id: barContent

        x: 0
        y: 0
        width: parent.width
        height: 40
        clip: true
        z: 999

        color: Theme.background

        Item {
            id: leftSlot

            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }

            anchors.leftMargin: 8

            width: 36
            height: 36

            Rectangle {
                id: launcherButton

                anchors.fill: parent

                radius: 10
                color: launcherTap.pressed ? Theme.surfaceHover : (launcherHover.hovered ? Theme.surfaceHover : "transparent")

                HoverHandler {
                    id: launcherHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: launcherTap

                    onTapped: root.launcherController.toggle()
                }

                IconImage {
                    id: launcherIcon

                    anchors.centerIn: parent

                    source: Quickshell.iconPath("system-search", "application-x-executable")
                    asynchronous: true
                }
            }
        }

        Row {
            id: activeWindowRow

            readonly property string rawAppId: ToplevelManager.activeToplevel?.appId ?? ""
            readonly property string displayName: {
                if (rawAppId.length === 0)
                    return "Desktop"
                let names = {
                    "code": "VS Code",
                    "code-url-handler": "VS Code",
                    "code-oss": "VS Code",
                    "ghostty": "Ghostty",
                    "com.mitchellh.ghostty": "Ghostty",
                    "org.gnome.Nautilus": "Files",
                    "org.gnome.nautilus": "Files",
                    "google-chrome": "Chrome",
                    "chrome": "Chrome",
                    "chromium": "Chrome",
                    "firefox": "Firefox",
                    "kitty": "Kitty"
                }
                if (names[rawAppId] !== undefined)
                    return names[rawAppId]
                let lower = rawAppId.toLowerCase()
                if (names[lower] !== undefined)
                    return names[lower]
                let parts = rawAppId.split(".")
                let name = parts[parts.length - 1]
                return name.charAt(0).toUpperCase() + name.slice(1)
            }

            anchors {
                left: leftSlot.right
                verticalCenter: parent.verticalCenter
            }

            anchors.leftMargin: 8

            spacing: activeWindowIcon.visible ? 6 : 0

            IconImage {
                id: activeWindowIcon

                visible: activeWindowRow.rawAppId.length > 0
                width: visible ? 16 : 0
                height: 16
                anchors.verticalCenter: parent.verticalCenter

                source: Quickshell.iconPath(activeWindowRow.rawAppId, "computer")
                asynchronous: true
            }

            Text {
                id: activeWindowTitle

                width: Math.min(implicitWidth, 180)
                anchors.verticalCenter: parent.verticalCenter

                text: activeWindowRow.displayName
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.textDim
                font.pixelSize: 12
            }
        }

        Text {
            id: holdLabel

            anchors.centerIn: parent
            visible: barState.screen === root.screen && (barState.mode === "power" || barState.mode === "display" || barState.mode === "mediaPreview" || barState.mode === "mediaCompact")
            text: barState.mode === "power" ? "Power Menu"
                : barState.mode === "display" ? "Display"
                : (barState.mode === "mediaPreview" || barState.mode === "mediaCompact") ? "Media"
                : ""
            color: Theme.textMuted
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Item {
            id: rightSlot

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }

            anchors.rightMargin: 8

            width: 36
            height: 36

            Rectangle {
                id: centerButton

                anchors.fill: parent

                radius: 10
                color: root.centerOpen || centerTap.pressed ? Theme.surfaceHover : (centerHover.hovered ? Theme.surfaceHover : "transparent")

                HoverHandler {
                    id: centerHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: centerTap

                    onTapped: {
                        if (root.centerOpen) {
                            barState.screen = null
                            barState.mode = ""
                        } else {
                            barState.screen = root.screen
                            barState.mode = "center"
                        }
                    }
                }

                IconImage {
                    id: centerIcon

                    anchors.centerIn: parent

                    width: 20
                    height: 20

                    source: "file://" + Quickshell.shellPath("assets/controls-symbolic.svg")
                    asynchronous: true
                }
            }
        }

        DateTimeWidget {
            id: dateTime

            screen: root.screen

            anchors {
                verticalCenter: parent.verticalCenter
                right: rightSlot.left
            }
            anchors.rightMargin: 8
        }

        BatteryWidget {
            id: battery

            screen: root.screen

            anchors {
                verticalCenter: parent.verticalCenter
                right: dateTime.left
            }
            anchors.rightMargin: 2
        }
    }

    DynamicCenter {
        id: dynamicCenter

        screen: root.screen
        anchors.horizontalCenter: parent.horizontalCenter
        activeSurface: barState.screen === root.screen && (barState.mode === "power" || barState.mode === "display" || barState.mode === "mediaPreview" || barState.mode === "mediaCompact")
            ? barState.mode
            : root.isCaptureActive ? "capture" : "idle"
    }

    Connections {
        target: dynamicCenter

        onCloseRequested: {
            barState.screen = null
            barState.mode = ""
            CaptureService.closeBar()
        }
    }
}