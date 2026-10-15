# SYMT Tempo v0.5 - core: storage, time maths, queries.
# No WinForms dependency: this file can be dot-sourced and tested on its own.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+.

$script:TempoVersion = '0.5.1'
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture

# ---------------------------------------------------------------- state
$script:tasks     = New-Object 'System.Collections.Generic.List[object]'
$script:intervals = New-Object 'System.Collections.Generic.List[object]'
$script:settings  = $null
$script:active    = $null   # taskId currently recording
$script:started   = $null   # [datetime] start of the running interval
$script:pausedTask = $null  # taskId kept in the "now" card while paused
$script:pausedAt  = $null
$script:lastTask  = $null
$script:cache     = @{ day = [datetime]::MinValue; byTask = @{}; dayTotal = 0.0; weekTotal = 0.0 }

function Initialize-Store([string]$root) {
    $script:dataDir = Join-Path $root 'Data'
    $script:backupDir = Join-Path $script:dataDir 'Backups'
    foreach ($d in @($script:dataDir, $script:backupDir)) {
        if (!(Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
    }
    $script:dataFile = Join-Path $script:dataDir 'tempo-data.json'
    $script:settingsFile = Join-Path $script:dataDir 'settings.json'
    $script:sessionFile = Join-Path $script:dataDir 'session.json'
}

# ---------------------------------------------------------------- dates
function ConvertTo-Dt($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [datetime]) {
        if ($value.Kind -eq [System.DateTimeKind]::Utc) { return $value.ToLocalTime() }
        return $value
    }
    return [datetime]::Parse([string]$value, $script:Inv, [System.Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
}
function ConvertTo-Iso([datetime]$dt) { return $dt.ToString('o', $script:Inv) }
function Get-WeekStart([datetime]$day) {
    $d = $day.Date
    $offset = (([int]$d.DayOfWeek) + 6) % 7   # Monday = 0
    return $d.AddDays(-$offset)
}
function Get-Overlap([datetime]$from, [datetime]$to, [datetime]$rangeStart, [datetime]$rangeEnd) {
    $a = if ($from -gt $rangeStart) { $from } else { $rangeStart }
    $b = if ($to -lt $rangeEnd) { $to } else { $rangeEnd }
    if ($b -le $a) { return 0.0 }
    return ($b - $a).TotalSeconds
}

# ---------------------------------------------------------------- formatting
function Format-Clock([double]$seconds) {
    if ($seconds -lt 0) { $seconds = 0 }
    $s = [int][math]::Floor($seconds)
    return ('{0}:{1:00}:{2:00}' -f [int][math]::Floor($s / 3600), [int][math]::Floor(($s % 3600) / 60), ($s % 60))
}
function Format-Short([double]$seconds) {
    if ($seconds -lt 0) { $seconds = 0 }
    $m = [int][math]::Floor($seconds / 60)
    if ($m -lt 1) { if ($seconds -lt 1) { return '0m' } return ('{0}s' -f [int][math]::Floor($seconds)) }
    if ($m -lt 60) { return ('{0}m' -f $m) }
    return ('{0}h {1:00}m' -f [int][math]::Floor($m / 60), ($m % 60))
}
function Format-Compact([double]$seconds) {
    # orb read-out: 12:04 under an hour (mm:ss), 1:24 after (h:mm)
    $s = [int][math]::Floor([math]::Max(0, $seconds))
    if ($s -lt 3600) { return ('{0}:{1:00}' -f [int][math]::Floor($s / 60), ($s % 60)) }
    return ('{0}:{1:00}' -f [int][math]::Floor($s / 3600), [int][math]::Floor(($s % 3600) / 60))
}

# ---------------------------------------------------------------- settings
function Get-DefaultSettings {
    return [ordered]@{
        orbX = -1; orbY = -1
        topMost = $true
        pinned = $false
        idleMinutes = 10
        dailyTargetHours = 7.5
        startView = 'orb'          # orb | panel | tray
        hotkey = $true
        showArchived = $false
        lastTaskId = $null
        tab = 'tasks'
    }
}
function Load-Settings {
    $s = Get-DefaultSettings
    if (Test-Path -LiteralPath $script:settingsFile) {
        try {
            $obj = Get-Content -LiteralPath $script:settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) { if ($s.Contains($p.Name)) { $s[$p.Name] = $p.Value } }
        } catch { }
    }
    $script:settings = $s
    return $s
}
function Save-Settings {
    if ($null -eq $script:settings) { return }
    Write-FileAtomic $script:settingsFile ($script:settings | ConvertTo-Json -Depth 4) $false
}

# ---------------------------------------------------------------- persistence
function Write-FileAtomic([string]$path, [string]$text, [bool]$keepBackup) {
    $tmp = "$path.tmp"
    [System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $path) {
        $bak = if ($keepBackup) { "$path.bak" } else { $null }
        try { [System.IO.File]::Replace($tmp, $path, $bak) }
        catch { Copy-Item -LiteralPath $tmp -Destination $path -Force; Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    } else {
        [System.IO.File]::Move($tmp, $path)
    }
}
function New-TaskObject([string]$name, [string]$project) {
    $now = ConvertTo-Iso (Get-Date)
    return [pscustomobject]@{ id = [guid]::NewGuid().ToString(); name = $name; project = $project; created = $now; lastUsed = $now; archived = $false }
}
function Normalize-Task($t) {
    $o = [pscustomobject]@{
        id = [string]$t.id
        name = [string]$t.name
        project = if ([string]::IsNullOrWhiteSpace([string]$t.project)) { 'General' } else { [string]$t.project }
        created = if ($t.created) { ConvertTo-Iso (ConvertTo-Dt $t.created) } else { $null }
        lastUsed = if ($t.lastUsed) { ConvertTo-Iso (ConvertTo-Dt $t.lastUsed) } else { $null }
        archived = [bool]$t.archived
    }
    return $o
}
function Normalize-Interval($i) {
    $src = [string]$i.source
    if ([string]::IsNullOrEmpty($src)) { $src = if ([string]$i.note -eq 'Manual entry') { 'manual' } else { 'timer' } }
    $note = [string]$i.note
    if ($note -eq 'Automatic tracking' -or $note -eq 'Manual entry') { $note = '' }   # v0.1-v0.3 placeholder notes
    return [pscustomobject]@{
        id = if ($i.id) { [string]$i.id } else { [guid]::NewGuid().ToString() }
        taskId = [string]$i.taskId
        start = ConvertTo-Iso (ConvertTo-Dt $i.start)
        end = ConvertTo-Iso (ConvertTo-Dt $i.end)
        note = $note
        source = $src
    }
}
function Load-Data {
    $script:tasks.Clear(); $script:intervals.Clear()
    if (Test-Path -LiteralPath $script:dataFile) {
        $raw = Get-Content -LiteralPath $script:dataFile -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $obj = $raw | ConvertFrom-Json
            foreach ($t in @($obj.tasks)) { if ($null -ne $t -and $t.id) { $script:tasks.Add((Normalize-Task $t)) } }
            foreach ($i in @($obj.intervals)) {
                if ($null -eq $i -or -not $i.start -or -not $i.end) { continue }
                $n = Normalize-Interval $i
                if ((ConvertTo-Dt $n.end) -gt (ConvertTo-Dt $n.start)) { $script:intervals.Add($n) }
            }
        }
    }
    # tasks from v0.3 have no lastUsed: derive it from their latest interval
    $latest = @{}
    foreach ($i in $script:intervals) {
        if (-not $latest.ContainsKey($i.taskId) -or $latest[$i.taskId] -lt $i.end) { $latest[$i.taskId] = $i.end }
    }
    foreach ($t in $script:tasks) {
        if (-not $t.lastUsed) { $t.lastUsed = if ($latest.ContainsKey($t.id)) { $latest[$t.id] } elseif ($t.created) { $t.created } else { '2000-01-01T00:00:00.0000000+00:00' } }
        if (-not $t.created) { $t.created = $t.lastUsed }
    }
    Update-Cache -Force
}
function Save-Data {
    $payload = [ordered]@{
        schemaVersion = 2
        app = "SYMT Tempo $script:TempoVersion"
        saved = ConvertTo-Iso (Get-Date)
        tasks = $script:tasks.ToArray()
        intervals = $script:intervals.ToArray()
    }
    Write-FileAtomic $script:dataFile ($payload | ConvertTo-Json -Depth 6) $true
    Invoke-DailyBackup
    Update-Cache -Force
}
function Invoke-DailyBackup {
    try {
        $target = Join-Path $script:backupDir ('tempo-data-{0}.json' -f (Get-Date -Format 'yyyyMMdd'))
        if (!(Test-Path -LiteralPath $target) -and (Test-Path -LiteralPath $script:dataFile)) {
            Copy-Item -LiteralPath $script:dataFile -Destination $target
            Get-ChildItem -LiteralPath $script:backupDir -Filter 'tempo-data-*.json' | Sort-Object Name -Descending | Select-Object -Skip 14 | Remove-Item -Force
        }
    } catch { }
}

# ---------------------------------------------------------------- crash-safe running session
function Write-Session {
    if ($null -eq $script:active) { Clear-Session; return }
    $o = [ordered]@{ taskId = $script:active; start = ConvertTo-Iso $script:started; lastSeen = ConvertTo-Iso (Get-Date) }
    try { Write-FileAtomic $script:sessionFile ($o | ConvertTo-Json) $false } catch { }
}
function Clear-Session { if (Test-Path -LiteralPath $script:sessionFile) { Remove-Item -LiteralPath $script:sessionFile -Force -ErrorAction SilentlyContinue } }
function Read-Session {
    if (!(Test-Path -LiteralPath $script:sessionFile)) { return $null }
    try {
        $o = Get-Content -LiteralPath $script:sessionFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $o.taskId -or -not $o.start) { return $null }
        return [pscustomobject]@{ taskId = [string]$o.taskId; start = (ConvertTo-Dt $o.start); lastSeen = (ConvertTo-Dt $o.lastSeen) }
    } catch { return $null }
}

# ---------------------------------------------------------------- tasks
function Find-Task([string]$id) {
    if ([string]::IsNullOrEmpty($id)) { return $null }
    foreach ($t in $script:tasks) { if ($t.id -eq $id) { return $t } }
    return $null
}
function Get-TaskName([string]$id) { $t = Find-Task $id; if ($null -eq $t) { return '(deleted task)' }; return $t.name }
function Get-TaskProject([string]$id) { $t = Find-Task $id; if ($null -eq $t) { return '' }; return $t.project }
function Get-Projects {
    return @($script:tasks | ForEach-Object { $_.project } | Sort-Object -Unique)
}
function Split-QuickAdd([string]$text, [string]$defaultProject = 'General') {
    # "Project: Task" or "Project / Task" (delimiter must be followed by a space); otherwise the whole text is the task name
    $t = $text.Trim()
    $m = [regex]::Match($t, '^\s*([^:/]{1,60}?)\s*(?::\s|\s/\s)\s*(.+)$')
    if ($m.Success -and $m.Groups[2].Value.Trim()) {
        return @{ project = $m.Groups[1].Value.Trim(); name = $m.Groups[2].Value.Trim() }
    }
    return @{ project = $defaultProject; name = $t }
}
function Find-TaskByName([string]$name, [string]$project) {
    foreach ($t in $script:tasks) {
        if ($t.name -ieq $name -and $t.project -ieq $project) { return $t }
    }
    return $null
}
function Add-Task([string]$name, [string]$project) {
    if ([string]::IsNullOrWhiteSpace($project)) { $project = 'General' }
    $existing = Find-TaskByName $name.Trim() $project.Trim()
    if ($null -ne $existing) { if ($existing.archived) { $existing.archived = $false; Save-Data }; return $existing }
    $t = New-TaskObject $name.Trim() $project.Trim()
    $script:tasks.Add($t)
    Save-Data
    return $t
}
function Search-Tasks([string]$query, [bool]$includeArchived = $false) {
    $tokens = @(([string]$query).ToLowerInvariant().Split(@(' ', ':', '/'), [System.StringSplitOptions]::RemoveEmptyEntries))
    $result = foreach ($t in $script:tasks) {
        if ($t.archived -and -not $includeArchived -and $tokens.Count -eq 0) { continue }
        $hay = ($t.project + ' ' + $t.name).ToLowerInvariant()
        $ok = $true
        foreach ($tok in $tokens) { if (-not $hay.Contains($tok)) { $ok = $false; break } }
        if ($ok) { $t }
    }
    # running/paused task first, then most recently used
    $pin = if ($script:active) { $script:active } else { $script:pausedTask }
    return @($result | Sort-Object @{ Expression = { if ($_.id -eq $pin) { 0 } else { 1 } } }, @{ Expression = { [bool]$_.archived } }, @{ Expression = { $_.lastUsed }; Descending = $true })
}
function Get-RecentTasks([int]$count = 6) {
    return @($script:tasks | Where-Object { -not $_.archived } | Sort-Object @{ Expression = { $_.lastUsed }; Descending = $true } | Select-Object -First $count)
}
function Touch-Task([string]$id) { $t = Find-Task $id; if ($t) { $t.lastUsed = ConvertTo-Iso (Get-Date) } }
function Remove-Task([string]$id) {
    $t = Find-Task $id
    if ($null -eq $t) { return }
    [void]$script:tasks.Remove($t)
    foreach ($i in @($script:intervals | Where-Object { $_.taskId -eq $id })) { [void]$script:intervals.Remove($i) }
    Save-Data
}
function Get-TaskIntervalCount([string]$id) { return @($script:intervals | Where-Object { $_.taskId -eq $id }).Count }

# ---------------------------------------------------------------- intervals
function Add-Interval([string]$taskId, [datetime]$from, [datetime]$to, [string]$note = '', [string]$source = 'timer') {
    if ($to -le $from) { return $null }
    if (($to - $from).TotalSeconds -lt 1) { return $null }
    $i = [pscustomobject]@{ id = [guid]::NewGuid().ToString(); taskId = $taskId; start = (ConvertTo-Iso $from); end = (ConvertTo-Iso $to); note = $note; source = $source }
    $script:intervals.Add($i)
    Save-Data
    return $i
}
function Find-Interval([string]$id) { foreach ($i in $script:intervals) { if ($i.id -eq $id) { return $i } }; return $null }
function Remove-Interval([string]$id) { $i = Find-Interval $id; if ($i) { [void]$script:intervals.Remove($i); Save-Data } }
function Set-Interval([string]$id, [string]$taskId, [datetime]$from, [datetime]$to, [string]$note) {
    $i = Find-Interval $id
    if ($null -eq $i -or $to -le $from) { return $false }
    $i.taskId = $taskId; $i.start = ConvertTo-Iso $from; $i.end = ConvertTo-Iso $to; $i.note = $note
    if ($i.source -eq 'timer') { $i.source = 'edited' }
    Save-Data
    return $true
}
function Get-Overlaps([datetime]$from, [datetime]$to, [string]$exceptId) {
    $n = 0
    foreach ($i in $script:intervals) {
        if ($i.id -eq $exceptId) { continue }
        if ((Get-Overlap (ConvertTo-Dt $i.start) (ConvertTo-Dt $i.end) $from $to) -gt 59) { $n++ }
    }
    if ($script:active -and $null -ne $script:started -and (Get-Overlap $script:started (Get-Date) $from $to) -gt 59) { $n++ }
    return $n
}

# ---------------------------------------------------------------- running timer
function Start-Task([string]$id) {
    if ([string]::IsNullOrEmpty($id) -or $null -eq (Find-Task $id)) { return }
    if ($script:active -eq $id) { return }
    Stop-Recording
    $script:active = $id
    $script:started = Get-Date
    $script:pausedTask = $null; $script:pausedAt = $null
    $script:lastTask = $id
    $t = Find-Task $id; $t.lastUsed = ConvertTo-Iso $script:started; if ($t.archived) { $t.archived = $false }
    if ($script:settings) { $script:settings.lastTaskId = $id }
    Save-Data
    Write-Session
}
function Stop-Recording([Nullable[datetime]]$at = $null) {
    # closes the running interval (if any); does not touch paused state
    if ($null -ne $script:active -and $null -ne $script:started) {
        $end = if ($null -ne $at) { [datetime]$at } else { Get-Date }
        [void](Add-Interval $script:active $script:started $end '' 'timer')
    }
    $script:active = $null; $script:started = $null
    Clear-Session
}
function Pause-Task {
    if ($null -eq $script:active) { return }
    $id = $script:active
    Stop-Recording
    $script:pausedTask = $id; $script:pausedAt = Get-Date
}
function Resume-Task {
    $id = if ($script:pausedTask) { $script:pausedTask } else { $script:lastTask }
    if ($id -and (Find-Task $id)) { Start-Task $id }
}
function Stop-Task {
    Stop-Recording
    $script:pausedTask = $null; $script:pausedAt = $null
}
function Get-RunningSeconds { if ($null -ne $script:started) { return ((Get-Date) - $script:started).TotalSeconds }; return 0.0 }

# ---------------------------------------------------------------- totals (closed intervals are cached; the running one is added live)
function Update-Cache([switch]$Force) {
    $today = (Get-Date).Date
    if (-not $Force -and $script:cache.day -eq $today) { return }
    $dayEnd = $today.AddDays(1)
    $weekStart = Get-WeekStart $today; $weekEnd = $weekStart.AddDays(7)
    $byTask = @{}; $dayTotal = 0.0; $weekTotal = 0.0
    foreach ($i in $script:intervals) {
        $a = ConvertTo-Dt $i.start; $b = ConvertTo-Dt $i.end
        if ($b -le $weekStart -or $a -ge $weekEnd) { continue }
        $weekTotal += Get-Overlap $a $b $weekStart $weekEnd
        $d = Get-Overlap $a $b $today $dayEnd
        if ($d -gt 0) {
            $dayTotal += $d
            if ($byTask.ContainsKey($i.taskId)) { $byTask[$i.taskId] += $d } else { $byTask[$i.taskId] = $d }
        }
    }
    $script:cache = @{ day = $today; byTask = $byTask; dayTotal = $dayTotal; weekTotal = $weekTotal }
}
function Get-LiveSeconds([datetime]$rangeStart, [datetime]$rangeEnd) {
    if ($null -eq $script:started) { return 0.0 }
    return Get-Overlap $script:started (Get-Date) $rangeStart $rangeEnd
}
function Get-TodayTotal {
    Update-Cache
    $t = (Get-Date).Date
    return $script:cache.dayTotal + (Get-LiveSeconds $t $t.AddDays(1))
}
function Get-WeekTotal {
    Update-Cache
    $w = Get-WeekStart (Get-Date)
    return $script:cache.weekTotal + (Get-LiveSeconds $w $w.AddDays(7))
}
function Get-TaskTodayTotal([string]$id) {
    Update-Cache
    $v = 0.0
    if ($script:cache.byTask.ContainsKey($id)) { $v = $script:cache.byTask[$id] }
    if ($script:active -eq $id) { $t = (Get-Date).Date; $v += Get-LiveSeconds $t $t.AddDays(1) }
    return $v
}

# ---------------------------------------------------------------- day log
function Get-DayEntries([datetime]$day, [bool]$includeRunning = $true) {
    $d0 = $day.Date; $d1 = $d0.AddDays(1)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($i in $script:intervals) {
        $a = ConvertTo-Dt $i.start; $b = ConvertTo-Dt $i.end
        if ($b -le $d0 -or $a -ge $d1) { continue }
        $rows.Add([pscustomobject]@{ id = $i.id; taskId = $i.taskId; from = $a; to = $b; seconds = ($b - $a).TotalSeconds; note = $i.note; source = $i.source; running = $false })
    }
    if ($includeRunning -and $null -ne $script:started) {
        $now = Get-Date
        if ($now -gt $d0 -and $script:started -lt $d1) {
            $rows.Add([pscustomobject]@{ id = $null; taskId = $script:active; from = $script:started; to = $now; seconds = ($now - $script:started).TotalSeconds; note = ''; source = 'timer'; running = $true })
        }
    }
    return @($rows | Sort-Object @{ Expression = { $_.from }; Descending = $true })
}
function Get-DayTotal([datetime]$day) {
    $d0 = $day.Date; $d1 = $d0.AddDays(1); $sum = 0.0
    foreach ($i in $script:intervals) { $sum += Get-Overlap (ConvertTo-Dt $i.start) (ConvertTo-Dt $i.end) $d0 $d1 }
    return $sum + (Get-LiveSeconds $d0 $d1)
}

# ---------------------------------------------------------------- export
function Get-RangeBounds([string]$range) {
    $today = (Get-Date).Date
    switch ($range) {
        'today'     { return @($today, $today.AddDays(1)) }
        'yesterday' { return @($today.AddDays(-1), $today) }
        'week'      { $w = Get-WeekStart $today; return @($w, $w.AddDays(7)) }
        'lastweek'  { $w = (Get-WeekStart $today).AddDays(-7); return @($w, $w.AddDays(7)) }
        'month'     { $m = New-Object DateTime($today.Year, $today.Month, 1); return @($m, $m.AddMonths(1)) }
        default     { return @([datetime]::MinValue, [datetime]::MaxValue) }
    }
}
function Get-ExportRows([datetime]$from, [datetime]$to) {
    $rows = foreach ($i in ($script:intervals | Sort-Object start)) {
        $a = ConvertTo-Dt $i.start; $b = ConvertTo-Dt $i.end
        if ($b -le $from -or $a -ge $to) { continue }
        $mins = [math]::Round(($b - $a).TotalMinutes, 2)
        [pscustomobject][ordered]@{
            date = $a.ToString('yyyy-MM-dd'); project = (Get-TaskProject $i.taskId); task = (Get-TaskName $i.taskId)
            start = $a.ToString('yyyy-MM-dd HH:mm:ss'); end = $b.ToString('yyyy-MM-dd HH:mm:ss')
            minutes = $mins; hours = [math]::Round($mins / 60, 2); note = $i.note; source = $i.source
        }
    }
    return @($rows)
}
function Get-SummaryRows([datetime]$from, [datetime]$to) {
    $acc = @{}
    foreach ($i in $script:intervals) {
        $s = Get-Overlap (ConvertTo-Dt $i.start) (ConvertTo-Dt $i.end) $from $to
        if ($s -le 0) { continue }
        if ($acc.ContainsKey($i.taskId)) { $acc[$i.taskId] += $s } else { $acc[$i.taskId] = $s }
    }
    $rows = foreach ($k in $acc.Keys) {
        [pscustomobject][ordered]@{ project = (Get-TaskProject $k); task = (Get-TaskName $k); hours = [math]::Round($acc[$k] / 3600, 2); minutes = [math]::Round($acc[$k] / 60, 1) }
    }
    return @($rows | Sort-Object project, task)
}

# ---------------------------------------------------------------- colour key for projects (stable per name)
function Get-ProjectIndex([string]$project, [int]$paletteSize = 8) {
    $h = 17
    foreach ($ch in ([string]$project).ToLowerInvariant().ToCharArray()) { $h = (($h * 31) + [int]$ch) % 1000003 }
    return [int]($h % $paletteSize)
}
