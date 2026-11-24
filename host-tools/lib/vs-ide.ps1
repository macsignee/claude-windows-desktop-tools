# lib\vs-ide.ps1 - Visual Studio IDE operations (trigger_vs.flag: open / status / reload / clear / break / debug / inspect / output / step / continue / pause / eval)
# Dot-sourced from watch_and_build.ps1 (same scope). Do not run alone.
#
# Each flag line is one operation (blank lines and # lines are ignored). Run in order; stop at the first failure.
#   open                      open the solution in Visual Studio (or bring the running one to the front)
#   status                    report: SOLUTION / OPEN / INSTANCES / DEBUG_MODE / DIRTY (read only; never starts VS)
#   reload <path>             close and reopen a document that VS has open and that has NO unsaved edits (path relative to the solution folder)
#   clear                     delete the breakpoints that this tool set (Tag = claude-vs-debug)
#   break <path>:<line>       set a breakpoint (path relative to the solution folder); skipped if one is already there
#   debug                     start debugging (only when VS is in design mode); report the mode and the stopped location
#   inspect                   (v2.99.0) break mode only: EXCEPTION: / STACK: (up to 10 frames) / LOCALS: (up to 30). Read only. INSPECT_SKIP: when not in break mode
#   output <lines>            (v2.99.0) the last <lines> (1..500) of the "Debug" pane of the Output window (Debug.WriteLine / Trace / OutputDebugString / TRACE).
#                             Full text -> <TargetDir>\vs_debug_output.txt; facts -> OUTPUT: file=... lines=... total=.... Read only: the pane is never cleared.
#                             OUTPUT_UNAVAILABLE: when the pane does not exist yet (no debug session has run in this VS)
#   step <over|into|out> <n>  (v2.101.0) F10 / F11 / Shift+F11, n steps (1..30). Break mode only. Per step: STEP i: <file>:<line>  <source line>, then CHANGED: (locals that changed) or FRAME: + LOCALS:
#                             when the function changed. STEP_DONE: / STEP_END: (the program ended) / STEP_TIMEOUT: (still running: a modal dialog, or waiting for input)
#   continue                  (v2.101.0) F5 (Debugger.Go). Break mode only. Waits for the next break / the end (up to VsBreakWaitSec)
#   pause                     (v2.101.0) Debugger.Break. Run mode only
#   eval <expression>         (v2.101.0) the value of an expression (watch). READ-ONLY: an assignment, ++, --, ';' are rejected (EVAL_REJECTED). Break mode only. Function calls are NOT blocked here (a side effect is possible): the Skill tells Claude not to use them without the user's consent
#   There is NO stop operation (Shift+F5 is the user's). Steps / Go / Break do not block (WaitForBreakOrEnd = false) and the mode is polled with a timeout, so a modal dialog cannot freeze the watcher.
#   inspect / output never start VS: they need exactly one VS that has the solution open (like reload / clear / break / debug).
# Result: <TargetDir>\vs_result.txt (OK / FAILED, written last), vs_output.txt (facts), vs_error.log (reason when FAILED), vs_debug_output.txt (output).
# The VS instance is found by the Running Object Table, matched by Solution.FullName (never "the first VS").

