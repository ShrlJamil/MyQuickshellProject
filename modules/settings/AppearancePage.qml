import QtQuick
import "../../components"

// The Settings Appearance page (phase 1): one real preference end to
// end - the material border opacity. The page is a thin view over
// PreferencesService, which owns validation and persistence
// (preferences.json); the value reaches every shell surface live
// through the shell.qml binding into Theme.materialBorderOpacity.
// Nothing else about the theme is adjustable here yet, and the slider
// is labelled for exactly what it controls: border strength, not panel
// transparency.
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
        signal moved(real value)

        implicitHeight: 26

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

    // ---- Surface group --------------------------------------------------------
    Text {
        id: surfaceTitle

        anchors {
            top: divider.bottom
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
