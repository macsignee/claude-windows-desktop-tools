<#
.SYNOPSIS
  フラグファイルを監視し、build-windows.cmd でビルド (必要ならテストも) して結果を通知ファイルに書く。

.DESCRIPTION
  VS 検出・環境読み込み・MSBuild 実行は build-windows.cmd が担当する。
  このスクリプトは次を行う:

  [ビルドのみ]  <TargetDir>\trigger_build.flag
    - 失敗時のみ <TargetDir>\build_error.log を作成 (Claude Code が読む)
    - ビルド終了時に <TargetDir>\build_result.txt へ SUCCESS / FAILED を書く (完了マーカー)
      build_error.log を書いたあとに作るので、マーカーが現れた時点でログは読める状態

  [ビルド + テスト]  <TargetDir>\trigger_test.flag
    - 上記と同じビルドを行い (build_result.txt も書く)、成功したら GoogleTest の exe を実行する
    - 完了マーカーは <TargetDir>\test_result.txt (最後に書く):
        PASSED       全テスト成功
        FAILED       テスト失敗 (または異常終了)。詳細は test_error.log
        TIMEOUT      テストが制限時間内に終わらない。test_error.log に対象 exe
        BUILD_FAILED ビルド失敗のためテスト未実行。詳細は build_error.log
        ENV_ERROR    テスト exe が見つからない等。test_error.log 先頭が [ENVIRONMENT ERROR ...]
    - テスト exe は <ソリューションフォルダ>\<x64|Win32|ARM64>\<Configuration>\ から、
      名前が -TestExePattern に一致するものを実行する

  [GoogleTest のソース取得]  <TargetDir>\trigger_gtest.flag  (ビルド・テストとは独立)
    - GitHub から GoogleTest (固定タグ) を取得して、<TargetDir>\ThirdParty\googletest\ (include\, src\, LICENSE, VERSION.txt) に置く。
      git があれば git clone --depth 1、なければ zip のダウンロード (Windows 側が、GitHub に届く必要がある)。
    - フラグの 1 行目に、タグを書ける (例: v1.17.0)。空なら -GtestTag (既定 v1.17.0)。
      許可する形: v1.17.0 / release-1.12.1 (英数字だけの、決まった形。コマンドへ渡るため)
    - 同じタグが、すでに置かれていれば、何もせずに OK (冪等)
    - 完了マーカーは <TargetDir>\gtest_result.txt (最後に書く): OK / FAILED (詳細は gtest_error.log。環境の問題として扱う)
    - ソリューションに含める静的ライブラリ (gtest.vcxproj) は、Claude 側が作る。ここは、取得だけ

  このスクリプトの終了コード:
    2 引数不正 (ソリューションや build-windows.cmd が見つからない)
    3 同じプロジェクトフォルダで、すでに別のウォッチャーが動いている (二重起動の拒否)

  build-windows.cmd の終了コード:
    0 成功 / 1 ビルド失敗 / 2 引数不正 / 10 vswhere なし / 11 VS(C++)なし
    12 VsDevCmd なし / 13 VsDevCmd 失敗 / 14 cl.exe or MSBuild.exe が PATH にない
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$TargetDir,

    [Parameter(Mandatory=$true)]
    [string]$SolutionPath,

    [ValidateSet("x64","Win32","x86","ARM64")]
    [string]$Platform = "x64",

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

    # テスト実行時の作業フォルダ。省略時は exe のあるフォルダ
    [string]$TestWorkingDir,

    # trigger_gtest.flag の 1 行目が空のときに取得する、GoogleTest のタグ
    [string]$GtestTag = "v1.17.0"
)

