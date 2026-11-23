# lib\git-remote.ps1 - Windows の git.exe による、リモートの操作 (状態・fetch・push)。trigger_git.flag で、WSL (Skill: git-remote) から依頼される。
# watch_and_build.ps1 から、ドットソース (同じスコープに読み込む) で使う。単独では実行しない。
#
# なぜ Windows の git.exe か: 認証は、Windows の Git Credential Manager (Visual Studio の Git と同じ保管先)。GitHub 以外のリモートでも、VS と同じ認証で通る。
# WSL の git からは、その認証が見えない。push は、インデックスも作業フォルダも書き換えないので、VS や WSL の git と、競合しない。
#
# 操作 (フラグの 1 行 1 操作。上から実行し、失敗したら、そこで止める):
#   status                                     読み取りだけ。BRANCH / UPSTREAM / REMOTE / AHEAD / BEHIND / UNCOMMITTED / push される予定のコミット
#   fetch [<リモート名>]                       省略すると、すべてのリモート
#   push [remote=<名前>] [set-upstream] [allow-main]   現在のブランチだけを、同じ名前で push する
# 持たない操作 (フラグに書かれても、断る): 強制 push・ブランチやタグの削除・タグの一括 push・mirror・pull・merge・rebase。
# 結果: git_result.txt = OK / AUTH_REQUIRED / REJECTED / FAILED (最後に書く)。git_output.txt (事実)、失敗時のみ git_error.log。

$script:GitTimeoutSec = 120   # git の 1 コマンドの上限。超えたら、プロセスを終了させる (認証の待ち・ネットワークの停止で、ウォッチャーが固まらないように)

