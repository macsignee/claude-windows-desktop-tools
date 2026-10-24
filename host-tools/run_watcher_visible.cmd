@echo off
rem ============================================================
rem run_watcher_visible.cmd
rem   run_watcher.cmd for watching UI tests with your own eyes.
rem   UI tests run on YOUR desktop (windows are visible, and you cannot use the PC
rem   comfortably while they run) with a slow-motion delay between operations.
rem
rem Usage:
rem   run_watcher_visible.cmd [ProjectDir] [Solution] [Platform] [Configuration]
rem   (same arguments as run_watcher.cmd)
rem   Delay: set WATCH_UI_SLOWMO_MS before running (default 800 ms).
rem ============================================================
setlocal
set "WATCH_UI_DESKTOP=default"
if not defined WATCH_UI_SLOWMO_MS set "WATCH_UI_SLOWMO_MS=800"
echo [visible mode] WATCH_UI_DESKTOP=%WATCH_UI_DESKTOP%  WATCH_UI_SLOWMO_MS=%WATCH_UI_SLOWMO_MS%
call "%~dp0run_watcher.cmd" %*
exit /b %errorlevel%
