# quickshell

A hand-rolled [Quickshell](https://github.com/Quickshell/Quickshell) desktop shell for **Hyprland** (Wayland), written in pure QML. No build system, no framework — just QML files and good taste.

```
   ___                      _      _     _
  / _ \ _   _  __ _ _ __   | | ___| |__ (_)_   _ ___
 | | | | | | | |/ _` | '_ \ | |/ _ \ '_ \| | | | / __|
 | |_| | |_| | |(_| | | | || |  __/ | | | | |_| \__ \
  \__\_\\__,_|\__,_|_| |_|/ |\___|_| |_|_|\__,_|___/
                       |__/
```

> **WIP** - this project is a work in progress. Treat it as a living sketch, not a shipped product.

---

## Status: still cooking

Prototype, not a stable release. Expect rough edges and breaking changes. What exists today:

- **Launcher** (solid): full-screen keyboard app launcher with fuzzy scoring, usage history, and prefix search modes.
- **Top bar** (working): static 40px bar per monitor with a pop-down **Dynamic Center** (power menu, display manager, wallpaper picker, expanded media player, capture picker), a **Control Center** overlay, system tray, and status indicators.
- **Media**: MPRIS-backed now-playing preview in the bar centre (click-to-expand, never auto-expands) plus an expanded player surface.
- **Notifications**: freedesktop notification history (Notification Center) + popup toasts, with inline reply support.
- **OSD**: standalone bottom-centre overlay for volume / brightness / caps-lock, plus a workspace OSD.
- **Capture**: region / window / screen / fullscreen screenshots with overlay selection and preview.
- No tests. Verification is a scratch copy (`cp -r . /tmp/scratch && qs -p /tmp/scratch -n`) plus reading stderr / `qs log`.

Built and verified against **Quickshell 0.3.2**, **Qt 6.11**, **Hyprland 0.56**.

---

## What's here: the launcher

A full-screen, keyboard-first application launcher.

| Piece | File | Role |
| --- | --- | --- |
| Window | `modules/launcher/Launcher.qml` | Transparent full-screen `PanelWindow`, mask-driven shape, focus grab, IPC |
| View | `modules/launcher/LauncherView.qml` | The card: search bar + results |
| Search | `modules/launcher/SearchBar.qml` | Icon + `TextField`, keyboard handling |
| Results | `modules/launcher/ResultList.qml` | `ListView` + navigation + activation |
| Row | `modules/launcher/ResultItem.qml` | Icon, highlighted title/subtitle |
| Wrap | `modules/launcher/ResultContainer.qml` | Sizing wrapper for the result list |
| Data | `modules/services/AppProvider.qml` | The brain: filtering, scoring, history, modes, fallbacks |
| Modes | `modules/services/SearchModeProvider.qml` | Prefix-based search mode detection |
| Theme | `components/Theme.qml` | Color palette singleton (defaults + `palette.json` override) |
| State | `modules/controllers/LauncherController.qml` | Visibility toggle |

The launcher is created lazily: the `Loader` in `shell.qml` stays inactive until the first open, then latches active so reopening is instant.

### Launching

- `quickshell` (or `qs`) runs the directory as the `default` config; `shell.qml` is the entrypoint.
- `quickshell -p <path>` runs a config from an arbitrary path — **always** use this to test a scratch copy; running `qs` bare replaces the live shell.
- IPC control, e.g. `qs ipc call launcher toggle`. Full target list is in [IPC reference](#ipc-reference) below.

---

## The brain: `AppProvider`

### Fuzzy scoring

Sequence-based fuzzy matching across four fields, with per-field penalties applied on top of a raw score:

```
name          -> no penalty
genericName   -> -300
execString    -> -150
keywords      -> -450 (floor of 10 per match)
```

Bonuses reward intuitive matches over sloppy ones:

```
prefix    +450
acronym   +300
boundary  +150
```

### Usage history

Launches are recorded per-query in `launcher-history.json` (stored via `Quickshell.statePath`). A ranked boost is derived from recent usage:

- half-life: 21 days of exponential decay
- per-record cap: 10
- relative boost: up to 10% of the fuzzy score
- saturation: 5
- only applied when the gap to the top result is within a 5% tolerance

Exact name matches always win the tier before anything else is compared.

### Smart fallbacks

When nothing matches, the launcher gets smarter instead of going blank:

1. **URL detection** — if the query *looks* like a URL (domain, `localhost`, IPv4, `http(s)://`), it opens directly in the default browser, auto-prepending `https://` when no scheme is given. Queries containing whitespace or starting with `?` are never treated as URLs.
2. **Web search** — otherwise it offers `Search the web for "..."`, which opens the configured search engine. The engine is a template, not a hardcode:

```qml
property string searchEngine: "https://www.google.com/search?q=%1"
```

Swap in DuckDuckGo, Startpage, or anything else by changing one property. Fallbacks are never written to usage history.

---

## Search modes

Typing isn't just app search — a leading character switches the whole mode (detected live by `SearchModeProvider`):

| Prefix | Mode | What it does |
| --- | --- | --- |
| *(none)* | apps | Fuzzy app search (the default) |
| URL (auto) | url | Queries that look like URLs open in the browser |
| `=` | calculator | Evaluate a math expression, copy the result |
| `>` | command | Run a shell command in the terminal, with a small action set (`lock`, `logout`, `suspend`, `reboot`, `shutdown`) and per-session history via `Up`/`Down` |
| `?` | web | Force a web search |
| `:` | clipboard | Browse cliphist history; `Delete` deletes the selected entry, `Ctrl+Shift+Delete` wipes it |
| `/` | file | Scan the file index with `fd` and fuzzy-match paths |

### File mode (partial)

File search exists but is **not fully working yet**:

- The index is loaded with `fd --type f` over `~/.config`, `~/Projects`, `~/Documents`, and `~/Downloads`.
- Scanning is chunked and throttled so the UI stays responsive.
- **Activation is a no-op** — `fileExecute` is an empty stub, so opening the selected file is not wired up. You can find and scroll files, but pressing Enter does nothing.

---

## The bar

A static **40px** top bar, one instance per monitor (`Variants(Quickshell.screens)`), all sharing a single `barState { mode, screen, mediaManual }` object in `shell.qml`.

| Zone | Contents |
| --- | --- |
| Left | Arch logo (click: fastfetch-style system popover via `UptimeService`), active window icon + title, Hyprland submap pill |
| Centre | Mode hold-label, or the `MediaPreview` now-playing pill (artwork, scrolling title/artist, cava mini-viz) |
| Right | Control-Center button, clock (`DateTimeWidget`), battery widget + popover, caffeine indicator, system tray, mic-mute indicator, Wi-Fi indicator + details popover |

| Piece | File | Role |
| --- | --- | --- |
| Bar | `modules/bar/Bar.qml` | `PanelWindow`, `exclusiveZone: 40`, focus grab, input mask, all bar content |
| Dynamic center | `modules/bar/DynamicCenter.qml` | Plain `Item` at `y: 40`, attached under the bar; raises one surface at a time, each behind a latched `Loader` with crossfade |
| Power menu | `modules/bar/PowerMenu.qml` + `PowerActionItem.qml` | 6 actions — Lock, Hibernate, Logout, Shutdown, Suspend, Reboot — with hold-to-confirm |
| Display | `modules/display/DisplayManager.qml` | Monitor-arrangement surface (backed by `DisplayService`) |
| Wallpapers | `modules/wallpapers/WallpaperPicker.qml` | Thumbnail strip, keyboard nav, applies via `walset-backend`-style flow (wallpaper + wallust + matugen) |
| Control Center | `modules/bar/ControlCenter.qml` + `ControlSlider.qml` / `ControlTile.qml` | Separate top-right overlay window: audio, brightness, network, bluetooth, hotspot and quick toggles (audio over native PipeWire, no `wpctl`) |
| Clock/date | `modules/bar/DateTimeWidget.qml` | Clock + calendar popover |
| Battery | `modules/bar/BatteryWidget.qml` + `BatteryService.qml` | UPower-backed indicator + popover |

### The dynamic center

The bar's centre can raise a surface that looks like it grows straight out of the bar — no gap, square top corners. Implemented surfaces: `power`, `display`, `wallpapers`, `media` (expanded player), `capture` (picker). `mediaPreview` / `mediaCompact` IPC modes also exist.

- The bar's `PanelWindow` height stays constant at runtime; surfaces fade/crossfade inside the allocated space. (Resizing a layer-shell surface every open flickers badly on fractional-scale outputs.)
- When idle, the transparent area below the 40px strip is click-through (input mask); when a surface is open the window grabs input via `HyprlandFocusGrab`.
- Wi-Fi and audio output deliberately live in **Control Center**, not here. Search and clipboard live in the **launcher**.

### Power menu

- **Hold to confirm** — press and hold (mouse *or* `Enter`) for ~1s; a progress bar fills; releasing or leaving early cancels. No accidental shutdowns.
- Arrow keys move the selection, `Esc` closes, clicking outside closes.
- Icons are SVGs from `assets/`, recoloured to white in QML (`ColorOverlay`) — the source files are left untouched.
- Multi-monitor safe: only the focused monitor's bar activates the surface and the focus grab.

---

## Media

One `MediaService` (`modules/services/MediaService.qml`) wraps the native `Quickshell.Services.Mpris` singleton for every consumer: laptop-first player selection, a runtime last-media cache (pause/stop/gone players keep showing the last track), a stable `trackKey` identity (`mpris:trackid`, title-anchored fallback), and a 1 Hz position tick that only runs while the expanded player is open and playing.

- **Bar preview** (`modules/bar/MediaPreview.qml`): compact pill — artwork, scrolling title/artist, live cava mini-viz. Intro animation on open only (artwork flies in from the right and unveils the content); track/metadata changes update in place, no animation.
- **Expanded player** (`modules/bar/MediaPlayer.qml`): DynamicCenter surface with vinyl artwork, transport controls, seek bar, and a multi-player selector pill.
- **Click-to-expand, never auto-expand**: playback, track changes, and metadata updates never touch `barState` — only clicking the preview opens the expanded player (`mediaManual`).
- **Artwork prefetch**: a hidden zero-size `Image` in `MediaService` pre-loads the current artwork URL (same URL + size as the display art, sharing Qt's image cache); the intro never waits for it, and the `♪` fallback covers misses/errors.
- `CavaService` runs the `cava` spectrum analyzer only while something is actually playing; pausing releases the capture stream.

---

## Notifications, OSD, capture, display

| Area | Files | Notes |
| --- | --- | --- |
| Notifications | `modules/bar/NotificationService.qml`, `NotificationCenter.qml`, `NotificationPopup.qml`, `NotificationReply.qml` | freedesktop `NotificationServer` history + per-screen center and popup toasts, inline reply |
| OSD | `modules/osd/OSD.qml`, `OSDService.qml` | Standalone bottom-centre, click-through overlay: volume / brightness / caps-lock (+ workspace OSD). Brightness keys step optimistically, then run `brightnessctl` detached |
| Capture | `modules/capture/CaptureService.qml`, `CaptureBar.qml`, `CaptureOverlay.qml`, `ScreenshotPreview.qml` | Region / window / screen / instant-fullscreen shots to file + clipboard; selection overlay; preview. Lives outside `barState.mode` |
| Eco mode | `modules/bar/EcoService.qml` | Snapshot-apply-restore over `hyprctl`: blur/shadow off + opaque QML surfaces, no config edits |
| Misc services | `AudioService`, `MicService`, `NetworkService`, `BluetoothService`, `BatteryService`, `BrightnessService`, `NightLightService`, `HotspotService`, `SubmapService`, `UptimeService`, `CaffeineService` (all under `modules/bar/`) | Native backends first (PipeWire, UPower, BlueZ, NetworkManager); tiny shell reads only where the 0.3.x QML API has gaps. `MprisService.qml` is a legacy stub superseded by `MediaService` |

---

## IPC reference

`qs ipc call <target> <fn>` (target = focused monitor where relevant):

| Target | Functions |
| --- | --- |
| `launcher` | `show`, `hide`, `toggle` |
| `power`, `display`, `wallpapers`, `center`, `mediaPreview`, `mediaCompact` | `show`, `hide`, `toggle` (set `barState.mode` + `screen`) |
| `volume` | `up`, `down` (±5 via native PipeWire) |
| `brightness` | `up`, `down` (step + OSD) |
| `capture` | `open`, `bar`, `region`, `window`, `screen`, `fullscreen` |

---

## Theming

All colors flow from a single `Theme` singleton (`components/Theme.qml`) — no hardcoded hex colors in the UI. Each widget imports `../../components` and reads `Theme.*`.

`Theme` ships with built-in defaults, then **overrides them from `palette.json`** in the config directory (`~/.config/quickshell/palette.json`) when that file exists. It is watched for changes and re-applied live, so you don't need to restart the shell.

### The palette file

A minimal `palette.json`:

```json
{
  "background": "#0f0f0f",
  "surface": "#1a1b26",
  "text": "#c0caf5",
  "textDim": "#565f89",
  "textMuted": "#3b4261",
  "accent": "#7aa2f7"
}
```

Every key is optional — unset keys keep their defaults. The full set is `background`, `surface`, `text`, `textDim`, `textMuted`, and `accent`. (`surfaceHover` is computed as white at 5% opacity, not overridable.)

The file is **gitignored**, since it is meant to be generated by a color scheme tool.

### Generating it with wallust

A wallust template is included at `~/.config/wallust/templates/quickshell.json` and registered in `[templates]` in `wallust.toml`, writing straight to `~/.config/quickshell/palette.json`:

```json
{
    "background": "{{background}}",
    "surface": "{{color0}}",
    "text": "{{foreground}}",
    "textDim": "{{color7}}",
    "textMuted": "{{color8}}",
    "accent": "{{color4}}"
}
```

Just run `wallust` against a wallpaper as usual — the whole shell picks the new colors up without a restart. (Note: wallust v4 variables already include the `#` prefix, so don't add one in the template.)

---

## Conventions

- 2-space indentation; colors come from the `Theme` singleton, defaulting to a black card / light text (was Catppuccin Mocha in previous versions).
- Per-file imports (each QML file declares its own `QtQuick` / `Quickshell` needs).
- QML "modules" are plain directories imported by relative path — every `.qml` in `modules/launcher/` or `modules/bar/` becomes a type (`Launcher`, `Bar`, `PowerMenu`, ...). No `qmldir`, no manifest. `components/` is imported the same way for `Theme`.
- Explanatory comments live with the tricky code (layer-shell sizing, focus grabs, MPRIS quirks) — read them before touching those paths.
- One non-QtQuick QML dependency: `Qt5Compat.GraphicalEffects` (`ColorOverlay`, for white-tinting icons) — package `qt6-5compat`. Plus external tools the shell shells out to: `cava`, `brightnessctl`, `nmcli`/`ip`, `fd`, `cliphist`, `wallust`/`matugen` (wallpaper flow).

---

## Roadmap (very incomplete)

- [x] Launcher window + focus grabbing + IPC (lazy-loaded)
- [x] Fuzzy scoring with field penalties
- [x] Usage-ranked history with decay
- [x] Exact-match tier
- [x] Browser search fallback (configurable engine)
- [x] URL detection fallback
- [x] Calculator, command, web, and clipboard search modes
- [x] Centralized theming via `palette.json` (+ wallust integration)
- [x] Static top bar (per-monitor, tray, indicators, popovers)
- [x] Dynamic center surfaces: power, display, wallpapers, media, capture
- [x] Power menu with hold-to-confirm, keyboard nav, multi-monitor-safe focus grab
- [x] MPRIS media stack (preview + expanded player, click-to-expand, prefetch)
- [x] Control Center (audio/network/bluetooth/hotspot tiles)
- [x] Tray (StatusNotifierItem hosts in the bar), notifications (center + popups + reply), OSD (volume/brightness/caps + workspace)
- [x] Screenshot capture (region/window/screen) with overlay + preview
- [ ] File search activation — results are found but Enter is a no-op
- [ ] Drop shadow for the launcher (design settled, code pending)
- [ ] `mediaPreview` / `mediaCompact` IPC surfaces (targets exist, surfaces unbuilt)

---

*Pure QML, no framework, endless WIP.*
