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
- `components/`, `services/`, `models/`, `scripts/`, and `assets/` exist as empty placeholders and are not wired up yet.
- A drop-shadow design for the launcher was researched and spec'd but is **not implemented**.
- No tests. Verification is done with throwaway Node mirrors of the scoring logic (kept in `/tmp`).
- The only way to validate QML is to run it against the live shell and read stderr.

---

## What's here: the launcher

The shell currently ships one feature: a full-screen, keyboard-first application launcher.

| Piece | File | Role |
| --- | --- | --- |
| Window | `modules/launcher/Launcher.qml` | Transparent full-screen `PanelWindow`, focus grab, IPC |
| View | `modules/launcher/LauncherView.qml` | The card: search bar + results |
| Search | `modules/launcher/SearchBar.qml` | Icon + `TextField`, keyboard handling |
| Results | `modules/launcher/ResultList.qml` | `ListView` + navigation + activation |
| Row | `modules/launcher/ResultItem.qml` | Icon, highlighted title/subtitle |
| Wrap | `modules/launcher/ResultContainer.qml` | Sizing wrapper for the result list |
| Data | `modules/services/AppProvider.qml` | The brain: filtering, scoring, history, fallbacks |
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

## Conventions

- 2-space indentation; Catppuccin Mocha palette as hardcoded hex (`#1e1e2e`, `#313244`, `#fab387`, ...).
- Per-file imports (each QML file declares its own `QtQuick` / `Quickshell` needs).
- QML "modules" are plain directories imported by relative path — every `.qml` in `modules/launcher/` becomes a type (`Launcher`, `SearchBar`, ...). No `qmldir`, no manifest.
- No comments in the codebase.

---

## Roadmap (very incomplete)

- [x] Launcher window + focus grabbing + IPC
- [x] Fuzzy scoring with field penalties
- [x] Usage-ranked history with decay
- [x] Exact-match tier
- [x] Browser search fallback (configurable engine)
- [x] URL detection fallback
- [ ] Drop shadow for the launcher (design settled, code pending)
- [ ] Wire search results to real filtering UX (navigable, mode-switchable)
- [ ] Bar, tray, notifications, OSD — everything else a shell needs
- [ ] Anything beyond the launcher, really

---

*Pure QML, zero deps, endless WIP.*
