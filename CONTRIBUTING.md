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
- If the tool changes the system, record each change with `Add-History '<id>' '<action>' '<text>'` (optionally with a list of `@{ what; before; after }`) so it shows in History. Tweaks are recorded by the engine.

The `id` is also what `-Page` takes. If a manifest is missing a field or reuses an `id`, the panel skips that tool and says why in Activity.

## Translations

The code is written in Spanish, and `OptiEleven/lang/<code>.json` translates it:

- `"strings"`: exact Spanish text → translation.
- `"patterns"`: `[regex, replacement]` for sentences with numbers or names. In the replacement, `$1` copies a group as is and `@1` translates it too.

To add a language, copy `lang/en.json` to a new file named with the language code (for example `fr.json`), set `"name"` (for example `"Français"`) and translate the values. Leave the keys alone. The language shows up in the language menu automatically.

## Building and releasing

`build/Build.ps1` makes a release, the same way on your PC and in CI. Run it with Windows PowerShell 5.1:

```powershell
powershell -ExecutionPolicy Bypass -File build\Build.ps1
```

It runs `tests/Run-Tests.ps1` (if present) and stops if it fails, takes the **committed** files (`git archive HEAD`), and compiles with the C# compiler that ships with Windows (.NET Framework 4.8), so there is nothing to install:

- `OptiEleven.exe`, the launcher (`launcher/Launcher.cs`). It asks for administrator and runs `OptiEleven.ps1` from its folder inside its own process. No hidden `powershell.exe`, no encoded command, nothing embedded.
- `native/OptiEleven.Native.dll`, the `$GpSource` block of `OptiEleven.ps1`, and `native/OptiEleven-Apps.exe`, the app installer stub (`assets/installer.cs`). Users' PCs load these instead of compiling. Each carries the hash of its source; if the source changed, the panel compiles it as before, which is also what happens in a git checkout.

Then it adds `LICENSE` and `THIRD-PARTY.md`, signs with `build/Sign.ps1`, and writes `dist/OptiEleven.zip` and `dist/SHA256SUMS.txt`.

`.github/workflows/release.yml` runs the same script on `windows-latest` for pushes to `v2`, manual runs and tags `v*`. Every run uploads the zip and the sums as a workflow artifact. A tag also creates a **draft** release with both files and the hashes in the notes; review it and publish it by hand.

### Signing

Signing is optional. With no secrets the build prints `signing skipped (no certificate)` and succeeds, so forks work. `Sign.ps1` signs the `.exe`, `.dll` and `.ps1` files with `signtool` (SHA256 and a timestamp) and fails unless Windows reports every signature as Valid. The app installer stub is left unsigned, because the panel appends each user's app list to it. Set these repository secrets for one mode:

- **Azure Artifact Signing** (formerly Trusted Signing), the realistic option: `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT`, `AZURE_SIGNING_PROFILE`, plus `AZURE_TENANT_ID`, `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET` for an app registration with the *Trusted Signing Certificate Profile Signer* role. The workflow installs Microsoft's signing client from NuGet.
- **PFX**: `SIGN_PFX_BASE64` (the .pfx as base64) and `SIGN_PFX_PASSWORD`. Since June 2023 public CAs only issue code-signing keys on hardware (a token or HSM), so you can't get a new public .pfx; this mode is for older certificates or a private CA.

Optional: `SIGN_TIMESTAMP_URL`. Once releases are signed, the one-line launcher refuses scripts whose signature isn't valid.

- **SignPath Foundation** (the one this project uses): free signing for open source, done by SignPath's service, not by `Sign.ps1`. On tags `v*` the workflow uploads the unsigned zip, sends a signing request and waits, then replaces the zip with the signed one, checks every signature and rewrites `SHA256SUMS.txt`. Set the secret `SIGNPATH_API_TOKEN` and the repository variable `SIGNPATH_ORGANIZATION_ID`. Optional variables: `SIGNPATH_PROJECT_SLUG` (default `OptiEleven`), `SIGNPATH_SIGNING_POLICY` (default `release-signing`) and `SIGNPATH_ARTIFACT_CONFIGURATION` (default `initial`). The artifact configuration to paste into SignPath is in [.signpath/artifact-configuration.xml](.signpath/artifact-configuration.xml).

## Style

- PowerShell 5.1 compatible (no `??`, `?:` or `&&`).
- Save `.ps1` files as UTF-8 **with BOM**, or PowerShell 5.1 breaks accented characters.
- Keep UI text short and plain. Say what a setting does and what it costs.
