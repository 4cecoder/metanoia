; packaging/windows-installer.nsi
;
; NSIS installer for the bundled Windows distribution produced by
; packaging/build-windows.sh (metanoia.exe + its full DLL closure + GTK4
; runtime resources, all flat in one directory — see that script's header
; comment for why "flat" is deliberate, not lazy: it matches GLib's own
; documented g_win32_get_package_installation_directory_of_module()
; algorithm, so GTK/GDK-Pixbuf auto-discover "$INSTDIR/lib/..." and
; "$INSTDIR/share/..." with no bin/ nesting required).
;
; Built with: mingw-w64-ucrt-x86_64-nsis's makensis.exe (already installed
; by both release workflows' "Setup MSYS2" step — it was unused until this
; task). Verified only by inspection against NSIS's documented grammar/
; Modern UI 2 conventions — there is no Windows/NSIS environment available
; in the sandbox this was written in to actually run makensis. See this
; task's final report for what was and wasn't verified.
;
; Usage (invocation cwd does NOT matter — see the path-resolution note
; below — but this repo's CI always runs it as
; `makensis -DAPP_VERSION=... packaging/windows-installer.nsi` from the
; repo root, matching every other packaging script's convention):
;   makensis -DAPP_VERSION=1.2.3 packaging/windows-installer.nsi
;
; IMPORTANT, actually verified (not just researched) by installing
; Homebrew's `makensis` package on the macOS sandbox this was written in
; and compiling this exact script against a fake dist/ tree: NSIS resolves
; every relative path used in `File`/`Icon`/etc. (and in any !define whose
; value is later used by one of those) relative to THIS .nsi FILE'S OWN
; DIRECTORY (packaging/), NOT the directory makensis was invoked from. A
; first draft of this script used CI-root-relative defaults like
; "dist/Metanoia" and failed to compile for exactly this reason ("File:
; ... -> no files found"). DIST_DIR/OUT_FILE/the icon path below are
; therefore "../"-relative to packaging/, not to the repo root — do not
; "fix" them back to repo-root-relative without re-testing, that's the bug
; this comment exists to prevent someone from reintroducing.
!ifndef DIST_DIR
  !define DIST_DIR "..\dist\Metanoia"
!endif
!ifndef OUT_FILE
  !define OUT_FILE "..\dist\Metanoia-Setup.exe"
!endif
!ifndef APP_VERSION
  !define APP_VERSION "0.0.0-dev"
!endif

!include "MUI2.nsh"

!define APP_NAME "Metanoia"
!define APP_PUBLISHER "ByteCats"
!define UNINSTALL_REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"

Name "${APP_NAME}"
OutFile "${OUT_FILE}"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKCU "Software\${APP_NAME}" "InstallDir"
RequestExecutionLevel admin
Unicode true
SetCompressor /SOLID lzma

; ── Modern UI 2 setup ───────────────────────────────────────────────────
; Standard, well-documented NSIS idiom (bundled with NSIS itself, so no
; extra download/plugin needed) rather than a hand-rolled page flow.
!define MUI_ICON "..\assets\metanoia.ico"
!define MUI_UNICON "..\assets\metanoia.ico"
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; ── Install ──────────────────────────────────────────────────────────────
Section "Metanoia" SecMain
  SectionIn RO

  SetOutPath "$INSTDIR"
  ; Recursive copy of the entire pre-assembled dist folder: exe, every
  ; bundled DLL, metanoia.ico, data/, assets/, lib/, share/ — everything
  ; packaging/build-windows.sh produced, verbatim.
  File /r "${DIST_DIR}\*.*"

  ; Regenerate gdk-pixbuf's loaders.cache against the REAL install path
  ; this specific user chose (may not be the default $PROGRAMFILES64
  ; path — MUI_PAGE_DIRECTORY lets them pick anything). This is the fix
  ; for the CI-baked-absolute-path limitation documented in
  ; packaging/build-windows.sh section 2 — the one place in this whole
  ; pipeline where the cache is guaranteed to point at the correct,
  ; final, real location. Best-effort: don't abort the install if this
  ; single step fails (a stale/incorrect cache still leaves the rest of
  ; the app usable, just with degraded icon rendering).
  IfFileExists "$INSTDIR\gdk-pixbuf-query-loaders.exe" 0 SkipPixbufCache
    ExecWait '"$INSTDIR\gdk-pixbuf-query-loaders.exe" --update-cache'
  SkipPixbufCache:

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\${APP_NAME}" "InstallDir" "$INSTDIR"

  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  ; Shortcut's working directory is whatever SetOutPath was last set to —
  ; that's "$INSTDIR" here (see the SetOutPath above), which matches where
  ; data/bible.db and assets/ actually are (src/main.zig opens both as
  ; bare paths relative to cwd, and has no Windows equivalent of its own
  ; macOS resolveBundleRoot() chdir — see packaging/build-windows.sh for
  ; the full reasoning). Getting this wrong is the single easiest way for
  ; the Start Menu shortcut to launch a window that can't find its Bible.
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\metanoia.exe" "" "$INSTDIR\metanoia.ico" 0
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe"

  ; Add/Remove Programs registration — the standard, modern-NSIS-idiomatic
  ; registry-key pattern (no undocumented shortcuts taken here).
  WriteRegStr HKLM "${UNINSTALL_REGKEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINSTALL_REGKEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_REGKEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "${UNINSTALL_REGKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_REGKEY}" "DisplayIcon" "$INSTDIR\metanoia.ico"
  WriteRegStr HKLM "${UNINSTALL_REGKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINSTALL_REGKEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTALL_REGKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_REGKEY}" "NoRepair" 1
SectionEnd

; ── Uninstall ────────────────────────────────────────────────────────────
Section "Uninstall"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  RMDir /r "$INSTDIR\data"
  RMDir /r "$INSTDIR\assets"
  RMDir /r "$INSTDIR\lib"
  RMDir /r "$INSTDIR\share"
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\metanoia.exe"
  Delete "$INSTDIR\metanoia.ico"
  Delete "$INSTDIR\gdk-pixbuf-query-loaders.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKLM "${UNINSTALL_REGKEY}"
  DeleteRegKey HKCU "Software\${APP_NAME}"
SectionEnd
