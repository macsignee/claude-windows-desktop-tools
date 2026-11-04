# lib\build.ps1 - ビルドの実行 (build-windows.cmd の呼び出し)
# watch_and_build.ps1 から、ドットソース (同じスコープに読み込む) で使う。単独では実行しない。

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
