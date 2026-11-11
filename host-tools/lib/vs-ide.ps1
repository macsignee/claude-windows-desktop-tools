# lib\vs-ide.ps1 - Visual Studio IDE operations (trigger_vs.flag: open / status / reload / clear / break / debug)
# Dot-sourced from watch_and_build.ps1 (same scope). Do not run alone.
#
# Each flag line is one operation (blank lines and # lines are ignored). Run in order; stop at the first failure.
#   open                      open the solution in Visual Studio (or bring the running one to the front)
#   status                    report: SOLUTION / OPEN / INSTANCES / DEBUG_MODE / DIRTY (read only; never starts VS)
#   reload <path>             close and reopen a document that VS has open and that has NO unsaved edits (path relative to the solution folder)
#   clear                     delete the breakpoints that this tool set (Tag = claude-vs-debug)
#   break <path>:<line>       set a breakpoint (path relative to the solution folder); skipped if one is already there
#   debug                     start debugging (only when VS is in design mode); report the mode and the stopped location
# Result: <TargetDir>\vs_result.txt (OK / FAILED, written last), vs_output.txt (facts), vs_error.log (reason when FAILED).
# The VS instance is found by the Running Object Table, matched by Solution.FullName (never "the first VS").

$VsTag = "claude-vs-debug"
$VsMaxBreakpoints = 20
$VsOpenWaitSec = 180
$ReVsPath = '^[^\x00-\x1f"<>|*?:]+$'

if (-not ([System.Management.Automation.PSTypeName]'VsNative').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class VsNative {
    [DllImport("ole32.dll")] static extern int GetRunningObjectTable(int reserved, out IRunningObjectTable rot);
    [DllImport("ole32.dll")] static extern int CreateBindCtx(int reserved, out IBindCtx ctx);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

    // Every running Visual Studio (monikers "!VisualStudio.DTE.<version>:<pid>"): name -> DTE object
    public static List<KeyValuePair<string, object>> FindDte() {
        List<KeyValuePair<string, object>> res = new List<KeyValuePair<string, object>>();
        IRunningObjectTable rot;
        if (GetRunningObjectTable(0, out rot) != 0) return res;
        IBindCtx ctx;
        CreateBindCtx(0, out ctx);
        IEnumMoniker en;
        rot.EnumRunning(out en);
        en.Reset();
        IMoniker[] m = new IMoniker[1];
        while (en.Next(1, m, IntPtr.Zero) == 0) {
            string name;
            try { m[0].GetDisplayName(ctx, null, out name); } catch { continue; }
            if (name != null && name.StartsWith("!VisualStudio.DTE.")) {
                object o;
                if (rot.GetObject(m[0], out o) == 0) res.Add(new KeyValuePair<string, object>(name, o));
            }
        }
        return res;
    }

    public static void BringToFront(IntPtr hWnd) {
        if (IsIconic(hWnd)) ShowWindow(hWnd, 9);            // SW_RESTORE
        keybd_event(0x12, 0, 0, UIntPtr.Zero);               // Alt down/up: lets SetForegroundWindow through the foreground lock
        keybd_event(0x12, 0, 2, UIntPtr.Zero);
        SetForegroundWindow(hWnd);
    }
}
'@
}

