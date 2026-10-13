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
    [string]$TestWorkingDir
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
Write-Host " Triggers     : trigger_build.flag (build) / trigger_test.flag (build + test)" -ForegroundColor Cyan
Write-Host " Test exe     : $TestExePattern (timeout ${TestTimeoutSec}s)" -ForegroundColor Cyan
Write-Host " QuickEdit    : $QuickEditStatus" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# ---------- 監視ループ ----------
while ($true) {
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
            $console = & $BuildScript $SolutionPath $Platform $Configuration $MSBuildTarget $LogDir 2>&1 |
                ForEach-Object { Write-Host $_; $_ }
            $exitCode = $LASTEXITCODE
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
