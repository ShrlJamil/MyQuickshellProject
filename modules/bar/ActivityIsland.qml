import QtQuick
import "../../components"

// Media and screen recording share this one spot in the bar. Each
// activity owns a SLOT, assigned by start order: the activity that
// started first keeps the left slot, the one that started later
// takes the right slot, and neither ever moves to the other's slot.
// Inside its slot an activity is shown as its full pill (expanded)
// or as a small detached round circle ("minimal"):
// - One activity active: full pill.
// - Both active: the most recently started one starts expanded;
//   the other shrinks to its round minimal IN ITS OWN SLOT (the
//   older one visibly shrinks at the left when the newer joins at
//   the right).
// - Tapping a minimal expands that activity IN ITS OWN SLOT while
//   the other one shrinks in its slot. Nothing ever trades places -
//   Sahrul's direction on 2026-11-17, after the earlier form-first
//   layout (pill always left, circle always right, so an activity
//   seemed to jump across the island whenever the pill changed
//   hands) read as position-swapping rather than growth.
// - When one activity ends, the survivor expands to its full pill
//   in its own slot if it was the minimal.
//
// Animation mirrors the shell's top-centre DynamicIsland.qml (the
// reference Sahrul pointed at on the external monitor): every form
// animates its OWN width with a plain Behavior, 300 ms OutCubic,
// its background filling the item so the rounded ends stay rounded
// at every width; the island itself is just the sum of the slots
// plus an animated gap, so the whole spot only ever widens and
// narrows.
Item {
    id: root

    required property var mediaService

    // Mirrors the media pill's old show condition (submap hold label).
    property bool mediaSuppressed: false

    // The media popover's open state, owned by Bar.qml as before.
    property bool popoverOpen: false

    signal mediaActivateRequested()

    readonly property bool mediaActive: !root.mediaSuppressed && root.mediaService && root.mediaService.hasMedia
    readonly property bool recordActive: RecordService.recording
    readonly property bool bothActive: root.mediaActive && root.recordActive

    // Start-order bookkeeping for the slots: every activation takes
    // the next sequence number; the number is released only once
    // the activity's forms have fully shrunk away (see the watchers
    // below). The lower number owns the left slot.
    property int seqCounter: 0
    property int mediaSeq: 0
    property int recordSeq: 0

    // Which activity is expanded. Activation edges hand it to the
    // newest activity; a tap on a minimal hands it to that activity
    // (it expands in its own slot - see the header note).
    property string primary: "media"

    readonly property bool mediaExpanded: root.mediaActive && (!root.recordActive || root.primary === "media")
    readonly property bool recordExpanded: root.recordActive && (!root.mediaActive || root.primary === "record")

    // A slot's width is the WIDER of its two stacked forms, not
    // their sum: pill and minimal share the slot's x, so summing
    // double-counts the overlap mid-morph and shoves the other
    // slot away by the narrower form's width (the visible gap
    // between the forms ballooned to ~66 device px on Sahrul's
    // 2026-11-17 recording before this fix).
    readonly property real mediaFormWidth: Math.max(mediaPill.width, mediaMinimal.width)
    readonly property real recordFormWidth: Math.max(recordPill.width, recordMinimal.width)
    readonly property bool mediaIsLeft: root.mediaSeq <= root.recordSeq

    // The inter-slot gap, animated so the island never takes an
    // instant 6 px step when the second activity joins or leaves.
    property real gapW: root.bothActive ? 6 : 0

    Behavior on gapW {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    readonly property real mediaX: root.mediaIsLeft ? 0 : root.recordFormWidth + root.gapW
    readonly property real recordX: root.mediaIsLeft ? root.mediaFormWidth + root.gapW : 0

    // Media pill centre in this item's coordinates; Bar.qml adds
    // root.x to anchor the media popover under the pill as before.
    readonly property real mediaCenterOffset: mediaPill.x + mediaPill.width / 2

    // Stays visible while any form is still animating out.
    visible: root.mediaActive || root.recordActive || mediaPill.width > 0.5 || recordPill.width > 0.5 || mediaMinimal.width > 0.5 || recordMinimal.width > 0.5
    width: root.mediaFormWidth + root.recordFormWidth + root.gapW
    height: 30
    clip: true

    Component.onCompleted: {
        if (root.mediaActive) {
            root.seqCounter += 1
            root.mediaSeq = root.seqCounter
        }
    }

    onMediaActiveChanged: {
        if (root.mediaActive) {
            root.seqCounter += 1
            root.mediaSeq = root.seqCounter
            if (root.recordActive)
                root.primary = "media"
        }
    }

    // A slot is released only once the departing activity's forms
    // have fully shrunk. Releasing it on the deactivation edge made
    // mediaIsLeft flip at the START of the exit morph, so the
    // departing form teleported into the other slot and shrank
    // there: stopping a right-slot recording made its pill jump to
    // the left and vanish at the left (Sahrul's report, 2026-11-17).
    // While the seq is held, the survivor expands in its own slot
    // and the departing form is pushed toward its own side as it
    // shrinks - a right-slot recording shrinks toward the right.
    // The final flip is invisible: with the departed form at width
    // 0, both slot formulas put the survivor at x = 0 either way.
    onMediaFormWidthChanged: {
        if (!root.mediaActive && root.mediaSeq !== 0 && root.mediaFormWidth < 0.5)
            root.mediaSeq = 0
    }

    onRecordFormWidthChanged: {
        if (!root.recordActive && root.recordSeq !== 0 && root.recordFormWidth < 0.5)
            root.recordSeq = 0
    }

    onRecordActiveChanged: {
        if (root.recordActive) {
            root.seqCounter += 1
            root.recordSeq = root.seqCounter
            if (root.mediaActive)
                root.primary = "record"
        }
    }

    // Minimals are declared before the pills so the pill renders on
    // top during a same-slot morph (pill grows over the shrinking
    // circle and vice versa).
    MediaMinimal {
        id: mediaMinimal

        anchors.verticalCenter: parent.verticalCenter
        x: root.mediaX
        mediaService: root.mediaService
        show: root.bothActive && root.primary === "record"
        covered: mediaPill.width > 30
        onActivateRequested: root.primary = "media"
    }

    RecordMinimal {
        id: recordMinimal

        anchors.verticalCenter: parent.verticalCenter
        x: root.recordX
        show: root.bothActive && root.primary === "media"
        covered: recordPill.width > 30
        onActivateRequested: root.primary = "record"
    }

    MediaPill {
        id: mediaPill

        anchors.verticalCenter: parent.verticalCenter
        x: root.mediaX
        mediaService: root.mediaService
        show: root.mediaExpanded
        popoverOpen: root.popoverOpen
        onActivateRequested: root.mediaActivateRequested()
    }

    RecordPill {
        id: recordPill

        anchors.verticalCenter: parent.verticalCenter
        x: root.recordX
        forceHidden: !root.recordExpanded
    }
}
