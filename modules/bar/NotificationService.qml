pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Single source of truth for the Notification Center:
//  - in-memory notification history (freedesktop notifications via Quickshell's
//    NotificationServer),
//  - unread/notification count for the Date & Time badge,
//  - Do Not Disturb state (shell-side suppression flag),
//  - which screen the Notification Center panel is currently open on,
//  - the incremental models (historyModel / popupModel) the UI binds to.
//
// Deliberately absent: persistence across restarts and per-app grouping.
// Actions and inline replies ARE supported generically (see invokeAction /
// sendInlineReply) — the old "no actions" note was stale.
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

    // ---- Do Not Disturb ------------------------------------------------------
    // Shell-side flag, session-only (not persisted). While on:
    //   - new arrivals are recorded to history but raise no toast — EXCEPT
    //     critical ones, which always show (the usual desktop convention);
    //   - toasts already on screen are hidden immediately (popup-level
    //     removal only; history and the senders are untouched).
    // Turning it back off never resurrects toasts that were suppressed.
    property bool doNotDisturb: false
    function toggleDnd() {
        root.doNotDisturb = !root.doNotDisturb
    }

    onDoNotDisturbChanged: {
        if (root.doNotDisturb)
            root.popups = []
    }

    // ---- History ------------------------------------------------------------
    // Newest first. Each entry is deliberately minimal:
    //   { id, notification, stackKey, time }
    // Display fields (appName, summary, body, image, actions, urgency, ...)
    // are NOT copied here: delegates bind them directly to the live
    // Notification object, which Quickshell mutates in place on a freedesktop
    // replace (replaces_id) and never re-emits. That is what makes a replaced
    // notification update on screen with no service-side sync code at all.
    // `time` is the first-arrival time and never moves on replace.
    // `stackKey` identifies stack-tag replacement (see _stackKeyOf); "" when
    // the notification carries no stack tag.
    property var list: []
    readonly property int count: root.list.length

    // Retention cap for the history. Without it, every notification ever
    // received is retained forever — its entry here plus its Notification
    // object (and any image payload) on the server — so a long-running shell
    // grows without bound. Arrivals beyond the cap evict the OLDEST entries;
    // see _pruneHistory().
    readonly property int maxHistory: 100

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

    // Toast auto-dismiss policy for one live Notification, in milliseconds;
    // 0 = never auto-dismiss. Public so delegates can evaluate it in a
    // binding (which then tracks urgency/expireTimeout for free). This is a
    // DISPLAY lifetime only — the history entry itself stays until the user
    // or the sender clears it, whatever the sender asked for.
    //   - critical: never (same as the original fixed behaviour);
    //   - the sender's expireTimeout, honoured when positive. NOTE:
    //     Quickshell passes the freedesktop value through raw, i.e. in
    //     MILLISECONDS, even though its header doc says seconds (verified
    //     against the 0.3.2 server: expire_timeout 2000 arrives as 2000);
    //   - expireTimeout exactly 0: the sender asked for "never expire";
    //   - expireTimeout negative (-1): the sender defers to the server, so
    //     per-urgency defaults apply — Low shorter than Normal.
    function autoDismissMsFor(n) {
        if (!n)
            return 5000
        if (n.urgency === NotificationUrgency.Critical)
            return 0
        if (n.expireTimeout > 0)
            return Math.round(n.expireTimeout)
        if (n.expireTimeout === 0)
            return 0
        return n.urgency === NotificationUrgency.Low ? 3000 : 5000
    }

    // Evict the oldest entries (tail of the newest-first list) until the
    // history fits maxHistory. Runs after each insertion — the only place the
    // list grows. The kept/evicted arrays are swapped in BEFORE dismissing
    // anything, mirroring clearAll(), so the evicted notifications' n.closed
    // hooks find nothing left to mutate. Evicted entries are dismissed
    // properly — not just dropped from the array — so the server releases
    // their Notification objects (and image payloads) as well.
    function _pruneHistory() {
        if (root.list.length <= root.maxHistory)
            return
        const evicted = root.list.slice(root.maxHistory)
        root.list = root.list.slice(0, root.maxHistory)
        for (let i = 0; i < evicted.length; i++) {
            root._removePopup(evicted[i].id)
            const n = evicted[i].notification
            if (n && n.dismiss) {
                try {
                    n.dismiss()
                } catch (e) {}
            }
        }
    }

    // Invoke a notification action generically. Never dismisses: whether the
    // notification closes afterwards is decided by Notification.resident and the
    // sender (handled by the n.closed hook below).
    function invokeAction(id, actionIndex) {
        const entry = root._entryById(id)
        if (!entry || !entry.notification || !entry.notification.actions)
            return
        const actions = entry.notification.actions
        if (actionIndex < 0 || actionIndex >= actions.length)
            return
        const a = actions[actionIndex]
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

    // Incremental models for the UI. A raw JS array used directly as a
    // ListView/Repeater model makes the view destroy and recreate EVERY
    // delegate on every change (and drops the Center's scroll position).
    // ScriptModel diffs successive values by IDENTITY — entry objects are
    // stable across array reassignments — so an arrival/removal only
    // creates/destroys the affected delegates, while content updates reach
    // delegates through their live bindings to the Notification object and
    // need no model operation at all.
    property ScriptModel historyModel: ScriptModel {
        values: root.list
        comparisonMode: ObjectComparison.Identity
    }
    property ScriptModel popupModel: ScriptModel {
        values: root.popups
        comparisonMode: ObjectComparison.Identity
    }

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
            // and a replaces_id update is applied to the object in place and
            // picked up by the delegates' live bindings, so an emission for a
            // known id can only be a re-delivery: ignore it and stop.
            const known = root._entryById(n.id)
            if (known)
                return

            const entry = {
                "id": n.id,
                "notification": n,
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
            root._pruneHistory()

            // Show a toast unless Do Not Disturb is on; critical notifications
            // bypass DND. History/count are updated above regardless of DND.
            // (Criticality is read live off the notification, not the entry.)
            if (!root.doNotDisturb || n.urgency === NotificationUrgency.Critical)
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
