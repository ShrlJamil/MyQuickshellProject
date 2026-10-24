import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../components"

// Standalone toast stack (instances exist only on bar screens — see shell.qml).
// Shows NotificationService.popups on the bar monitor regardless of which
// monitor is currently focused, newest on top. Each toast owns its lifecycle
// (auto-dismiss, hover-pause, close button). Removing a toast never touches the
// Notification Center history — that stays in NotificationService.list.
PanelWindow {
    id: root

    required property var modelData

    screen: modelData.screen

    // Always render the toast stack on this (bar) screen, regardless of which
    // monitor Hyprland currently has focused. Instances only exist on bar
    // screens (shell.qml Variants), so in the normal setup exactly one stack
    // renders; focus moving to another monitor never hides incoming toasts.
    readonly property var items: NotificationService.popups

    visible: root.items.length > 0

    // Automatic toasts must be keyboard-focus NEUTRAL — a popup that appears
    // while the user is typing in another app must never steal focus. The layer
    // surface therefore requests NO keyboard focus by default, and only asks for
    // OnDemand focus while an inline reply is actively in use (a real text input
    // that needs keystrokes). It drops back to None the instant the reply ends.
    // Pointer interaction (hover, close, action, reply taps) never depends on
    // keyboard focus, so it keeps working in both states.
    property int replyFocusHolders: 0
    readonly property bool wantKeyboard: root.replyFocusHolders > 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: root.wantKeyboard
        ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.None
    focusable: root.wantKeyboard

    anchors {
        top: true
        right: true
    }

    margins {
        top: 48
        right: 12
    }

    // Window tracks the content so there is no large empty area; the toasts
    // themselves are the only opaque surfaces.
    implicitWidth: 380
    implicitHeight: Math.max(1, stack.implicitHeight)
    color: "transparent"

    Column {
        id: stack

        anchors.right: parent.right
        width: 372
        spacing: 8
        clip: true

        Repeater {
            model: root.items

            delegate: Item {
                id: slot

                required property var modelData

                width: stack.width
                height: slot.closing ? 0 : card.implicitHeight
                clip: true

                property bool entered: false
                property bool closing: false
                // Arms the height Behavior ONLY for the closing collapse. Reply
                // expand/collapse changes card.implicitHeight while the toast is
                // alive; that must reach slot.height instantly (one PanelWindow
                // geometry update), not through the 160ms animation.
                property bool closeAnimating: false

                // Generic actions the sender attached, as {action, index} pairs
                // with the original index preserved. Empty-text actions dropped.
                readonly property var actionItems: {
                    const src = slot.modelData.actions
                    if (!src)
                        return []
                    const out = []
                    for (let i = 0; i < src.length; i++) {
                        const a = src[i]
                        if (a && a.text && a.text.length > 0)
                            out.push({ "action": a, "index": i })
                    }
                    return out
                }

                // Inline-reply availability/mode, mirrored on the slot so the
                // actions row and the auto-dismiss timer can consult them
                // WITHOUT instantiating the reply editor (see replyLoader).
                // Availability is a pure function of the notification; mode
                // and active simply read through the loader once it exists.
                readonly property bool replyAvailable: !!(slot.modelData.notification
                    && slot.modelData.notification.hasInlineReply)
                readonly property bool replyModeOn: !!(replyLoader.item && replyLoader.item.replyMode)
                readonly property bool replyActive: !!(replyLoader.item && replyLoader.item.active)

                // Build the reply editor on first use, then flip it open.
                function openReply() {
                    replyLoader.active = true
                    if (replyLoader.item)
                        replyLoader.item.replyMode = true
                }

                function beginClose() {
                    if (slot.closing)
                        return
                    // Arm the Behavior before triggering height -> 0 so the
                    // collapse animates regardless of binding evaluation order.
                    slot.closeAnimating = true
                    slot.closing = true
                    closeTimer.start()
                }

                Behavior on height {
                    enabled: slot.closeAnimating
                    NumberAnimation { duration: 160; easing.type: Easing.InCubic }
                }

                // Fires just after the exit animation; hands removal back to the
                // single source of truth.
                Timer {
                    id: closeTimer
                    interval: 180
                    onTriggered: NotificationService.dismissPopup(slot.modelData.id)
                }

                // Normal toasts auto-dismiss after 5s; critical ones stay until
                // closed by the user or the sender. Hover pauses the timer, and
                // so does an active inline-reply interaction (reply mode / input
                // focus) so a toast never vanishes mid-typing.
                Timer {
                    id: autoTimer
                    interval: 5000
                    running: !slot.closing
                        && !slot.modelData.critical
                        && !hoverHandler.hovered
                        && !slot.replyActive
                    onTriggered: slot.beginClose()
                }

                Rectangle {
                    id: card

                    width: parent.width
                    implicitHeight: layout.implicitHeight + 24
                    radius: 16
                    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, Theme.moduleSurfaceOpacity)
                    border.width: 1
                    border.color: Theme.surfaceHover

                    x: (slot.entered && !slot.closing) ? 0 : (slot.width + 24)
                    opacity: (slot.entered && !slot.closing) ? 1 : 0

                    Behavior on x {
                        NumberAnimation {
                            duration: slot.closing ? 160 : 200
                            easing.type: slot.closing ? Easing.InCubic : Easing.OutCubic
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: slot.closing ? 150 : 190
                            easing.type: slot.closing ? Easing.InCubic : Easing.OutCubic
                        }
                    }

                    HoverHandler {
                        id: hoverHandler
                    }

                    // Click anywhere on the toast dismisses it (no app launch,
                    // no actions — Phase 1).
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: slot.beginClose()
                    }

                    // Shared glass highlight (see ControlTile): inset by the
                    // 1px border so the peak never paints over the border
                    // stroke; radius reduced to match. Falloff shaped by
                    // stops. Below content.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 15
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: Qt.rgba(1, 1, 1, Theme.materialHighlightOpacity)
                            }
                            GradientStop {
                                position: 0.4
                                color: "transparent"
                            }
                            GradientStop {
                                position: 1
                                color: "transparent"
                            }
                        }
                    }

                    // Close button.
                    Rectangle {
                        id: closeBtn

                        anchors {
                            right: parent.right
                            top: parent.top
                            margins: 8
                        }
                        width: 20
                        height: 20
                        radius: 10
                        color: closeHover.hovered ? Theme.surfaceHover : "transparent"
                        z: 2

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: closeHover.hovered ? Theme.text : Theme.textMuted
                            font.pixelSize: 11
                        }

                        HoverHandler {
                            id: closeHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: slot.beginClose()
                        }
                    }

                    Column {
                        id: layout

                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 12
                            rightMargin: 12
                        }
                        spacing: 6

                        // app name + time
                        Row {
                            width: parent.width - 24
                            spacing: 6

                            Text {
                                text: slot.modelData.appName.length > 0
                                    ? slot.modelData.appName : "Notification"
                                color: Theme.textDim
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, parent.width - timeLabel.width - 6)
                            }

                            Text {
                                id: timeLabel
                                text: Qt.formatDateTime(slot.modelData.time, "hh:mm")
                                color: Theme.textMuted
                                font.pixelSize: 10
                            }
                        }

                        // icon + summary/body
                        Row {
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                id: iconBox
                                width: 36
                                height: 36
                                radius: 8
                                color: Theme.surface

                                IconImage {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    asynchronous: true
                                    source: {
                                        const img = slot.modelData.image
                                        if (img && img.length > 0)
                                            return img.charAt(0) === "/" ? "file://" + img : img
                                        const ic = slot.modelData.appIcon
                                        if (ic && ic.length > 0)
                                            return ic.charAt(0) === "/" ? "file://" + ic
                                                : Quickshell.iconPath(ic, "dialog-information")
                                        return Quickshell.iconPath(
                                            slot.modelData.appName.toLowerCase(),
                                            "dialog-information")
                                    }
                                }
                            }

                            Column {
                                width: parent.width - iconBox.width - 10
                                spacing: 2

                                Text {
                                    width: parent.width
                                    visible: slot.modelData.summary.length > 0
                                    text: slot.modelData.summary
                                    color: Theme.text
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }

                                Text {
                                    width: parent.width
                                    visible: slot.modelData.body.length > 0
                                    text: slot.modelData.body
                                    color: Theme.textDim
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }
                            }
                        }

                        // Generic actions — text only, no card/border/fill. Hover
                        // only recolours the label. Still consumes its own tap so
                        // the card body handler does not also fire, and still runs
                        // the existing invokeAction(...).
                        Flow {
                            width: parent.width
                            spacing: 16
                            visible: slot.actionItems.length > 0
                                || (slot.replyAvailable && !slot.replyModeOn)

                            // Reply as a generic action: identical metrics/style
                            // to the delegates after this; opens the input below.
                            Text {
                                id: replyActLabel

                                visible: slot.replyAvailable && !slot.replyModeOn
                                width: replyActLabel.implicitWidth
                                height: 28
                                verticalAlignment: Text.AlignVCenter
                                text: "Reply"
                                color: replyActHover.hovered ? Theme.accent : Theme.text
                                font.pixelSize: 11
                                elide: Text.ElideRight

                                HoverHandler {
                                    id: replyActHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    gesturePolicy: TapHandler.ReleaseWithinBounds
                                    onTapped: slot.openReply()
                                }
                            }

                            Repeater {
                                model: slot.actionItems

                                delegate: Text {
                                    id: actLabel

                                    required property var modelData

                                    width: Math.min(implicitWidth, card.width - 28)
                                    height: 28
                                    verticalAlignment: Text.AlignVCenter
                                    text: actLabel.modelData.action.text
                                    color: actHover.hovered ? Theme.accent : Theme.text
                                    font.pixelSize: 11
                                    elide: Text.ElideRight

                                    HoverHandler {
                                        id: actHover
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                    TapHandler {
                                        gesturePolicy: TapHandler.ReleaseWithinBounds
                                        onTapped: NotificationService.invokeAction(
                                            slot.modelData.id, actLabel.modelData.index)
                                    }
                                }
                            }
                        }

                        // Generic inline-reply affordance — shown only when the
                        // notification advertises hasInlineReply. The collapsed
                        // button is hidden here (showAffordance: false); Reply
                        // is the first item of the actions Flow above, same
                        // style as generic actions. The expanded input form
                        // lives here, below the whole action row.
                        //
                        // Loaded lazily: the editor's object tree (TextInput,
                        // buttons, handlers) is the heaviest part of this
                        // delegate and most toasts are never replied to, so it
                        // is built only when the user first opens the reply
                        // (slot.openReply) and then kept for the toast's
                        // remaining life — replyMode and the keyboard-focus
                        // bookkeeping inside keep exactly one owner.
                        Loader {
                            id: replyLoader
                            width: parent.width
                            active: false
                            visible: slot.replyAvailable

                            sourceComponent: NotificationReply {
                                id: replyItem

                                showAffordance: false
                                notifId: slot.modelData.id
                                notification: slot.modelData.notification

                                // Raise the window's keyboard-focus demand only
                                // while this reply is actually in use. Idempotent
                                // via _counted so a toast torn down mid-reply
                                // still balances the count. No state leaves
                                // this card.
                                property bool _counted: false
                                onActiveChanged: {
                                    if (replyItem.active === replyItem._counted)
                                        return
                                    replyItem._counted = replyItem.active
                                    root.replyFocusHolders += replyItem.active ? 1 : -1
                                }
                                Component.onDestruction: {
                                    if (replyItem._counted)
                                        root.replyFocusHolders -= 1
                                }
                            }
                        }
                    }
                }

                Component.onCompleted: slot.entered = true
            }
        }
    }
}
