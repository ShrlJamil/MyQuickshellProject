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
    //     urgency, critical, stackKey, time }
    // `actions` is the notification's own list<NotificationAction> captured at
    // arrival — the SAME NotificationAction objects, valid while the retained
    // Notification is alive. Used generically: label = action.text, click =
    // action.invoke(). No per-app interpretation.
    // The snapshot fields are a cache, not a copy set in stone: when a sender
    // replaces its notification (freedesktop replaces_id), Quickshell mutates
    // the SAME Notification object in place and does NOT re-emit it, so each
    // entry is kept in sync by _watchEntry()/_syncEntry() below.
    // `stackKey` identifies stack-tag replacement (see _stackKeyOf); "" when
    // the notification carries no stack tag.
    property var list: []
    readonly property int count: root.list.length

    function _entryById(id) {
        for (let i = 0; i < root.list.length; i++) {
            if (root.list[i].id === id)
                return root.list[i]
        }
        return null
    }

    // Stack-tag identity for replace-by-hint, following the dunst / notify-osd
    // convention: a new notification carrying the same stack tag from the same
    // app replaces the previous one instead of stacking next to it. The tag is
    // read from the standard hints: `x-dunst-stack-tag` first, then Canonical's
    // `x-canonical-private-synchronous`. Returns "" when there is no usable
    // tag (the common case — then nothing is ever deduplicated).
    function _stackKeyOf(n) {
        if (!n || !n.hints)
            return ""
        let tag = n.hints["x-dunst-stack-tag"]
        if (tag === undefined || tag === null || tag === "")
            tag = n.hints["x-canonical-private-synchronous"]
        if (tag === undefined || tag === null)
            return ""
        const t = String(tag)
        if (t.length === 0)
            return ""
        return (n.appName || "") + "\n" + t
    }

    // Re-read every snapshot field of an entry from its live Notification and
    // re-publish both arrays (same entry objects, new array identities) so
    // bound UI — history cards and any visible toast — rebuilds with the new
    // content. The entry keeps its position; only its content and time move.
    function _syncEntry(entry) {
        const n = entry.notification
        if (!n)
            return
        entry.actions = n.actions
        entry.appName = n.appName || ""
        entry.appIcon = n.appIcon || ""
        entry.summary = n.summary || ""
        entry.body = n.body || ""
        entry.image = n.image || ""
        entry.urgency = n.urgency
        entry.critical = n.urgency === NotificationUrgency.Critical
        entry.stackKey = root._stackKeyOf(n)
        entry.time = new Date()
        root.list = root.list.slice()
        for (let i = 0; i < root.popups.length; i++) {
            if (root.popups[i].id === entry.id) {
                root.popups = root.popups.slice()
                break
            }
        }
    }

    // Keep an entry's snapshot in sync with its Notification. A freedesktop
    // replace (replaces_id) mutates the object and fires these property
    // signals instead of producing a new notification, so without this hook a
    // replaced notification would keep displaying its first-arrival content
    // forever. Connected once per entry, in the same style as the n.closed
    // hook in the server handler below.
    function _watchEntry(entry) {
        const n = entry.notification
        if (!n)
            return
        const sync = function() { root._syncEntry(entry) }
        n.appNameChanged.connect(sync)
        n.appIconChanged.connect(sync)
        n.summaryChanged.connect(sync)
        n.bodyChanged.connect(sync)
        n.imageChanged.connect(sync)
        n.urgencyChanged.connect(sync)
        n.actionsChanged.connect(sync)
        n.hintsChanged.connect(sync)
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

            // Same id seen again — never duplicate the entry. Quickshell
            // re-emits retained notifications on config reload (keepOnReload),
            // and a replaces_id update is applied to the object in place (see
            // _watchEntry), so an emission for a known id can only be a
            // re-delivery: refresh the existing entry and stop.
            const known = root._entryById(n.id)
            if (known) {
                root._syncEntry(known)
                return
            }

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
                "stackKey": root._stackKeyOf(n),
                "time": new Date()
            }

            // Stack-tag replacement: this notification supersedes any earlier
            // entry from the same app carrying the same stack tag (progress
            // meters, volume-style indicators, this project's own screenshot
            // toasts, ...). Dismiss the superseded entries first — which also
            // closes their Notification objects, so nothing tracked leaks on
            // the server — then add the new one as a normal arrival.
            if (entry.stackKey.length > 0) {
                const snapshot = root.list.slice()
                for (let i = 0; i < snapshot.length; i++) {
                    if (snapshot[i].stackKey === entry.stackKey)
                        root.dismiss(snapshot[i].id)
                }
            }

            const next = root.list.slice()
            next.unshift(entry)
            root.list = next

            // Show a toast unless Do Not Disturb is on. History/count are updated
            // above regardless of DND.
            if (!root.doNotDisturb)
                root._addPopup(entry)

            root._watchEntry(entry)

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
