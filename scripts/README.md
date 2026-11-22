# scripts — build cleanup

Scripts for removing all build output under `Automata` (the parent repo **and**
every submodule: currently `fsm_cpp`).

Two equivalent versions are provided — use whichever matches your shell:

| Script             | Use from                                     |
| ------------------ | -------------------------------------------- |
| `clean-builds.sh`  | Git Bash, VS Code bash terminal, WSL         |
| `clean-builds.cmd` | CMD, PowerShell, or double-click in Explorer |

Both do exactly the same thing, never touch source files, and support a
**dry-run** that previews what would be deleted without deleting anything.

---

## What gets deleted

- **Directories** named: `build`, `build-*`, `out`, `bin`, `obj`,
  `cmake-build-*`, `CMakeFiles`, `x64`, `x86`, `Debug`, `Release`,
  `__pycache__`
- **Stray files**: `CMakeCache.txt`, `cmake_install.cmake`, `CTestTestfile.cmake`
- With `--deep` **only**: also `vcpkg_installed/` (the vcpkg dependency tree —
  restorable, but re-running it re-downloads/rebuilds `rxcpp`, so it is **not**
  removed by default)

Anything inside `.git` is skipped. Source files are never removed.

> **Tip:** always do a `--dry-run` first and read the list before deleting.

---

## Git Bash — `clean-builds.sh`

From anywhere (the script locates the repo root itself):

```bash
cd /d/Automata
./scripts/clean-builds.sh --dry-run    # preview only, deletes nothing
./scripts/clean-builds.sh              # delete build output
./scripts/clean-builds.sh --deep       # also remove vcpkg_installed/
./scripts/clean-builds.sh --deep -n    # preview a deep clean
```

`-n` is accepted as a short form of `--dry-run`.

If you get `permission denied`, invoke it through bash explicitly:

```bash
bash scripts/clean-builds.sh --dry-run
```

**In VS Code:** open a terminal with the **Git Bash** profile
(Terminal → the `+` split dropdown → *Git Bash*), then run the commands above.

---

## CMD / PowerShell — `clean-builds.cmd`

From the repo root (or any directory — it `cd`s to the root itself):

```bat
cd /d d:\Automata
scripts\clean-builds.cmd --dry-run     :: preview only, deletes nothing
scripts\clean-builds.cmd               :: delete build output
scripts\clean-builds.cmd --deep        :: also remove vcpkg_installed
```

`-n` and `/dry-run` are also accepted as the dry-run flag.

**PowerShell** — same commands; if you launch it by full path prefix it with `&`:

```powershell
cd d:\Automata
& scripts\clean-builds.cmd --dry-run
```

**Double-click** `clean-builds.cmd` in File Explorer to run a real clean
(no dry-run). The window may close immediately after it finishes.

---

## Notes

- Both scripts are safe to run when there is nothing to clean — they simply
  report `Nothing to clean`.
- Because the subproject(s) are git submodules, running either script cleans
  build output across all of them in one pass.
- After `--deep`, restore dependencies by re-running the vcpkg manifest install
  (or just rebuild — CMake/MSBuild with the vcpkg toolchain restores
  `vcpkg_installed/` automatically).
