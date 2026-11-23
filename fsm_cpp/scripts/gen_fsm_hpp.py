#!/usr/bin/env python3
"""Generate src/fsm/fsm.hpp (the header-only twin) from src/fsm/fsm.ixx (the module).

fsm.ixx (the C++20 module) is the single source of truth for the generic DFA.
fsm.hpp exists ONLY so the Qt/MinGW consumers (fsm_visualizer) can use the exact
same code without C++ modules / `import std`, which that toolchain can't rely on.

Do not edit fsm.hpp by hand -- edit fsm.ixx and run this script. The transform is
mechanical: drop `export module fsm;`, drop `import std;` (replaced by the fixed
#include block below), strip the `export` keyword, and prepend the header preamble.

Usage:
  py -I scripts/gen_fsm_hpp.py           # (re)generate src/fsm/fsm.hpp
  py -I scripts/gen_fsm_hpp.py --check   # exit 1 if fsm.hpp is stale (CI / pre-commit)
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
IXX = ROOT / "src" / "fsm" / "fsm.ixx"
HPP = ROOT / "src" / "fsm" / "fsm.hpp"

# Emitted in place of `export module fsm; import std;`. If you add a new std
# facility to fsm.ixx (e.g. std::span), add the matching header to this list.
PREAMBLE = """\
#pragma once

// ============================================================================
// GENERATED FILE -- DO NOT EDIT.
// Header-only twin of fsm.ixx (the C++20 module), produced by
// scripts/gen_fsm_hpp.py. fsm.ixx is the source of truth: edit it and re-run
//   py -I scripts/gen_fsm_hpp.py
// This header exists so CMake/Qt consumers (e.g. fsm_visualizer) can use the
// same generic DFA without C++ modules / `import std`.
// ============================================================================

// fsm uses C++20 concepts and <ranges>. Fail early with a clear message on a
// too-old toolchain (e.g. the MinGW 8.1 kit) instead of a wall of errors.
#if defined(__GNUC__) && !defined(__clang__) && (__GNUC__ < 11)
#  error "fsm.hpp requires a C++20 compiler (GCC >= 11). Point the MinGW kit at the Qt 6.12 bundled MinGW 13.1.0, not MinGW 8.1."
#endif

#include <concepts>
#include <functional>
#include <map>
#include <ranges>
#include <set>
#include <utility>
#include <vector>
"""

_EXPORT_PREFIX = re.compile(r"^(\s*)export\s+")


def transform(ixx_text: str) -> str:
    """Turn the module source into the equivalent header text (LF line endings)."""
    body_lines = []
    for line in ixx_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("export module "):
            continue  # module declaration has no header equivalent
        if stripped.startswith("import "):
            continue  # `import std;` -> the #include block in PREAMBLE
        line = _EXPORT_PREFIX.sub(r"\1", line, count=1)  # `export namespace` -> `namespace`
        body_lines.append(line)

    body = "\n".join(body_lines).lstrip("\n")           # drop blank lines left at the top
    return PREAMBLE + "\n" + body.rstrip("\n") + "\n"


def _detect_eol(path: pathlib.Path) -> str:
    """Working-tree line ending of `path` (so the generated header matches its
    sibling and doesn't churn under git's autocrlf). Defaults to LF."""
    if path.exists():
        data = path.read_bytes()
        if b"\r\n" in data:
            return "\r\n"
    return "\n"


def main(argv) -> int:
    check_only = "--check" in argv[1:]
    if not IXX.exists():
        print(f"error: {IXX} not found", file=sys.stderr)
        return 2
    expected = transform(IXX.read_text(encoding="utf-8"))

    if check_only:
        # Compare by lines so a CRLF/LF difference (git autocrlf) is not a false
        # mismatch -- only the actual text content matters.
        current = HPP.read_text(encoding="utf-8") if HPP.exists() else ""
        if current.splitlines() == expected.splitlines():
            print(f"ok: {HPP.name} is in sync with {IXX.name}")
            return 0
        print(
            f"error: {HPP.relative_to(ROOT)} is STALE relative to {IXX.relative_to(ROOT)}.\n"
            f"       Regenerate it with:  py -I scripts/gen_fsm_hpp.py",
            file=sys.stderr,
        )
        return 1

    # Write with the sibling module's line ending (keeps the two consistent).
    eol = _detect_eol(IXX)
    with open(HPP, "w", encoding="utf-8", newline="") as f:
        f.write(expected.replace("\n", eol))
    print(f"wrote {HPP.relative_to(ROOT)} from {IXX.relative_to(ROOT)} ({'CRLF' if eol == chr(13)+chr(10) else 'LF'})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
