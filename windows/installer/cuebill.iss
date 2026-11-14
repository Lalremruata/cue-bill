; CueBill Windows installer (Inno Setup 6.3 or later).
;
; Build, on Windows, from the project folder:
;   1. flutter build windows --release
;      (add --dart-define-from-file=google_oauth.json for Google Drive backups)
;   2. Optional, recommended: put Microsoft's vc_redist.x64.exe next to this script
;      (https://aka.ms/vs/17/release/vc_redist.x64.exe). The installer then installs the
;      Visual C++ runtime on PCs that don't have it. Without it, CueBill won't start on those PCs.
;   3. Open this file in Inno Setup and press Compile, or run:
;      "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows\installer\cuebill.iss
;
; Output: build\windows\installer\CueBill-Setup-<version>.exe
;
; The version is read from cue_bill.exe, which Flutter stamps with the version in pubspec.yaml.
; Sales data lives in %APPDATA%, not in the install folder, so updating or uninstalling
; CueBill keeps it.

#define AppName "CueBill"
#define AppExe "cue_bill.exe"
#define BuildDir AddBackslash(SourcePath) + "..\..\build\windows\x64\runner\Release"
#define VcRedist AddBackslash(SourcePath) + "vc_redist.x64.exe"

#ifnexist BuildDir + "\" + AppExe
  #error build\windows\x64\runner\Release\cue_bill.exe not found. Run: flutter build windows --release
#endif
#define AppVersion GetVersionNumbersString(BuildDir + "\" + AppExe)

[Setup]
; Never change AppId: Windows uses it to recognise updates to the same app.
AppId={{D38AF75A-0756-4BDF-8FE9-67D8D9A22BF9}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir=..\..\build\windows\installer
OutputBaseFilename=CueBill-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
PrivilegesRequired=admin
; Close a running CueBill before updating it.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifexist VcRedist
Source: "{#VcRedist}"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: NeedsVcRuntime
#endif

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
#ifexist VcRedist
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing the Microsoft Visual C++ runtime..."; Flags: waituntilterminated; Check: NeedsVcRuntime
#endif
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// True when the 64-bit Visual C++ 2015-2022 runtime, which Flutter apps need, isn't installed.
function NeedsVcRuntime: Boolean;
var
  Installed: Cardinal;
begin
  Result := not (RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Installed', Installed) and (Installed = 1));
end;
