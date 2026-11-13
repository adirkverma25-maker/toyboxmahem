; Inno Setup script for the Toybox Mayhem Windows installer.
; Built by tools/build_installer.sh (export the game first, then: ISCC /DAppVersion=1.0.0 installer/toybox_mayhem.iss).
; Installs for the current user by default (no admin prompt); saves live in %APPDATA%\Godot\app_userdata\Toybox Mayhem
; and are left alone on uninstall.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{DF4C45D1-5F42-4EA4-B596-228E4DD498F3}
AppName=Toybox Mayhem
AppVersion={#AppVersion}
AppVerName=Toybox Mayhem {#AppVersion}
AppPublisher=Toybox Mayhem
DefaultDirName={autopf}\Toybox Mayhem
DefaultGroupName=Toybox Mayhem
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\build
OutputBaseFilename=ToyboxMayhem-Setup
SetupIconFile=..\assets\icon\toybox_icon.ico
UninstallDisplayIcon={app}\ToyboxMayhem.exe
UninstallDisplayName=Toybox Mayhem
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\ToyboxMayhem.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\icon\toybox_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Toybox Mayhem"; Filename: "{app}\ToyboxMayhem.exe"; IconFilename: "{app}\toybox_icon.ico"
Name: "{group}\Uninstall Toybox Mayhem"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Toybox Mayhem"; Filename: "{app}\ToyboxMayhem.exe"; IconFilename: "{app}\toybox_icon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\ToyboxMayhem.exe"; Description: "{cm:LaunchProgram,Toybox Mayhem}"; Flags: nowait postinstall skipifsilent
