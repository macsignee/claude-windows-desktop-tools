# lib\common.ps1 - 複数の機能が使う共通の関数 (外部プロセスの出力の読み取り、実行 ID、処理中の印、UI テストの所要時間)
# watch_and_build.ps1 から、ドットソース (同じスコープに読み込む) で使う。単独では実行しない。

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
# UI テストの、各段階の時刻を、.claude-logs\ui-timing.txt に追記する (ビルド完了から、UI テスト開始までに、長い空白があったときの、原因の切り分け用。実機で、14.5 分の空白が、1 回だけ出た)。
function Write-UiTiming([string]$what) {
    try {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Add-Content -LiteralPath (Join-Path $LogDir "ui-timing.txt") -Value ("{0:HH:mm:ss.fff} {1}" -f (Get-Date), $what) -Encoding UTF8
    } catch { }
}

# 実行 ID と、処理中の印 (v2.20.0)。
# - フラグの 1 行目 `run=<ID>` を読み、結果のマーカーを書く直前に、同じ ID を .claude-logs\run_id.txt に書く (Skill 側のスクリプトが、結果が「今回の実行のもの」かを照合する。
#   前の実行 (Skill が TIMEOUT で、あきらめた実行) の、古いマーカーを、今回の結果と取り違えない)。
# - 処理 (ビルド・テスト・取得・パッケージ操作) の間だけ、.claude-logs\watcher_busy.txt を置く (Skill 側が、「フラグを、15 秒以内に拾わない = 未起動」と、誤判定しない)。
function Get-RunIdFromFlag([string]$path) {
    try {
        $t = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ($t -and $t -match '(?m)^#?\s*run=(\S+)') { return $Matches[1] }   # build 系: 1 行目 run=<ID> / gtest・package: コメント行 # run=<ID> (古いウォッチャーが、操作やタグと取り違えない形)
    } catch { }
    return ""
}

function Write-RunId {
    if (-not $script:CurrentRunId) { return }
    try {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        # 1 行目 (run=) だけを、照合に使う (古い Skill は、1 行目しか読まない)。2 行目以降は、結果の自己記述 (v2.29.0。いつ、どの実行の、どの入力の結果か、と、ウォッチャーの版)。
        $info = "run=$($script:CurrentRunId)`r`nwatcher=$($script:WatcherVersion)`r`nkind=$($script:CurrentKind)`r`ninput=$TargetDir`r`nfinished=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
        [System.IO.File]::WriteAllText((Join-Path $LogDir "run_id.txt"), $info)
    } catch { }
}

function Set-WatcherBusy([string]$what) {
    try {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $LogDir "watcher_busy.txt"), "$what`r`nstarted=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n")
    } catch { }
}

function Clear-WatcherBusy {
    Remove-Item -LiteralPath (Join-Path $LogDir "watcher_busy.txt") -ErrorAction SilentlyContinue
}
