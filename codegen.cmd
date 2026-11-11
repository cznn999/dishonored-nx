@echo off
rem dishonored-nx (2026-11-11, pure-nx's codegen.cmd): reruns the ReXGlue code generator of tools\rexglue-sdk-dishonored
rem (pure-nx's newer sa2-nx copy: the optimised codegen options of overrides.toml) on dishonored_manifest.toml into
rem generated\default, and writes the loaded game image (out\default_image.bin) for tools\post_codegen_dishonored.py.
rem Only files whose content changed are written. Output in out\codegen.log. Takes several minutes.
rem The generated text is the plain codegen: run python tools\post_codegen_dishonored.py after it (build_switch_turbo.cmd
rem does), or the build lacks the optimised forms.
setlocal
cd /d "%~dp0"
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch 'devkitpro|msys|mingw' }) -join ';'"`) do set "PATH=%%p"
set "REXGLUE=%~dp0tools\rexglue-sdk-dishonored\sdk\out\win-amd64\rexgluerd.exe"
if not exist "%REXGLUE%" set "REXGLUE=%~dp0tools\rexglue-sdk-dishonored\sdk\out\win-amd64\rexglue.exe"
if not exist "%REXGLUE%" (echo [codegen] rexglue not found in tools\rexglue-sdk-dishonored\sdk\out\win-amd64 & exit /b 1)
if not exist "assets\game_root\default.xex" (echo [codegen] no assets\game_root\default.xex ^(dishonored_manifest.toml^) & exit /b 1)
if not exist out mkdir out
echo [codegen] %REXGLUE% codegen dishonored_manifest.toml ...
set "REXGLUE_DUMP_IMAGE=%~dp0out\default_image.bin"
"%REXGLUE%" --force codegen dishonored_manifest.toml > out\codegen.log 2>&1
if errorlevel 1 (echo [codegen] FAILED - see out\codegen.log & exit /b 1)
if not exist "out\default_image.bin" (echo [codegen] no out\default_image.bin: this rexglue does not dump the image & exit /b 1)
echo [codegen] done - see out\codegen.log
