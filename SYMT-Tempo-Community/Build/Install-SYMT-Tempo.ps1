Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference='Stop'
$src = Split-Path -Parent $PSScriptRoot
$dst = Join-Path $env:LOCALAPPDATA 'SYMT\Tempo'
$license = Get-Content (Join-Path $src 'LICENSE.txt') -Raw
$dlg=New-Object System.Windows.Forms.Form
$dlg.Text='Install SYMT Tempo v0.5.1';$dlg.Width=620;$dlg.Height=535;$dlg.StartPosition='CenterScreen';$dlg.FormBorderStyle='FixedDialog';$dlg.MaximizeBox=$false
$lbl=New-Object System.Windows.Forms.Label;$lbl.Text='SYMT Tempo v0.5.1  |  Free Personal Use Edition';$lbl.SetBounds(20,14,560,25);$dlg.Controls.Add($lbl)
$txt=New-Object System.Windows.Forms.TextBox;$txt.Multiline=$true;$txt.ReadOnly=$true;$txt.ScrollBars='Vertical';$txt.SetBounds(20,48,560,365);$txt.Text=$license;$dlg.Controls.Add($txt)
$agree=New-Object System.Windows.Forms.CheckBox;$agree.Text='I have read and accept the licence and terms';$agree.SetBounds(20,422,410,26);$dlg.Controls.Add($agree)
$btn=New-Object System.Windows.Forms.Button;$btn.Text='Install';$btn.SetBounds(465,452,115,28);$btn.Enabled=$false;$dlg.Controls.Add($btn)
$cancel=New-Object System.Windows.Forms.Button;$cancel.Text='Cancel';$cancel.SetBounds(340,452,115,28);$cancel.Add_Click({$dlg.Close()});$dlg.Controls.Add($cancel)
$agree.Add_CheckedChanged({$btn.Enabled=$agree.Checked})
$btn.Add_Click({
 try {
  if (-not $agree.Checked) { return }
  if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force|Out-Null }
  foreach($file in @('Tempo.ps1','Launch-SYMT-Tempo.vbs','LICENSE.txt','TERMS.txt','NOTICE.txt','README.md','CHANGELOG.md','VERSION')) { Copy-Item (Join-Path $src $file) (Join-Path $dst $file) -Force }
  foreach($dir in @('Assets','Lib')) { Copy-Item (Join-Path $src $dir) (Join-Path $dst $dir) -Recurse -Force }
  # Data directory is intentionally preserved on reinstallation / upgrade
  Copy-Item (Join-Path $PSScriptRoot 'Uninstall-SYMT-Tempo.ps1') (Join-Path $dst 'Uninstall-SYMT-Tempo.ps1') -Force
  Copy-Item (Join-Path $PSScriptRoot 'Uninstall-SYMT-Tempo.vbs') (Join-Path $dst 'Uninstall-SYMT-Tempo.vbs') -Force
  $ws=New-Object -ComObject WScript.Shell
  $start=Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\SYMT'; New-Item -Path $start -ItemType Directory -Force|Out-Null
  $sc=$ws.CreateShortcut((Join-Path $start 'SYMT Tempo.lnk'));$sc.TargetPath=Join-Path $dst 'Launch-SYMT-Tempo.vbs';$sc.WorkingDirectory=$dst;$sc.IconLocation=Join-Path $dst 'Assets\Tempo.ico';$sc.Save()
  $un=$ws.CreateShortcut((Join-Path $start 'Uninstall SYMT Tempo.lnk'));$un.TargetPath=Join-Path $dst 'Uninstall-SYMT-Tempo.vbs';$un.WorkingDirectory=$dst;$un.Save()
  [System.Windows.Forms.MessageBox]::Show('Installation complete. Find SYMT Tempo in the Start menu. Existing Data was preserved.','SYMT Tempo')|Out-Null
  $dlg.Close()
 } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Installation error')|Out-Null }
})
[void]$dlg.ShowDialog()
