# SYMT Tempo — Community Edition

**Windows • Free personal use • Source available • © 2026 SYMT Limited**

> **Not open source:** the custom [community licence](LICENSE.txt) permits personal, non-commercial use and inspection/modification for personal use, but does not permit redistribution or commercial use. Read it before using or contributing.

**Website:** https://www.symt.co.uk  
**Current source:** v0.5.1 (Windows PowerShell 5.1 / WinForms)  
**Status:** community test release; Windows runtime and installer build require verification.

## What it does
A compact desktop floating task timer with system tray access, manual time correction, local task storage, idle handling, backups and CSV/JSON export.

## Quick start
1. Download the official portable package from **Releases** once the maintainer publishes it, or obtain this repository's source.
2. On Windows 10/11, run `Launch-SYMT-Tempo.vbs` from a **writable** folder.
3. Back up your `Data/` folder before upgrading. Personal data is intentionally excluded from Git.

## Build installer
Install Inno Setup 6 on Windows and run `Build\Build-Setup.cmd`. The output is an installer EXE, *not* a compiled standalone application. See `Build/README-INSTALLER.md`.

## Community and branding
Issues and pull requests are welcome under [CONTRIBUTING.md](CONTRIBUTING.md). The app includes SYMT's proprietary artwork for official branding; no independent permission to reuse it is granted. See [TRADEMARKS.md](TRADEMARKS.md). For the repository avatar, use a neutral stopwatch/timer icon rather than the full corporate logo.

## Privacy
The current application stores tasks locally, does not integrate with Gmail/Outlook/calendar, and does not transmit timesheet data to SYMT servers. Review exports before invoicing or reporting time.

---

## Version 0.5.1 usage notes

A floating, keyboard-first time tracker for Windows. Portable Windows PowerShell 5.1 / .NET WinForms — no installer, no third-party packages.

## Run
1. Extract the ZIP to a writable folder (not Program Files).
2. Double-click **Launch-SYMT-Tempo.vbs**. Windows may ask you to allow locally downloaded files (right-click › Properties › Unblock).
3. A round orb appears near the bottom-right of your screen. **Click** it to open the panel, **drag** it anywhere (it snaps to screen edges), **right-click** it for the quick menu.

## The 10-second workflow
| You want to… | Do this |
|---|---|
| Start a new task | Open the panel, type `DMC: Mirth channel review`, press **Enter**. The task is created *and* started. |
| Switch task | Type a few letters to filter, **Enter**. Or hover a row and click its ▶. Or right-click the orb › *Switch to*. |
| Take a break | **Space** (pause). **Space** again resumes the same task. |
| Finish | ■ in the card stops and clears the current task. |
| Forgot to start the timer | Click *“since 09:12”* under the clock and move the start back (−5m / −10m / −15m / −30m). |
| Forgot a whole block | **Log** tab › **+** (or **Ctrl+M**) and enter `9.30` → `11` (presets: 15m, 30m, 45m, 1h, 2h, Until now). |
| Fix an entry | **Log** tab › double-click the row. Edit, delete, change task, add a note. |
| Timesheet | **Ctrl+E** › range (Today / This week / Last week / Month / All) › Detailed CSV, Summary CSV or JSON. |

### Panel layout
- **Now card**: the current task, its total for today, the session length and start time, and Play/Pause and Stop buttons. The coloured bar on the left is green while tracking, amber while paused and grey when idle.
- **Today / This week**: running totals, with a progress bar towards your daily target (set it in Settings).
- **Tasks tab**: search and quick-add box above a list of tasks, most recently used first. The running task stays on top and each row shows today's time for that task.
- **Log tab**: a day-by-day list of time entries. Use ‹ › to change day, click the date to jump back to today, and **+** to add time. Manual and edited entries are labelled.

### Keyboard
`Enter` start · `Space` pause/resume · type to search · `Ctrl+Enter` force-create · `Ctrl+1/2` tabs · `←/→` change day (Log) · `F2` rename/edit · `Del` archive/delete · `Ctrl+M` add time · `Ctrl+E` export · `Ctrl+,` settings · `Esc` clear search, then collapse · **`Ctrl+Alt+T` toggles the panel from any app**.

## Things Tempo now does for you
- **Idle detection.** If you're away from the keyboard and mouse longer than the threshold (10 min by default) while a timer runs, Tempo asks on your return: discard the idle time and keep tracking, keep it, or stop at the moment you left. The same applies when the PC sleeps.
- **Crash recovery.** The running timer is check-pointed every 30 s. If Tempo or Windows dies, the next launch offers to save the time up to the last checkpoint, keep tracking, or discard it.
- **Backups.** Every save keeps `tempo-data.json.bak`, plus a daily snapshot in `Data\Backups` (the last 14 are kept).
- **Auto-collapse.** The panel folds back into the orb when you click elsewhere. Pin it (📌 in the header) to keep it open.

## Settings (⚙ or Ctrl+,)
Idle threshold (Off / 5 / 10 / 15 / 30 min) · Daily target (Off / 6h / 7h / 7.5h / 8h) · Launch view (orb / panel / tray only) · Always on top · Global shortcut · Launch at Windows sign-in · Show archived tasks · Open data folder.

## Upgrading from v0.1 – v0.3
Close the old version, then copy its whole `Data` folder next to `Tempo.ps1` in v0.5 (back it up first). v0.5 reads the `schemaVersion: 1` format and saves as `schemaVersion: 2`. The change only adds fields, so all your tasks and intervals carry over. The old placeholder notes (“Automatic tracking” / “Manual entry”) become a `source` field.

## Files
- `Launch-SYMT-Tempo.vbs`: launcher with no console window
- `Tempo.ps1`: user interface
- `Lib\Tempo.Core.ps1`: data, time maths, export. Has no UI dependencies, so it can be tested on its own.
- `Lib\Tempo.Native.cs`: optional helpers compiled at start-up (idle detection, global hotkey, dark menus, Windows 11 rounded corners, dark scrollbars). If your PC blocks compilation, Tempo still runs without those features.
- `Assets\Tempo.ico`: app and tray icon
- `Data\`: created on first run (`tempo-data.json`, `settings.json`, `Backups\`, `session.json` while tracking, `error.log` if something goes wrong)
- `CHANGELOG.md`, `DEVELOPMENT.md`, `LICENSE.txt`

## Limitations
This is a PowerShell script, not a compiled EXE. Only one copy runs at a time. Exports include completed entries only, so stop or pause the timer to include the current session. The orb's circular edge is a window region, so it isn't anti-aliased against the desktop. The panel is fixed at 344 × 556 px (scaled for DPI). This build has not been runtime-tested on Windows.

## v0.5 branding and licensing
Includes SYMT logo artwork supplied by the publisher, a branded Windows icon and About page, product website, Free Personal Use Edition terms, disclaimer and privacy notes. The installer variant stores program and data under the current user's LocalAppData; the portable variant stores data beside Tempo.ps1. Neither requires administrator rights.

**Copyright (c) 2026 SYMT Limited. All rights reserved.** Website: https://www.symt.co.uk. Read LICENSE.txt and TERMS.txt before using. This edition is not approved for commercial use under the draft licence.


## Build Windows installer EXE
Install Inno Setup 6 and run `Build\Build-Setup.cmd` from the extracted full-source directory. See `Build\README-INSTALLER.md`.
