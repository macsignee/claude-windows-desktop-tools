<#
.SYNOPSIS
  フラグファイルを監視し、build-windows.cmd でビルド (必要ならテストも) して結果を通知ファイルに書く。
  ソリューションの中身 (C++ の .vcxproj / .NET の .csproj) を見て、ビルドとテストの方法を決める (C++ のみ / .NET のみ / 混在)。

.DESCRIPTION
  VS 検出・環境読み込み・MSBuild 実行は build-windows.cmd が担当する。
  機能ごとの関数 (GoogleTest の取得・パッケージ操作・テストの実行・UI テストの基盤など) は、同じフォルダの lib\*.ps1 に分かれていて、
  このスクリプトが、起動時に読み込む (lib\ が欠けると、起動しない)。
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
    - テストには、環境変数で、実行環境を渡す: UITEST_SOLUTION_DIR / UITEST_CONFIGURATION / UITEST_PLATFORM / UITEST_SCREENSHOT_DIR / UITEST_SLOWMO_MS / UITEST_HOLD_SEC (flag の hold=。目視確認のために、テストが、最後の状態を見せる秒数)
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
    2 引数不正 (-SolutionPath を明示したのに見つからない、build-windows.cmd が見つからない、lib\*.ps1 が見つからない)
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

# 環境変数 GTEST_* (GTEST_FILTER、GTEST_REPEAT、GTEST_SHUFFLE など) を、子プロセスに渡さない。
# GoogleTest は、これらを自動で読む。ウォッチャーの親のコマンドプロンプトに残っていると、全テストが 0 件になる (GTEST_FILTER=NoSuchTest* で確認) など、
# 原因の分かりにくい失敗になる。絞り込みは、-TestArgs (--gtest_filter=...) で指定する。
$script:RemovedGtestEnv = @(Get-ChildItem Env: | Where-Object { $_.Name -like 'GTEST_*' } | ForEach-Object { $_.Name })
foreach ($n in $script:RemovedGtestEnv) { Remove-Item "Env:\$n" -ErrorAction SilentlyContinue }
if ($script:RemovedGtestEnv.Count -gt 0) {
    Write-Host ("[ENV] removed from the watcher process: " + ($script:RemovedGtestEnv -join ", ") + " (use -TestArgs --gtest_filter=... instead)") -ForegroundColor Yellow
}

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

# ウォッチャーの版 (v2.29.0): install.sh が、配布先に VERSION を置く。Skill 側 (*_once.sh) が、自分の版と照合する (不一致は、警告 (NOTE) だけ)。
$script:WatcherVersion = "unknown"
try {
    $verDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $verFile = Join-Path $verDir "VERSION"
    if (Test-Path -LiteralPath $verFile) {
        $verText = ((Get-Content -LiteralPath $verFile -TotalCount 1 -ErrorAction Stop) -as [string]).Trim().TrimStart([char]0xFEFF)
        if ($verText -match '^[0-9A-Za-z._+-]{1,32}$') { $script:WatcherVersion = $verText }
    }
} catch { }
$script:CurrentKind = ""

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
$WatcherMutex = New-Object System.Threading.Mutex($true, "Local\claude-windows-desktop-tools-watcher-$pathHash", [ref]$createdNew)
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

