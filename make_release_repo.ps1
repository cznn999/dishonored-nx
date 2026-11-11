# dishonored-nx: a clean copy of the port's source for publishing (pure-nx's make_release_repo.ps1, adapted).
#   powershell -ExecutionPolicy Bypass -File make_release_repo.ps1 [-Dest ..\dishonored-nx-release]
# Copies only the source (an allow list), never game data or anything made from it (generated/, switch_shaders/,
# renut_shaders/, logs, PGO profiles), nor test and development leftovers (tools\switch_test.ini: the console's
# address and FTP login; working notes). Then checks the copy and packs it as <Dest>.zip. No git commit here: the repository gets its commit (author
# cznn999, no e-mail) where it is pushed from.
param([string]$Dest = (Join-Path $PSScriptRoot "..\dishonored-nx-release"))
$ErrorActionPreference = "Stop"
$Src = $PSScriptRoot
$Dest = [System.IO.Path]::GetFullPath($Dest)
if ((Test-Path $Dest) -and (Get-ChildItem -Force $Dest | Select-Object -First 1)) {
    throw "$Dest exists and is not empty: choose another -Dest or remove it"
}
New-Item -ItemType Directory -Force $Dest | Out-Null

function Copy-One([string]$rel) {
    $from = Join-Path $Src $rel
    if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { return }
    $to = Join-Path $Dest $rel
    New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to -Force
}

# 1. Top-level files.
$top = @("CMakeLists.txt", "CMakePresets.json", ".gitignore", "README.md", "overrides.toml",
         "dishonored_manifest.toml", "dishonored.toml", "dishonored_switch.toml", "dishonored_switch_defaults.toml",
         "dishonored_builtin_config.h.in", "build.cmd", "build_switch.cmd", "build_switch_pgo.cmd",
         "build_switch_turbo.cmd", "codegen.cmd", "package_switch.cmd", "make_release_repo.ps1", "icon.jpg")
foreach ($f in $top) { Copy-One $f }

# 2. Source folders (whole), and the port's own tools (not their outputs, not the console test scripts).
# src\cpu\hot and src\cpu\dishonored_hot_*.cpp are localized copies of recompiled game code (out of the build since
# 2026-11-11): made from default.xex, like generated\, so never published.
$skipDir = '\\(__pycache__|rexglue-sdk-dishonored|hot)(\\|$)'
# Test and development leftovers stay out: the console test runs (switch_test.*, switch_agent.py, agent_steps.py: the
# console's address and FTP login), the codegen bisect switch (codegen_options.py), one-off fixes and the shader
# package's part merge (deko3d_window_clamp.py, install_shaders.cmd).
$skipFile = '\\tools\\(switch_test\.ini|switch_test\.py|switch_agent\.py|agent_steps\.py|codegen_options\.py|deko3d_window_clamp\.py|install_shaders\.cmd)$|\\src\\cpu\\dishonored_hot_[a-z]+\.cpp$'
foreach ($d in @("cmake", "src", "patches", "tools")) {  # not notes\ (working notes) nor BUDOWANIE.md
    $root = Join-Path $Src $d
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($Src.Length).TrimStart('\')
        if (($rel -notmatch $skipDir) -and ("\$rel" -notmatch $skipFile)) { Copy-One $rel }
    }
}

# 3. The SDK fork (tools\rexglue-sdk-dishonored): its source, without build output, PGO data, the third-party sources
#    tools\fetch_thirdparty.py fetches (only the files the fork changed are kept) and the DXC binaries.
$sdk = "tools\rexglue-sdk-dishonored"
$sdkSrc = Join-Path $Src $sdk
$sdkDst = Join-Path $Dest $sdk
$xd = @(".git", "pgo", "out", "build", "cache", "logs", "__pycache__",
        "sdk\out", "sdk\thirdparty", "mesa\work", "shaders\wasm\out",
        "app\thirdparty\reblue-XenosRecomp\thirdparty\dxc-bin\bin",
        "app\thirdparty\reblue-XenosRecomp\thirdparty\dxc-bin\lib") | ForEach-Object { Join-Path $sdkSrc $_ }
