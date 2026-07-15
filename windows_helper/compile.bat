@echo off
title Metanoia Setup Wizard — Compiler

echo [Metanoia] Compiling Windows Setup Wizard...
echo.

REM Find the C# compiler that ships with .NET Framework
if exist "%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" (
    set CSC="%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
) else if exist "%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe" (
    set CSC="%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) else (
    echo ERROR: C# compiler not found.
    echo Make sure .NET Framework 4.7.2 or later is installed.
    echo Download: https://dotnet.microsoft.com/download/dotnet-framework
    pause
    exit /b 1
)

%CSC% /target:winexe /out:windows_helper\MetanoiaSetup.exe ^
    /reference:System.IO.Compression.dll ^
    /reference:System.IO.Compression.FileSystem.dll ^
    /win32icon:assets\Metanoia.icns ^
    windows_helper\SetupWizard.cs

if %ERRORLEVEL% equ 0 (
    echo.
    echo SUCCESS: MetanoiaSetup.exe created in windows_helper\
    echo Double-click MetanoiaSetup.exe to run the setup wizard.
) else (
    echo.
    echo COMPILATION FAILED (exit code %ERRORLEVEL%)
    echo Check that all references are correct.
)

pause
