# Contributing to OptiEleven

Thanks for helping. Issues and pull requests in English or Spanish are both fine.

## Reporting a bug

Open an issue with:

- Your Windows version (Settings → System → About, or `winver`).
- What you did and what happened.
- The relevant lines of `%ProgramData%\OptiEleven\panel.log` (System → Backups → Open folder).

## Adding or changing a tweak

Each tweak is one file: `OptiEleven/tools/tweaks/<category>/<id>.tweak.json`. The panel loads every file on start, sorted by `order`.

- Fields: `id`, `kind` (`"tweak"`), `category` (the tab it goes in), `order`, `name` and `summary` (each `{ "es": "...", "en": "..." }`), `risk` (`safe`, `moderate` or `advanced`), `presets` (`recommended`, `advanced`), `requiresAdmin`, `reboot`, `reversible`, `undo` and `actions`.
- `actions` is a list of `{ "registry", "name", "type", "value", "default" }`, `{ "service", "startup", "default" }` and `{ "task" }`. The engine saves the current state before applying and restores it on revert, so these need no code.
- If a tweak needs code (power plans, app removal…), add `"script": "<id>.tweak.ps1"` and put next to it a file that returns `@{ Backup; Test; Apply; Revert; Diff }` scriptblocks.

Every tweak must be reversible, or set `"reversible": false` and say why in `undo.note`. A file with a missing field or a repeated `id` is skipped with a warning in Activity.

Please include in the PR:

- What it changes and why it helps (a source is great).
- What it breaks, if anything. That text goes in the description users read.
- That you ran `.\OptiEleven.ps1 -Status` without errors, then applied and reverted the tweak on a real machine or VM.

## Adding a tool

A tool is a folder in `OptiEleven/tools/` with two files. The panel finds it on start; you don't touch `OptiEleven.ps1`.

- `tool.json`: `id`, `kind` (`"tool"`), `category` (an `id` from `tools/categories.json`), `order`, `name`, `title`, `summary` (each `{ "es": "...", "en": "..." }`), `icon` (a name from `assets/icons.json`), `color`, `view` (the function that builds the page), `risk` (`safe`, `moderate` or `advanced`), `requiresAdmin`, `reversible` and `undo` (`{ "type": "...", "note": { ... } }`). Optional: `onShow`, a function that runs each time the page opens.
- `tool.ps1`: defines the `view` function, which returns the page's WPF content.

The `id` is also what `-Page` takes. If a manifest is missing a field or reuses an `id`, the panel skips that tool and says why in Activity.

## Translations

The code is written in Spanish, and `OptiEleven/lang/<code>.json` translates it:

- `"strings"`: exact Spanish text → translation.
- `"patterns"`: `[regex, replacement]` for sentences with numbers or names. In the replacement, `$1` copies a group as is and `@1` translates it too.

To add a language, copy `lang/en.json` to a new file named with the language code (for example `fr.json`), set `"name"` (for example `"Français"`) and translate the values. Leave the keys alone. The language shows up in the language menu automatically.

## Style

- PowerShell 5.1 compatible (no `??`, `?:` or `&&`).
- Save `.ps1` files as UTF-8 **with BOM**, or PowerShell 5.1 breaks accented characters.
- Keep UI text short and plain. Say what a setting does and what it costs.
