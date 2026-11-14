import QtQuick
import Qt5Compat.GraphicalEffects
import "../../components"

// The Settings Appearance page: a thin view over PreferencesService,
// which owns validation and persistence (preferences.json). One
// section: Bar Appearance (layout mode, background transparency and
// opacity, segmented widget background opacity). Every control reads
// and writes the service directly - no local state - and values reach
// the shell live through the shell.qml bindings into Theme.
Item {
    id: root

    // Local Settings surface tokens, set by the host (SettingsView) so
    // this page stays monochrome-dark regardless of the global palette.
    property color settingsBackground: Theme.darkMode ? "#0A0A0A" : Theme.background
    property color settingsSurface: Theme.darkMode ? "#141414" : Theme.surface
    property color settingsSurfaceRaised: Theme.darkMode ? "#1E1E1E" : Theme.surfaceRaised
    property color settingsSurfaceOverlay: Theme.darkMode ? "#2A2A2A" : Theme.surfaceOverlay

    function percentText(v) {
        const p = Math.round(v * 1000) / 10
        return (Number.isInteger(p) ? String(p) : p.toFixed(1)) + "%"
    }

    // Derived from the service only (no local state): the Bar section
    // is at defaults when all four preferences match theirs.
    component PageButton: Rectangle {
        id: btn

        property string label: ""
        property bool accent: false
        property bool disabled: false
        signal activated()

        implicitWidth: btnLabel.implicitWidth + 24
        implicitHeight: 30
        radius: 8
        opacity: btn.disabled ? 0.45 : 1
        color: btn.accent ? Theme.accent : (btnHover.hovered && !btn.disabled ? Theme.surfaceHover : Qt.rgba(1, 1, 1, 0.03))
        border.width: 1
        border.color: "transparent"

        Text {
            id: btnLabel

            anchors.centerIn: parent
            text: btn.label
            color: btn.accent ? settingsBackground : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        HoverHandler {
            id: btnHover
            cursorShape: btn.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        }
        TapHandler {
            enabled: !btn.disabled
            onTapped: btn.activated()
        }
    }

    // Minimal slider in the Settings tokens: accent fill, overlay
    // handle. The value is owned by the caller (the service); the
    // slider only reports intent via moved(), so its handle always
    // shows the validated service value, including after a reset.
    component PrefSlider: Item {
        id: slider

        property real from: 0
        property real to: 1
        property real stepSize: 0.005
        property real value: 0
        property bool enabled: true
        signal moved(real value)

        implicitHeight: 26
        opacity: slider.enabled ? 1 : 0.45

        readonly property real _frac: (slider.value - slider.from) / (slider.to - slider.from)

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
            }

            height: 4
            radius: 2
            color: settingsSurfaceRaised

            Rectangle {
                width: parent.width * slider._frac
                height: parent.height
                radius: 2
                color: Theme.accent
            }
        }

        Rectangle {
            width: 16
            height: 16
            radius: 8
            x: slider._frac * (slider.width - width)
            anchors.verticalCenter: parent.verticalCenter
            color: settingsSurfaceOverlay
            border.width: 1
            border.color: slider.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.25)
        }

        MouseArea {
            anchors.fill: parent
            enabled: slider.enabled
            cursorShape: Qt.PointingHandCursor

            onPressed: (mouse) => {
                slider.forceActiveFocus()
                slider._apply(mouse.x)
            }
            onPositionChanged: (mouse) => {
                if (pressed)
                    slider._apply(mouse.x)
            }
        }

        function _apply(x) {
            const f = Math.max(0, Math.min(1, x / slider.width))
            let v = slider.from + f * (slider.to - slider.from)
            v = Math.round(v / slider.stepSize) * slider.stepSize
            slider.moved(Math.max(slider.from, Math.min(slider.to, v)))
        }

        Keys.onLeftPressed: slider.moved(Math.max(slider.from, slider.value - slider.stepSize))
        Keys.onRightPressed: slider.moved(Math.min(slider.to, slider.value + slider.stepSize))
    }

    // Minimal switch in the same visual language as PrefSlider: accent
    // track while on, overlay knob. Stateless like the slider - the
    // caller owns the value; toggled() only reports intent.
    component PrefToggle: Item {
        id: toggle

        property bool checked: false
        signal toggled()

        implicitWidth: 40
        implicitHeight: 22

        Rectangle {
            anchors.fill: parent
            radius: 11
            color: toggle.checked ? Theme.accent : settingsSurfaceRaised
        }

        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 3
            x: toggle.checked ? parent.width - width - 3 : 3
            color: settingsSurfaceOverlay
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.25)

            Behavior on x {
                NumberAnimation {
                    duration: 120
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled()
        }
    }

    // Layout mode picker tile: a flat miniature screen with the bar
    // drawn in the mode's shape, so the three modes read at a glance
    // without words. One box only - no frame layer around it - and
    // the active mode is marked by its border alone. Stateless like
    // PrefToggle: state comes from the service, chosen() is intent.
    component ModeTile: Rectangle {
        id: tile

        property string mode: "default"
        signal chosen()

        // Screen-shaped: the box keeps a 16:9 ratio at any width.
        height: width * 9 / 16
        radius: 8
        color: tileHover.hovered ? settingsSurfaceRaised : settingsBackground
        border.width: 2
        border.color: PreferencesService.barLayoutMode === tile.mode ? Theme.accent : "transparent"

        // Default: one slab attached to the top edge.
        Rectangle {
            visible: tile.mode === "default"

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 7
                leftMargin: 7
                rightMargin: 7
            }

            height: 8
            radius: 3
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.55)
        }

        // Float: one pill, inset from the top and side edges.
        Rectangle {
            visible: tile.mode === "float"

            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
                topMargin: 14
            }

            width: parent.width * 0.74
            height: 8
            radius: 4
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.55)
        }

        // Segmented: one pill per widget along the top edge.
        Row {
            visible: tile.mode === "segmented"

            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
                topMargin: 7
            }

            spacing: 5

            Rectangle {
                width: tile.width * 0.20
                height: 8
                radius: 4
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.55)
            }

            Rectangle {
                width: tile.width * 0.32
                height: 8
                radius: 4
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.55)
            }

            Rectangle {
                width: tile.width * 0.20
                height: 8
                radius: 4
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.55)
            }
        }

        HoverHandler {
            id: tileHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: tile.chosen()
        }
    }

    // ---- header -------------------------------------------------------------
    Text {
        id: pageTitle

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 10
            leftMargin: 10
            rightMargin: 10
        }

        text: "Appearance"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 18
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: divider

        anchors {
            top: pageTitle.bottom
            left: parent.left
            right: parent.right
            topMargin: 14
            leftMargin: 10
            rightMargin: 10
        }

        height: 1
        color: "transparent"
    }

    // ---- scrollable groups (header and footer stay pinned) -------------------
    Flickable {
        id: pageScroll

        anchors {
            top: divider.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        contentWidth: width
        contentHeight: scrollContent.height
        clip: true

    Item {
        id: scrollContent

        width: pageScroll.width
        height: typographyCard.y + typographyCard.height + 14

    // ---- Bar Appearance group ---------------------------------------------------
    Text {
        id: barTitle

        anchors {
            top: parent.top
            left: parent.left
            topMargin: 16
            leftMargin: 10
        }

        text: "Bar Appearance"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: barCard

        anchors {
            top: barTitle.bottom
            left: parent.left
            right: parent.right
            topMargin: 10
            leftMargin: 10
            rightMargin: 10
        }

        height: barContent.implicitHeight + 28
        radius: 10
        color: settingsSurface

        Column {
            id: barContent

            anchors {
                fill: parent
                margins: 14
            }

            spacing: 14

            // Layout mode: three illustration tiles, one per mode;
            // the accent-ringed tile is the service's current mode.
            // The flat miniatures replace the old text buttons and
            // their description - the shapes say what each mode does.
            Column {
                width: parent.width
                spacing: 8

                Text {
                    text: "Layout mode"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Row {
                    spacing: 14

                    ModeTile {
                        width: 150
                        mode: "default"
                        onChosen: PreferencesService.setBarLayoutMode("default")
                    }

                    ModeTile {
                        width: 150
                        mode: "float"
                        onChosen: PreferencesService.setBarLayoutMode("float")
                    }

                    ModeTile {
                        width: 150
                        mode: "segmented"
                        onChosen: PreferencesService.setBarLayoutMode("segmented")
                    }
                }
            }

            // Transparency + background opacity as ONE composite
            // control. The preview is the label: a mock bar over a
            // flat wallpaper, its fill following the same rule the
            // shell uses - solid while transparency is off, the
            // stored opacity while on. The switch beside the preview
            // owns the on/off; dragging the amount slider turns
            // transparency on by itself, so the whole thing answers
            // in one gesture and needs no explaining text.
            Column {
                width: parent.width
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        id: bgPreview

                        width: parent.width - 40 - 12
                        height: 42
                        radius: 9
                        color: settingsSurfaceOverlay

                        // Flat wallpaper shapes under the mock bar,
                        // masked to the preview's rounded corners.
                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: bgPreview.width
                                    height: bgPreview.height
                                    radius: bgPreview.radius
                                    visible: false
                                }
                            }

                            Rectangle {
                                width: 54
                                height: 54
                                radius: 27
                                x: parent.width - 44
                                y: -18
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                            }

                            Rectangle {
                                width: 90
                                height: 90
                                radius: 45
                                x: -30
                                y: 16
                                color: Qt.rgba(0, 0, 0, 0.28)
                            }

                            Rectangle {
                                width: 46
                                height: 46
                                radius: 23
                                x: parent.width * 0.38
                                y: 22
                                color: Qt.rgba(0, 0, 0, 0.18)
                            }
                        }

                        // The mock bar itself.
                        Rectangle {
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 6
                            }

                            height: 13
                            radius: 6.5
                            color: Qt.rgba(1, 1, 1, 0.92)
                            opacity: PreferencesService.barTransparency ? PreferencesService.barBackgroundOpacity : 1
                        }
                    }

                    PrefToggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: PreferencesService.barTransparency
                        onToggled: PreferencesService.setBarTransparency(!PreferencesService.barTransparency)
                    }
                }

                Row {
                    width: parent.width
                    spacing: 12

                    PrefSlider {
                        width: parent.width - bgValueText.implicitWidth - 12
                        height: 32
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0
                        to: 1
                        stepSize: 0.005
                        value: PreferencesService.barBackgroundOpacity
                        onMoved: (v) => {
                            if (!PreferencesService.barTransparency)
                                PreferencesService.setBarTransparency(true)
                            PreferencesService.setBarBackgroundOpacity(v)
                        }
                    }

                    Text {
                        id: bgValueText

                        anchors.verticalCenter: parent.verticalCenter
                        text: root.percentText(PreferencesService.barBackgroundOpacity)
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }
            }

            // Segmented widget backgrounds: the same pattern - three
            // mock widget pills over the flat wallpaper, their fills
            // following the stored opacity. No words needed. Shown
            // only while the segmented layout is active - the one
            // mode this setting affects.
            Column {
                visible: PreferencesService.barLayoutMode === "segmented"
                width: parent.width
                spacing: 10

                Rectangle {
                    id: widgetPreview

                    width: parent.width
                    height: 42
                    radius: 9
                    color: settingsSurfaceOverlay

                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: widgetPreview.width
                                height: widgetPreview.height
                                radius: widgetPreview.radius
                                visible: false
                            }
                        }

                        Rectangle {
                            width: 54
                            height: 54
                            radius: 27
                            x: parent.width - 44
                            y: -18
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                        }

                        Rectangle {
                            width: 90
                            height: 90
                            radius: 45
                            x: -30
                            y: 16
                            color: Qt.rgba(0, 0, 0, 0.28)
                        }

                        Rectangle {
                            width: 46
                            height: 46
                            radius: 23
                            x: parent.width * 0.38
                            y: 22
                            color: Qt.rgba(0, 0, 0, 0.18)
                        }
                    }

                    Row {
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            margins: 6
                        }

                        height: 13
                        spacing: 6

                        Repeater {
                            model: [0.24, 0.40, 0.24]

                            Rectangle {
                                width: (widgetPreview.width - 12 - 12) * modelData
                                height: 13
                                radius: 6.5
                                color: Qt.rgba(1, 1, 1, 0.92)
                                opacity: PreferencesService.barWidgetBackgroundOpacity
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 12

                    PrefSlider {
                        width: parent.width - widgetValueText.implicitWidth - 12
                        height: 32
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0
                        to: 1
                        stepSize: 0.005
                        value: PreferencesService.barWidgetBackgroundOpacity
                        onMoved: (v) => PreferencesService.setBarWidgetBackgroundOpacity(v)
                    }

                    Text {
                        id: widgetValueText

                        anchors.verticalCenter: parent.verticalCenter
                        text: root.percentText(PreferencesService.barWidgetBackgroundOpacity)
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    // ---- Typography group (a section here since the tab redesign; it
    // used to be its own category). The card holds a font dropdown:
    // the closed field shows the current family in its own typeface,
    // and the expanding list renders each candidate in itself, so the
    // list previews itself. Only families Qt reports as installed are
    // offered. The pick persists through PreferencesService and binds
    // shell-wide via Theme.fontFamily.
    Text {
        id: typographyTitle

        anchors {
            top: barCard.bottom
            left: parent.left
            topMargin: 20
            leftMargin: 10
        }

        text: "Typography"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: typographyCard

        anchors {
            top: typographyTitle.bottom
            left: parent.left
            right: parent.right
            topMargin: 10
            leftMargin: 10
            rightMargin: 10
        }

        height: typographyContent.implicitHeight + 28
        radius: 10
        color: settingsSurface

        Column {
            id: typographyContent

            property bool fontListOpen: false

            anchors {
                fill: parent
                margins: 14
            }

            spacing: 10

            readonly property var fontChoices: {
                const wanted = ["Inter", "Adwaita Sans", "Google Sans Flex", "SF Pro Display", "Roboto", "Open Sans", "Noto Sans", "Lato", "Montserrat", "Poppins", "Manrope", "Plus Jakarta Sans", "Cantarell", "Red Hat Text", "Ubuntu", "Carlito", "DejaVu Sans"]
                const available = Qt.fontFamilies()
                const installed = wanted.filter(function (f) { return available.indexOf(f) >= 0 })
                if (installed.indexOf(PreferencesService.fontFamily) < 0)
                    installed.unshift(PreferencesService.fontFamily)
                return installed
            }

            // Dropdown: a closed field showing the current family in
            // its own typeface, chevron drawn from two bars. The list
            // expands in place, capped at five rows with its own
            // scroll, so the page stays compact however many families
            // the candidate list grows to.
            Rectangle {
                id: fontField

                width: parent.width
                height: 40
                radius: 8
                color: settingsBackground
                border.width: typographyContent.fontListOpen ? 1 : 0
                border.color: Theme.accent

                Text {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                    }

                    text: PreferencesService.fontFamily
                    color: Theme.text
                    font.family: PreferencesService.fontFamily
                    font.pixelSize: 14
                }

                Item {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 12
                    }

                    width: 12
                    height: 8
                    rotation: typographyContent.fontListOpen ? 180 : 0

                    Behavior on rotation {
                        NumberAnimation { duration: 150 }
                    }

                    Rectangle {
                        width: 8
                        height: 2
                        radius: 1
                        color: Theme.textDim
                        rotation: 45

                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle {
                        width: 8
                        height: 2
                        radius: 1
                        color: Theme.textDim
                        rotation: -45

                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: typographyContent.fontListOpen = !typographyContent.fontListOpen
                }
            }

            Item {
                width: parent.width
                height: typographyContent.fontListOpen ? Math.min(typographyContent.fontChoices.length * 40, 200) : 0
                visible: height > 0
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                Flickable {
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: fontList.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: fontList

                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: typographyContent.fontChoices

                            delegate: Rectangle {
                                required property var modelData

                                width: fontList.width
                                height: 38
                                radius: 8
                                color: choiceArea.containsMouse ? settingsSurfaceRaised : "transparent"
                                border.width: PreferencesService.fontFamily === modelData ? 2 : 0
                                border.color: Theme.accent

                                Text {
                                    anchors {
                                        left: parent.left
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 12
                                    }

                                    text: modelData
                                    color: Theme.text
                                    font.family: modelData
                                    font.pixelSize: 14
                                }

                                MouseArea {
                                    id: choiceArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: {
                                        PreferencesService.setFontFamily(modelData)
                                        typographyContent.fontListOpen = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    }
    }
}

