# lib\tests.ps1 - テストの実行 (C++ の GoogleTest exe と、.NET のテストプロジェクト。trigger_test.flag / trigger_uitest.flag)
# watch_and_build.ps1 から、ドットソース (同じスコープに読み込む) で使う。単独では実行しない。

function Find-TestExes {
    # C++ のプロジェクトがなければ、探さない (.NET だけのソリューションに、x64 のフォルダはない)
    if (-not $HasCpp) { return @() }
    $platDir = switch ($Platform.ToLower()) { "x64" { "x64" } "arm64" { "ARM64" } default { "Win32" } }
    # 出力先は <ソリューションフォルダ>\<x64|Win32|ARM64>\<Configuration>\
    # ただし、Visual Studio の既定では、Win32 だけ、プラットフォームのフォルダが付かない (<ソリューションフォルダ>\<Configuration>\)。両方を探す
    $dirs = @(Join-Path (Join-Path $SolutionDir $platDir) $Configuration)
    if ($platDir -eq "Win32") { $dirs += (Join-Path $SolutionDir $Configuration) }
    $found = @()
    foreach ($dir in $dirs) {
        if (Test-Path -LiteralPath $dir) {
            $found = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match $TestExePattern } | Sort-Object Name)
            if ($found.Count -gt 0) { break }
        }
    }
    # 既定の出力先に exe がないテストプロジェクトは、OutDir を変えたものかもしれない。そのプロジェクトだけ、MSBuild の TargetPath で探す
    # (一部のテストだけ OutDir を変えたとき、既定の出力先に見つかった分だけで終わって、残りを黙って飛ばさないため)
    $extra = @(Find-TestExesByTargetPath @($found | ForEach-Object { $_.Name }))
    if ($extra.Count -eq 0) { return $found }
    return @(@($found) + $extra | Sort-Object FullName -Unique | Sort-Object Name)
}

# vswhere で、MSBuild.exe を探す (見つからなければ $null)
function Get-MSBuildExe {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) { return $null }
    $found = @(& $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" 2>$null | Where-Object { $_ })
    if ($found.Count -eq 0) { return $null }
    return $found[0]
}

