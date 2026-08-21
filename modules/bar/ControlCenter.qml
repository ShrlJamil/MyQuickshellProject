import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../components"

PanelWindow {
    id: root

    required property var modelData

    readonly property var barState: modelData.barState

    screen: modelData.screen

    property bool open: barState.mode === "center" && barState.screen === modelData.screen
    property bool closing: false
    property bool wifiPanelOpen: false

    visible: root.open || root.closing

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        right: true
    }

    readonly property real barStripHeight: 40
    readonly property real barGap: 8
    property int topMargin: 48
    property int barSurfaceTop: 0

    margins {
        top: root.topMargin
        right: 12
    }

    color: "transparent"

    readonly property real colWidth: 210
    readonly property real colGap: 12
    readonly property real wifiHeight: 100
    readonly property real circleSize: 100
    readonly property real circleGap: 10
    readonly property real rowGap: 10
    readonly property real mediaHeight: 210
    readonly property real focusHeight: 100
    readonly property real sliderHeight: 100
    readonly property real tilesHeight: root.wifiHeight + root.rowGap + root.circleSize + root.rowGap + root.focusHeight
    readonly property real contentHeight: root.tilesHeight + root.rowGap + root.sliderHeight + root.rowGap + root.sliderHeight + root.rowGap + root.circleSize

    implicitWidth: root.colWidth * 2 + root.colGap
    implicitHeight: root.contentHeight

    focusable: root.visible

    onVisibleChanged: {
        if (root.visible) {
            root.probeBarSurface()
            content.forceActiveFocus()
        }
    }

    Component.onCompleted: root.probeBarSurface()

    function probeBarSurface() {
        if (!barProbe.running) barProbe.running = true
    }

    function updateBarSurface() {
        try {
            const layers = JSON.parse(barProbe.stdout.text)
            const mon = layers[root.screen.name]
            if (mon == null || mon.levels == null) return

            root.barSurfaceTop = 0

            for (const key of Object.keys(mon.levels)) {
                const arr = mon.levels[key]
                if (!Array.isArray(arr)) continue

                const level = parseInt(key, 10)

                for (const surf of arr) {
                    if (surf.namespace !== "quickshell" || surf.pid !== Quickshell.processId) continue
                    if (level === 2) root.barSurfaceTop = surf.y
                }
            }

            if (root.barSurfaceTop > 0) {
                const target = root.barSurfaceTop + root.barStripHeight + root.barGap
                const screenY = root.screen.y ? root.screen.y : 0
                root.topMargin = Math.max(8, target - screenY)
            }
        } catch (e) {}
    }

    Process {
        id: barProbe

        command: ["hyprctl", "-j", "layers"]

        stdout: StdioCollector {
            waitForEnd: true
        }

        onExited: root.updateBarSurface()
    }

    function close() {
        barState.screen = null
        barState.mode = ""

        if (root.open) {
            root.closing = true
            hideTimer.restart()
        }
    }

    function wifiStatusText(net) {
        if (net === null || net === undefined) return ""
        if (net.connected) return "Connected"
        if (net.connecting) return "Connecting…"
        if (net.failed) return "Connection failed"
        if (!net.known && net.secured) return "Password required"
        return (net.secured ? "Secured · " : "Open · ") + net.signal + "%"
    }

    onOpenChanged: {
        if (root.open) {
            root.closing = false
            hideTimer.stop()
        }
    }

    Timer {
        id: hideTimer

        interval: 210
        onTriggered: root.closing = false
    }

    HyprlandFocusGrab {
        id: focusGrab

        windows: [root]
        active: root.visible

        onCleared: root.close()
    }

    WifiService {
        id: wifiService
    }

    Item {
        id: content

        anchors.fill: parent

        opacity: 0

        transform: Translate {
            id: drift

            y: -(root.implicitHeight)
        }

        states: [
            State {
                name: "open"

                when: root.open

                PropertyChanges {
                    target: content
                    opacity: 1
                }

                PropertyChanges {
                    target: drift
                    y: 0
                }
            }
        ]

        transitions: [
            Transition {
                from: ""
                to: "open"

                ParallelAnimation {
                    NumberAnimation {
                        target: content
                        property: "opacity"
                        duration: 180
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        target: drift
                        property: "y"
                        duration: 230
                        easing.type: Easing.OutCubic
                    }
                }
            },

            Transition {
                from: "open"
                to: ""

                ParallelAnimation {
                    NumberAnimation {
                        target: content
                        property: "opacity"
                        duration: 140
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        target: drift
                        property: "y"
                        duration: 170
                        easing.type: Easing.OutCubic
                    }
                }
            }
        ]

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                if (root.wifiPanelOpen) root.wifiPanelOpen = false
                else root.close()
                event.accepted = true
            }
        }

        Row {
            id: columns

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }

            height: root.tilesHeight

            spacing: root.colGap

            Column {
                id: leftColumn

                width: root.colWidth

                spacing: root.rowGap

                Rectangle {
                    id: wifiTile

                    width: parent.width
                    height: root.wifiHeight

                    radius: 22
                    color: wifiHover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background

                    HoverHandler {
                        id: wifiHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }

                        anchors.leftMargin: 14
                        anchors.rightMargin: 14

                        spacing: 12

                        Item {
                            width: 36
                            height: 36

                            Rectangle {
                                id: wifiActiveCircle

                                anchors.centerIn: parent

                                width: 44
                                height: 44
                                radius: width / 2
                                color: Theme.accent
                                visible: wifiService.enabled
                            }

                            IconImage {
                                anchors.centerIn: parent

                                width: 36
                                height: 36

                                source: Quickshell.iconPath("network-wireless-symbolic", "network-wireless")
                                asynchronous: true
                            }

                            MouseArea {
                                anchors.centerIn: parent

                                width: 44
                                height: 44
                                cursorShape: Qt.PointingHandCursor

                                onClicked: wifiService.toggle()
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter

                            width: parent.parent.width - 36 - 12 - 60

                            spacing: 2

                            Text {
                                width: parent.width
                                elide: Text.ElideRight

                                text: "Wi-Fi"
                                color: Theme.text
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideRight

                                text: {
                                    if (!wifiService.enabled) return "Off"
                                    if (wifiService.connected) return wifiService.connectionName
                                    return "Not connected"
                                }

                                color: Theme.textMuted
                                font.pixelSize: 11
                            }
                        }
                    }

                    IconImage {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }

                        anchors.rightMargin: 8

                        width: 16
                        height: 16

                        source: Quickshell.iconPath("go-next-symbolic", "go-next")
                        asynchronous: true
                    }

                    MouseArea {
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            bottom: parent.bottom
                        }

                        anchors.leftMargin: 62
                        anchors.rightMargin: 14

                        cursorShape: Qt.PointingHandCursor

                        onClicked: root.wifiPanelOpen = true
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter

                    spacing: root.circleGap

                    ControlTile {
                        width: root.circleSize
                        height: root.circleSize

                        round: true
                        label: "Bluetooth"
                        iconSource: Quickshell.iconPath("bluetooth-active-symbolic", "bluetooth")
                    }

                    ControlTile {
                        width: root.circleSize
                        height: root.circleSize

                        round: true
                        label: "Mobile"
                        iconSource: Quickshell.iconPath("network-wireless-hotspot", "network-wireless")
                    }
                }

                ControlTile {
                    width: root.colWidth
                    height: root.focusHeight

                    label: "Focus"
                    iconSource: Quickshell.iconPath("moon-symbolic", "weather-clear-night")
                }
            }

            Column {
                id: rightColumn

                width: root.colWidth

                spacing: root.rowGap

                Rectangle {
                    id: mediaTile

                    width: parent.width
                    height: root.mediaHeight

                radius: 22
                color: mediaHover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background

                HoverHandler {
                    id: mediaHover

                    cursorShape: Qt.PointingHandCursor
                }

                Column {
                    anchors.centerIn: parent

                    spacing: 6

                    IconImage {
                        width: 44
                        height: 44

                        anchors.horizontalCenter: parent.horizontalCenter

                        source: Quickshell.iconPath("multimedia-player-symbolic", "applications-multimedia")
                        asynchronous: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: "Media"
                        color: Theme.text
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: "Nothing playing"
                        color: Theme.textMuted
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    id: mediaTrack

                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }

                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    anchors.bottomMargin: 26

                    height: 4
                    radius: 2
                    color: Theme.surface

                    Rectangle {
                        id: mediaTrackFill

                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                        }

                        width: parent.width * 0.35

                        radius: 2
                        color: Theme.accent
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter

                spacing: root.circleGap

                ControlTile {
                    width: root.circleSize
                    height: root.circleSize

                    round: true
                    label: "Workspaces"
                    iconSource: Quickshell.iconPath("view-app-grid-symbolic", "view-grid-symbolic")
                }

                ControlTile {
                    width: root.circleSize
                    height: root.circleSize

                    round: true
                    label: "Display"
                    iconSource: Quickshell.iconPath("video-display-symbolic", "video-display")
                }
            }
        }
    }

    Rectangle {
        id: displayTile

            anchors {
                left: parent.left
                right: parent.right
                top: columns.bottom
            }

            anchors.topMargin: root.rowGap

            height: root.sliderHeight

            radius: 22
            color: displayHover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background

            HoverHandler {
                id: displayHover

                cursorShape: Qt.PointingHandCursor
            }

            Text {
                id: displayLabel

                anchors {
                    left: parent.left
                    top: parent.top
                }

                anchors.leftMargin: 20
                anchors.topMargin: 16

                text: "Display"
                color: Theme.text
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            ControlSlider {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: displayLabel.bottom
                    bottom: parent.bottom
                }

                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 8
                anchors.bottomMargin: 12

                label: "Display"
                iconSource: Quickshell.iconPath("display-brightness-symbolic", "video-display")
                value: 0.8
            }
        }

        Rectangle {
            id: soundTile

            anchors {
                left: parent.left
                right: parent.right
                top: displayTile.bottom
            }

            anchors.topMargin: root.rowGap

            height: root.sliderHeight

            radius: 22
            color: soundHover.hovered ? Qt.lighter(Theme.background, 1.35) : Theme.background

            HoverHandler {
                id: soundHover

                cursorShape: Qt.PointingHandCursor
            }

            Text {
                id: soundLabel

                anchors {
                    left: parent.left
                    top: parent.top
                }

                anchors.leftMargin: 20
                anchors.topMargin: 16

                text: "Sound"
                color: Theme.text
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            ControlSlider {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: soundLabel.bottom
                    bottom: parent.bottom
                }

                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 8
                anchors.bottomMargin: 12

                label: "Sound"
                iconSource: Quickshell.iconPath("audio-volume-high-symbolic", "audio-volume-high")
                value: 0.6
            }
        }

        Row {
            anchors {
                top: soundTile.bottom
                horizontalCenter: parent.horizontalCenter
            }

            anchors.topMargin: root.rowGap

            height: root.circleSize

            spacing: root.circleGap

            ControlTile {
                width: root.circleSize
                height: root.circleSize

                round: true
                label: "Capture"
                iconSource: Quickshell.iconPath("camera-photo-symbolic", "camera-photo")
            }

            ControlTile {
                width: root.circleSize
                height: root.circleSize

                round: true
                active: false
                label: "Night Light"
                iconSource: Quickshell.iconPath("night-light-symbolic", "weather-clear-night")
            }

            ControlTile {
                width: root.circleSize
                height: root.circleSize

                round: true
                label: "Mic"
                iconSource: Quickshell.iconPath("microphone-sensitivity-muted-symbolic", "microphone-sensitivity-muted")
            }

            ControlTile {
                width: root.circleSize
                height: root.circleSize

                round: true
                label: "Output"
                iconSource: Quickshell.iconPath("audio-speakers-symbolic", "audio-speakers")
            }
        }
    }

    Rectangle {
        id: wifiPanel

        anchors.fill: parent

        z: 10
        visible: root.wifiPanelOpen

        radius: 22
        color: Theme.background
        clip: true

        Column {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            anchors.margins: 14

            spacing: 8

            Row {
                width: parent.width
                height: 32

                spacing: 10

                MouseArea {
                    width: 32
                    height: 32
                    cursorShape: Qt.PointingHandCursor

                    onClicked: root.wifiPanelOpen = false

                    Rectangle {
                        anchors.fill: parent

                        radius: 16
                        color: backHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"
                    }

                    HoverHandler {
                        id: backHover
                    }

                    IconImage {
                        anchors.centerIn: parent

                        width: 18
                        height: 18

                        source: Quickshell.iconPath("go-previous-symbolic", "go-previous")
                        asynchronous: true
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter

                    text: "Wi-Fi"
                    color: Theme.text
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter

                text: wifiService.enabled ? "No networks found" : "Wi-Fi is Off"
                color: Theme.textMuted
                font.pixelSize: 12
                visible: wifiService.viewNetworks.length === 0
            }

            ListView {
                id: wifiList

                width: parent.width
                height: parent.height - 40

                clip: true
                spacing: 4
                visible: wifiService.viewNetworks.length > 0
                model: wifiService.viewNetworks

                delegate: Rectangle {
                    id: row

                    required property var modelData

                    readonly property var net: row.modelData

                    width: wifiList.width
                    height: 52
                    radius: 14
                    color: rowHover.hovered ? Qt.lighter(Theme.background, 1.35) : "transparent"

                    HoverHandler {
                        id: rowHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    Row {
                        anchors.fill: parent

                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        spacing: 10

                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter

                            width: 28
                            height: 28

                            source: {
                                switch (row.net ? row.net.level : -1) {
                                case 4: return Quickshell.iconPath("network-wireless-signal-excellent-symbolic", "network-wireless-signal-excellent")
                                case 3: return Quickshell.iconPath("network-wireless-signal-good-symbolic", "network-wireless-signal-good")
                                case 2: return Quickshell.iconPath("network-wireless-signal-ok-symbolic", "network-wireless-signal-ok")
                                case 1: return Quickshell.iconPath("network-wireless-signal-weak-symbolic", "network-wireless-signal-weak")
                                default: return Quickshell.iconPath("network-wireless-signal-none-symbolic", "network-wireless-signal-none")
                                }
                            }

                            asynchronous: true
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter

                            width: parent.width - 28 - 10 - (check.visible ? check.width + 10 : 0)

                            spacing: 2

                            Text {
                                width: parent.width
                                elide: Text.ElideRight

                                text: row.net ? row.net.name : ""
                                color: Theme.text
                                font.pixelSize: 13
                                font.weight: row.net && row.net.connected ? Font.DemiBold : Font.Normal
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideRight

                                text: root.wifiStatusText(row.net)
                                color: Theme.textMuted
                                font.pixelSize: 11
                            }
                        }

                        IconImage {
                            id: check

                            anchors.verticalCenter: parent.verticalCenter

                            width: 18
                            height: 18
                            visible: row.net && row.net.connected

                            source: Quickshell.iconPath("object-select-symbolic", "emblem-default")
                            asynchronous: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent

                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: (mouse) => {
                            if (row.net === null || row.net === undefined) return
                            if (mouse.button === Qt.RightButton) {
                                if (row.net.known) wifiService.forgetNetwork(row.net.name)
                            } else {
                                wifiService.connectNetwork(row.net.name)
                            }
                        }
                    }
                }
            }
        }
    }
}