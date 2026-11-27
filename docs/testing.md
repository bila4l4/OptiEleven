# Testing a fresh install

A checklist to install and try OptiEleven from scratch, as a new user would, without help. Write down anything that confuses you or takes more than a few seconds to find: that's what we want to fix.

## 1. Get a clean Windows 11

Pick one:

- **Windows Sandbox** (Windows 11 Pro): turn it on in *Turn Windows features on or off → Windows Sandbox*, then double-click [`tools/OptiEleven.wsb`](../tools/OptiEleven.wsb). It's a clean, throwaway Windows that is deleted when you close it. It has no winget, so skip the Install apps step there.
- **A virtual machine** (Hyper-V *Quick Create*, VirtualBox or VMware) with a fresh Windows 11.
- **A spare PC**. Create a restore point first.

Note the Windows edition, version and build (`winver`).

## 2. Install with the command

- [ ] Open **optieleven.app** in a browser. Is it clear what OptiEleven is and how to get it?
- [ ] Click **Copy**, right-click Start → **Terminal**, paste and press Enter.
- [ ] Accept the administrator prompt. The panel opens. How long did it take?
- [ ] Note any warning: SmartScreen, antivirus, execution policy. Write down the exact text.
- [ ] `%LOCALAPPDATA%\OptiEleven\app` now holds the app.

## 3. Install from the zip

- [ ] On optieleven.app, click **Download OptiEleven**.
- [ ] Check the zip against `SHA256SUMS.txt` from the [latest release](https://github.com/bila4l4/OptiEleven/releases/latest): `Get-FileHash .\OptiEleven.zip`.
- [ ] Extract it and double-click `OptiEleven.exe`. Note any SmartScreen or antivirus warning.
- [ ] If the exe is blocked, `OptiEleven.cmd` in the same folder opens it.

## 4. First look

- [ ] Home shows the greeting, the health ring and the four parts. Hover each part: does the detail make sense?
- [ ] Switch **EN / ES** and **light / dark**. Everything is translated and readable.
- [ ] Press **Ctrl+K** and search for "disk". The result opens Disk space.

## 5. Everyday tasks

Try each one without reading the README first.

- [ ] **Free up memory** on Home. A result shows below the button.
- [ ] **Apply and undo a tweak:** in **System → Interface**, turn on *Show file extensions*, press **Apply changes** and accept the restore point. File Explorer now shows extensions. Open **History**, press **Undo** and check they're hidden again.
- [ ] **Recommended preset:** press it, read the change sheet and press **Discard**. No need to apply.
- [ ] **Cleanup:** wait for the scan, then clean the ticked items. The freed size shows.
- [ ] **Disk space:** scan C:, expand a folder, and send a test file to the Recycle Bin.
- [ ] **Install apps:** install one small app, for example 7-Zip.
- [ ] **Network:** run the speed test.
- [ ] **Repair:** run *Rebuild the icon cache*.

## 6. Without administrator rights

- [ ] Run `OptiEleven.ps1` without elevation (or decline the prompt). The panel opens read-only and says so.
- [ ] **Restart as admin** opens it elevated.

## 7. Update

- [ ] Run the command again with the panel closed. It updates or says it's up to date.
- [ ] Run it with the panel open. It says to close the panel, and the app still works.

## 8. Remove it

- [ ] Undo the tweaks you want back (History, or turn them off and apply).
- [ ] Delete `%LOCALAPPDATA%\OptiEleven` and `%ProgramData%\OptiEleven`. Nothing else is left behind.

## Report what you found

Open an [issue](https://github.com/bila4l4/OptiEleven/issues/new/choose) with the Windows version, how you installed it, the step, what you expected and what happened. Turn on *Show technical details* to see the **Activity** log and paste the relevant lines.
