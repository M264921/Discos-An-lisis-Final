#ifndef AppVersion
  #define AppVersion "1.1.0"
#endif
#ifndef SourceDir
  #error SourceDir must point to the tested PyInstaller folder
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
AppId={{8C0AC42D-5493-4C6C-8C5A-549F6BF52141}
AppName=MingoMedia
AppVersion={#AppVersion}
AppPublisher=MingoMedia
AppPublisherURL=https://github.com/M264921/Discos-An-lisis-Final
DefaultDirName={localappdata}\Programs\MingoMedia
DefaultGroupName=MingoMedia
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=MingoMedia-Setup-{#AppVersion}-win64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\MingoMedia.exe
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el Escritorio"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MingoMedia"; Filename: "{app}\MingoMedia.exe"
Name: "{autodesktop}\MingoMedia"; Filename: "{app}\MingoMedia.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\MingoMedia.exe"; Description: "Abrir MingoMedia"; Flags: nowait postinstall skipifsilent
