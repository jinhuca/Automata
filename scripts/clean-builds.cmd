@echo off
rem ============================================================
rem clean-builds.cmd - remove all build output under Automata
rem (parent repo + every submodule). Source files are never touched.
rem Windows CMD equivalent of clean-builds.sh.
rem
rem Usage:
rem   scripts\clean-builds.cmd             delete build output
rem   scripts\clean-builds.cmd --dry-run   preview only, delete nothing
rem   scripts\clean-builds.cmd -n          same as --dry-run
rem   scripts\clean-builds.cmd --deep      also remove vcpkg_installed (restorable deps)
rem ============================================================
setlocal EnableDelayedExpansion

rem Capture the script's directory BEFORE any shift (shift also moves %0).
set "SCRIPTDIR=%~dp0"

set "DRY=0"
set "DEEP=0"
:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--dry-run" set "DRY=1" & shift & goto parse
if /i "%~1"=="-n"        set "DRY=1" & shift & goto parse
if /i "%~1"=="/dry-run"  set "DRY=1" & shift & goto parse
if /i "%~1"=="--deep"    set "DEEP=1" & shift & goto parse
echo Unknown option: %~1
echo Usage: %~nx0 [--dry-run^|-n] [--deep]
exit /b 2
:parsed

rem Run from the repo root regardless of where the script is called from.
pushd "%SCRIPTDIR%.." || exit /b 1
set "ROOT=%CD%"
echo Scanning for build output under: !ROOT!
if "!DRY!"=="1"  echo (dry run - nothing will be deleted)
if "!DEEP!"=="1" echo (deep - vcpkg_installed will also be removed)

set "FOUND=0"
call :scan "!ROOT!"

if "!FOUND!"=="0" (
  echo Nothing to clean - already clean.
  popd
  exit /b 0
)
if "!DRY!"=="1" (
  echo Dry run complete. Re-run without --dry-run to delete.
) else (
  echo Done - build output removed.
)
popd
exit /b 0

rem ------------------------------------------------------------
rem :scan <dir>  - recurse, pruning build dirs (never descend into them)
rem ------------------------------------------------------------
:scan
rem Stray CMake-generated config files in THIS directory (build dirs are pruned
rem below, so only files outside build output are seen here).
for %%F in ("%~1\CMakeCache.txt" "%~1\cmake_install.cmake" "%~1\CTestTestfile.cmake") do if exist "%%~fF" (
  set "FOUND=1"
  echo   file  %%~fF
  if "!DRY!"=="0" del /f /q "%%~fF" 2>nul
)

for /d %%S in ("%~1\*") do (
  set "nm=%%~nxS"

  set "isbuild=0"
  for %%N in (build out bin obj CMakeFiles x64 x86 Debug Release __pycache__) do if /i "!nm!"=="%%N" set "isbuild=1"
  if /i "!nm:~0,6!"=="build-"       set "isbuild=1"
  if /i "!nm:~0,12!"=="cmake-build-" set "isbuild=1"

  if /i "!nm!"==".git" (
    rem skip VCS metadata, do not recurse
  ) else if /i "!nm!"=="vcpkg_installed" (
    rem never descend; remove whole tree only in --deep mode
    if "!DEEP!"=="1" (
      set "FOUND=1"
      echo   dir   %%~fS
      if "!DRY!"=="0" rd /s /q "%%~fS" 2>nul
    )
  ) else if "!isbuild!"=="1" (
    set "FOUND=1"
    echo   dir   %%~fS
    if "!DRY!"=="0" rd /s /q "%%~fS" 2>nul
  ) else (
    call :scan "%%~fS"
  )
)
exit /b 0
