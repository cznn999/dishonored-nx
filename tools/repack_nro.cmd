@echo off
rem dishonored-nx (2026-11-11): packs dishonored.nro again from a finished build, with the current icon.jpg and a
rem version, without relinking (seconds instead of the LTO link): nacptool + elf2nro on the build's stripped ELF.
rem   tools\repack_nro.cmd [build folder] [version]
rem   default: out\nx_pgo_use and 0.10
setlocal
cd /d "%~dp0.."
set "BUILD=%~1"
if "%BUILD%"=="" set "BUILD=out\nx_pgo_use"
set "VER=%~2"
if "%VER%"=="" set "VER=0.10"
rem devkitPro's installer sets DEVKITPRO to an MSYS2 path (/opt/devkitpro): the Windows folder as build_switch.cmd.
if not defined DEVKITPRO_WIN set "DEVKITPRO_WIN=C:\devkitPro"
set "TOOLS=%DEVKITPRO_WIN%\tools\bin"
if not exist "%TOOLS%\elf2nro.exe" (echo [repack] no elf2nro.exe in "%TOOLS%": set DEVKITPRO_WIN & exit /b 1)
if not exist "%BUILD%\dishonored.stripped.elf" (echo [repack] no %BUILD%\dishonored.stripped.elf: the build did not finish & exit /b 1)
if not exist "icon.jpg" (echo [repack] no icon.jpg & exit /b 1)
"%TOOLS%\nacptool.exe" --create "Dishonored" "dishonored-nx" "%VER%" "%BUILD%\dishonored.nacp" || exit /b 1
"%TOOLS%\elf2nro.exe" "%BUILD%\dishonored.stripped.elf" "%BUILD%\dishonored.nro" "--nacp=%BUILD%\dishonored.nacp" "--icon=icon.jpg" || exit /b 1
echo [repack] %BUILD%\dishonored.nro: version %VER%, icon.jpg
exit /b 0
