; Inno Setup script for fsm::dfa visualizer (Windows x64).
; Compile with:  ISCC.exe packaging\installer.iss
; (run packaging\package.ps1 to build + deploy + compile in one step).
; Paths are relative to this .iss file (packaging\).

#define AppName "fsm::dfa visualizer"
; Filesystem-safe name for Start-menu folder / shortcut files (AppName has ':'
; which is illegal in folder and .lnk file names).
#define ShortcutName "FSM Visualizer"
#define AppVersion "1.0.1"
#define AppExe "appFsmVisualizer.exe"
#define AppPublisher "fsm_cpp"
#define DistDir "..\build-release\dist"

[Setup]
; A stable unique id so upgrades replace the previous install.
AppId={{A1F3C2D4-5B6E-47F8-9A0B-1C2D3E4F5A6B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
; Per-user install: no admin/UAC. With lowest privileges the "auto" constants
; resolve to per-user locations ({autopf} -> {localappdata}\Programs, {group}
; and {autodesktop} -> the current user's menu/desktop).
PrivilegesRequired=lowest
DefaultDirName={autopf}\fsm_visualizer
DefaultGroupName={#ShortcutName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
OutputDir=..\build-release
OutputBaseFilename=fsm_visualizer-{#AppVersion}-setup
SetupIconFile=..\appicon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; 64-bit app: install under 64-bit Program Files and only on x64 Windows.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=THIRD-PARTY-NOTICES.txt
; Code signing (optional): package.ps1 -SignToolCmd "..." passes /DSIGN and a
; "signtool" sign-tool definition, which signs the installer + uninstaller.
#ifdef SIGN
SignTool=signtool
SignedUninstaller=yes
#endif

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#DistDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#ShortcutName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#ShortcutName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#ShortcutName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
