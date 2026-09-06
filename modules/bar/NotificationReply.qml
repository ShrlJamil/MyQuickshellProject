import QtQuick
import "../../components"

// Generic inline-reply affordance for ONE notification card.
//
// Purely UI + card-local state. Visibility depends only on
// Notification.hasInlineReply — never on appName / appIcon / summary / action
// text / identifier. The actual send is delegated to
// NotificationService.sendInlineReply(); this widget never invokes a
// NotificationAction and never dismisses.
//
// Collapsed state: a compact "Reply" button (same weight as a generic action
// button). Clicking it opens the input + Cancel/Send. Every interactive part
// consumes its own tap (gesturePolicy: ReleaseWithinBounds) so a host card's
// generic body TapHandler never fires while interacting here.
Column {
    id: root

    // Notification entry id + its live Notification object.
    property int notifId: -1
    property var notification: null

    // Card-local state — never lifted into NotificationService.
    property bool replyMode: false

    // Host should suppress popup auto-dismiss while this is true.
    readonly property bool active: root.replyMode || input.activeFocus

    readonly property bool available: !!(root.notification && root.notification.hasInlineReply)

    signal replySent()

    spacing: 6
    visible: root.available
    width: parent ? parent.width : 200

    function _enter() {
        root.replyMode = true
        input.forceActiveFocus()
    }

    function _cancel() {
        root.replyMode = false
        input.text = ""
        input.focus = false
    }

    function _send() {
        const t = input.text
        if (!t || t.length === 0)
            return
        // Re-checks entry/notification/hasInlineReply and wraps the call.
        const ok = NotificationService.sendInlineReply(root.notifId, t)
        if (ok) {
            root.replyMode = false
            input.text = ""
            input.focus = false
            root.replySent()
        }
        // On failure: keep replyMode and keep the typed text.
    }

    // ---- collapsed affordance ----
    Rectangle {
        visible: !root.replyMode
        implicitWidth: replyLabel.implicitWidth + 20
        implicitHeight: 28
        radius: 8
        color: replyAffHover.hovered ? Qt.lighter(Theme.surface, 1.2) : Theme.surface

        Text {
            id: replyLabel
            anchors.centerIn: parent
            text: "Reply"
            color: Theme.text
            font.pixelSize: 11
        }

        HoverHandler { id: replyAffHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: root._enter()
        }
    }

    // ---- input ----
    Rectangle {
        visible: root.replyMode
        width: parent.width
        implicitHeight: 32
        radius: 8
        color: Theme.surface
        border.width: input.activeFocus ? 1 : 0
        border.color: Theme.accent

        // Clicking the field consumes the tap (host card must not close) and
        // gives the input focus.
        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: input.forceActiveFocus()
        }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.pixelSize: 11
            clip: true
            selectByMouse: true
            selectionColor: Theme.accent
            inputMethodHints: Qt.ImhNone

            onAccepted: root._send()
            Keys.onEscapePressed: (event) => {
                root._cancel()
                event.accepted = true
            }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: input.text.length === 0
                text: (root.notification && root.notification.inlineReplyPlaceholder
                       && root.notification.inlineReplyPlaceholder.length > 0)
                    ? root.notification.inlineReplyPlaceholder : "Reply…"
                color: Theme.textMuted
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }

    // ---- Cancel / Send ----
    Row {
        visible: root.replyMode
        width: parent.width
        spacing: 6

        Rectangle {
            id: cancelBtn
            implicitWidth: cancelLabel.implicitWidth + 20
            implicitHeight: 28
            radius: 8
            color: cancelHover.hovered ? Qt.lighter(Theme.surface, 1.2) : Theme.surface

            Text {
                id: cancelLabel
                anchors.centerIn: parent
                text: "Cancel"
                color: Theme.textDim
                font.pixelSize: 11
            }

            HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root._cancel()
            }
        }

        Item {
            width: Math.max(0, parent.width - cancelBtn.width - sendBtn.width - parent.spacing)
            height: 1
        }

        Rectangle {
            id: sendBtn
            implicitWidth: sendLabel.implicitWidth + 20
            implicitHeight: 28
            radius: 8
            readonly property bool enabled: input.text.length > 0
            color: sendBtn.enabled
                ? (sendHover.hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                : Theme.surface

            Text {
                id: sendLabel
                anchors.centerIn: parent
                text: "Send"
                color: sendBtn.enabled ? Theme.background : Theme.textMuted
                font.pixelSize: 11
            }

            HoverHandler { id: sendHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root._send()
            }
        }
    }
}
