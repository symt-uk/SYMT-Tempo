# Windows installers

**Runnable per-user installer:** extract the installation ZIP, double-click `Build/Install-SYMT-Tempo.vbs`, read and accept the licence. No admin permissions are required. The launcher runs without a command console. Uses %LOCALAPPDATA%\SYMT\Tempo and preserves Data during updates/uninstall.

**Optional conventional .exe installer:** on Windows with Inno Setup 6, open `Build/SYMT-Tempo.iss` and Compile. This generates a Setup EXE. This EXE cannot be compiled or tested in the current Linux build environment.

Close SYMT Tempo before installing/upgrading. Do not run both portable and installed editions simultaneously because they use the same single-instance mutex but different data folders. Backup/copy Data explicitly when switching editions.

### Compile the public Setup EXE (on Windows)
1. Install **Inno Setup 6** from https://jrsoftware.org/isinfo.php.
2. Extract the **complete source ZIP**, leaving `Build`, `Assets`, `Lib`, and `Tempo.ps1` together.
3. Double-click `Build\Build-Setup.cmd` (or open `Build\SYMT-Tempo.iss` in Inno Setup Compiler and click **Build > Compile**).
4. Share `Build\Output\SYMT_Tempo_v0.5.1_Setup.exe` as your Windows installer.
5. Test licence acceptance, startup, uninstall and data preservation in a clean Windows user profile before publishing.

The generated Setup EXE is an **installer**, not a native compiled app: Tempo still runs in Windows PowerShell 5.1. There is no MSI in this project. MSI packaging requires an additional WiX Toolset/MSIX workflow. The EXE will be unsigned until code signing is configured; Windows SmartScreen may warn users about an unfamiliar publisher.
