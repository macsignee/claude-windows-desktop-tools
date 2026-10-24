@echo off
rem ============================================================
rem build-windows.cmd
rem   最新の Visual Studio (C++ ツール) の環境を VsDevCmd.bat で読み込み、
rem   MSBuild でソリューション/プロジェクトをビルドする。
rem
rem 使い方:
rem   build-windows.cmd <target> <Platform> [Configuration] [MSBuildTarget] [LogDir] [Features]
rem
rem   target         : ビルドするソリューションまたはプロジェクト (.sln .slnx .vcxproj .csproj)
rem   Platform       : x64 | Win32 | x86 | ARM64 | AnyCPU  (AnyCPU は MSBuild に Any CPU と渡す)
rem   Configuration  : 省略時は Debug
rem   MSBuildTarget  : Build (省略時) | Rebuild | Clean
rem   LogDir         : ログの出力先。省略時は <targetのフォルダ>\.claude-logs
rem   Features       : カンマ区切り。省略時は cpp
rem                    cpp     : C++ ツール入りの VS を要求し、cl.exe を確認する
rem                    restore : MSBuild に /restore を付ける (SDK 形式の .NET プロジェクト用。Clean では付けない)
rem                    cpp を含めないと、C++ ツールのない VS (MSBuild だけ) でも動く (.NET のみのソリューション用)
rem
rem 終了コード:
rem    0 成功
rem    1 ビルド失敗 (MSBuild が 0 以外を返した)
rem    2 引数が不正、または target が見つからない
rem   10 vswhere.exe が見つからない
rem   11 必要な構成要素 (cpp なら C++ ツール、そうでなければ MSBuild) 入りの Visual Studio が見つからない
rem   12 VsDevCmd.bat が見つからない
rem   13 VsDevCmd.bat の実行に失敗した
rem   14 VsDevCmd の後に、MSBuild.exe (cpp なら cl.exe も) が PATH にない
rem
rem 画面に出すメッセージ (echo) は、文字化けを避けるため、英語 (ASCII) のままにしてある。
rem このファイルの文字コードは CP932 (Shift_JIS)、改行は CRLF。
rem ============================================================
rem setlocal: 以降の変数の変更や、VsDevCmd が設定する環境変数を、このバッチの中だけに閉じ込める。
setlocal EnableExtensions

rem --- 引数を変数に取り込む（引用符は外す）。第5引数まで ---
set "TARGET=%~1"
set "PLATFORM=%~2"
set "CONFIG=%~3"
set "MSTARGET=%~4"
set "LOGDIR=%~5"
set "FEATURES=%~6"

rem --- 必須の引数 (target、Platform) がなければ、使い方を表示して終了する。省略可能な引数には、既定値を入れる ---
if "%TARGET%"=="" goto usage
if "%PLATFORM%"=="" goto usage
if "%CONFIG%"=="" set "CONFIG=Debug"
if "%MSTARGET%"=="" set "MSTARGET=Build"
if "%FEATURES%"=="" set "FEATURES=cpp"
rem --- MSBuildTarget を正規化する。大文字小文字を区別せず、Build / Rebuild / Clean だけを許可する ---
set "MSNORM="
if /i "%MSTARGET%"=="Build"   set "MSNORM=Build"
if /i "%MSTARGET%"=="Rebuild" set "MSNORM=Rebuild"
if /i "%MSTARGET%"=="Clean"   set "MSNORM=Clean"
if not defined MSNORM (
    echo ERROR: unsupported MSBuildTarget: %MSTARGET%  ^(Build / Rebuild / Clean^)
    exit /b 2
)
set "MSTARGET=%MSNORM%"
rem --- Features を解釈する。cpp: C++ ツールを要求する。restore: NuGet の復元を付ける ---
set "NEEDCPP="
set "DORESTORE="
set "FEAT_LIST=,%FEATURES%,"
if /i not "%FEAT_LIST:,cpp,=%"=="%FEAT_LIST%" set "NEEDCPP=1"
if /i not "%FEAT_LIST:,restore,=%"=="%FEAT_LIST%" set "DORESTORE=1"
rem target が存在しなければ、終了コード 2 で終了する。
if not exist "%TARGET%" (
    echo ERROR: target not found: %TARGET%
    exit /b 2
)

rem --- Platform を、VsDevCmd の -arch の値と、MSBuild の Platform の値に変換する ---
rem x86 は、MSBuild では Win32 と呼ぶ。
rem VCARCH: VsDevCmd に渡す値。MSPLATFORM: MSBuild に渡す値。
set "VCARCH="
set "MSPLATFORM="
if /i "%PLATFORM%"=="x64"   set "VCARCH=x64"   & set "MSPLATFORM=x64"
if /i "%PLATFORM%"=="Win32" set "VCARCH=x86"   & set "MSPLATFORM=Win32"
if /i "%PLATFORM%"=="x86"   set "VCARCH=x86"   & set "MSPLATFORM=Win32"
if /i "%PLATFORM%"=="ARM64" set "VCARCH=arm64" & set "MSPLATFORM=ARM64"
rem AnyCPU は .NET 用。VsDevCmd は x64 で読み込み、MSBuild には Any CPU と渡す。
if /i "%PLATFORM%"=="AnyCPU"   set "VCARCH=x64" & set "MSPLATFORM=Any CPU"
if /i "%PLATFORM%"=="Any CPU"  set "VCARCH=x64" & set "MSPLATFORM=Any CPU"
if not defined VCARCH (
    echo ERROR: unsupported platform: %PLATFORM%  ^(x64 / Win32 / x86 / ARM64 / AnyCPU^)
    exit /b 2
)

