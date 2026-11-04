# lib\package.ps1 - パッケージの操作 (trigger_package.flag。nuget / vcpkg / fetch)
# watch_and_build.ps1 から、ドットソース (同じスコープに読み込む) で使う。単独では実行しない。

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
    Write-RunId
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
