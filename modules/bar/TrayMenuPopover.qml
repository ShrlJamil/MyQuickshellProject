import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "../../components"

// Custom system-tray context menu, rendered by the shell in the panel
// palette instead of the platform menu that SystemTrayItem.display()
// would show. The menu data is the item's own DBusMenu, read live
// through QsMenuOpener: entries carry text, icon, enabled, separator,
// button type and check state, and activate via their triggered()
// signal - the same mechanism the platform renderer uses.
//
// Submenus drill in (the list is replaced, with a back row on top)
// instead of flying out, so the popover stays a single anchored window.
// Window/dismiss behaviour mirrors MediaPlayerPopover: focus grab
// clears on outside click, Escape closes, close fades out.
PanelWindow {
    id: root

    // The tray item's menu handle (SystemTrayItem.menu).
    property var menuHandle: null
    // X centre of the clicked tray icon, in bar-content coordinates.
    property real anchorCenter: 0
    property bool open: false
    property bool closing: false

    signal dismissRequested()

    // Navigation stack of handles; the top is the level on display. The
    // root handle is the item's menu; pushed entries are submenus (a
    // QsMenuEntry is itself a handle).
    property var _stack: []
    readonly property var _currentHandle: root._stack.length > 0 ? root._stack[root._stack.length - 1] : null

    QsMenuOpener {
        id: opener

        menu: root._currentHandle
    }

    readonly property real screenWidth: root.screen ? root.screen.width : 1920

    visible: root.open || root.closing

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        left: true
    }

    margins {
        // 44 = strip (36) + gap (8) from the screen top; float adds the
        // strip's top inset so the gap below the strip stays 8.
        top: 44 + (Theme.barFloating ? Theme.barFloatInsetTop : 0)
        // anchorCenter arrives in bar-content coordinates; float insets
        // the content, so shift into screen coordinates by the inset.
        left: Math.max(8, Math.min((root.anchorCenter + (Theme.barFloating ? Theme.barFloatInsetX : 0)) - root.implicitWidth / 2,
            root.screenWidth - root.implicitWidth - 8))
    }

    implicitWidth: card.width + 16
    implicitHeight: card.height + 16

    color: "transparent"

    onOpenChanged: {
        if (root.open) {
            root.closing = false
            hideTimer.stop()
            root._reset()
            card.forceActiveFocus()
        } else {
            root.closing = true
            hideTimer.restart()
        }
    }

    onMenuHandleChanged: if (root.open) root._reset()

    function _reset() {
        root._stack = root.menuHandle ? [root.menuHandle] : []
    }

    function _activate(entry) {
        if (!entry.enabled)
            return
        if (entry.hasChildren) {
            root._stack = root._stack.concat([entry])
            return
        }
        entry.triggered()
        root.dismissRequested()
    }

    Timer {
        id: hideTimer

        interval: 170
        onTriggered: root.closing = false
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: {
            if (!root.open)
                return
            root.dismissRequested()
        }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: 248
        height: flick.height + 12
        radius: Theme.cornerRadius
        color: Qt.rgba(Theme.panelBackground.r, Theme.panelBackground.g, Theme.panelBackground.b, Theme.moduleSurfaceOpacity)
        border.width: 1
        border.color: Theme.surfaceHover

        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.open ? 110 : 140
                easing.type: Easing.OutCubic
            }
        }

        transform: Translate {
            x: root.open ? 0 : -6
            y: root.open ? 0 : -6

            Behavior on x {
                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
            }
        }

        Shortcut {
            sequence: "Escape"
            enabled: root.open
            onActivated: root.dismissRequested()
        }

        Flickable {
            id: flick

            anchors.centerIn: parent
            width: card.width - 12
            height: Math.min(428, col.implicitHeight)
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true

            Column {
                id: col

                width: flick.width
                spacing: 1

                // Back row, visible inside a submenu.
                Rectangle {
                    visible: root._stack.length > 1
                    width: col.width
                    height: 30
                    radius: 8
                    color: backHover.hovered ? Theme.panelSurface : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: "\u2039"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root._currentHandle && root._currentHandle.text ? root._currentHandle.text : ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }

                    HoverHandler { id: backHover }
                    TapHandler {
                        onTapped: root._stack = root._stack.slice(0, root._stack.length - 1)
                    }
                }

                Repeater {
                    model: opener.children

                    delegate: Item {
                        id: entryRow

                        required property var modelData
                        readonly property var entry: modelData

                        width: col.width
                        height: entry.isSeparator ? 9 : 32

                        // Separator line.
                        Rectangle {
                            visible: entryRow.entry.isSeparator
                            anchors.centerIn: parent
                            width: parent.width - 16
                            height: 1
                            color: Theme.surfaceHover
                        }

                        // Entry row.
                        Rectangle {
                            visible: !entryRow.entry.isSeparator
                            anchors.fill: parent
                            radius: 8
                            color: rowHover.hovered && entryRow.entry.enabled ? Theme.panelSurface : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                // Check / radio mark slot.
                                Item {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16

                                    Text {
                                        anchors.centerIn: parent
                                        visible: entryRow.entry.buttonType === QsMenuButtonType.CheckBox
                                            && entryRow.entry.checkState === Qt.Checked
                                        text: "\u2713"
                                        color: Theme.accent
                                        font.pixelSize: 13
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: entryRow.entry.buttonType === QsMenuButtonType.CheckBox
                                            && entryRow.entry.checkState === Qt.PartiallyChecked
                                        width: 8
                                        height: 2
                                        color: Theme.accent
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: entryRow.entry.buttonType === QsMenuButtonType.RadioButton
                                            && entryRow.entry.checkState === Qt.Checked
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: Theme.accent
                                    }
                                }

                                IconImage {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    visible: !!entryRow.entry.icon
                                    source: entryRow.entry.icon
                                    asynchronous: true
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: entryRow.entry.text
                                    color: entryRow.entry.enabled ? Theme.text : Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    visible: entryRow.entry.hasChildren
                                    text: "\u203a"
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                }
                            }

                            HoverHandler { id: rowHover }
                            TapHandler {
                                onTapped: root._activate(entryRow.entry)
                            }
                        }
                    }
                }

                // Placeholder while the app has not delivered entries yet
                // (DBusMenu children can arrive asynchronously).
                Text {
                    visible: opener.children.count === 0
                    width: col.width
                    height: 30
                    text: "Loading\u2026"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
