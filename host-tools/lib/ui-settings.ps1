# lib\ui-settings.ps1 - UI テストの設定 (uitest.settings の読み取りと、実行するデスクトップの解決)
# watch_and_build.ps1 から、ドットソース (同じスコープに読み込む) で使う。単独では実行しない。

# UI テストのプロジェクトの、既定の設定 (プロジェクトのフォルダの uitest.settings。`desktop=visible|separate` と `slowmo=N`)。
# フレームワークごとの違い (WPF のメニューは、別のデスクトップで開かない、など) は、ウォッチャーでなく、このファイルが持つ (add_ui_tests.py が、プロジェクトを作るときに、書く)。
# UI テストのプロジェクトが複数あるときは、1 つでも visible なら visible (visible は、どのコントロールでも動くため)。slowmo は、最大。
# 戻り値: @{ Desktop = ''|'default'|'separate'; SlowMoMs = $null|int; Source = string }
function Read-UiProjectSettings {
    $desktop = ""
    $slow = $null
    $timeout = $null
    $src = @()
    foreach ($p in @(Find-DotnetTestProjects -Ui)) {
        $f = Join-Path (Split-Path -Parent $p) "uitest.settings"
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $src += (Split-Path -Leaf (Split-Path -Parent $p)) + "/uitest.settings"
        $kv = ConvertFrom-UiSettingsText ([System.IO.File]::ReadAllText($f))
        if ($kv.Desktop -eq "default") { $desktop = "default" } elseif ($kv.Desktop -eq "separate" -and $desktop -ne "default") { $desktop = "separate" }
        if ($null -ne $kv.SlowMoMs -and ($null -eq $slow -or $kv.SlowMoMs -gt $slow)) { $slow = $kv.SlowMoMs }
        if ($null -ne $kv.TimeoutSec -and ($null -eq $timeout -or $kv.TimeoutSec -gt $timeout)) { $timeout = $kv.TimeoutSec }
    }

    return @{ Desktop = $desktop; SlowMoMs = $slow; TimeoutSec = $timeout; Source = ($src -join ", ") }
}

# `desktop=...` / `slowmo=...` / `timeout=...` / `filter=...` の行 (flag の中身と、uitest.settings で共通。# から行末は、コメント)。desktop: visible → default、invisible → separate。
# timeout: UI テストのプロジェクト 1 つあたりの制限時間 (秒)。filter: dotnet test の --filter の式 (flag だけで使う。引用符・改行は、拒否する)。
function ConvertFrom-UiSettingsText([string]$text) {
    $desktop = ""
    $slow = $null
    $timeout = $null
    $filter = ""
    $hold = $null
    $present = $false
    foreach ($line in @("$text" -split "[\r\n]+")) {
        $rawLine = ($line -replace '^\uFEFF', '')
        # filter= は、# を含み得るので、コメントを除く前に、読む。末尾が \ の値は、引数の閉じ引用符を壊すので、拒否する
        if ($rawLine -match '^\s*filter\s*=\s*([^"`]+?)\s*$') {
            if ($Matches[1] -notmatch '\\$') { $filter = $Matches[1] }
            continue
        }
        $l = ($rawLine -replace '#.*$', '').Trim()
        if ($l -match '^desktop\s*=\s*(\w+)$') {
            $w = $Matches[1].ToLowerInvariant()
            if ($w -eq "visible") { $w = "default" }
            if ($w -eq "invisible") { $w = "separate" }
            if ($w -in @("default", "separate")) { $desktop = $w }
        }
        elseif ($l -match '^slowmo\s*=\s*(\d+)$') { $slow = [int]$Matches[1] }
        elseif ($l -match '^timeout\s*=\s*(\d+)$') { $timeout = [int]$Matches[1] }
        elseif ($l -match '^hold\s*=\s*(\d+)$') { $hold = [int]$Matches[1] }
        elseif ($l -match '^present\s*=\s*1$') { $present = $true }
    }

    return @{ Desktop = $desktop; SlowMoMs = $slow; TimeoutSec = $timeout; Filter = $filter; HoldSec = $hold; Present = $present }
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
    # 制限時間: flag > uitest.settings > -UiTestTimeoutSec / WATCH_UI_TIMEOUT_SEC。filter は、flag だけ (1 回ごとの指定)
    $limit = if ($null -ne $fl.TimeoutSec) { $fl.TimeoutSec } elseif ($null -ne $proj.TimeoutSec) { $proj.TimeoutSec } else { $UiTestTimeoutSec }
    # 目視確認 (hold=): テストが、最後の状態を、この秒数だけ見せる。flag だけ (1 回ごとの指定)。制限時間は、見せる時間より、長くする (見せている間に、強制終了しない)
    $hold = if ($null -ne $fl.HoldSec) { $fl.HoldSec } else { 0 }
    if ($hold -gt 0 -and $limit -lt ($hold + 120)) { $limit = $hold + 120 }
    # プレゼン (present=1。flag だけ): UI テストを、デモとして、ユーザーのデスクトップで、ゆっくり再生する (操作する要素を、赤い枠で囲む)。操作の間の待ちは、指定がなければ、800 ms。
    $present = [bool]$fl.Present
    if ($present -and -not $fl.Filter) {
        # 再生するのは、filter= で指定したテストだけ。filter がなければ、全部を、ゆっくり再生してしまうので、プレゼンは、無効にする
        Write-Host "[UI] present=1 is ignored: it plays only the tests selected with filter=" -ForegroundColor Yellow
        $present = $false
    }
    if ($present) {
        if ($desktop -ne "default") { $desktop = "default"; $reason = "present (needs your desktop)" }
        if ($slow -le 0) { $slow = 800 }
    }
    return @{ Desktop = $desktop; SlowMoMs = $slow; TimeoutSec = $limit; Filter = $fl.Filter; HoldSec = $hold; Present = $present; Reason = $reason }
}
