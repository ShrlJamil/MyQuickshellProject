import QtQuick
import Quickshell
import Quickshell.Wayland

// The desktop widget strip: calendar + weather cards side by side on
// the bottom layer-shell layer, shown on the internal panel only
// (wired in shell.qml). Everything inside is static between data
// updates - no animations, no fast timers - so the strip costs no
// GPU work in practice.
//
// This window never changes size: it is exactly the strip (412x200).
// The location picker lives in its own PopupWindow anchored below
// the weather card, so opening, resizing or unloading the picker
// reconfigures only the popup surface and can never make the cards
// flicker (they did when the picker shared this window: its width
// and content-driven height resized the whole surface on every
// change). The picker itself stays lazy: a Loader keeps
// LocationPicker unloaded until the first click, and unloads it
// again on close.
//
// Input: the strip mask covers only the weather card, so the
// calendar and the rest of the desktop stay click-through;
// clicking the weather card toggles the picker popup. The popup
// grabs focus while open, so clicking anywhere else dismisses it.
PanelWindow {
    id: root

    required property var modelData

    readonly property int pickerX: calCard.width + strip.spacing
    readonly property int pickerY: strip.implicitHeight + 8

    screen: modelData.screen

    anchors {
        top: true
        left: true
    }

    margins {
        top: 54
        left: 18
    }

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region { item: weatherCard }

    color: "transparent"

    implicitWidth: strip.implicitWidth
    implicitHeight: strip.implicitHeight

    Row {
        id: strip

        spacing: 12

        CalendarWidget { id: calCard }

        WeatherWidget {
            id: weatherCard

            height: calCard.height

            onActivated: pickerPopup.visible = !pickerPopup.visible
        }
    }

    PopupWindow {
        id: pickerPopup

        anchor {
            window: root
            rect.x: root.pickerX
            rect.y: root.pickerY
            rect.width: 1
            rect.height: 1
        }

        grabFocus: true
        visible: false
        color: "transparent"

        width: pickerLoader.item ? pickerLoader.item.width : 300
        height: pickerLoader.item ? pickerLoader.item.height : 120

        Loader {
            id: pickerLoader

            active: pickerPopup.visible
            asynchronous: true
            source: "LocationPicker.qml"
        }

        Connections {
            target: pickerLoader.item

            function onCloseRequested() {
                pickerPopup.visible = false
            }
        }
    }
}