# ---------- 機能ごとの関数 (lib\*.ps1。同じスコープに読み込む) ----------
$LibDir = Join-Path $PSScriptRoot "lib"
foreach ($libName in @("gtest", "package", "common", "build", "test-results", "ui-settings", "uitest-desktop", "tests")) {
    $libPath = Join-Path $LibDir "$libName.ps1"
    if (-not (Test-Path -LiteralPath $libPath)) {
        Write-Host "ERROR: library script not found: $libPath (copy the whole host-tools folder, including lib\)" -ForegroundColor Red
        exit 2
    }
    . $libPath
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
Write-Host " Version      : $($script:WatcherVersion)  (the Skill side compares it with its own; a mismatch is only a NOTE)" -ForegroundColor Cyan
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
Clear-WatcherBusy   # 前回のウォッチャーが、処理の途中で異常終了したときの、処理中の印を、消す

# ---------- 監視ループ ----------
while ($true) {
    # GoogleTest のソース取得 (ビルドの前提になるので、先に処理する)
    if (Test-Path -LiteralPath $GtestTriggerFile) {
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Trigger detected (gtest fetch)!" -ForegroundColor Yellow
        Set-WatcherBusy "gtest fetch"
        Start-Sleep -Milliseconds 500   # Claude 側の書き込み完了待ち
        Update-SolutionState
        $gtestTagLine = ""
        $script:CurrentRunId = Get-RunIdFromFlag $GtestTriggerFile   # Skill 側 (gtest_once.sh) の実行 ID。タグは 1 行目 (空のこともある)、ID は 2 行目 (# run=...)
        $script:CurrentKind = "gtest"
        Set-WatcherBusy "gtest fetch run=$($script:CurrentRunId)"
        try { $gtestTagLine = "$(Get-Content -LiteralPath $GtestTriggerFile -TotalCount 1 -ErrorAction Stop)" } catch { }
        if ($gtestTagLine -match '^\s*#') { $gtestTagLine = "" }
        Remove-Item -LiteralPath $GtestTriggerFile, $GtestResultFile, $GtestErrorLog -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        try {
            Invoke-GtestFetch $gtestTagLine
        } catch {
            Write-GtestFailure @("ERROR: gtest fetch failed: $($_.Exception.Message)")
        }
        Clear-WatcherBusy
        Write-Host "Waiting for next trigger..." -ForegroundColor Cyan
    }

    # パッケージの操作 (NuGet / vcpkg / ソースの取得)。ビルドの前提になるので、ビルドより先に処理する
    if (Test-Path -LiteralPath $PackageTriggerFile) {
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Trigger detected (package)!" -ForegroundColor Yellow
        Set-WatcherBusy "package"
        Start-Sleep -Milliseconds 500   # Claude 側の書き込み完了待ち
        Update-SolutionState
        $packageLines = @()
        $script:CurrentRunId = Get-RunIdFromFlag $PackageTriggerFile   # Skill 側 (package_once.sh) の実行 ID (コメント行 # run=...。操作としては、無視される)
        $script:CurrentKind = "package"
        Set-WatcherBusy "package run=$($script:CurrentRunId)"
        try { $packageLines = @(Get-Content -LiteralPath $PackageTriggerFile -ErrorAction Stop) } catch { }
        Remove-Item -LiteralPath $PackageTriggerFile, $PackageResultFile, $PackageErrorLog, $PackageOutputFile -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        try {
            Invoke-PackageOps $packageLines
        } catch {
            @("[ENVIRONMENT ERROR - not a source code problem]", "ERROR: package operation failed: $($_.Exception.Message)") | Out-File $PackageErrorLog -Encoding utf8
            Write-PackageMarker "FAILED"
        }
        Clear-WatcherBusy
        Write-Host "Waiting for next trigger..." -ForegroundColor Cyan
    }

    $runUiTests = Test-Path -LiteralPath $UiTestTriggerFile
    $runTests = (-not $runUiTests) -and (Test-Path -LiteralPath $TestTriggerFile)   # 両方あるときは、UI テストを先に処理する (もう一方のフラグは、残して、次の周回で処理)
    if ($runUiTests -or $runTests -or (Test-Path -LiteralPath $TriggerFile)) {
        $mode = if ($runUiTests) { "build + UI test" } elseif ($runTests) { "build + test" } else { "build" }
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Trigger detected ($mode)! Starting build..." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500   # Claude 側の書き込み完了待ち
        Update-SolutionState   # 起動後に、ソリューションができた・プロジェクトが増えた (テストの後付けなど) 場合に備え、トリガーごとに、決め直す
        $script:CurrentRunId = Get-RunIdFromFlag $(if ($runUiTests) { $UiTestTriggerFile } elseif ($runTests) { $TestTriggerFile } else { $TriggerFile })   # フラグを消す前に、実行 ID を読む
        $script:CurrentKind = $(if ($runUiTests) { "uitest" } elseif ($runTests) { "test" } else { "build" })
        Set-WatcherBusy "$mode run=$($script:CurrentRunId)"
        if ($runUiTests) {
            $uiFlagText = ""
            try { $uiFlagText = Get-Content -LiteralPath $UiTestTriggerFile -Raw -Encoding UTF8 -ErrorAction Stop } catch { $uiFlagText = "" }   # フラグを消す前に、1 回ごとの指定 (desktop= / slowmo=) を読む
            if ($null -eq $uiFlagText) { $uiFlagText = "" }   # 空ファイル (0 バイト) では、Get-Content -Raw が $null を返す場合があるため ($null -replace は配列になり、Trim() で失敗する)
            $script:UiRun = Resolve-UiRun $uiFlagText
            Remove-Item -LiteralPath (Join-Path $LogDir "ui-timing.txt") -ErrorAction SilentlyContinue   # 今回の実行の、時刻の記録だけを残す
            Write-UiTiming "trigger detected; settings resolved (flag: $(($uiFlagText -replace '\s+', ' ').Trim())); the build starts next"
            Write-Host "[UI] desktop: $($script:UiRun.Desktop) ($($script:UiRun.Reason)), slow-motion: $($script:UiRun.SlowMoMs) ms, timeout: $($script:UiRun.TimeoutSec) s, hold: $($script:UiRun.HoldSec) s, present: $($script:UiRun.Present), filter: $(if ($script:UiRun.Filter) { $script:UiRun.Filter } else { '(all)' })" -ForegroundColor Cyan
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
        Write-RunId
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
                    if ($runUiTests) { Write-UiTiming "build done; starting the UI test phase (desktop: $($script:UiRun.Desktop))" }
                    if ($runUiTests -and $script:UiRun.Desktop -eq "separate") { Set-WpfSoftwareRendering }
                    if ($runUiTests) { Write-UiTiming "WPF rendering setting done; calling Invoke-Tests" }
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
            Remove-Item Env:\UITEST_SOLUTION_DIR, Env:\UITEST_CONFIGURATION, Env:\UITEST_PLATFORM, Env:\UITEST_SCREENSHOT_DIR, Env:\UITEST_SLOWMO_MS, Env:\UITEST_HOLD_SEC, Env:\UITEST_PRESENT -ErrorAction SilentlyContinue
        }
        Clear-WatcherBusy
        Write-Host "Waiting for next trigger..." -ForegroundColor Cyan
    }
    Start-Sleep -Seconds 1
}
