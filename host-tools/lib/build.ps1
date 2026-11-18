# lib\build.ps1 - ビルドの実行 (build-windows.cmd の呼び出し)
# watch_and_build.ps1 から、ドットソース (同じスコープに読み込む) で使う。単独では実行しない。

# build-windows.cmd を、専用の「表示しない」コンソールで実行し、出力をパイプで受け取って、このウィンドウに、1 行ずつ流す。
#   - ビルド用の、別のコンソール (ウィンドウ / タブ) が開かない。出力は、このウィンドウ (テストの出力と同じ画面) だけに出る。
#   - バッチの chcp 65001 / chcp 932 が、このウィンドウの文字コードを、変えない (表示が乱れない)。
# 戻り値: @{ Lines = 出力の行 (標準エラーを含む); ExitCode = バッチの終了コード }
function Invoke-BuildScript([string]$Target = "") {
    if (-not $Target) { $Target = $SolutionPath }   # 省略時は、ソリューション (プロジェクト単位のビルド (project=) のときだけ、プロジェクトのファイルを渡す)
    # 起動後に、build-windows.cmd が消えた・別名になった場合: cmd /c は、終了コード 1 (ビルド失敗と区別できない) などで返る。環境エラー (2) として返す
    if (-not (Test-Path -LiteralPath $BuildScript)) {
        return @{ Lines = @("ERROR: build script not found: $BuildScript (restore it, e.g. with copy-host-tools.sh, then run again)."); ExitCode = 2 }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    # cmd /c の引用符の規則: 全体を、もう一度、引用符で囲む (先頭の " と、最後の " が、取り除かれる)。
    # 2>&1 で標準エラーも標準出力にまとめて、読み取りを 1 本にする (パイプが詰まって止まるのを避ける)。
    $psi.Arguments = '/c ""' + $BuildScript + '" "' + $Target + '" "' + $Platform + '" "' + $Configuration +
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

# ---------- プロジェクト単位 (flag の project=<名前>) ----------
# trigger_build.flag / trigger_test.flag / trigger_uitest.flag の中身に `project=<名前>` と書くと、その 1 回だけ、ソリューション全体ではなく、
# <名前> と、そのテストのプロジェクトだけを、ビルド・実行する (書かなければ、これまでどおり、ソリューション全体)。
# テストのプロジェクトの名前は、<名前> から推測する: C++ は <名前>Test、.NET は <名前>.Tests (<名前>Tests も可)、UI テストは <名前>.UITests。
$script:Scope = $null          # project= を指定した回だけ: @{ Name; Main; Test (配列); Error }。なければ $null
$script:ScopeActive = $false   # テストの段階で、$ProjectPaths を、スコープのテストのプロジェクトだけに絞っている間、$true

# フラグの中身から、project= の値を取り出す (なければ空)。# 以降は、コメント。
function Get-FlagProjectName([string]$text) {
    if (-not $text) { return "" }
    foreach ($rawLine in ($text -split "`r?`n")) {
        $l = ($rawLine -replace '#.*$', '').Trim()
        if ($l -match '^project\s*=\s*(\S+)$') { return $Matches[1] }
    }
    return ""
}

# <名前> から、ビルドするプロジェクト (Main) と、テストのプロジェクト (Test。配列) を、ソリューションのプロジェクト ($ProjectPaths) から決める。
# $ui が $true のときは、UI テストのプロジェクトを選ぶ。見つからないときは、Error に、理由を書く。
function Resolve-ProjectScope([string]$name, [bool]$ui) {
    $r = @{ Name = $name; Main = $null; Test = @(); Error = "" }
    if ($name -notmatch '^[A-Za-z0-9_.\-]+$') {
        $r.Error = "invalid project name '$name' (use letters, digits, '_', '.', '-')"
        return $r
    }
    $suffixes = if ($ui) { @(".UITests", "UITests", ".UiTests", "UiTests") } else { @("Test", "Tests", ".Tests") }
    $names = @()
    foreach ($p in $ProjectPaths) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($p)
        $names += $base
        if ($base -ieq $name) { if (-not $r.Main) { $r.Main = $p }; continue }
        foreach ($s in $suffixes) {
            if ($base -ieq ($name + $s)) { $r.Test += $p; break }
        }
    }
    if (-not $r.Main -and $r.Test.Count -eq 0) {
        $r.Error = "no project named '$name' (or its test project) in the solution. Projects: " + (($names | Sort-Object -Unique) -join ", ")
    }
    return $r
}

# プロジェクト単位のビルド: Main、続けて Test を、1 つずつ MSBuild に渡す (最初の失敗で止まる)。戻り値は、Invoke-BuildScript と同じ形。
# 単独のプロジェクトを MSBuild に渡すと、SolutionDir が空になり、OutDir ($(SolutionDir)...) が、ソリューション全体のときと、別の場所になる。
# そのため、環境変数 SolutionDir を、ソリューションのフォルダにして、渡す (MSBuild は、環境変数を、プロパティとして読む。引用符の問題がない)。
function Invoke-ScopedBuild {
    $sc = $script:Scope
    if ($sc.Error) { return @{ Lines = @("ERROR: project scope: $($sc.Error)"); ExitCode = 2 } }
    $targets = @()
    if ($sc.Main) { $targets += $sc.Main }
    $targets += @($sc.Test)
    $all = @()
    $prev = $env:SolutionDir
    $env:SolutionDir = $SolutionDir.TrimEnd('\') + '\'
    try {
        foreach ($t in $targets) {
            Write-Host "[SCOPE] project=$($sc.Name): building $([System.IO.Path]::GetFileName($t)) ..." -ForegroundColor DarkCyan
            $b = Invoke-BuildScript -Target $t
            $all += @($b.Lines)
            if ($b.ExitCode -ne 0) { return @{ Lines = $all; ExitCode = $b.ExitCode } }
        }
    } finally {
        if ($null -eq $prev) { Remove-Item Env:\SolutionDir -ErrorAction SilentlyContinue } else { $env:SolutionDir = $prev }
    }
    return @{ Lines = $all; ExitCode = 0 }
}
