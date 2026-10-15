# SYMT Tempo — development notes (v0.5)

## Architecture
```
Launch-SYMT-Tempo.vbs   hidden-console launcher (powershell.exe -STA -ExecutionPolicy Bypass)
Tempo.ps1               WinForms UI: theme, widgets, orb/panel, lists, dialogs, tray, timer loop
Lib/Tempo.Core.ps1      state, persistence, time maths, queries, export rows (no UI types)
Lib/Tempo.Native.cs     optional P/Invoke helpers, compiled with Add-Type at start-up
```
`Tempo.Core.ps1` is dot-sourced, so its `$script:` state lives in the UI script's scope. You can test it headless, including under PowerShell 7 on Linux:
```powershell
. .\Lib\Tempo.Core.ps1; Initialize-Store $PWD; Load-Data; Get-TodayTotal
```

## Data model (schemaVersion 2)
```json
{ "schemaVersion": 2, "tasks": [ { "id", "name", "project", "created", "lastUsed", "archived" } ],
  "intervals": [ { "id", "taskId", "start", "end", "note", "source": "timer|manual|edited|recovered" } ] }
```
- Times are ISO-8601 round-trip strings with an offset (`ToString('o')`).
- `settings.json` holds UI preferences, and `session.json` holds the crash-recovery checkpoint `{taskId, start, lastSeen}` while a timer runs.
- Save sequence: write `*.tmp`, call `File.Replace` (which keeps `*.bak`), then take a daily snapshot in `Backups/` (14 kept).

## Timer state machine
```
idle ──start(task)──▶ running ──pause──▶ paused ──resume──▶ running
  ▲                     │  └──start(other)──▶ running(other)  │
  └───────stop──────────┴────────────────stop─────────────────┘
```
Each running → (paused | stopped | switched) transition closes one interval.

## UI conventions
- All pixel geometry goes through `P()` (DPI scale). Fonts are in points, so they scale on their own.
- Buttons, segments and toggles are painted `Label`s: anti-aliased, with hover state and no focus rectangles. `OnClick` blocks receive the control as `$args[0]`.
- Dialogs keep their state in `$dialog.Tag` (a hashtable). Handlers reach it through `$sender.FindForm().Tag`, because PowerShell event scriptblocks are not closures.
- **PowerShell variable names ignore case.** Theme, fonts and glyphs are `$TH`, `$FN` and `$GL`, so locals such as `$t`, `$f` and `$g` cannot shadow them. Event handlers run in a dynamic scope, so script-level geometry uses the `$script:` prefix.
- Never compare `KeyCode` in a string `switch`. Use `-eq`, because `Keys.Enter` stringifies as `Return`.
- Save `.ps1` files as **UTF-8 with BOM**. Windows PowerShell 5.1 reads BOM-less files as ANSI, which garbles `·`, `–` and `‹ ›`.

## Ideas for v0.5
Weekly view with a per-project bar chart; tags and billable flag; rounding rules on export (6/15 min); calendar import; a pomodoro mode on the orb ring; an optional compiled single-file EXE.

## v0.5 packaging
Use Build/Install-SYMT-Tempo.ps1 (via Install-SYMT-Tempo.vbs) on Windows for a per-user install; uninstall script is included. An optional Inno Setup definition is under Build. Run tests from tests/ on Windows PowerShell 5.1 before releasing. The PowerShell application has not been runtime tested here.
