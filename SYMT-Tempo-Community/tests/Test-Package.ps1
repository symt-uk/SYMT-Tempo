$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($path in @('Tempo.ps1','Lib\Tempo.Core.ps1','Lib\Tempo.Native.cs','Assets\Tempo.ico','LICENSE.txt','TERMS.txt','Launch-SYMT-Tempo.vbs')) {
 if (-not (Test-Path (Join-Path $root $path))) { throw "Missing $path" }
}
$tokens=$null;$parseErrors=$null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Tempo.ps1'),[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count) { $parseErrors | Format-Table; throw 'PowerShell syntax errors found' }
Write-Host 'SYMT Tempo source/package checks passed. UI still requires Windows runtime testing.'
