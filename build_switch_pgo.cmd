@echo off
rem dishonored-nx (2026-11-11): profile-guided and link-time optimisation of the Switch build (pure-nx's
rem build_switch_pgo.cmd; renut-nx's docs/pgo-lto.md, sa2-nx's method). The same source, compiled with what the
rem console sessions counted: nothing it computes changes.
rem
rem   build_switch_pgo.cmd generate   instrumented NRO: out\nx_pgo_gen\dishonored.nro. Put it on the SD as
rem                                   /switch/dishonored-nx/dishonored.nro (start it through the forwarder as usual)
rem                                   and play: menus, then missions (stealth, fights, the city), 15 min or more; it
rem                                   writes /switch/dishonored-nx/pgo/dishonored_pgo_<N>.stream every minute and when
rem                                   the HOME menu opens.
rem   python tools\pgo_merge.py <the SD's pgo folder copied to the PC>
rem                                   merges every session into pgo\ (.gcda files; move an old pgo\ aside first).
rem   build_switch_pgo.cmd use [keep] the optimised NRO with LTO: out\nx_pgo_use\dishonored.nro (a long link: set JOBS=2
rem                                   and DIS_LTO_JOBS=1 with little memory).
rem
rem The instrumented NRO runs slower (it counts every branch); only the optimised one is for playing. A change to the
rem game code or the renderer after the session keeps the counts of every function it did not change.
setlocal
cd /d "%~dp0"
if /i "%~1"=="generate" (
  set "DIS_BUILD=out\nx_pgo_gen"
  set "DIS_CMAKE_EXTRA=-DDISHONORED_PGO=generate -DDISHONORED_SWITCH_LTO=OFF"
) else if /i "%~1"=="use" (
  if not exist "pgo\" (echo [pgo] no pgo\ folder: run python tools\pgo_merge.py first & exit /b 1)
  if not defined DIS_LTO_JOBS set "DIS_LTO_JOBS=2"
  set "DIS_BUILD=out\nx_pgo_use"
) else (
  echo usage: build_switch_pgo.cmd generate ^| use [keep]
  exit /b 1
)
if /i "%~1"=="use" set "DIS_CMAKE_EXTRA=-DDISHONORED_PGO=use -DDISHONORED_SWITCH_LTO=ON -DDISHONORED_SWITCH_LTO_JOBS=%DIS_LTO_JOBS%"
rem ninja does not see the .gcda files as inputs: a new profile needs a clean build of the optimised folder.
rem "use keep" builds again with the same profile (a change outside the generated code, the profile untouched): no
rem clean, only what changed is compiled again.
if /i "%~1"=="use" if /i not "%~2"=="keep" if exist "out\nx_pgo_use\build.ninja" (
  echo [pgo] cleaning out\nx_pgo_use for the new profile
  rmdir /s /q "out\nx_pgo_use"
)
call build_switch.cmd
exit /b %errorlevel%
