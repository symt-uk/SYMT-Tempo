# SYMT Tempo v0.5 - Windows PowerShell 5.1 / .NET WinForms portable edition
# UI layer. Data and time logic live in Lib\Tempo.Core.ps1; optional native helpers in Lib\Tempo.Native.cs.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch { }
# must be set before any control exists; handler is attached just before Application.Run
try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch { }
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'Lib\Tempo.Core.ps1')
Initialize-Store $root
Load-Settings | Out-Null

# Single instance: refuse to start twice (two copies would fight over the data file).
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\SYMT.Tempo.SingleInstance')
$gotMutex = $false
try { $gotMutex = $script:mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $gotMutex = $true }   # previous run crashed
if (-not $gotMutex) {
    [System.Windows.Forms.MessageBox]::Show('SYMT Tempo is already running. Look for the floating orb or the tray icon.', 'SYMT Tempo') | Out-Null
    return
}

$script:native = $false
try {
    Add-Type -TypeDefinition ([System.IO.File]::ReadAllText((Join-Path $root 'Lib\Tempo.Native.cs'))) -ReferencedAssemblies System.Windows.Forms, System.Drawing -ErrorAction Stop
    $script:native = $true
} catch { $script:native = $false }

# ====================================================================== theme
function RGB([int]$r, [int]$g, [int]$b, [int]$a = 255) { return [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }
$TH = @{
    Bg = RGB 13 18 28;      Card = RGB 21 28 42;     Field = RGB 27 35 51;   Hover = RGB 34 45 64
    Sel = RGB 30 42 62;     Line = RGB 40 52 72;     Text = RGB 232 238 246; Muted = RGB 140 156 180
    Faint = RGB 96 112 136; Accent = RGB 79 177 251; AccentHi = RGB 118 196 255
    Run = RGB 61 220 151;   RunTint = RGB 20 44 44;  Pause = RGB 245 184 75; Danger = RGB 240 100 110
    DangerTint = RGB 58 28 36
}
$PALETTE = @((RGB 79 177 251), (RGB 61 220 151), (RGB 245 184 75), (RGB 186 140 255), (RGB 255 128 170), (RGB 80 214 214), (RGB 255 150 90), (RGB 160 205 95))
function Get-ProjectColor([string]$p) { return $PALETTE[(Get-ProjectIndex $p $PALETTE.Count)] }

$gfx0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$script:S = [math]::Max(1.0, $gfx0.DpiX / 96.0)
$gfx0.Dispose()
function P([double]$v) { return [int][math]::Round($v * $script:S) }

$fams = @{}
foreach ($f in (New-Object System.Drawing.Text.InstalledFontCollection).Families) { $fams[$f.Name] = $true }
function Fnt([string]$family, [single]$size, [string]$style = 'Regular', [string]$fallback = 'Segoe UI') {
    $name = if ($fams.ContainsKey($family)) { $family } else { $fallback }
    return New-Object System.Drawing.Font($name, $size, [System.Drawing.FontStyle]$style)
}
$FN = @{
    Body = Fnt 'Segoe UI' 9; Small = Fnt 'Segoe UI' 8; SmallB = Fnt 'Segoe UI Semibold' 8
    Strong = Fnt 'Segoe UI Semibold' 9.5; Title = Fnt 'Segoe UI Semibold' 11; Brand = Fnt 'Segoe UI Semibold' 9.5
    Timer = Fnt 'Segoe UI Light' 25; Orb = Fnt 'Segoe UI Semibold' 9; Kbd = Fnt 'Consolas' 8.5
}
$mdl = $fams.ContainsKey('Segoe MDL2 Assets')
$FN.Icon = if ($mdl) { Fnt 'Segoe MDL2 Assets' 10 } else { Fnt 'Segoe UI Symbol' 10.5 }
$FN.IconLg = if ($mdl) { Fnt 'Segoe MDL2 Assets' 15 } else { Fnt 'Segoe UI Symbol' 15 }
$FN.IconSm = if ($mdl) { Fnt 'Segoe MDL2 Assets' 8 } else { Fnt 'Segoe UI Symbol' 8.5 }
function Glyph([int]$mdlCode, [int]$fallbackCode) { if ($mdl) { return [string][char]$mdlCode } return [string][char]$fallbackCode }
$GL = @{
    Play = Glyph 0xE768 0x25B6; Pause = Glyph 0xE769 0x23F8; Stop = Glyph 0xE71A 0x25A0; Add = Glyph 0xE710 0x002B
    Search = Glyph 0xE721 0x2315; More = Glyph 0xE712 0x22EF; Min = Glyph 0xE921 0x2013; Pin = Glyph 0xE718 0x25CB
    Pinned = Glyph 0xE840 0x25CF; Clock = Glyph 0xE823 0x25F7; Export = Glyph 0xE896 0x21E9; Settings = Glyph 0xE713 0x2699
    Back = Glyph 0xE76B 0x2039; Fwd = Glyph 0xE76C 0x203A; Close = Glyph 0xE711 0x2715; Watch = Glyph 0xE916 0x23F1
}

$TFF = [System.Windows.Forms.TextFormatFlags]
$TF_L = $TFF::Left -bor $TFF::VerticalCenter -bor $TFF::EndEllipsis -bor $TFF::NoPrefix -bor $TFF::SingleLine
$TF_R = $TFF::Right -bor $TFF::VerticalCenter -bor $TFF::NoPrefix -bor $TFF::SingleLine
$TF_C = $TFF::HorizontalCenter -bor $TFF::VerticalCenter -bor $TFF::NoPrefix -bor $TFF::SingleLine
$TF_WRAP = $TFF::Left -bor $TFF::Top -bor $TFF::WordBreak -bor $TFF::NoPrefix
$TR = [System.Windows.Forms.TextRenderer]

# ====================================================================== drawing helpers
$script:brushes = @{}; $script:pens = @{}
function Br([System.Drawing.Color]$c) {
    $k = $c.ToArgb()
    if (-not $script:brushes.ContainsKey($k)) { $script:brushes[$k] = New-Object System.Drawing.SolidBrush($c) }
    return $script:brushes[$k]
}
function Pn([System.Drawing.Color]$c, [single]$w = 1) {
    $k = '{0}|{1}' -f $c.ToArgb(), $w
    if (-not $script:pens.ContainsKey($k)) { $p = New-Object System.Drawing.Pen($c, $w); $p.StartCap = 'Round'; $p.EndCap = 'Round'; $script:pens[$k] = $p }
    return $script:pens[$k]
}
function Rc([double]$x, [double]$y, [double]$w, [double]$h) { return New-Object System.Drawing.Rectangle([int]$x, [int]$y, [int]$w, [int]$h) }
function RcF([double]$x, [double]$y, [double]$w, [double]$h) { return New-Object System.Drawing.RectangleF([single]$x, [single]$y, [single]$w, [single]$h) }
function New-RoundPath([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = [math]::Min($r, [math]::Min($w, $h) / 2)
    if ($r -le 0.5) { $p.AddRectangle((RcF $x $y $w $h)); return $p }
    $d = [single]($r * 2)
    $p.AddArc([single]$x, [single]$y, $d, $d, 180, 90)
    $p.AddArc([single]($x + $w - $d), [single]$y, $d, $d, 270, 90)
    $p.AddArc([single]($x + $w - $d), [single]($y + $h - $d), $d, $d, 0, 90)
    $p.AddArc([single]$x, [single]($y + $h - $d), $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}
function Fill-Round($g, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r, [System.Drawing.Color]$c) {
    $p = New-RoundPath $x $y $w $h $r; $g.FillPath((Br $c), $p); $p.Dispose()
}
function Stroke-Round($g, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r, [System.Drawing.Color]$c) {
    $p = New-RoundPath $x $y $w $h $r; $g.DrawPath((Pn $c 1), $p); $p.Dispose()
}
function Set-RoundRegion($ctl, [double]$r) {
    $p = New-RoundPath 0 0 $ctl.Width $ctl.Height $r
    $ctl.Region = New-Object System.Drawing.Region($p); $p.Dispose()
}
function Txt($g, [string]$s, $font, [System.Drawing.Rectangle]$r, [System.Drawing.Color]$c, $flags) {
    $TR::DrawText($g, $s, $font, $r, $c, $flags)
}
function Measure-Str([string]$s, $font) { return $TR::MeasureText($s, $font, (New-Object System.Drawing.Size(10000, 1000)), ($TFF::NoPrefix -bor $TFF::SingleLine)) }
function Enable-DoubleBuffer($ctl) {
    $pi = $ctl.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance')
    if ($pi) { $pi.SetValue($ctl, $true, $null) }
}
function Set-Text($ctl, [string]$v) { if ($ctl.Text -ne $v) { $ctl.Text = $v } }

# ====================================================================== tooltips (owner drawn, dark)
$script:tips = New-Object System.Windows.Forms.ToolTip
$script:tips.OwnerDraw = $true
$script:tips.InitialDelay = 450
$script:tips.Add_Popup({ param($s, $e)
    $sz = $TR::MeasureText($s.GetToolTip($e.AssociatedControl), $FN.Small)
    $e.ToolTipSize = New-Object System.Drawing.Size(($sz.Width + (P 16)), ($sz.Height + (P 10)))
})
$script:tips.Add_Draw({ param($s, $e)
    $e.Graphics.FillRectangle((Br $TH.Field), $e.Bounds)
    $e.Graphics.DrawRectangle((Pn $TH.Line 1), (Rc 0 0 ($e.Bounds.Width - 1) ($e.Bounds.Height - 1)))
    Txt $e.Graphics $e.ToolTipText $FN.Small $e.Bounds $TH.Text $TF_C
})
function Set-Tip($ctl, [string]$text) { $script:tips.SetToolTip($ctl, $text) }

# ====================================================================== widgets
# Buttons are painted labels: anti-aliased shapes, hover states, no focus rectangles.
function Paint-Btn($s, $e) {
    $t = $s.Tag; $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $w = $s.Width; $h = $s.Height
    $fill = $null; $fg = $TH.Text
    switch ($t.kind) {
        'primary' { $fill = if ($t.hover) { $TH.AccentHi } else { $TH.Accent }; $fg = $TH.Bg }
        'ghost'   { $fill = if ($t.hover) { $TH.Hover } else { $TH.Field }; $fg = $TH.Text }
        'icon'    { if ($t.hover) { $fill = $TH.Hover }; $fg = if ($t.hover) { $TH.Text } else { $TH.Muted } }
        'danger'  { $fill = if ($t.hover) { $TH.DangerTint } else { $null }; $fg = $TH.Danger }
        'link'    { $fg = if ($t.hover) { $TH.AccentHi } else { $TH.Accent } }
    }
    if ($null -ne $t.fill) { $fill = $t.fill }
    if ($null -ne $t.fg) { $fg = $t.fg }
    if (-not $t.enabled) { $fg = $TH.Faint; if ($t.kind -eq 'primary') { $fill = $TH.Field } }
    if ($t.down -and $null -ne $fill) { $fill = [System.Windows.Forms.ControlPaint]::Dark($fill, 0.05) }
    if ($null -ne $fill) {
        if ($t.shape -eq 'circle') { $g.FillEllipse((Br $fill), (RcF 0.5 0.5 ($w - 1.5) ($h - 1.5))) }
        else { Fill-Round $g 0.5 0.5 ($w - 1.5) ($h - 1.5) (P 7) $fill }
    }
    if ($t.ring) { $g.DrawEllipse((Pn $t.ring (P 1.5)), (RcF (P 1) (P 1) ($w - (P 2) - 1) ($h - (P 2) - 1))) }
    $full = Rc 0 0 $w $h
    if ($t.glyph -and $t.text) {
        $gs = Measure-Str $t.glyph $t.gfont; $ts = Measure-Str $t.text $FN.Strong
        $total = $gs.Width + (P 2) + $ts.Width
        $x0 = [int](($w - $total) / 2)
        Txt $g $t.glyph $t.gfont (Rc $x0 0 $gs.Width $h) $fg $TF_C
        Txt $g $t.text $FN.Strong (Rc ($x0 + $gs.Width + (P 2)) 0 $ts.Width $h) $fg $TF_C
    } elseif ($t.glyph) {
        Txt $g $t.glyph $t.gfont $full $fg $TF_C
    } else {
        Txt $g $t.text $t.tfont $full $fg $TF_C
    }
}
function New-Btn {
    param($Parent, [string]$Text = '', [string]$Glyph = '', [double]$X, [double]$Y, [double]$W, [double]$H,
          [string]$Kind = 'ghost', [scriptblock]$OnClick = $null, [string]$Tip = '', [string]$Shape = 'round', $GlyphFont = $null, $TextFont = $null)
    $b = New-Object System.Windows.Forms.Label
    $b.Location = New-Object System.Drawing.Point((P $X), (P $Y))
    $b.Size = New-Object System.Drawing.Size((P $W), (P $H))
    $b.BackColor = $Parent.BackColor
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.UseMnemonic = $false
    $b.Tag = @{ text = $Text; glyph = $Glyph; kind = $Kind; shape = $Shape; hover = $false; down = $false; enabled = $true
                onClick = $OnClick; fill = $null; fg = $null; ring = $null
                gfont = $(if ($GlyphFont) { $GlyphFont } else { $FN.Icon }); tfont = $(if ($TextFont) { $TextFont } else { $FN.Strong }) }
    $b.Add_Paint({ param($s, $e) Paint-Btn $s $e })
    $b.Add_MouseEnter({ param($s, $e) if ($s.Tag.enabled) { $s.Tag.hover = $true; $s.Invalidate() } })
    $b.Add_MouseLeave({ param($s, $e) $s.Tag.hover = $false; $s.Tag.down = $false; $s.Invalidate() })
    $b.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Left') { $s.Tag.down = $true; $s.Invalidate() } })
    $b.Add_MouseUp({ param($s, $e)
        $was = $s.Tag.down; $s.Tag.down = $false; $s.Invalidate()
        if ($e.Button -eq 'Left' -and $was -and $s.Tag.enabled -and $s.ClientRectangle.Contains($e.Location) -and $s.Tag.onClick) { & $s.Tag.onClick $s }
    })
    if ($Tip) { Set-Tip $b $Tip }
    $Parent.Controls.Add($b)
    return $b
}
function Set-Btn($b, $glyph = $null, $fill = 'keep', $fg = 'keep', [Nullable[bool]]$enabled = $null, $text = $null) {
    # untyped on purpose: a [string] parameter would turn $null into '' and wipe the glyph
    $dirty = $false
    if ($null -ne $glyph -and $b.Tag.glyph -ne $glyph) { $b.Tag.glyph = $glyph; $dirty = $true }
    if ($null -ne $text -and $b.Tag.text -ne $text) { $b.Tag.text = $text; $dirty = $true }
    if (-not ($fill -is [string])) { if ($b.Tag.fill -ne $fill) { $b.Tag.fill = $fill; $dirty = $true } }
    if (-not ($fg -is [string])) { if ($b.Tag.fg -ne $fg) { $b.Tag.fg = $fg; $dirty = $true } }
    if ($null -ne $enabled -and $b.Tag.enabled -ne [bool]$enabled) {
        $b.Tag.enabled = [bool]$enabled; $b.Cursor = $(if ($enabled) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default }); $dirty = $true
    }
    if ($dirty) { $b.Invalidate() }
}

function New-Lbl($Parent, [string]$Text, [double]$X, [double]$Y, [double]$W, [double]$H, $Font = $null, $Color = $null, [string]$Align = 'MiddleLeft') {
    $l = New-Object System.Windows.Forms.Label
    $l.Location = New-Object System.Drawing.Point((P $X), (P $Y))
    $l.Size = New-Object System.Drawing.Size((P $W), (P $H))
    $l.Font = $(if ($Font) { $Font } else { $FN.Body })
    $l.ForeColor = $(if ($Color) { $Color } else { $TH.Text })
    $l.BackColor = $Parent.BackColor
    $l.UseMnemonic = $false; $l.AutoEllipsis = $true
    $l.TextAlign = [System.Drawing.ContentAlignment]$Align
    $l.Text = $Text
    $Parent.Controls.Add($l)
    return $l
}

# Text field: borderless TextBox inside a painted rounded container.
function New-Field($Parent, [double]$X, [double]$Y, [double]$W, [string]$Text = '', [string]$Placeholder = '', [double]$Indent = 10) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point((P $X), (P $Y))
    $p.Size = New-Object System.Drawing.Size((P $W), (P 34))
    $p.BackColor = $Parent.BackColor
    $p.Tag = @{ focus = $false }
    Enable-DoubleBuffer $p
    $p.Add_Paint({ param($s, $e)
        $e.Graphics.SmoothingMode = 'AntiAlias'
        Fill-Round $e.Graphics 0.5 0.5 ($s.Width - 1.5) ($s.Height - 1.5) (P 8) $TH.Field
        $c = if ($s.Tag.focus) { $TH.Accent } else { $TH.Line }
        Stroke-Round $e.Graphics 0.5 0.5 ($s.Width - 1.5) ($s.Height - 1.5) (P 8) $c
    })
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.BorderStyle = 'None'; $tb.BackColor = $TH.Field; $tb.ForeColor = $TH.Text; $tb.Font = $FN.Body
    $tb.Location = New-Object System.Drawing.Point((P $Indent), [int](($p.Height - $tb.PreferredHeight) / 2 + 1))
    $tb.Width = $p.Width - (P $Indent) - (P 10)
    $tb.Text = $Text
    $ph = New-Object System.Windows.Forms.Label
    $ph.Text = $Placeholder; $ph.ForeColor = $TH.Faint; $ph.BackColor = $TH.Field; $ph.Font = $FN.Body; $ph.UseMnemonic = $false
    $ph.Location = New-Object System.Drawing.Point(($tb.Left - 1), $tb.Top); $ph.Size = New-Object System.Drawing.Size($tb.Width, $tb.Height)
    $ph.Visible = [string]::IsNullOrEmpty($Text) -and $Placeholder; $ph.Cursor = [System.Windows.Forms.Cursors]::IBeam
    $ph.Tag = $tb
    $ph.Add_Click({ param($s, $e) $s.Tag.Focus() })
    $p.Add_Click({ param($s, $e) foreach ($c in $s.Controls) { if ($c -is [System.Windows.Forms.TextBox]) { $c.Focus() } } })
    $tb.Tag = @{ placeholder = $ph; container = $p }
    $tb.Add_TextChanged({ param($s, $e) $s.Tag.placeholder.Visible = ($s.Text.Length -eq 0 -and $s.Tag.placeholder.Text.Length -gt 0) })
    $tb.Add_GotFocus({ param($s, $e) $s.Tag.container.Tag.focus = $true; $s.Tag.container.Invalidate() })
    $tb.Add_LostFocus({ param($s, $e) $s.Tag.container.Tag.focus = $false; $s.Tag.container.Invalidate() })
    $p.Controls.Add($tb); $p.Controls.Add($ph); $ph.BringToFront()
    $Parent.Controls.Add($p)
    return $tb
}

# Segmented control: one painted label, options split evenly.
function New-Segment($Parent, [double]$X, [double]$Y, [double]$W, [string[]]$Options, [int]$Index = 0, [scriptblock]$OnChange = $null, [double]$H = 32, $Font = $null) {
    $c = New-Object System.Windows.Forms.Label
    $c.Location = New-Object System.Drawing.Point((P $X), (P $Y))
    $c.Size = New-Object System.Drawing.Size((P $W), (P $H))
    $c.BackColor = $Parent.BackColor; $c.Cursor = [System.Windows.Forms.Cursors]::Hand
    $c.Tag = @{ options = $Options; index = $Index; hover = -1; onChange = $OnChange; font = $(if ($Font) { $Font } else { $FN.Strong }); enabled = $true }
    $c.Add_Paint({ param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $t = $s.Tag
        Fill-Round $g 0.5 0.5 ($s.Width - 1.5) ($s.Height - 1.5) (P 9) $TH.Card
        Stroke-Round $g 0.5 0.5 ($s.Width - 1.5) ($s.Height - 1.5) (P 9) $TH.Line
        $n = $t.options.Count; $sw = ($s.Width - (P 6)) / $n
        for ($i = 0; $i -lt $n; $i++) {
            $x = (P 3) + $i * $sw
            if ($i -eq $t.index) { Fill-Round $g $x (P 3) $sw ($s.Height - (P 6)) (P 7) $TH.Hover }
            elseif ($i -eq $t.hover -and $t.enabled) { Fill-Round $g $x (P 3) $sw ($s.Height - (P 6)) (P 7) $TH.Field }
            $col = if (-not $t.enabled) { $TH.Faint } elseif ($i -eq $t.index) { $TH.Text } else { $TH.Muted }
            Txt $g $t.options[$i] $t.font (Rc $x 0 $sw $s.Height) $col $TF_C
        }
    })
    $c.Add_MouseMove({ param($s, $e)
        $n = $s.Tag.options.Count; $i = [math]::Min($n - 1, [math]::Max(0, [int][math]::Floor(($e.X - (P 3)) / (($s.Width - (P 6)) / $n))))
        if ($s.Tag.hover -ne $i) { $s.Tag.hover = $i; $s.Invalidate() }
    })
    $c.Add_MouseLeave({ param($s, $e) $s.Tag.hover = -1; $s.Invalidate() })
    $c.Add_MouseUp({ param($s, $e)
        if ($e.Button -ne 'Left' -or -not $s.Tag.enabled) { return }
        $n = $s.Tag.options.Count; $i = [math]::Min($n - 1, [math]::Max(0, [int][math]::Floor(($e.X - (P 3)) / (($s.Width - (P 6)) / $n))))
        if ($i -ne $s.Tag.index) { $s.Tag.index = $i; $s.Invalidate(); if ($s.Tag.onChange) { & $s.Tag.onChange $s } }
    })
    $Parent.Controls.Add($c)
    return $c
}
function Set-SegmentIndex($seg, [int]$i) { if ($seg.Tag.index -ne $i) { $seg.Tag.index = $i; $seg.Invalidate() } }

# Toggle switch row.
function New-Toggle($Parent, [double]$X, [double]$Y, [double]$W, [string]$Text, [bool]$Checked, [string]$Hint = '') {
    $c = New-Object System.Windows.Forms.Label
    $c.Location = New-Object System.Drawing.Point((P $X), (P $Y))
    $c.Size = New-Object System.Drawing.Size((P $W), (P 30))
    $c.BackColor = $Parent.BackColor; $c.Cursor = [System.Windows.Forms.Cursors]::Hand
    $c.Tag = @{ checked = $Checked; text = $Text; hint = $Hint; enabled = $true }
    $c.Add_Paint({ param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $t = $s.Tag
        $tw = P 34; $trackH = P 18; $tx = $s.Width - $tw - 1; $ty = [int](($s.Height - $trackH) / 2)
        $col = if (-not $t.enabled) { $TH.Faint } else { $TH.Text }
        Txt $g $t.text $FN.Body (Rc 0 0 ($tx - (P 8)) $s.Height) $col $TF_L
        $track = if ($t.checked -and $t.enabled) { $TH.Accent } else { $TH.Line }
        Fill-Round $g $tx $ty $tw $trackH ($trackH / 2) $track
        $k = $trackH - (P 6); $kx = if ($t.checked) { $tx + $tw - $k - (P 3) } else { $tx + (P 3) }
        $g.FillEllipse((Br $(if ($t.checked) { $TH.Bg } else { $TH.Muted })), (RcF $kx ($ty + (P 3)) $k $k))
    })
    $c.Add_MouseUp({ param($s, $e) if ($e.Button -eq 'Left' -and $s.Tag.enabled) { $s.Tag.checked = -not $s.Tag.checked; $s.Invalidate() } })
    if ($Hint) { Set-Tip $c $Hint }
    $Parent.Controls.Add($c)
    return $c
}

# ====================================================================== dialogs (dark, borderless, modal)
$script:modal = 0
function Invoke-Modal($dlg) {
    $script:modal++
    try {
        $owner = if ($form.Visible) { $form } else { $null }
        $dlg.StartPosition = 'Manual'
        # centre on the panel when it is open, otherwise on the screen the orb lives on
        $anchor = if ($owner -and $script:expanded) { $owner.Bounds }
                  elseif ($owner) { [System.Windows.Forms.Screen]::FromRectangle($owner.Bounds).WorkingArea }
                  else { [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
        $wa = [System.Windows.Forms.Screen]::FromRectangle($anchor).WorkingArea
        $x = $anchor.Left + [int](($anchor.Width - $dlg.Width) / 2)
        $y = $anchor.Top + [int](($anchor.Height - $dlg.Height) / 2)
        $x = [math]::Max($wa.Left + (P 8), [math]::Min($x, $wa.Right - $dlg.Width - (P 8)))
        $y = [math]::Max($wa.Top + (P 8), [math]::Min($y, $wa.Bottom - $dlg.Height - (P 8)))
        $dlg.Location = New-Object System.Drawing.Point($x, $y)
        if ($owner) { return $dlg.ShowDialog($owner) } else { return $dlg.ShowDialog() }
    } finally { $script:modal-- }
}
function Enable-Drag($handle, $win) {
    $handle.Tag = if ($handle.Tag -is [hashtable]) { $handle.Tag } else { @{} }
    $handle.Tag.dragWin = $win
    $handle.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Left') { $s.Tag.dragFrom = [System.Windows.Forms.Cursor]::Position; $s.Tag.dragOrigin = $s.Tag.dragWin.Location } })
    $handle.Add_MouseMove({ param($s, $e)
        if ($s.Tag.dragFrom -and [System.Windows.Forms.Control]::MouseButtons -eq 'Left') {
            $p = [System.Windows.Forms.Cursor]::Position
            $s.Tag.dragWin.Location = New-Object System.Drawing.Point(($s.Tag.dragOrigin.X + $p.X - $s.Tag.dragFrom.X), ($s.Tag.dragOrigin.Y + $p.Y - $s.Tag.dragFrom.Y))
        }
    })
    $handle.Add_MouseUp({ param($s, $e) $s.Tag.dragFrom = $null })
}
function New-Dialog([string]$Title, [double]$W, [double]$H) {
    $d = New-Object System.Windows.Forms.Form
    $d.FormBorderStyle = 'None'; $d.ShowInTaskbar = $false; $d.TopMost = $true; $d.KeyPreview = $true
    $d.BackColor = $TH.Card; $d.ForeColor = $TH.Text; $d.Font = $FN.Body
    $d.AutoScaleMode = 'None'
    $d.Size = New-Object System.Drawing.Size((P $W), (P $H))
    $d.Text = $Title
    if ($form -and $form.Icon) { $d.Icon = $form.Icon }
    Enable-DoubleBuffer $d
    $d.Tag = @{ accept = $null; result = $null }
    $titleLbl = New-Lbl $d $Title 20 12 ($W - 70) 30 $FN.Title $TH.Text
    Enable-Drag $titleLbl $d
    [void](New-Btn -Parent $d -Glyph $GL.Close -X ($W - 44) -Y 12 -W 30 -H 28 -Kind 'icon' -Tip 'Close (Esc)' -OnClick { param($b) $b.FindForm().DialogResult = 'Cancel' })
    $d.Add_Paint({ param($s, $e) $e.Graphics.DrawRectangle((Pn $TH.Line 1), (Rc 0 0 ($s.Width - 1) ($s.Height - 1))) })
    $d.Add_KeyDown({ param($s, $e)
        if ($e.KeyCode -eq 'Escape') { $e.SuppressKeyPress = $true; $s.DialogResult = 'Cancel' }
        elseif ($e.KeyCode -eq 'Enter' -and $s.Tag.accept) {
            $ac = $s.ActiveControl
            if ($ac -is [System.Windows.Forms.TextBox] -and $ac.Multiline) { return }
            $e.SuppressKeyPress = $true; & $s.Tag.accept $s
        }
    })
    $d.Add_Shown({ param($s, $e)
        if ($script:native -and [SymtTempo.Native]::RoundCorners($s.Handle)) { } else { Set-RoundRegion $s (P 10) }
    })
    return $d
}
function Add-DialogButtons($d, [string]$OkText = 'Save', [string]$OkKind = 'primary', [string]$CancelText = 'Cancel', [double]$W, [double]$H) {
    $ok = New-Btn -Parent $d -Text $OkText -X ($W - 20 - 110) -Y ($H - 56) -W 110 -H 36 -Kind $OkKind -OnClick { param($b) $f = $b.FindForm(); & $f.Tag.accept $f }
    if ($CancelText) {
        [void](New-Btn -Parent $d -Text $CancelText -X ($W - 20 - 110 - 8 - 96) -Y ($H - 56) -W 96 -H 36 -Kind 'ghost' -OnClick { param($b) $b.FindForm().DialogResult = 'Cancel' })
    }
    return $ok
}
function Get-WrappedHeight([string]$text, $font, [int]$width) {
    $sz = $TR::MeasureText($text, $font, (New-Object System.Drawing.Size($width, 2000)), $TF_WRAP)
    return $sz.Height
}
function Show-Confirm([string]$Title, [string]$Message, [string]$OkText = 'OK', [string]$Kind = 'primary') {
    $W = 380; $msgH = [math]::Ceiling((Get-WrappedHeight $Message $FN.Body (P ($W - 40))) / $script:S) + 6
    $H = 60 + $msgH + 76
    $d = New-Dialog $Title $W $H
    $m = New-Lbl $d $Message 20 52 ($W - 40) $msgH $FN.Body $TH.Muted 'TopLeft'; $m.AutoEllipsis = $false
    $okKind = if ($Kind -eq 'danger') { 'primary' } else { $Kind }
    $ok = Add-DialogButtons $d $OkText $okKind 'Cancel' $W $H
    if ($Kind -eq 'danger') { $ok.Tag.fill = $TH.Danger }
    $d.Tag.accept = { param($f) $f.DialogResult = 'OK' }
    $r = Invoke-Modal $d; $d.Dispose()
    return ($r -eq 'OK')
}
function Show-Info([string]$Title, [string]$Message) {
    $W = 380; $msgH = [math]::Ceiling((Get-WrappedHeight $Message $FN.Body (P ($W - 40))) / $script:S) + 6
    $H = 60 + $msgH + 76
    $d = New-Dialog $Title $W $H
    $m = New-Lbl $d $Message 20 52 ($W - 40) $msgH $FN.Body $TH.Muted 'TopLeft'; $m.AutoEllipsis = $false
    [void](Add-DialogButtons $d 'OK' 'primary' '' $W $H)
    $d.Tag.accept = { param($f) $f.DialogResult = 'OK' }
    [void](Invoke-Modal $d); $d.Dispose()
}
# Vertical stack of choices; returns the chosen index or -1.
function Show-Choice([string]$Title, [string]$Message, [string[]]$Choices, [int]$Primary = 0) {
    $W = 400; $msgH = [math]::Ceiling((Get-WrappedHeight $Message $FN.Body (P ($W - 40))) / $script:S) + 8
    $H = 60 + $msgH + 12 + $Choices.Count * 44 + 14
    $d = New-Dialog $Title $W $H
    $m = New-Lbl $d $Message 20 52 ($W - 40) $msgH $FN.Body $TH.Muted 'TopLeft'; $m.AutoEllipsis = $false
    $y = 60 + $msgH + 6
    for ($i = 0; $i -lt $Choices.Count; $i++) {
        $kind = if ($i -eq $Primary) { 'primary' } else { 'ghost' }
        $b = New-Btn -Parent $d -Text $Choices[$i] -X 20 -Y $y -W ($W - 40) -H 36 -Kind $kind -OnClick { param($b) $f = $b.FindForm(); $f.Tag.result = $b.Tag.index; $f.DialogResult = 'OK' }
        $b.Tag.index = $i
        $y += 44
    }
    $d.Tag.result = -1; $d.Tag.primary = $Primary
    $d.Tag.accept = { param($f) $f.Tag.result = $f.Tag.primary; $f.DialogResult = 'OK' }
    [void](Invoke-Modal $d); $r = $d.Tag.result; $d.Dispose()
    return $r
}
function Show-Prompt([string]$Title, [string]$Label, [string]$Default = '', [string[]]$Suggestions = @()) {
    $W = 380; $H = 190
    $d = New-Dialog $Title $W $H
    [void](New-Lbl $d $Label 20 50 ($W - 40) 20 $FN.Small $TH.Muted)
    $tb = New-Field $d 20 72 ($W - 40) $Default
    if ($Suggestions.Count) {
        $src = New-Object System.Windows.Forms.AutoCompleteStringCollection; $src.AddRange([string[]]$Suggestions)
        $tb.AutoCompleteCustomSource = $src; $tb.AutoCompleteSource = 'CustomSource'; $tb.AutoCompleteMode = 'SuggestAppend'
    }
    $d.Tag.tb = $tb
    [void](Add-DialogButtons $d 'Save' 'primary' 'Cancel' $W $H)
    $d.Tag.accept = { param($f) if ($f.Tag.tb.Text.Trim()) { $f.Tag.result = $f.Tag.tb.Text.Trim(); $f.DialogResult = 'OK' } }
    $d.Add_Shown({ param($s, $e) $s.Tag.tb.Focus(); $s.Tag.tb.SelectAll() })
    $r = Invoke-Modal $d; $v = $d.Tag.result; $d.Dispose()
    if ($r -eq 'OK') { return $v } return $null
}

# ====================================================================== main window
$script:PW = 344; $script:PH = 556; $script:ORB = 60
$form = New-Object System.Windows.Forms.Form
$form.Text = "SYMT Tempo $script:TempoVersion"
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.AutoScaleMode = 'None'
$form.BackColor = $TH.Bg; $form.ForeColor = $TH.Text; $form.Font = $FN.Body
$form.ShowInTaskbar = $false
$form.TopMost = [bool]$script:settings.topMost
$form.KeyPreview = $true
$iconPath = Join-Path $root 'Assets\Tempo.ico'
$form.Icon = New-Object System.Drawing.Icon($iconPath)
Enable-DoubleBuffer $form
$script:expanded = $false
$script:quitting = $false
$script:panelMoved = $false
$script:hoverOrb = $false
$script:logDay = (Get-Date).Date
$script:taskRows = New-Object 'System.Collections.Generic.List[object]'
$script:logRows = New-Object 'System.Collections.Generic.List[object]'
$script:hoverTask = -1; $script:hoverLog = -1; $script:hoverTaskAction = $false
$script:lastRowAction = [datetime]::MinValue
$script:flashUntil = [datetime]::MinValue
$script:lastAutoCollapse = [datetime]::MinValue
$script:menuOpen = $false
$script:lastTask = $script:settings.lastTaskId
if ($script:lastTask -and -not (Find-Task $script:lastTask)) { $script:lastTask = $null }

# ---------------------------------------------------------------- header
$lblBrand = New-Lbl $form 'SYMT Tempo' 32 12 150 24 $FN.Brand $TH.Text
$btnPin = New-Btn -Parent $form -Glyph $GL.Pin -X ($script:PW - 112) -Y 10 -W 30 -H 28 -Kind 'icon' -Tip 'Keep panel open when clicking away' -OnClick { Toggle-Pin }
$btnMore = New-Btn -Parent $form -Glyph $GL.More -X ($script:PW - 78) -Y 10 -W 30 -H 28 -Kind 'icon' -Tip 'Menu' -OnClick { param($b) $script:menu.Show($b, (New-Object System.Drawing.Point(0, $b.Height))) }
$btnMin = New-Btn -Parent $form -Glyph $GL.Min -X ($script:PW - 44) -Y 10 -W 30 -H 28 -Kind 'icon' -Tip 'Collapse to orb (Esc)' -OnClick { Collapse-Panel }

# ---------------------------------------------------------------- now card
$card = New-Object System.Windows.Forms.Panel
$card.Location = New-Object System.Drawing.Point((P 12), (P 48)); $card.Size = New-Object System.Drawing.Size((P 320), (P 118))
$card.BackColor = $TH.Card
Enable-DoubleBuffer $card
Set-RoundRegion $card (P 12)
$card.Tag = @{ bar = $TH.Line }
$card.Add_Paint({ param($s, $e)
    $e.Graphics.SmoothingMode = 'AntiAlias'
    Fill-Round $e.Graphics 0 (P 20) (P 3) ($s.Height - (P 40)) (P 1.5) $s.Tag.bar
})
$form.Controls.Add($card)
$lblChip = New-Lbl $card '' 16 12 190 18 $FN.SmallB $TH.Faint
$lblNowTask = New-Lbl $card 'Nothing running' 16 30 190 24 $FN.Title $TH.Text
$lblNowTime = New-Lbl $card '0:00:00' 11 52 200 46 $FN.Timer $TH.Faint
$lblNowMeta = New-Lbl $card '' 16 94 220 18 $FN.Small $TH.Muted
$btnPrimary = New-Btn -Parent $card -Glyph $GL.Play -X 254 -Y 30 -W 52 -H 52 -Kind 'primary' -Shape 'circle' -GlyphFont $FN.IconLg -Tip 'Start / pause (Space)' -OnClick { Toggle-Primary }
$btnStop = New-Btn -Parent $card -Glyph $GL.Stop -X 212 -Y 40 -W 32 -H 32 -Kind 'ghost' -Shape 'circle' -GlyphFont $FN.IconSm -Tip 'Stop and clear' -OnClick { Stop-Task; Refresh-All; Flash 'Stopped' }
$lblNowMeta.Add_Click({ if ($script:active) { Show-AdjustStart } })

# ---------------------------------------------------------------- stats strip (today / week / target)
$stats = New-Object System.Windows.Forms.Panel
$stats.Location = New-Object System.Drawing.Point((P 12), (P 174)); $stats.Size = New-Object System.Drawing.Size((P 320), (P 44))
$stats.BackColor = $TH.Bg
Enable-DoubleBuffer $stats
$stats.Add_Paint({ param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $today = Get-TodayTotal; $week = Get-WeekTotal
    $cap = P 14; $val = P 20
    Txt $g 'TODAY' $FN.SmallB (Rc (P 2) 0 (P 100) $cap) $TH.Faint $TF_L
    Txt $g (Format-Short $today) $FN.Title (Rc 0 $cap (P 110) $val) $TH.Text $TF_L
    Txt $g 'THIS WEEK' $FN.SmallB (Rc (P 112) 0 (P 100) $cap) $TH.Faint $TF_L
    Txt $g (Format-Short $week) $FN.Title (Rc (P 110) $cap (P 110) $val) $TH.Text $TF_L
    $target = [double]$script:settings.dailyTargetHours
    if ($target -gt 0) {
        $pct = $today / ($target * 3600)
        Txt $g ('{0:0}% of {1}h' -f ([math]::Min(999, $pct * 100)), $target) $FN.Small (Rc (P 200) 0 (P 120) $cap) $TH.Muted $TF_R
        $by = $s.Height - (P 5)
        Fill-Round $g 0 $by $s.Width (P 4) (P 2) $TH.Card
        $fillW = [math]::Max((P 4), [math]::Min(1.0, $pct) * $s.Width)
        if ($today -gt 0) { Fill-Round $g 0 $by $fillW (P 4) (P 2) $(if ($pct -ge 1) { $TH.Run } else { $TH.Accent }) }
    }
})
$form.Controls.Add($stats)

# ---------------------------------------------------------------- tabs
$tabs = New-Segment $form 12 226 320 @('Tasks', 'Log') 0 { param($s) Set-Tab $(if ($s.Tag.index -eq 0) { 'tasks' } else { 'log' }) } 32

# ---------------------------------------------------------------- search / quick add (Tasks tab)
$searchHost = New-Object System.Windows.Forms.Panel
$searchHost.Location = New-Object System.Drawing.Point((P 12), (P 266)); $searchHost.Size = New-Object System.Drawing.Size((P 320), (P 36))
$searchHost.BackColor = $TH.Bg
$form.Controls.Add($searchHost)
$txtSearch = New-Field $searchHost 0 1 280 '' 'Search or add  (Client: Task)' 30
$searchIcon = New-Object System.Windows.Forms.Label
$searchIcon.Text = $GL.Search; $searchIcon.Font = $FN.IconSm; $searchIcon.ForeColor = $TH.Faint; $searchIcon.BackColor = $TH.Field
$searchIcon.Location = New-Object System.Drawing.Point((P 9), (P 9)); $searchIcon.Size = New-Object System.Drawing.Size((P 18), (P 16)); $searchIcon.TextAlign = 'MiddleCenter'
$txtSearch.Parent.Controls.Add($searchIcon)
$btnAdd = New-Btn -Parent $searchHost -Glyph $GL.Add -X 286 -Y 1 -W 34 -H 34 -Kind 'ghost' -Tip 'New task (Ctrl+N)' -OnClick { Invoke-AddButton }

# ---------------------------------------------------------------- day navigator (Log tab)
$dayHost = New-Object System.Windows.Forms.Panel
$dayHost.Location = New-Object System.Drawing.Point((P 12), (P 266)); $dayHost.Size = New-Object System.Drawing.Size((P 320), (P 36))
$dayHost.BackColor = $TH.Bg; $dayHost.Visible = $false
$form.Controls.Add($dayHost)
$btnPrevDay = New-Btn -Parent $dayHost -Glyph $GL.Back -X 0 -Y 2 -W 32 -H 32 -Kind 'icon' -Tip 'Previous day' -OnClick { Set-LogDay ($script:logDay.AddDays(-1)) }
$lblDay = New-Lbl $dayHost 'Today' 36 0 140 36 $FN.Strong $TH.Text
$lblDay.Cursor = [System.Windows.Forms.Cursors]::Hand
$lblDay.Add_Click({ Set-LogDay (Get-Date).Date })
Set-Tip $lblDay 'Jump to today'
$btnNextDay = New-Btn -Parent $dayHost -Glyph $GL.Fwd -X 178 -Y 2 -W 32 -H 32 -Kind 'icon' -Tip 'Next day' -OnClick { Set-LogDay ($script:logDay.AddDays(1)) }
$lblDayTotal = New-Lbl $dayHost '' 212 0 66 36 $FN.Strong $TH.Muted 'MiddleRight'
$btnAddTime = New-Btn -Parent $dayHost -Glyph $GL.Add -X 286 -Y 1 -W 34 -H 34 -Kind 'ghost' -Tip 'Add time manually (Ctrl+M)' -OnClick { Show-IntervalEditor -TaskId $(Get-SelectedTaskId) -Day $script:logDay }

# ---------------------------------------------------------------- lists
function New-RowList([int]$itemHeight) {
    $l = New-Object System.Windows.Forms.ListBox
    $l.Location = New-Object System.Drawing.Point((P 12), (P 310)); $l.Size = New-Object System.Drawing.Size((P 320), (P 196))
    $l.BorderStyle = 'None'; $l.BackColor = $TH.Bg; $l.ForeColor = $TH.Text
    $l.DrawMode = 'OwnerDrawFixed'; $l.ItemHeight = $itemHeight; $l.IntegralHeight = $false
    Enable-DoubleBuffer $l
    $form.Controls.Add($l)
    return $l
}
$lstTasks = New-RowList (P 48)
$lstLog = New-RowList (P 48); $lstLog.Visible = $false
$lblEmpty = New-Lbl $form '' 24 340 296 120 $FN.Body $TH.Faint 'MiddleCenter'
$lblEmpty.AutoEllipsis = $false
$lblEmpty.BringToFront()

# ---------------------------------------------------------------- footer
$lblHint = New-Lbl $form '' 16 518 236 26 $FN.Small $TH.Faint
$btnExport = New-Btn -Parent $form -Glyph $GL.Export -X ($script:PW - 78) -Y 516 -W 30 -H 28 -Kind 'icon' -Tip 'Export (Ctrl+E)' -OnClick { Show-Export }
$btnSettings = New-Btn -Parent $form -Glyph $GL.Settings -X ($script:PW - 44) -Y 516 -W 30 -H 28 -Kind 'icon' -Tip 'Settings (Ctrl+,)' -OnClick { Show-Settings }

# ====================================================================== painting of the window itself (panel chrome + orb)
$form.Add_Paint({ param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    if ($script:expanded) {
        $g.DrawRectangle((Pn $TH.Line 1), (Rc 0 0 ($s.Width - 1) ($s.Height - 1)))
        $dot = if ($script:active) { $TH.Run } elseif ($script:pausedTask) { $TH.Pause } else { $TH.Accent }
        $g.FillEllipse((Br $dot), (RcF (P 17) (P 20) (P 8) (P 8)))
        $g.DrawLine((Pn $TH.Line 1), 0, (P 510), $s.Width, (P 510))
        return
    }
    Paint-Orb $g $s.ClientSize.Width
})
function Paint-Orb($g, [int]$size) {
    $g.Clear($TH.Line)
    $in = 1
    $face = if ($script:hoverOrb) { $TH.Hover } else { $TH.Bg }
    $g.FillEllipse((Br $face), (RcF $in $in ($size - 2 * $in - 1) ($size - 2 * $in - 1)))
    $rw = [single](P 3); $ri = (P 6)
    $ring = RcF $ri $ri ($size - 2 * $ri - 1) ($size - 2 * $ri - 1)
    $g.DrawEllipse((Pn $TH.Card $rw), $ring)
    $full = Rc 0 0 $size $size
    if ($script:active) {
        $sec = Get-RunningSeconds
        $sweep = [single](360.0 * (($sec % 3600) / 3600.0))
        if ($sec -ge 3600) { $g.DrawEllipse((Pn (RGB 61 220 151 90) $rw), $ring) }
        if ($sweep -gt 0.5) { $g.DrawArc((Pn $TH.Run $rw), $ring, -90, $sweep) }
        Txt $g (Format-Compact $sec) $FN.Orb $full $TH.Text $TF_C
    } elseif ($script:pausedTask) {
        $g.DrawEllipse((Pn $TH.Pause $rw), $ring)
        Txt $g $GL.Pause $FN.Icon $full $TH.Pause $TF_C
    } else {
        Txt $g $GL.Watch $FN.IconLg $full $TH.Accent $TF_C
    }
}

# ====================================================================== orb / panel geometry
function Get-OrbSize { return (P $script:ORB) }
function Get-DefaultOrbPos {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    return New-Object System.Drawing.Point(($wa.Right - (Get-OrbSize) - (P 16)), ($wa.Bottom - (Get-OrbSize) - (P 40)))
}
function Get-OrbPos {
    $o = Get-OrbSize
    if ([int]$script:settings.orbX -ge -30000 -and [int]$script:settings.orbX -ne -1) {
        $r = Rc ([int]$script:settings.orbX) ([int]$script:settings.orbY) $o $o
        foreach ($sc in [System.Windows.Forms.Screen]::AllScreens) { if ($sc.WorkingArea.IntersectsWith($r)) { return $r.Location } }
    }
    return Get-DefaultOrbPos
}
function Set-OrbPos([System.Drawing.Point]$p) { $script:settings.orbX = $p.X; $script:settings.orbY = $p.Y }
function Get-PanelRect {
    $o = Get-OrbSize; $op = Get-OrbPos
    $orb = Rc $op.X $op.Y $o $o
    $wa = [System.Windows.Forms.Screen]::FromRectangle($orb).WorkingArea
    $pw = P $script:PW; $ph = P $script:PH
    $cx = $orb.Left + $o / 2; $cy = $orb.Top + $o / 2
    $x = if ($cx -gt ($wa.Left + $wa.Width / 2)) { $orb.Right - $pw } else { $orb.Left }
    $y = if ($cy -gt ($wa.Top + $wa.Height / 2)) { $orb.Bottom - $ph } else { $orb.Top }
    $x = [math]::Max($wa.Left, [math]::Min($x, $wa.Right - $pw)); $y = [math]::Max($wa.Top, [math]::Min($y, $wa.Bottom - $ph))
    return Rc $x $y $pw $ph
}
function Snap-Orb([System.Drawing.Point]$p) {
    $o = Get-OrbSize; $wa = [System.Windows.Forms.Screen]::FromPoint((New-Object System.Drawing.Point(($p.X + $o / 2), ($p.Y + $o / 2)))).WorkingArea
    $m = P 8; $snap = P 28
    $x = $p.X; $y = $p.Y
    if ($x - $wa.Left -lt $snap) { $x = $wa.Left + $m }
    if ($wa.Right - ($x + $o) -lt $snap) { $x = $wa.Right - $o - $m }
    if ($y - $wa.Top -lt $snap) { $y = $wa.Top + $m }
    if ($wa.Bottom - ($y + $o) -lt $snap) { $y = $wa.Bottom - $o - $m }
    return New-Object System.Drawing.Point([int]$x, [int]$y)
}
function Set-Mode([bool]$panel) {
    $form.SuspendLayout()
    if (-not $panel -and $script:expanded -and $script:panelMoved) {
        # panel was dragged: re-anchor the orb to the panel corner nearest the screen edge
        $b = $form.Bounds; $o = Get-OrbSize; $wa = [System.Windows.Forms.Screen]::FromRectangle($b).WorkingArea
        $x = if (($b.Left + $b.Width / 2) -gt ($wa.Left + $wa.Width / 2)) { $b.Right - $o } else { $b.Left }
        $y = if (($b.Top + $b.Height / 2) -gt ($wa.Top + $wa.Height / 2)) { $b.Bottom - $o } else { $b.Top }
        Set-OrbPos (New-Object System.Drawing.Point([int]$x, [int]$y))
        $script:panelMoved = $false
    }
    $script:expanded = $panel
    foreach ($c in $form.Controls) { $c.Visible = $false }
    if ($panel) {
        $form.Bounds = Get-PanelRect
        if ($script:roundedByDwm) { $form.Region = $null } else { Set-RoundRegion $form (P 12) }
        foreach ($c in @($lblBrand, $btnPin, $btnMore, $btnMin, $card, $stats, $tabs, $lblHint, $btnExport, $btnSettings)) { $c.Visible = $true }
        Apply-Tab
    } else {
        $o = Get-OrbSize; $p = Get-OrbPos
        $form.Bounds = Rc $p.X $p.Y $o $o
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath; $path.AddEllipse(0, 0, $o, $o)
        $form.Region = New-Object System.Drawing.Region($path); $path.Dispose()
    }
    $form.ResumeLayout()
    $form.Invalidate()
    Update-Live
}
function Open-Panel { if (-not $form.Visible) { $form.Show() }; if (-not $script:expanded) { Set-Mode $true }; $form.Activate(); if ($script:native) { [SymtTempo.Native]::Foreground($form.Handle) }; Focus-Default }
function Collapse-Panel { if (-not $form.Visible) { $form.Show() }; if ($script:expanded) { Set-Mode $false }; Save-Settings }
function Hide-ToTray { $form.Hide(); Flash-Tray 'SYMT Tempo is still running in the tray.' }
function Toggle-Panel {
    if (-not $form.Visible -or -not $script:expanded) { Open-Panel; return }
    if ([System.Windows.Forms.Form]::ActiveForm -ne $form) { Open-Panel; return }
    Collapse-Panel
}
function Toggle-Pin {
    $script:settings.pinned = -not [bool]$script:settings.pinned
    Update-PinButton; Save-Settings
    Flash $(if ($script:settings.pinned) { 'Panel pinned open' } else { 'Panel collapses when you click away' })
}
function Update-PinButton {
    if ($script:settings.pinned) { Set-Btn $btnPin -glyph $GL.Pinned -fg $TH.Accent } else { Set-Btn $btnPin -glyph $GL.Pin -fg $null }
}
function Focus-Default {
    if ($script:settings.tab -eq 'log') { $lstLog.Focus() | Out-Null }
    elseif ($lstTasks.Items.Count -gt 0) { $lstTasks.Focus() | Out-Null }
    else { $txtSearch.Focus() | Out-Null }
}

# ---------------------------------------------------------------- dragging (orb + panel header)
$script:drag = $null
$dragDown = { param($s, $e)
    if ($e.Button -ne 'Left') { return }
    if ($script:expanded -and $s -eq $form -and $e.Y -gt (P 46)) { return }
    $script:drag = @{ from = [System.Windows.Forms.Cursor]::Position; origin = $form.Location; moved = $false }
}
$dragMove = { param($s, $e)
    if ($s -eq $form -and -not $script:expanded) {
        if (-not $script:hoverOrb) { $script:hoverOrb = $true; $form.Invalidate() }
    }
    if ($null -eq $script:drag -or [System.Windows.Forms.Control]::MouseButtons -ne 'Left') { return }
    $p = [System.Windows.Forms.Cursor]::Position
    $dx = $p.X - $script:drag.from.X; $dy = $p.Y - $script:drag.from.Y
    if ([math]::Abs($dx) + [math]::Abs($dy) -gt (P 4)) { $script:drag.moved = $true }
    if ($script:drag.moved) { $form.Location = New-Object System.Drawing.Point(($script:drag.origin.X + $dx), ($script:drag.origin.Y + $dy)) }
}
$dragUp = { param($s, $e)
    if ($e.Button -ne 'Left' -or $null -eq $script:drag) { return }
    $moved = $script:drag.moved; $script:drag = $null
    if ($script:expanded) { if ($moved) { $script:panelMoved = $true }; return }
    if ($moved) { $p = Snap-Orb $form.Location; $form.Location = $p; Set-OrbPos $p; Save-Settings }
    else { Open-Panel }
}
foreach ($dragCtl in @($form, $lblBrand)) { $dragCtl.Add_MouseDown($dragDown); $dragCtl.Add_MouseMove($dragMove); $dragCtl.Add_MouseUp($dragUp) }
$form.Add_MouseLeave({ if ($script:hoverOrb) { $script:hoverOrb = $false; $form.Invalidate() } })

# ====================================================================== row painting
function Draw-RowBackground($g, [System.Drawing.Rectangle]$b, [bool]$sel, [bool]$hover, [bool]$running) {
    $g.FillRectangle((Br $TH.Bg), $b)
    $x = $b.X; $y = $b.Y + (P 2); $w = $b.Width - 1; $h = $b.Height - (P 4)
    if ($running) { Fill-Round $g $x $y $w $h (P 9) $TH.RunTint }
    elseif ($sel) { Fill-Round $g $x $y $w $h (P 9) $TH.Sel }
    elseif ($hover) { Fill-Round $g $x $y $w $h (P 9) $TH.Card }
    if ($sel -and $running) { Stroke-Round $g ($x + 0.5) ($y + 0.5) ($w - 1) ($h - 1) (P 9) (RGB 61 220 151 110) }
}
$lstTasks.Add_DrawItem({ param($s, $e)
    if ($e.Index -lt 0 -or $e.Index -ge $script:taskRows.Count) { return }
    $row = $script:taskRows[$e.Index]; $g = $e.Graphics; $b = $e.Bounds
    $g.SmoothingMode = 'AntiAlias'
    $sel = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    $hover = ($e.Index -eq $script:hoverTask)
    if ($row.kind -eq 'create') {
        Draw-RowBackground $g $b $sel $hover $false
        $cy = $b.Y + $b.Height / 2
        $g.FillEllipse((Br $TH.Field), (RcF ($b.X + (P 6)) ($cy - (P 13)) (P 26) (P 26)))
        Txt $g $GL.Add $FN.IconSm (Rc ($b.X + (P 6)) ($cy - (P 13)) (P 26) (P 26)) $TH.Accent $TF_C
        Txt $g ('Create "{0}"' -f $row.name) $FN.Strong (Rc ($b.X + (P 40)) ($b.Y + (P 6)) ($b.Width - (P 50)) (P 20)) $TH.Text $TF_L
        Txt $g ('in {0}  ·  Enter' -f $row.project) $FN.Small (Rc ($b.X + (P 40)) ($b.Y + (P 25)) ($b.Width - (P 50)) (P 16)) $TH.Muted $TF_L
        return
    }
    $t = $row.task
    $running = ($script:active -eq $t.id); $paused = ($script:pausedTask -eq $t.id)
    Draw-RowBackground $g $b $sel $hover $running
    $cy = $b.Y + $b.Height / 2
    if ($running) { Fill-Round $g ($b.X + (P 1)) ($b.Y + (P 12)) (P 3) ($b.Height - (P 24)) (P 1.5) $TH.Run }
    $pc = Get-ProjectColor $t.project
    if ($t.archived) { $g.DrawEllipse((Pn $pc 1.5), (RcF ($b.X + (P 13)) ($cy - (P 4)) (P 8) (P 8))) }
    else { $g.FillEllipse((Br $pc), (RcF ($b.X + (P 13)) ($cy - (P 4)) (P 8) (P 8))) }
    $textW = $b.Width - (P 32) - (P 104)
    $nameCol = if ($t.archived) { $TH.Muted } else { $TH.Text }
    Txt $g $t.name $FN.Strong (Rc ($b.X + (P 30)) ($b.Y + (P 6)) $textW (P 20)) $nameCol $TF_L
    $sub = $t.project; if ($t.archived) { $sub += '  ·  archived' } elseif ($paused) { $sub += '  ·  paused' }
    Txt $g $sub $FN.Small (Rc ($b.X + (P 30)) ($b.Y + (P 25)) $textW (P 16)) $(if ($paused) { $TH.Pause } else { $TH.Muted }) $TF_L
    $tot = Get-TaskTodayTotal $t.id
    if ($tot -ge 1) {
        $col = if ($running) { $TH.Run } else { $TH.Muted }
        $txt = if ($running) { Format-Clock $tot } else { Format-Short $tot }
        Txt $g $txt $FN.Small (Rc ($b.Right - (P 112)) $b.Y (P 70) $b.Height) $col $TF_R
    }
    $showAction = $hover -or $sel -or $running -or $paused
    if ($showAction) {
        $ar = RcF ($b.Right - (P 36)) ($cy - (P 14)) (P 28) (P 28)
        if ($running) {
            $g.FillEllipse((Br $TH.Run), $ar)
            Txt $g $GL.Pause $FN.IconSm (Rc $ar.X $ar.Y $ar.Width $ar.Height) $TH.Bg $TF_C
        } else {
            $hot = $hover -and $script:hoverTaskAction
            $g.FillEllipse((Br $(if ($hot) { $TH.Accent } else { $TH.Field })), $ar)
            Txt $g $GL.Play $FN.IconSm (Rc $ar.X $ar.Y $ar.Width $ar.Height) $(if ($hot) { $TH.Bg } else { $TH.Text }) $TF_C
        }
    }
})
$lstLog.Add_DrawItem({ param($s, $e)
    if ($e.Index -lt 0 -or $e.Index -ge $script:logRows.Count) { return }
    $r = $script:logRows[$e.Index]; $g = $e.Graphics; $b = $e.Bounds
    $g.SmoothingMode = 'AntiAlias'
    $sel = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    Draw-RowBackground $g $b $sel ($e.Index -eq $script:hoverLog) $r.running
    $d0 = $script:logDay.Date
    $fromTxt = if ($r.from -lt $d0) { '‹' + $r.from.ToString('HH:mm') } else { $r.from.ToString('HH:mm') }
    $toTxt = if ($r.running) { 'now' } elseif ($r.to -gt $d0.AddDays(1)) { $r.to.ToString('HH:mm') + '›' } else { $r.to.ToString('HH:mm') }
    Txt $g ('{0} – {1}' -f $fromTxt, $toTxt) $FN.Small (Rc ($b.X + (P 12)) ($b.Y + (P 7)) (P 90) (P 16)) $(if ($r.running) { $TH.Run } else { $TH.Muted }) $TF_L
    $dur = if ($r.running) { Format-Clock $r.seconds } else { Format-Short $r.seconds }
    Txt $g $dur $FN.Strong (Rc ($b.X + (P 12)) ($b.Y + (P 23)) (P 90) (P 18)) $(if ($r.running) { $TH.Run } else { $TH.Text }) $TF_L
    $proj = Get-TaskProject $r.taskId
    $g.FillEllipse((Br (Get-ProjectColor $proj)), (RcF ($b.X + (P 104)) ($b.Y + (P 12)) (P 7) (P 7)))
    Txt $g (Get-TaskName $r.taskId) $FN.Strong (Rc ($b.X + (P 116)) ($b.Y + (P 5)) ($b.Width - (P 124)) (P 20)) $TH.Text $TF_L
    $sub = $proj
    if ($r.source -eq 'manual') { $sub += '  ·  manual' } elseif ($r.source -eq 'edited') { $sub += '  ·  edited' } elseif ($r.source -eq 'recovered') { $sub += '  ·  recovered' }
    if ($r.note) { $sub += '  ·  ' + $r.note }
    Txt $g $sub $FN.Small (Rc ($b.X + (P 104)) ($b.Y + (P 24)) ($b.Width - (P 112)) (P 16)) $TH.Muted $TF_L
})

# hover tracking + row action hit-testing
function Get-RowIndex($lst, [System.Drawing.Point]$pt) {
    $i = $lst.IndexFromPoint($pt)
    if ($i -lt 0 -or $i -ge $lst.Items.Count) { return -1 }
    if (-not $lst.GetItemRectangle($i).Contains($pt)) { return -1 }
    return $i
}
function Invalidate-Row($lst, [int]$i) { if ($i -ge 0 -and $i -lt $lst.Items.Count) { $lst.Invalidate($lst.GetItemRectangle($i)) } }
$lstTasks.Add_MouseMove({ param($s, $e)
    $i = Get-RowIndex $s $e.Location
    $onAction = ($i -ge 0 -and $e.X -ge ($s.ClientSize.Width - (P 44)))
    if ($i -ne $script:hoverTask -or $onAction -ne $script:hoverTaskAction) {
        $old = $script:hoverTask; $script:hoverTask = $i; $script:hoverTaskAction = $onAction
        Invalidate-Row $s $old; Invalidate-Row $s $i
        $s.Cursor = $(if ($onAction) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default })
    }
})
$lstTasks.Add_MouseLeave({ param($s, $e) $old = $script:hoverTask; $script:hoverTask = -1; Invalidate-Row $s $old })
$lstTasks.Add_MouseUp({ param($s, $e)
    $i = Get-RowIndex $s $e.Location
    if ($i -lt 0) { return }
    if ($e.Button -eq 'Left' -and $e.X -ge ($s.ClientSize.Width - (P 44))) {
        # debounce: a double-click on the play button must not start-then-pause
        if (((Get-Date) - $script:lastRowAction).TotalMilliseconds -lt 450) { return }
        $script:lastRowAction = Get-Date
        Invoke-TaskRow $i
    }
    elseif ($e.Button -eq 'Right') { $s.SelectedIndex = $i; Show-TaskMenu $i $e.Location }
})
$lstTasks.Add_DoubleClick({ param($s, $e)
    $pt = $s.PointToClient([System.Windows.Forms.Cursor]::Position)
    if ($pt.X -ge ($s.ClientSize.Width - (P 44))) { return }   # handled by MouseUp
    $i = Get-RowIndex $s $pt; if ($i -ge 0) { Invoke-TaskRow $i }
})
$lstTasks.Add_KeyPress({ param($s, $e)
    $ch = $e.KeyChar
    if (-not [char]::IsControl($ch) -and $ch -ne ' ') { $e.Handled = $true; $txtSearch.Focus() | Out-Null; $txtSearch.AppendText([string]$ch) }
})
$lstLog.Add_MouseMove({ param($s, $e)
    $i = Get-RowIndex $s $e.Location
    if ($i -ne $script:hoverLog) { $old = $script:hoverLog; $script:hoverLog = $i; Invalidate-Row $s $old; Invalidate-Row $s $i }
})
$lstLog.Add_MouseLeave({ param($s, $e) $old = $script:hoverLog; $script:hoverLog = -1; Invalidate-Row $s $old })
$lstLog.Add_MouseUp({ param($s, $e)
    $i = Get-RowIndex $s $e.Location
    if ($i -ge 0 -and $e.Button -eq 'Right') { $s.SelectedIndex = $i; Show-LogMenu $i $e.Location }
})
$lstLog.Add_DoubleClick({ param($s, $e) $i = Get-RowIndex $s ($s.PointToClient([System.Windows.Forms.Cursor]::Position)); if ($i -ge 0) { Edit-LogRow $i } })

# ====================================================================== list content
function Refresh-TaskList {
    $q = $txtSearch.Text.Trim()
    $selId = $null
    if ($lstTasks.SelectedIndex -ge 0 -and $lstTasks.SelectedIndex -lt $script:taskRows.Count) {
        $sr = $script:taskRows[$lstTasks.SelectedIndex]; if ($sr.kind -eq 'task') { $selId = $sr.task.id }
    }
    $top = $lstTasks.TopIndex
    $script:taskRows.Clear()
    foreach ($t in (Search-Tasks $q ([bool]$script:settings.showArchived))) { $script:taskRows.Add([pscustomobject]@{ kind = 'task'; task = $t }) }
    if ($q) {
        $qa = Split-QuickAdd $q
        if ($qa.name -and $null -eq (Find-TaskByName $qa.name $qa.project)) {
            $script:taskRows.Add([pscustomobject]@{ kind = 'create'; name = $qa.name; project = $qa.project })
        }
    }
    $lstTasks.BeginUpdate()
    $lstTasks.Items.Clear()
    for ($i = 0; $i -lt $script:taskRows.Count; $i++) { [void]$lstTasks.Items.Add([string]$i) }
    if ($q) { if ($lstTasks.Items.Count) { $lstTasks.SelectedIndex = 0 } }
    else {
        for ($i = 0; $i -lt $script:taskRows.Count; $i++) { if ($script:taskRows[$i].task.id -eq $selId) { $lstTasks.SelectedIndex = $i; break } }
        if ($top -lt $lstTasks.Items.Count) { $lstTasks.TopIndex = $top }
    }
    $lstTasks.EndUpdate()
    $script:hoverTask = -1
    Update-Empty
}
function Refresh-Log {
    $selId = $null
    if ($lstLog.SelectedIndex -ge 0 -and $lstLog.SelectedIndex -lt $script:logRows.Count) { $selId = $script:logRows[$lstLog.SelectedIndex].id }
    $script:logRows.Clear()
    foreach ($r in (Get-DayEntries $script:logDay)) { $script:logRows.Add($r) }
    $lstLog.BeginUpdate(); $lstLog.Items.Clear()
    for ($i = 0; $i -lt $script:logRows.Count; $i++) { [void]$lstLog.Items.Add([string]$i); if ($selId -and $script:logRows[$i].id -eq $selId) { $lstLog.SelectedIndex = $i } }
    $lstLog.EndUpdate()
    $today = (Get-Date).Date
    $label = if ($script:logDay -eq $today) { 'Today  ·  ' + $script:logDay.ToString('ddd d MMM') }
             elseif ($script:logDay -eq $today.AddDays(-1)) { 'Yesterday  ·  ' + $script:logDay.ToString('ddd d MMM') }
             else { $script:logDay.ToString('dddd d MMM') }
    Set-Text $lblDay $label
    Set-Text $lblDayTotal (Format-Short (Get-DayTotal $script:logDay))
    Set-Btn $btnNextDay -enabled ($script:logDay -lt $today)
    $script:hoverLog = -1
    Update-Empty
}
function Set-LogDay([datetime]$d) {
    $today = (Get-Date).Date
    if ($d.Date -gt $today) { return }
    $script:logDay = $d.Date; Refresh-Log
}
function Update-Empty {
    if (-not $script:expanded) { $lblEmpty.Visible = $false; return }
    if ($script:settings.tab -eq 'log') {
        $lblEmpty.Visible = ($script:logRows.Count -eq 0)
        $lblEmpty.Text = "Nothing logged on this day.`r`n`r`nUse  +  to add time you forgot to track."
    } else {
        $lblEmpty.Visible = ($script:taskRows.Count -eq 0)
        $lblEmpty.Text = "No tasks yet.`r`n`r`nType a name above and press Enter.`r`n`"Client: Task`" files it under a project."
    }
    if ($lblEmpty.Visible) { $lblEmpty.BringToFront() }
}
function Set-Tab([string]$tab) { $script:settings.tab = $tab; Apply-Tab; Focus-Default }
function Apply-Tab {
    if (-not $script:expanded) { return }
    $isLog = ($script:settings.tab -eq 'log')
    Set-SegmentIndex $tabs $(if ($isLog) { 1 } else { 0 })
    $searchHost.Visible = -not $isLog; $lstTasks.Visible = -not $isLog
    $dayHost.Visible = $isLog; $lstLog.Visible = $isLog
    if ($isLog) { Refresh-Log } else { Refresh-TaskList }
    Restore-Hint
}
function Restore-Hint {
    $script:flashUntil = [datetime]::MinValue
    $lblHint.ForeColor = $TH.Faint
    $hkText = if ($script:hotkeyOk) { '  ·  Ctrl+Alt+T' } else { '' }
    if ($script:settings.tab -eq 'log') { Set-Text $lblHint ('Double-click to edit  ·  Del removes' + $hkText) }
    else { Set-Text $lblHint ('Enter start  ·  Space pause  ·  F1 help' + $hkText) }
}
function Flash([string]$msg) {
    if (-not $script:expanded) { return }
    $lblHint.ForeColor = $TH.Accent; Set-Text $lblHint $msg
    $script:flashUntil = (Get-Date).AddSeconds(3)
}

# ====================================================================== actions
function Get-SelectedTaskId {
    if ($script:settings.tab -eq 'log') {
        if ($lstLog.SelectedIndex -ge 0 -and $lstLog.SelectedIndex -lt $script:logRows.Count) { return $script:logRows[$lstLog.SelectedIndex].taskId }
    } elseif ($lstTasks.SelectedIndex -ge 0 -and $lstTasks.SelectedIndex -lt $script:taskRows.Count) {
        $r = $script:taskRows[$lstTasks.SelectedIndex]; if ($r.kind -eq 'task') { return $r.task.id }
    }
    if ($script:active) { return $script:active }
    return $script:lastTask
}
function Invoke-TaskRow([int]$i, [bool]$forceCreate = $false) {
    if ($forceCreate -or ($i -ge 0 -and $i -lt $script:taskRows.Count -and $script:taskRows[$i].kind -eq 'create')) {
        $q = $txtSearch.Text.Trim(); if (-not $q) { return }
        $qa = Split-QuickAdd $q
        $t = Add-Task $qa.name $qa.project
        Start-Task $t.id
        $txtSearch.Text = ''
        Refresh-All; Select-TaskRow $t.id; $lstTasks.Focus() | Out-Null
        Flash ('Started "{0}"' -f $t.name)
        return
    }
    if ($i -lt 0 -or $i -ge $script:taskRows.Count) { return }
    $t = $script:taskRows[$i].task
    if ($script:active -eq $t.id) { Pause-Task; Flash 'Paused' }
    else { Start-Task $t.id; Flash ('Started "{0}"' -f $t.name) }
    if ($txtSearch.Text) { $txtSearch.Text = '' }
    Refresh-All; Select-TaskRow $t.id
    if ($txtSearch.Focused) { $lstTasks.Focus() | Out-Null }
}
function Select-TaskRow([string]$id) {
    for ($i = 0; $i -lt $script:taskRows.Count; $i++) { if ($script:taskRows[$i].kind -eq 'task' -and $script:taskRows[$i].task.id -eq $id) { $lstTasks.SelectedIndex = $i; return } }
}
function Toggle-Primary {
    if ($script:active) { Pause-Task; Flash 'Paused  ·  Space to resume' }
    elseif ($script:pausedTask -or ($script:lastTask -and (Find-Task $script:lastTask))) { Resume-Task; Flash 'Resumed' }
    else { if (-not $script:expanded) { Open-Panel }; Set-Tab 'tasks'; $txtSearch.Focus() | Out-Null; Flash 'Pick a task or type a new one'; return }
    Refresh-All
}
function Invoke-AddButton {
    if ($txtSearch.Text.Trim()) { Invoke-TaskRow -1 $true; return }
    $txtSearch.Focus() | Out-Null
    Flash 'Type a task  ·  "Client: Task" sets the project'
}
function Refresh-All {
    if ($script:expanded) { if ($script:settings.tab -eq 'log') { Refresh-Log } else { Refresh-TaskList } }
    Update-Live -Full
}

# ---------------------------------------------------------------- live updates (called every second)
function Update-NowCard {
    $id = if ($script:active) { $script:active } elseif ($script:pausedTask) { $script:pausedTask } else { $null }
    $t = if ($id) { Find-Task $id } else { $null }
    if ($t) {
        $lblChip.ForeColor = Get-ProjectColor $t.project
        Set-Text $lblChip ([string][char]0x25CF + '  ' + $t.project.ToUpperInvariant())
        Set-Text $lblNowTask $t.name
        Set-Text $lblNowTime (Format-Clock (Get-TaskTodayTotal $id))
        if ($script:active) {
            $lblNowTime.ForeColor = $TH.Text
            Set-Text $lblNowMeta ('Session {0}  ·  since {1}' -f (Format-Short (Get-RunningSeconds)), $script:started.ToString('HH:mm'))
            $lblNowMeta.Cursor = [System.Windows.Forms.Cursors]::Hand
            Set-Btn $btnPrimary -glyph $GL.Pause
            if ($card.Tag.bar -ne $TH.Run) { $card.Tag.bar = $TH.Run; $card.Invalidate() }
        } else {
            $lblNowTime.ForeColor = $TH.Pause
            Set-Text $lblNowMeta ('Paused at {0}  ·  Space to resume' -f $script:pausedAt.ToString('HH:mm'))
            $lblNowMeta.Cursor = [System.Windows.Forms.Cursors]::Default
            Set-Btn $btnPrimary -glyph $GL.Play
            if ($card.Tag.bar -ne $TH.Pause) { $card.Tag.bar = $TH.Pause; $card.Invalidate() }
        }
        $btnStop.Visible = $true
    } else {
        $lblChip.ForeColor = $TH.Faint
        Set-Text $lblChip 'READY'
        Set-Text $lblNowTask 'Nothing running'
        $lblNowTime.ForeColor = $TH.Faint
        Set-Text $lblNowTime '0:00:00'
        $lt = if ($script:lastTask) { Find-Task $script:lastTask } else { $null }
        Set-Text $lblNowMeta $(if ($lt) { 'Press play to resume "' + $lt.name + '"' } else { 'Pick a task below, or type to add one' })
        $lblNowMeta.Cursor = [System.Windows.Forms.Cursors]::Default
        Set-Btn $btnPrimary -glyph $GL.Play
        $btnStop.Visible = $false
        if ($card.Tag.bar -ne $TH.Line) { $card.Tag.bar = $TH.Line; $card.Invalidate() }
    }
}
function Update-Tray {
    $txt = if ($script:active) { 'Tempo · ' + (Get-TaskName $script:active) + ' · ' + (Format-Short (Get-RunningSeconds)) }
           elseif ($script:pausedTask) { 'Tempo · paused · ' + (Get-TaskName $script:pausedTask) }
           else { 'SYMT Tempo · today ' + (Format-Short (Get-TodayTotal)) }
    if ($txt.Length -gt 63) { $txt = $txt.Substring(0, 62) + [char]0x2026 }
    if ($tray.Text -ne $txt) { $tray.Text = $txt }
    $icon = if ($script:active) { $script:iconRun } elseif ($script:pausedTask) { $script:iconPause } else { $script:iconIdle }
    if (-not [object]::ReferenceEquals($tray.Icon, $icon)) { $tray.Icon = $icon }
}
function Update-Live([switch]$Full) {
    if ($script:expanded) {
        Update-NowCard
        $stats.Invalidate()
        if ($Full) { $form.Invalidate((Rc 0 0 (P 40) (P 46))) }
        if ($script:active) {
            if ($script:settings.tab -eq 'log') {
                for ($i = 0; $i -lt $script:logRows.Count; $i++) {
                    if ($script:logRows[$i].running) { $script:logRows[$i].to = Get-Date; $script:logRows[$i].seconds = Get-RunningSeconds; Invalidate-Row $lstLog $i }
                }
                if ($script:logDay -eq (Get-Date).Date) { Set-Text $lblDayTotal (Format-Short (Get-DayTotal $script:logDay)) }
            } else {
                for ($i = 0; $i -lt $script:taskRows.Count; $i++) {
                    if ($script:taskRows[$i].kind -eq 'task' -and $script:taskRows[$i].task.id -eq $script:active) { Invalidate-Row $lstTasks $i; break }
                }
            }
        }
        if ($script:flashUntil -ne [datetime]::MinValue -and (Get-Date) -gt $script:flashUntil) { Restore-Hint }
    } elseif ($form.Visible) {
        $form.Invalidate()
    }
    Update-Tray
}

# ====================================================================== context menus
function New-Menu {
    $m = New-Object System.Windows.Forms.ContextMenuStrip
    $m.ShowImageMargin = $true
    $m.Font = $FN.Body
    $m.ForeColor = $TH.Text
    if ($script:native) { $m.Renderer = New-Object SymtTempo.DarkRenderer } else { $m.BackColor = $TH.Card; $m.ForeColor = $TH.Text }
    $m.Add_Opening({ $script:menuOpen = $true })
    $m.Add_Opened({ $script:menuOpen = $true })
    $m.Add_Closed({ $script:menuOpen = $false })
    return $m
}
function Add-MI($items, [string]$text, [scriptblock]$onClick, [bool]$enabled = $true, [bool]$checked = $false, [string]$keys = '', $tag = $null) {
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem($text)
    $mi.Enabled = $enabled; $mi.Checked = $checked
    if ($keys) { $mi.ShortcutKeyDisplayString = $keys }
    if (-not $script:native) { $mi.ForeColor = $TH.Text; $mi.BackColor = $TH.Card }
    if ($null -ne $tag) { $mi.Tag = $tag }
    if ($onClick) { $mi.Add_Click($onClick) }
    [void]$items.Add($mi)
    return $mi
}
function Add-Sep($items) { [void]$items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }

$script:menu = New-Menu
$script:menu.Add_Opening({ param($s, $e)
    $s.Items.Clear()
    $head = if ($script:active) { [string][char]0x25CF + '  ' + (Get-TaskName $script:active) + '  ·  ' + (Format-Short (Get-RunningSeconds)) }
            elseif ($script:pausedTask) { 'Paused  ·  ' + (Get-TaskName $script:pausedTask) }
            else { 'Today  ·  ' + (Format-Short (Get-TodayTotal)) }
    $h = Add-MI $s.Items $head $null $false; $h.Font = $FN.Strong
    Add-Sep $s.Items
    if ($script:active) { [void](Add-MI $s.Items 'Pause' { Toggle-Primary } $true $false 'Space') }
    else { [void](Add-MI $s.Items 'Resume' { Toggle-Primary } ([bool]($script:pausedTask -or $script:lastTask)) $false 'Space') }
    [void](Add-MI $s.Items 'Stop' { Stop-Task; Refresh-All } ([bool]($script:active -or $script:pausedTask)))
    $sw = Add-MI $s.Items 'Switch to' $null
    $recent = Get-RecentTasks 8
    if ($recent.Count -eq 0) { [void](Add-MI $sw.DropDownItems '(no tasks yet)' $null $false) }
    foreach ($t in $recent) {
        [void](Add-MI $sw.DropDownItems ($t.project + '  ·  ' + $t.name) { param($m, $a) Start-Task $m.Tag; Refresh-All } $true ($t.id -eq $script:active) '' $t.id)
    }
    if ($script:native) { $sw.DropDown.Renderer = $s.Renderer }
    Add-Sep $s.Items
    [void](Add-MI $s.Items 'Add time…' { Show-IntervalEditor -TaskId (Get-SelectedTaskId) -Day $(if ($script:settings.tab -eq 'log') { $script:logDay } else { (Get-Date).Date }) } $true $false 'Ctrl+M')
    [void](Add-MI $s.Items 'Export…' { Show-Export } $true $false 'Ctrl+E')
    Add-Sep $s.Items
    if ($script:expanded -and $form.Visible) { [void](Add-MI $s.Items 'Collapse to orb' { Collapse-Panel } $true $false 'Esc') }
    else { [void](Add-MI $s.Items 'Open panel' { Open-Panel } $true $false $(if ($script:hotkeyOk) { 'Ctrl+Alt+T' } else { '' })) }
    if ($form.Visible) { [void](Add-MI $s.Items 'Hide to tray' { Hide-ToTray }) } else { [void](Add-MI $s.Items 'Show floating orb' { Collapse-Panel }) }
    [void](Add-MI $s.Items 'Always on top' { $script:settings.topMost = -not [bool]$script:settings.topMost; $form.TopMost = [bool]$script:settings.topMost; Save-Settings } $true ([bool]$script:settings.topMost))
    [void](Add-MI $s.Items 'Settings…' { Show-Settings } $true $false 'Ctrl+,')
    [void](Add-MI $s.Items 'Help & shortcuts' { Show-Help } $true $false 'F1')
    [void](Add-MI $s.Items 'About SYMT Tempo' { Show-About })
    Add-Sep $s.Items
    [void](Add-MI $s.Items 'Exit' { Exit-App })
    $e.Cancel = $false
})
# A single placeholder item lets WinForms open a menu whose items are built in Opening.
[void]$script:menu.Items.Add('…')

$script:rowMenu = New-Menu
function Show-TaskMenu([int]$i, [System.Drawing.Point]$pt) {
    $r = $script:taskRows[$i]
    if ($r.kind -ne 'task') { return }
    $t = $r.task; $m = $script:rowMenu; $m.Items.Clear()
    $running = ($script:active -eq $t.id)
    [void](Add-MI $m.Items $(if ($running) { 'Pause' } else { 'Start' }) { param($x, $a) Invoke-TaskRowById $x.Tag } $true $false 'Enter' $t.id)
    [void](Add-MI $m.Items 'Add time…' { param($x, $a) Show-IntervalEditor -TaskId $x.Tag -Day (Get-Date).Date } $true $false '' $t.id)
    Add-Sep $m.Items
    [void](Add-MI $m.Items 'Rename…' { param($x, $a) Rename-Task $x.Tag } $true $false 'F2' $t.id)
    [void](Add-MI $m.Items 'Change project…' { param($x, $a) Move-TaskProject $x.Tag } $true $false '' $t.id)
    [void](Add-MI $m.Items $(if ($t.archived) { 'Restore from archive' } else { 'Archive' }) { param($x, $a) Toggle-Archive $x.Tag } $true $false 'Del' $t.id)
    Add-Sep $m.Items
    $del = Add-MI $m.Items 'Delete task…' { param($x, $a) Delete-Task $x.Tag } $true $false '' $t.id
    $del.ForeColor = $TH.Danger
    $m.Show($lstTasks, $pt)
}
function Show-LogMenu([int]$i, [System.Drawing.Point]$pt) {
    $r = $script:logRows[$i]; $m = $script:rowMenu; $m.Items.Clear()
    if ($r.running) {
        [void](Add-MI $m.Items 'Adjust start time…' { Show-AdjustStart })
        [void](Add-MI $m.Items 'Pause' { Toggle-Primary })
        [void](Add-MI $m.Items 'Stop' { Stop-Task; Refresh-All })
    } else {
        [void](Add-MI $m.Items 'Edit…' { param($x, $a) Show-IntervalEditor -IntervalId $x.Tag } $true $false 'Enter' $r.id)
        [void](Add-MI $m.Items 'Continue this task' { param($x, $a) Start-Task $x.Tag; Refresh-All } $true $false '' $r.taskId)
        Add-Sep $m.Items
        $del = Add-MI $m.Items 'Delete entry' { param($x, $a) Delete-Entry $x.Tag } $true $false 'Del' $r.id
        $del.ForeColor = $TH.Danger
    }
    $m.Show($lstLog, $pt)
}
function Invoke-TaskRowById([string]$id) {
    for ($i = 0; $i -lt $script:taskRows.Count; $i++) { if ($script:taskRows[$i].kind -eq 'task' -and $script:taskRows[$i].task.id -eq $id) { Invoke-TaskRow $i; return } }
}
function Rename-Task([string]$id) {
    $t = Find-Task $id; if (-not $t) { return }
    $v = Show-Prompt 'Rename task' 'Task name' $t.name
    if ($v) { $t.name = $v; Save-Data; Refresh-All; Flash 'Renamed' }
}
function Move-TaskProject([string]$id) {
    $t = Find-Task $id; if (-not $t) { return }
    $v = Show-Prompt 'Change project' 'Project / client' $t.project (Get-Projects)
    if ($v) { $t.project = $v; Save-Data; Refresh-All; Flash ('Moved to {0}' -f $v) }
}
function Toggle-Archive([string]$id) {
    $t = Find-Task $id; if (-not $t) { return }
    if (-not $t.archived -and ($script:active -eq $id -or $script:pausedTask -eq $id)) { Stop-Task }
    $t.archived = -not $t.archived; Save-Data; Refresh-All
    Flash $(if ($t.archived) { 'Archived  ·  search finds it again' } else { 'Restored' })
}
function Delete-Task([string]$id) {
    $t = Find-Task $id; if (-not $t) { return }
    $n = Get-TaskIntervalCount $id
    $msg = if ($n) { "Delete `"$($t.name)`" and its $n time entr$(if ($n -eq 1) { 'y' } else { 'ies' })? This cannot be undone. Archive keeps the history instead." } else { "Delete `"$($t.name)`"?" }
    if (-not (Show-Confirm 'Delete task' $msg 'Delete' 'danger')) { return }
    if ($script:active -eq $id -or $script:pausedTask -eq $id) { Stop-Recording; $script:pausedTask = $null }
    if ($script:lastTask -eq $id) { $script:lastTask = $null }
    Remove-Task $id; Refresh-All; Flash 'Task deleted'
}
function Delete-Entry([string]$id) {
    $i = Find-Interval $id; if (-not $i) { return }
    $sec = ((ConvertTo-Dt $i.end) - (ConvertTo-Dt $i.start)).TotalSeconds
    if (-not (Show-Confirm 'Delete entry' ("Remove {0} on `"{1}`"?" -f (Format-Short $sec), (Get-TaskName $i.taskId)) 'Delete' 'danger')) { return }
    Remove-Interval $id; Refresh-All; Flash 'Entry deleted'
}
function Edit-LogRow([int]$i) {
    if ($i -lt 0 -or $i -ge $script:logRows.Count) { return }
    $r = $script:logRows[$i]
    if ($r.running) { Show-AdjustStart } else { Show-IntervalEditor -IntervalId $r.id }
}

# ====================================================================== editors
function Parse-TimeText([string]$s) {
    $m = [regex]::Match($s.Trim(), '^(\d{1,2})(?:\s*[:.h]\s*(\d{1,2})|(\d{2}))?$')
    if (-not $m.Success) { return $null }
    $h = [int]$m.Groups[1].Value
    $mi = if ($m.Groups[2].Success) { [int]$m.Groups[2].Value } elseif ($m.Groups[3].Success) { [int]$m.Groups[3].Value } else { 0 }
    if ($h -gt 23 -or $mi -gt 59) { return $null }
    return New-Object TimeSpan($h, $mi, 0)
}
function Show-AdjustStart {
    if (-not $script:active) { return }
    $W = 360; $H = 236
    $d = New-Dialog 'Adjust start time' $W $H
    [void](New-Lbl $d ('Tracking "{0}". Forgot to start on time? Move the start back.' -f (Get-TaskName $script:active)) 20 48 ($W - 40) 34 $FN.Small $TH.Muted 'TopLeft')
    $tb = New-Field $d 20 88 110 ($script:started.ToString('HH:mm'))
    $d.Tag.tb = $tb
    $x = 140
    foreach ($m in @(5, 10, 15, 30)) {
        $b = New-Btn -Parent $d -Text ('-{0}m' -f $m) -X $x -Y 88 -W 46 -H 34 -Kind 'ghost' -TextFont $FN.Small -OnClick { param($b) $f = $b.FindForm(); $f.Tag.tb.Text = $script:started.AddMinutes(-$b.Tag.mins).ToString('HH:mm') }
        $b.Tag.mins = $m; $x += 50
    }
    $d.Tag.err = New-Lbl $d '' 20 128 ($W - 40) 20 $FN.Small $TH.Danger
    [void](Add-DialogButtons $d 'Apply' 'primary' 'Cancel' $W $H)
    $d.Tag.accept = { param($f)
        $ts = Parse-TimeText $f.Tag.tb.Text
        if ($null -eq $ts) { $f.Tag.err.Text = 'Use a time like 09:30'; return }
        $now = Get-Date
        $new = $script:started.Date.Add($ts)
        if ($new -gt $now) { $new = $new.AddDays(-1) }
        if (($now - $new).TotalHours -gt 24) { $f.Tag.err.Text = 'Start must be within the last 24 hours'; return }
        $f.Tag.result = $new; $f.DialogResult = 'OK'
    }
    $d.Add_Shown({ param($s, $e) $s.Tag.tb.Focus(); $s.Tag.tb.SelectAll() })
    if ((Invoke-Modal $d) -eq 'OK' -and $script:active) {
        $script:started = [datetime]$d.Tag.result; Write-Session; Refresh-All; Flash ('Start moved to {0}' -f $script:started.ToString('HH:mm'))
    }
    $d.Dispose()
}

function Show-IntervalEditor {
    param([string]$IntervalId = $null, [string]$TaskId = $null, [Nullable[datetime]]$Day = $null)
    $editing = $null
    if ($IntervalId) { $editing = Find-Interval $IntervalId; if (-not $editing) { return } }
    if (-not $editing -and $script:tasks.Count -eq 0) { Show-Info 'Add time' 'Create a task first: type its name in the search box and press Enter.'; return }
    $W = 400; $H = 452
    $d = New-Dialog $(if ($editing) { 'Edit time entry' } else { 'Add time' }) $W $H
    $ctx = $d.Tag
    # task picker
    [void](New-Lbl $d 'TASK' 20 50 100 18 $FN.SmallB $TH.Faint)
    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.DropDownStyle = 'DropDownList'; $cb.FlatStyle = 'Flat'; $cb.DrawMode = 'OwnerDrawFixed'; $cb.ItemHeight = (P 24)
    $cb.BackColor = $TH.Field; $cb.ForeColor = $TH.Text; $cb.Font = $FN.Body; $cb.MaxDropDownItems = 12
    $cb.Location = New-Object System.Drawing.Point((P 20), (P 70)); $cb.Width = (P ($W - 40))
    $cb.Add_DrawItem({ param($s, $e)
        if ($e.Index -lt 0) { return }
        $t = $s.Items[$e.Index]
        $sel = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
        $e.Graphics.FillRectangle((Br $(if ($sel) { $TH.Hover } else { $TH.Field })), $e.Bounds)
        $e.Graphics.SmoothingMode = 'AntiAlias'
        $cy = $e.Bounds.Y + $e.Bounds.Height / 2
        $e.Graphics.FillEllipse((Br (Get-ProjectColor $t.project)), (RcF ($e.Bounds.X + (P 6)) ($cy - (P 3.5)) (P 7) (P 7)))
        Txt $e.Graphics ($t.project + '  ·  ' + $t.name) $FN.Body (Rc ($e.Bounds.X + (P 20)) $e.Bounds.Y ($e.Bounds.Width - (P 22)) $e.Bounds.Height) $TH.Text $TF_L
    })
    $pick = @($script:tasks | Where-Object { -not $_.archived -or $_.id -eq $TaskId -or ($editing -and $_.id -eq $editing.taskId) } | Sort-Object project, name)
    foreach ($t in $pick) { [void]$cb.Items.Add($t) }
    $want = if ($editing) { $editing.taskId } elseif ($TaskId) { $TaskId } else { $script:lastTask }
    for ($i = 0; $i -lt $cb.Items.Count; $i++) { if ($cb.Items[$i].id -eq $want) { $cb.SelectedIndex = $i } }
    if ($cb.SelectedIndex -lt 0 -and $cb.Items.Count) { $cb.SelectedIndex = 0 }
    $d.Controls.Add($cb); $ctx.cb = $cb
    # date
    [void](New-Lbl $d 'DATE' 20 110 100 18 $FN.SmallB $TH.Faint)
    $ctx.day = if ($editing) { (ConvertTo-Dt $editing.start).Date } elseif ($Day) { ([datetime]$Day).Date } else { (Get-Date).Date }
    $ctx.lblDate = New-Lbl $d '' 56 130 ($W - 112) 34 $FN.Strong $TH.Text 'MiddleCenter'
    [void](New-Btn -Parent $d -Glyph $GL.Back -X 20 -Y 130 -W 34 -H 34 -Kind 'ghost' -OnClick { param($b) $f = $b.FindForm(); $f.Tag.day = $f.Tag.day.AddDays(-1); & $f.Tag.update $f })
    [void](New-Btn -Parent $d -Glyph $GL.Fwd -X ($W - 54) -Y 130 -W 34 -H 34 -Kind 'ghost' -OnClick { param($b) $f = $b.FindForm(); if ($f.Tag.day -lt (Get-Date).Date) { $f.Tag.day = $f.Tag.day.AddDays(1); & $f.Tag.update $f } })
    # times
    [void](New-Lbl $d 'START' 20 172 100 18 $FN.SmallB $TH.Faint)
    [void](New-Lbl $d 'END' 132 172 100 18 $FN.SmallB $TH.Faint)
    [void](New-Lbl $d 'DURATION' 244 172 120 18 $FN.SmallB $TH.Faint)
    if ($editing) { $s0 = (ConvertTo-Dt $editing.start).ToString('HH:mm'); $e0 = (ConvertTo-Dt $editing.end).ToString('HH:mm') }
    else {
        $endDefault = if ($ctx.day -eq (Get-Date).Date) { Get-Date } else { $ctx.day.AddHours(17) }
        $s0 = $endDefault.AddMinutes(-30).ToString('HH:mm'); $e0 = $endDefault.ToString('HH:mm')
    }
    $ctx.tbStart = New-Field $d 20 192 102 $s0
    $ctx.tbEnd = New-Field $d 132 192 102 $e0
    $ctx.lblDur = New-Lbl $d '' 244 192 136 34 $FN.Title $TH.Text
    # presets
    $x = 20
    foreach ($p in @(@('15m', 15), @('30m', 30), @('45m', 45), @('1h', 60), @('2h', 120))) {
        $b = New-Btn -Parent $d -Text $p[0] -X $x -Y 236 -W 52 -H 30 -Kind 'ghost' -TextFont $FN.Small -Tip ('Set start to end minus ' + $p[0]) -OnClick { param($b)
            $f = $b.FindForm(); $e = Parse-TimeText $f.Tag.tbEnd.Text
            if ($null -eq $e) { $e = (Get-Date).TimeOfDay }
            $st = $f.Tag.day.Add($e).AddMinutes(-$b.Tag.mins)
            $f.Tag.tbStart.Text = $st.ToString('HH:mm')
        }
        $b.Tag.mins = $p[1]; $x += 56
    }
    [void](New-Btn -Parent $d -Text 'Until now' -X $x -Y 236 -W ($W - 20 - $x) -H 30 -Kind 'ghost' -TextFont $FN.Small -Tip 'Set end to the current time (today)' -OnClick { param($b)
        $f = $b.FindForm(); $f.Tag.day = (Get-Date).Date; $f.Tag.tbEnd.Text = (Get-Date).ToString('HH:mm'); & $f.Tag.update $f })
    # note
    [void](New-Lbl $d 'NOTE' 20 278 100 18 $FN.SmallB $TH.Faint)
    $ctx.tbNote = New-Field $d 20 298 ($W - 40) $(if ($editing) { $editing.note } else { '' }) 'Optional — what you worked on'
    $ctx.lblWarn = New-Lbl $d '' 20 340 ($W - 40) 40 $FN.Small $TH.Pause 'TopLeft'
    $ctx.lblWarn.AutoEllipsis = $false
    # buttons
    [void](Add-DialogButtons $d 'Save' 'primary' 'Cancel' $W $H)
    if ($editing) {
        $ctx.deleteId = $editing.id
        [void](New-Btn -Parent $d -Text 'Delete' -X 20 -Y ($H - 56) -W 84 -H 36 -Kind 'danger' -OnClick { param($b) $f = $b.FindForm(); $f.Tag.result = 'delete'; $f.DialogResult = 'OK' })
    }
    $ctx.editId = if ($editing) { $editing.id } else { $null }
    # live validation
    $ctx.compute = { param($f)
        $c = $f.Tag; $a = Parse-TimeText $c.tbStart.Text; $b = Parse-TimeText $c.tbEnd.Text
        if ($null -eq $a -or $null -eq $b) { return $null }
        $from = $c.day.Add($a); $to = $c.day.Add($b)
        if ($to -le $from) { $to = $to.AddDays(1) }
        return @($from, $to)
    }
    $ctx.update = { param($f)
        $c = $f.Tag
        $today = (Get-Date).Date
        $c.lblDate.Text = if ($c.day -eq $today) { 'Today  ·  ' + $c.day.ToString('ddd d MMM') } elseif ($c.day -eq $today.AddDays(-1)) { 'Yesterday  ·  ' + $c.day.ToString('ddd d MMM') } else { $c.day.ToString('dddd d MMMM yyyy') }
        $r = & $c.compute $f
        if ($null -eq $r) { $c.lblDur.Text = '—'; $c.lblDur.ForeColor = $TH.Faint; $c.lblWarn.ForeColor = $TH.Danger; $c.lblWarn.Text = 'Times look like 09:30, 930 or 9.30'; return }
        $sec = ($r[1] - $r[0]).TotalSeconds
        $c.lblDur.ForeColor = $TH.Text
        $c.lblDur.Text = (Format-Short $sec) + $(if ($r[1].Date -gt $r[0].Date) { '  (+1 day)' } else { '' })
        $warn = @()
        if ($r[1] -gt (Get-Date).AddMinutes(1)) { $warn += 'Ends in the future.' }
        if ($sec -gt 12 * 3600) { $warn += 'Longer than 12 hours — double-check the times.' }
        $ov = Get-Overlaps $r[0] $r[1] $c.editId
        if ($ov) { $warn += ('Overlaps {0} other entr{1}.' -f $ov, $(if ($ov -eq 1) { 'y' } else { 'ies' })) }
        $c.lblWarn.ForeColor = $TH.Pause
        $c.lblWarn.Text = ($warn -join '  ')
    }
    foreach ($tb in @($ctx.tbStart, $ctx.tbEnd)) { $tb.Add_TextChanged({ param($s, $e) $f = $s.FindForm(); if ($f) { & $f.Tag.update $f } }) }
    $ctx.accept = { param($f)
        $c = $f.Tag
        if ($c.cb.SelectedIndex -lt 0) { $c.lblWarn.ForeColor = $TH.Danger; $c.lblWarn.Text = 'Choose a task.'; return }
        $r = & $c.compute $f
        if ($null -eq $r) { $c.lblWarn.ForeColor = $TH.Danger; $c.lblWarn.Text = 'Times look like 09:30, 930 or 9.30'; return }
        $c.result = @{ taskId = $c.cb.SelectedItem.id; from = $r[0]; to = $r[1]; note = $c.tbNote.Text.Trim() }
        $f.DialogResult = 'OK'
    }
    & $ctx.update $d
    $d.Add_Shown({ param($s, $e) $s.Tag.tbStart.Focus(); $s.Tag.tbStart.SelectAll() })
    $res = Invoke-Modal $d
    $out = $ctx.result; $delId = $ctx.deleteId
    $d.Dispose()
    if ($res -ne 'OK' -or $null -eq $out) { return }
    if ($out -is [string] -and $out -eq 'delete') { Delete-Entry $delId; return }
    if ($editing) { [void](Set-Interval $editing.id $out.taskId $out.from $out.to $out.note); Flash 'Entry updated' }
    else { [void](Add-Interval $out.taskId $out.from $out.to $out.note 'manual'); Touch-Task $out.taskId; Save-Data; Flash ('Added {0}' -f (Format-Short ($out.to - $out.from).TotalSeconds)) }
    if ($script:expanded -and $script:settings.tab -eq 'log') { $script:logDay = $out.from.Date }
    Refresh-All
}

function Show-Export {
    $W = 420; $H = 330
    $d = New-Dialog 'Export' $W $H
    $ctx = $d.Tag
    $ctx.ranges = @('today', 'week', 'lastweek', 'month', 'all')
    [void](New-Lbl $d 'RANGE' 20 50 100 18 $FN.SmallB $TH.Faint)
    $ctx.segRange = New-Segment $d 20 70 ($W - 40) @('Today', 'This week', 'Last week', 'Month', 'All') 1 { param($s) $f = $s.FindForm(); & $f.Tag.preview $f } 32 $FN.Small
    [void](New-Lbl $d 'FORMAT' 20 114 100 18 $FN.SmallB $TH.Faint)
    $ctx.segFmt = New-Segment $d 20 134 ($W - 40) @('Detailed CSV', 'Summary CSV', 'JSON') 0 { param($s) $f = $s.FindForm(); & $f.Tag.preview $f } 32 $FN.Small
    $ctx.lblPrev = New-Lbl $d '' 20 180 ($W - 40) 60 $FN.Body $TH.Muted 'TopLeft'
    $ctx.lblPrev.AutoEllipsis = $false
    [void](Add-DialogButtons $d 'Export…' 'primary' 'Cancel' $W $H)
    $ctx.preview = { param($f)
        $c = $f.Tag; $b = Get-RangeBounds $c.ranges[$c.segRange.Tag.index]
        $rows = Get-ExportRows $b[0] $b[1]
        $sum = 0.0; foreach ($r in $rows) { $sum += $r.minutes * 60 }
        $projects = @($rows | ForEach-Object { $_.project } | Sort-Object -Unique).Count
        $span = if ($c.ranges[$c.segRange.Tag.index] -eq 'all') { 'All recorded time' } else { '{0:ddd d MMM} – {1:ddd d MMM yyyy}' -f $b[0], $b[1].AddDays(-1) }
        $kind = @('One row per time entry, ready for timesheets.', 'Hours per project and task.', 'Entries as JSON for other tools.')[$c.segFmt.Tag.index]
        $c.lblPrev.Text = "$span`r`n$($rows.Count) entries  ·  $projects project$(if ($projects -ne 1) { 's' })  ·  $(Format-Short $sum)`r`n$kind"
        $c.count = $rows.Count
    }
    $ctx.accept = { param($f) $f.DialogResult = 'OK' }
    & $ctx.preview $d
    $res = Invoke-Modal $d
    $range = $ctx.ranges[$ctx.segRange.Tag.index]; $fmt = $ctx.segFmt.Tag.index
    $d.Dispose()
    if ($res -ne 'OK') { return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $ext = if ($fmt -eq 2) { 'json' } else { 'csv' }
    $sfd.Filter = if ($fmt -eq 2) { 'JSON files (*.json)|*.json' } else { 'CSV files (*.csv)|*.csv' }
    $sfd.FileName = 'SYMT-Tempo-{0}-{1}{2}.{3}' -f $range, (Get-Date -Format 'yyyyMMdd'), $(if ($fmt -eq 1) { '-summary' } else { '' }), $ext
    $script:modal++
    try { $ok = $sfd.ShowDialog($form) -eq 'OK' } finally { $script:modal-- }
    if (-not $ok) { $sfd.Dispose(); return }
    $path = $sfd.FileName; $sfd.Dispose()
    try {
        $b = Get-RangeBounds $range
        switch ($fmt) {
            0 { $rows = Get-ExportRows $b[0] $b[1]
                if ($rows.Count) { $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $path }
                else { [System.IO.File]::WriteAllText($path, 'date,project,task,start,end,minutes,hours,note,source' + [Environment]::NewLine) } }
            1 { $rows = Get-SummaryRows $b[0] $b[1]
                if ($rows.Count) { $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $path }
                else { [System.IO.File]::WriteAllText($path, 'project,task,hours,minutes' + [Environment]::NewLine) } }
            2 { ConvertTo-Json -InputObject @(Get-ExportRows $b[0] $b[1]) -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8 }
        }
        Flash ('Exported to {0}' -f [System.IO.Path]::GetFileName($path))
        $tray.ShowBalloonTip(3000, 'Export complete', $path, 'Info')
    } catch { Show-Info 'Export failed' $_.Exception.Message }
}

# ---------------------------------------------------------------- settings / help / about
$script:startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'SYMT Tempo.lnk'
function Set-Autostart([bool]$on) {
    try {
        if ($on) {
            $sh = New-Object -ComObject WScript.Shell
            $lnk = $sh.CreateShortcut($script:startupLnk)
            $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
            $lnk.Arguments = '"' + (Join-Path $root 'Launch-SYMT-Tempo.vbs') + '"'
            $lnk.WorkingDirectory = $root
            $lnk.IconLocation = $iconPath
            $lnk.Description = 'SYMT Tempo'
            $lnk.Save()
        } elseif (Test-Path -LiteralPath $script:startupLnk) { Remove-Item -LiteralPath $script:startupLnk -Force }
    } catch { Show-Info 'Launch at sign-in' $_.Exception.Message }
}
function Show-Settings {
    $W = 420; $H = 520
    $d = New-Dialog 'Settings' $W $H
    $c = $d.Tag
    [void](New-Lbl $d 'TRACKING' 20 52 200 18 $FN.SmallB $TH.Accent)
    [void](New-Lbl $d 'Ask about idle time after' 20 74 ($W - 40) 20 $FN.Body $TH.Text)
    $idleOpts = @(0, 5, 10, 15, 30)
    $ii = [array]::IndexOf($idleOpts, [int]$script:settings.idleMinutes); if ($ii -lt 0) { $ii = 2 }
    $c.segIdle = New-Segment $d 20 96 ($W - 40) @('Off', '5 min', '10 min', '15 min', '30 min') $ii $null 30 $FN.Small
    if (-not $script:native) { $c.segIdle.Tag.enabled = $false; Set-Tip $c.segIdle 'Idle detection is unavailable on this PC (native helper blocked).' }
    [void](New-Lbl $d 'Daily target' 20 136 ($W - 40) 20 $FN.Body $TH.Text)
    $tgtOpts = @(0.0, 6.0, 7.0, 7.5, 8.0)
    $ti = [array]::IndexOf($tgtOpts, [double]$script:settings.dailyTargetHours); if ($ti -lt 0) { $ti = 3 }
    $c.segTarget = New-Segment $d 20 158 ($W - 40) @('Off', '6h', '7h', '7.5h', '8h') $ti $null 30 $FN.Small
    [void](New-Lbl $d 'WINDOW' 20 206 200 18 $FN.SmallB $TH.Accent)
    [void](New-Lbl $d 'On launch show' 20 228 ($W - 40) 20 $FN.Body $TH.Text)
    $sv = @('orb', 'panel', 'tray'); $si = [array]::IndexOf($sv, [string]$script:settings.startView); if ($si -lt 0) { $si = 0 }
    $c.segStart = New-Segment $d 20 250 ($W - 40) @('Floating orb', 'Panel', 'Tray only') $si $null 30 $FN.Small
    $c.tTop = New-Toggle $d 20 290 ($W - 40) 'Always on top' ([bool]$script:settings.topMost)
    $c.tHot = New-Toggle $d 20 322 ($W - 40) 'Global shortcut  Ctrl+Alt+T' ([bool]$script:settings.hotkey) 'Opens or collapses the panel from anywhere'
    if (-not $script:native) { $c.tHot.Tag.enabled = $false }
    $c.tAuto = New-Toggle $d 20 354 ($W - 40) 'Launch at Windows sign-in' (Test-Path -LiteralPath $script:startupLnk)
    $c.tArch = New-Toggle $d 20 386 ($W - 40) 'Show archived tasks in the list' ([bool]$script:settings.showArchived)
    [void](New-Btn -Parent $d -Text 'Open data folder' -X 20 -Y ($H - 56) -W 130 -H 36 -Kind 'link' -TextFont $FN.Body -OnClick { Start-Process explorer.exe $script:dataDir })
    [void](Add-DialogButtons $d 'Save' 'primary' 'Cancel' $W $H)
    $c.accept = { param($f) $f.DialogResult = 'OK' }
    if ((Invoke-Modal $d) -eq 'OK') {
        $s = $script:settings
        $s.idleMinutes = $idleOpts[$c.segIdle.Tag.index]
        $s.dailyTargetHours = $tgtOpts[$c.segTarget.Tag.index]
        $s.startView = $sv[$c.segStart.Tag.index]
        $s.topMost = [bool]$c.tTop.Tag.checked; $form.TopMost = $s.topMost
        $hotChanged = ([bool]$s.hotkey -ne [bool]$c.tHot.Tag.checked)
        $s.hotkey = [bool]$c.tHot.Tag.checked
        $s.showArchived = [bool]$c.tArch.Tag.checked
        if ([bool]$c.tAuto.Tag.checked -ne (Test-Path -LiteralPath $script:startupLnk)) { Set-Autostart ([bool]$c.tAuto.Tag.checked) }
        Save-Settings
        if ($hotChanged) { Register-Hotkey }
        Refresh-All; $stats.Invalidate(); Flash 'Settings saved'
    }
    $d.Dispose()
}
function Show-Help {
    $rows = @(
        @('Enter', 'Start the selected task (or create it)'), @('Space', 'Pause / resume'), @('Type anywhere', 'Search tasks; Enter on "Create" adds one'),
        @('Client: Task', 'Quick-add syntax that sets the project'), @('Ctrl+Enter', 'Always create a new task from the search text'),
        @('Ctrl+N / Ctrl+F', 'Focus search'), @('Ctrl+1 / Ctrl+2', 'Tasks / Log tab'), @('← →  (Log)', 'Previous / next day'),
        @('Ctrl+M', 'Add time manually'), @('F2', 'Rename task / edit entry'), @('Del', 'Archive task / delete entry'),
        @('Ctrl+E', 'Export'), @('Ctrl+,', 'Settings'), @('Esc', 'Clear search, then collapse to orb'), @('Ctrl+Alt+T', 'Toggle the panel from anywhere')
    )
    $W = 440; $H = 132 + $rows.Count * 24 + 64
    $d = New-Dialog 'Help & shortcuts' $W $H
    [void](New-Lbl $d 'Click the orb to open the panel, drag it anywhere (it snaps to screen edges). Right-click the orb or tray icon for quick switching. Tempo asks what to do with idle time and recovers a running timer after a crash.' 20 48 ($W - 40) 64 $FN.Small $TH.Muted 'TopLeft')
    $y = 118
    foreach ($r in $rows) {
        [void](New-Lbl $d $r[0] 20 $y 130 22 $FN.SmallB $TH.Accent)
        [void](New-Lbl $d $r[1] 152 $y ($W - 172) 22 $FN.Small $TH.Text)
        $y += 24
    }
    [void](Add-DialogButtons $d 'Got it' 'primary' '' $W $H)
    [void](New-Btn -Parent $d -Text 'Open README' -X 20 -Y ($H - 56) -W 120 -H 36 -Kind 'link' -TextFont $FN.Body -OnClick { Start-Process notepad.exe (Join-Path $root 'README.md') })
    $d.Tag.accept = { param($f) $f.DialogResult = 'OK' }
    [void](Invoke-Modal $d); $d.Dispose()
}
function Show-About {
    $W = 430; $H = 440
    $d = New-Dialog 'About SYMT Tempo' $W $H
    $logoPath = Join-Path $root 'Assets\SYMT-Logo-Transparent.png'
    if (Test-Path $logoPath) {
        $pic = New-Object System.Windows.Forms.PictureBox
        $pic.Location = New-Object System.Drawing.Point((P 24),(P 44))
        $pic.Size = New-Object System.Drawing.Size((P 365),(P 100))
        $pic.SizeMode = 'Zoom'
        $pic.BackColor = $d.BackColor  # Blend with the About dialog's own navy background
        $pic.Image = [System.Drawing.Image]::FromFile($logoPath)
        $d.Controls.Add($pic)
        $d.Add_FormClosed({ if ($pic.Image) { $pic.Image.Dispose() } })
    }
    [void](New-Lbl $d 'SYMT Tempo' 20 148 ($W - 40) 28 (Fnt 'Segoe UI Semibold' 16) $TH.Text)
    [void](New-Lbl $d ("Version $script:TempoVersion  |  Free Personal Use Edition") 20 180 ($W - 40) 20 $FN.Small $TH.Accent)
    $txt = "(c) 2026 SYMT Limited. All rights reserved.`r`nwww.symt.co.uk`r`n`r`nSYMT name, identity and supplied logo artwork are used as SYMT branding. No registered-trademark status is asserted.`r`n`r`nProvided AS IS, without warranty, to the extent permitted by applicable law. No guarantee of time-record accuracy or data preservation. See LICENSE.txt and TERMS.txt for details."
    [void](New-Lbl $d $txt 20 212 ($W - 40) 140 $FN.Small $TH.Muted 'TopLeft')
    [void](Add-DialogButtons $d 'Close' 'primary' '' $W $H)
    [void](New-Btn -Parent $d -Text 'Licence / T&C' -X 18 -Y ($H - 56) -W 128 -H 36 -Kind 'link' -TextFont $FN.Body -OnClick { Start-Process notepad.exe (Join-Path $root 'TERMS.txt') })
    [void](New-Btn -Parent $d -Text 'Website' -X 150 -Y ($H - 56) -W 83 -H 36 -Kind 'link' -TextFont $FN.Body -OnClick { Start-Process 'https://www.symt.co.uk' })
    $d.Tag.accept = { param($f) $f.DialogResult = 'OK' }
    [void](Invoke-Modal $d); $d.Dispose()
}

# ====================================================================== keyboard
# Note: compare KeyCode with -eq (string is parsed to the enum). A string switch would fail for Enter,
# because Keys.Enter and Keys.Return share a value and stringify as "Return".
$form.Add_KeyDown({ param($s, $e)
    $k = $e.KeyCode; $ctrl = $e.Control
    $handled = $true
    $onLog = ($script:settings.tab -eq 'log')
    $ti = $lstTasks.SelectedIndex
    $selTask = $null
    if ($ti -ge 0 -and $ti -lt $script:taskRows.Count -and $script:taskRows[$ti].kind -eq 'task') { $selTask = $script:taskRows[$ti].task }
    if ($ctrl -and ($k -eq 'N' -or $k -eq 'F')) { Set-Tab 'tasks'; $txtSearch.Focus() | Out-Null; $txtSearch.SelectAll() }
    elseif ($ctrl -and ($k -eq 'D1' -or $k -eq 'T')) { Set-Tab 'tasks' }
    elseif ($ctrl -and ($k -eq 'D2' -or $k -eq 'L')) { Set-Tab 'log' }
    elseif ($ctrl -and $k -eq 'E') { Show-Export }
    elseif ($ctrl -and $k -eq 'M') { Show-IntervalEditor -TaskId (Get-SelectedTaskId) -Day $(if ($onLog) { $script:logDay } else { (Get-Date).Date }) }
    elseif ($ctrl -and $k -eq 'Oemcomma') { Show-Settings }
    elseif ($k -eq 'F1') { Show-Help }
    elseif ($txtSearch.Focused) {
        if ($k -eq 'Down') { if ($lstTasks.Items.Count) { $lstTasks.SelectedIndex = [math]::Min($lstTasks.Items.Count - 1, $ti + 1) } }
        elseif ($k -eq 'Up') { if ($lstTasks.Items.Count) { $lstTasks.SelectedIndex = [math]::Max(0, $ti - 1) } }
        elseif ($k -eq 'Return') {
            if ($ctrl) { Invoke-TaskRow -1 $true }
            elseif ($ti -ge 0) { Invoke-TaskRow $ti }
            elseif ($txtSearch.Text.Trim()) { Invoke-TaskRow -1 $true }
        }
        elseif ($k -eq 'Escape') { if ($txtSearch.Text) { $txtSearch.Text = '' } else { Collapse-Panel } }
        else { $handled = $false }
    }
    elseif ($k -eq 'Space') {
        # Space on a different task starts it; otherwise it pauses / resumes the current one
        if (-not $onLog -and $selTask -and $selTask.id -ne $script:active -and $selTask.id -ne $script:pausedTask) { Invoke-TaskRow $ti } else { Toggle-Primary }
    }
    elseif ($k -eq 'Return') { if ($onLog) { Edit-LogRow $lstLog.SelectedIndex } else { Invoke-TaskRow $ti } }
    elseif ($k -eq 'F2') { if ($onLog) { Edit-LogRow $lstLog.SelectedIndex } elseif ($selTask) { Rename-Task $selTask.id } }
    elseif ($k -eq 'Delete') {
        if ($onLog) { $li = $lstLog.SelectedIndex; if ($li -ge 0 -and $li -lt $script:logRows.Count -and -not $script:logRows[$li].running) { Delete-Entry $script:logRows[$li].id } }
        elseif ($selTask) { Toggle-Archive $selTask.id }
    }
    elseif ($onLog -and $k -eq 'Left') { Set-LogDay ($script:logDay.AddDays(-1)) }
    elseif ($onLog -and $k -eq 'Right') { Set-LogDay ($script:logDay.AddDays(1)) }
    elseif ($k -eq 'Escape') { Collapse-Panel }
    else { $handled = $false }
    if ($handled) { $e.Handled = $true; $e.SuppressKeyPress = $true }
})
$txtSearch.Add_TextChanged({ Refresh-TaskList })

# ====================================================================== tray
function New-StateIcon([System.Drawing.Color]$dot) {
    $sz = [System.Windows.Forms.SystemInformation]::SmallIconSize
    $base = New-Object System.Drawing.Icon($iconPath, $sz)
    $bmp = $base.ToBitmap(); $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
    $r = [int]($sz.Width * 0.5)
    $g.FillEllipse((Br $TH.Bg), ($sz.Width - $r - 1), ($sz.Height - $r - 1), ($r + 1), ($r + 1))
    $g.FillEllipse((Br $dot), ($sz.Width - $r), ($sz.Height - $r), ($r - 1), ($r - 1))
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$script:iconIdle = New-Object System.Drawing.Icon($iconPath, [System.Windows.Forms.SystemInformation]::SmallIconSize)
try { $script:iconRun = New-StateIcon $TH.Run; $script:iconPause = New-StateIcon $TH.Pause } catch { $script:iconRun = $script:iconIdle; $script:iconPause = $script:iconIdle }
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $script:iconIdle; $tray.Text = 'SYMT Tempo'; $tray.Visible = $true
$tray.ContextMenuStrip = $script:menu
$tray.Add_MouseClick({ param($s, $e)
    if ($e.Button -ne 'Left') { return }
    if (((Get-Date) - $script:lastAutoCollapse).TotalMilliseconds -lt 400) { return }
    Toggle-Panel
})
function Flash-Tray([string]$msg) { try { $tray.ShowBalloonTip(2500, 'SYMT Tempo', $msg, 'None') } catch { } }
$form.ContextMenuStrip = $null
$form.Add_MouseUp({ param($s, $e) if ($e.Button -eq 'Right' -and -not $script:expanded) { $script:menu.Show($form, $e.Location) } })

# ====================================================================== global hotkey
$script:hotkeyOk = $false
$script:hk = $null
function Register-Hotkey {
    $script:hotkeyOk = $false
    if (-not $script:native) { return }
    try {
        if ($null -eq $script:hk) {
            $script:hk = New-Object SymtTempo.HotKey
            $script:hk.add_Pressed({ Toggle-Panel })
        }
        if ($script:settings.hotkey) { $script:hotkeyOk = $script:hk.Register(3, [System.Windows.Forms.Keys]::T) } else { $script:hk.Unregister() }
    } catch { $script:hotkeyOk = $false }
    Restore-Hint
}

# ====================================================================== idle + sleep detection
$script:idleSince = $null
$script:prompting = $false
$script:lastTick = Get-Date
$script:lastBeat = Get-Date
$script:lastSecond = -1
function Check-Idle {
    if (-not $script:active) { $script:idleSince = $null; return }
    if ($script:prompting -or $script:modal -gt 0) { return }
    if ($script:idleSince) {
        $back = $true
        if ($script:native) { $back = ([SymtTempo.Native]::IdleSeconds() -lt 3) }
        if ($back) { Prompt-Idle }
        return
    }
    if ($script:native -and [int]$script:settings.idleMinutes -gt 0) {
        $idle = [SymtTempo.Native]::IdleSeconds()
        if ($idle -ge [int]$script:settings.idleMinutes * 60) { $script:idleSince = (Get-Date).AddSeconds(-$idle) }
    }
}
function Prompt-Idle {
    $script:prompting = $true
    try {
        $since = if ($script:idleSince -lt $script:started) { $script:started } else { $script:idleSince }
        $away = ((Get-Date) - $since).TotalSeconds
        if ($away -lt 60 -or -not $script:active) { return }
        $name = Get-TaskName $script:active
        $msg = 'You were away for {0} (since {1}) while tracking "{2}".' -f (Format-Short $away), $since.ToString('HH:mm'), $name
        $choice = Show-Choice 'Welcome back' $msg @('Discard the idle time and keep tracking', 'Keep the idle time', ('Discard and stop at {0}' -f $since.ToString('HH:mm'))) 0
        switch ($choice) {
            0 { $id = $script:active; Stop-Recording $since; Start-Task $id; Flash ('Removed {0} of idle time' -f (Format-Short $away)) }
            2 { Stop-Recording $since; $script:pausedTask = $null; Flash ('Stopped at {0}' -f $since.ToString('HH:mm')) }
            default { }
        }
    } finally {
        $script:idleSince = $null; $script:prompting = $false
        Refresh-All
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    try {
        $now = Get-Date
        if (($now - $script:lastTick).TotalSeconds -gt 120 -and $script:active -and -not $script:idleSince) { $script:idleSince = $script:lastTick }   # PC slept / was suspended
        $script:lastTick = $now
        if ($now.Date -ne $script:cache.day) { Update-Cache -Force; if ($script:expanded) { Refresh-All } }
        Check-Idle
        if ($script:active -and ($now - $script:lastBeat).TotalSeconds -ge 30) { $script:lastBeat = $now; Write-Session }
        if ($now.Second -ne $script:lastSecond) { $script:lastSecond = $now.Second; Update-Live }
    } catch { }
})

# ====================================================================== window events
$form.Add_Deactivate({
    if ($script:expanded -and -not [bool]$script:settings.pinned -and $script:modal -eq 0 -and -not $script:menuOpen -and -not $script:quitting) {
        $script:lastAutoCollapse = Get-Date
        Collapse-Panel
    }
})
$form.Add_FormClosing({ param($s, $e)
    if (-not $script:quitting -and $e.CloseReason -eq 'UserClosing') { $e.Cancel = $true; Collapse-Panel; return }
    if (-not $script:quitting) { Stop-Recording }   # Windows shutting down / task manager: close the interval cleanly
})
function Exit-App {
    $script:quitting = $true
    Stop-Task
    if ($form.Visible -and -not $script:expanded) { Set-OrbPos $form.Location }
    Save-Settings
    $tray.Visible = $false
    $form.Close()
}

function Invoke-Recovery {
    $sess = Read-Session
    if (-not $sess) { return }
    if (-not (Find-Task $sess.taskId)) { Clear-Session; return }
    $last = if ($sess.lastSeen -and $sess.lastSeen -gt $sess.start) { $sess.lastSeen } else { $sess.start }
    $name = Get-TaskName $sess.taskId
    $msg = 'Tempo closed unexpectedly while tracking "{0}" (started {1}). It was last seen running at {2}.' -f $name, $sess.start.ToString('ddd HH:mm'), $last.ToString('ddd HH:mm')
    $choices = @(('Save {0} up to {1}' -f (Format-Short ($last - $sess.start).TotalSeconds), $last.ToString('HH:mm')),
                 ('Keep tracking from {0} ({1} so far)' -f $sess.start.ToString('HH:mm'), (Format-Short ((Get-Date) - $sess.start).TotalSeconds)),
                 'Discard it')
    $c = Show-Choice 'Recover running timer' $msg $choices 0
    switch ($c) {
        1 { $script:active = $sess.taskId; $script:started = $sess.start; $script:lastTask = $sess.taskId; Write-Session }
        2 { Clear-Session }
        default { [void](Add-Interval $sess.taskId $sess.start $last '' 'recovered'); $script:lastTask = $sess.taskId; Clear-Session }
    }
    Refresh-All
}

$form.Add_Shown({
    $script:roundedByDwm = $false
    if ($script:native) {
        $script:roundedByDwm = [SymtTempo.Native]::RoundCorners($form.Handle)
        [SymtTempo.Native]::DarkScrollbars($lstTasks.Handle); [SymtTempo.Native]::DarkScrollbars($lstLog.Handle)
    }
    Register-Hotkey
    Update-PinButton
    $view = [string]$script:settings.startView
    if ($view -eq 'panel') { Set-Mode $true; Focus-Default } else { Set-Mode $false }
    if ($view -eq 'tray') { $form.Hide(); Flash-Tray 'SYMT Tempo is running in the tray.' }
    Invoke-Recovery
    $timer.Start()
})

# ====================================================================== run
# Errors inside event handlers are logged rather than surfacing the raw WinForms crash dialog.
[System.Windows.Forms.Application]::add_ThreadException({ param($s, $e)
    try {
        $line = '{0}  {1}{2}' -f (Get-Date -Format 's'), $e.Exception.Message, [Environment]::NewLine
        [System.IO.File]::AppendAllText((Join-Path $script:dataDir 'error.log'), $line)
    } catch { }
    if ($script:expanded) { $lblHint.ForeColor = $TH.Danger; $lblHint.Text = 'Something went wrong. Details in Data\error.log'; $script:flashUntil = (Get-Date).AddSeconds(6) }
})
try {
    Load-Data
    $orb0 = Get-OrbPos; $orbSize0 = Get-OrbSize
    $form.Bounds = Rc $orb0.X $orb0.Y $orbSize0 $orbSize0
    foreach ($ctl0 in $form.Controls) { $ctl0.Visible = $false }
    [System.Windows.Forms.Application]::Run($form)
} catch {
    [System.Windows.Forms.MessageBox]::Show(($_.Exception.Message + "`r`n`r`n" + $_.ScriptStackTrace), 'SYMT Tempo error') | Out-Null
} finally {
    if (-not $script:quitting) { try { Stop-Recording } catch { } }
    try { Save-Settings } catch { }
    $timer.Stop(); $timer.Dispose()
    if ($script:hk) { $script:hk.Dispose() }
    $tray.Visible = $false; $tray.Dispose()
    try { $script:mutex.ReleaseMutex() } catch { }
}
