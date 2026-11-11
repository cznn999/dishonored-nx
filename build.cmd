@echo off
rem Builds Dishonored (stage 1: PC, emulated Xenos GPU) with ReXGlue.
rem Needs: Visual Studio 2022/2026 (Desktop development with C++), LLVM clang 20; the SDK is in this tree
rem (tools\rexglue-sdk-dishonored, see BUDOWANIE.md). Run from a normal cmd window.
setlocal EnableDelayedExpansion
cd /d "%~dp0"

rem --- 1. PATH without devkitPro / MSYS2 / MinGW (they break CMake's cache: sa2-nx docs/porting-guide.md)
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch 'devkitpro|msys|mingw' }) -join ';'"`) do set "PATH=%%p"

rem --- 2. Visual Studio environment (MSVC libraries + Windows SDK), 64-bit
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
if not defined VS (echo [build] Visual Studio with the C++ tools not found & exit /b 1)
call "%VS%\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul || exit /b 1
set "VSCMAKE=%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake"
if not exist "%VSCMAKE%\CMake\bin\cmake.exe" (echo [build] Install "C++ CMake tools for Windows" in the VS Installer & exit /b 1)

rem --- 3. LLVM clang 20
if not defined LLVM_DIR set "LLVM_DIR=%ProgramFiles%\LLVM"
if not exist "%LLVM_DIR%\bin\clang.exe" (echo [build] clang not found in "%LLVM_DIR%\bin": install LLVM 20 or set LLVM_DIR & exit /b 1)
"%LLVM_DIR%\bin\clang.exe" --version | findstr /c:"clang version 20." >nul || (echo [build] clang in "%LLVM_DIR%" is not version 20 & exit /b 1)
set "PATH=%LLVM_DIR%\bin;%VSCMAKE%\CMake\bin;%VSCMAKE%\Ninja;%PATH%"

rem --- 4. The ReXGlue SDK (the sa2-nx fork in this tree, dishonored-nx 2026-11-11: standalone) and the game files
if not defined REXSDK_DIR set "REXSDK_DIR=%~dp0tools\rexglue-sdk-dishonored\sdk"
for %%d in ("%REXSDK_DIR%") do set "REXSDK_DIR=%%~fd"
if not exist "%REXSDK_DIR%\CMakeLists.txt" (echo [build] SDK not found at "%REXSDK_DIR%": tools\rexglue-sdk-dishonored is missing, or set REXSDK_DIR & exit /b 1)
if not exist "%REXSDK_DIR%\thirdparty\sdl3\CMakeLists.txt" (echo [build] SDK third-party sources missing: run "python tools\fetch_thirdparty.py" in tools\rexglue-sdk-dishonored & exit /b 1)
if not exist "assets\game_root\default.xex" (echo [build] assets\game_root\default.xex missing: copy your extracted disc into assets\game_root & exit /b 1)

echo [build] clang: & "%LLVM_DIR%\bin\clang.exe" --version | findstr /c:"clang version"
echo [build] SDK:   %REXSDK_DIR%

rem --- 5. Configure once, then build (the build runs the code generator first: several minutes)
if not defined JOBS set "JOBS=6"
rem GPU emulation backend: d3d12 (default) or vulkan ("set GPU_BACKEND=vulkan" before build.cmd).
rem Both are set explicitly so switching back and forth reconfigures the same build tree.
if /i "%GPU_BACKEND%"=="vulkan" (
  set "BACKEND_FLAGS=-DREXGLUE_USE_D3D12=OFF -DREXGLUE_USE_VULKAN=ON"
) else (
  set "BACKEND_FLAGS=-DREXGLUE_USE_D3D12=ON -DREXGLUE_USE_VULKAN=OFF"
)
echo [build] GPU backend flags: %BACKEND_FLAGS%
set "BUILD=out\build\win-amd64-relwithdebinfo"
if exist "%BUILD%\CMakeCache.txt" if not exist "%BUILD%\build.ninja" rmdir /s /q "%BUILD%"
rem Configure every time (quick after the first): the game's generated sources are only picked up by a
rem configure that runs after the code generator, so a first build generates them and a second configure adds them.
cmake --preset win-amd64-relwithdebinfo "-DREXSDK_DIR=%REXSDK_DIR%" "-DCMAKE_C_FLAGS=-march=x86-64-v2" "-DCMAKE_CXX_FLAGS=-march=x86-64-v2" %BACKEND_FLAGS% || exit /b 1
if not exist "generated\default\sources.cmake" (
  echo [build] running the code generator first...
  cmake --build "%BUILD%" --target dishonored_codegen || exit /b 1
  cmake --preset win-amd64-relwithdebinfo "-DREXSDK_DIR=%REXSDK_DIR%" "-DCMAKE_C_FLAGS=-march=x86-64-v2" "-DCMAKE_CXX_FLAGS=-march=x86-64-v2" %BACKEND_FLAGS% || exit /b 1
)
cmake --build "%BUILD%" -j %JOBS% %* || exit /b 1
echo.
echo [build] done: %BUILD%\dishonored.exe
