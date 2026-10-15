; Optional conventional EXE installer. Requires Inno Setup 6 on Windows.
#define AppVersion "0.5.1"
[Setup]
AppId={{41F3B705-07BD-41A1-8C9C-69C9C7F90505}
AppName=SYMT Tempo
AppVersion={#AppVersion}
AppPublisher=SYMT Limited
AppPublisherURL=https://www.symt.co.uk
DefaultDirName={localappdata}\SYMT\Tempo
DefaultGroupName=SYMT
PrivilegesRequired=lowest
OutputBaseFilename=SYMT_Tempo_v0.5.1_Setup
Compression=lzma
SolidCompression=yes
LicenseFile=..\LICENSE.txt
UninstallDisplayIcon={app}\Assets\Tempo.ico
SetupIconFile=..\Assets\Tempo.ico
[Files]
Source: "..\Tempo.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Launch-SYMT-Tempo.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Lib\*"; DestDir: "{app}\Lib"; Flags: recursesubdirs ignoreversion
Source: "..\Assets\*"; DestDir: "{app}\Assets"; Flags: recursesubdirs ignoreversion
Source: "..\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\TERMS.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\NOTICE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{group}\SYMT Tempo"; Filename: "{app}\Launch-SYMT-Tempo.vbs"; IconFilename: "{app}\Assets\Tempo.ico"
[Run]
Filename: "{app}\Launch-SYMT-Tempo.vbs"; Description: "Launch SYMT Tempo"; Flags: postinstall shellexec skipifsilent
[UninstallDelete]
; Deliberately preserve Data/ on uninstall.
