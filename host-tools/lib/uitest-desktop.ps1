# lib\uitest-desktop.ps1 - UI テストを実行するデスクトップの基盤 (別デスクトップでの実行、WPF のソフトウェアレンダリング)
# watch_and_build.ps1 から、ドットソース (同じスコープに読み込む) で使う。単独では実行しない。

function Initialize-UiDesktopRunner {
    if ("UiDesktopRunner" -as [type]) { return }
    Write-UiTiming "Initialize-UiDesktopRunner: compiling the desktop runner (Add-Type; first time only)"
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

// UI テストを、別のデスクトップ (Win32 の CreateDesktop) で実行する。ユーザーの画面に、ウィンドウが出ず、フォーカスも奪わない。
// プロセスは、ジョブオブジェクト (KILL_ON_JOB_CLOSE) に入れる: 終了後 / 時間切れのとき、テストが起動して残ったアプリを、すべて終了する。
public static class UiDesktopRunner
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS { public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount; }
    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation; public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateDesktopW(string name, IntPtr device, IntPtr devmode, int flags, uint access, IntPtr sa);
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateJobObjectW(IntPtr sa, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, int size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint WaitForSingleObject(IntPtr handle, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    const uint GENERIC_ALL = 0x10000000;
    const uint CREATE_SUSPENDED = 0x00000004;
    const uint CREATE_NO_WINDOW = 0x08000000;
    const int STARTF_USESTDHANDLES = 0x00000100;
    const uint HANDLE_FLAG_INHERIT = 1;
    const uint WAIT_TIMEOUT = 0x00000102;
    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
    const int JobObjectExtendedLimitInformation = 9;

    static IntPtr Inheritable(FileStream fs)
    {
        IntPtr h = fs.SafeFileHandle.DangerousGetHandle();
        if (!SetHandleInformation(h, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT)) throw new Win32Exception(Marshal.GetLastWin32Error());
        return h;
    }

    // 戻り値: 終了コード (時間切れのときは -1)。timedOut: 制限時間を超えて、強制終了したか。
    public static int Run(string commandLine, string workDir, string desktopName, string outPath, string errPath, int timeoutMs, out bool timedOut)
    {
        timedOut = false;
        IntPtr desk = CreateDesktopW(desktopName, IntPtr.Zero, IntPtr.Zero, 0, GENERIC_ALL, IntPtr.Zero);
        if (desk == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateDesktop failed");
        IntPtr job = IntPtr.Zero;
        PROCESS_INFORMATION pi = new PROCESS_INFORMATION();
        bool started = false;
        FileStream fsOut = null, fsErr = null, fsIn = null;
        try
        {
            fsOut = new FileStream(outPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
            fsErr = new FileStream(errPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
            try { fsIn = new FileStream(@"\\.\NUL", FileMode.Open, FileAccess.Read, FileShare.ReadWrite); } catch (Exception) { fsIn = null; }

            job = CreateJobObjectW(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObject failed");
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, ref info, Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION))))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SetInformationJobObject failed");

            STARTUPINFO si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            si.lpDesktop = "WinSta0\\" + desktopName;
            si.dwFlags = STARTF_USESTDHANDLES;
            si.hStdInput = (fsIn != null) ? Inheritable(fsIn) : IntPtr.Zero;
            si.hStdOutput = Inheritable(fsOut);
            si.hStdError = Inheritable(fsErr);

            StringBuilder cmd = new StringBuilder(commandLine);
            if (!CreateProcessW(null, cmd, IntPtr.Zero, IntPtr.Zero, true, CREATE_SUSPENDED | CREATE_NO_WINDOW, IntPtr.Zero, workDir, ref si, out pi))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateProcess failed");
            started = true;
            if (!AssignProcessToJobObject(job, pi.hProcess)) throw new Win32Exception(Marshal.GetLastWin32Error(), "AssignProcessToJobObject failed");
            ResumeThread(pi.hThread);

            uint w = WaitForSingleObject(pi.hProcess, (uint)timeoutMs);
            int exit;
            if (w == WAIT_TIMEOUT)
            {
                timedOut = true;
                exit = -1;
            }
            else
            {
                uint code;
                exit = GetExitCodeProcess(pi.hProcess, out code) ? unchecked((int)code) : -2;
            }
            // 時間切れでも、正常終了でも、ジョブの中のプロセス (テストが起動して、残ったアプリ) を、すべて終了する
            TerminateJobObject(job, 1);
            WaitForSingleObject(pi.hProcess, 5000);
            return exit;
        }
        finally
        {
            if (started)
            {
                if (job != IntPtr.Zero) TerminateJobObject(job, 1);
                CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
            }
            if (job != IntPtr.Zero) CloseHandle(job);
            if (fsIn != null) fsIn.Dispose();
            if (fsOut != null) fsOut.Dispose();
            if (fsErr != null) fsErr.Dispose();
            CloseDesktop(desk);
        }
    }
}
'@
}

# 別のデスクトップでは、WPF の画面を PrintWindow で撮ると、クライアント領域が白くなる (ハードウェアアクセラレーションの描画。実機で確認)。
# UI テストの間だけ、ユーザーの WPF の描画を、ソフトウェアレンダリングにする (HKCU の DisableHWAcceleration=1)。WPF は、プロセスの起動時に読む。
# **元の値を、変更する前に、ファイルに記録する** (absent = もともと無い / 数値)。終わったら、記録から、元に戻して、記録を消す。
# ウォッチャーが、途中で異常終了して、記録が残っていたら、**次の起動時に、元に戻す** (Restore-WpfRendering を、起動時にも呼ぶ)。
# 記録は、ウォッチャーの間で共有する (最初に変えた時の、元の値を、守る。UI テストを、同時に 2 つは、実行しない前提)。
$WpfHwAccelKey = 'HKCU:\Software\Microsoft\Avalon.Graphics'
$WpfHwAccelBackup = Join-Path $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:TEMP }) "claude-watcher\wpf-hwaccel-backup.txt"
function Set-WpfSoftwareRendering {
    try {
        if (-not (Test-Path -LiteralPath $WpfHwAccelBackup)) {   # すでにあれば、元の値は、記録済み (前回の残り)
            if (-not (Test-Path -LiteralPath $WpfHwAccelKey)) { New-Item -Path $WpfHwAccelKey -Force | Out-Null }
            $prev = (Get-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -ErrorAction SilentlyContinue).DisableHWAcceleration
            New-Item -ItemType Directory -Path (Split-Path -Parent $WpfHwAccelBackup) -Force | Out-Null
            [System.IO.File]::WriteAllText($WpfHwAccelBackup, $(if ($null -eq $prev) { "absent" } else { "$prev" }))
        }
        Set-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -Value 1 -Type DWord
        Write-Host "[UITEST] WPF software rendering ON (HKCU Avalon.Graphics DisableHWAcceleration=1; the original value is recorded and restored after the run)" -ForegroundColor DarkGray
    } catch {
        Write-Host "[UITEST] could not set WPF software rendering: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
function Restore-WpfRendering {
    if (-not (Test-Path -LiteralPath $WpfHwAccelBackup)) { return }
    try {
        $v = ([System.IO.File]::ReadAllText($WpfHwAccelBackup)).Trim()
        # 失敗を、握りつぶさない (-ErrorAction Stop)。以前は SilentlyContinue で、失敗しても「復元した」と表示した (UT14b の実機で発見)
        if ($v -eq "absent") {
            if (Get-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -ErrorAction Stop
            }
        } else {
            Set-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -Value ([int]$v) -Type DWord -ErrorAction Stop
        }
        # 実際に戻ったかを、確かめてから、記録を消す
        $now = (Get-ItemProperty -LiteralPath $WpfHwAccelKey -Name DisableHWAcceleration -ErrorAction SilentlyContinue).DisableHWAcceleration
        $expected = if ($v -eq "absent") { $null } else { [int]$v }
        if ("$now" -ne "$expected") { throw "the registry value is still '$now' (expected '$expected')" }
        Remove-Item -LiteralPath $WpfHwAccelBackup -ErrorAction Stop
        if (Test-Path -LiteralPath $WpfHwAccelBackup) { throw "the backup file could not be deleted" }
        Write-Host "[UITEST] WPF rendering setting restored ($v)" -ForegroundColor DarkGray
    } catch {
        Write-Host "[UITEST] could not restore the WPF rendering setting: $($_.Exception.GetType().Name): $($_.Exception.Message) (backup file: $WpfHwAccelBackup)" -ForegroundColor Yellow
    }
}

# 別のデスクトップで、子プロセスを、制限時間つきで実行する。戻り値は、Invoke-TestProcess と同じ形。
function Invoke-TestProcessOnDesktop([string]$filePath, [string]$argString, [string]$workDir, [int]$limit, [string]$outTmp, [string]$errTmp) {
    Initialize-UiDesktopRunner
    $cmdLine = '"' + $filePath + '"' + $(if ($argString) { " " + $argString } else { "" })
    $timedOut = $false
    $exit = [UiDesktopRunner]::Run($cmdLine, $workDir, ("ClaudeUiTest" + $PID), $outTmp, $errTmp, ($limit * 1000), [ref]$timedOut)
    $lines = @()
    foreach ($f in @($outTmp, $errTmp)) {
        $lines += @(Read-ProcessOutput $f)
    }
    Remove-Item -LiteralPath $outTmp, $errTmp -ErrorAction SilentlyContinue
    $code = if ($timedOut) { $null } else { $exit }
    return @{ Timeout = $timedOut; ExitCode = $code; Output = $lines }
}
