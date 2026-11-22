# Build, deploy and package fsm::dfa visualizer into a Windows installer.
#
#   powershell -ExecutionPolicy Bypass -File packaging\package.ps1 [-Trim] [-Minimal]
#
# Produces build-release\fsm_visualizer-<version>-setup.exe (and a stable
# build-release\fsm_visualizer-latest-setup.exe copy).
# Requires: Qt 6.8.3 (MinGW 64-bit) + Inno Setup 6. Override paths via
# -QtDir / -MingwDir / -Ninja / -Iscc if your install locations differ.

param(
    [string]$QtDir    = "C:\Qt\6.8.3\mingw_64",
    [string]$MingwDir = "C:\Qt\Tools\mingw1310_64",
    [string]$Ninja    = "C:\Qt\Tools\Ninja\ninja.exe",
    [string]$Iscc     = "",             # auto-detected below if empty
    [switch]$Trim,                      # drop clearly-unused files (translations, virtual keyboard)
    [switch]$Minimal,                   # also drop the software-GL fallback + unused Controls styles
                                        #   (smaller installer; needs a working GPU on the target)
    [string]$SignToolCmd = ""           # if set, code-sign the exe + installer (see README)
)
$ErrorActionPreference = "Stop"

if (-not $Iscc) {
    $Iscc = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
$pkg  = $PSScriptRoot
$root = Split-Path -Parent $pkg          # fsm_visualizer\
$bld  = Join-Path $root "build-release"
$dist = Join-Path $bld  "dist"

Write-Host "==> Configuring + building (Release)"
cmake -S $root -B $bld -G Ninja -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_CXX_COMPILER="$MingwDir\bin\g++.exe" `
    -DCMAKE_RC_COMPILER="$MingwDir\bin\windres.exe" `
    -DCMAKE_MAKE_PROGRAM="$Ninja" `
    -DCMAKE_PREFIX_PATH="$QtDir"
cmake --build $bld

Write-Host "==> Deploying Qt runtime (windeployqt)"
Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
New-Item -ItemType Directory $dist | Out-Null
$distExe = Join-Path $dist "appFsmVisualizer.exe"
Copy-Item (Join-Path $bld "appFsmVisualizer.exe") $dist
& "$QtDir\bin\windeployqt.exe" --release --compiler-runtime --qmldir "$root\qml" $distExe

function Drop($relPath) { Remove-Item -Recurse -Force (Join-Path $dist $relPath) -ErrorAction SilentlyContinue }

if ($Trim -or $Minimal) {
    Write-Host "==> Trimming unused files"
    # Not localised and doesn't use the virtual keyboard.
    Drop "translations"
    Drop "Qt6VirtualKeyboard.dll"
    Drop "qml\QtQuick\VirtualKeyboard"
    Drop "platforminputcontexts\qtvirtualkeyboardplugin.dll"
}
if ($Minimal) {
    Write-Host "==> Minimal: dropping software-GL fallback + unused Controls styles"
    # ~16 MB software OpenGL fallback (only needed where hardware GL is unavailable,
    # e.g. some VMs / Remote Desktop).
    Drop "opengl32sw.dll"
    # The app uses the Fusion style (set in main.cpp); drop the others.
    foreach ($style in @("Material","Universal","Imagine","FluentWinUI3","Windows")) {
        Drop "Qt6QuickControls2$style.dll"
        Drop "Qt6QuickControls2${style}StyleImpl.dll"
        Drop "qml\QtQuick\Controls\$style"
    }
}

if ($SignToolCmd) {
    Write-Host "==> Signing application exe"
    Invoke-Expression "$SignToolCmd `"$distExe`""
}

Write-Host "==> Compiling installer (Inno Setup)"
if (-not $Iscc -or -not (Test-Path $Iscc)) { throw "Inno Setup (ISCC.exe) not found. Install it or pass -Iscc <path>." }
$isccArgs = @((Join-Path $pkg "installer.iss"))
if ($SignToolCmd) { $isccArgs = @("/DSIGN", "/Ssigntool=$SignToolCmd `$f") + $isccArgs }
& $Iscc @isccArgs

Write-Host "==> Writing 'latest' copy"
$built = Get-ChildItem (Join-Path $bld "fsm_visualizer-*-setup.exe") |
    Where-Object { $_.Name -notlike "*latest*" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item $built.FullName (Join-Path $bld "fsm_visualizer-latest-setup.exe") -Force

Write-Host "==> Done. Installers:"
Get-ChildItem (Join-Path $bld "fsm_visualizer-*-setup.exe") | ForEach-Object {
    "{0,8:N1} MB  {1}" -f ($_.Length/1MB), $_.FullName | Write-Host
}