$VsTag = "claude-vs-debug"
$VsMaxBreakpoints = 20
$VsOpenWaitSec = 180
$VsBreakWaitSec = 20   # after the app starts, wait this long for a breakpoint hit before reporting "run"
$ReVsPath = '^[^\x00-\x1f"<>|*?:]+$'
$VsOutputMaxLines = 500          # output <lines>: 1..500
$VsOutputMaxChars = 200000       # the capture file is cut to the last 200000 characters
$VsInspectMaxFrames = 10
$VsInspectMaxLocals = 30
$VsInspectValueMax = 200         # characters per value
$VsOutputWindowKind = '{34E76E81-EE4A-11D0-AE2E-00A0C90FFFC3}'   # EnvDTE.Constants.vsWindowKindOutput
$VsUnknownWaitSec = 5            # after the breakpoint wait: a stop at an exception can read as 'unknown' for a moment
$VsStepMax = 30                 # steps per step operation (the Skill also limits one run to 30 in total)
$VsStepWaitSec = 15              # a step that has not stopped after this long is reported as STEP_TIMEOUT
$VsPauseWaitSec = 10
$VsInspectExtraWaitSec = 40      # inspect right after debug: if the app is still starting (mode run), wait this long more for the break
$VsLocationWaitSec = 3           # STOPPED: waits this long for the stack frame to be ready (right after a continue it can be empty)
$VsStepChangedMax = 10           # CHANGED: / LOCALS: lines per step
$VsTargetRetry = 3               # when no VS answers right after the app starts, ask again (2 s apart) before giving up
$VsDebugPaneGuid = '{FC076020-078A-11D1-A7DF-00A0C9110051}'   # the Debug pane (VSConstants.OutputWindowPaneGuid.DebugPane_guid). Found by GUID: the pane name is localized