function Write-GitMarker([string]$value) {
    Write-RunId
    try {
        [System.IO.File]::WriteAllText($GitResultFile, $value)
        Write-Host "[MARKER] $value -> $GitResultFile" -ForegroundColor DarkGray
    } catch {
        Write-Host "[MARKER] FAILED to write $GitResultFile : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# git.exe を探す: PATH → 通常のインストール先 → Visual Studio に同梱のもの。見つからなければ、$null
function Find-GitExe {
    $cmd = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Git\cmd\git.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe")
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    try {
        $vsGit = Get-ChildItem -Path (Join-Path $env:ProgramFiles "Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe") -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($vsGit) { return $vsGit.FullName }
    } catch { }
    return $null
}

# リモートの URL に埋め込まれた認証情報 (https://user:token@host/...) を、伏せる
function Hide-GitUrlSecret([string]$text) {
    return ($text -replace '(://)[^/@\s]+@', '$1***@')
}

function ConvertTo-GitArg([string]$s) {
    if ($s -match '^[A-Za-z0-9._/=:@{}^~-]+$') { return $s }
    return '"' + ($s -replace '"', '\"') + '"'
}

# git を 1 回実行する。入力待ちをしない (GIT_TERMINAL_PROMPT=0、GCM_INTERACTIVE=never: 認証が要るときは、待たずに失敗する)。時間切れは、プロセスを終了させる。
# 戻り値: @{ Code; Out (行の配列); TimedOut }
function Invoke-GitProc([string]$gitExe, [string[]]$gitArgs) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $gitExe
    $psi.Arguments = (($gitArgs | ForEach-Object { ConvertTo-GitArg $_ }) -join ' ')
    $psi.WorkingDirectory = $TargetDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0"
    $psi.EnvironmentVariables["GCM_INTERACTIVE"] = "never"
    $psi.EnvironmentVariables["LC_ALL"] = "C"   # git の文言を英語にそろえる (結果の分類のため)
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $so = $p.StandardOutput.ReadToEndAsync()
    $se = $p.StandardError.ReadToEndAsync()
    $timedOut = $false
    if (-not $p.WaitForExit($script:GitTimeoutSec * 1000)) {
        $timedOut = $true
        try { $p.Kill() } catch { }
        [void]$p.WaitForExit(5000)
    }
    $text = ""
    try { $text = $so.Result + $se.Result } catch { }
    $lines = @($text -split "`r?`n" | Where-Object { $_ -ne "" })
    $code = if ($timedOut) { -1 } else { $p.ExitCode }
    return @{ Code = $code; Out = $lines; TimedOut = $timedOut }
}

# 失敗の出力から、種類を決める: AUTH_REQUIRED (認証) / REJECTED (リモートの拒否) / FAILED (そのほか)
function Get-GitFailKind([string]$text) {
    if ($text -match 'Authentication failed|could not read (Username|Password)|terminal prompts disabled|Permission denied \(publickey|returned error: 40[13]|HTTP/\S+ 40[13]|Logon failed|password authentication was removed|Permission to .* denied|Unable to (get|acquire).*(token|credential)|no credential|GCM') { return "AUTH_REQUIRED" }
    if ($text -match 'non-fast-forward|\[rejected\]|\[remote rejected\]|fetch first|protected branch|failed to push some refs|pre-receive hook declined|Updates were rejected') { return "REJECTED" }
    return "FAILED"
}

function New-GitResult([bool]$ok, [string]$marker, [string[]]$lines) {
    return @{ Ok = $ok; Marker = $marker; Lines = @($lines) }
}

# 読み取りだけの 1 コマンド (出力の 1 行目だけが要るとき)。失敗したら、空文字
function Get-GitLine([string]$gitExe, [string[]]$gitArgs) {
    $r = Invoke-GitProc $gitExe $gitArgs
    if ($r.Code -ne 0 -or $r.Out.Count -eq 0) { return "" }
    return [string]$r.Out[0]
}

function Get-GitStateLines([string]$gitExe) {
    $lines = @()
    $top = Get-GitLine $gitExe @("rev-parse", "--show-toplevel")
    if (-not $top) { return @{ Ok = $false; Lines = @("not a git repository: $TargetDir") } }
    $lines += "REPO: $top"
    $branch = Get-GitLine $gitExe @("symbolic-ref", "--short", "-q", "HEAD")
    $lines += "BRANCH: $(if ($branch) { $branch } else { '(detached HEAD)' })"
    $up = Get-GitLine $gitExe @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
    $lines += "UPSTREAM: $(if ($up) { $up } else { '(none)' })"
    $remotes = Invoke-GitProc $gitExe @("remote")
    foreach ($rn in $remotes.Out) {
        if ($rn -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { continue }
        $url = Get-GitLine $gitExe @("remote", "get-url", $rn)
        $lines += "REMOTE: $rn $(Hide-GitUrlSecret $url)"
    }
    if ($remotes.Out.Count -eq 0) { $lines += "REMOTE: (none)" }
    if ($up) {
        $cnt = Get-GitLine $gitExe @("rev-list", "--left-right", "--count", "HEAD...@{u}")
        if ($cnt -match '^(\d+)\s+(\d+)$') { $lines += "AHEAD: $($Matches[1])"; $lines += "BEHIND: $($Matches[2])" }
        $log = Invoke-GitProc $gitExe @("log", "--oneline", "-n", "20", "@{u}..HEAD")
    } else {
        $log = Invoke-GitProc $gitExe @("log", "--oneline", "-n", "20", "HEAD", "--not", "--remotes")
    }
    if ($log.Code -eq 0 -and $log.Out.Count -gt 0) {
        $lines += "TO_PUSH: $($log.Out.Count) commit(s) (the newest 20 at most)"
        foreach ($l in $log.Out) { $lines += "  $l" }
    }
    $st = Invoke-GitProc $gitExe @("status", "--porcelain")
    $lines += "UNCOMMITTED: $($st.Out.Count) file(s) (a push sends commits only)"
    return @{ Ok = $true; Lines = $lines }
}

function Invoke-GitFetchOp([string]$gitExe, [string]$remote) {
    if ($remote) {
        if ($remote -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { return (New-GitResult $false "FAILED" @("REFUSED: not a remote name: $remote")) }
        $args2 = @("fetch", $remote)
    } else {
        $args2 = @("fetch", "--all")
    }
    $r = Invoke-GitProc $gitExe $args2
    $text = ($r.Out -join "`n")
    if ($r.TimedOut) { return (New-GitResult $false "FAILED" @("FAILED: git fetch did not finish within $($script:GitTimeoutSec) s (network or sign-in?).")) }
    if ($r.Code -ne 0) {
        $kind = Get-GitFailKind $text
        $head = if ($kind -eq "AUTH_REQUIRED") { "AUTH_REQUIRED: sign in once from Visual Studio (Git > Fetch or Push), then retry." } else { "${kind}: git fetch failed (exit $($r.Code))." }
        return (New-GitResult $false $kind (@($head) + @($r.Out | Select-Object -Last 15 | ForEach-Object { Hide-GitUrlSecret $_ })))
    }
    return (New-GitResult $true "OK" @("FETCHED: $(if ($remote) { $remote } else { 'all remotes' })"))
}

function Invoke-GitPushOp([string]$gitExe, [string]$remote, [bool]$setUpstream, [bool]$allowMain) {
    $branch = Get-GitLine $gitExe @("symbolic-ref", "--short", "-q", "HEAD")
    if (-not $branch) { return (New-GitResult $false "FAILED" @("FAILED: detached HEAD. Switch to a branch first.")) }
    if ($branch -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or $branch -match '\.\.|//|\.lock$|/$') { return (New-GitResult $false "FAILED" @("REFUSED: the branch name has characters that are not allowed here: $branch")) }
    if (($branch -eq "main" -or $branch -eq "master") -and -not $allowMain) {
        return (New-GitResult $false "REJECTED" @("REJECTED: '$branch' is a protected branch name for this tool. Push a work branch, or have the user say that '$branch' is OK (allow-main)."))
    }
    $remotesOut = Invoke-GitProc $gitExe @("remote")
    $remoteNames = @($remotesOut.Out)
    $upstream = Get-GitLine $gitExe @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
    if (-not $remote) {
        $cfgRemote = Get-GitLine $gitExe @("config", "--get", "branch.$branch.remote")
        if ($cfgRemote -and $cfgRemote -ne ".") { $remote = $cfgRemote }
        elseif ($remoteNames -contains "origin") { $remote = "origin" }
        elseif ($remoteNames.Count -eq 1) { $remote = [string]$remoteNames[0] }
        else { return (New-GitResult $false "FAILED" @("FAILED: no remote to push to (remotes: $($remoteNames -join ', ')). Name one with --remote.")) }
    }
    if ($remote -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or ($remoteNames -notcontains $remote)) {
        return (New-GitResult $false "FAILED" @("FAILED: '$remote' is not a configured remote (remotes: $($remoteNames -join ', ')). A URL is not accepted."))
    }
    if ($upstream) {
        $merge = Get-GitLine $gitExe @("config", "--get", "branch.$branch.merge")
        if ($merge -and $merge -ne "refs/heads/$branch") {
            return (New-GitResult $false "FAILED" @("FAILED: the upstream branch name differs from the local one ($upstream). Push it from Visual Studio, or fix the upstream."))
        }
        $cnt = Get-GitLine $gitExe @("rev-list", "--left-right", "--count", "HEAD...@{u}")
        if ($cnt -match '^0\s+') { return (New-GitResult $true "OK" @("NOTHING_TO_PUSH: $branch is not ahead of $upstream")) }
    } elseif (-not $setUpstream) {
        return (New-GitResult $false "FAILED" @("FAILED: '$branch' has no upstream. Push it for the first time with --set-upstream (it creates the branch on '$remote')."))
    }
    $pushArgs = @("push")
    if ($setUpstream) { $pushArgs += "-u" }
    $pushArgs += @($remote, "refs/heads/${branch}:refs/heads/${branch}")
    $r = Invoke-GitProc $gitExe $pushArgs
    $text = ($r.Out -join "`n")
    if ($r.TimedOut) { return (New-GitResult $false "FAILED" @("FAILED: git push did not finish within $($script:GitTimeoutSec) s (network or sign-in?). Check whether it reached the remote before pushing again.")) }
    if ($r.Code -ne 0) {
        $kind = Get-GitFailKind $text
        $head = switch ($kind) {
            "AUTH_REQUIRED" { "AUTH_REQUIRED: sign in once from Visual Studio (Git > Push), then retry." }
            "REJECTED" { "REJECTED: the remote refused the push (for example: it has commits you do not have (non-fast-forward), or the branch is protected). Do not force-push." }
            default { "FAILED: git push failed (exit $($r.Code))." }
        }
        return (New-GitResult $false $kind (@($head) + @($r.Out | Select-Object -Last 15 | ForEach-Object { Hide-GitUrlSecret $_ })))
    }
    $done = @("PUSHED: $remote $branch")
    if ($setUpstream) {
        # push -u が、上流を設定しないことがあった (実機 GR4: PUSHED のあとも UPSTREAM: (none))。明示して、設定する。失敗しても、push は成功しているので、警告にする
        $setup = Invoke-GitProc $gitExe @("branch", "--set-upstream-to=$remote/$branch", $branch)
        $now = Get-GitLine $gitExe @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
        if ($now) { $done[0] = "PUSHED: $remote $branch (upstream set: $now)" }
        else { $done += "WARN: the push succeeded, but the upstream could not be set (exit $($setup.Code)): $(($setup.Out | Select-Object -First 2) -join ' ')" }
    }
    return (New-GitResult $true "OK" $done)
}

# フラグの行を、上から実行する。失敗したら、そこで止める。戻り値: @{ Ok; Marker; Lines }
function Invoke-GitOps([string[]]$flagLines) {
    $gitExe = Find-GitExe
    if (-not $gitExe) { return @{ Ok = $false; Marker = "FAILED"; Env = $true; Lines = @("git.exe was not found (PATH, Program Files\Git, Visual Studio's bundled Git). Install Git for Windows or Visual Studio's Git tools.") } }
    $out = @("GIT: $gitExe")
    foreach ($raw in $flagLines) {
        $line = ([string]$raw).Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        $parts = @($line -split '\s+')
        $op = $parts[0]
        $rest = @($parts | Select-Object -Skip 1)
        switch ($op) {
            'status' {
                $s = Get-GitStateLines $gitExe
                $out += $s.Lines
                if (-not $s.Ok) { return @{ Ok = $false; Marker = "FAILED"; Lines = $out } }
            }
            'fetch' {
                $r = Invoke-GitFetchOp $gitExe $(if ($rest.Count -ge 1) { [string]$rest[0] } else { "" })
                if (-not $r.Ok) { return @{ Ok = $false; Marker = $r.Marker; Lines = ($out + $r.Lines) } }
                $out += $r.Lines
            }
            'push' {
                $remote = ""; $setUp = $false; $allow = $false; $badOpt = $null
                foreach ($t in $rest) {
                    if ($t -match '^remote=(.+)$') { $remote = $Matches[1] }
                    elseif ($t -eq 'set-upstream') { $setUp = $true }
                    elseif ($t -eq 'allow-main') { $allow = $true }
                    else { $badOpt = $t }
                }
                if ($badOpt) { return @{ Ok = $false; Marker = "FAILED"; Lines = ($out + @("REFUSED: unknown push option: $badOpt")) } }
                $r = Invoke-GitPushOp $gitExe $remote $setUp $allow
                if (-not $r.Ok) { return @{ Ok = $false; Marker = $r.Marker; Lines = ($out + $r.Lines) } }
                $out += $r.Lines
            }
            default {
                return @{ Ok = $false; Marker = "FAILED"; Lines = ($out + @("REFUSED: unknown operation: $op (only status / fetch / push exist)")) }
            }
        }
    }
    return @{ Ok = $true; Marker = "OK"; Lines = $out }
}

function Invoke-GitFlag([string[]]$flagLines) {
    try {
        $r = Invoke-GitOps $flagLines
    } catch {
        $r = @{ Ok = $false; Marker = "FAILED"; Env = $true; Lines = @("git operation failed: $($_.Exception.Message)") }
    }
    $r.Lines | Out-File $GitOutputFile -Encoding utf8
    if ($r.Ok) { Write-GitMarker "OK"; return }
    $head = if ($r.Env) { @("[ENVIRONMENT ERROR - not a source code problem]") } else { @() }
    ($head + $r.Lines) | Out-File $GitErrorLog -Encoding utf8
    Write-GitMarker $r.Marker
}