robocopy $sdkSrc $sdkDst /E /XD $xd /XF .git *.exe *.dll *.lib *.pdb *.a *.o *.obj *.gcda *.stream *.log /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy of $sdk failed ($LASTEXITCODE)" }
$keep = @("CMakeLists.txt", "FFmpeg\config.h", "FFmpeg\config_switch_aarch64.h", "FFmpeg\config_masseffect_wmv3.h",
          "FFmpeg\libavcodec\mdct_template.c", "FFmpeg\libavcodec\fft_template.c", "ffmpeg-overlay\codec_list.c")
foreach ($k in $keep) { Copy-One (Join-Path "$sdk\sdk\thirdparty" $k) }
Copy-Item -LiteralPath (Join-Path $sdkSrc "LICENSE") -Destination (Join-Path $Dest "LICENSE") -Force

# 4. Checks: no game data, nothing made from it, no big binaries, no personal data.
$bad = Get-ChildItem -LiteralPath $Dest -Recurse -File -Force | Where-Object {
    $_.Extension -in @(".xex", ".nro", ".nsp", ".nxpack", ".log", ".gcda", ".stream", ".zip", ".dksh", ".bin", ".ini") -or
    $_.Length -gt 20MB -or
    $_.FullName.Substring($Dest.Length) -match '^\\(generated|switch_shaders|renut_shaders|out|assets|pgo[^\\]*)\\' -or
    $_.FullName -match '\\(game_root|logs)\\'
}
if ($bad) {
    $bad | ForEach-Object { Write-Host "  not for publishing: $($_.FullName) ($([math]::Round($_.Length / 1MB, 1)) MB)" }
    throw "the copy holds files that must not be published (above): fix the allow list"
}
# Personal data: the port's own files (not the SDK fork) for paths of a Windows profile, mail addresses, login data and
# LAN addresses; the SDK fork (its third-party code names its authors with their public addresses, and its own help
# texts give example LAN addresses) for profile paths and login data only. This script itself is not checked.
$sdkDstPrefix = (Join-Path $Dest "tools\rexglue-sdk-dishonored") + "\"
$texts = Get-ChildItem -LiteralPath $Dest -Recurse -File -Force -Include *.cpp,*.h,*.c,*.inc,*.py,*.cmd,*.ps1,*.toml,*.md,*.txt,*.cmake,*.json,*.ini |
    Where-Object { $_.Name -ne "make_release_repo.ps1" }
$own = $texts | Where-Object { -not $_.FullName.StartsWith($sdkDstPrefix) }
$fork = $texts | Where-Object { $_.FullName.StartsWith($sdkDstPrefix) }
$personal = @()
$personal += $own | Select-String -Pattern 'C:\\Users\\|@gmail\.com|ftp_password|ftp_user|haslo|192\.168\.' -List
$personal += $fork | Select-String -Pattern 'C:\\Users\\|ftp_password|ftp_user|haslo' -List
if ($personal) {
    $personal | ForEach-Object { Write-Warning "personal data? $($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
    throw "personal data in the copy (above): remove it before publishing"
}

# 5. One zip of the copy, to upload.
$zip = "$Dest.zip"
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
# Windows's own tar (bsdtar): devkitPro's MSYS2 tar may come first in PATH and reads "X:" as a remote host.
& (Join-Path $env:SystemRoot "System32\tar.exe") -a -c -f $zip -C $Dest .
if ($LASTEXITCODE -ne 0) { throw "tar failed ($LASTEXITCODE)" }
$n = (Get-ChildItem -LiteralPath $Dest -Recurse -File -Force | Measure-Object).Count
Write-Host "[release] $n files in $Dest"
Write-Host "[release] zip: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
