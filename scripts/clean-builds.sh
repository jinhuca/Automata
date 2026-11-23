#!/usr/bin/env bash
#
# clean-builds.sh — remove all build output under Automata
# (parent repo + every submodule). Source files are never touched.
#
# Usage:
#   scripts/clean-builds.sh             # delete build output
#   scripts/clean-builds.sh --dry-run   # show what would be deleted, delete nothing
#   scripts/clean-builds.sh -n          # same as --dry-run
#   scripts/clean-builds.sh --deep      # also remove vcpkg_installed/ (restorable deps)
#   scripts/clean-builds.sh --deep -n   # preview a deep clean
#
set -euo pipefail

DRY_RUN=0
DEEP=0
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=1 ;;
    --deep)       DEEP=1 ;;
    *) echo "Unknown option: $arg" >&2
       echo "Usage: $0 [--dry-run|-n] [--deep]" >&2; exit 2 ;;
  esac
done

# Run from the repo root regardless of where the script is called from.
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
echo "Scanning for build output under: $ROOT"
[ "$DRY_RUN" -eq 1 ] && echo "(dry run — nothing will be deleted)"
[ "$DEEP" -eq 1 ]    && echo "(deep — vcpkg_installed/ will also be removed)"

# Build-output directory names. -prune: match but do not descend. Never match inside .git.
NAME_ARGS=(
  -name 'build'          -o
  -name 'build-*'        -o
  -name 'out'            -o
  -name 'bin'            -o
  -name 'obj'            -o
  -name 'cmake-build-*'  -o
  -name 'CMakeFiles'     -o
  -name '.vs'            -o
  -name 'x64'            -o
  -name 'x86'            -o
  -name 'Debug'          -o
  -name 'Release'        -o
  -name '__pycache__'
)

# vcpkg_installed is always pruned (never descended into): in normal mode it is
# left untouched; in --deep mode it is matched for removal as a whole.
if [ "$DEEP" -eq 1 ]; then
  NAME_ARGS+=( -o -name 'vcpkg_installed' )
  PRUNE_ARGS=( -name '.git' )
else
  PRUNE_ARGS=( -name '.git' -o -name 'vcpkg_installed' )
fi

mapfile -t DIRS < <(
  find . -type d \( "${PRUNE_ARGS[@]}" \) -prune -o -type d \( "${NAME_ARGS[@]}" \) -prune -print | sort
)

# Stray CMake-generated config files sitting outside a build dir.
# Skip .git and vcpkg_installed (its internals are managed by vcpkg).
mapfile -t FILES < <(
  find . -type d \( -name '.git' -o -name 'vcpkg_installed' \) -prune -o -type f \( \
      -name 'CMakeCache.txt'      -o \
      -name 'cmake_install.cmake' -o \
      -name 'CTestTestfile.cmake' \
    \) -print | sort
)

if [ "${#DIRS[@]}" -eq 0 ] && [ "${#FILES[@]}" -eq 0 ]; then
  echo "Nothing to clean — already clean."
  exit 0
fi

for d in "${DIRS[@]}";  do echo "  dir   $d"; done
for f in "${FILES[@]}"; do echo "  file  $f"; done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run complete. Re-run without --dry-run to delete."
  exit 0
fi

for d in "${DIRS[@]}";  do rm -rf  "$d"; done
for f in "${FILES[@]}"; do rm -f   "$f"; done
echo "Done — build output removed."
