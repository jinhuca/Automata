# Automata

Umbrella repository for automata / state-machine projects.

| Subproject | Description |
| ---------- | ----------- |
| [`fsm_cpp`](fsm_cpp/) | C++ finite-state-machine library, demos, tests, and a Qt/QML `fsm_visualizer` GUI. |

## Getting the code

```bash
git clone <url> Automata
```

## Building / dependencies

`fsm_cpp` is **not self-contained** — it depends on external tooling and
libraries that are not vendored in the repo. A fresh checkout does **not**
include `vcpkg_installed/` (it is git-ignored), so the first build must restore
dependencies via vcpkg.

### Required

| Dependency | Needed by | Notes |
| ---------- | --------- | ----- |
| **Visual Studio 2022 (MSVC)** | `FiniteStateMachine.sln` — core library, demos, tests | C++23 (`/std:c++23`). Tests use the built-in CppUnitTest framework. |
| **Qt 6.12.x** (min 6.5; components: `Quick`, `QuickControls2`, `Quick3D`) | `fsm_visualizer` (CMake) | Must be installed separately — **not** managed by vcpkg. Reference build used `C:/Qt/6.12.0/mingw_64`. |
| **vcpkg** | restoring `rxcpp` | Manifest mode via `fsm_cpp/vcpkg.json` (baseline pinned). Provides **rxcpp**, used by `src/demo` and `src/console_demo`. |

### Optional

| Dependency | Needed by | Notes |
| ---------- | --------- | ----- |
| **Python 3** | `scripts/gen_fsm_hpp.py` code generation | CMake locates it via `find_package(Python3 ... QUIET)`. |
| **Inno Setup** | `fsm_visualizer/packaging/` | Only to produce the Windows installer (`package.ps1` + `installer.iss`). |

> The core FSM library (`fsm_cpp/src/fsm`) itself is self-contained (standard
> C++ only). The external dependencies come from the demos (**rxcpp**) and the
> GUI (**Qt 6**).

### Restoring dependencies

In manifest mode, building with the vcpkg toolchain restores
`vcpkg_installed/` automatically. To restore explicitly:

```bash
cd fsm_cpp
vcpkg install            # reads vcpkg.json, populates vcpkg_installed/
```

See `fsm_cpp/build_readme.txt` for packaging/versioning notes.

## Cleaning build output

Scripts to remove all build output across the repo and submodules live in
[`scripts/`](scripts/) — see [scripts/README.md](scripts/README.md).

```bash
# Git Bash
./scripts/clean-builds.sh --dry-run     # preview
./scripts/clean-builds.sh               # delete build output
./scripts/clean-builds.sh --deep        # also remove vcpkg_installed/
```

```bat
:: CMD / PowerShell / double-click
scripts\clean-builds.cmd --dry-run
scripts\clean-builds.cmd
scripts\clean-builds.cmd --deep
```

By default `vcpkg_installed/` is left in place (removing it means re-running the
vcpkg restore); `--deep` removes it too.
