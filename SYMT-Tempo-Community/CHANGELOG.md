# Changelog

## 0.5.1 — About dialog / build refinement
- Replaced embedded black-matte logo with SYMT supplied transparent artwork.
- Matched PictureBox background to About dialog.
- Added Build/Build-Setup.cmd for one-step Inno Setup compilation on Windows.
- Version and EXE installer output name updated to 0.5.1.

# Changelog

## 0.4.0 — workflow & UI redesign

### Workflow
- **One-step start:** a quick-add/search box replaces the two pop-up input boxes. Type `Client: Task` and press Enter to create and start in one go. Typing filters existing tasks.
- **Real pause:** Pause now keeps the task in the Now card, and Space resumes it. Stop clears it. (In v0.3, Pause and Stop did the same thing.)
- **Per-row play/pause:** hover a task and click ▶. Right-click for Rename, Change project, Add time, Archive or Delete.
- **Log tab:** browse any day's entries, then edit, delete, add notes or continue a task. Manual and edited entries are labelled.
- **Adjust start time** of the running timer, for when you started work before starting the timer.
- **Add-time editor:** presets (15m to 2h, Until now), flexible time input (`930`, `9:30`, `9.30`), live duration, and warnings for overlaps, future end times and entries over 12 h. Entries can span midnight.
- **Export dialog:** choose a range (Today / This week / Last week / Month / All) and a format (Detailed CSV, Summary CSV, JSON). A live preview shows the entry count and total.
- **Tray and orb quick menu:** shows the current status and offers Pause, Stop, a *Switch to* list of recent tasks, Add time and Export.
- **Global shortcut** `Ctrl+Alt+T` opens or collapses the panel from any app. There is a full keyboard map (F1).
- **Archive** tasks to hide them without losing history. Search still finds archived tasks.

### Reliability
- **Idle and sleep detection** with a "Welcome back" choice: discard the idle time, keep it, or stop.
- **Crash recovery:** the running session is check-pointed every 30 s and offered back on the next launch.
- Rolling daily backups (14 days), atomic saves via `File.Replace`, and a single-instance guard.
- Totals now split correctly across midnight, and closed-interval totals are cached so the per-second refresh stays cheap.
- Event-handler errors go to `Data\error.log` instead of the WinForms crash dialog.
- Windows shutdown closes the running interval cleanly.

### Design
- **New dark theme:** custom-painted controls, rounded cards, anti-aliased round buttons, and a dark tooltip, menu and scrollbar style.
- **Round orb:** a progress ring sweeps once an hour and shows the live elapsed time. It turns amber when paused. It snaps to screen edges, and the panel opens towards the centre of the screen.
- **Now card:** project colour chip, today's total for the task in large type, session length and start time, and a status bar coloured green, amber or grey.
- **Today and This week** totals, with a progress bar towards the daily target.
- **Stable project colours** on every row and in the log.
- **Auto-collapse** when you click away, with a pin to keep the panel open.
- Layout scales with DPI. Windows 11 gets rounded corners.
- **Settings dialog:** idle threshold, daily target, launch view, always on top, hotkey, launch at sign-in, show archived tasks.

### Code
- Split into `Lib\Tempo.Core.ps1` (no UI, testable), `Tempo.ps1` (UI) and the optional `Lib\Tempo.Native.cs`.
- Data schema 2 is a backwards-compatible superset of schema 1.

## 0.3.0
Floating icon and compact panel, tray menu, manual interval dialog, CSV/JSON export.

## 0.5.1 — SYMT branding and Windows installer
- Supplied SYMT artwork, window/tray icon and About branding.
- Website, terms, personal-use licence, trademark notice and legal disclaimer.
- Per-user installation wizard and uninstaller; GitHub source project.
