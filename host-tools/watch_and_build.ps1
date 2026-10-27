<#
.SYNOPSIS
  フラグファイルを監視し、build-windows.cmd でビルド (必要ならテストも) して結果を通知ファイルに書く。
  ソリューションの中身 (C++ の .vcxproj / .NET の .csproj) を見て、ビルドとテストの方法を決める (C++ のみ / .NET のみ / 混在)。

.DESCRIPTION
  VS 検出・環境読み込み・MSBuild 実行は build-windows.cmd が担当する。
  このスクリプトは次を行う:

  [ビルドのみ]  <TargetDir>\trigger_build.flag
    - 失敗時のみ <TargetDir>\build_error.log を作成 (Claude Code が読む)
    - ビルド終了時に <TargetDir>\build_result.txt へ SUCCESS / FAILED を書く (完了マーカー)
      build_error.log を書いたあとに作るので、マーカーが現れた時点でログは読める状態

  [ビルド + テスト]  <TargetDir>\trigger_test.flag
    - 上記と同じビルドを行い (build_result.txt も書く)、成功したらテストを実行する:
        C++  : GoogleTest の exe (--gtest_output=xml で、機械可読な結果も .claude-logs\test-results\ に残す)
        .NET : テストプロジェクト (MSTest など) を dotnet test --no-build で実行する (trx を、同じ場所に残す)
      どちらか一方だけの場合も、両方ある場合も、結果は 1 つの test_result.txt にまとまる
    - 完了マーカーは <TargetDir>\test_result.txt (最後に書く):
        PASSED       全テスト成功
        FAILED       テスト失敗 (または異常終了)。詳細は test_error.log
        TIMEOUT      テストが制限時間内に終わらない。test_error.log に対象 exe
        BUILD_FAILED ビルド失敗のためテスト未実行。詳細は build_error.log
        ENV_ERROR    テスト exe が見つからない等。test_error.log 先頭が [ENVIRONMENT ERROR ...]
    - GoogleTest の exe は <ソリューションフォルダ>\<x64|Win32|ARM64>\<Configuration>\ から、
      名前が -TestExePattern に一致するものを実行する
    - .NET のテストプロジェクトは、ソリューションの .csproj / .vbproj / .fsproj のうち、Microsoft.NET.Test.Sdk
      (または MSTest) を参照するもの、IsTestProject が true のもの、名前が Test / Tests で終わるもの

  [ビルド + UI テスト]  <TargetDir>\trigger_uitest.flag
    - ビルドのあと、**UI テストのプロジェクトだけ**を、dotnet test で実行する (FlaUI など)。結果のファイルは、trigger_test.flag と同じ
      (test_result.txt (最後に書く) / test_error.log / test.log / .claude-logs\test-results\*.trx)。
    - UI テストのプロジェクト: 名前が UITests / UiTests で終わる、または FlaUI.* を参照しているもの。
      **通常のテスト (trigger_test.flag) からは、除かれる** (UI テストは、遅く、デスクトップを占有するため)。
    - テストには、環境変数で、実行環境を渡す: UITEST_SOLUTION_DIR / UITEST_CONFIGURATION / UITEST_PLATFORM / UITEST_SCREENSHOT_DIR / UITEST_SLOWMO_MS
      (<LogDir>\ui-screenshots。失敗時のスクリーンショット (PNG) の保存先。WSL の Claude が、画像として読める)。
    - 実行の前後に、ソリューションのフォルダの下の exe のプロセス (テストが残したアプリ) を終了する (残ると、次のビルドが、exe のロックで失敗する)。
    - 制限時間は、テストプロジェクトごとに -UiTestTimeoutSec (既定 600)。
    - 実行中は、マウス・キーボードに触らない。画面のロック、RDP の切断・最小化も避ける (UIA が動かなくなる)。

  [GoogleTest のソース取得]  <TargetDir>\trigger_gtest.flag  (ビルド・テストとは独立)
    - GitHub から GoogleTest (固定タグ) を取得して、<TargetDir>\ThirdParty\googletest\ (include\, src\, LICENSE, VERSION.txt) に置く。
      git があれば git clone --depth 1、なければ zip のダウンロード (Windows 側が、GitHub に届く必要がある)。
    - フラグの 1 行目に、タグを書ける (例: v1.17.0)。空なら -GtestTag (既定 v1.17.0)。
      許可する形: v1.17.0 / release-1.12.1 (英数字だけの、決まった形。コマンドへ渡るため)
    - 同じタグが、すでに置かれていれば、何もせずに OK (冪等)
    - 完了マーカーは <TargetDir>\gtest_result.txt (最後に書く): OK / FAILED (詳細は gtest_error.log。環境の問題として扱う)
    - ソリューションに含める静的ライブラリ (gtest.vcxproj) は、Claude 側が作る。ここは、取得だけ

  [パッケージの操作]  <TargetDir>\trigger_package.flag  (ビルド・テストとは独立。WSL からは、NuGet も vcpkg も実行できないため)
    - フラグの各行が、1 つの操作 (空行と # 行は無視)。上から順に実行し、最初の失敗で止まる。許可する形 (引数は、決まった文字だけ):
        nuget search <語>                          NuGet の検索 (nuget.org。ダウンロード数・発行元の確認済みも出す)
        nuget versions <ID>                        バージョンの一覧 (nuget.org)
        nuget add <プロジェクト> <ID> [<バージョン>]  dotnet add package。プロジェクトは、ソリューション内の .csproj / .vbproj / .fsproj
        nuget remove <プロジェクト> <ID>           dotnet remove package
        vcpkg search <語>                          vcpkg search
        vcpkg baseline                             vcpkg x-update-baseline --add-initial-baseline (vcpkg.json の builtin-baseline)
        vcpkg install                              vcpkg install (マニフェストモード。トリプレットは Platform から決める)
        fetch <owner/repo> <タグ> <名前> [<サブフォルダ>]   GitHub のタグのソースを、ThirdParty\<名前>\ に置く (ヘッダーのみのライブラリなど)
    - 結果は <TargetDir>\package_output.txt (各操作の出力)、失敗時のみ package_error.log、
      完了マーカー <TargetDir>\package_result.txt (OK / FAILED。最後に書く)
    - 環境の問題 (ネットワーク・vcpkg / dotnet が見つからない) の失敗は、package_error.log の先頭が [ENVIRONMENT ERROR ...]

  ソリューション (.sln / .slnx):
    - -SolutionPath を省略すると、<TargetDir> の .slnx、なければ .sln を、**トリガーが来るたびに**探す。
      そのため、**ソリューションができる前に、ウォッチャーを起動しておける** (new_solution.py で作ってから、ビルドのトリガーを置けばよい)。
    - トリガーが来たときに、ソリューションがなければ、ビルドせずに、build_result.txt = FAILED、build_error.log の先頭が
      [ENVIRONMENT ERROR ...] と "ERROR: no .sln / .slnx found in ..." (テストのトリガーのときは、test_result.txt = BUILD_FAILED) を書く。
    - -SolutionPath を明示したときは、それを使う (起動時に、存在しなければ、終了コード 2)。

  このスクリプトの終了コード:
    2 引数不正 (-SolutionPath を明示したのに見つからない、build-windows.cmd が見つからない)
    3 同じプロジェクトフォルダで、すでに別のウォッチャーが動いている (二重起動の拒否)

  build-windows.cmd の終了コード:
    0 成功 / 1 ビルド失敗 / 2 引数不正 / 10 vswhere なし / 11 VS(C++)なし
    12 VsDevCmd なし / 13 VsDevCmd 失敗 / 14 cl.exe or MSBuild.exe が PATH にない
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$TargetDir,

    # 省略時: <TargetDir> の .slnx、なければ .sln を、自動で探す。**ソリューションが、まだなくても、起動できる**
    # (トリガーが来たときに、探す。new_solution.py で作る前に、ウォッチャーを起動しておける)
    [string]$SolutionPath,

    # auto: C++ のプロジェクトがあれば x64、.NET だけなら AnyCPU
    [ValidateSet("auto","x64","Win32","x86","ARM64","AnyCPU")]
    [string]$Platform = "auto",

    [string]$Configuration = "Debug",

    [ValidateSet("Build","Rebuild","Clean")]
    [string]$MSBuildTarget = "Build",

    [string]$LogDir,

    # 省略時: このスクリプトと同じフォルダの build-windows.cmd
    [string]$BuildScript,

    # テスト exe の名前 (正規表現、大文字小文字無視)
    [string]$TestExePattern = '(Test|Tests)\.exe$',

    # テスト exe に渡す引数
    [string]$TestArgs = "--gtest_color=no",

    # テスト1本あたりの制限時間 (秒)
    [int]$TestTimeoutSec = 120,

    # UI テスト (trigger_uitest.flag) の、テストプロジェクト 1 つあたりの制限時間 (秒)。アプリの起動と操作を含むので、通常のテストより長い。
    # 省略時: 環境変数 WATCH_UI_TIMEOUT_SEC、なければ 600。UI テストが多いプロジェクト (ダイアログの調査など) で、600 秒を超えて強制終了されるときに、長くする (例: set WATCH_UI_TIMEOUT_SEC=1800)。
    [int]$UiTestTimeoutSec = $(if ($env:WATCH_UI_TIMEOUT_SEC) { [int]$env:WATCH_UI_TIMEOUT_SEC } else { 600 }),

    # UI テストを実行するデスクトップ。省略時: 環境変数 WATCH_UI_DESKTOP、なければ auto。
    # **1 回ごとの指定が、これより優先される:** trigger_uitest.flag の中身に `desktop=visible` / `desktop=separate` と書く (uitest_once.sh --visible / --separate)。
    # auto:     UI テストのプロジェクトの uitest.settings (desktop=visible|separate) に従う。ファイルがなければ、別のデスクトップ (separate)。
    #           (フレームワークごとの違い (WPF のメニューは、別のデスクトップで開かない、など) は、このファイルが持つ。add_ui_tests.py が、WPF には visible を書く。)
    # separate: 別のデスクトップ (Win32 の CreateDesktop)。ユーザーの画面に、ウィンドウが出ず、フォーカスも奪わない。
    #           テストが起動して残ったアプリは、ジョブオブジェクトで、すべて終了する。UI テストの間だけ、WPF をソフトウェアレンダリングにする。
    # default:  ユーザーのデスクトップ (ウィンドウが見え、フォーカスを奪うことがある)。visible は、default の別名。invisible は、separate の別名 (WPF でも、別のデスクトップにしたいとき)。
    [ValidateSet("auto","default","visible","separate","invisible")]
    [string]$UiTestDesktop = $(if ($env:WATCH_UI_DESKTOP) { $env:WATCH_UI_DESKTOP } else { "auto" }),

    # UI テストの、操作の間隔 (ミリ秒)。0 より大きいと、テストは、要素を探すたびに、その時間だけ待ち、最後の状態も 2 倍の時間だけ見せる。
    # ユーザーのデスクトップ (-UiTestDesktop default) で、操作の様子を、目で確かめるときに使う (例: 800)。省略時: 環境変数 WATCH_UI_SLOWMO_MS、なければ 0。
    [int]$UiTestSlowMoMs = $(if ($env:WATCH_UI_SLOWMO_MS) { [int]$env:WATCH_UI_SLOWMO_MS } else { 0 }),

    # テスト実行時の作業フォルダ。省略時は exe のあるフォルダ
    [string]$TestWorkingDir,

    # trigger_gtest.flag の 1 行目が空のときに取得する、GoogleTest のタグ
    [string]$GtestTag = "v1.17.0",

    # dotnet test に追加で渡す引数。例: -DotnetTestArgs:-p:Platform=x64 (プロジェクトの出力先が、プラットフォーム別のとき。値が - で始まるので、コロンで結ぶ)
    [string]$DotnetTestArgs = "",

    # dotnet の実行ファイル (PATH にないときは、フルパス)
    [string]$DotnetExe = "dotnet",

    # パッケージの操作 1 件あたりの制限時間 (秒)。vcpkg install は、ポートをビルドするので、長い
    [int]$PackageTimeoutSec = 1800,

    # vcpkg.exe。省略時: 環境変数 VCPKG_ROOT、なければ、Visual Studio 同梱 (VC\vcpkg\vcpkg.exe)
    [string]$VcpkgExe,

    # vcpkg のトリプレット。省略時: Platform から決める (x64-windows-static-md / x86-windows-static-md / arm64-windows-static-md)
    [string]$VcpkgTriplet
)

