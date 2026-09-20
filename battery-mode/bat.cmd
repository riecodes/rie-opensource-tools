@echo off
REM ---------------------------------------------------------------------------
REM Shim for battery-mode.ps1. Install a copy of this file somewhere on PATH.
REM
REM The engine location comes from BATTERY_MODE_HOME so the shim keeps working
REM if the scripts move; the directory holding this shim is used as a fallback
REM when that variable is not set.
REM ---------------------------------------------------------------------------
setlocal

REM Resolution order, first hit wins:
REM   1. BATTERY_MODE_HOME, so the install can be relocated or overridden per shell
REM   2. the path baked in at install time, which still works in shells that were
REM      already open when the environment variable was created
REM   3. this shim's own directory, for running it straight out of the repo
set "ENGINE="

if defined BATTERY_MODE_HOME call :try "%BATTERY_MODE_HOME%"
if not defined ENGINE call :try "C:\dev\battery-mode"
if not defined ENGINE call :try "%~dp0"

if not defined ENGINE (
    echo Cannot find battery-mode.ps1.
    echo Looked in BATTERY_MODE_HOME ^(currently "%BATTERY_MODE_HOME%"^),
    echo the baked-in install path, and this shim's own folder "%~dp0".
    echo Set BATTERY_MODE_HOME to the folder containing battery-mode.ps1.
    exit /b 3
)

REM Prefer PowerShell 7 when present, fall back to Windows PowerShell.
where /q pwsh.exe
if %ERRORLEVEL%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" %*
)

exit /b %ERRORLEVEL%

REM Sets ENGINE when battery-mode.ps1 exists in the candidate directory %~1.
:try
set "CAND=%~1"
if not defined CAND goto :eof
if "%CAND:~-1%"=="\" set "CAND=%CAND:~0,-1%"
if exist "%CAND%\battery-mode.ps1" set "ENGINE=%CAND%\battery-mode.ps1"
goto :eof
