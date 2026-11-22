# fsm::dfa visualizer — Windows installer

This folder packages the app into a single Windows installer
(`fsm_visualizer-<version>-setup.exe`) using **Inno Setup**. It is a
**per-user** installer: it runs without administrator rights and installs into
the current user's profile.

Contents:

| File | Purpose |
|------|---------|
| `package.ps1` | One command: build (Release) → deploy Qt runtime → compile the installer. |
| `installer.iss` | Inno Setup script (what goes in, shortcuts, uninstaller, icon). |
| `THIRD-PARTY-NOTICES.txt` | Qt LGPLv3 / MinGW-runtime notice, shown during install and shipped with the app. |

---

## Building the installer

### Prerequisites (one-time)

- **Qt 6.8.3, MinGW 64-bit** — expected at `C:\Qt\6.8.3\mingw_64`
  (with the matching toolchain under `C:\Qt\Tools\mingw1310_64` and
  `C:\Qt\Tools\Ninja`).
- **Inno Setup 6** — install once with:
  ```powershell
  winget install JRSoftware.InnoSetup
  ```

### Build it

From the `fsm_visualizer` folder:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\package.ps1 -Trim
```

Output:

```
build-release\fsm_visualizer-<version>-setup.exe
build-release\fsm_visualizer-latest-setup.exe   (a copy with a stable name)
```

`package.ps1` runs three steps:

1. **Release build** into `build-release\` (CMake + Ninja, MinGW).
2. **`windeployqt`** — copies the Qt DLLs, QML module plugins, the `qwindows`
   platform plugin and the MinGW runtime next to the exe in `build-release\dist\`.
3. **Inno Setup (`ISCC.exe`)** — compiles `installer.iss` over `dist\` into the
   final `setup.exe`.

`build-release\` is git-ignored, so the build output and the installer are not
committed.

### Options

- `-Trim` — drop files the app doesn't use (translations, virtual keyboard).
  Recommended; safe everywhere. (~24 MB installer.)
- `-Minimal` — `-Trim` **plus** drop the software-OpenGL fallback
  (`opengl32sw.dll`, ~16 MB) and the unused Qt Quick Controls styles
  (Material/Universal/Imagine/…; the app uses Fusion). Smaller (~17 MB), but the
  target machine must have working GPU OpenGL/Direct3D drivers — avoid for VMs /
  Remote Desktop / GPU-less boxes.
- `-SignToolCmd "<cmd>"` — code-sign the app exe and the installer (see
  **Code signing** below).
- Override tool locations if your install differs:
  ```powershell
  packaging\package.ps1 -QtDir "C:\Qt\6.8.3\mingw_64" `
                        -MingwDir "C:\Qt\Tools\mingw1310_64" `
                        -Ninja "C:\Qt\Tools\Ninja\ninja.exe" `
                        -Iscc  "C:\...\Inno Setup 6\ISCC.exe"
  ```
  (`-Iscc` is auto-detected in the common install locations if omitted.)

### Bumping the version

The version appears in two places — keep them in sync:

- `CMakeLists.txt`: `project(fsm_visualizer VERSION x.y.z ...)`
- `packaging\installer.iss`: `#define AppVersion "x.y.z"` (drives the output filename)

Then re-run `package.ps1`.

### Doing it by hand (if not using the script)

```powershell
cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CXX_COMPILER=C:/Qt/Tools/mingw1310_64/bin/g++.exe ^
  -DCMAKE_RC_COMPILER=C:/Qt/Tools/mingw1310_64/bin/windres.exe ^
  -DCMAKE_MAKE_PROGRAM=C:/Qt/Tools/Ninja/ninja.exe ^
  -DCMAKE_PREFIX_PATH=C:/Qt/6.8.3/mingw_64
cmake --build build-release

mkdir build-release\dist
copy build-release\appFsmVisualizer.exe build-release\dist\
C:\Qt\6.8.3\mingw_64\bin\windeployqt.exe --release --compiler-runtime --qmldir qml build-release\dist\appFsmVisualizer.exe

"%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" packaging\installer.iss
```

---

## Installing and using the app

### Install

1. Run `fsm_visualizer-<version>-setup.exe`.
2. **SmartScreen note:** the installer is not code-signed, so Windows may show
   *"Windows protected your PC"*. Click **More info → Run anyway**.
3. No administrator prompt (UAC) — it installs for the current user only.
4. Follow the wizard (optionally tick *Create a desktop shortcut*).

Installed to:

```
%LOCALAPPDATA%\Programs\fsm_visualizer\
```

You get a **FSM Visualizer** Start-menu entry (and a desktop shortcut if chosen).

### Uninstall

Either:

- **Settings → Apps → Installed apps → "fsm::dfa visualizer" → Uninstall**, or
- Start menu → **FSM Visualizer → Uninstall FSM Visualizer**.

It removes cleanly (per-user; no leftover admin/registry state).

### Where the app keeps its data

Settings and the last session are stored in the registry under
`HKEY_CURRENT_USER\Software\fsm_cpp\fsm_visualizer` (window geometry, theme,
last-opened file, autosaved session). Uninstalling the app does not remove
these; delete that key manually if you want a completely clean slate.

Documents you save (`.json`), and exported C++/DOT/PNG/SVG files, live wherever
you chose to save them and are left untouched.

---

## Code signing

Signing removes the SmartScreen "unknown publisher" warning. With a code-signing
certificate installed (or a hardware token), pass the signtool command to the
packager — it signs both the app exe and the installer (and the uninstaller):

```powershell
packaging\package.ps1 -Minimal `
  -SignToolCmd 'signtool.exe sign /fd sha256 /a /tr http://timestamp.digicert.com /td sha256'
```

The packager appends the file to sign to that command. It also passes `/DSIGN`
to Inno Setup, which activates the `SignTool=signtool` block in `installer.iss`.
Without `-SignToolCmd`, nothing is signed (the default).

## Notes / future options

- **`D3Dcompiler_47.dll`** (~4 MB) is kept even in `-Minimal` (some Direct3D
  shader paths use it); drop it only if you've confirmed the target doesn't need
  it.
- **Per-machine install:** switch `PrivilegesRequired=lowest` to `admin` in
  `installer.iss` and the `{auto*}` paths become `Program Files` / all-users
  (requires UAC).