rem --- ログの出力先を決める。省略時は、target と同じフォルダの .claude-logs。なければ作成する ---
for %%I in ("%TARGET%") do set "TARGET_DIR=%%~dpI"
if "%LOGDIR%"=="" set "LOGDIR=%TARGET_DIR%.claude-logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

rem --- vswhere.exe の場所を探す。Program Files (x86) 側を先に、なければ通常の Program Files 側 ---
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" set "VSWHERE=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERROR: vswhere.exe not found. Install Visual Studio.
    exit /b 10
)

rem --- 必要な構成要素を持つ、最新のリリース版 VS を検索する条件を作る ---
rem cpp なら C++ の x86/x64 ツール、そうでなければ MSBuild だけを要求する。
rem プレビュー版は、対象にしない（vswhere に -prerelease を付けない）。
set "VSQUERY=-latest -products * -requires Microsoft.Component.MSBuild"
if defined NEEDCPP set "VSQUERY=-latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64"

rem --- 検出した VS のインストール先、名前、バージョンを取得して表示する ---
set "VSINSTALL="
set "VSNAME="
set "VSVER="
for /f "usebackq tokens=* delims=" %%I in (`"%VSWHERE%" %VSQUERY% -property installationPath`) do set "VSINSTALL=%%I"
if not defined VSINSTALL (
    if defined NEEDCPP (
        echo ERROR: no Visual Studio with C++ x86/x64 tools found.
        echo ERROR: Open Visual Studio Installer, choose Modify, and add the workload "Desktop development with C++". It cannot be added automatically. Then run again.
    ) else (
        echo ERROR: no Visual Studio with MSBuild found.
        echo ERROR: Install Visual Studio ^(or Build Tools^) with Visual Studio Installer, including the ".NET desktop development" workload. Then run again.
    )
    exit /b 11
)
for /f "usebackq tokens=* delims=" %%I in (`"%VSWHERE%" %VSQUERY% -property displayName`) do set "VSNAME=%%I"
for /f "usebackq tokens=* delims=" %%I in (`"%VSWHERE%" %VSQUERY% -property installationVersion`) do set "VSVER=%%I"

echo [VS] name    : %VSNAME%
echo [VS] version : %VSVER%
echo [VS] path    : %VSINSTALL%

rem --- VC の環境 (PATH、INCLUDE、LIB など) を読み込む ---
rem VsDevCmd.bat を呼ぶと、この後のコマンドから cl.exe や MSBuild.exe が使えるようになる。
set "VSDEVCMD=%VSINSTALL%\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEVCMD%" (
    echo ERROR: VsDevCmd.bat not found: %VSDEVCMD%
    exit /b 12
)
call "%VSDEVCMD%" -no_logo -arch=%VCARCH% -host_arch=x64 >nul
if errorlevel 1 (
    echo ERROR: VsDevCmd.bat failed ^(-arch=%VCARCH%^)
    exit /b 13
)
rem --- 環境が正しく読み込まれたかを、MSBuild.exe (cpp なら cl.exe も) が見つかるかで確認する ---
if defined NEEDCPP (
    where cl.exe >nul 2>&1
    if errorlevel 1 (
        echo ERROR: cl.exe not on PATH after VsDevCmd.
        exit /b 14
    )
)
where MSBuild.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: MSBuild.exe not on PATH after VsDevCmd.
    exit /b 14
)
rem 使用する MSBuild.exe の場所を表示する（最初の1件だけ）。
for /f "usebackq delims=" %%I in (`where MSBuild.exe`) do (
    echo [MSBuild] %%I
    goto :build
)

:build
rem --- MSBuild を実行する ---
rem   /m          : 並列ビルド
rem   /t          : 実行するターゲット (Build / Rebuild / Clean)
rem   /p          : 構成 (Configuration) とプラットフォーム (Platform)
rem   /fl1 /fl2 /fl3 : ファイルロガー。それぞれ、次のログを UTF-8 で出力する。
rem        build.log (詳細)、errors.log (エラーのみ)、warnings.log (警告のみ)
echo [BUILD] target=%TARGET%
echo [BUILD] Configuration=%CONFIG% Platform=%MSPLATFORM% MSBuildTarget=%MSTARGET%
echo [BUILD] logs=%LOGDIR%
echo [BUILD] features=%FEATURES%

rem /restore は、SDK 形式のプロジェクトの、NuGet 復元。Clean では不要。
set "RESTORE_OPT="
if defined DORESTORE if /i not "%MSTARGET%"=="Clean" set "RESTORE_OPT=/restore"

chcp 65001 >nul
MSBuild.exe "%TARGET%" /nologo /m %RESTORE_OPT% /t:%MSTARGET% /p:Configuration=%CONFIG% "/p:Platform=%MSPLATFORM%" /verbosity:minimal /fl1 "/flp1:logfile=%LOGDIR%\build.log;verbosity=normal;encoding=UTF-8" /fl2 "/flp2:logfile=%LOGDIR%\errors.log;errorsonly;encoding=UTF-8" /fl3 "/flp3:logfile=%LOGDIR%\warnings.log;warningsonly;encoding=UTF-8"
set "RC=%ERRORLEVEL%"
chcp 932 >nul
rem MSBuild の終了コードを保存する。0 以外ならビルド失敗として、このバッチは終了コード 1 で終わる。
echo [BUILD] MSBuild exit code: %RC%
if not "%RC%"=="0" exit /b 1
exit /b 0

rem --- 引数が足りないときの使い方の表示（終了コード 2） ---
:usage
echo Usage: %~nx0 ^<target.sln^|.slnx^|.vcxproj^|.csproj^> ^<Platform^> [Configuration] [MSBuildTarget] [LogDir] [Features]
exit /b 2
