@echo off
rem ============================================================
rem run_watchers.cmd
rem   Start one watcher per candidate solution folder under a work folder: one TAB per candidate in a
rem   single Windows Terminal window (wt.exe). Without wt.exe, or with /windows, one console window each.
rem   (A candidate = a direct subfolder that contains a .sln or .slnx.)
rem   Each tab / window runs run_watcher.cmd for that folder, so every candidate has its own
rem   watcher (the watcher serves one folder). Closing a tab / window stops only that watcher.
rem
rem Usage:
rem   run_watchers.cmd [WorkFolder] [/list] [/windows]
rem
rem   WorkFolder : the folder that holds the candidate folders (the one with solutions.md).
rem                Omitted = the current folder.
rem   /list      : only list the candidates; do not start anything.
rem   /windows   : do not use Windows Terminal; open one console window per candidate.
rem
rem Windows Terminal: the tabs go to the named window "watchers" (created if it does not exist),
rem   so running this again adds tabs to the same window (the duplicates stop with
rem   "a watcher is already running").
rem
rem Notes:
rem   - Folders whose name starts with "." (.claude, .git ...) are skipped.
rem   - A candidate that already has a watcher is refused by run_watcher.cmd itself; nothing breaks.
rem   - A candidate created after this run needs its own run_watcher.cmd (or run this again).
rem   - Needs run_watcher.cmd, watch_and_build.ps1 and build-windows.cmd in the same folder as this file.
rem   - This file is ASCII only (CP932 safe), CRLF.
rem ============================================================
setlocal EnableExtensions

rem Keep the folder of this file BEFORE the argument loop: "shift" also shifts %0, so %~dp0 would change.
set "HERE=%~dp0"
set "WORK="
set "LISTONLY="
set "FORCEWIN="
set "WTARGS="
:args
if "%~1"=="" goto :args_done
if /i "%~1"=="/list" (
    set "LISTONLY=1"
) else if /i "%~1"=="/windows" (
    set "FORCEWIN=1"
) else if not defined WORK (
    set "WORK=%~f1"
) else (
    echo ERROR: unexpected argument: %~1
    goto :fail_usage
)
shift
goto :args
:args_done
if not defined WORK set "WORK=%CD%"
if not "%WORK:~-2%"==":\" if "%WORK:~-1%"=="\" set "WORK=%WORK:~0,-1%"

if not exist "%WORK%\" (
    echo ERROR: work folder not found: %WORK%
    goto :fail_usage
)
set "WATCHER=%HERE%run_watcher.cmd"
if not exist "%WATCHER%" (
    echo ERROR: not found: %WATCHER%
    goto :fail
)

rem Windows Terminal is used when wt.exe is found (and /windows is not given).
set "USEWT="
if not defined FORCEWIN where wt.exe >nul 2>&1 && set "USEWT=1"

echo ========================================================
echo  Work folder: %WORK%
if defined LISTONLY (
    echo  Mode       : list only ^(nothing is started^)
) else if defined USEWT (
    echo  Mode       : Windows Terminal tabs ^(window "watchers"^)
) else (
    echo  Mode       : separate console windows
)
echo ========================================================
set /a COUNT=0
for /d %%d in ("%WORK%\*") do call :candidate "%%~fd" "%%~nxd"

echo.
if %COUNT%==0 (
    echo No candidate folder ^(a subfolder with a .sln / .slnx^) found in %WORK%
    echo Check the folder, or run /new-solutions first.
    goto :end
)
if defined LISTONLY (
    echo %COUNT% candidate^(s^) found. Run without /list to start the watchers.
    goto :end
)
if defined USEWT (
    wt.exe -w watchers %WTARGS%
    echo Started %COUNT% watcher tab^(s^) in Windows Terminal. Each one runs until its tab is closed.
) else (
    echo Started %COUNT% watcher window^(s^). Each one runs until its window is closed.
)
goto :end

:candidate
set "NAME=%~2"
if "%NAME:~0,1%"=="." exit /b 0
set "HAS="
if exist "%~1\*.slnx" set "HAS=1"
if exist "%~1\*.sln" set "HAS=1"
if not defined HAS exit /b 0
set /a COUNT+=1
echo   %NAME%   ^(%~1^)
if defined LISTONLY exit /b 0
if defined USEWT (
    if defined WTARGS (
        set "WTARGS=%WTARGS% ; new-tab --title "%NAME%" --suppressApplicationTitle "%WATCHER%" "%~1""
    ) else (
        set "WTARGS=new-tab --title "%NAME%" --suppressApplicationTitle "%WATCHER%" "%~1""
    )
    exit /b 0
)
start "watcher: %NAME%" cmd /c ""%WATCHER%" "%~1""
exit /b 0

:fail_usage
echo.
echo Usage  : run_watchers.cmd [WorkFolder] [/list] [/windows]
echo Example: run_watchers.cmd C:\path\to\WorkFolder
echo         run_watchers.cmd .          ^(the current folder^)
echo         run_watchers.cmd . /list    ^(only list the candidates^)
echo         run_watchers.cmd . /windows ^(separate console windows, not Windows Terminal^)
:fail
echo.
pause
exit /b 2

:end
echo.
pause
exit /b 0
