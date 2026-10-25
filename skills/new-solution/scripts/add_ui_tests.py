#!/usr/bin/env python3
"""add_ui_tests.py - 既存のソリューション (WPF / WinForms / MFC などの C++) に、UI テストのプロジェクト <アプリ名>.UITests (MSTest + FlaUI) を足す。

Usage:
  python3 add_ui_tests.py <SLN_DIR> [--app 名前] [--namespace NS] [--tfm net10.0] [--flaui-version 5.0.0]
                          [--mstest-version V] [--testsdk-version V] [--dry-run]

  <SLN_DIR>   .sln / .slnx のあるフォルダ
  --app       UI テストの対象のアプリのプロジェクト名。省略時: .slnx の DefaultStartup、なければ、WPF / WinForms の exe、なければ、C++ の Application
  --namespace UI テストの名前空間の根 (既定: アプリ名 (. を除く))

作るもの (<アプリ名>.UITests/):
  <アプリ名>.UITests.csproj   MSTest + FlaUI.Core + FlaUI.UIA3 (net10.0-windows)
  UiTestBase.cs               テストごとに、アプリを起動し、終了する。失敗したときは、ウィンドウのスクリーンショットを残す
  AppLocator.cs               アプリの exe を探す (UITEST_* の環境変数。WPF / WinForms: bin\\<構成>\\<TFM>\\、C++: <プラットフォーム>\\<構成>\\)
  Screenshots.cs              PrintWindow によるウィンドウのスクリーンショット (別のデスクトップでも、撮れる)
  UiNative.cs                 デスクトップ名、前面表示、操作の記録 (ui-trace.txt)
  MainWindowUiTests.cs        ひな形のテスト (WPF / WinForms の標準の View なら、入力 → 挨拶 → クリア。それ以外は、ウィンドウが開くだけ)
.slnx / .sln にも登録する。ウォッチャーの trigger_uitest.flag (uitest_once.sh) で実行する。通常のテスト (trigger_test.flag) には含まれない。
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FLAUI_VER = '5.0.0'


def die(msg, rc=1):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(rc)


def load_ap():
    d = os.path.join(HERE, '..', '..', 'wpf-test-first', 'scripts')
    if d not in sys.path:
        sys.path.insert(0, d)
    try:
        import add_project as AP
    except ImportError:
        die('wpf-test-first/scripts/add_project.py が見つからない (wpf-test-first Skill も、配布されている必要がある)')
    return AP


# ------------------------------------------------------------------ ひな形
CSPROJ = '''<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>__TFM__</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>__NS__.UITests</RootNamespace>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="__SDK__" />
    <PackageReference Include="MSTest.TestAdapter" Version="__MSTEST__" />
    <PackageReference Include="MSTest.TestFramework" Version="__MSTEST__" />
    <PackageReference Include="FlaUI.Core" Version="__FLAUI__" />
    <PackageReference Include="FlaUI.UIA3" Version="__FLAUI__" />
  </ItemGroup>

</Project>
'''

BASE_CS = '''using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.UIA3;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace __NS__.UITests;

/// <summary>
/// UI テストの基底。テストごとに、アプリを起動し、終了する。失敗したときは、ウィンドウのスクリーンショットを残す
/// (環境変数 UITEST_SCREENSHOT_DIR。ウォッチャーの trigger_uitest.flag が、渡す)。
/// 操作は、UIA のパターン (Invoke / Value) を使う。マウスやキーボードの入力は、使わない
/// (別のデスクトップでも動き、ユーザーの作業と干渉しない)。要素は、AutomationId で探す。
///
/// 動いたことを、確かめるために:
///  - 操作の記録 (トレース) を、ui-trace.txt (スクリーンショットと同じフォルダ) に残す。
///  - 環境変数 UITEST_SLOWMO_MS (ウォッチャーの -UiTestSlowMoMs) が 0 より大きいと、要素を探すたびに、その時間だけ待つ。
///    ユーザーのデスクトップ (WATCH_UI_DESKTOP=default) で実行すると、操作の様子を、目で見られる。
///    終了の前にも、その 2 倍の時間だけ、最後の状態を見せる。
/// </summary>
public abstract class UiTestBase
{
    public TestContext TestContext { get; set; } = null!;

    protected Application App { get; private set; } = null!;
    protected UIA3Automation Automation { get; private set; } = null!;
    protected Window MainWindow { get; private set; } = null!;

    /// <summary>対象のアプリのプロジェクト名 (= exe の名前)。</summary>
    protected virtual string AppName => "__APP__";

    private static int SlowMoMs =>
        int.TryParse(Environment.GetEnvironmentVariable("UITEST_SLOWMO_MS"), out var ms) && ms > 0 ? ms : 0;

    [TestInitialize]
    public void StartApp()
    {
        UiTrace.Write($"=== {TestContext.TestName}: start (desktop: {UiNative.DesktopName()}, slowmo: {SlowMoMs} ms)");
        var exe = AppLocator.Find(AppName);
        App = Application.Launch(exe);
        Automation = new UIA3Automation();
        MainWindow = App.GetMainWindow(Automation, TimeSpan.FromSeconds(15))
            ?? throw new InvalidOperationException("メインウィンドウが、15 秒以内に出ない: " + exe);
        UiTrace.Write($"launched: {exe} (title: {MainWindow.Title})");
        if (SlowMoMs > 0) UiNative.BringToFront(MainWindow);   // ユーザーのデスクトップで、見えるように、前面に出す
    }

    [TestCleanup]
    public void StopApp()
    {
        var outcome = TestContext.CurrentTestOutcome;
        try
        {
            if (outcome != UnitTestOutcome.Passed)
            {
                Screenshots.Save(MainWindow, TestContext.TestName ?? "test");
            }
            if (SlowMoMs > 0) Thread.Sleep(SlowMoMs * 2);   // 最後の状態を、見せる
        }
        catch (Exception)
        {
            // スクリーンショットの失敗で、テストの結果を、隠さない
        }

        try
        {
            App.Close();
            if (!WaitExit(5000)) App.Kill();
        }
        catch (Exception)
        {
        }
        Automation.Dispose();
        App.Dispose();
        UiTrace.Write($"=== {TestContext.TestName}: {outcome}");
    }

    /// <summary>AutomationId で、要素を探す。なければ、テストを失敗にする。(MFC のコントロールは、リソースのコントロール ID が、AutomationId)</summary>
    protected AutomationElement Find(string automationId)
    {
        UiTrace.Write($"find: {automationId}");
        if (SlowMoMs > 0) Thread.Sleep(SlowMoMs);
        return MainWindow.FindFirstDescendant(cf => cf.ByAutomationId(automationId))
            ?? throw new AssertFailedException($"AutomationId '{automationId}' の要素が、見つからない");
    }

    protected bool WaitExit(int timeoutMs)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < timeoutMs)
        {
            if (App.HasExited) return true;
            Thread.Sleep(100);
        }
        return App.HasExited;
    }

    /// <summary>条件が成り立つまで待つ (固定の Thread.Sleep を、使わない)。</summary>
    protected static bool WaitFor(Func<bool> condition, int timeoutMs = 5000)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < timeoutMs)
        {
            if (condition()) return true;
            Thread.Sleep(100);
        }
        return condition();
    }
}
'''

NATIVE_CS = '''using System.Runtime.InteropServices;
using FlaUI.Core.AutomationElements;

namespace __NS__.UITests;

/// <summary>デスクトップ名の取得、ウィンドウの前面表示、操作の記録 (トレース)。</summary>
internal static class UiNative
{
    [DllImport("user32.dll")] private static extern IntPtr GetThreadDesktop(int threadId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool GetUserObjectInformationW(IntPtr obj, int index, char[] info, int length, out int needed);
    [DllImport("kernel32.dll")] private static extern int GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);

    /// <summary>このスレッドが属するデスクトップの名前。ユーザーのデスクトップは "Default"。ウォッチャーの別のデスクトップは "ClaudeUiTest..."。</summary>
    public static string DesktopName()
    {
        var buf = new char[256];
        return GetUserObjectInformationW(GetThreadDesktop(GetCurrentThreadId()), 2 /* UOI_NAME */, buf, buf.Length * 2, out _)
            ? new string(buf).TrimEnd('\0') : "(取得できない)";
    }

    public static void BringToFront(AutomationElement window)
    {
        try { SetForegroundWindow(window.Properties.NativeWindowHandle.ValueOrDefault); }
        catch (Exception) { }
    }
}

/// <summary>操作の記録。スクリーンショットと同じフォルダの ui-trace.txt に、追記する (ウォッチャーが、実行の前に、フォルダを空にする)。</summary>
internal static class UiTrace
{
    private static readonly object Gate = new();

    public static void Write(string message)
    {
        try
        {
            lock (Gate)
            {
                File.AppendAllText(Path.Combine(Screenshots.Dir, "ui-trace.txt"),
                    $"{DateTime.Now:HH:mm:ss.fff} {message}{Environment.NewLine}");
            }
        }
        catch (Exception)
        {
        }
    }
}
'''


LOCATOR_CS = '''namespace __NS__.UITests;

/// <summary>アプリの exe を探す。ウォッチャー (trigger_uitest.flag) が、環境変数 UITEST_SOLUTION_DIR / UITEST_CONFIGURATION / UITEST_PLATFORM を渡す。</summary>
internal static class AppLocator
{
    public static string Find(string appName)
    {
        var sol = Environment.GetEnvironmentVariable("UITEST_SOLUTION_DIR") ?? FindSolutionDir();
        var cfg = Environment.GetEnvironmentVariable("UITEST_CONFIGURATION") ?? "Debug";
        var platform = Environment.GetEnvironmentVariable("UITEST_PLATFORM");
        var candidates = new List<string>();

        // .NET (WPF): <ソリューション>\\<アプリ>\\bin\\<構成>\\<TFM>\\<アプリ>.exe (プラットフォーム別の出力: bin\\<プラットフォーム>\\<構成>\\<TFM>)
        var bin = Path.Combine(sol, appName, "bin");
        if (Directory.Exists(bin))
        {
            var sep = Path.DirectorySeparatorChar;
            candidates.AddRange(Directory.EnumerateFiles(bin, appName + ".exe", SearchOption.AllDirectories)
                .Where(p => p.Contains(sep + cfg + sep)));
        }

        // C++ (MFC など): <ソリューション>\\<プラットフォーム>\\<構成>\\<アプリ>.exe
        foreach (var plat in new[] { platform, "x64", "Win32", "ARM64" }.Where(x => !string.IsNullOrEmpty(x)).Distinct())
        {
            var p = Path.Combine(sol, plat!, cfg, appName + ".exe");
            if (File.Exists(p)) candidates.Add(p);
        }

        return candidates.OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault()
            ?? throw new FileNotFoundException(
                $"アプリの exe が、見つからない: {appName}.exe (ソリューション: {sol}、構成: {cfg})。先に、ビルドすること");
    }

    private static string FindSolutionDir()
    {
        var d = new DirectoryInfo(AppContext.BaseDirectory);
        while (d != null)
        {
            if (d.EnumerateFiles("*.slnx").Any() || d.EnumerateFiles("*.sln").Any()) return d.FullName;
            d = d.Parent;
        }
        return AppContext.BaseDirectory;
    }
}
'''

SHOTS_CS = '''using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace __NS__.UITests;

/// <summary>
/// テストのプロセスを、DPI 対応 (Per-Monitor V2) にする。アセンブリの読み込み時に、1 回だけ (ウィンドウや UI Automation を使う前)。
/// 非対応のままだと、UI Automation の矩形が縮小されて、スクリーンショットの右下が切れる。
/// </summary>
internal static class DpiAwareness
{
    [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [ModuleInitializer]
    internal static void Enable()
    {
        try
        {
            SetProcessDpiAwarenessContext(new IntPtr(-4));   // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2。すでに決まっていれば、失敗するだけ
        }
        catch (Exception)
        {
        }
    }
}

/// <summary>
/// ウィンドウのスクリーンショットを、PNG で保存する (WSL の Claude が、画像として読める)。
/// PrintWindow (ウィンドウ自身に描かせる) を使う: 別のデスクトップでは、画面のコピーが、黒くなる。
/// (WPF は、ハードウェアアクセラレーションの描画だと、白くなる。ウォッチャーが、別のデスクトップの UI テストの間だけ、ソフトウェアレンダリングにする。)
/// ユーザーのデスクトップで、PrintWindow の結果が、空白 (1 色) だったときは、画面のコピー (FlaUI の Capture) に切り替える。
/// </summary>
internal static class Screenshots
{
    [DllImport("user32.dll")] private static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsProcessDPIAware();

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    public static string Dir
    {
        get
        {
            var d = Environment.GetEnvironmentVariable("UITEST_SCREENSHOT_DIR");
            if (string.IsNullOrEmpty(d)) d = Path.Combine(AppContext.BaseDirectory, "ui-screenshots");
            return Directory.CreateDirectory(d).FullName;
        }
    }

    public static void Save(FlaUI.Core.AutomationElements.AutomationElement window, string testName)
    {
        var name = string.Concat(testName.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));
        var path = Path.Combine(Dir, name + "-window.png");
        var hwnd = window.Properties.NativeWindowHandle.ValueOrDefault;
        var r = window.BoundingRectangle;
        // UIA の矩形と、ウィンドウ自身の矩形 (GetWindowRect) の、大きいほうに合わせる
        var width = r.Width;
        var height = r.Height;
        if (GetWindowRect(hwnd, out var wr))
        {
            width = Math.Max(width, wr.Right - wr.Left);
            height = Math.Max(height, wr.Bottom - wr.Top);
        }
        // このプロセスが DPI 非対応だと、矩形は、縮小された値で返る (PrintWindow は、実際の大きさで描くので、右下が切れる。実機で確認)。
        // 起動時に DPI 対応にしている (DpiAwareness) が、できなかったときは、対象のウィンドウの DPI で、拡大する。
        var dpi = GetDpiForWindow(hwnd);
        if (dpi > 96 && !IsProcessDPIAware())
        {
            width = (int)Math.Ceiling(width * dpi / 96.0);
            height = (int)Math.Ceiling(height * dpi / 96.0);
        }
        using var bmp = new System.Drawing.Bitmap(Math.Max(1, width), Math.Max(1, height));
        using (var g = System.Drawing.Graphics.FromImage(bmp))
        {
            var hdc = g.GetHdc();
            try { PrintWindow(hwnd, hdc, 2 /* PW_RENDERFULLCONTENT */); }
            finally { g.ReleaseHdc(hdc); }
        }
        if (IsBlank(bmp) && UiNative.DesktopName() == "Default")
        {
            FlaUI.Core.Capturing.Capture.Element(window).ToFile(path);   // ユーザーのデスクトップなら、画面のコピーで、撮れる
            UiTrace.Write("screenshot: PrintWindow was blank; used a screen capture");
            return;
        }
        bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        UiTrace.Write("screenshot: " + path);
    }

    /// <summary>格子状に、点を取って、すべて同じ色なら、空白とみなす。</summary>
    private static bool IsBlank(System.Drawing.Bitmap bmp)
    {
        var first = bmp.GetPixel(0, 0);
        for (var x = 0; x < bmp.Width; x += Math.Max(1, bmp.Width / 10))
        {
            for (var y = 0; y < bmp.Height; y += Math.Max(1, bmp.Height / 10))
            {
                if (bmp.GetPixel(x, y) != first) return false;
            }
        }
        return true;
    }
}
'''


TESTS_WPF_CS = '''using FlaUI.Core.AutomationElements;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace __NS__.UITests;

/// <summary>ひな形の UI テスト (WPF の標準の View: NameTextBox / GreetingText / ClearButton)。画面に合わせて、書き換える。</summary>
[TestClass]
public class MainWindowUiTests : UiTestBase
{
    [TestMethod]
    public void MainWindow_Opens_WithTitle()
    {
        Assert.IsFalse(string.IsNullOrEmpty(MainWindow.Title));
    }

    [TestMethod]
    public void Greeting_NameEntered_ShowsGreeting()
    {
        var name = Find("NameTextBox").AsTextBox();
        name.Text = "太郎";   // ValuePattern (キー入力を使わない)

        Assert.IsTrue(WaitFor(() => Find("GreetingText").Name == "こんにちは、太郎 さん"),
            "挨拶が、変わらない: " + Find("GreetingText").Name);
    }

    [TestMethod]
    public void ClearButton_Invoked_ClearsName()
    {
        var name = Find("NameTextBox").AsTextBox();
        name.Text = "太郎";
        Assert.IsTrue(WaitFor(() => Find("ClearButton").IsEnabled), "クリアボタンが、有効にならない");

        Find("ClearButton").AsButton().Invoke();   // InvokePattern (マウスを使わない)

        Assert.IsTrue(WaitFor(() => string.IsNullOrEmpty(name.Text)), "クリアしても、入力欄が空にならない");
    }
}
'''

TESTS_WINFORMS_CS = '''using FlaUI.Core.AutomationElements;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace __NS__.UITests;

/// <summary>ひな形の UI テスト (WinForms の標準の Form: NameTextBox / GreetingLabel / ClearButton。AutomationId は、コントロールの Name)。画面に合わせて、書き換える。</summary>
[TestClass]
public class MainWindowUiTests : UiTestBase
{
    [TestMethod]
    public void MainWindow_Opens_WithTitle()
    {
        Assert.IsFalse(string.IsNullOrEmpty(MainWindow.Title));
    }

    [TestMethod]
    public void Greeting_NameEntered_ShowsGreeting()
    {
        var name = Find("NameTextBox").AsTextBox();
        name.Text = "太郎";   // ValuePattern (キー入力を使わない。TextChanged が起きる)

        Assert.IsTrue(WaitFor(() => Find("GreetingLabel").Name == "こんにちは、太郎 さん"),
            "挨拶が、変わらない: " + Find("GreetingLabel").Name);
    }

    [TestMethod]
    public void ClearButton_Invoked_ClearsName()
    {
        var name = Find("NameTextBox").AsTextBox();
        name.Text = "太郎";
        Assert.IsTrue(WaitFor(() => Find("ClearButton").IsEnabled), "クリアボタンが、有効にならない");

        Find("ClearButton").AsButton().Invoke();   // InvokePattern (マウスを使わない)

        Assert.IsTrue(WaitFor(() => string.IsNullOrEmpty(name.Text)), "クリアしても、入力欄が空にならない");
    }
}
'''

TESTS_GENERIC_CS = '''using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace __NS__.UITests;

/// <summary>
/// ひな形の UI テスト。ウィンドウが開くことだけを、確かめる。画面に合わせて、テストを足す。
///  - WPF: 操作したいコントロールに、AutomationProperties.AutomationId を付ける。Find("Id") で探し、
///    AsTextBox().Text = "..." (ValuePattern) / AsButton().Invoke() (InvokePattern) で操作する。
///  - WinForms: 操作したいコントロールに、Name を付ける (Name が、AutomationId になる)。使い方は、WPF と同じ。
///  - MFC: コントロールの ID (リソースの ID の数値。IDOK = "1"、IDCANCEL = "2") が、AutomationId。IDC_STATIC は、ID で探せない (Name = 表示の文字)。
/// </summary>
[TestClass]
public class MainWindowUiTests : UiTestBase
{
    [TestMethod]
    public void MainWindow_Opens_WithTitle()
    {
        Assert.IsFalse(string.IsNullOrEmpty(MainWindow.Title));
    }
}
'''


# ------------------------------------------------------------------ ソリューションの読み取り
def project_paths(sln_path):
    text = open(sln_path, encoding='utf-8-sig').read()
    if sln_path.lower().endswith('.slnx'):
        items = [(m.group(1), 'DefaultStartup="true"' in m.group(0))
                 for m in re.finditer(r'<Project\s+[^>]*?Path="([^"]+\.(?:csproj|vcxproj))"[^>]*/?>', text, re.I)]
    else:
        items = [(m.group(1), False) for m in re.finditer(r'Project\("\{[^}]+\}"\)\s*=\s*"[^"]*"\s*,\s*"([^"]+\.(?:csproj|vcxproj))"', text, re.I)]
    return [(p.replace('\\', '/'), start) for p, start in items]


def classify(sln_dir, rel):
    """('wpf' | 'winforms' | 'cpp' | None, 名前, TFM)"""
    path = os.path.join(sln_dir, *rel.split('/'))
    name = os.path.splitext(os.path.basename(rel))[0]
    if not os.path.isfile(path):
        return None, name, None
    text = open(path, encoding='utf-8-sig', errors='replace').read()
    if rel.lower().endswith('.csproj'):
        if re.search(r'<UseWPF>\s*true\s*</UseWPF>', text, re.I) and re.search(r'<OutputType>\s*(Win)?Exe\s*</OutputType>', text, re.I):
            tfm = re.search(r'<TargetFramework>([^<]+)</TargetFramework>', text)
            return 'wpf', name, tfm.group(1) if tfm else None
        if re.search(r'<UseWindowsForms>\s*true\s*</UseWindowsForms>', text, re.I) and re.search(r'<OutputType>\s*(Win)?Exe\s*</OutputType>', text, re.I):
            tfm = re.search(r'<TargetFramework>([^<]+)</TargetFramework>', text)
            return 'winforms', name, tfm.group(1) if tfm else None
        return None, name, None
    if re.search(r'<ConfigurationType>\s*Application\s*</ConfigurationType>', text):
        return 'cpp', name, None
    return None, name, None


def choose_app(sln_dir, sln_path, app_arg):
    projs = [(rel, start, *classify(sln_dir, rel)) for rel, start in project_paths(sln_path)]
    apps = [p for p in projs if p[2] and not re.search(r'(Tests?|UITests)$', p[3])]
    if app_arg:
        for p in apps:
            if p[3] == app_arg:
                return p
        die(f'--app {app_arg} が、アプリ (WPF / WinForms の exe / C++ の Application) として見つからない。候補: {", ".join(p[3] for p in apps) or "なし"}')
    if not apps:
        die('UI テストの対象にできるアプリ (WPF / WinForms の exe / C++ の Application) が、ソリューションにない')
    started = [p for p in apps if p[1]]
    if started:
        return started[0]
    dotnet_gui = [p for p in apps if p[2] in ('wpf', 'winforms')]
    return (dotnet_gui or apps)[0]


def fill(t, **kv):
    for k, v in kv.items():
        t = t.replace(f'__{k}__', v)
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir')
    ap.add_argument('--app')
    ap.add_argument('--namespace')
    ap.add_argument('--tfm')
    ap.add_argument('--flaui-version', default=FLAUI_VER)
    ap.add_argument('--mstest-version')
    ap.add_argument('--testsdk-version')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--refresh-support-files', action='store_true', help='すでにある <アプリ名>.UITests の、UiTestBase.cs / AppLocator.cs / Screenshots.cs / UiNative.cs を、最新のひな形で上書きする (テストの本体 MainWindowUiTests.cs は、触らない)。CLAUDE.md の節も、更新する')
    ap.add_argument('--refresh-claude-md', action='store_true', help='すでにある <アプリ名>.UITests は、そのままにして、CLAUDE.md の「UI テスト (FlaUI)」の節だけを、最新にする')
    a = ap.parse_args()

    AP = load_ap()
    sln_dir = os.path.abspath(a.dir)
    if not os.path.isdir(sln_dir):
        die(f'フォルダがない: {a.dir}')
    sln = AP.find_solution(sln_dir)
    rel, _start, kind, app, app_tfm = choose_app(sln_dir, sln, a.app)
    ui = app + '.UITests'
    if a.refresh_claude_md:
        print(update_claude_md(sln_dir, ui, app, refresh=True))
        return
    if a.refresh_support_files:
        if not os.path.isdir(os.path.join(sln_dir, ui)):
            die(f'{ui} がない (先に、add_ui_tests.py で足す)')
        ns0 = a.namespace or AP.type_prefix(app)
        kv0 = dict(NS=ns0, APP=app, TFM='', SDK='', MSTEST='', FLAUI='')
        sup = {f'{ui}/UiTestBase.cs': fill(BASE_CS, **kv0), f'{ui}/AppLocator.cs': fill(LOCATOR_CS, **kv0),
               f'{ui}/Screenshots.cs': fill(SHOTS_CS, **kv0), f'{ui}/UiNative.cs': fill(NATIVE_CS, **kv0)}
        for r in sup:
            print(f'  ~ {r}')
        if a.dry_run:
            print('(dry-run: 何も書いていない)')
            return
        AP.write_files(sln_dir, sup)
        print(update_claude_md(sln_dir, ui, app, refresh=True))
        print('完了。テストの本体 (MainWindowUiTests.cs) は、変えていない。')
        return
    if os.path.exists(os.path.join(sln_dir, ui)):
        die(f'すでに存在する: {ui} (何も書いていない)', 3)
    for v in (a.flaui_version, a.mstest_version or AP.MSTEST_VER, a.testsdk_version or AP.TESTSDK_VER):
        if not re.match(r'^[0-9][0-9A-Za-z.+-]{0,63}$', v):
            die(f'バージョンが不正: {v}')
    ns = a.namespace or AP.type_prefix(app)
    if not all(re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', x) for x in ns.split('.')):
        die(f'名前空間が不正: {ns}')
    tfm = AP.windows_tfm(a.tfm or (app_tfm.replace('-windows', '') if app_tfm else AP.DEFAULT_TFM))
    if not re.match(r'^net\d+\.\d+-windows$', tfm):
        die(f'TFM が不正: {tfm}')

    # ひな形の View (標準) かを、調べる (NameTextBox / GreetingText / ClearButton の AutomationId)
    standard = False
    if kind == 'wpf':
        xaml = os.path.join(sln_dir, app, 'Views', 'MainWindow.xaml')
        if os.path.isfile(xaml):
            t = open(xaml, encoding='utf-8-sig').read()
            standard = all(f'AutomationId="{i}"' in t for i in ('NameTextBox', 'GreetingText', 'ClearButton'))
    elif kind == 'winforms':
        designer = os.path.join(sln_dir, app, 'Forms', 'MainForm.Designer.cs')
        if os.path.isfile(designer):
            t = open(designer, encoding='utf-8-sig').read()
            standard = all(f'{i}.Name = "{i}";' in t for i in ('NameTextBox', 'GreetingLabel', 'ClearButton'))

    kv = dict(NS=ns, APP=app, TFM=tfm, SDK=a.testsdk_version or AP.TESTSDK_VER, MSTEST=a.mstest_version or AP.MSTEST_VER, FLAUI=a.flaui_version)
    files = {
        f'{ui}/{ui}.csproj': fill(CSPROJ, **kv),
        f'{ui}/UiTestBase.cs': fill(BASE_CS, **kv),
        f'{ui}/AppLocator.cs': fill(LOCATOR_CS, **kv),
        f'{ui}/Screenshots.cs': fill(SHOTS_CS, **kv),
        f'{ui}/UiNative.cs': fill(NATIVE_CS, **kv),
        f'{ui}/MainWindowUiTests.cs': fill((TESTS_WINFORMS_CS if kind == 'winforms' else TESTS_WPF_CS) if standard else TESTS_GENERIC_CS, **kv),
    }
    print(f'ソリューション : {os.path.basename(sln)}')
    print(f'対象のアプリ   : {app} ({"WPF" if kind == "wpf" else "WinForms" if kind == "winforms" else "C++ (MFC など)"}。{rel})')
    print(f'UI テスト      : {ui} (MSTest {kv["MSTEST"]} + FlaUI {kv["FLAUI"]} (UIA3)、{tfm})')
    print(f'ひな形のテスト : {("WPF" if kind == "wpf" else "WinForms") + " の標準の View (入力 → 挨拶 → クリア)" if standard else "ウィンドウが開くことだけ (画面に合わせて、足す)"}')
    for r in files:
        print(f'  + {r}')
    print(f'  ~ {os.path.basename(sln)} (1 プロジェクトを追加)')
    if kind == 'cpp':
        print('NOTE: C++ のソリューションに、.NET のプロジェクトが加わる (混在)。ウォッチャーは、C++ と .NET の両方をビルドする (docs/DESIGN.md 4.24)。')
    if kind == 'wpf' and not standard:
        print('NOTE: View に AutomationProperties.AutomationId が、見つからない。操作したいコントロールに、付けること (wpf-check の UI002)。')
    if kind == 'winforms' and not standard:
        print('NOTE: 標準の MainForm (NameTextBox / GreetingLabel / ClearButton) ではない。操作したいコントロールに、Name を付けること (Name が AutomationId になる)。')
    if a.dry_run:
        print('NUGET: 初回のビルドで、MSTest と FlaUI を復元する (ホストが nuget.org に届くこと)')
        print('(dry-run: 何も書いていない)')
        return
    AP.write_files(sln_dir, files)
    AP.register(sln, [(ui, AP.new_guid())])
    print(update_claude_md(sln_dir, ui, app))
    print('完了。実行: uitest_once.sh (ウォッチャーの trigger_uitest.flag)。NuGet の復元は、ウォッチャーのビルドが行う。')


def claude_md_section(ui, app):
    return f'''## UI テスト (FlaUI)
- `{ui}` (MSTest + FlaUI.UIA3)。`{app}` の exe を、テストごとに起動して、UIA のパターン (Invoke / Value) で操作する。**マウス・キーボードの入力は使わない。**
- **流れ: テスト先行 (Red) → 実装 → ビルド → テスト (Green、`build_test_once.sh` が `PASSED`) の「あとに、追加で」、UI テストを実行する。** **全テストが `PASSED` になったら、続けて `uitest_once.sh "$PWD" 900` を実行すること** (`~/.claude/skills/build-test-loop/scripts/uitest_once.sh`。画面を伴う変更のとき。Green になってから 1 回)。UI テストを、先に書く (UI テストファースト) ことは、しない。
- **通常のテスト (`build_test_once.sh`) には、含まれない。** 別のデスクトップで実行され (`-UiTestDesktop separate`)、ユーザーの画面を乱さない。「マウスとキーボードに触らないで」と頼む必要は、ない。
- 要素は、**AutomationId** で探す (WPF: `AutomationProperties.AutomationId`。WinForms: コントロールの `Name`。MFC: コントロールの ID の数値)。失敗したときは、`.claude-logs/ui-screenshots/*.png` を、Read ツールで開いて、画面の状態を見る。仕様変更で、期待値が古くなったなら、画面の実際の状態を確認して、期待値を直す (アサーションを弱めない)。
- 書き方の規約と手順: `build-test-loop` の「UI テスト」。
'''


def update_claude_md(sln_dir, ui, app, refresh=False):
    p = os.path.join(sln_dir, 'CLAUDE.md')
    if not os.path.isfile(p):
        return 'CLAUDE.md がない (何も更新していない)'
    text = open(p, encoding='utf-8').read()
    sec = claude_md_section(ui, app)
    if '## UI テスト (FlaUI)' in text:
        if not refresh:
            return 'CLAUDE.md は、すでに「UI テスト (FlaUI)」がある (更新するなら --refresh-claude-md)'
        i = text.index('## UI テスト (FlaUI)')
        m = re.search(r'^## ', text[i + 3:], re.M)
        j = i + 3 + m.start() if m else len(text)
        text = text[:i] + sec + ('\n' + text[j:] if m else '')
        note = 'CLAUDE.md の「UI テスト (FlaUI)」を更新した'
    else:
        text = text.rstrip('\n') + '\n\n' + sec
        note = 'CLAUDE.md に「UI テスト (FlaUI)」を追記した'
    with open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    return note


if __name__ == '__main__':
    main()
