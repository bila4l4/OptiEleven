# Changelog

What changed in each release. The full notes and downloads are on the [releases page](https://github.com/bila4l4/OptiEleven/releases).

## Unreleased

- Teal logo everywhere: the exe and window icon, the website and the README.
- The window icon is set again; a merged line in 2.0 skipped it.
- Code comments are in English.
- Release pipeline: optional signing through SignPath Foundation on tags, builds on `main`.
- Website opens in English by default.

## 2.0.0 (2026-11-27)

OptiEleven grows from a gaming optimizer into a Windows 11 toolkit.

- New Home: a 0-100 PC health ring (privacy, performance, space, startup) and a **Free up memory** button that frees RAM and temp files without changing any tweak.
- New design: native Fluent look with Mica, light and dark, Segoe UI Variable and Fluent icons, a teal accent and shorter text everywhere.
- New menu by category (Optimize, Privacy, Clean up, Install, Network, Repair, System) and **Ctrl+K** search.
- **History**: every change with its date and what it changed before and after, with undo per tweak. Tweaks applied with 1.x stay undoable.
- `OptiEleven.exe` launcher and prebuilt native code; the one-line install checks the zip against `SHA256SUMS.txt`.
- Each tool and each tweak is its own file, loaded on start.
- Automated tests and a release pipeline on GitHub Actions.
- New website and command: `irm optieleven.app | iex`.

## 1.9.0 (2026-11-25)

- Disk space: select one or several files and folders (Ctrl/Shift), and act on them from a toolbar or right-click menu: open, show in File Explorer, copy path, terminal, properties, refresh, move to Recycle Bin, delete permanently.
- System folders and whole drives can't be deleted from there.

## 1.8.0 (2026-11-25)

- Disk space as a WinDirStat-style tree with a share bar, percent, size, files and date, plus an extensions panel.
- Scans a full C: drive in about 15 seconds without admin rights.

## 1.7.0 (2026-11-25)

- New Disk space page: the folders and files that take the most space on each drive.

## 1.6.1 (2026-11-25)

- Cleanup and Boost FPS show a progress window inside the panel.
- Fixed: updating with the panel open could leave the installation half-deleted.
- Fixed: progress bars stayed empty until the end.

## 1.6.0 (2026-11-25)

- Cleanup deletes in the background with live progress.
- Loading spinners for pages that take a moment to open.

## 1.5.2 (2026-11-25)

- Fixed: Cleanup crashed after freeing more than 2 GB.
- An error inside a button no longer closes the panel.

## 1.5.1 (2026-11-24)

- The taskbar shows the OptiEleven logo instead of the PowerShell icon.
- Fixed an error when closing with the booster still on.

## 1.5.0 (2026-11-24)

- New Home page, Expert mode (formerly Pro view), "Tweaks" naming in English and category filters that wrap.

## 1.4.0 (2026-11-24)

- Redesign with a violet theme, the Inter font and animations.
- Create installer builds a single `.exe`, like Ninite.
- More cleanup items: browser, Discord and Steam caches and Windows logs.
- Fixed: Cleanup never finished measuring sizes in 1.2 and 1.3.

## 1.3.0 (2026-11-24)

- Install apps lists 107 apps, 98 with their own logo, including a new Peripherals group.

## 1.2.0 (2026-11-24)

- Opens in about 3 s instead of 8-12 and no longer freezes.
- Install apps with search, install-all and a one-file installer.
- Network speed test powered by speed.cloudflare.com.

## 1.1.0 (2026-11-24)

- Pro view, more color per category, and Recommended / Advanced buttons with a start notice.

## 1.0.0 (2026-11-23)

- First release: 60 reversible tweaks in 8 categories with presets and a preview of every change, Boost FPS, Game Booster, My games, Install apps, Startup, Cleanup, Network, Repair, Hardware and profiles.