$ErrorActionPreference = "Stop"

# 環境変数 Platform を、子プロセスに渡さない。
# MSBuild は、環境変数を、プロパティとして読む。run_watcher.cmd (以前の版) が、cmd の変数 PLATFORM = auto を作ると、環境変数 Platform になり、
# dotnet test --no-build が、プロジェクトを Platform=auto で評価して、出力先を bin\auto\Debug と誤解し、テストの DLL を見つけられなかった。
# (ビルドは、/p:Platform を、明示するので、影響を受けなかった)
Remove-Item Env:\Platform -ErrorAction SilentlyContinue

# .NET の SDK / ビルドツールがない環境 (例: C++ のワークロードだけの Visual Studio) で、.NET のビルド・テストを求められたときの案内。
# 自動では追加できないので、利用者に、手で追加してもらう。
$DotnetInstallHint = "ERROR: The .NET SDK is missing or too old. Open Visual Studio Installer, choose Modify, and add the workload `".NET desktop development`" (or install the .NET SDK from https://dotnet.microsoft.com/download). It cannot be added automatically. Then run again."

# プロキシの環境変数 (HTTPS_PROXY / HTTP_PROXY) を、PowerShell の Web 要求 (nuget search / versions、fetch の zip の取得) にも、適用する。
# dotnet / NuGet / git は、環境変数を見るが、PowerShell 5.1 の Invoke-RestMethod は、システムのプロキシ設定だけを見るため、
# 環境変数でプロキシを指定しても、nuget search / versions だけが、プロキシを通らなかった (P6 の実機で発見)。
$proxyUrl = @($env:HTTPS_PROXY, $env:https_proxy, $env:HTTP_PROXY, $env:http_proxy) | Where-Object { $_ } | Select-Object -First 1
if ($proxyUrl) {
    try { [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($proxyUrl, $true) } catch { }
}

# build-windows.cmd が MSBuild 呼び出しの前後だけ chcp 65001 にするため、
# パイプで受け取るネイティブプロセスの出力も UTF-8 として解釈する (PS 5.1)。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# param 内の既定値では $PSScriptRoot が空になる環境があるため、ここで解決する
if (-not $BuildScript) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $BuildScript = Join-Path $scriptDir "build-windows.cmd"
}

# ---------- パス解決 ----------
$TargetDir = [System.IO.Path]::GetFullPath($TargetDir).TrimEnd('\')
# -SolutionPath を明示したときは、それを使う (なければ、起動を拒否する)。省略したときは、トリガーのたびに、<TargetDir> から探す
$SolutionExplicit = [bool]$SolutionPath
if ($SolutionExplicit) {
    if (-not [System.IO.Path]::IsPathRooted($SolutionPath)) {
        $SolutionPath = Join-Path $TargetDir $SolutionPath
    }
    if (-not (Test-Path -LiteralPath $SolutionPath)) {
        Write-Host "ERROR: target not found: $SolutionPath" -ForegroundColor Red
        exit 2
    }
}
if (-not (Test-Path -LiteralPath $BuildScript)) {
    Write-Host "ERROR: build script not found: $BuildScript" -ForegroundColor Red
    exit 2
}
if (-not $LogDir) { $LogDir = Join-Path $TargetDir ".claude-logs" }
$LogDir = $LogDir.TrimEnd('\')

# ---------- ソリューションの中身の判定 ----------
# .sln / .slnx (または単独のプロジェクトファイル) から、プロジェクトのパスを集める。
function Get-SolutionProjectPaths {
    $ext = [System.IO.Path]::GetExtension($SolutionPath).ToLowerInvariant()
    if ($ext -match '^\.(vcxproj|csproj|vbproj|fsproj)$') { return @($SolutionPath) }
    $text = ""
    try { $text = [System.IO.File]::ReadAllText($SolutionPath) } catch { return @() }
    if ($ext -eq ".slnx") {
        $pattern = 'Path="([^"]+\.(?:vcxproj|csproj|vbproj|fsproj))"'
    } else {
        $pattern = 'Project\("\{[^}]+\}"\)\s*=\s*"[^"]*"\s*,\s*"([^"]+\.(?:vcxproj|csproj|vbproj|fsproj))"'
    }
    $paths = @()
    foreach ($m in [regex]::Matches($text, $pattern, 'IgnoreCase')) {
        $rel = $m.Groups[1].Value.Replace('/', '\')
        $full = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $SolutionDir $rel }
        $paths += [System.IO.Path]::GetFullPath($full)
    }
    return @($paths | Select-Object -Unique)
}

# 指定された Platform (auto を含む)。ソリューションを読み直すたびに、ここから Platform を決め直す
$PlatformSetting = $Platform

# <TargetDir> の .slnx、なければ .sln を探して、フルパスを返す (なければ $null)。
# *.sln のワイルドカードは、8.3 形式の短い名前の仕様により、.slnx にも一致することがある。そのため、拡張子を厳密に確認する。
function Find-SolutionFile {
    foreach ($ext in @(".slnx", ".sln")) {
        $found = @(Get-ChildItem -LiteralPath $TargetDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ieq $ext } | Sort-Object Name | Select-Object -First 1)
        if ($found.Count -gt 0) { return $found[0].FullName }
    }
    return $null
}

# ソリューションの状態 (パス・プロジェクトの一覧・C++ / .NET の判定・Platform・ビルドの機能) を、決め直す。
# 起動時と、トリガーが来るたびに呼ぶ (起動後に、ソリューションができた・プロジェクトが増えた (テストの後付けなど) 場合に備える)。
# ソリューションがなければ、$SolutionPath は $null になる (ビルドのトリガーは、環境エラーとして返す)。
function Update-SolutionState {
    if (-not $SolutionExplicit) { $script:SolutionPath = Find-SolutionFile }
    if ($script:SolutionPath -and (Test-Path -LiteralPath $script:SolutionPath)) {
        $script:SolutionDir = Split-Path -Parent $script:SolutionPath
        $script:ProjectPaths = @(Get-SolutionProjectPaths)
    } else {
        $script:SolutionPath = $null
        $script:SolutionDir = $TargetDir
        $script:ProjectPaths = @()
    }
    $script:HasCpp    = @($script:ProjectPaths | Where-Object { $_ -match '\.vcxproj$' }).Count -gt 0
    $script:HasDotnet = @($script:ProjectPaths | Where-Object { $_ -match '\.(csproj|vbproj|fsproj)$' }).Count -gt 0
    if (-not $script:SolutionPath) {
        $script:Platform = $PlatformSetting
    } elseif ($PlatformSetting -eq "auto") {
        $script:Platform = if ($script:HasDotnet -and -not $script:HasCpp) { "AnyCPU" } else { "x64" }
    } else {
        $script:Platform = $PlatformSetting
    }
    # build-windows.cmd の第 6 引数。cpp: C++ ツール入りの VS を要求する / restore: NuGet の復元 (/restore) をする。
    # 中身を判定できなかったときは、従来どおり cpp。
    $features = @()
    if ($script:HasCpp -or -not $script:HasDotnet) { $features += "cpp" }
    if ($script:HasDotnet) { $features += "restore" }
    $script:BuildFeatures = $features -join ","
    $script:SolutionKind = if (-not $script:SolutionPath) { "(no .sln / .slnx yet)" } elseif ($script:HasCpp -and $script:HasDotnet) { "C++ + .NET" } elseif ($script:HasDotnet) { ".NET" } elseif ($script:HasCpp) { "C++" } else { "unknown (treated as C++)" }
}
Update-SolutionState

# dotnet の初回の案内文やテレメトリの確認で、出力が乱れるのを避ける
$env:DOTNET_NOLOGO = "1"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"

# ---------- 二重起動の防止 ----------
# 同じプロジェクトフォルダで、ウォッチャーが2つ動くと、同じフラグを奪い合い、結果が混ざる。
# 名前付きミューテックスで、先に起動したものだけを残す。プロセスが終了すれば、自動で解放される
# (ロックファイルと違い、異常終了しても、古いロックが残らない)。
$sha1 = [System.Security.Cryptography.SHA1]::Create()
$pathHash = (($sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($TargetDir.ToLowerInvariant())) |
    ForEach-Object { $_.ToString("x2") }) -join "")
$createdNew = $false
$WatcherMutex = New-Object System.Threading.Mutex($true, "Local\cpp-claude-build-tools-watcher-$pathHash", [ref]$createdNew)
if (-not $createdNew) {
    Write-Host "ERROR: a watcher is already running for this folder: $TargetDir" -ForegroundColor Red
    Write-Host "       Use that window, or close it first." -ForegroundColor Red
    exit 3
}

$TriggerFile     = Join-Path $TargetDir "trigger_build.flag"
$TestTriggerFile = Join-Path $TargetDir "trigger_test.flag"
$UiTestTriggerFile = Join-Path $TargetDir "trigger_uitest.flag"
if ($UiTestDesktop -eq "visible") { $UiTestDesktop = "default" }
if ($UiTestDesktop -eq "invisible") { $UiTestDesktop = "separate" }
$ResultFile      = Join-Path $TargetDir "build_result.txt"
$ErrorLog        = Join-Path $TargetDir "build_error.log"
$TestResultFile  = Join-Path $TargetDir "test_result.txt"
$TestErrorLog    = Join-Path $TargetDir "test_error.log"
$BuildLog        = Join-Path $LogDir "build.log"
$ErrorsOnly      = Join-Path $LogDir "errors.log"
$WarnsOnly       = Join-Path $LogDir "warnings.log"
$TestLog         = Join-Path $LogDir "test.log"
$TestResultsDir  = Join-Path $LogDir "test-results"
$UiScreenshotDir = Join-Path $LogDir "ui-screenshots"
$GtestTriggerFile = Join-Path $TargetDir "trigger_gtest.flag"
$GtestResultFile  = Join-Path $TargetDir "gtest_result.txt"
$GtestErrorLog    = Join-Path $TargetDir "gtest_error.log"
$GtestRepoUrl     = "https://github.com/google/googletest"
$PackageTriggerFile = Join-Path $TargetDir "trigger_package.flag"
$PackageResultFile  = Join-Path $TargetDir "package_result.txt"
$PackageErrorLog    = Join-Path $TargetDir "package_error.log"
$PackageOutputFile  = Join-Path $TargetDir "package_output.txt"
$PackageLog         = Join-Path $LogDir "package.log"

# ---------- GoogleTest のソース取得 (trigger_gtest.flag) ----------
function Write-GtestMarker($value) {
    try {
        [System.IO.File]::WriteAllText($GtestResultFile, $value)
        Write-Host "[MARKER] $value -> $GtestResultFile" -ForegroundColor DarkGray
    } catch {
        Write-Host "[MARKER] FAILED to write $GtestResultFile : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 失敗を記録する。gtest_error.log を書いたあとに、完了マーカー (FAILED) を書く。
function Write-GtestFailure([string[]]$lines) {
    Write-Host "[GTEST] FAILED" -ForegroundColor Red
    $lines | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    (@("[ENVIRONMENT ERROR - not a source code problem]") + @($lines)) | Out-File $GtestErrorLog -Encoding utf8
    Write-GtestMarker "FAILED"
}

# 取得して <TargetDir>\ThirdParty\googletest に置く。成功したら OK、失敗したら FAILED をマーカーに書く。
function Invoke-GtestFetch([string]$tagLine) {
    $tag = "$tagLine".Trim()
    if (-not $tag) { $tag = $GtestTag }
    # タグは、コマンドの引数や URL に渡るので、決まった形だけを許可する
    if ($tag -notmatch '^(v|release-)\d+\.\d+(\.\d+)?$') {
        Write-GtestFailure @("ERROR: invalid GoogleTest tag: '$tag' (allowed: v1.17.0 / release-1.12.1)")
        return
    }
    $dest    = Join-Path $TargetDir "ThirdParty\googletest"
    $verFile = Join-Path $dest "VERSION.txt"
    $headerP = Join-Path $dest "include\gtest\gtest.h"
    # すでに同じタグが置かれていれば、取得しない (冪等)。判定の材料は、毎回、表示する (実機での原因調べのため)。
    $haveHeader = Test-Path -LiteralPath $headerP
    $haveVer = "<none>"
    if (Test-Path -LiteralPath $verFile) {
        $haveVer = ("" + (Get-Content -LiteralPath $verFile -Raw)).Trim([char]0xFEFF, [char]32, [char]9, [char]13, [char]10)
    }
    Write-Host "[GTEST] check: wanted='$tag' / VERSION.txt='$haveVer' / gtest.h exists=$haveHeader" -ForegroundColor DarkGray
    if ($haveHeader -and ($haveVer -ieq $tag)) {
        Write-Host "[GTEST] $tag is already in $dest" -ForegroundColor Green
        Write-GtestMarker "OK"
        return
    }

    Write-Host "[GTEST] Fetching GoogleTest $tag ..." -ForegroundColor Yellow
    $tmp = Join-Path $LogDir "gtest_tmp"
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $log = @()
    $src = $null

    # PS 5.1 は Stop 下でネイティブの stderr を例外にするため、ここでは Continue にする
    $ErrorActionPreference = "Continue"
    try {
        # 1. git
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $cloneDir = Join-Path $tmp "clone"
            $out = & git clone --depth 1 --branch $tag "$GtestRepoUrl.git" $cloneDir 2>&1
            $code = $LASTEXITCODE
            $log += @($out | ForEach-Object { "$_" })
            if ($code -eq 0 -and (Test-Path -LiteralPath (Join-Path $cloneDir "googletest\include\gtest\gtest.h"))) {
                $src = Join-Path $cloneDir "googletest"
            } else {
                $log += "git clone failed (exit code $code). Trying the zip download."
            }
        } else {
            $log += "git was not found. Using the zip download."
        }
        # 2. zip
        if (-not $src) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $zip = Join-Path $tmp "googletest.zip"
                Invoke-WebRequest -Uri "$GtestRepoUrl/archive/refs/tags/$tag.zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
                Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp "zip") -Force -ErrorAction Stop
                $root = Get-ChildItem -LiteralPath (Join-Path $tmp "zip") -Directory | Select-Object -First 1
                if ($root -and (Test-Path -LiteralPath (Join-Path $root.FullName "googletest\include\gtest\gtest.h"))) {
                    $src = Join-Path $root.FullName "googletest"
                } else {
                    $log += "The zip was downloaded, but googletest\include\gtest\gtest.h was not found in it."
                }
            } catch {
                $log += "zip download failed: $($_.Exception.Message)"
            }
        }
    } finally {
        $ErrorActionPreference = "Stop"
    }

    if (-not $src) {
        Write-GtestFailure (@("ERROR: could not get GoogleTest $tag from $GtestRepoUrl (check the network / proxy / the tag name).") + $log)
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
    foreach ($need in @("include\gtest\gtest.h", "src\gtest-all.cc", "src\gtest_main.cc")) {
        if (-not (Test-Path -LiteralPath (Join-Path $src $need))) {
            Write-GtestFailure @("ERROR: the fetched GoogleTest has no googletest\$need (unexpected layout).")
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            return
        }
    }

    # include / src / LICENSE だけを置く (サイズを小さく。ビルドに要るものだけ)
    Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $src "include") -Destination $dest -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $src "src") -Destination $dest -Recurse -Force
    $license = Join-Path (Split-Path $src -Parent) "LICENSE"
    if (Test-Path -LiteralPath $license) { Copy-Item -LiteralPath $license -Destination $dest -Force }
    [System.IO.File]::WriteAllText($verFile, $tag)
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "[GTEST] GoogleTest $tag -> $dest" -ForegroundColor Green
    Write-GtestMarker "OK"
}

# ---------- パッケージの操作 (trigger_package.flag) ----------
# NuGet / vcpkg / GitHub のソース取得を、Windows 側で実行する。引数は、コマンドに渡るので、決まった形だけを許可する。
# 各操作の戻り値: @{ Ok = bool; Env = bool (環境の問題); Lines = string[] }
$PackageMaxLines = 60
$RePkgId      = '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'
$RePkgVersion = '^[0-9][0-9A-Za-z.+-]{0,63}$'
$RePkgTerm    = '^[A-Za-z0-9][A-Za-z0-9._+-]{0,59}$'
$RePkgRepo    = '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'
$RePkgTag     = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
$RePkgName    = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

function Write-PackageMarker($value) {
    try {
        [System.IO.File]::WriteAllText($PackageResultFile, $value)
        Write-Host "[MARKER] $value -> $PackageResultFile" -ForegroundColor DarkGray
    } catch {
        Write-Host "[MARKER] FAILED to write $PackageResultFile : $($_.Exception.Message)" -ForegroundColor Red
    }
}

function New-PackageResult([bool]$ok, [bool]$envErr, [string[]]$lines) {
    return @{ Ok = $ok; Env = $envErr; Lines = @($lines) }
}

# ネットワーク・フィードに届かない、という種類の出力か (ソースの問題ではない)
function Test-PackageEnvOutput($lines) {
    return @($lines | Where-Object { "$_" -match 'NU1301|Unable to load the service index|No such host is known|could not be resolved|actively refused|timed out|Failed to download|unable to access|Could not resolve host|fatal: unable|拒否されたため、接続できません|そのようなホストは不明|リモート名を解決できません|サービス インデックスを読み込めません|タイムアウト|応答しなかった|HttpRequestException|SocketException' }).Count -gt 0
}

# ソリューション内の、プロジェクトファイル。外・存在しない・拡張子違いは $null
function Get-PackageProjectPath([string]$rel) {
    if ($rel -notmatch '^[A-Za-z0-9._/\\-]+\.(csproj|vbproj|fsproj)$') { return $null }
    if ($rel -match '(^|[/\\])\.\.([/\\]|$)') { return $null }
    $full = [System.IO.Path]::GetFullPath((Join-Path $SolutionDir ($rel -replace '/', '\')))
    if (-not $full.StartsWith($SolutionDir.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    if (-not (Test-Path -LiteralPath $full)) { return $null }
    return $full
}

# 追加した結果のバージョンを、.csproj (なければ、上位の Directory.Packages.props) から読む
function Get-PackageResolvedVersion([string]$proj, [string]$id) {
    try {
        $x = [xml](Get-Content -LiteralPath $proj -Raw -Encoding UTF8)
        foreach ($r in @($x.SelectNodes("//PackageReference"))) {
            if ("$($r.GetAttribute('Include'))" -ieq $id) {
                $v = "$($r.GetAttribute('Version'))"
                if ($v) { return $v }
                break
            }
        }
        $dir = Split-Path -Parent $proj
        while ($dir -and $dir.Length -ge $SolutionDir.TrimEnd('\').Length) {
            $props = Join-Path $dir "Directory.Packages.props"
            if (Test-Path -LiteralPath $props) {
                $px = [xml](Get-Content -LiteralPath $props -Raw -Encoding UTF8)
                foreach ($r in @($px.SelectNodes("//PackageVersion"))) {
                    if ("$($r.GetAttribute('Include'))" -ieq $id) { return "$($r.GetAttribute('Version')) (Directory.Packages.props)" }
                }
            }
            $dir = Split-Path -Parent $dir
        }
    } catch { }
    return "(unknown)"
}

function Invoke-NugetRest([string]$url) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    return Invoke-RestMethod -Uri $url -UseBasicParsing -ErrorAction Stop
}

# REST の例外を、(環境の問題か, メッセージ) にする。HTTP 404 は、パッケージがない (ソースの問題)。
function ConvertTo-PackageRestResult($err, [string]$what) {
    $resp = $err.Exception.Response
    if ($resp -and [int]$resp.StatusCode -eq 404) {
        return New-PackageResult $false $false @("$what : not found (HTTP 404). Check the spelling with 'nuget search'.")
    }
    return New-PackageResult $false $true @("$what : could not reach nuget.org: $($err.Exception.Message)")
}

function Find-Vcpkg {
    $cands = @()
    if ($VcpkgExe) { $cands += $VcpkgExe }
    if ($env:VCPKG_ROOT) { $cands += (Join-Path $env:VCPKG_ROOT "vcpkg.exe") }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        $inst = & $vswhere -latest -products * -property installationPath 2>$null
        if ($inst) { $cands += (Join-Path ("$inst".Trim()) "VC\vcpkg\vcpkg.exe") }
    }
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-VcpkgTripletName {
    if ($VcpkgTriplet) { return $VcpkgTriplet }
    switch ($Platform.ToLower()) {
        "arm64" { return "arm64-windows-static-md" }
        "win32" { return "x86-windows-static-md" }
        "x86"   { return "x86-windows-static-md" }
        default { return "x64-windows-static-md" }
    }
}

# GitHub のタグのソースを、<TargetDir>\ThirdParty\<名前>\ に置く (サブフォルダがあれば、その中身だけ)。同じ内容なら、何もしない。
function Invoke-PackageFetch([string]$repo, [string]$tag, [string]$name, [string]$sub) {
    if ($repo -notmatch $RePkgRepo -or $tag -notmatch $RePkgTag -or $name -notmatch $RePkgName) {
        return New-PackageResult $false $false @("ERROR: invalid fetch arguments (repo=$repo tag=$tag name=$name). Allowed: owner/repo, tag, name of letters, digits, . _ -")
    }
    if ($sub) {
        $segs = @($sub -split '[/\\]')
        if ($segs | Where-Object { $_ -notmatch '^[A-Za-z0-9._-]+$' -or $_ -eq '.' -or $_ -eq '..' }) {
            return New-PackageResult $false $false @("ERROR: invalid subfolder: $sub")
        }
    }
    $dest = Join-Path $TargetDir ("ThirdParty\" + $name)
    $verFile = Join-Path $dest "VERSION.txt"
    $stamp = "$repo@$tag" + $(if ($sub) { "#$sub" } else { "" })
    if (Test-Path -LiteralPath $verFile) {
        $have = ("" + (Get-Content -LiteralPath $verFile -Raw)).Trim([char]0xFEFF, [char]32, [char]9, [char]13, [char]10)
        if ($have -ieq $stamp) { return New-PackageResult $true $false @("already present: $dest ($stamp)") }
    }

    $tmp = Join-Path $LogDir "pkg_tmp"
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $log = @()
    $src = $null
    $ErrorActionPreference = "Continue"
    try {
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $cloneDir = Join-Path $tmp "clone"
            $out = & git clone --depth 1 --branch $tag "https://github.com/$repo.git" $cloneDir 2>&1
            $code = $LASTEXITCODE
            $log += @($out | ForEach-Object { "$_" })
            if ($code -eq 0 -and (Test-Path -LiteralPath $cloneDir)) { $src = $cloneDir } else { $log += "git clone failed (exit code $code). Trying the zip download." }
        } else {
            $log += "git was not found. Using the zip download."
        }
        if (-not $src) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $zip = Join-Path $tmp "src.zip"
                Invoke-WebRequest -Uri "https://github.com/$repo/archive/refs/tags/$tag.zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
                Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp "zip") -Force -ErrorAction Stop
                $root = Get-ChildItem -LiteralPath (Join-Path $tmp "zip") -Directory | Select-Object -First 1
                if ($root) { $src = $root.FullName }
            } catch {
                $log += "zip download failed: $($_.Exception.Message)"
            }
        }
    } finally {
        $ErrorActionPreference = "Stop"
    }
    if (-not $src) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return New-PackageResult $false $true (@("ERROR: could not get $repo@$tag from github.com (check the network / proxy / the repo and tag names).") + $log)
    }
    $from = $src
    if ($sub) {
        $from = Join-Path $src ($sub -replace '/', '\')
        if (-not (Test-Path -LiteralPath $from)) {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            return New-PackageResult $false $false @("ERROR: subfolder '$sub' was not found in $repo@$tag.")
        }
    }
    Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Get-ChildItem -LiteralPath $from -Force | Where-Object { $_.Name -ne ".git" } | Copy-Item -Destination $dest -Recurse -Force
    if ($sub) {
        # サブフォルダだけを置くときも、ライセンスは、残す
        Get-ChildItem -LiteralPath $src -File -Force | Where-Object { $_.Name -match '^(LICENSE|COPYING|NOTICE)' } | Copy-Item -Destination $dest -Force
    }
    [System.IO.File]::WriteAllText($verFile, $stamp)
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    return New-PackageResult $true $false @("fetched $stamp -> $dest")
}

# 1 件の操作を実行する
function Invoke-OnePackageOp([string]$op) {
    $t = @($op -split '\s+' | Where-Object { $_ })
    if ($t.Count -lt 1) { return New-PackageResult $false $false @("ERROR: empty operation") }

    if ($t[0] -eq "fetch") {
        if ($t.Count -lt 4 -or $t.Count -gt 5) { return New-PackageResult $false $false @("ERROR: usage: fetch <owner/repo> <tag> <name> [<subfolder>]") }
        return Invoke-PackageFetch $t[1] $t[2] $t[3] $(if ($t.Count -eq 5) { $t[4] } else { "" })
    }

    if ($t[0] -eq "nuget") {
        $verb = if ($t.Count -ge 2) { $t[1] } else { "" }
        if ($verb -eq "search") {
            if ($t.Count -ne 3 -or $t[2] -notmatch $RePkgTerm) { return New-PackageResult $false $false @("ERROR: usage: nuget search <term>  (term: letters, digits, . _ + -)") }
            try {
                $res = Invoke-NugetRest ("https://azuresearch-usnc.nuget.org/query?q=" + [uri]::EscapeDataString($t[2]) + "&take=10&prerelease=false&semVerLevel=2.0.0")
            } catch { return ConvertTo-PackageRestResult $_ "nuget search $($t[2])" }
            $lines = @($res.data | ForEach-Object { "{0} {1}  downloads={2}  verified={3}  authors={4}" -f $_.id, $_.version, $_.totalDownloads, $_.verified, (@($_.authors) -join ",") })
            if ($lines.Count -eq 0) { $lines = @("(no packages found for '$($t[2])')") }
            return New-PackageResult $true $false $lines
        }
        if ($verb -eq "versions") {
            if ($t.Count -ne 3 -or $t[2] -notmatch $RePkgId) { return New-PackageResult $false $false @("ERROR: usage: nuget versions <id>") }
            try {
                $res = Invoke-NugetRest ("https://api.nuget.org/v3-flatcontainer/" + $t[2].ToLowerInvariant() + "/index.json")
            } catch { return ConvertTo-PackageRestResult $_ "nuget versions $($t[2])" }
            $all = @($res.versions)
            $stable = @($all | Where-Object { $_ -notmatch '-' })
            $pre = @($all | Where-Object { $_ -match '-' })
            $lines = @("$($t[2]): $($all.Count) versions")
            $lines += "stable (newest last): " + (@($stable | Select-Object -Last 10) -join ", ")
            if ($pre.Count -gt 0) { $lines += "prerelease (newest last): " + (@($pre | Select-Object -Last 3) -join ", ") }
            return New-PackageResult $true $false $lines
        }
        if ($verb -eq "add" -or $verb -eq "remove") {
            $isAdd = $verb -eq "add"
            $okCount = if ($isAdd) { ($t.Count -eq 4 -or $t.Count -eq 5) } else { $t.Count -eq 4 }
            if (-not $okCount) { return New-PackageResult $false $false @("ERROR: usage: nuget add <project> <id> [<version>]  /  nuget remove <project> <id>") }
            $proj = Get-PackageProjectPath $t[2]
            if (-not $proj) { return New-PackageResult $false $false @("ERROR: project not found in the solution folder (must be a .csproj / .vbproj / .fsproj under it): $($t[2])") }
            if ($t[3] -notmatch $RePkgId) { return New-PackageResult $false $false @("ERROR: invalid package id: $($t[3])") }
            if ($isAdd -and $t.Count -eq 5 -and $t[4] -notmatch $RePkgVersion) { return New-PackageResult $false $false @("ERROR: invalid version: $($t[4])") }
            $cmd = Get-Command $DotnetExe -ErrorAction SilentlyContinue
            if (-not $cmd) { return New-PackageResult $false $true @("ERROR: '$DotnetExe' was not found. Install the .NET SDK, or pass -DotnetExe <full path>.", $DotnetInstallHint) }
            $argString = if ($isAdd) { 'add "' + $proj + '" package ' + $t[3] + $(if ($t.Count -eq 5) { " --version " + $t[4] } else { "" }) }
                         else { 'remove "' + $proj + '" package ' + $t[3] }
            $r = Invoke-TestProcess $cmd.Source $argString (Split-Path -Parent $proj) $PackageTimeoutSec
            $lines = @($r.Output | Where-Object { "$_".Trim() })
            if ($r.Timeout) { return New-PackageResult $false $true (@("ERROR: dotnet timed out after ${PackageTimeoutSec}s") + $lines) }
            if ($r.ExitCode -ne 0) { return New-PackageResult $false (Test-PackageEnvOutput $lines) $lines }
            if ($isAdd) { $lines = @("added $($t[3]) $(Get-PackageResolvedVersion $proj $t[3]) -> $($t[2])") + $lines }
            else { $lines = @("removed $($t[3]) from $($t[2])") + $lines }
            return New-PackageResult $true $false $lines
        }
        return New-PackageResult $false $false @("ERROR: unknown nuget operation: $op  (search / versions / add / remove)")
    }

    if ($t[0] -eq "vcpkg") {
        $verb = if ($t.Count -ge 2) { $t[1] } else { "" }
        if ($verb -notin @("search", "baseline", "install")) { return New-PackageResult $false $false @("ERROR: unknown vcpkg operation: $op  (search / baseline / install)") }
        $exe = Find-Vcpkg
        if (-not $exe) {
            return New-PackageResult $false $true @("ERROR: vcpkg.exe was not found. Install the 'vcpkg package manager' component of Visual Studio, set VCPKG_ROOT, or pass -VcpkgExe <full path>.")
        }
        $argString = ""
        if ($verb -eq "search") {
            if ($t.Count -ne 3 -or $t[2] -notmatch $RePkgTerm) { return New-PackageResult $false $false @("ERROR: usage: vcpkg search <term>") }
            $argString = "search " + $t[2]
        } else {
            if ($t.Count -ne 2) { return New-PackageResult $false $false @("ERROR: usage: vcpkg $verb") }
            if (-not (Test-Path -LiteralPath (Join-Path $SolutionDir "vcpkg.json"))) {
                return New-PackageResult $false $false @("ERROR: vcpkg.json was not found in $SolutionDir. Create it first (cpp_pkg.py setup).")
            }
            $argString = if ($verb -eq "baseline") { "x-update-baseline --add-initial-baseline" } else { "install --triplet " + (Get-VcpkgTripletName) }
        }
        $env:VCPKG_DISABLE_METRICS = "1"
        $r = Invoke-TestProcess $exe $argString $SolutionDir $PackageTimeoutSec
        $lines = @($r.Output | Where-Object { "$_".Trim() })
        if ($r.Timeout) { return New-PackageResult $false $true (@("ERROR: vcpkg timed out after ${PackageTimeoutSec}s (raise -PackageTimeoutSec, then run 'vcpkg install' again: finished ports are cached)") + $lines) }
        if ($r.ExitCode -ne 0) { return New-PackageResult $false (Test-PackageEnvOutput $lines) $lines }
        return New-PackageResult $true $false (@("vcpkg $verb finished (exit code 0): $exe") + $lines)
    }

    return New-PackageResult $false $false @("ERROR: unknown operation: $op  (nuget ... / vcpkg ... / fetch ...)")
}

# trigger_package.flag の各行を実行する。package_output.txt と package_error.log を書いたあとに、完了マーカーを書く。
function Invoke-PackageOps([string[]]$rawLines) {
    $ops = @($rawLines | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })
    $out = @()
    $full = @()
    $failure = $null
    if ($ops.Count -eq 0) {
        $failure = @{ Env = $false; Lines = @("ERROR: the flag has no operation (one operation per line).") }
    }
    foreach ($op in $ops) {
        if ($failure) { break }
        Write-Host "[PACKAGE] $op" -ForegroundColor Yellow
        try {
            $r = Invoke-OnePackageOp $op
        } catch {
            $r = New-PackageResult $false $false @("ERROR: $($_.Exception.Message)")
        }
        $full += @("## $op") + @($r.Lines)
        $shown = @($r.Lines)
        if ($shown.Count -gt $PackageMaxLines) {
            $shown = @($shown | Select-Object -First $PackageMaxLines) + "... ($($r.Lines.Count) lines in total; see .claude-logs\package.log)"
        }
        $out += @("## $op") + $shown
        $shown | ForEach-Object { Write-Host "  $_" }
        if (-not $r.Ok) { $failure = @{ Env = $r.Env; Lines = @($shown) } }
    }
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $full | Out-File $PackageLog -Encoding utf8
    @(ConvertTo-RelativePaths $out) | Out-File $PackageOutputFile -Encoding utf8
    if ($failure) {
        Write-Host "[PACKAGE] FAILED" -ForegroundColor Red
        $head = if ($failure.Env) { @("[ENVIRONMENT ERROR - not a source code problem]") } else { @() }
        @(ConvertTo-RelativePaths ($head + $failure.Lines)) | Out-File $PackageErrorLog -Encoding utf8
        Write-PackageMarker "FAILED"
    } else {
        Write-Host "[PACKAGE] OK" -ForegroundColor Green
        Write-PackageMarker "OK"
    }
}

# ---------- ビルドの実行 (build-windows.cmd) ----------
# build-windows.cmd を、専用の「表示しない」コンソールで実行し、出力をパイプで受け取って、このウィンドウに、1 行ずつ流す。
#   - ビルド用の、別のコンソール (ウィンドウ / タブ) が開かない。出力は、このウィンドウ (テストの出力と同じ画面) だけに出る。
#   - バッチの chcp 65001 / chcp 932 が、このウィンドウの文字コードを、変えない (表示が乱れない)。
# 戻り値: @{ Lines = 出力の行 (標準エラーを含む); ExitCode = バッチの終了コード }
function Invoke-BuildScript {
    # 起動後に、build-windows.cmd が消えた・別名になった場合: cmd /c は、終了コード 1 (ビルド失敗と区別できない) などで返る。環境エラー (2) として返す
    if (-not (Test-Path -LiteralPath $BuildScript)) {
        return @{ Lines = @("ERROR: build script not found: $BuildScript (restore it, e.g. with copy-host-tools.sh, then run again)."); ExitCode = 2 }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    # cmd /c の引用符の規則: 全体を、もう一度、引用符で囲む (先頭の " と、最後の " が、取り除かれる)。
    # 2>&1 で標準エラーも標準出力にまとめて、読み取りを 1 本にする (パイプが詰まって止まるのを避ける)。
    $psi.Arguments = '/c ""' + $BuildScript + '" "' + $SolutionPath + '" "' + $Platform + '" "' + $Configuration +
        '" "' + $MSBuildTarget + '" "' + $LogDir + '" "' + $BuildFeatures + '" 2>&1"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    # build-windows.cmd が、MSBuild の前後だけ chcp 65001 にするので、出力は UTF-8
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $lines = New-Object System.Collections.Generic.List[string]
    while ($null -ne ($line = $p.StandardOutput.ReadLine())) {
        Write-Host $line
        $lines.Add($line)
    }
    $p.WaitForExit()
    return @{ Lines = @($lines); ExitCode = $p.ExitCode }
}

# ---------- テスト関連の関数 ----------
function Find-TestExes {
    # C++ のプロジェクトがなければ、探さない (.NET だけのソリューションに、x64 のフォルダはない)
    if (-not $HasCpp) { return @() }
    $platDir = switch ($Platform.ToLower()) { "x64" { "x64" } "arm64" { "ARM64" } default { "Win32" } }
    # 出力先は <ソリューションフォルダ>\<x64|Win32|ARM64>\<Configuration>\
    # ただし、Visual Studio の既定では、Win32 だけ、プラットフォームのフォルダが付かない (<ソリューションフォルダ>\<Configuration>\)。両方を探す
    $dirs = @(Join-Path (Join-Path $SolutionDir $platDir) $Configuration)
    if ($platDir -eq "Win32") { $dirs += (Join-Path $SolutionDir $Configuration) }
    foreach ($dir in $dirs) {
        if (Test-Path -LiteralPath $dir) {
            $found = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match $TestExePattern } | Sort-Object Name)
            if ($found.Count -gt 0) { return $found }
        }
    }
    return @()
}

# .NET のテストプロジェクト: Microsoft.NET.Test.Sdk / MSTest を参照している、IsTestProject が true、または名前が Test(s) で終わる。
# (Directory.Build.props 側で指定している場合は、中身では判定できないので、名前で拾う)
# UI テストのプロジェクト: 名前が UITests / UiTests で終わる、または FlaUI を参照している。
# 通常のテスト (trigger_test.flag) からは除外し、trigger_uitest.flag (-Ui) のときだけ実行する (遅く、デスクトップを占有するため)。
function Find-DotnetTestProjects([switch]$Ui) {
    $found = @()
    foreach ($p in $ProjectPaths) {
        if ($p -notmatch '\.(csproj|vbproj|fsproj)$') { continue }
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $text = ""
        try { $text = [System.IO.File]::ReadAllText($p) } catch { continue }
        $byName = [System.IO.Path]::GetFileNameWithoutExtension($p) -match '(Test|Tests)$'
        if ($byName -or $text -match 'Microsoft\.NET\.Test\.Sdk|<IsTestProject>\s*true\s*</IsTestProject>|Sdk="MSTest\.Sdk|Include="MSTest"') {
            $isUi = ([System.IO.Path]::GetFileNameWithoutExtension($p) -match '(UI|Ui)Tests$') -or ($text -match 'Include="FlaUI\.')
            if ([bool]$Ui -eq [bool]$isUi) { $found += $p }
        }
    }
    return @($found)
}

# テストランナーの出力 (バイト列) を、行にする。
# dotnet test は UTF-8 で出力し、MSVC でビルドした GoogleTest の exe は ANSI (CP932) で出すことが多い。
# 先に UTF-8 として厳密に読み (不正なバイト列があれば例外)、できなければ ANSI として読む。BOM は除く。
# (以前は、すべてを ANSI として読んでいたため、dotnet test の日本語のメッセージが、文字化けした)
function Read-ProcessOutput([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    # 共有を許して開く: 強制終了した dotnet test の子プロセス (テストが起動したアプリなど) が、リダイレクト先のファイルを、
    # 開いたまま残していても、読める (ReadAllBytes は、書き込みで開かれていると、失敗する。UT7 で実機で確認)
    $fs = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try {
        $ms = New-Object System.IO.MemoryStream
        $fs.CopyTo($ms)
        $bytes = $ms.ToArray()
    } finally {
        $fs.Dispose()
    }
    if ($bytes.Length -eq 0) { return @() }
    try {
        $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)
    } catch {
        $text = [System.Text.Encoding]::Default.GetString($bytes)
    }
    $lines = @($text.TrimStart([char]0xFEFF) -split "`r?`n")
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") {
        $lines = @($lines | Select-Object -First ($lines.Count - 1))
    }
    return $lines
}

# UI テストを、別のデスクトップで実行するためのヘルパー (C#。Add-Type で、1 回だけ、コンパイルする)。
function Initialize-UiDesktopRunner {
    if ("UiDesktopRunner" -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

// UI テストを、別のデスクトップ (Win32 の CreateDesktop) で実行する。ユーザーの画面に、ウィンドウが出ず、フォーカスも奪わない。
// プロセスは、ジョブオブジェクト (KILL_ON_JOB_CLOSE) に入れる: 終了後 / 時間切れのとき、テストが起動して残ったアプリを、すべて終了する。
public static class UiDesktopRunner
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS { public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount; }
    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation; public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateDesktopW(string name, IntPtr device, IntPtr devmode, int flags, uint access, IntPtr sa);
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateJobObjectW(IntPtr sa, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, int size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint WaitForSingleObject(IntPtr handle, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    const uint GENERIC_ALL = 0x10000000;
    const uint CREATE_SUSPENDED = 0x00000004;
    const uint CREATE_NO_WINDOW = 0x08000000;
    const int STARTF_USESTDHANDLES = 0x00000100;
    const uint HANDLE_FLAG_INHERIT = 1;
    const uint WAIT_TIMEOUT = 0x00000102;
    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
    const int JobObjectExtendedLimitInformation = 9;

    static IntPtr Inheritable(FileStream fs)
    {
        IntPtr h = fs.SafeFileHandle.DangerousGetHandle();
        if (!SetHandleInformation(h, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT)) throw new Win32Exception(Marshal.GetLastWin32Error());
        return h;
    }

    // 戻り値: 終了コード (時間切れのときは -1)。timedOut: 制限時間を超えて、強制終了したか。
    public static int Run(string commandLine, string workDir, string desktopName, string outPath, string errPath, int timeoutMs, out bool timedOut)
    {
        timedOut = false;
        IntPtr desk = CreateDesktopW(desktopName, IntPtr.Zero, IntPtr.Zero, 0, GENERIC_ALL, IntPtr.Zero);
        if (desk == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateDesktop failed");
        IntPtr job = IntPtr.Zero;
        PROCESS_INFORMATION pi = new PROCESS_INFORMATION();
        bool started = false;
        FileStream fsOut = null, fsErr = null, fsIn = null;
        try
        {
            fsOut = new FileStream(outPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
            fsErr = new FileStream(errPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
            try { fsIn = new FileStream(@"\\.\NUL", FileMode.Open, FileAccess.Read, FileShare.ReadWrite); } catch (Exception) { fsIn = null; }

            job = CreateJobObjectW(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObject failed");
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, ref info, Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION))))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SetInformationJobObject failed");

            STARTUPINFO si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            si.lpDesktop = "WinSta0\\" + desktopName;
            si.dwFlags = STARTF_USESTDHANDLES;
            si.hStdInput = (fsIn != null) ? Inheritable(fsIn) : IntPtr.Zero;
            si.hStdOutput = Inheritable(fsOut);
            si.hStdError = Inheritable(fsErr);

            StringBuilder cmd = new StringBuilder(commandLine);
            if (!CreateProcessW(null, cmd, IntPtr.Zero, IntPtr.Zero, true, CREATE_SUSPENDED | CREATE_NO_WINDOW, IntPtr.Zero, workDir, ref si, out pi))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateProcess failed");
            started = true;
            if (!AssignProcessToJobObject(job, pi.hProcess)) throw new Win32Exception(Marshal.GetLastWin32Error(), "AssignProcessToJobObject failed");
            ResumeThread(pi.hThread);

            uint w = WaitForSingleObject(pi.hProcess, (uint)timeoutMs);
            int exit;
            if (w == WAIT_TIMEOUT)
            {
                timedOut = true;
                exit = -1;
            }
            else
            {
                uint code;
                exit = GetExitCodeProcess(pi.hProcess, out code) ? unchecked((int)code) : -2;
            }
            // 時間切れでも、正常終了でも、ジョブの中のプロセス (テストが起動して、残ったアプリ) を、すべて終了する
            TerminateJobObject(job, 1);
            WaitForSingleObject(pi.hProcess, 5000);
            return exit;
        }
        finally
        {
            if (started)
            {
                if (job != IntPtr.Zero) TerminateJobObject(job, 1);
                CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
            }
            if (job != IntPtr.Zero) CloseHandle(job);
            if (fsIn != null) fsIn.Dispose();
            if (fsOut != null) fsOut.Dispose();
            if (fsErr != null) fsErr.Dispose();
            CloseDesktop(desk);
        }
    }
}
'@
}

# 別のデスクトップでは、WPF の画面を PrintWindow で撮ると、クライアント領域が白くなる (ハードウェアアクセラレーションの描画。実機で確認)。
# UI テストの間だけ、ユーザーの WPF の描画を、ソフトウェアレンダリングにする (HKCU の DisableHWAcceleration=1)。WPF は、プロセスの起動時に読む。
# **元の値を、変更する前に、ファイルに記録する** (absent = もともと無い / 数値)。終わったら、記録から、元に戻して、記録を消す。
# ウォッチャーが、途中で異常終了して、記録が残っていたら、**次の起動時に、元に戻す** (Restore-WpfRendering を、起動時にも呼ぶ)。
# 記録は、ウォッチャーの間で共有する (最初に変えた時の、元の値を、守る。UI テストを、同時に 2 つは、実行しない前提)。
$WpfHwAccelKey = 'HKCU:\Software\Microsoft\Avalon.Graphics'
$WpfHwAccelBackup = Join-Path $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:TEMP }) "claude-watcher\wpf-hwaccel-backup.txt"
function Set-WpfSoftwareRendering {
    try {
        if (-not (Test-Path -LiteralPath $WpfHwAccelBackup)) {   # すでにあれば、元の値は、記録済み (前回の残り)
            if (-not (Test-Path -LiteralPath $WpfHwAccelKey)) { New-Item -Path $WpfHwAccelKey -Force | Out-Null }
            $prev = (Get-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -ErrorAction SilentlyContinue).DisableHWAcceleration
            New-Item -ItemType Directory -Path (Split-Path -Parent $WpfHwAccelBackup) -Force | Out-Null
            [System.IO.File]::WriteAllText($WpfHwAccelBackup, $(if ($null -eq $prev) { "absent" } else { "$prev" }))
        }
        Set-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -Value 1 -Type DWord
        Write-Host "[UITEST] WPF software rendering ON (HKCU Avalon.Graphics DisableHWAcceleration=1; the original value is recorded and restored after the run)" -ForegroundColor DarkGray
    } catch {
        Write-Host "[UITEST] could not set WPF software rendering: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
function Restore-WpfRendering {
    if (-not (Test-Path -LiteralPath $WpfHwAccelBackup)) { return }
    try {
        $v = ([System.IO.File]::ReadAllText($WpfHwAccelBackup)).Trim()
        # 失敗を、握りつぶさない (-ErrorAction Stop)。以前は SilentlyContinue で、失敗しても「復元した」と表示した (UT14b の実機で発見)
        if ($v -eq "absent") {
            if (Get-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -ErrorAction Stop
            }
        } else {
            Set-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -Value ([int]$v) -Type DWord -ErrorAction Stop
        }
        # 実際に戻ったかを、確かめてから、記録を消す
        $now = (Get-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -ErrorAction SilentlyContinue).DisableHWAcceleration
        $expected = if ($v -eq "absent") { $null } else { [int]$v }
        if ("$now" -ne "$expected") { throw "the registry value is still '$now' (expected '$expected')" }
        Remove-Item -LiteralPath $WpfHwAccelBackup -ErrorAction Stop
        if (Test-Path -LiteralPath $WpfHwAccelBackup) { throw "the backup file could not be deleted" }
        Write-Host "[UITEST] WPF rendering setting restored ($v)" -ForegroundColor DarkGray
    } catch {
        Write-Host "[UITEST] could not restore the WPF rendering setting: $($_.Exception.GetType().Name): $($_.Exception.Message) (backup file: $WpfHwAccelBackup)" -ForegroundColor Yellow
    }
}

# 別のデスクトップで、子プロセスを、制限時間つきで実行する。戻り値は、Invoke-TestProcess と同じ形。
function Invoke-TestProcessOnDesktop([string]$filePath, [string]$argString, [string]$workDir, [int]$limit, [string]$outTmp, [string]$errTmp) {
    Initialize-UiDesktopRunner
    $cmdLine = '"' + $filePath + '"' + $(if ($argString) { " " + $argString } else { "" })
    $timedOut = $false
    $exit = [UiDesktopRunner]::Run($cmdLine, $workDir, ("ClaudeUiTest" + $PID), $outTmp, $errTmp, ($limit * 1000), [ref]$timedOut)
    $lines = @()
    foreach ($f in @($outTmp, $errTmp)) {
        $lines += @(Read-ProcessOutput $f)
    }
    Remove-Item -LiteralPath $outTmp, $errTmp -ErrorAction SilentlyContinue
    $code = if ($timedOut) { $null } else { $exit }
    return @{ Timeout = $timedOut; ExitCode = $code; Output = $lines }
}

# 子プロセスを、制限時間つきで実行する。戻り値: @{ Timeout = bool; ExitCode = int; Output = string[] }
function Invoke-TestProcess([string]$filePath, [string]$argString, [string]$workDir, [int]$timeoutSec = 0) {
    $limit = if ($timeoutSec -gt 0) { $timeoutSec } else { $TestTimeoutSec }
    $outTmp = Join-Path $LogDir "test_stdout.tmp"
    $errTmp = Join-Path $LogDir "test_stderr.tmp"
    Remove-Item -LiteralPath $outTmp, $errTmp -ErrorAction SilentlyContinue
    if ($script:UiSeparateDesktop) { return Invoke-TestProcessOnDesktop $filePath $argString $workDir $limit $outTmp $errTmp }

    $spArgs = @{
        FilePath               = $filePath
        WorkingDirectory       = $workDir
        RedirectStandardOutput = $outTmp
        RedirectStandardError  = $errTmp
        PassThru               = $true
        NoNewWindow            = $true
    }
    if ($argString) { $spArgs["ArgumentList"] = $argString }
    $p = Start-Process @spArgs
    $null = $p.Handle   # PS 5.1: これがないと ExitCode が取れないことがある
    $timedOut = $false
    if (-not $p.WaitForExit($limit * 1000)) {
        $timedOut = $true
        # 子プロセスごと強制終了。Stop 下でネイティブの stderr が例外になるため握りつぶす
        try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch { }
        try { $p.Kill() } catch { }
        # 終了待ちにも上限を付ける (無期限に待つとウォッチャー全体が止まる)
        [void]$p.WaitForExit(5000)
    }
    $exitCode = if ($timedOut) { $null } else { $p.ExitCode }

    # 出力の文字コードは、ランナーによって違う (UTF-8 または ANSI)。Read-ProcessOutput が、判定して読む
    $lines = @()
    foreach ($f in @($outTmp, $errTmp)) {
        $lines += @(Read-ProcessOutput $f)
    }
    Remove-Item -LiteralPath $outTmp, $errTmp -ErrorAction SilentlyContinue
    return @{ Timeout = $timedOut; ExitCode = $exitCode; Output = $lines }
}

# GoogleTest の exe。--gtest_output=xml で、機械可読な結果を、.claude-logs\test-results\<exe名>.xml にも残す。
function Invoke-TestExe($exe) {
    $workDir = if ($TestWorkingDir) { $TestWorkingDir } else { $exe.DirectoryName }
    $xml = Join-Path $TestResultsDir ([System.IO.Path]::GetFileNameWithoutExtension($exe.Name) + ".xml")
    $argString = (@($TestArgs, ('"--gtest_output=xml:' + $xml + '"')) | Where-Object { $_ }) -join " "
    return Invoke-TestProcess $exe.FullName $argString $workDir
}

# .NET のテストプロジェクト。ビルドは、ソリューションのビルドで済んでいるので --no-build。
# trx を、.claude-logs\test-results\<プロジェクト名>.trx に残す。
function Invoke-DotnetTest([string]$project, [string]$dotnetPath, [int]$timeoutSec = 0) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($project)
    $argString = 'test "' + $project + '" --no-build -c ' + $Configuration +
        ' --results-directory "' + $TestResultsDir + '" --logger "trx;LogFileName=' + $name + '.trx"'
    if ($DotnetTestArgs) { $argString += " " + $DotnetTestArgs }
    return Invoke-TestProcess $dotnetPath $argString (Split-Path -Parent $project) $timeoutSec
}

# trx の集計 (実行数など)。trx がない、読めないときは $null。
function Get-TrxCounters([string]$trx) {
    if (-not (Test-Path -LiteralPath $trx)) { return $null }
    try {
        $x = [xml](Get-Content -LiteralPath $trx -Raw -Encoding UTF8)
        return $x.TestRun.ResultSummary.Counters
    } catch {
        return $null
    }
}

# dotnet test --no-build が、古い出力先のテストアセンブリを実行していないか調べる。
# 出力先が bin\x64\Debug などのプラットフォーム別のとき、-DotnetTestArgs を付けないと、dotnet test は bin\Debug を探す。
# そこに過去のビルドの古い DLL が残っていると、今回のビルドの成果物ではなく、古い DLL のテストが通る (偽の成功)。
# 実行されたアセンブリ (trx の storage) と同名で、より新しい DLL が、プロジェクトの bin 配下の別の場所にあれば、その一覧を返す。
# (増分ビルドで DLL が書き換わらないのは、正常。なので、更新時刻とビルドの開始時刻は比べない)
# 比べるのは、構成 (Debug / Release) と、TFM (net8.0 など) が同じで、プラットフォームのフォルダだけが違うもの (bin\Debug\net8.0 と bin\x64\Debug\net8.0)。
# Debug と Release は、別の成果物なので、比べない (構成を切り替えて使うと、古い側が、誤って ENV_ERROR になる)
function Get-StaleTestAssemblies([string]$project, [string]$trx) {
    if (-not (Test-Path -LiteralPath $trx)) { return @() }
    try { $x = [xml](Get-Content -LiteralPath $trx -Raw -Encoding UTF8) } catch { return @() }
    $binDir = Join-Path (Split-Path -Parent $project) "bin"
    if (-not (Test-Path -LiteralPath $binDir)) { return @() }
    $used = @{}
    foreach ($u in @($x.TestRun.TestDefinitions.UnitTest)) {
        if ($u -and $u.storage -and (Test-Path -LiteralPath $u.storage)) { $used[(Get-Item -LiteralPath $u.storage).FullName] = $true }
    }
    $stale = @()
    foreach ($path in $used.Keys) {
        $usedItem = Get-Item -LiteralPath $path
        $newer = Get-ChildItem -LiteralPath $binDir -Recurse -File -Filter $usedItem.Name -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $usedItem.FullName -and $_.LastWriteTimeUtc -gt $usedItem.LastWriteTimeUtc.AddSeconds(2) -and
                           $_.Directory.Name -eq $usedItem.Directory.Name -and
                           $_.Directory.Parent -and $usedItem.Directory.Parent -and $_.Directory.Parent.Name -eq $usedItem.Directory.Parent.Name } |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if ($newer) { $stale += "$($usedItem.FullName) ($($usedItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))) is older than $($newer.FullName) ($($newer.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')))" }
    }
    return $stale
}

# trx の失敗したテストを、人が読める形 (test_error.log 用) にする。構造化された解釈は、WSL 側の summarize_test_log.py が、trx を直接読んで行う。
function Get-TrxFailureLines([string]$trx) {
    if (-not (Test-Path -LiteralPath $trx)) { return }
    try { $x = [xml](Get-Content -LiteralPath $trx -Raw -Encoding UTF8) } catch { return }
    $defs = @{}
    foreach ($u in @($x.TestRun.TestDefinitions.UnitTest)) {
        if ($u -and $u.TestMethod) {
            $defs["$($u.id)"] = (("$($u.TestMethod.className)" -split ',')[0].Trim()) + "." + $u.TestMethod.name
        }
    }
    foreach ($r in @($x.TestRun.Results.UnitTestResult)) {
        if (-not $r) { continue }
        if ("$($r.outcome)" -notmatch '^(Failed|Timeout|Aborted|Error)$') { continue }
        $key = "$($r.testId)"
        $name = if ($defs.ContainsKey($key)) { $defs[$key] } else { "$($r.testName)" }
        "FAILED $name"
        foreach ($l in ("$($r.Output.ErrorInfo.Message)" -split "`r?`n")) {
            if ($l.Trim()) { "  " + $l.Trim() }
        }
        foreach ($l in ("$($r.Output.ErrorInfo.StackTrace)" -split "`r?`n")) {
            if ($l -match '\s(in|場所)\s+.+:(line|行)\s+\d+\s*$') { "  at " + ($l.Trim() -replace '^(at|場所)\s+', ''); break }
        }
    }
}

# ログ中の "<ソリューションフォルダ>\xxx\yyy.cpp" を "xxx/yyy.cpp" (相対・スラッシュ) に変換する。
# Claude (WSL) がそのまま開けるようにし、出力も短くするため。パス以外の "\" は変えない。
function ConvertTo-RelativePaths($lines) {
    $pattern = [regex]::Escape($SolutionDir.TrimEnd('\') + '\') + '([^\s(\[\]:"]+)'
    $re = New-Object System.Text.RegularExpressions.Regex($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $ev = [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value.Replace('\', '/') }
    return @($lines | ForEach-Object { $re.Replace("$_", $ev) })
}

function Write-TestMarker($value) {
    try {
        [System.IO.File]::WriteAllText($TestResultFile, $value)
        Write-Host "[MARKER] $value -> $TestResultFile" -ForegroundColor DarkGray
    } catch {
        Write-Host "[MARKER] FAILED to write $TestResultFile : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 環境エラー (ソースの問題ではない) を記録する。test_error.log を書いたあとに、完了マーカーを書く。
function Write-TestEnvError([string[]]$lines) {
    Write-Host "[TEST] ENV_ERROR: $($lines[0])" -ForegroundColor Red
    (@("[ENVIRONMENT ERROR - not a source code problem]") + @($lines) + @("", "Test failed: environment error")) | Out-File $TestErrorLog -Encoding utf8
    Write-TestMarker "ENV_ERROR"
}

# ソリューションのフォルダの下の exe のプロセス (UI テストが残したアプリなど) を、終了する。
# 残ると、出力の exe がロックされ、次のビルドが失敗する (UI テストの前後に、呼ぶ)。
function Stop-SolutionProcesses {
    $prefix = $SolutionDir.TrimEnd('\') + '\'
    foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($proc.Id -eq $PID) { continue }
        $path = $null
        try { $path = $proc.Path } catch { }
        if ($path -and $path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "[UITEST] Stopping leftover process: $($proc.ProcessName) (PID $($proc.Id))" -ForegroundColor Yellow
            try { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null } catch { }
        }
    }
}

# UI テストのプロジェクトの、既定の設定 (プロジェクトのフォルダの uitest.settings。`desktop=visible|separate` と `slowmo=N`)。
# フレームワークごとの違い (WPF のメニューは、別のデスクトップで開かない、など) は、ウォッチャーでなく、このファイルが持つ (add_ui_tests.py が、プロジェクトを作るときに、書く)。
# UI テストのプロジェクトが複数あるときは、1 つでも visible なら visible (visible は、どのコントロールでも動くため)。slowmo は、最大。
# 戻り値: @{ Desktop = ''|'default'|'separate'; SlowMoMs = $null|int; Source = string }
function Read-UiProjectSettings {
    $desktop = ""
    $slow = $null
    $src = @()
    foreach ($p in @(Find-DotnetTestProjects -Ui)) {
        $f = Join-Path (Split-Path -Parent $p) "uitest.settings"
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $src += (Split-Path -Leaf (Split-Path -Parent $p)) + "/uitest.settings"
        $kv = ConvertFrom-UiSettingsText ([System.IO.File]::ReadAllText($f))
        if ($kv.Desktop -eq "default") { $desktop = "default" } elseif ($kv.Desktop -eq "separate" -and $desktop -ne "default") { $desktop = "separate" }
        if ($null -ne $kv.SlowMoMs -and ($null -eq $slow -or $kv.SlowMoMs -gt $slow)) { $slow = $kv.SlowMoMs }
    }

    return @{ Desktop = $desktop; SlowMoMs = $slow; Source = ($src -join ", ") }
}

# `desktop=...` と `slowmo=...` の行 (flag の中身と、uitest.settings で共通。# から行末は、コメント)。desktop: visible → default、invisible → separate。
function ConvertFrom-UiSettingsText([string]$text) {
    $desktop = ""
    $slow = $null
    foreach ($line in @("$text" -split "[\r\n]+")) {
        $l = (($line -replace '^\uFEFF', '') -replace '#.*$', '').Trim()
        if ($l -match '^desktop\s*=\s*(\w+)$') {
            $w = $Matches[1].ToLowerInvariant()
            if ($w -eq "visible") { $w = "default" }
            if ($w -eq "invisible") { $w = "separate" }
            if ($w -in @("default", "separate")) { $desktop = $w }
        }
        elseif ($l -match '^slowmo\s*=\s*(\d+)$') { $slow = [int]$Matches[1] }
    }

    return @{ Desktop = $desktop; SlowMoMs = $slow }
}

# trigger_uitest.flag の中身 (1 回ごとの指定) と、ウォッチャーの設定と、プロジェクトの uitest.settings から、この回の UI テストの設定を決める。
# 優先順: flag の desktop= > ウォッチャーの -UiTestDesktop / WATCH_UI_DESKTOP (auto 以外) > プロジェクトの uitest.settings > separate。
# slowmo= も、flag > uitest.settings > ウォッチャーの -UiTestSlowMoMs。戻り値: @{ Desktop = 'default'|'separate'; SlowMoMs = int; Reason = string }
function Resolve-UiRun([string]$flagText) {
    $fl = ConvertFrom-UiSettingsText $flagText
    $proj = Read-UiProjectSettings
    if ($fl.Desktop) { $desktop = $fl.Desktop; $reason = "trigger_uitest.flag" }
    elseif ($UiTestDesktop -in @("default", "separate")) { $desktop = $UiTestDesktop; $reason = "watcher setting (-UiTestDesktop / WATCH_UI_DESKTOP)" }
    elseif ($proj.Desktop) { $desktop = $proj.Desktop; $reason = $proj.Source }
    else { $desktop = "separate"; $reason = "default (no uitest.settings)" }
    $slow = if ($null -ne $fl.SlowMoMs) { $fl.SlowMoMs } elseif ($null -ne $proj.SlowMoMs) { $proj.SlowMoMs } else { $UiTestSlowMoMs }
    return @{ Desktop = $desktop; SlowMoMs = $slow; Reason = $reason }
}

# ビルド成功後のテスト実行 (GoogleTest の exe と、.NET のテストプロジェクト)。test_result.txt を最後に書く。
# -Ui: UI テストのプロジェクトだけを実行する (GoogleTest の exe は、実行しない)。環境変数 UITEST_* で、テストに実行環境を渡す。
function Invoke-Tests([switch]$Ui) {
    New-Item -ItemType Directory -Path $TestResultsDir -Force | Out-Null
    $limit = if ($Ui) { $UiTestTimeoutSec } else { $TestTimeoutSec }
    $script:UiSeparateDesktop = ($Ui -and $script:UiRun.Desktop -eq "separate")
    if ($Ui) {
        New-Item -ItemType Directory -Path $UiScreenshotDir -Force | Out-Null
        $env:UITEST_SOLUTION_DIR = $SolutionDir
        $env:UITEST_CONFIGURATION = $Configuration
        $env:UITEST_PLATFORM = $Platform
        $env:UITEST_SCREENSHOT_DIR = $UiScreenshotDir
        $env:UITEST_SLOWMO_MS = "$($script:UiRun.SlowMoMs)"
    }
    $exes = if ($Ui) { @() } else { @(Find-TestExes) }
    $projects = @(Find-DotnetTestProjects -Ui:$Ui)
    if ($Ui -and $projects.Count -eq 0) {
        Write-TestEnvError @("ERROR: no UI test project found under $SolutionDir",
            "  A .NET test project whose name ends with UITests / UiTests, or that references FlaUI.* (.NET project in solution: $HasDotnet)")
        return
    }
    if ($exes.Count -eq 0 -and $projects.Count -eq 0) {
        Write-TestEnvError @("ERROR: no tests found for $Configuration|$Platform under $SolutionDir",
            "  GoogleTest exe matching '$TestExePattern' : none (C++ project in solution: $HasCpp)",
            "  .NET test project (Microsoft.NET.Test.Sdk / MSTest, or a name ending in Test/Tests) : none (.NET project in solution: $HasDotnet)")
        return
    }
    $dotnetPath = $null
    if ($projects.Count -gt 0) {
        $cmd = Get-Command $DotnetExe -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-TestEnvError @("ERROR: '$DotnetExe' was not found, but the solution has .NET test projects. Install the .NET SDK, or pass -DotnetExe <full path>.", $DotnetInstallHint)
            return
        }
        $dotnetPath = $cmd.Source
    }

    $report = @()
    $failed = $false
    $timedOut = $false
    $invalid = $false
    $staleFound = $false
    $all = @()

    # --- GoogleTest (C++) ---
    foreach ($exe in $exes) {
        Write-Host "[TEST] Running $($exe.Name) (timeout ${TestTimeoutSec}s)..." -ForegroundColor Yellow
        $r = Invoke-TestExe $exe
        $all += @("=== $($exe.Name) ===") + @($r.Output)
        $r.Output | ForEach-Object { Write-Host $_ }

        if ($r.Timeout) {
            $timedOut = $true
            $report += "=== $($exe.Name): TIMEOUT after ${TestTimeoutSec}s (killed) ==="
            $hung = Get-HungTest $r.Output
            if ($hung) { $report += "Hung test (was running when killed): $hung" }
            $report += @(Select-TestFailureLines $r.Output)
            break
        }
        # 終了コード 0 でも "[  PASSED  ]" がなければテストは実行されていない
        # (不正な引数でヘルプだけ表示して終了コード 0、テスト0件、GoogleTest でない exe など)
        if ($r.ExitCode -eq 0 -and -not ($r.Output | Where-Object { "$_" -match '^\[\s+PASSED\s+\]' })) {
            $invalid = $true
            $report += "=== $($exe.Name): no gtest summary ([  PASSED  ]) in output; tests were probably not run ==="
            $report += @($r.Output | Select-Object -First 15)
        }
        if ($r.ExitCode -ne 0) {
            $failed = $true
            $report += "=== $($exe.Name): exit code $($r.ExitCode) ==="
            $lines = @(Select-TestFailureLines $r.Output)
            $report += $lines
            if (-not ($r.Output | Where-Object { "$_" -match '^\[\s+FAILED\s+\]' })) {
                $report += "(no gtest failure lines: process crashed or exited abnormally, exit code $($r.ExitCode))"
            }
        }
    }

    # --- dotnet test (MSTest など) ---
    if (-not $timedOut) {
        foreach ($proj in $projects) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($proj)
            Write-Host "[TEST] Running dotnet test: $name (timeout ${limit}s)..." -ForegroundColor Yellow
            $r = Invoke-DotnetTest $proj $dotnetPath $limit
            $all += @("=== $name (dotnet test) ===") + @($r.Output)
            $r.Output | ForEach-Object { Write-Host $_ }
            $trx = Join-Path $TestResultsDir "$name.trx"

            if ($r.Timeout) {
                $timedOut = $true
                $report += "=== $name (dotnet test): TIMEOUT after ${limit}s (killed) ==="
                if ($Ui) { Stop-SolutionProcesses }   # テストが起動して、残ったアプリ
                break
            }
            # 古い出力先の DLL を実行していないか (成功のときは、偽の成功を防ぐため、ENV_ERROR にする)
            $stale = @(Get-StaleTestAssemblies $proj $trx)
            if ($stale.Count -gt 0) {
                $staleFound = $true
                if ($r.ExitCode -eq 0) { $invalid = $true }
                $report += "=== $name (dotnet test): the test assembly that was run is older than a build output in another folder ==="
                $report += $stale
                $report += "dotnet test --no-build looked in a different output folder than the build wrote (e.g. bin\Debug, while the build wrote bin\x64\Debug). Pass -DotnetTestArgs:-p:Platform=x64 (match the build platform), or delete the stale bin folder."
            }
            if ($r.ExitCode -eq 0) {
                # 終了コード 0 でも、1 件も実行されていなければ、テストは走っていない (テスト 0 件、アダプタ未検出など)
                $counters = Get-TrxCounters $trx
                if (-not $counters -or [int]$counters.executed -le 0) {
                    $invalid = $true
                    $report += "=== $name (dotnet test): no tests were executed (no trx, or executed=0) ==="
                    $report += @($r.Output | Select-Object -Last 15)
                }
            } else {
                $failed = $true
                $report += "=== $name (dotnet test): exit code $($r.ExitCode) ==="
                $lines = @(Get-TrxFailureLines $trx)
                if ($lines.Count -gt 0) {
                    $report += $lines
                } else {
                    $report += "(no test results: the test host crashed, or dotnet test failed before running tests)"
                    $report += @($r.Output | Select-Object -Last 30)
                }
            }
        }
    }
    $all | Out-File $TestLog -Encoding utf8

    if ($timedOut) {
        Write-Host "[RESULT] Tests TIMEOUT." -ForegroundColor Red
        $report += ""; $report += "Test timeout: ${limit}s"
        @(ConvertTo-RelativePaths $report) | Out-File $TestErrorLog -Encoding utf8
        Write-TestMarker "TIMEOUT"
    } elseif ($failed) {
        Write-Host "[RESULT] Tests FAILED." -ForegroundColor Red
        $report += ""; $report += "Tests failed"
        @(ConvertTo-RelativePaths $report) | Out-File $TestErrorLog -Encoding utf8
        Write-TestMarker "FAILED"
    } elseif ($invalid) {
        $envNote = if ($staleFound) { "Test result is not trusted: the tests ran against an older build output (see above)." } else { "Test failed: tests were probably not run (GoogleTest: check -TestArgs / is this a GoogleTest exe? dotnet: is Microsoft.NET.Test.Sdk and a test adapter referenced?)" }
        Write-Host "[RESULT] Tests ENV_ERROR ($(if ($staleFound) { 'tests ran against an older build output' } else { 'tests were probably not run' }))." -ForegroundColor Red
        @(ConvertTo-RelativePaths (@("[ENVIRONMENT ERROR - not a source code problem]") + $report + @("", $envNote))) |
            Out-File $TestErrorLog -Encoding utf8
        Write-TestMarker "ENV_ERROR"
    } else {
        Write-Host "[RESULT] Tests PASSED." -ForegroundColor Green
        Write-TestMarker "PASSED"
    }
}

# 成功テストの実行ログ ([ RUN ] / [ OK ] / 区切り線) を除いて、失敗に関する行だけ残す
function Select-TestFailureLines($lines) {
    return @($lines | Where-Object { "$_" -notmatch '^\[\s+RUN\s+\]|^\[\s+OK\s+\]|^\[-{10}\]|^\s*$' })
}

# 強制終了時に実行中だったテスト名 ("[ RUN ]" だけで "[ OK ]"/"[ FAILED ]" が続かなかったもの) を返す
function Get-HungTest($lines) {
    $current = $null
    foreach ($l in $lines) {
        if ("$l" -match '^\[\s+RUN\s+\]\s+(\S+)') { $current = $Matches[1] }
        elseif ($current -and "$l" -match '^\[\s+(OK|FAILED)\s+\]\s+(\S+)' -and $Matches[2] -eq $current) { $current = $null }
    }
    return $current
}

# ---------- クイック編集モードの無効化 ----------
# コンソール内をクリック/選択すると出力が一時停止し、ビルドやテストが途中で止まる (Enter/Esc で再開) のを防ぐ。
# 失敗しても監視は続行する (戻り値は表示用の状態文字列)。
function Disable-ConsoleQuickEdit {
    try {
        Add-Type -Namespace WatcherNative -Name ConsoleMode -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
'@
        $h = [WatcherNative.ConsoleMode]::GetStdHandle(-10)   # STD_INPUT_HANDLE
        $mode = [uint32]0
        if (-not [WatcherNative.ConsoleMode]::GetConsoleMode($h, [ref]$mode)) { return "skipped (no console)" }
        # QUICK_EDIT_MODE (0x40) を外し、変更を有効にするため EXTENDED_FLAGS (0x80) を付ける
        $newMode = [uint32](([int64]$mode -band 0xFFFFFFBFL) -bor 0x80L)
        if ([WatcherNative.ConsoleMode]::SetConsoleMode($h, $newMode)) { return "disabled (clicking this window will not pause the build)" }
        return "not changed"
    } catch {
        return "not changed ($($_.Exception.Message))"
    }
}
$QuickEditStatus = Disable-ConsoleQuickEdit

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " MSBuild Watcher Started" -ForegroundColor Cyan
Write-Host " Target       : $(if ($SolutionPath) { $SolutionPath } else { '(no .sln / .slnx in ' + $TargetDir + ' yet: it is detected when a trigger arrives)' })" -ForegroundColor Cyan
Write-Host " Solution     : $SolutionKind  (build features: $BuildFeatures)" -ForegroundColor Cyan
Write-Host " Build        : $Configuration|$Platform  /t:$MSBuildTarget" -ForegroundColor Cyan
Write-Host " Build script : $BuildScript" -ForegroundColor Cyan
Write-Host " Logs         : $LogDir" -ForegroundColor Cyan
Write-Host " Triggers     : trigger_build.flag (build) / trigger_test.flag (build + test) / trigger_uitest.flag (build + UI test) / trigger_gtest.flag (fetch GoogleTest) / trigger_package.flag (NuGet / vcpkg / fetch)" -ForegroundColor Cyan
Write-Host " Test exe     : $TestExePattern (GoogleTest, timeout ${TestTimeoutSec}s)" -ForegroundColor Cyan
Write-Host " UI test      : trigger_uitest.flag (desktop: $UiTestDesktop [auto = uitest.settings of the UI test project, else separate; override per run with desktop=visible|separate in the flag], timeout ${UiTestTimeoutSec}s, slow-motion: ${UiTestSlowMoMs}ms)" -ForegroundColor Cyan
Write-Host " Proxy        : $(if ($proxyUrl) { $proxyUrl + ' (from the HTTPS_PROXY / HTTP_PROXY environment variable)' } else { '(none: the system proxy settings are used)' })" -ForegroundColor Cyan
Write-Host " dotnet test  : $DotnetExe  (projects: $(@(Find-DotnetTestProjects).Count))" -ForegroundColor Cyan
Write-Host " QuickEdit    : $QuickEditStatus" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 前回のウォッチャーが、UI テストの途中で異常終了して、WPF の描画の設定を、変えたままなら、元に戻す
Restore-WpfRendering

# ---------- 監視ループ ----------
while ($true) {
    # GoogleTest のソース取得 (ビルドの前提になるので、先に処理する)
    if (Test-Path -LiteralPath $GtestTriggerFile) {
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Trigger detected (gtest fetch)!" -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500   # Claude 側の書き込み完了待ち
        Update-SolutionState
        $gtestTagLine = ""
        try { $gtestTagLine = "$(Get-Content -LiteralPath $GtestTriggerFile -TotalCount 1 -ErrorAction Stop)" } catch { }
        Remove-Item -LiteralPath $GtestTriggerFile, $GtestResultFile, $GtestErrorLog -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        try {
            Invoke-GtestFetch $gtestTagLine
        } catch {
            Write-GtestFailure @("ERROR: gtest fetch failed: $($_.Exception.Message)")
        }
        Write-Host "Waiting for next trigger..." -ForegroundColor Cyan
    }

    # パッケージの操作 (NuGet / vcpkg / ソースの取得)。ビルドの前提になるので、ビルドより先に処理する
    if (Test-Path -LiteralPath $PackageTriggerFile) {
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Trigger detected (package)!" -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500   # Claude 側の書き込み完了待ち
        Update-SolutionState
        $packageLines = @()
        try { $packageLines = @(Get-Content -LiteralPath $PackageTriggerFile -ErrorAction Stop) } catch { }
        Remove-Item -LiteralPath $PackageTriggerFile, $PackageResultFile, $PackageErrorLog, $PackageOutputFile -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        try {
            Invoke-PackageOps $packageLines
        } catch {
            @("[ENVIRONMENT ERROR - not a source code problem]", "ERROR: package operation failed: $($_.Exception.Message)") | Out-File $PackageErrorLog -Encoding utf8
            Write-PackageMarker "FAILED"
        }
        Write-Host "Waiting for next trigger..." -ForegroundColor Cyan
    }

    $runUiTests = Test-Path -LiteralPath $UiTestTriggerFile
    $runTests = (-not $runUiTests) -and (Test-Path -LiteralPath $TestTriggerFile)   # 両方あるときは、UI テストを先に処理する (もう一方のフラグは、残して、次の周回で処理)
    if ($runUiTests -or $runTests -or (Test-Path -LiteralPath $TriggerFile)) {
        $mode = if ($runUiTests) { "build + UI test" } elseif ($runTests) { "build + test" } else { "build" }
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Trigger detected ($mode)! Starting build..." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500   # Claude 側の書き込み完了待ち
        Update-SolutionState   # 起動後に、ソリューションができた・プロジェクトが増えた (テストの後付けなど) 場合に備え、トリガーごとに、決め直す
        if ($runUiTests) {
            $uiFlagText = ""
            try { $uiFlagText = Get-Content -LiteralPath $UiTestTriggerFile -Raw -ErrorAction Stop } catch { $uiFlagText = "" }   # フラグを消す前に、1 回ごとの指定 (desktop= / slowmo=) を読む
            $script:UiRun = Resolve-UiRun $uiFlagText
            Write-Host "[UI] desktop: $($script:UiRun.Desktop) ($($script:UiRun.Reason)), slow-motion: $($script:UiRun.SlowMoMs) ms" -ForegroundColor Cyan
        }
        Remove-Item -LiteralPath $TriggerFile, $(if ($runUiTests) { $UiTestTriggerFile } else { $TestTriggerFile }) -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Remove-Item -LiteralPath $ResultFile, $ErrorLog, $TestResultFile, $TestErrorLog, $BuildLog, $ErrorsOnly, $WarnsOnly, $TestLog -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $TestResultsDir -Recurse -Force -ErrorAction SilentlyContinue   # 前回の XML / trx (古い結果の誤読を防ぐ)
        if ($runUiTests) {
            Remove-Item -LiteralPath $UiScreenshotDir -Recurse -Force -ErrorAction SilentlyContinue   # 前回のスクリーンショット
            Stop-SolutionProcesses   # 前回のアプリが残っていると、出力の exe がロックされ、ビルドが失敗する
        }

        if (-not $SolutionPath) {
            # ソリューション (.sln / .slnx) が、まだない。ビルドせずに、環境の問題 (終了コード 2) として返す
            $console = @("ERROR: no .sln / .slnx found in $TargetDir. Create the solution first (new_solution.py), then run the trigger again.")
            $exitCode = 2
        } else {
            # バッチは毎回別プロセスで実行される (環境変数が持ち越されない)
            # PS 5.1 は Stop 下でネイティブの stderr を例外にするため、ここだけ Continue にする
            $ErrorActionPreference = "Continue"
            try {
                $build = Invoke-BuildScript
                $console = $build.Lines
                $exitCode = $build.ExitCode
            } catch {
                $console = @("ERROR: $($_.Exception.Message)")
                $exitCode = 99
            } finally {
                $ErrorActionPreference = "Stop"
            }
        }

        if ($exitCode -eq 0) {
            Write-Host "[RESULT] Build SUCCEEDED." -ForegroundColor Green
            $result = "SUCCESS"
        } else {
            Write-Host "[RESULT] Build FAILED (exit code $exitCode)." -ForegroundColor Red
            $result = "FAILED"

            if ($exitCode -eq 1) {
                # ビルド失敗: MSBuild の errors.log (errorsonly) を渡す
                $errs = if (Test-Path $ErrorsOnly) { Get-Content $ErrorsOnly -Encoding UTF8 | Select-Object -Unique } else { @() }
                if (-not $errs) {
                    $errs = if (Test-Path $BuildLog) { Get-Content $BuildLog -Encoding UTF8 | Select-Object -Last 30 } else { @("MSBuild failed before logging.") }
                }
            } else {
                # 環境・引数エラー (2, 10-14): バッチが出した ERROR 行を渡す
                $errs = @($console | Where-Object { "$_" -match '^ERROR:' })
                if (-not $errs) { $errs = @("build script failed before MSBuild (environment/arguments).") }
                $errs = @("[ENVIRONMENT ERROR - not a source code problem]") + $errs
            }
            # 1件だけだと文字列になり連結されるため、必ず配列にする。行頭の "2>" (ノード番号) は除去
            $errs = @($errs | ForEach-Object { "$_" -replace '^\s*\d+>', '' })
            $errs = @(ConvertTo-RelativePaths $errs)
            # .NET の SDK が見つからない / 古い (MSB4236, NETSDK1045, NETSDK1141)、NuGet のソースに届かない (NU1301) は、
            # ソースの問題ではないので、環境エラーとして扱う
            if ($exitCode -eq 1 -and @($errs | Where-Object { "$_" -match '\b(MSB4236|NETSDK1045|NETSDK1141|NU1301)\b' }).Count -gt 0) {
                $errs = @("[ENVIRONMENT ERROR - not a source code problem]") + $errs
            }
            # SDK がない / 古いときは、対処 (VS Installer での追加) も伝える。NU1301 (ネットワーク) には付けない。
            # build_once.sh は、先頭の 40 行までしか出さないので、エラーが多くても届くように、2 行目 ([ENVIRONMENT ERROR] の次) に置く
            if ($exitCode -eq 1 -and @($errs | Where-Object { "$_" -match '\b(MSB4236|NETSDK1045|NETSDK1141)\b' }).Count -gt 0) {
                $errs = @($errs[0]) + @($DotnetInstallHint) + @($errs | Select-Object -Skip 1)
            }
            $errs += ""
            $errs += "Build failed with exit code: $exitCode"
            $errs | Out-File $ErrorLog -Encoding utf8
        }

        # ビルドの完了マーカー (build_error.log を書いたあとに作る)
        try {
            [System.IO.File]::WriteAllText($ResultFile, $result)
            Write-Host "[MARKER] $result -> $ResultFile" -ForegroundColor DarkGray
        } catch {
            Write-Host "[MARKER] FAILED to write $ResultFile : $($_.Exception.Message)" -ForegroundColor Red
        }

        # ---------- テスト (trigger_test.flag / trigger_uitest.flag のときだけ) ----------
        if ($runTests -or $runUiTests) {
            if ($exitCode -ne 0) {
                Write-TestMarker "BUILD_FAILED"
            } else {
                try {
                    if ($runUiTests -and $script:UiRun.Desktop -eq "separate") { Set-WpfSoftwareRendering }
                    Invoke-Tests -Ui:$runUiTests
                } catch {
                    Write-Host "[TEST] ENV_ERROR: $($_.Exception.Message)" -ForegroundColor Red
                    @("[ENVIRONMENT ERROR - not a source code problem]",
                      "ERROR: test runner failed: $($_.Exception.Message)",
                      "",
                      "Test failed: runner exception") | Out-File $TestErrorLog -Encoding utf8
                    Write-TestMarker "ENV_ERROR"
                }
            }
        }
        if ($runUiTests) {
            Restore-WpfRendering
            Stop-SolutionProcesses   # テストが残したアプリを、終了する
            Remove-Item Env:\UITEST_SOLUTION_DIR, Env:\UITEST_CONFIGURATION, Env:\UITEST_PLATFORM, Env:\UITEST_SCREENSHOT_DIR, Env:\UITEST_SLOWMO_MS -ErrorAction SilentlyContinue
        }
        Write-Host "Waiting for next trigger..." -ForegroundColor Cyan
    }
    Start-Sleep -Seconds 1
}
