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

- The launcher is the **only** widget that exists. There is no bar, no tray, no notifications, no OSD — nothing else.
- `components/` holds the `Theme` palette singleton (wired into the launcher); `models/`, `scripts/`, and `assets/` are still empty placeholders.
- A drop-shadow design for the launcher was researched and spec'd but is **not implemented**.
- No tests. Verification is done with throwaway Node mirrors of the scoring logic (kept in `/tmp`).
- The only way to validate QML is to run it against the live shell and read stderr.

---

## What's here: the launcher

The shell currently ships one feature: a full-screen, keyboard-first application launcher.

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
- `quickshell -p <path>` runs a config from an arbitrary path (handy for testing a scratch copy).
- IPC control: `quickshell ipc launcher toggle | show | hide`.

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

## Theming

All colors flow from a single `Theme` singleton (`components/Theme.qml`) — there are **no hardcoded hex colors** in the launcher UI anymore. Each widget imports `../../components` and reads `Theme.*`.

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

Just run `wallust` against a wallpaper as usual — the launcher picks the new colors up without a restart. (Note: wallust v4 variables already include the `#` prefix, so don't add one in the template.)

---

## Conventions

- 2-space indentation; colors come from the `Theme` singleton, defaulting to a black launcher card with light text (was Catppuccin Mocha in previous versions).
- Per-file imports (each QML file declares its own `QtQuick` / `Quickshell` needs).
- QML "modules" are plain directories imported by relative path — every `.qml` in `modules/launcher/` becomes a type (`Launcher`, `SearchBar`, ...). No `qmldir`, no manifest. `components/` is imported the same way for `Theme`.
- No comments in the codebase.

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
- [ ] File search activation — results are found but Enter is a no-op
- [ ] Drop shadow for the launcher (design settled, code pending)
- [ ] Bar, tray, notifications, OSD — everything else a shell needs
- [ ] Anything beyond the launcher, really

---

*Pure QML, zero deps, endless WIP.*
