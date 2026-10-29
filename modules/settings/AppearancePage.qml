import QtQuick
import "../../components"

// The Settings Appearance page: a thin view over PreferencesService,
// which owns validation and persistence (preferences.json). Two
// sections: Surface (material border opacity) and Bar Appearance
// (layout mode, background transparency and opacity, segmented widget
// background opacity). Every control reads and writes the service
// directly - no local state - and values reach the shell live through
// the shell.qml bindings into Theme.
Item {
    id: root

    // Local Settings surface tokens, set by the host (SettingsView) so
    // this page stays monochrome-dark regardless of the global palette.
    property color settingsBackground: "#0A0A0A"
    property color settingsSurface: "#141414"
    property color settingsSurfaceRaised: "#1E1E1E"
    property color settingsSurfaceOverlay: "#2A2A2A"

    function percentText(v) {
        const p = Math.round(v * 1000) / 10
        return (Number.isInteger(p) ? String(p) : p.toFixed(1)) + "%"
    }

    // Derived from the service only (no local state): the Bar section
    // is at defaults when all four preferences match theirs.
    readonly property bool barIsDefault: PreferencesService.barLayoutMode === PreferencesService.defaultBarLayoutMode
        && PreferencesService.barTransparency === PreferencesService.defaultBarTransparency
        && PreferencesService.barBackgroundOpacity === PreferencesService.defaultBarBackgroundOpacity
        && PreferencesService.barWidgetBackgroundOpacity === PreferencesService.defaultBarWidgetBackgroundOpacity

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
        border.color: btn.accent ? "transparent" : Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)

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
        color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
    }

    // ---- scrollable groups (header and footer stay pinned) -------------------
    Flickable {
        id: pageScroll

        anchors {
            top: divider.bottom
            left: parent.left
            right: parent.right
            bottom: footerDivider.top
        }

        contentWidth: width
        contentHeight: scrollContent.height
        clip: true

    Item {
        id: scrollContent

        width: pageScroll.width
        height: barResetRow.y + barResetRow.height + 14

    // ---- Surface group --------------------------------------------------------
    Text {
        id: surfaceTitle

        anchors {
            top: parent.top
            left: parent.left
            topMargin: 16
            leftMargin: 10
        }

        text: "Surface"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: surfaceCard

        anchors {
            top: surfaceTitle.bottom
            left: parent.left
            right: parent.right
            topMargin: 10
            leftMargin: 10
            rightMargin: 10
        }

        height: surfaceContent.implicitHeight + 28
        radius: 10
        color: settingsSurface

        Column {
            id: surfaceContent

            anchors {
                fill: parent
                margins: 14
            }

            spacing: 10

            Row {
                width: parent.width
                spacing: 12

                Column {
                    width: parent.width - valueText.implicitWidth - 12
                    spacing: 3

                    Text {
                        width: parent.width
                        text: "Material border opacity"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: "Strength of the outline borders on shell surfaces and panels."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                Text {
                    id: valueText

                    anchors.verticalCenter: parent.verticalCenter
                    text: root.percentText(PreferencesService.materialBorderOpacity)
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            PrefSlider {
                width: parent.width
                from: PreferencesService.minMaterialBorderOpacity
                to: PreferencesService.maxMaterialBorderOpacity
                value: PreferencesService.materialBorderOpacity
                onMoved: (v) => PreferencesService.setMaterialBorderOpacity(v)
            }
        }
    }

    // ---- Bar Appearance group ---------------------------------------------------
    Text {
        id: barTitle

        anchors {
            top: surfaceCard.bottom
            left: parent.left
            topMargin: 20
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

            // Layout mode: three mutually exclusive PageButtons, the
            // accent one is the service's current mode.
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
                    spacing: 8

                    PageButton {
                        label: "Default"
                        accent: PreferencesService.barLayoutMode === "default"
                        onActivated: PreferencesService.setBarLayoutMode("default")
                    }

                    PageButton {
                        label: "Float"
                        accent: PreferencesService.barLayoutMode === "float"
                        onActivated: PreferencesService.setBarLayoutMode("float")
                    }

                    PageButton {
                        label: "Segmented"
                        accent: PreferencesService.barLayoutMode === "segmented"
                        onActivated: PreferencesService.setBarLayoutMode("segmented")
                    }
                }

                Text {
                    width: parent.width
                    text: PreferencesService.barLayoutMode === "float"
                        ? "Inset from the top and side edges of the screen, with rounded corners."
                        : PreferencesService.barLayoutMode === "segmented"
                            ? "Every widget gets its own background instead of one bar background."
                            : "Attached to the top edge of the screen, the way the bar has always been."
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            // Bar background: the opacity slider keeps its stored value
            // while transparency is off; it only takes effect (Stage 2
            // binding) once transparency is on.
            Item {
                width: parent.width
                height: 22

                Text {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }

                    text: "Enable transparency"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                PrefToggle {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }

                    checked: PreferencesService.barTransparency
                    onToggled: PreferencesService.setBarTransparency(!PreferencesService.barTransparency)
                }
            }

            Column {
                width: parent.width
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 12
                    opacity: PreferencesService.barTransparency ? 1 : 0.45

                    Column {
                        width: parent.width - bgValueText.implicitWidth - 12
                        spacing: 3

                        Text {
                            width: parent.width
                            text: "Background opacity"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: "Opacity of the bar background while transparency is on."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
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

                PrefSlider {
                    width: parent.width
                    from: 0
                    to: 1
                    stepSize: 0.005
                    value: PreferencesService.barBackgroundOpacity
                    enabled: PreferencesService.barTransparency
                    onMoved: (v) => PreferencesService.setBarBackgroundOpacity(v)
                }
            }

            // Segmented widget backgrounds.
            Column {
                width: parent.width
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 12

                    Column {
                        width: parent.width - widgetValueText.implicitWidth - 12
                        spacing: 3

                        Text {
                            width: parent.width
                            text: "Widget background opacity"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: "Opacity of the individual widget backgrounds in Segmented mode. The main bar background is not affected."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
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

                PrefSlider {
                    width: parent.width
                    from: 0
                    to: 1
                    stepSize: 0.005
                    value: PreferencesService.barWidgetBackgroundOpacity
                    onMoved: (v) => PreferencesService.setBarWidgetBackgroundOpacity(v)
                }
            }
        }
    }

    // Bar reset row: scoped to the Bar section only, mirroring the
    // pinned footer's status + Reset pattern for Appearance.
    Item {
        id: barResetRow

        anchors {
            top: barCard.bottom
            left: parent.left
            right: parent.right
            topMargin: 10
            leftMargin: 10
            rightMargin: 10
        }

        height: 30

        Text {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }

            text: root.barIsDefault ? "Default values" : "Custom values"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        PageButton {
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }

            label: "Reset bar"
            disabled: root.barIsDefault
            onActivated: PreferencesService.resetBar()
        }
    }

    }
    }

    // ---- footer (pinned) -------------------------------------------------------
    Rectangle {
        id: footerDivider

        anchors {
            bottom: footer.top
            left: parent.left
            right: parent.right
            bottomMargin: 10
            leftMargin: 10
            rightMargin: 10
        }

        height: 1
        color: Qt.rgba(1, 1, 1, Theme.materialBorderOpacity)
    }

    Item {
        id: footer

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 10
            rightMargin: 10
            bottomMargin: 10
        }

        height: 30

        Text {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }

            text: PreferencesService.materialBorderOpacity === PreferencesService.defaultMaterialBorderOpacity
                ? "Default value" : "Custom value"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        PageButton {
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }

            label: "Reset"
            disabled: PreferencesService.materialBorderOpacity === PreferencesService.defaultMaterialBorderOpacity
            onActivated: PreferencesService.resetAppearance()
        }
    }
}
