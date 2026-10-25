@echo off
rem ============================================================
rem run_watcher.cmd
rem   プロジェクトフォルダを指定して、ウォッチャー (watch_and_build.ps1) を起動する。
rem   ウォッチャーは、フラグファイルを監視して、ビルド（必要ならテストも）を実行する。
rem
rem 使い方:
rem   run_watcher.cmd [ProjectDir] [Solution] [Platform] [Configuration]
rem   （プロジェクトフォルダをこのファイルにドラッグ＆ドロップしても起動できる）
rem
rem   ProjectDir     : 省略時は、このファイルがあるフォルダ（通常は、プロジェクトのフォルダを指定する）
rem   Solution       : 省略時は、ProjectDir 内の .slnx、なければ .sln を自動検出する (ソリューションが、まだなくても起動できる。トリガーが来たときに探す)
rem   Platform       : 省略時は auto  (auto / x64 / Win32 / x86 / ARM64 / AnyCPU)
rem                    auto は、C++ のプロジェクトがあれば x64、.NET だけなら AnyCPU
rem   Configuration  : 省略時は Debug
rem
rem 前提:
rem   watch_and_build.ps1 と build-windows.cmd を、このファイルと同じフォルダに置くこと。
rem   画面に出すメッセージ (echo) は、文字化けを避けるため、英語 (ASCII) のままにしてある。
rem   このファイルの文字コードは CP932 (Shift_JIS)、改行は CRLF。
rem ============================================================
rem setlocal: 以降の変数の変更を、このバッチの中だけに閉じ込める（呼び出し元の環境を汚さない）。
setlocal EnableExtensions

rem --- プロジェクトフォルダを決める。第1引数があれば、そのフルパス。なければ、このファイルのフォルダ ---
rem 引数なしのときは、DEFAULT_DIR に印を付ける（エラー時に、引数の指定を案内するため）。
set "DEFAULT_DIR="
if not "%~1"=="" (
    set "PROJECT_DIR=%~f1"
) else (
    set "PROJECT_DIR=%~dp0"
    set "DEFAULT_DIR=1"
)
rem 末尾の円記号を取り除く。残すと、PowerShell -File に渡す引数が、引用符のエスケープと解釈されて壊れる。
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

rem フォルダが存在しなければ、メッセージを出して、:fail で終了する。
if not exist "%PROJECT_DIR%\" (
    echo ERROR: project folder not found: %PROJECT_DIR%
    goto :fail_usage
)

rem --- ソリューションを決める。第2引数があれば、それを使う（自動検出しない） ---
set "SLN_FILE=%~2"
if defined SLN_FILE goto :sln_ready
rem *.sln のワイルドカードは、8.3 形式の短い名前の仕様により、.slnx にも一致することがある。
rem そのため、拡張子を厳密に確認する。
rem 両方ある場合は、新しい形式の .slnx を優先する。
rem 見つかった最初の .slnx と .sln の名前を、それぞれの変数に入れる。
set "FOUND_SLNX="
set "FOUND_SLN="
for %%f in ("%PROJECT_DIR%\*.slnx") do (
    if /i "%%~xf"==".slnx" if not defined FOUND_SLNX set "FOUND_SLNX=%%~nxf"
)
for %%f in ("%PROJECT_DIR%\*.sln") do (
    if /i "%%~xf"==".sln" if not defined FOUND_SLN set "FOUND_SLN=%%~nxf"
)
rem .slnx があればそれを、なければ .sln を使う。両方あるときは、どちらを使ったかを知らせる。
if defined FOUND_SLNX (
    set "SLN_FILE=%FOUND_SLNX%"
    if defined FOUND_SLN echo NOTE: both .slnx and .sln found; using %FOUND_SLNX% ^(pass the 2nd argument to choose^)
) else (
    set "SLN_FILE=%FOUND_SLN%"
)
rem --- ここまでで、ソリューションが決まっていなくても、起動する (ウォッチャーが、トリガーが来たときに探す) ---
rem ただし、フォルダの引数がなく、このファイルのフォルダを使っているときは、指定ミスの可能性が高いので、終了する。
:sln_ready
if not defined SLN_FILE if defined DEFAULT_DIR (
    echo ERROR: no .sln / .slnx found in %PROJECT_DIR%
    echo NOTE: no ProjectDir argument was given, so the folder of this cmd was used.
    goto :fail_usage
)
rem ソリューションがあれば、-SolutionPath を渡す。なければ、渡さない (ウォッチャーが、トリガーのたびに、フォルダから探す)。
set "SLN_ARG="
if defined SLN_FILE set SLN_ARG=-SolutionPath "%SLN_FILE%"

rem --- ビルド構成。省略時は、Platform=x64、Configuration=Debug ---
set "WATCH_PLATFORM=%~3"
if "%WATCH_PLATFORM%"=="" set "WATCH_PLATFORM=auto"
set "WATCH_CONFIG=%~4"
if "%WATCH_CONFIG%"=="" set "WATCH_CONFIG=Debug"

rem --- ウォッチャー本体 (ps1) は、このファイルと同じフォルダにあるものを使う ---
set "WATCH_PS=%~dp0watch_and_build.ps1"
if not exist "%WATCH_PS%" (
    echo ERROR: not found: %WATCH_PS%
    goto :fail
)

rem --- 起動する内容を表示する ---
echo ========================================================
echo  Project : %PROJECT_DIR%
if defined SLN_FILE echo  Solution: %SLN_FILE%
if not defined SLN_FILE echo  Solution: ^(none yet - detected when a trigger arrives^)
echo  Build   : %WATCH_CONFIG% / %WATCH_PLATFORM%
echo ========================================================

rem --- ウォッチャーを起動する。終了するまで（ウィンドウを閉じるか Ctrl+C まで）ここで待つ ---
rem -ExecutionPolicy Bypass: ExecutionPolicy の設定に関係なく、この ps1 を実行する。
rem テスト実行の制限時間など、ここにない細かいオプションを使うときは、ps1 を直接起動する。
powershell -ExecutionPolicy Bypass -NoProfile -File "%WATCH_PS%" -TargetDir "%PROJECT_DIR%" %SLN_ARG% -Platform "%WATCH_PLATFORM%" -Configuration "%WATCH_CONFIG%"
echo.
echo Watcher exited with code %ERRORLEVEL%.
rem 終了メッセージを読めるよう、キー入力まで待つ。
pause
exit /b %ERRORLEVEL%

rem --- 使い方を表示してから、:fail に続く（引数の指定ミスのとき） ---
:fail_usage
echo.
echo Usage  : run_watcher.cmd ^<ProjectDir^> [Solution] [Platform] [Configuration]
echo Example : run_watcher.cmd C:\path\to\MyApp
echo          run_watcher.cmd .          ^(the current folder^)
rem --- エラー終了。メッセージを読めるよう、キー入力まで待ち、終了コード 2 で終わる ---
:fail
echo.
pause
exit /b 2
