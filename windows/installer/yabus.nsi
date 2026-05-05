; YABus Windows NSIS Installer

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

!define APPNAME "YABus"
!define APPNAMEINTERNAL "YetAnotherBusApp"
!define COMPANYNAME "AvianJay"
!define APPID "tw.avianjay.taiwanbus.flutter"
!define DESCRIPTION "台灣公車即時動態查詢"

; These will be overridden by CI via /D command-line flags
!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef SOURCE_DIR
  !define SOURCE_DIR "..\..\build\windows\x64\runner\Release"
!endif

Name "${APPNAME} ${VERSION}"
OutFile "YABus-${VERSION}-windows-x64-setup.exe"
InstallDir "$LOCALAPPDATA\${APPNAME}"
RequestExecutionLevel user
ShowInstDetails nevershow
ShowUninstDetails nevershow
AutoCloseWindow true

; ── Modern UI ──────────────────────────────────────────────
!define MUI_ICON "..\..\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\..\windows\runner\resources\app_icon.ico"
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "TradChinese"

; ── Install ─────────────────────────────────────────────────
Section "Install"
  SetShellVarContext current

  ; In-app updates launch this installer before the Flutter process exits.
  ; Close the running app first so $INSTDIR can be replaced reliably.
  ExecWait "taskkill /IM ${APPNAMEINTERNAL}.exe /F"

  SetOutPath $INSTDIR

  ; Remove old install
  RMDir /r "$INSTDIR"

  ; Copy all files
  File /r "${SOURCE_DIR}\*.*"

  ; Write uninstaller
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Registry entries for Add/Remove Programs
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}" \
    "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}" \
    "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}" \
    "Publisher" "${COMPANYNAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}" \
    "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}" \
    "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}" \
    "DisplayIcon" "$INSTDIR\${APPNAMEINTERNAL}.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}" \
    "NoRepair" "1"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}" \
    "NoModify" "1"

  ; Estimate size
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}" \
    "EstimatedSize" "$0"

  ; Start Menu shortcut
  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\${APPNAMEINTERNAL}.exe" "" \
    "$INSTDIR\${APPNAMEINTERNAL}.exe" 0

  ; Desktop shortcut
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\${APPNAMEINTERNAL}.exe" "" \
    "$INSTDIR\${APPNAMEINTERNAL}.exe" 0

  ; Launch the app after a successful install, including silent updates.
  Exec '"$INSTDIR\${APPNAMEINTERNAL}.exe"'
SectionEnd

; ── Uninstall ───────────────────────────────────────────────
Section "Uninstall"
  SetShellVarContext current
  ; Kill running process if any
  ExecWait "taskkill /IM ${APPNAMEINTERNAL}.exe /F"

  ; Remove files
  RMDir /r "$INSTDIR"

  ; Remove shortcuts
  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  RMDir "$SMPROGRAMS\${APPNAME}"
  Delete "$DESKTOP\${APPNAME}.lnk"

  ; Remove registry entries
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}"
SectionEnd

; ── Init ────────────────────────────────────────────────────
Function .onInit
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}
FunctionEnd
