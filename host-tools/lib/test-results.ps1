# lib\test-results.ps1 - テストの結果の解析 (trx の集計、失敗行の抽出、ハングの判定、完了マーカーの書き出し)
# watch_and_build.ps1 から、ドットソース (同じスコープに読み込む) で使う。単独では実行しない。

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
    Write-RunId
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
