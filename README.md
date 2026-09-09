# quickshell

A hand-rolled [Quickshell](https://github.com/Quickshell/Quickshell) desktop shell for **Hyprland** (Wayland), written in pure QML. No build system, no dependencies, no framework — just QML files and good taste.

```
   ___                      _      _     _
  / _ \ _   _  __ _ _ __   | | ___| |__ (_)_   _ ___
 | | | | | | | |/ _` | '_ \ | |/ _ \ '_ \| | | | / __|
 | |_| | |_| | |(_| | | | || |  __/ | | | | |_| \__ \
  \__\_\\__,_|\__,_|_| |_|/ |\___|_| |_|_|\__,_|___/
                       |__/
```

> **WIP** - this project is a work in progress. It is *far* from finished.
> Treat it as a living sketch, not a shipped product.

---

## Status: still cooking

This is a **prototype**, not a stable release. Expect rough edges, missing features, and breaking changes at any commit. Things we already know are unfinished or unimplemented:

- Two widgets exist: the **launcher** (solid) and a **top bar** with a pop-down "dynamic center" and a power menu (working, but young). A tray, notifications, and OSD do not exist.
- The bar's **Control Center** (Wi-Fi / sliders / quick-toggle tiles) is stubbed — it renders but most tiles do nothing. The `display` / media-preview / media-compact surfaces are placeholders.
- `components/` holds the `Theme` palette singleton (now used by everything); `assets/` holds a handful of SVG icons; `models/` and top-level `scripts/` / `services/` are still empty placeholders.
- A drop-shadow design for the launcher was researched and spec'd but is **not implemented**.
- No tests. Verification is done by running a scratch copy (`qs -p /tmp/copy`) and reading stderr, plus throwaway Node mirrors of the scoring logic.
- The only way to validate QML is to run it and read stderr — there is no dry-run flag.

Built and verified against **Quickshell 0.3.1**, **Qt 6.11**, **Hyprland 0.56**.

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

### Launching

- `quickshell` (or `qs`) runs the directory as the `default` config; `shell.qml` is the entrypoint.
- `quickshell -p <path>` runs a config from an arbitrary path — **always** use this to test a scratch copy; running `qs` bare replaces the live shell.
- IPC control: `qs ipc call launcher toggle`, `qs ipc call bar toggle`, `qs ipc call power toggle`, `qs ipc call center toggle`.

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

A static **40px** top bar, one instance per monitor (`Variants(Quickshell.screens)`), all sharing a single `barState { mode, screen, barEnabled }` object in `shell.qml`. Toggle it with `qs ipc call bar toggle`.

| Piece | File | Role |
| --- | --- | --- |
| Bar | `modules/bar/Bar.qml` | `PanelWindow`, `exclusiveZone: 40`, fixed height, focus grab, mask. Static content: launcher button, clock, control-center button, "Hold to confirm" hint |
| Dynamic center | `modules/bar/DynamicCenter.qml` | Plain `Item` at `y: 40`, attached under the bar; raises one surface at a time |
| Power menu | `modules/bar/PowerMenu.qml` | 6 actions — Lock, Hibernate, Logout, Shutdown, Suspend, Reboot |
| Action tile | `modules/bar/PowerActionItem.qml` | Icon + label + hold-to-confirm progress bar |
| Control Center | `modules/bar/ControlCenter.qml` | Separate top-right overlay window (Wi-Fi, sliders, quick toggles) — **stubbed** |
| Helpers | `ControlSlider.qml`, `ControlTile.qml`, `WifiService.qml` | Slider/tile widgets; `WifiService` shells out to `nmcli` |

### The dynamic center

The idea: the bar's centre can drop a surface that looks like it grows straight out of the bar — no gap, square top corners — and different "commands" reuse the same slot.

- `qs ipc call power toggle` → power menu. `display` / `mediaPreview` / `mediaCompact` targets exist but their surfaces are empty stubs.
- The bar's `PanelWindow` is a **runtime constant height** (`40` + a fixed max surface size). It never resizes when the surface opens/closes — the content just fades in and out inside the already-allocated space. (Resizing a layer-shell surface every open turned out to flicker badly on fractional-scale outputs.)
- When idle, the transparent area below the 40px strip is click-through (input mask); when a surface is open the whole window grabs input via `HyprlandFocusGrab`.
- Wi-Fi and audio output deliberately live in **Control Center**, not here. Search and clipboard live in the **launcher**.

### Power menu

- **Hold to confirm** — press and hold (mouse *or* `Enter`) for ~1s; a progress bar fills; releasing or leaving early cancels. No accidental shutdowns.
- Arrow keys move the selection, `Esc` closes, clicking outside closes.
- Icons are SVGs from `assets/`, recoloured to white in QML (`ColorOverlay`) — the source files are left untouched.
- Multi-monitor safe: only the focused monitor's bar activates the surface and the focus grab.

---

## Theming

All colors flow from a single `Theme` singleton (`components/Theme.qml`) — there are **no hardcoded hex colors** in the UI anymore (launcher and bar both). Each widget imports `../../components` and reads `Theme.*`.

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
- No comments in the codebase.
- One non-QtQuick QML dependency: `Qt5Compat.GraphicalEffects` (`ColorOverlay`, for white-tinting icons) — package `qt6-5compat`.

---

## Roadmap (very incomplete)

- [x] Launcher window + focus grabbing + IPC
- [x] Fuzzy scoring with field penalties
- [x] Usage-ranked history with decay
- [x] Exact-match tier
- [x] Browser search fallback (configurable engine)
- [x] URL detection fallback
- [x] Calculator, command, web, and clipboard search modes
- [x] Centralized theming via `palette.json` (+ wallust integration)
- [x] Static top bar (per-monitor, fixed height, IPC toggle)
- [x] Dynamic center surface, attached under the bar
- [x] Power menu with hold-to-confirm, keyboard nav, multi-monitor-safe focus grab
- [ ] File search activation — results are found but Enter is a no-op
- [ ] Drop shadow for the launcher (design settled, code pending)
- [ ] Control Center — renders, but Wi-Fi/sliders/toggles are mostly stubs
- [ ] `display` and media (preview / compact now-playing) surfaces
- [ ] Tray, notifications, OSD — everything else a shell needs

---

*Pure QML, no framework, one stock Qt module, endless WIP.*
