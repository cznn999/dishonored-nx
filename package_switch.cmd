@echo off
rem The SD card folder of Dishonored for the Switch: <target>\switch\dishonored-nx\ with dishonored.nro and game_root\
rem (your game files from assets\game_root). <target> is the SD card's root, or Ryujinx's sdcard folder:
rem   package_switch.cmd                          -> out\nx\sdcard (copy its "switch" folder to the card)
rem   package_switch.cmd E:\                      -> straight onto the SD card in drive E:
rem   package_switch.cmd "%APPDATA%\Ryujinx\sdcard"   -> Ryujinx
rem game_root is copied with robocopy /MIR: only what changed is copied again.
setlocal
cd /d "%~dp0"
if not exist "out\nx\dishonored.nro" (echo [package] no out\nx\dishonored.nro: run build_switch.cmd first & exit /b 1)
if not exist "assets\game_root\default.xex" (echo [package] no assets\game_root\default.xex & exit /b 1)
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=%~dp0out\nx\sdcard"
set "DEST=%TARGET%\switch\dishonored-nx"
mkdir "%DEST%" 2>nul
copy /y "out\nx\dishonored.nro" "%DEST%\dishonored.nro" >nul || exit /b 1
echo [package] %DEST%\dishonored.nro
robocopy "assets\game_root" "%DEST%\game_root" /MIR /XD "$SystemUpdate" /NFL /NDL /NJH /NP
if errorlevel 8 (echo [package] copying game_root failed & exit /b 1)
echo [package] done: %DEST%
exit /b 0