$ErrorActionPreference = "Stop"

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
if (-not [System.IO.Path]::IsPathRooted($SolutionPath)) {
    $SolutionPath = Join-Path $TargetDir $SolutionPath
}
if (-not (Test-Path -LiteralPath $SolutionPath)) {
    Write-Host "ERROR: target not found: $SolutionPath" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $BuildScript)) {
    Write-Host "ERROR: build script not found: $BuildScript" -ForegroundColor Red
    exit 2
}
if (-not $LogDir) { $LogDir = Join-Path $TargetDir ".claude-logs" }
$LogDir = $LogDir.TrimEnd('\')
$SolutionDir = Split-Path -Parent $SolutionPath

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
$ResultFile      = Join-Path $TargetDir "build_result.txt"
$ErrorLog        = Join-Path $TargetDir "build_error.log"
$TestResultFile  = Join-Path $TargetDir "test_result.txt"
$TestErrorLog    = Join-Path $TargetDir "test_error.log"
$BuildLog        = Join-Path $LogDir "build.log"
$ErrorsOnly      = Join-Path $LogDir "errors.log"
$WarnsOnly       = Join-Path $LogDir "warnings.log"
$TestLog         = Join-Path $LogDir "test.log"
$GtestTriggerFile = Join-Path $TargetDir "trigger_gtest.flag"
$GtestResultFile  = Join-Path $TargetDir "gtest_result.txt"
$GtestErrorLog    = Join-Path $TargetDir "gtest_error.log"
$GtestRepoUrl     = "https://github.com/google/googletest"

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

# ---------- ビルドの実行 (build-windows.cmd) ----------
# build-windows.cmd を、専用の「表示しない」コンソールで実行し、出力をパイプで受け取って、このウィンドウに、1 行ずつ流す。
#   - ビルド用の、別のコンソール (ウィンドウ / タブ) が開かない。出力は、このウィンドウ (テストの出力と同じ画面) だけに出る。
#   - バッチの chcp 65001 / chcp 932 が、このウィンドウの文字コードを、変えない (表示が乱れない)。
# 戻り値: @{ Lines = 出力の行 (標準エラーを含む); ExitCode = バッチの終了コード }
function Invoke-BuildScript {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    # cmd /c の引用符の規則: 全体を、もう一度、引用符で囲む (先頭の " と、最後の " が、取り除かれる)。
    # 2>&1 で標準エラーも標準出力にまとめて、読み取りを 1 本にする (パイプが詰まって止まるのを避ける)。
    $psi.Arguments = '/c ""' + $BuildScript + '" "' + $SolutionPath + '" "' + $Platform + '" "' + $Configuration +
        '" "' + $MSBuildTarget + '" "' + $LogDir + '" 2>&1"'
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
    $platDir = switch ($Platform.ToLower()) { "x64" { "x64" } "arm64" { "ARM64" } default { "Win32" } }
    # 出力先は <ソリューションフォルダ>\<x64|Win32|ARM64>\<Configuration>\
    $dir = Join-Path (Join-Path $SolutionDir $platDir) $Configuration
    if (Test-Path -LiteralPath $dir) {
        return @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match $TestExePattern } | Sort-Object Name)
    }
    return @()
}

