; Metanoia Windows Installer — NSIS script
; Build with: makensis scripts/installer.nsi

!define PRODUCT_NAME "Metanoia"
!define PRODUCT_VERSION "1.0.0"
!define PRODUCT_PUBLISHER "Metanoia Bible Study"

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "Metanoia-Setup-${PRODUCT_VERSION}.exe"
InstallDir "$PROGRAMFILES64\${PRODUCT_NAME}"
RequestExecutionLevel admin

; Load icon for the installer itself
Icon "assets\metanoia.ico"
UninstallIcon "assets\metanoia.ico"

Section "Metanoia" SecMain
  SectionIn RO
  SetOutPath "$INSTDIR"

  ; App binary + all GTK4 DLLs
  File /r "zig-out\bin\*.*"

  ; Database
  File /nonfatal "data\bible.db"

  ; Theme
  File /nonfatal "assets\themes\tokyo-night.css"

  ; Uninstaller
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Start Menu shortcut
  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Metanoia.lnk" \
    "$INSTDIR\metanoia.exe" "" "$INSTDIR\metanoia.exe" 0
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall.lnk" \
    "$INSTDIR\uninstall.exe"

  ; Desktop shortcut (optional)
  CreateShortCut "$DESKTOP\Metanoia.lnk" \
    "$INSTDIR\metanoia.exe" "" "$INSTDIR\metanoia.exe" 0

  ; Registry for Add/Remove Programs
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "UninstallString" "$INSTDIR\uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "DisplayIcon" "$INSTDIR\metanoia.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" \
    "Publisher" "${PRODUCT_PUBLISHER}"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\*.*"
  RMDir /r "$INSTDIR"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\*.*"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"
  Delete "$DESKTOP\Metanoia.lnk"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
SectionEnd
