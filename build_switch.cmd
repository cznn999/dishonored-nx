@echo off
rem Builds Dishonored for the Nintendo Switch: out\nx\dishonored.nro (Renut on deko3d, devkitA64 GCC + libnx).
rem Needs: devkitPro with Switch development (C:\devkitPro), Visual Studio's CMake + Ninja, tools\rexglue-sdk-dishonored (in this tree),
rem and a finished PC build first (build.cmd): the Switch build is a cross build and uses the code the PC build
rem generated (generated\default). See BUDOWANIE.md, section 6. Run from a normal cmd window.
setlocal EnableDelayedExpansion
cd /d "%~dp0"

rem --- 1. PATH without MSYS2 / MinGW tools (their cmd, link and find break CMake)
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch 'msys|mingw' }) -join ';'"`) do set "PATH=%%p"

rem --- 2. devkitPro
if not defined DEVKITPRO_WIN set "DEVKITPRO_WIN=C:\devkitPro"
set "DKP=%DEVKITPRO_WIN:\=/%"
if not exist "%DEVKITPRO_WIN%\devkitA64\bin\aarch64-none-elf-g++.exe" (echo [switch] devkitA64 not found in "%DEVKITPRO_WIN%": install devkitPro with Switch development, or set DEVKITPRO_WIN & exit /b 1)
if not exist "%DEVKITPRO_WIN%\libnx\switch.specs" (echo [switch] libnx not found in "%DEVKITPRO_WIN%\libnx": in devkitPro's MSYS2 run "pacman -S switch-dev" & exit /b 1)
if not exist "%DEVKITPRO_WIN%\libnx\lib\libdeko3d.a" (echo [switch] deko3d not found in "%DEVKITPRO_WIN%\libnx\lib": in devkitPro's MSYS2 run "pacman -S deko3d" & exit /b 1)
if not exist "%DEVKITPRO_WIN%\tools\bin\elf2nro.exe" (echo [switch] elf2nro not found in "%DEVKITPRO_WIN%\tools\bin": in devkitPro's MSYS2 run "pacman -S switch-tools" & exit /b 1)
for %%l in (zstd z) do if not exist "%DEVKITPRO_WIN%\portlibs\switch\lib\lib%%l.a" (echo [switch] lib%%l.a not found in "%DEVKITPRO_WIN%\portlibs\switch\lib": in devkitPro's MSYS2 run "pacman -S switch-zlib switch-zstd" & exit /b 1)
rem The toolchain reads DEVKITPRO; devkitPro's installer sets it to an MSYS2 path (/opt/devkitpro) CMake cannot open.
set "DEVKITPRO=%DKP%"

rem --- 3. CMake and Ninja from Visual Studio
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -property installationPath`) do set "VS=%%i"
set "VSCMAKE=%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake"
if not exist "%VSCMAKE%\CMake\bin\cmake.exe" (echo [switch] Visual Studio's CMake not found ("C++ CMake tools for Windows") & exit /b 1)
set "PATH=%VSCMAKE%\CMake\bin;%VSCMAKE%\Ninja;%PATH%"

rem --- 4. The SDK, the generated code, the ready-made Switch shaders
rem dishonored-nx (2026-11-11): standalone, as pure-nx: the SDK is this tree's tools\rexglue-sdk-dishonored (the
rem sa2-nx fork with its app\thirdparty: plume, XenosRecomp with DXC and patches\*.patch applied, imgui, uam; and its
rem tools\switch). No sa2-nx folder next to this one. REXSDK_DIR still overrides it.
if not defined REXSDK_DIR set "REXSDK_DIR=%~dp0tools\rexglue-sdk-dishonored\sdk"
for %%d in ("%REXSDK_DIR%") do set "REXSDK_DIR=%%~fd"
for %%d in ("%REXSDK_DIR%\..") do set "REXSDK_ROOT=%%~fd"
if not exist "%REXSDK_DIR%\CMakeLists.txt" (echo [switch] SDK not found at "%REXSDK_DIR%" & exit /b 1)
if not exist "%REXSDK_ROOT%\tools\switch\cmake\switch-devkitA64.cmake" (echo [switch] no switch-devkitA64.cmake in "%REXSDK_ROOT%\tools\switch\cmake" & exit /b 1)
if not exist "%REXSDK_ROOT%\app\thirdparty\uam\CMakeLists.txt" (echo [switch] no "%REXSDK_ROOT%\app\thirdparty\uam": tools\rexglue-sdk-dishonored is incomplete & exit /b 1)
if not exist "generated\default\sources.cmake" (echo [switch] generated\default is missing: run build.cmd ^(the PC build^) first & exit /b 1)
if not exist "switch_shaders\deko3d_glsl.bin" (echo [switch] switch_shaders\ is missing: unpack it from the dishonored-nx package & exit /b 1)

rem --- 5. No Vulkan driver in this NRO (Renut draws with deko3d): the SDK only needs Vulkan's headers and the name of a
rem     driver archive, which is never linked (REXGLUE_SWITCH_NO_NVK). out\nvk-stub stands in for Mesa's Switch SDK.
set "NVK=%~dp0out\nvk-stub"
if not exist "%NVK%\lib\libvulkan.a" (
  if not exist "%REXSDK_DIR%\thirdparty\vulkan-headers\include\vulkan\vulkan.h" (echo [switch] no Vulkan headers in the SDK: run "python tools\fetch_thirdparty.py" in tools\rexglue-sdk-dishonored & exit /b 1)
  mkdir "%NVK%\lib" 2>nul
  xcopy /e /i /q /y "%REXSDK_DIR%\thirdparty\vulkan-headers\include" "%NVK%\include" >nul || exit /b 1
  powershell -NoProfile -Command "[IO.File]::WriteAllBytes('%NVK%\lib\libvulkan.a', [byte[]](33,60,97,114,99,104,62,10))" || exit /b 1
)
set "NVK_FWD=%NVK:\=/%"

rem --- 6. Configure once, then build
rem GCC needs 1-3 GB a job on the game code: fewer jobs with little RAM ("set JOBS=2").
if not defined JOBS set "JOBS=4"
rem dishonored-nx (2026-11-01): "set LTO=1" before build_switch.cmd: the link-time optimised build in out\nx-lto
if "%LTO%"=="1" (set "BUILD=out\nx-lto" & set "LTOFLAG=-DDISHONORED_SWITCH_LTO=ON") else (set "BUILD=out\nx" & set "LTOFLAG=-DDISHONORED_SWITCH_LTO=OFF")
rem dishonored-nx (2026-11-11): build_switch_pgo.cmd builds in a folder of its own with its own options (DIS_BUILD,
rem DIS_CMAKE_EXTRA, as pure-nx's PURE_BUILD / PURE_CMAKE_EXTRA); the everyday folders stay without them.
if defined DIS_BUILD set "BUILD=%DIS_BUILD%"
if exist "%BUILD%\CMakeCache.txt" if not exist "%BUILD%\build.ninja" rmdir /s /q "%BUILD%"
if not exist "%BUILD%\build.ninja" (
  cmake -S . -B "%BUILD%" -G Ninja -DCMAKE_BUILD_TYPE=Release ^
    "-DCMAKE_TOOLCHAIN_FILE=%REXSDK_ROOT%\tools\switch\cmake\switch-devkitA64.cmake" ^
    "-DDEVKITPRO=%DKP%" "-DREXSDK_DIR=%REXSDK_DIR%" ^
    "-DREXGLUE_SWITCH_NVK_SDK=%NVK_FWD%" -DREXGLUE_SWITCH_NO_NVK=ON || exit /b 1
)
rem "set DEKO3D_DEBUG=1" before build_switch.cmd: devkitPro's debug deko3d (every call's input checked, guard bytes after
rem each memory block, reported in deko3d.log beside the NRO). Slower; for finding a GPU fault.
if "%DEKO3D_DEBUG%"=="1" (set "DKDBG=ON") else (set "DKDBG=OFF")
cmake "%BUILD%" -DPLUME_DEKO3D_DEBUG=%DKDBG% %LTOFLAG% %DIS_CMAKE_EXTRA% >nul || exit /b 1
echo [switch] deko3d debug library: %DKDBG%
cmake --build "%BUILD%" -j %JOBS% %* || exit /b 1
echo.
echo [switch] done: %BUILD%\dishonored.nro
echo [switch] next: package_switch.cmd (the SD card folder)
