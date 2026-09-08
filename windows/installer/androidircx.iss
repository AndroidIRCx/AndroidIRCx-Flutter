; Inno Setup script for AndroidIRCx (Flutter Windows desktop build).
;
; Produces a setup.exe that installs and cleanly upgrades the app (a stable
; AppId lets a newer setup replace an older install in place). The same app is
; also shipped as a portable .zip; both are built by the Release Windows
; workflow and attached to the matching GitHub release.
;
; Values that vary per build are passed in from CI:
;   ISCC /DAppVersion=1.0.16 /DSourceDir=<abs path to Release folder> androidircx.iss
; Sensible fallbacks are defined so the script also compiles for a local run.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#ifndef SourceDir
  ; Relative to this .iss file: ..\..\build\windows\x64\runner\Release
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#define AppName "AndroidIRCx"
#define AppPublisher "AndroidIRCx"
#define AppExeName "androidircx.exe"
#define AppURL "https://github.com/AndroidIRCx/AndroidIRCx-Flutter"

[Setup]
; A fixed AppId is what makes upgrades work - do not change it between releases.
AppId={{7B9E4C1A-2D6F-4A88-9E3C-5F1A2B3C4D5E}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}
OutputBaseFilename=AndroidIRCx-Flutter-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; 64-bit only build.
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Install per-machine by default, but let a user without admin rights choose a
; per-user install instead (the app is fully relocatable / portable).
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