if (-not ([System.Management.Automation.PSTypeName]'VsNative').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class VsNative {
    // IDispatch late binding by NAME. $dte.ToolWindows (a DTE2 member) is invisible to PowerShell and unknown to IDispatch (DISP_E_UNKNOWNNAME),
    // but Windows.Item(<kind>).Object -> OutputWindowPanes is reachable by name (verified on VS 2026, 2026-11-19). The panes must be ENUMERATED:
    // OutputWindowPanes.Item(<index>) as a property fails with DISP_E_MEMBERNOTFOUND.
    static object Prop(object o, string name, params object[] args) {
        return o.GetType().InvokeMember(name, System.Reflection.BindingFlags.GetProperty, null, o, args);
    }
    static object Meth(object o, string name, params object[] args) {
        return o.GetType().InvokeMember(name, System.Reflection.BindingFlags.InvokeMethod, null, o, args);
    }
    // The text of the Output window pane whose GUID is paneGuid; null when there is no such pane. panes = "name=guid; ..." of all panes (for the diagnostic).
    public static string ReadOutputPane(object dte, string windowKind, string paneGuid, out string panes) {
        object wins = Prop(dte, "Windows");
        object win = Prop(wins, "Item", windowKind);
        object ow = Prop(win, "Object");
        object col = Prop(ow, "OutputWindowPanes");
        System.Text.StringBuilder list = new System.Text.StringBuilder();
        string result = null;
        foreach (object p in (System.Collections.IEnumerable)col) {
            string name = "", guid = "";
            try { name = Convert.ToString(Prop(p, "Name")); } catch { }
            try { guid = Convert.ToString(Prop(p, "Guid")); } catch { }
            if (list.Length > 0) list.Append("; ");
            list.Append(name + "=" + guid);
            if (result == null && string.Equals(guid, paneGuid, StringComparison.OrdinalIgnoreCase)) {
                object td = Prop(p, "TextDocument");
                object sp = Prop(td, "StartPoint");
                object ep = Prop(td, "EndPoint");
                object e = Meth(sp, "CreateEditPoint");
                result = Convert.ToString(Meth(e, "GetText", ep));
            }
        }
        panes = list.ToString();
        return result;
    }

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

# EnvDTE.dbgDebugMode: dbgDesignMode = 1, dbgBreakMode = 2, dbgRunMode = 3 (break is 2, NOT 3)
function Get-VsModeName($dte) {
    switch ([int](Invoke-VsRetry { $dte.Debugger.CurrentMode })) { 1 { "design" } 2 { "break" } 3 { "run" } default { "unknown" } }
}

function Get-VsStatusLines {
    $lines = @("SOLUTION: $SolutionPath")
    $targets = @(Get-VsTargets)
    if ($targets.Count -eq 0) { return $lines + @("OPEN: no", "INSTANCES: 0") }
    $lines += "OPEN: yes"
    $lines += "INSTANCES: $($targets.Count)"
    $dte = $targets[0].Dte
    $mode = Get-VsModeName $dte
    $lines += "DEBUG_MODE: $mode"
    if ($mode -eq 'break') { $lines += (Get-VsLocation $dte) }
    $dirty = 0
    foreach ($d in @(Invoke-VsRetry { @($dte.Documents) })) {
        try { if (-not $d.Saved) { $lines += "DIRTY: $($d.FullName)"; $dirty++ } } catch { }
    }
    try { if (-not (Invoke-VsRetry { $dte.Solution.Saved })) { $lines += "DIRTY: (solution or project items: $SolutionPath)"; $dirty++ } } catch { }
    $lines += "DIRTY_COUNT: $dirty"
    return $lines
}

function Get-VsLocation($dte) {
    $deadline = (Get-Date).AddSeconds($VsLocationWaitSec)
    $func = ""; $where = ""
    do {
        try {
            $frame = Invoke-VsRetry { $dte.Debugger.CurrentStackFrame }
            $func = [string]$frame.FunctionName
            $file = ""; $line = 0
            try { $file = [string]$frame.FileName; $line = [int]$frame.LineNumber } catch { }
            if ($file -and $line -gt 0) { $where = " at ${file}:$line" }
            else {
                $doc = $dte.ActiveDocument
                if ($doc) { $where = " at $($doc.FullName):$($doc.Selection.CurrentLine)" }
            }
        } catch { }
        if ($func -and $where) { break }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Milliseconds 200
    } while ($true)
    if (-not $func -and -not $where) { return "STOPPED: (location unknown)" }
    return "STOPPED: $func$where"
}

# The "Debug" pane of the Output window (found by GUID; the name is localized). Read only (never cleared).
# Returns @{ Text; Panes }. Text is $null when the pane does not exist. Panes = "name=guid; ..." of every pane (for the OUTPUT_UNAVAILABLE diagnostic).
function Get-VsOutputPane($dte) {
    $panes = ""
    $text = Invoke-VsRetry { [VsNative]::ReadOutputPane($dte, $VsOutputWindowKind, $VsDebugPaneGuid, [ref]$panes) }
    return @{ Text = $text; Panes = $panes }
}

# One line, at most $VsInspectValueMax characters
function Limit-VsText([string]$t) {
    $one = ($t -replace '[\r\n]+', ' ').Trim()
    if ($one.Length -gt $VsInspectValueMax) { return $one.Substring(0, $VsInspectValueMax) + '...' }
    return $one
}

# A value for output. When VS cannot read it (IsValidValue is false: an optimized-away variable in a Release module, for example),
# VS puts a long message in Value. Show a short mark instead.
function Format-VsValue($e) {
    try { if (-not $e.IsValidValue) { return "(unavailable)" } } catch { }
    return (Limit-VsText ([string]$e.Value))
}

# Values are read in decimal: VS's "hexadecimal display" setting turns int 3 into 0x00000003. Turn it off while reading, then give it back.
function Use-VsDecimal($dte) {
    try {
        $prev = [bool]$dte.Debugger.HexDisplayMode
        if ($prev) { $dte.Debugger.HexDisplayMode = $false }
        return $prev
    } catch { return $false }
}
function Restore-VsHex($dte, [bool]$prev) {
    if ($prev) { try { $dte.Debugger.HexDisplayMode = $true } catch { } }
}

# Break mode: the exception, the call stack and the locals of the current frame (read only). Each part is best effort.
function Get-VsInspectLines($dte) {
    $lines = New-Object System.Collections.Generic.List[string]
    $hex = Use-VsDecimal $dte
    try {
        $ex = Invoke-VsRetry { $dte.Debugger.GetExpression('$exception', $false, 2000) }
        if ($ex -and $ex.IsValidValue) {
            $exType = ""
            try { if ($ex.Type) { $exType = "$($ex.Type) " } } catch { }
            $lines.Add("EXCEPTION: $exType$(Limit-VsText ([string]$ex.Value))")
        }
    } catch { }
    try {
        $frames = @(Invoke-VsRetry { @($dte.Debugger.CurrentThread.StackFrames) })
        $i = 0
        foreach ($f in $frames) {
            if ($i -ge $VsInspectMaxFrames) { $lines.Add("STACK_TRUNCATED: $($frames.Count - $VsInspectMaxFrames) more frames"); break }
            $where = ""
            try { if ($f.FileName) { $where = " at $($f.FileName):$($f.LineNumber)" } } catch { }
            $lines.Add("STACK: #$i $($f.FunctionName)$where")
            $i++
        }
    } catch { $lines.Add("STACK_UNAVAILABLE: $($_.Exception.Message)") }
    try {
        $frame = Invoke-VsRetry { $dte.Debugger.CurrentStackFrame }
        $n = 0
        foreach ($e in @(Invoke-VsRetry { @($frame.Locals) })) {
            if ($n -ge $VsInspectMaxLocals) { $lines.Add("LOCALS_TRUNCATED: more than $VsInspectMaxLocals"); break }
            try { $lines.Add("LOCALS: $($e.Name) = $(Format-VsValue $e)  ($($e.Type))") } catch { }
            $n++
        }
    } catch { $lines.Add("LOCALS_UNAVAILABLE: $($_.Exception.Message)") }
    Restore-VsHex $dte $hex
    return $lines.ToArray()
}

# The place where a stopped program is: @{ File; Line; Func }
function Get-VsPosition($dte) {
    $func = ""; $file = ""; $line = 0
    try { $frame = Invoke-VsRetry { $dte.Debugger.CurrentStackFrame }; $func = [string]$frame.FunctionName } catch { }
    try { $doc = $dte.ActiveDocument; if ($doc) { $file = [string]$doc.FullName; $line = [int]$doc.Selection.CurrentLine } } catch { }
    return @{ File = $file; Line = $line; Func = $func }
}

# The text of a source line, read from the file (not from VS: no COM call, and no change to VS)
function Get-VsSourceText([string]$file, [int]$line) {
    if (-not $file -or $line -lt 1 -or -not (Test-Path -LiteralPath $file)) { return "" }
    try { return (Limit-VsText ([string]([System.IO.File]::ReadLines($file) | Select-Object -Skip ($line - 1) -First 1))) } catch { return "" }
}

# name -> value of the locals of the current frame (up to VsInspectMaxLocals)
function Get-VsLocalsMap($dte) {
    $m = [ordered]@{}
    $hex = Use-VsDecimal $dte
    try {
        $frame = Invoke-VsRetry { $dte.Debugger.CurrentStackFrame }
        $n = 0
        foreach ($e in @(Invoke-VsRetry { @($frame.Locals) })) {
            if ($n -ge $VsInspectMaxLocals) { break }
            try { $m[[string]$e.Name] = Format-VsValue $e } catch { }
            $n++
        }
    } catch { }
    Restore-VsHex $dte $hex
    return ,$m
}

# One step (F10 / F11 / Shift+F11) without blocking. Returns the mode afterwards.
# Right after the command, the mode can still read "break" before the debugger has resumed, so: wait until the mode leaves break,
# or the place changes, or a short time has passed (a step that lands on the same line); then, if it is running, wait for break / the end.
function Invoke-VsStepOnce($dte, [string]$kind, $before) {
    $d = $dte.Debugger
    switch ($kind) {
        'over' { Invoke-VsRetry { $d.StepOver($false) } | Out-Null }
        'into' { Invoke-VsRetry { $d.StepInto($false) } | Out-Null }
        'out'  { Invoke-VsRetry { $d.StepOut($false) } | Out-Null }
    }
    $deadline = (Get-Date).AddSeconds($VsStepWaitSec)
    $quick = (Get-Date).AddMilliseconds(1500)
    $left = $false
    while ((Get-Date) -lt $deadline) {
        $mode = Get-VsModeName $dte
        if ($mode -eq 'design') { break }
        if ($mode -ne 'break') { $left = $true }
        else {
            if ($left) { break }
            $pos = Get-VsPosition $dte
            if ($pos.File -ne $before.File -or $pos.Line -ne $before.Line -or $pos.Func -ne $before.Func) { break }
            if ((Get-Date) -gt $quick) { break }
        }
        Start-Sleep -Milliseconds 100
    }
    return (Get-VsModeName $dte)
}

# eval is read-only: an assignment (=, +=, <<= ...), ++ and -- are not allowed. == != <= >= are comparisons.
function Test-VsAssignment([string]$e) {
    if ($e -match '<<=|>>=') { return $true }
    $t = $e -replace '==|!=|<=|>=', '  '
    return ($t -match '=')
}

# Run the operations. Returns @{ Ok; Env; Lines }
function Invoke-VsOps([string[]]$flagLines) {
    $out = New-Object System.Collections.Generic.List[string]
    $ops = @($flagLines | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($ops.Count -eq 0) { return @{ Ok = $false; Env = $false; Lines = @("no operation given") } }
    if (-not $SolutionPath) { return @{ Ok = $false; Env = $true; Lines = @("no .sln / .slnx found in $TargetDir") } }
    $breaks = 0
    $debugStarted = $false
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
            { $_ -in @('reload', 'clear', 'break', 'debug', 'inspect', 'output', 'step', 'continue', 'pause', 'eval') } {
                $targets = @(Get-VsTargets)
                for ($retry = 0; $targets.Count -eq 0 -and $retry -lt $VsTargetRetry; $retry++) { Start-Sleep -Seconds 2; $targets = @(Get-VsTargets) }   # right after the app starts, VS can briefly not answer
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
                    'step' {
                        if ($arg -notmatch '^(over|into|out) ([0-9]{1,2})$') { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("step: use <over|into|out> <steps>: $arg") } }
                        $kind = $Matches[1]; $count = [int]$Matches[2]
                        if ($count -lt 1 -or $count -gt $VsStepMax) { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("step: steps must be 1 to $($VsStepMax): $arg") } }
                        $mode = Get-VsModeName $dte
                        if ($mode -ne 'break') { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("step: not in break mode (mode: $mode). Stepping needs the program stopped at a breakpoint or an exception.") } }
                        $prevPos = Get-VsPosition $dte
                        $prevLocals = Get-VsLocalsMap $dte
                        $done = 0; $stop = $false
                        for ($i = 1; $i -le $count; $i++) {
                            $mode = Invoke-VsStepOnce $dte $kind $prevPos
                            if ($mode -eq 'design') { $out.Add("STEP_END: the program ended after $done step(s)."); $stop = $true; break }
                            if ($mode -ne 'break') { $out.Add("STEP_TIMEOUT: still running after ${VsStepWaitSec}s at step $i (a modal dialog, or the program is waiting for input?). Check with status, or ask the user."); $stop = $true; break }
                            $pos = Get-VsPosition $dte
                            $out.Add("STEP ${i}: $($pos.File):$($pos.Line)  $(Get-VsSourceText $pos.File $pos.Line)")
                            $locals = Get-VsLocalsMap $dte
                            $shown = 0
                            if ($pos.Func -ne $prevPos.Func) {
                                $out.Add("FRAME: $($pos.Func)")
                                foreach ($k in $locals.Keys) { if ($shown -ge $VsStepChangedMax) { break }; $out.Add("LOCALS: $k = $($locals[$k])"); $shown++ }
                            } else {
                                foreach ($k in $locals.Keys) {
                                    if ($shown -ge $VsStepChangedMax) { break }
                                    if (-not $prevLocals.Contains($k)) { $out.Add("CHANGED: $k = (new) -> $($locals[$k])"); $shown++ }
                                    elseif ($prevLocals[$k] -ne $locals[$k]) { $out.Add("CHANGED: $k = $($prevLocals[$k]) -> $($locals[$k])"); $shown++ }
                                }
                            }
                            $prevPos = $pos; $prevLocals = $locals; $done++
                        }
                        if (-not $stop) { $out.Add("STEP_DONE: $done/$count") }
                    }
                    'continue' {
                        if ($arg) { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("continue takes no argument") } }
                        $mode = Get-VsModeName $dte
                        if ($mode -ne 'break') { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("continue: not in break mode (mode: $mode).") } }
                        Invoke-VsRetry { $dte.Debugger.Go($false) } | Out-Null
                        $quick = (Get-Date).AddMilliseconds(1500)
                        while ((Get-VsModeName $dte) -eq 'break' -and (Get-Date) -lt $quick) { Start-Sleep -Milliseconds 100 }   # right after Go, the mode can still read break
                        $deadline = (Get-Date).AddSeconds($VsBreakWaitSec)
                        while ((Get-VsModeName $dte) -in @('run', 'unknown') -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
                        $mode = Get-VsModeName $dte
                        $out.Add("CONTINUED: DEBUG_MODE: $mode")
                        if ($mode -eq 'break') { $out.Add((Get-VsLocation $dte)) }
                        if ($mode -eq 'run') { $out.Add("NOTE: no break within ${VsBreakWaitSec}s. The program is running (waiting for the user, or no breakpoint is on its path). Use status or pause.") }
                        if ($mode -eq 'design') { $out.Add("CONTINUE_END: the program ended.") }
                    }
                    'pause' {
                        if ($arg) { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("pause takes no argument") } }
                        $mode = Get-VsModeName $dte
                        if ($mode -ne 'run') { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("pause: the program is not running (mode: $mode).") } }
                        Invoke-VsRetry { $dte.Debugger.Break($false) } | Out-Null
                        $deadline = (Get-Date).AddSeconds($VsPauseWaitSec)
                        while ((Get-VsModeName $dte) -in @('run', 'unknown') -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
                        $mode = Get-VsModeName $dte
                        $out.Add("PAUSED: DEBUG_MODE: $mode")
                        if ($mode -eq 'break') { $out.Add((Get-VsLocation $dte)) }
                    }
                    'eval' {
                        if (-not $arg -or $arg.Length -gt 200 -or $arg -match '[;\r\n]' -or $arg -match '\+\+|--' -or (Test-VsAssignment $arg)) {
                            return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("EVAL_REJECTED: only a read-only expression is allowed (no assignment, ++, --, ';'; 200 characters or less): $arg") }
                        }
                        $mode = Get-VsModeName $dte
                        if ($mode -ne 'break') { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("eval: not in break mode (mode: $mode).") } }
                        $hex = Use-VsDecimal $dte
                        try {
                        $ex = Invoke-VsRetry { $dte.Debugger.GetExpression($arg, $false, 5000) }
                        if ($ex -and $ex.IsValidValue) {
                            $exType = ""
                            try { if ($ex.Type) { $exType = "  ($($ex.Type))" } } catch { }
                            $out.Add("EVAL: $arg = $(Limit-VsText ([string]$ex.Value))$exType")
                        } else {
                            $exMsg = ""
                            try { $exMsg = Limit-VsText ([string]$ex.Value) } catch { }
                            $out.Add("EVAL_ERROR: $arg : $exMsg")
                        }
                        } finally { Restore-VsHex $dte $hex }
                    }
                    'inspect' {
                        if ($arg) { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("inspect takes no argument") } }
                        $mode = Get-VsModeName $dte
                        if ($mode -eq 'run' -and $debugStarted) {
                            # The first start of an app can take longer than the break wait of debug. Wait more, only when this run started the debug.
                            $deadline = (Get-Date).AddSeconds($VsInspectExtraWaitSec)
                            while ((Get-VsModeName $dte) -in @('run', 'unknown') -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }   # just before break, the mode can read unknown for a moment
                            Start-Sleep -Milliseconds 500
                            $mode = Get-VsModeName $dte
                            $out.Add("NOTE: the app was still starting; inspect waited for the break (up to ${VsInspectExtraWaitSec}s more). The mode is now $mode.")
                        }
                        if ($mode -ne 'break') { $out.Add("INSPECT_SKIP: the mode is $mode (not break). Use inspect only while the app is stopped at a breakpoint or an exception.") }
                        else { foreach ($l in (Get-VsInspectLines $dte)) { $out.Add($l) } }
                    }
                    'output' {
                        if ($arg -notmatch '^[0-9]{1,3}$' -or [int]$arg -lt 1 -or [int]$arg -gt $VsOutputMaxLines) { return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("output: use <lines> from 1 to $($VsOutputMaxLines): $arg") } }
                        $want = [int]$arg
                        $pane = Get-VsOutputPane $dte
                        $text = $pane.Text
                        if ($null -eq $text) {
                            $out.Add("OUTPUT_UNAVAILABLE: the Debug pane of the Output window was not found (no debug session has run in this Visual Studio, or its GUID differs). Panes: $($pane.Panes)")
                        } else {
                            $all = @($text -split "`r?`n")
                            if ($all.Count -gt 0 -and $all[$all.Count - 1] -eq '') { $all = @($all | Select-Object -First ($all.Count - 1)) }   # the text ends with a newline
                            $total = $all.Count
                            $tail = @($all | Select-Object -Last $want)
                            $body = ($tail -join "`r`n")
                            if ($body.Length -gt $VsOutputMaxChars) { $body = $body.Substring($body.Length - $VsOutputMaxChars) }
                            [System.IO.File]::WriteAllText($VsDebugOutputFile, $body + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
                            $out.Add("OUTPUT: file=vs_debug_output.txt lines=$($tail.Count) total=$total")
                        }
                    }
                    'debug' {
                        $mode = Get-VsModeName $dte
                        if ($mode -ne 'design') { $out.Add("DEBUG_MODE: $mode"); return @{ Ok = $false; Env = $false; Lines = $out.ToArray() + @("debug: already running or stopped; not started again.") } }
                        Invoke-VsRetry { $dte.Debugger.Go($false) } | Out-Null
                        $deadline = (Get-Date).AddSeconds(30)
                        while ((Get-VsModeName $dte) -in @('design', 'unknown') -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }   # right after Go the mode can be unknown (the app is starting)
                        # "run" begins when the app is launched, before it reaches the first breakpoint. Wait for break (or for the app to end).
                        $deadline = (Get-Date).AddSeconds($VsBreakWaitSec)
                        while ((Get-VsModeName $dte) -eq 'run' -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
                        $deadline = (Get-Date).AddSeconds($VsUnknownWaitSec)
                        while ((Get-VsModeName $dte) -eq 'unknown' -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
                        Start-Sleep -Milliseconds 500
                        $mode = Get-VsModeName $dte
                        $debugStarted = $true
                        $out.Add("DEBUG_STARTED")
                        $out.Add("DEBUG_MODE: $mode")
                        if ($mode -eq 'break') { $out.Add((Get-VsLocation $dte)) }
                        if ($mode -eq 'run') { $out.Add("NOTE: no breakpoint was hit within ${VsBreakWaitSec}s. The app is running (it may be waiting for the user, or the breakpoints may not be bound). Use status to check the mode again.") }
                        if ($mode -eq 'design') { $out.Add("NOTE: the mode is design (the app ended, or never started). The build may have failed or a dialog may be open in Visual Studio.") }
                    }
                }
            }
            default { return @{ Ok = $false; Env = $false; Lines = @("unknown operation: $op (open / status / reload / clear / break / debug / inspect / output / step / continue / pause / eval)") } }
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
