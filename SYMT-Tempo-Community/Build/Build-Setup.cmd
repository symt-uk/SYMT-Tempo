@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not defined ISCC for %%I in (ISCC.exe) do if not "%%~$PATH:I"=="" set "ISCC=%%~$PATH:I"
if not defined ISCC (
  echo Inno Setup 6 not found. Install it from https://jrsoftware.org/isinfo.php
  pause
  exit /b 1
)
"%ISCC%" "SYMT-Tempo.iss"
if errorlevel 1 (
  echo Installer build FAILED.
  pause
  exit /b 1
)
echo Installer created in Build\Output\
pause
