@echo off
rem dishonored-nx (2026-11-11, pure-nx's build_switch_diet.cmd + build_switch_turbo.cmd in one): the optimised codegen
rem (overrides.toml: the exact generator options, non_volatile_as_local "the diet", elide_lr_stores,
rem non_argument_as_local) with its two audits, the post-codegen steps, then the PGO-instrumented build. Each step stops
rem the script on an error. Three codegen runs (several minutes each) and a full build.
rem   1. the diet marks out, non_argument_as_local off; codegen: code for the diet audit
rem   2. tools\diet_marks_dishonored.py (renut-nx's read_before_write.py): the split pieces that read a register their
rem      parent set get share_registers in overrides.toml; codegen again: code for the non-argument audit
rem   3. tools\nonarg_keep_dishonored.py --write (renut-nx's non_argument_audit.py): the functions a value crosses a call
rem      into or out of in r0/r2/r11/r12/f0/v32-v63 keep them in ctx; codegen with every option
rem   4. checks: the diet audit must find nothing left; the non-argument audit's counts (out\nonarg_verify.txt)
rem   5. tools\post_codegen_dishonored.py
rem   6. build_switch_pgo.cmd generate: out\nx_pgo_gen\dishonored.nro (play it, then tools\pgo_merge.py and
rem      build_switch_pgo.cmd use, as that script says). "build_switch_turbo.cmd nopgo": out\nx-lto instead (LTO, no PGO).
setlocal
cd /d "%~dp0"
echo [turbo] 1/6 codegen without the marks and without non_argument_as_local
python tools\diet_marks_dishonored.py --clear || exit /b 1
python tools\nonarg_keep_dishonored.py --disable || exit /b 1
call codegen.cmd || exit /b 1
echo [turbo] 2/6 the diet audit and its marks, codegen again
python tools\diet_marks_dishonored.py || exit /b 1
call codegen.cmd || exit /b 1
echo [turbo] 3/6 the non-argument audit and its keep list, codegen with every option (long)
python tools\nonarg_keep_dishonored.py --write || exit /b 1
call codegen.cmd || exit /b 1
echo [turbo] 4/6 checks
python tools\diet_marks_dishonored.py --check
if errorlevel 1 (echo [turbo] the diet audit still finds unmarked pieces: see above; not building & exit /b 1)
python tools\nonarg_keep_dishonored.py --verify > out\nonarg_verify.txt
type out\nonarg_verify.txt
echo [turbo] 5/6 post-codegen
python tools\post_codegen_dishonored.py || exit /b 1
echo [turbo] 6/6 the build
if /i "%~1"=="nopgo" (
  set "LTO=1"
  call build_switch.cmd
) else (
  call build_switch_pgo.cmd generate
)
exit /b %errorlevel%