# 既定の出力先に、exe がないテストプロジェクトの、探し直し。名前が Test(s) で終わる .vcxproj のうち、既定の出力先に見つかった exe 名
# (引数 FoundNames) に、プロジェクト名 + .exe がないものだけ、MSBuild の TargetPath (実際の出力先) を取る。
# 全部が既定の出力先に見つかったときは、MSBuild を呼ばない (既存の動作は、変わらない)。-getProperty が使えない古い MSBuild では、何も見つからない (空を返す)。
function Find-TestExesByTargetPath([string[]]$FoundNames = @()) {
    if (-not $HasCpp) { return @() }
    $found = @()
    $msbuild = $null
    # .vcxproj を単体で MSBuild に渡すと、SolutionDir が空になり、OutDir に $(SolutionDir) を使うプロジェクトの TargetPath が、別の場所を指す。ソリューションと同じ値を渡す
    $slnDir = $SolutionDir.TrimEnd('\') + '\'
    foreach ($p in $ProjectPaths) {
        if ($p -notmatch '\.vcxproj$') { continue }
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($p)
        if ($base -notmatch '(Test|Tests)$') { continue }
        if ($FoundNames -contains ($base + '.exe')) { continue }
        if (-not $msbuild) { $msbuild = Get-MSBuildExe }
        if (-not $msbuild) { return @() }
        try {
            $out = @(& $msbuild $p -nologo -getProperty:TargetPath "-p:Configuration=$Configuration" "-p:Platform=$Platform" "-p:SolutionDir=$slnDir" 2>$null)
            $target = @($out | Where-Object { $_ -and $_.ToString().Trim() } | Select-Object -Last 1)
            if ($target.Count -eq 0) { continue }
            $path = $target[0].ToString().Trim()
            if ((Test-Path -LiteralPath $path -PathType Leaf) -and ([System.IO.Path]::GetFileName($path) -match $TestExePattern)) {
                $found += Get-Item -LiteralPath $path
            }
        } catch { }
    }
    return @($found | Sort-Object Name)
}

# .NET のテストプロジェクト: Microsoft.NET.Test.Sdk / MSTest を参照している、IsTestProject が true、または名前が Test(s) で終わる。
# (Directory.Build.props 側で指定している場合は、中身では判定できないので、名前で拾う)
# UI テストのプロジェクト: 名前が UITests / UiTests で終わる、または FlaUI を参照している。
# 通常のテスト (trigger_test.flag) からは除外し、trigger_uitest.flag (-Ui) のときだけ実行する (遅く、デスクトップを占有するため)。
function Find-DotnetTestProjects([switch]$Ui) {
    $found = @()
    foreach ($p in $ProjectPaths) {
        if ($p -notmatch '\.(csproj|vbproj|fsproj)$') { continue }
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $text = ""
        try { $text = [System.IO.File]::ReadAllText($p) } catch { continue }
        $byName = [System.IO.Path]::GetFileNameWithoutExtension($p) -match '(Test|Tests)$'
        if ($byName -or $text -match 'Microsoft\.NET\.Test\.Sdk|<IsTestProject>\s*true\s*</IsTestProject>|Sdk="MSTest\.Sdk|Include="MSTest"') {
            $isUi = ([System.IO.Path]::GetFileNameWithoutExtension($p) -match '(UI|Ui)Tests$') -or ($text -match 'Include="FlaUI\.')
            if ([bool]$Ui -eq [bool]$isUi) { $found += $p }
        }
    }
    return @($found)
}

# 子プロセスを、制限時間つきで実行する。戻り値: @{ Timeout = bool; ExitCode = int; Output = string[] }
function Invoke-TestProcess([string]$filePath, [string]$argString, [string]$workDir, [int]$timeoutSec = 0) {
    $limit = if ($timeoutSec -gt 0) { $timeoutSec } else { $TestTimeoutSec }
    $outTmp = Join-Path $LogDir "test_stdout.tmp"
    $errTmp = Join-Path $LogDir "test_stderr.tmp"
    Remove-Item -LiteralPath $outTmp, $errTmp -ErrorAction SilentlyContinue
    if ($script:UiSeparateDesktop) { return Invoke-TestProcessOnDesktop $filePath $argString $workDir $limit $outTmp $errTmp }

    $spArgs = @{
        FilePath               = $filePath
        WorkingDirectory       = $workDir
        RedirectStandardOutput = $outTmp
        RedirectStandardError  = $errTmp
        PassThru               = $true
        NoNewWindow            = $true
    }
    if ($argString) { $spArgs["ArgumentList"] = $argString }
    $p = Start-Process @spArgs
    $null = $p.Handle   # PS 5.1: これがないと ExitCode が取れないことがある
    $timedOut = $false
    if (-not $p.WaitForExit($limit * 1000)) {
        $timedOut = $true
        # 子プロセスごと強制終了。Stop 下でネイティブの stderr が例外になるため握りつぶす
        try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch { }
        try { $p.Kill() } catch { }
        # 終了待ちにも上限を付ける (無期限に待つとウォッチャー全体が止まる)
        [void]$p.WaitForExit(5000)
    }
    $exitCode = if ($timedOut) { $null } else { $p.ExitCode }

    # 出力の文字コードは、ランナーによって違う (UTF-8 または ANSI)。Read-ProcessOutput が、判定して読む
    $lines = @()
    foreach ($f in @($outTmp, $errTmp)) {
        $lines += @(Read-ProcessOutput $f)
    }
    Remove-Item -LiteralPath $outTmp, $errTmp -ErrorAction SilentlyContinue
    return @{ Timeout = $timedOut; ExitCode = $exitCode; Output = $lines }
}

# GoogleTest の exe。--gtest_output=xml で、機械可読な結果を、.claude-logs\test-results\<exe名>.xml にも残す。
function Invoke-TestExe($exe) {
    $workDir = if ($TestWorkingDir) { $TestWorkingDir } else { $exe.DirectoryName }
    $xml = Join-Path $TestResultsDir ([System.IO.Path]::GetFileNameWithoutExtension($exe.Name) + ".xml")
    $argString = (@($TestArgs, ('"--gtest_output=xml:' + $xml + '"')) | Where-Object { $_ }) -join " "
    return Invoke-TestProcess $exe.FullName $argString $workDir
}

# .NET のテストプロジェクト。ビルドは、ソリューションのビルドで済んでいるので --no-build。
# trx を、.claude-logs\test-results\<プロジェクト名>.trx に残す。
function Invoke-DotnetTest([string]$project, [string]$dotnetPath, [int]$timeoutSec = 0, [string]$filter = "") {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($project)
    $argString = 'test "' + $project + '" --no-build -c ' + $Configuration +
        ' --results-directory "' + $TestResultsDir + '" --logger "trx;LogFileName=' + $name + '.trx"'
    if ($filter) { $argString += ' --filter "' + $filter + '"' }   # UI テストの、1 回ごとの絞り込み (flag の filter=)
    if ($DotnetTestArgs) { $argString += " " + $DotnetTestArgs }
    return Invoke-TestProcess $dotnetPath $argString (Split-Path -Parent $project) $timeoutSec
}

# ソリューションのフォルダの下の exe のプロセス (UI テストが残したアプリなど) を、終了する。
# 残ると、出力の exe がロックされ、次のビルドが失敗する (UI テストの前後に、呼ぶ)。
function Stop-SolutionProcesses {
    $prefix = $SolutionDir.TrimEnd('\') + '\'
    foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($proc.Id -eq $PID) { continue }
        $path = $null
        try { $path = $proc.Path } catch { }
        if ($path -and $path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "[UITEST] Stopping leftover process: $($proc.ProcessName) (PID $($proc.Id))" -ForegroundColor Yellow
            try { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null } catch { }
        }
    }
}

# ビルド成功後のテスト実行 (GoogleTest の exe と、.NET のテストプロジェクト)。test_result.txt を最後に書く。
# -Ui: UI テストのプロジェクトだけを実行する (GoogleTest の exe は、実行しない)。環境変数 UITEST_* で、テストに実行環境を渡す。
function Invoke-Tests([switch]$Ui) {
    New-Item -ItemType Directory -Path $TestResultsDir -Force | Out-Null
    $limit = if ($Ui) { $script:UiRun.TimeoutSec } else { $TestTimeoutSec }
    $script:UiSeparateDesktop = ($Ui -and $script:UiRun.Desktop -eq "separate")
    if ($Ui) {
        New-Item -ItemType Directory -Path $UiScreenshotDir -Force | Out-Null
        $env:UITEST_SOLUTION_DIR = $SolutionDir
        $env:UITEST_CONFIGURATION = $Configuration
        $env:UITEST_PLATFORM = $Platform
        $env:UITEST_SCREENSHOT_DIR = $UiScreenshotDir
        $env:UITEST_SLOWMO_MS = "$($script:UiRun.SlowMoMs)"
        $env:UITEST_HOLD_SEC = "$($script:UiRun.HoldSec)"
        $env:UITEST_PRESENT = $(if ($script:UiRun.Present) { "1" } else { "0" })
    }
    if ($Ui) { Write-UiTiming "Invoke-Tests: environment ready (timeout $($script:UiRun.TimeoutSec) s)" }
    $exes = if ($Ui) { @() } else { @(Find-TestExes) }
    $projects = @(Find-DotnetTestProjects -Ui:$Ui)
    if ($Ui) { Write-UiTiming "Invoke-Tests: found $($projects.Count) UI test project(s)" }
    if ($Ui -and $projects.Count -eq 0) {
        Write-TestEnvError @("ERROR: no UI test project found under $SolutionDir",
            "  A .NET test project whose name ends with UITests / UiTests, or that references FlaUI.* (.NET project in solution: $HasDotnet)")
        return
    }
    if ($exes.Count -eq 0 -and $projects.Count -eq 0) {
        Write-TestEnvError @("ERROR: no tests found for $Configuration|$Platform under $SolutionDir",
            "  GoogleTest exe matching '$TestExePattern' : none (looked in the default output folder, then at the MSBuild TargetPath of each *Test/*Tests .vcxproj; C++ project in solution: $HasCpp)",
            "  .NET test project (Microsoft.NET.Test.Sdk / MSTest, or a name ending in Test/Tests) : none (.NET project in solution: $HasDotnet)")
        return
    }
    $dotnetPath = $null
    if ($projects.Count -gt 0) {
        $cmd = Get-Command $DotnetExe -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-TestEnvError @("ERROR: '$DotnetExe' was not found, but the solution has .NET test projects. Install the .NET SDK, or pass -DotnetExe <full path>.", $DotnetInstallHint)
            return
        }
        $dotnetPath = $cmd.Source
    }

    $report = @()
    $failed = $false
    $timedOut = $false
    $invalid = $false
    $staleFound = $false
    $all = @()

    # --- GoogleTest (C++) ---
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
        } elseif ($r.ExitCode -eq 0 -and ($r.Output | Where-Object { "$_" -match '^\[\s+PASSED\s+\]\s+0\s+tests?\b' })) {
            # "[  PASSED  ] 0 tests." (GoogleTest は、0 件でも終了コード 0): テストが 1 件も実行されていない (.vcxproj への足し忘れ、--gtest_filter が一致しない、など)
            $invalid = $true
            $report += "=== $($exe.Name): 0 tests were run ([  PASSED  ] 0 tests). Check that the new test file is in the project, and that --gtest_filter / -TestArgs match. GTEST_* environment variables are removed at startup ==="
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

    # --- dotnet test (MSTest など) ---
    if (-not $timedOut) {
        foreach ($proj in $projects) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($proj)
            Write-Host "[TEST] Running dotnet test: $name (timeout ${limit}s)..." -ForegroundColor Yellow
            if ($Ui) { Write-UiTiming "dotnet test start: $name" }
            $r = Invoke-DotnetTest $proj $dotnetPath $limit $(if ($Ui) { $script:UiRun.Filter } else { "" })
            $all += @("=== $name (dotnet test) ===") + @($r.Output)
            $r.Output | ForEach-Object { Write-Host $_ }
            if ($Ui) { Write-UiTiming "dotnet test end: $name (exit $($r.ExitCode), timeout $($r.Timeout))" }
            $trx = Join-Path $TestResultsDir "$name.trx"

            if ($r.Timeout) {
                $timedOut = $true
                $report += "=== $name (dotnet test): TIMEOUT after ${limit}s (killed) ==="
                if ($Ui) { Stop-SolutionProcesses }   # テストが起動して、残ったアプリ
                break
            }
            # 古い出力先の DLL を実行していないか (成功のときは、偽の成功を防ぐため、ENV_ERROR にする)
            $stale = @(Get-StaleTestAssemblies $proj $trx)
            if ($stale.Count -gt 0) {
                $staleFound = $true
                if ($r.ExitCode -eq 0) { $invalid = $true }
                $report += "=== $name (dotnet test): the test assembly that was run is older than a build output in another folder ==="
                $report += $stale
                $report += "dotnet test --no-build looked in a different output folder than the build wrote (e.g. bin\Debug, while the build wrote bin\x64\Debug). Pass -DotnetTestArgs:-p:Platform=x64 (match the build platform), or delete the stale bin folder."
            }
            if ($r.ExitCode -eq 0) {
                # 終了コード 0 でも、1 件も実行されていなければ、テストは走っていない (テスト 0 件、アダプタ未検出など)
                $counters = Get-TrxCounters $trx
                if (-not $counters -or [int]$counters.executed -le 0) {
                    $invalid = $true
                    if ($Ui -and $script:UiRun.Filter) {
                        # --filter (flag の filter=) に一致するテストが、1 件もない。式の誤りが、ほとんど (GoogleTest / アダプタの不備ではない)
                        $filterNoMatch = $true
                        $report += "=== $name (dotnet test): no test matches the filter: $($script:UiRun.Filter) ==="
                    } else {
                        $report += "=== $name (dotnet test): no tests were executed (no trx, or executed=0) ==="
                    }
                    $report += @($r.Output | Select-Object -Last 15)
                }
            } else {
                $failed = $true
                $report += "=== $name (dotnet test): exit code $($r.ExitCode) ==="
                $lines = @(Get-TrxFailureLines $trx)
                if ($lines.Count -gt 0) {
                    $report += $lines
                } else {
                    $report += "(no test results: the test host crashed, or dotnet test failed before running tests)"
                    $report += @($r.Output | Select-Object -Last 30)
                }
            }
        }
    }
    $all | Out-File $TestLog -Encoding utf8

    if ($timedOut) {
        Write-Host "[RESULT] Tests TIMEOUT." -ForegroundColor Red
        $report += ""; $report += "Test timeout: ${limit}s"
        @(ConvertTo-RelativePaths $report) | Out-File $TestErrorLog -Encoding utf8
        Write-TestMarker "TIMEOUT"
    } elseif ($failed) {
        Write-Host "[RESULT] Tests FAILED." -ForegroundColor Red
        $report += ""; $report += "Tests failed"
        @(ConvertTo-RelativePaths $report) | Out-File $TestErrorLog -Encoding utf8
        Write-TestMarker "FAILED"
    } elseif ($invalid) {
        $envNote = if ($filterNoMatch) { "Test failed: no test matches the --filter expression ($($script:UiRun.Filter)). Check the expression: ~ means contains, = means equals, & / | combine (e.g. FullyQualifiedName~LoginDialog). This is not a GoogleTest / adapter problem." } elseif ($staleFound) { "Test result is not trusted: the tests ran against an older build output (see above)." } else { "Test failed: tests were probably not run (GoogleTest: check -TestArgs / is this a GoogleTest exe? dotnet: is Microsoft.NET.Test.Sdk and a test adapter referenced?)" }
        Write-Host "[RESULT] Tests ENV_ERROR ($(if ($filterNoMatch) { 'no test matches the filter' } elseif ($staleFound) { 'tests ran against an older build output' } else { 'tests were probably not run' }))." -ForegroundColor Red
        @(ConvertTo-RelativePaths (@("[ENVIRONMENT ERROR - not a source code problem]") + $report + @("", $envNote))) |
            Out-File $TestErrorLog -Encoding utf8
        Write-TestMarker "ENV_ERROR"
    } else {
        Write-Host "[RESULT] Tests PASSED." -ForegroundColor Green
        Write-TestMarker "PASSED"
    }
}
