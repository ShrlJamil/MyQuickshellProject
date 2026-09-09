pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// "Caffeine" - keep the machine awake (no auto-suspend, no screen blank/lock)
// while enabled.
//
// D-BUS AUDIT (Quickshell 0.3.1, this build): there is NO generic D-Bus binding
// for QML - only the purpose-built services (Bluetooth, Mpris, Notifications,
// Pam, Pipewire, Polkit, SystemTray, UPower) plus DBusMenu. So a direct native
// `org.freedesktop.ScreenSaver` / `org.freedesktop.PowerManagement.Inhibit`
// call is not possible here without shelling out to busctl/dbus-send.
//
// What we do instead, per the fallback in the spec:
//   * logind / sleep side  -> `systemd-inhibit --what=idle:sleep ...`, which is
//     the canonical liblogind D-Bus inhibitor (Manager.Inhibit, holds an fd).
//     It shows up in `systemd-inhibit --list` / `loginctl`. Quickshell's Process
//     releases it automatically: clearing `running` (toggle off, shell reload,
//     crash) SIGTERMs the helper, the fd closes, the lock is gone - no manual
//     cookie/Uninhibit bookkeeping.
//   * compositor screen-blank side -> the always-on Bar window carries a native
//     `Quickshell.Wayland.IdleInhibitor` (zwp_idle_inhibit_manager_v1) bound to
//     `CaffeineService.enabled`; that is what stops hypridle blanking/locking.
Item {
    id: root

    property bool enabled: false

    function toggle() {
        root.enabled = !root.enabled
    }

    function setEnabled(v) {
        root.enabled = !!v
    }

    // Held for as long as `enabled` is true; killed (lock released) the moment
    // it goes false.
    Process {
        id: inhibitProc

        running: root.enabled
        command: [
            "systemd-inhibit",
            "--what=idle:sleep",
            "--who=Quickshell",
            "--why=Caffeine active",
            "--mode=block",
            "sleep", "infinity"
        ]
    }
}
