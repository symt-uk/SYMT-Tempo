Add-Type -AssemblyName System.Windows.Forms
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$choice=[System.Windows.Forms.MessageBox]::Show('Remove SYMT Tempo application files? Task data will be preserved unless you delete the Data folder yourself.','Uninstall SYMT Tempo','YesNo','Question')
if($choice -ne 'Yes'){return}
$start=Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\SYMT'
Remove-Item (Join-Path $start 'SYMT Tempo.lnk') -ErrorAction SilentlyContinue
Remove-Item (Join-Path $start 'Uninstall SYMT Tempo.lnk') -ErrorAction SilentlyContinue
foreach($f in @('Tempo.ps1','Launch-SYMT-Tempo.vbs','LICENSE.txt','TERMS.txt','NOTICE.txt','README.md','CHANGELOG.md','VERSION')){Remove-Item (Join-Path $root $f) -Force -ErrorAction SilentlyContinue}
foreach($d in @('Lib','Assets')){Remove-Item (Join-Path $root $d) -Recurse -Force -ErrorAction SilentlyContinue}
[System.Windows.Forms.MessageBox]::Show("Removed application files. Task data remains at: $root\Data. You can delete it manually after backing it up.",'SYMT Tempo')|Out-Null
