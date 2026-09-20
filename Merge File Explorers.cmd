@echo off
rem Double-click launcher for merge_file_explorers.ps1.
rem
rem Windows opens a .ps1 in an editor when you double-click it, and a plain
rem shortcut misses the flags the script needs, so this wrapper supplies them:
rem   -STA               the clipboard carries the folder path and needs it
rem   -ExecutionPolicy   the script is unsigned and local
rem   -NoProfile         your $PROFILE must not change how it behaves
rem
rem Right-click this file -> Send to -> Desktop (create shortcut) to get a
rem desktop or taskbar entry. Arguments are passed through, so a shortcut can
rem append -DelayScale 2 or -Trace.

setlocal
set "SCRIPT=%~dp0merge_file_explorers.ps1"

if not exist "%SCRIPT%" (
    echo Could not find merge_file_explorers.ps1 next to this launcher.
    echo Expected it at: "%SCRIPT%"
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %errorlevel%