function Write-VsMarker([string]$value) {
    Write-RunId
    try {
        [System.IO.File]::WriteAllText($VsResultFile, $value)
        Write-Host "[MARKER] $value -> $VsResultFile" -ForegroundColor DarkGray
    } catch {
        Write-Host "[MARKER] FAILED to write $VsResultFile : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# COM calls to a busy VS can be rejected (RPC_E_CALL_REJECTED 0x80010001 / 0x8001010A). Retry a few times.
function Invoke-VsRetry([scriptblock]$block) {
    $last = $null
    for ($i = 0; $i -lt 20; $i++) {
        try { return (& $block) } catch { $last = $_; Start-Sleep -Milliseconds 500 }
    }
    throw $last
}

function Get-VsFullPath([string]$rel) {
    if ($rel -notmatch $ReVsPath) { return $null }
    if ($rel -match '(^|[/\\])\.\.([/\\]|$)') { return $null }
    $full = [System.IO.Path]::GetFullPath((Join-Path $SolutionDir ($rel -replace '/', '\')))
    if (-not $full.StartsWith($SolutionDir.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $full
}

# Running VS instances that have THIS solution open: @{ Name; Dte }
function Get-VsTargets {
    $targets = @()
    if (-not $SolutionPath) { return $targets }
    $want = [System.IO.Path]::GetFullPath($SolutionPath).TrimEnd('\')
    foreach ($kv in [VsNative]::FindDte()) {
        try {
            $sln = [string](Invoke-VsRetry { $kv.Value.Solution.FullName })
            if ($sln -and ([System.IO.Path]::GetFullPath($sln).TrimEnd('\') -ieq $want)) {
                $targets += @{ Name = $kv.Key; Dte = $kv.Value }
            }
        } catch { }
    }
    return $targets
}

function Get-VsDevenv {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        $p = @(& $vswhere -latest -prerelease -products * -property productPath 2>$null) | Select-Object -First 1
        if ($p -and (Test-Path -LiteralPath "$p")) { return "$p" }
    }
    return $null
}

function Get-VsModeName($dte) {
    switch ([int](Invoke-VsRetry { $dte.Debugger.CurrentMode })) { 1 { "design" } 2 { "run" } 3 { "break" } default { "unknown" } }
}

function Get-VsStatusLines {
    $lines = @("SOLUTION: $SolutionPath")
    $targets = @(Get-VsTargets)
    if ($targets.Count -eq 0) { return $lines + @("OPEN: no", "INSTANCES: 0") }
    $lines += "OPEN: yes"
    $lines += "INSTANCES: $($targets.Count)"
    $dte = $targets[0].Dte
    $lines += "DEBUG_MODE: $(Get-VsModeName $dte)"
    $dirty = 0
    foreach ($d in @(Invoke-VsRetry { @($dte.Documents) })) {
        try { if (-not $d.Saved) { $lines += "DIRTY: $($d.FullName)"; $dirty++ } } catch { }
    }
    try { if (-not (Invoke-VsRetry { $dte.Solution.Saved })) { $lines += "DIRTY: (solution or project items: $SolutionPath)"; $dirty++ } } catch { }
    $lines += "DIRTY_COUNT: $dirty"
    return $lines
}

function Get-VsLocation($dte) {
    try {
        $frame = Invoke-VsRetry { $dte.Debugger.CurrentStackFrame }
        $doc = $dte.ActiveDocument
        $where = ""
        if ($doc) { $where = " at $($doc.FullName):$($doc.Selection.CurrentLine)" }
        return "STOPPED: $($frame.FunctionName)$where"
    } catch { return "STOPPED: (location unknown)" }
}

# Run the operations. Returns @{ Ok; Env; Lines }
function Invoke-VsOps([string[]]$flagLines) {
    $out = New-Object System.Collections.Generic.List[string]
    $ops = @($flagLines | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($ops.Count -eq 0) { return @{ Ok = $false; Env = $false; Lines = @("no operation given") } }
    if (-not $SolutionPath) { return @{ Ok = $false; Env = $true; Lines = @("no .sln / .slnx found in $TargetDir") } }
    $breaks = 0
    foreach ($op in $ops) {
        $t = $op -split '\s+', 2
        $arg = if ($t.Count -gt 1) { $t[1].Trim() } else { "" }
        switch ($t[0]) {
            'status' {
                if ($arg) { return @{ Ok = $false; Env = $false; Lines = @("status takes no argument") } }
                foreach ($l in (Get-VsStatusLines)) { $out.Add($l) }
            }
            'open' {
                if ($arg) { return @{ Ok = $false; Env = $false; Lines = @("open takes no argument") } }
                $targets = @(Get-VsTargets)
                if ($targets.Count -ge 2) {
                    $out.Add("MULTIPLE_INSTANCES: $($targets.Count) Visual Studio windows have this solution open. Ask the user which one to keep.")
                    return @{ Ok = $false; Env = $false; Lines = $out.ToArray() }
                }
                if ($targets.Count -eq 0) {
                    $devenv = Get-VsDevenv
                    if (-not $devenv) { return @{ Ok = $false; Env = $true; Lines = @("Visual Studio (devenv.exe) was not found (vswhere.exe).") } }
                    Start-Process -FilePath $devenv -ArgumentList @("`"$SolutionPath`"")
                    $out.Add("STARTED: $devenv")
                    $deadline = (Get-Date).AddSeconds($VsOpenWaitSec)
                    while ($targets.Count -eq 0 -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2; $targets = @(Get-VsTargets) }
                    if ($targets.Count -eq 0) { return @{ Ok = $false; Env = $true; Lines = $out.ToArray() + @("Visual Studio did not open the solution within ${VsOpenWaitSec}s.") } }
                    $deadline = (Get-Date).AddSeconds(60)   # wait until the solution has finished loading
                    while ((Get-Date) -lt $deadline) {
                        try { if ([bool](Invoke-VsRetry { $targets[0].Dte.Solution.IsOpen })) { break } } catch { }
                        Start-Sleep -Seconds 2
                    }
                } else {
                    $out.Add("FOUND: $($targets[0].Name)")
                }
                $dte = $targets[0].Dte
                try {
                    Invoke-VsRetry { $dte.MainWindow.Visible = $true; $dte.MainWindow.Activate() } | Out-Null
                    [VsNative]::BringToFront([IntPtr][int](Invoke-VsRetry { $dte.MainWindow.HWnd }))
                    $out.Add("ACTIVATED")
                } catch { $out.Add("ACTIVATE_FAILED: $($_.Exception.Message)") }
            }
            { $_ -in @('reload', 'clear', 'break', 'debug') } {
                $targets = @(Get-VsTargets)
                if ($targets.Count -ne 1) { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("$($t[0]): Visual Studio does not have this solution open (found $($targets.Count)). Run open first.") } }
                $dte = $targets[0].Dte
                switch ($t[0]) {
                    'reload' {
                        $full = Get-VsFullPath $arg
                        if (-not $full) { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("reload: invalid path: $arg") } }
                        $doc = $null
                        foreach ($d in @(Invoke-VsRetry { @($dte.Documents) })) { try { if ($d.FullName -ieq $full) { $doc = $d; break } } catch { } }
                        if (-not $doc) { $out.Add("RELOAD_SKIP (not open in VS): $arg") }
                        elseif (-not $doc.Saved) { $out.Add("RELOAD_SKIP_DIRTY: $arg") }
                        else {
                            Invoke-VsRetry { $doc.Close(2) } | Out-Null   # 2 = vsSaveChangesNo (the document has no unsaved edits)
                            Invoke-VsRetry { $dte.ItemOperations.OpenFile($full) | Out-Null } | Out-Null
                            $out.Add("RELOADED: $arg")
                        }
                    }
                    'clear' {
                        $mine = @()
                        foreach ($b in @(Invoke-VsRetry { @($dte.Debugger.Breakpoints) })) { try { if ("$($b.Tag)" -eq $VsTag) { $mine += $b } } catch { } }
                        foreach ($b in $mine) { try { $b.Delete() } catch { } }
                        $out.Add("CLEARED: $($mine.Count)")
                    }
                    'break' {
                        if ($arg -notmatch '^(.+):([0-9]{1,6})$') { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("break: use <path>:<line>: $arg") } }
                        $full = Get-VsFullPath $Matches[1]
                        $line = [int]$Matches[2]
                        if (-not $full -or -not (Test-Path -LiteralPath $full) -or $line -lt 1) { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("break: file not found under the solution folder, or bad line: $arg") } }
                        if ($breaks -ge $VsMaxBreakpoints) { $out.Add("BREAK_SKIP (limit ${VsMaxBreakpoints}): $arg"); break }
                        $exists = $false
                        foreach ($b in @(Invoke-VsRetry { @($dte.Debugger.Breakpoints) })) { try { if ($b.File -ieq $full -and [int]$b.FileLine -eq $line) { $exists = $true; break } } catch { } }
                        if ($exists) { $out.Add("BREAK_EXISTS: $arg"); break }
                        $added = Invoke-VsRetry { $dte.Debugger.Breakpoints.Add("", $full, $line) }
                        foreach ($b in @($added)) { try { $b.Tag = $VsTag } catch { } }
                        $breaks++
                        $out.Add("BREAK_SET: $arg")
                    }
                    'debug' {
                        $mode = Get-VsModeName $dte
                        if ($mode -ne 'design') { $out.Add("DEBUG_MODE: $mode"); return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("debug: already running or stopped; not started again.") } }
                        Invoke-VsRetry { $dte.Debugger.Go($false) } | Out-Null
                        $deadline = (Get-Date).AddSeconds(30)
                        while ((Get-VsModeName $dte) -eq 'design' -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
                        Start-Sleep -Milliseconds 1500   # a breakpoint hit right after start
                        $mode = Get-VsModeName $dte
                        $out.Add("DEBUG_STARTED")
                        $out.Add("DEBUG_MODE: $mode")
                        if ($mode -eq 'break') { $out.Add((Get-VsLocation $dte)) }
                        if ($mode -eq 'design') { $out.Add("NOTE: the mode is still design. The build may have failed or a dialog may be open in Visual Studio.") }
                    }
                }
            }
            default { return @{ Ok = $false; Env = $false; Lines = @("unknown operation: $op (open / status / reload / clear / break / debug)") } }
        }
    }
    return @{ Ok = $true; Env = $false; Lines = $out.ToArray() }
}

function Invoke-VsFlag([string[]]$flagLines) {
    try {
        $r = Invoke-VsOps $flagLines
    } catch {
        $r = @{ Ok = $false; Env = $true; Lines = @("Visual Studio operation failed: $($_.Exception.Message)") }
    }
    $r.Lines | Out-File $VsOutputFile -Encoding utf8
    if ($r.Ok) { Write-VsMarker "OK"; return }
    $head = if ($r.Env) { @("[ENVIRONMENT ERROR - not a source code problem]") } else { @() }
    ($head + $r.Lines) | Out-File $VsErrorLog -Encoding utf8
    Write-VsMarker "FAILED"
}
