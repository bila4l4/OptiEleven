# Contributing to OptiEleven

Thanks for helping. Issues and pull requests in English or Spanish are both fine.

## Reporting a bug

Open an issue with:

- Your Windows version (Settings → System → About, or `winver`).
- What you did and what happened.
- The relevant lines of `%ProgramData%\OptiEleven\panel.log` (System → Backups → Open folder).

## Adding or changing a tweak

Tweaks live in the catalog in `OptiEleven/OptiEleven.ps1`. Every tweak must be reversible: use the `Reg`, `Svc` and `Task` definitions where you can, so the engine saves and restores the original state for you. For anything else, provide `Backup`, `Test`, `Apply`, `Revert` and `Diff` scriptblocks.

Please include in the PR:

- What it changes and why it helps (a source is great).
- What it breaks, if anything. That text goes in the description users read.
- That you ran `.\OptiEleven.ps1 -Status` without errors, then applied and reverted the tweak on a real machine or VM.

## Translations

The code is written in Spanish, and `OptiEleven/lang/<code>.json` translates it:

- `"strings"`: exact Spanish text → translation.
- `"patterns"`: `[regex, replacement]` for sentences with numbers or names. In the replacement, `$1` copies a group as is and `@1` translates it too.

To add a language, copy `lang/en.json` to a new file named with the language code (for example `fr.json`), set `"name"` (for example `"Français"`) and translate the values. Leave the keys alone. The language shows up in the language menu automatically.

## Style

- PowerShell 5.1 compatible (no `??`, `?:` or `&&`).
- Save `.ps1` files as UTF-8 **with BOM**, or PowerShell 5.1 breaks accented characters.
- Keep UI text short and plain. Say what a setting does and what it costs.
