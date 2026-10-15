Option Explicit
Dim sh,fso,base
Set sh=CreateObject("WScript.Shell")
Set fso=CreateObject("Scripting.FileSystemObject")
base=fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "\Install-SYMT-Tempo.ps1""",0,False