# 戻り値: @{ Timeout = bool; ExitCode = int; Output = string[] }
function Invoke-TestExe($exe) {
    $outTmp = Join-Path $LogDir "test_stdout.tmp"
    $errTmp = Join-Path $LogDir "test_stderr.tmp"
    Remove-Item -LiteralPath $outTmp, $errTmp -ErrorAction SilentlyContinue
    $workDir = if ($TestWorkingDir) { $TestWorkingDir } else { $exe.DirectoryName }

    $spArgs = @{
        FilePath               = $exe.FullName
        WorkingDirectory       = $workDir
        RedirectStandardOutput = $outTmp
        RedirectStandardError  = $errTmp
        PassThru               = $true
        NoNewWindow            = $true
    }
    if ($TestArgs) { $spArgs["ArgumentList"] = $TestArgs }
    $p = Start-Process @spArgs
    $null = $p.Handle   # PS 5.1: これがないと ExitCode が取れないことがある
    $timedOut = $false
    if (-not $p.WaitForExit($TestTimeoutSec * 1000)) {
        $timedOut = $true
        # 子プロセスごと強制終了。Stop 下でネイティブの stderr が例外になるため握りつぶす
        try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch { }
        try { $p.Kill() } catch { }
        # 終了待ちにも上限を付ける (無期限に待つとウォッチャー全体が止まる)
        [void]$p.WaitForExit(5000)
    }
    $exitCode = if ($timedOut) { $null } else { $p.ExitCode }

    # テスト出力は ANSI(CP932) のことがあるため Default で読む
    $lines = @()
    foreach ($f in @($outTmp, $errTmp)) {
        if (Test-Path -LiteralPath $f) { $lines += @(Get-Content -LiteralPath $f -Encoding Default) }
    }
    Remove-Item -LiteralPath $outTmp, $errTmp -ErrorAction SilentlyContinue
    return @{ Timeout = $timedOut; ExitCode = $exitCode; Output = $lines }
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

# ビルド成功後のテスト実行。test_result.txt を最後に書く。
function Invoke-Tests {
    $exes = @(Find-TestExes)
    if ($exes.Count -eq 0) {
        Write-Host "[TEST] ENV_ERROR: no test exe matching '$TestExePattern' under $SolutionDir" -ForegroundColor Red
        @("[ENVIRONMENT ERROR - not a source code problem]",
          "ERROR: no test exe matching '$TestExePattern' found for $Configuration|$Platform under $SolutionDir",
          "",
          "Test failed: test exe not found") | Out-File $TestErrorLog -Encoding utf8
        Write-TestMarker "ENV_ERROR"
        return
    }

    $report = @()
    $failed = $false
    $timedOut = $false
    $invalid = $false
    $all = @()
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
    $all | Out-File $TestLog -Encoding utf8

    if ($timedOut) {
        Write-Host "[RESULT] Tests TIMEOUT." -ForegroundColor Red
        $report += ""; $report += "Test timeout: ${TestTimeoutSec}s"
        @(ConvertTo-RelativePaths $report) | Out-File $TestErrorLog -Encoding utf8
        Write-TestMarker "TIMEOUT"
    } elseif ($failed) {
        Write-Host "[RESULT] Tests FAILED." -ForegroundColor Red
        $report += ""; $report += "Tests failed"
        @(ConvertTo-RelativePaths $report) | Out-File $TestErrorLog -Encoding utf8
        Write-TestMarker "FAILED"
    } elseif ($invalid) {
        Write-Host "[RESULT] Tests ENV_ERROR (no gtest summary)." -ForegroundColor Red
        @(ConvertTo-RelativePaths (@("[ENVIRONMENT ERROR - not a source code problem]") + $report + @("", "Test failed: no gtest summary (check -TestArgs / is this a GoogleTest exe?)"))) |
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
Write-Host " Target       : $SolutionPath" -ForegroundColor Cyan
Write-Host " Build        : $Configuration|$Platform  /t:$MSBuildTarget" -ForegroundColor Cyan
Write-Host " Build script : $BuildScript" -ForegroundColor Cyan
Write-Host " Logs         : $LogDir" -ForegroundColor Cyan
Write-Host " Triggers     : trigger_build.flag (build) / trigger_test.flag (build + test) / trigger_gtest.flag (fetch GoogleTest)" -ForegroundColor Cyan
Write-Host " Test exe     : $TestExePattern (timeout ${TestTimeoutSec}s)" -ForegroundColor Cyan
Write-Host " QuickEdit    : $QuickEditStatus" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# ---------- 監視ループ ----------
while ($true) {
    # GoogleTest のソース取得 (ビルドの前提になるので、先に処理する)
    if (Test-Path -LiteralPath $GtestTriggerFile) {
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Trigger detected (gtest fetch)!" -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500   # Claude 側の書き込み完了待ち
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

    $runTests = Test-Path -LiteralPath $TestTriggerFile
    if ($runTests -or (Test-Path -LiteralPath $TriggerFile)) {
        $mode = if ($runTests) { "build + test" } else { "build" }
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Trigger detected ($mode)! Starting build..." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 500   # Claude 側の書き込み完了待ち
        Remove-Item -LiteralPath $TriggerFile, $TestTriggerFile -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Remove-Item -LiteralPath $ResultFile, $ErrorLog, $TestResultFile, $TestErrorLog, $BuildLog, $ErrorsOnly, $WarnsOnly, $TestLog -ErrorAction SilentlyContinue

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

        # ---------- テスト (trigger_test.flag のときだけ) ----------
        if ($runTests) {
            if ($exitCode -ne 0) {
                Write-TestMarker "BUILD_FAILED"
            } else {
                try {
                    Invoke-Tests
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
        Write-Host "Waiting for next trigger..." -ForegroundColor Cyan
    }
    Start-Sleep -Seconds 1
}
