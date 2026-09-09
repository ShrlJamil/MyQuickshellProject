pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Single source of truth for the Notification Center:
//  - in-memory notification history (freedesktop notifications via Quickshell's
//    NotificationServer),
//  - unread/notification count for the Date & Time badge,
//  - Do Not Disturb state (shell-side suppression flag),
//  - which screen the Notification Center panel is currently open on.
//
// No persistence, no grouping, no actions — deliberately minimal for now.
Item {
    id: root

    // ---- Notification Center open state -------------------------------------
    // The ShellScreen the panel is open on, or null when closed. Shared by every
    // per-screen DateTimeWidget and NotificationCenter instance.
    property var centerScreen: null

    function toggleCenter(screen) {
        root.centerScreen = (root.centerScreen === screen) ? null : screen
    }
    function closeCenter() {
        root.centerScreen = null
    }

    // ---- Do Not Disturb --------------------------------------------------------
    // Shell-side flag. Incoming notifications are still recorded to history; this
    // only exists for future popup/attention code to honour. Not persisted.
    property bool doNotDisturb: false
    function toggleDnd() {
        root.doNotDisturb = !root.doNotDisturb
    }

    // ---- History ------------------------------------------------------------
    // Newest first. Each entry:
    //   { id, notification, actions, appName, appIcon, summary, body, image,
    //     urgency, critical, time }
    // `actions` is the notification's own list<NotificationAction> captured at
    // arrival — the SAME NotificationAction objects, valid while the retained
    // Notification is alive. Used generically: label = action.text, click =
    // action.invoke(). No per-app interpretation.
    property var list: []
    readonly property int count: root.list.length

    function _entryById(id) {
        for (let i = 0; i < root.list.length; i++) {
            if (root.list[i].id === id)
                return root.list[i]
        }
        return null
    }

    // Invoke a notification action generically. Never dismisses: whether the
    // notification closes afterwards is decided by Notification.resident and the
    // sender (handled by the n.closed hook below).
    function invokeAction(id, actionIndex) {
        const entry = root._entryById(id)
        if (!entry || !entry.actions)
            return
        if (actionIndex < 0 || actionIndex >= entry.actions.length)
            return
        const a = entry.actions[actionIndex]
        if (a && a.invoke) {
            try {
                a.invoke()
            } catch (e) {}
        }
    }

    // Send a generic inline reply. Only valid when the (still-alive) Notification
    // advertises Notification.hasInlineReply. Never dismisses — the sender
    // decides whether the notification closes afterwards (n.closed hook handles
    // removal). Returns true only if the reply was actually handed off.
    function sendInlineReply(id, text) {
        if (!text || text.length === 0)
            return false
        const entry = root._entryById(id)
        if (!entry)
            return false
        const n = entry.notification
        if (!n || !n.hasInlineReply)
            return false
        try {
            n.sendInlineReply(text)
            return true
        } catch (e) {
            return false
        }
    }

    // ---- Active popups / toasts -------------------------------------------
    // Subset of history currently shown as a toast, newest first. Entries are
    // the SAME objects as in `list`. Removing an entry here never touches
    // history, count, or the notification object — a toast that times out or is
    // closed stays in the Notification Center.
    property var popups: []
    readonly property int maxPopups: 4

    function _addPopup(entry) {
        const next = root.popups.slice()
        next.unshift(entry)
        // Only the newest maxPopups stay on screen; the rest are still in history.
        if (next.length > root.maxPopups)
            next.length = root.maxPopups
        root.popups = next
    }

    function _removePopup(id) {
        const next = root.popups.filter(e => e.id !== id)
        if (next.length !== root.popups.length)
            root.popups = next
    }

    // Called by a toast itself (close button / auto-dismiss / body click).
    // History is untouched.
    function dismissPopup(id) {
        root._removePopup(id)
    }

    NotificationServer {
        id: server

        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: false
        inlineReplySupported: true

        onNotification: (n) => {
            // Keep the object alive past its popup timeout so it stays in the
            // center until the user (or the sender) clears it. This also keeps
            // its NotificationAction children alive.
            n.tracked = true

            const entry = {
                "id": n.id,
                "notification": n,
                "actions": n.actions,
                "appName": n.appName || "",
                "appIcon": n.appIcon || "",
                "summary": n.summary || "",
                "body": n.body || "",
                "image": n.image || "",
                "urgency": n.urgency,
                "critical": n.urgency === NotificationUrgency.Critical,
                "time": new Date()
            }

            const next = root.list.slice()
            next.unshift(entry)
            root.list = next

            // Show a toast unless Do Not Disturb is on. History/count are updated
            // above regardless of DND.
            if (!root.doNotDisturb)
                root._addPopup(entry)

            // If the sender closes/expires it elsewhere, drop it from both.
            n.closed.connect(function() {
                root._removePopup(n.id)
                root._remove(n.id)
            })
        }
    }

    function _remove(id) {
        const next = root.list.filter(e => e.id !== id)
        if (next.length !== root.list.length)
            root.list = next
    }

    // Dismiss one notification (also tells the sender it's gone). Removes it from
    // history AND from any visible toast.
    function dismiss(id) {
        for (let i = 0; i < root.list.length; i++) {
            if (root.list[i].id === id) {
                const n = root.list[i].notification
                if (n) {
                    try {
                        n.dismiss()
                    } catch (e) {}
                }
                break
            }
        }
        root._removePopup(id)
        root._remove(id)
    }

    // Clear the whole center (and every visible toast).
    function clearAll() {
        const snapshot = root.list.slice()
        root.list = []
        root.popups = []
        for (let i = 0; i < snapshot.length; i++) {
            const n = snapshot[i].notification
            if (n) {
                try {
                    n.dismiss()
                } catch (e) {}
            }
        }
    }
}
