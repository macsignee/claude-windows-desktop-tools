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
  UiDialogs.cs                ダイアログ・メニュー・コンボ・スライダーなどの、操作の道具 (WinForms / WPF / MFC で、実機で確かめた方法を、FrameworkId で、自動で切り替える)
  uitest.settings             UI テストの既定 (desktop=visible: ユーザーのデスクトップ / separate: 別のデスクトップ、slowmo=N)。WPF は visible (WPF のメニューは、別のデスクトップで開かない)、それ以外は separate。ウォッチャーが読む
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

    /// <summary>ダイアログを開くボタン / メニュー項目を押して、モーダルなダイアログが、出るのを待つ (UiDialogs.Click が、フレームワークに合う方法で、押す)。MessageBox・ファイルダイアログも、同じ。</summary>
    protected Window OpenModal(AutomationElement opener)
    {
        var how = UiDialogs.Click(opener);
        UiTrace.Write($"open modal: {opener.Name} ({how})");
        return UiDialogs.WaitModal(MainWindow) ?? throw new AssertFailedException("モーダルなダイアログが、main.ModalWindows に出ない");
    }

    protected bool WaitModalClosed() => UiDialogs.WaitModalClosed(MainWindow);

    /// <summary>モードレスなウィンドウを、タイトルで待つ (メインの子 / トップレベルの、両方を探す)。</summary>
    protected Window? WaitWindow(string title) => UiDialogs.WaitWindow(App, Automation, MainWindow, title);

    protected bool WaitWindowClosed(string title) => UiDialogs.WaitWindowClosed(App, Automation, MainWindow, title);

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

DIALOGS_CS = r'''using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace __NS__.UITests;

/// <summary>
/// ダイアログ・メニュー・コンボなどの、操作の道具 (WinForms / WPF / MFC の、PoC で、実機で確かめた方法)。
/// フレームワークの違いは、要素の FrameworkId ("WPF" / "WinForm" / "Win32") と、ウィンドウハンドルの有無で、自動で、切り替える。
/// 連動の規則 (チェックで入力欄が有効になる、など) は、純粋な関数の単体テストで確かめる。UI テストは、ダイアログごとに、煙テスト 1 件に留める。
///
/// 実機で確かめた、注意:
///  - UIA の Invoke は、クリックの処理が終わるまで戻らない。その中で、ShowDialog / DoModal / MessageBox が、閉じるまで戻らないと、
///    WinForms / MFC では、以後の UIA の呼び出しが、すべて止まる (WPF は止まらない)。ウィンドウを持つボタンは、BM_CLICK を PostMessage (非同期) で押す。
///  - メニュー項目は、ウィンドウを持たない。WinForms (ToolStrip) は、アプリ側で、ダイアログを開く処理を BeginInvoke で遅らせる。
///    MFC (Win32 のメニュー) は、UIA の Invoke では、コマンドが動かない → フレームへ WM_COMMAND (コマンド ID) を PostMessage する (MenuCommand)。
///  - WPF のメニューのポップアップは、別のデスクトップでは、開かない。WPF の UI テストは、既定で、ユーザーのデスクトップで動く (uitest_once.sh --visible で、明示もできる。古いウォッチャーは、run_watcher_visible.cmd)。
///  - Win32 のコンボ / リスト: UIA の選択は、不安定 (コンボの展開は、ツリーを壊す) / 通知 (SELCHANGE) が、アプリへ飛ばない。Win32 メッセージで選ぶ。
///  - キーボード・マウスの入力 (SendInput) は、別のデスクトップでは、拒否される。
/// </summary>
internal static class UiDialogs
{
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetDlgItem(IntPtr hDlg, int id);

    private const uint WM_COMMAND = 0x0111, WM_HSCROLL = 0x0114;
    private const uint WM_KEYDOWN = 0x0100, WM_KEYUP = 0x0101, WM_SYSKEYDOWN = 0x0104, WM_SYSKEYUP = 0x0105, WM_SYSCHAR = 0x0106;
    private const uint BM_CLICK = 0x00F5, CB_SETCURSEL = 0x014E, LB_SETCURSEL = 0x0186;
    private const uint TBM_GETPOS = 0x0400, TBM_SETPOS = 0x0405, SBM_SETPOS = 0x00E0, SBM_GETPOS = 0x00E1;

    // ---------------------------------------------------------------- 判定と待ち

    /// <summary>"WPF" / "WinForm" / "Win32" (MFC を含む)。</summary>
    public static string Framework(AutomationElement e)
    {
        try { return e.Properties.FrameworkId.ValueOrDefault ?? ""; }
        catch (Exception) { return ""; }
    }

    public static IntPtr Hwnd(AutomationElement e)
    {
        try { return e.Properties.NativeWindowHandle.ValueOrDefault; }
        catch (Exception) { return IntPtr.Zero; }
    }

    /// <summary>probe が、null 以外を返すまで、待つ (例外は、無視して、再試行)。</summary>
    public static T? WaitFor<T>(Func<T?> probe, TimeSpan? timeout = null) where T : class
    {
        var end = DateTime.UtcNow + (timeout ?? TimeSpan.FromSeconds(5));
        do
        {
            try
            {
                var v = probe();
                if (v != null) return v;
            }
            catch (Exception)
            {
                // 開く途中・閉じる途中は、UIA が、一時的に失敗する
            }

            Thread.Sleep(100);
        }
        while (DateTime.UtcNow < end);
        return null;
    }

    // ---------------------------------------------------------------- ダイアログを開く・検出する

    /// <summary>ボタンなどを、押す。ウィンドウを持つ要素 (WinForms / MFC のボタン、標準ダイアログのボタン) は、BM_CLICK を PostMessage (非同期)。
    /// ウィンドウを持たない要素 (WPF のボタン、WinForms のメニュー項目) は、UIA の Invoke を、別スレッドで呼ぶ。使った方法を、返す。</summary>
    public static string Click(AutomationElement element)
    {
        var hwnd = Hwnd(element);
        if (hwnd != IntPtr.Zero && element.ControlType != ControlType.MenuItem)
        {
            PostMessage(hwnd, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
            return "BM_CLICK";
        }

        if (Framework(element) == "Win32" && element.ControlType == ControlType.MenuItem)
        {
            throw new InvalidOperationException("Win32 (MFC) のメニュー項目は、UIA の Invoke では、コマンドが動かない。UiDialogs.MenuCommand(MainWindow, コマンド ID) を使う");
        }

        var invoke = element.Patterns.Invoke.PatternOrDefault
            ?? throw new InvalidOperationException($"Invoke パターンがない ({element.ControlType} '{element.Name}')。WPF の、サブメニューを持つ項目は、ExpandMenu で開く");
        var task = Task.Run(() => invoke.Invoke());
        try { task.Wait(TimeSpan.FromSeconds(1)); }   // ダイアログが閉じるまで戻らない場合 (WPF) は、待たずに、先へ進む
        catch (AggregateException ex) { throw ex.GetBaseException(); }
        return "Invoke (別スレッド)";
    }

    /// <summary>メインウィンドウの、モーダルなダイアログ (最初の 1 つ) を、待つ。MessageBox・標準ファイルダイアログも、ここに出る。</summary>
    public static Window? WaitModal(Window main, TimeSpan? timeout = null) =>
        WaitFor(() => main.ModalWindows.FirstOrDefault(), timeout);

    public static bool WaitModalClosed(Window main, TimeSpan? timeout = null) =>
        WaitFor(() => main.ModalWindows.Length == 0 ? new object() : null, timeout) != null;

    /// <summary>モードレスなウィンドウを、タイトルで探す。オーナーつきの Window / Form は、UIA3 では、メインの子として出る (UIA2 ではトップレベル)。両方を探す。</summary>
    public static Window? FindWindow(Application app, AutomationBase automation, Window main, string title)
    {
        var top = app.GetAllTopLevelWindows(automation).FirstOrDefault(w => w.Title == title);
        if (top != null) return top;
        return main.FindAllChildren(cf => cf.ByControlType(ControlType.Window)).Select(e => e.AsWindow()).FirstOrDefault(w => w.Title == title);
    }

    public static Window? WaitWindow(Application app, AutomationBase automation, Window main, string title, TimeSpan? timeout = null) =>
        WaitFor(() => FindWindow(app, automation, main, title), timeout);

    public static bool WaitWindowClosed(Application app, AutomationBase automation, Window main, string title, TimeSpan? timeout = null) =>
        WaitFor(() => FindWindow(app, automation, main, title) == null ? new object() : null, timeout) != null;

    // ---------------------------------------------------------------- メニュー

    private static string NormalizeMenuName(string? name)
    {
        var s = (name ?? "").Replace("&", "");
        var tab = s.IndexOf('\t');
        if (tab >= 0) s = s[..tab];
        s = Regex.Replace(s, @"\s+Ctrl\+\w+$", "");   // ショートカットの表記
        s = Regex.Replace(s, @"\([A-Za-z0-9]\)$", ""); // ニーモニックの表記 (例: ファイル(F))
        return s.Replace("...", "").Trim();
    }

    /// <summary>メニュー項目を、表示名で探す (ニーモニックの &amp; / (F)、ショートカットの表記、... は、無視)。WinForms の ToolStripMenuItem は、AutomationId が空。</summary>
    public static AutomationElement? FindMenuItem(AutomationBase automation, Window main, string name)
    {
        bool Match(AutomationElement e) => string.Equals(NormalizeMenuName(e.Name), NormalizeMenuName(name), StringComparison.OrdinalIgnoreCase);
        return main.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem)).FirstOrDefault(Match)
            ?? automation.GetDesktop().FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem)).FirstOrDefault(Match);
    }

    private static void PostSysKey(IntPtr hwnd, char mnemonic)
    {
        var vk = char.ToUpperInvariant(mnemonic);
        var down = (IntPtr)0x20000001;
        PostMessage(hwnd, WM_SYSKEYDOWN, (IntPtr)vk, down);
        PostMessage(hwnd, WM_SYSCHAR, (IntPtr)char.ToLowerInvariant(mnemonic), down);
        PostMessage(hwnd, WM_SYSKEYUP, (IntPtr)vk, unchecked((IntPtr)0xE0000001));
    }

    /// <summary>メニューを開く。Win32 (MFC): UIA の Expand は効かないので、Alt + ニーモニックを PostMessage し、ポップアップ (#32768) が開いたことを確かめる (3 回まで)。
    /// WPF / WinForms: UIA の Expand。WPF は、別のデスクトップでは、ポップアップが開かない → 分かりやすい例外にする。</summary>
    public static void ExpandMenu(AutomationBase automation, Window main, string menuName, char mnemonic = '\0')
    {
        var menu = WaitFor(() => FindMenuItem(automation, main, menuName))
            ?? throw new AssertFailedException($"メニュー '{menuName}' が、UIA のツリーに出ない");
        if (Framework(menu) == "Win32")
        {
            var m = mnemonic != '\0' ? mnemonic : NormalizeMenuName(menuName)[0];
            for (var attempt = 0; attempt < 3; attempt++)
            {
                if (attempt > 0)
                {
                    try { main.SetForeground(); main.Focus(); } catch (Exception) { /* 無視 */ }
                    Thread.Sleep(300);
                }

                PostSysKey(Hwnd(main), m);
                if (WaitFor(() => automation.GetDesktop().FindFirstChild(cf => cf.ByClassName("#32768")), TimeSpan.FromSeconds(1.5)) != null)
                {
                    Thread.Sleep(300);
                    return;
                }
            }

            throw new AssertFailedException($"メニュー '{menuName}' が、Alt + '{m}' で開かない");
        }

        menu.Patterns.ExpandCollapse.Pattern.Expand();
        var shown = WaitFor(() => menu.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem)).Length > 0 ? new object() : null, TimeSpan.FromSeconds(2));
        if (shown == null)
        {
            throw new AssertFailedException(
                $"メニュー '{menuName}' が、展開しても、サブ項目が出ない。WPF のメニューのポップアップは、別のデスクトップでは、開かない (desktop: {UiNative.DesktopName()})。" +
                "WPF の UI テストは、既定で、ユーザーのデスクトップで動く (新しいウォッチャー)。uitest_once.sh --visible で実行する (ウォッチャーが古いときは、再配置して再起動、または run_watcher_visible.cmd)");
        }

        Thread.Sleep(200);
    }

    public static void CollapseMenu(AutomationBase automation, Window main, string menuName)
    {
        try { FindMenuItem(automation, main, menuName)!.Patterns.ExpandCollapse.Pattern.Collapse(); }
        catch (Exception)
        {
            var hwnd = Hwnd(main);   // Win32 のメニュー: Esc を送って、閉じる
            PostMessage(hwnd, WM_KEYDOWN, (IntPtr)0x1B, (IntPtr)0x00010001);
            PostMessage(hwnd, WM_KEYUP, (IntPtr)0x1B, unchecked((IntPtr)0xC0010001));
        }

        Thread.Sleep(300);
    }

    /// <summary>メニューのコマンドを、フレームへ WM_COMMAND (コマンド ID) で PostMessage する (Win32 / MFC)。UIA にも、マウスにも頼らず、非同期なので、止まらない。</summary>
    public static void MenuCommand(Window main, int commandId) =>
        PostMessage(Hwnd(main), WM_COMMAND, (IntPtr)commandId, IntPtr.Zero);

    // ---------------------------------------------------------------- コンボ・リスト・スライダー・スクロールバー・タブ

    public static string ComboText(AutomationElement combo)
    {
        try
        {
            var v = combo.Patterns.Value.PatternOrDefault?.Value.ValueOrDefault;
            if (v != null) return v;
        }
        catch (Exception)
        {
            // 次の方法
        }

        return combo.AsComboBox().SelectedItem?.Text ?? "(選択なし)";
    }

    /// <summary>コンボで、項目を選ぶ。ウィンドウを持つコンボ (WinForms / MFC): CB_SETCURSEL + 親へ WM_COMMAND(CBN_SELCHANGE)。項目の位置が要るので、knownItems (表示の順の、全項目) を、渡す。
    /// WPF: UIA の ComboBox.Select。選べたかは、読み戻して確かめる。使った方法を、返す。</summary>
    public static string SelectComboItem(AutomationElement combo, string text, params string[] knownItems)
    {
        var tried = new List<string>();
        var methods = new List<(string Name, Action Do)>();
        var hwnd = Hwnd(combo);
        var index = Array.IndexOf(knownItems, text);
        if (hwnd != IntPtr.Zero && index >= 0)
        {
            methods.Add(("CB_SETCURSEL + WM_COMMAND(CBN_SELCHANGE)", () =>
            {
                SendMessage(hwnd, CB_SETCURSEL, (IntPtr)index, IntPtr.Zero);
                SendMessage(GetParent(hwnd), WM_COMMAND, (IntPtr)((1 << 16) | (GetDlgCtrlID(hwnd) & 0xFFFF)), hwnd);   // CBN_SELCHANGE = 1
            }));
        }

        methods.Add(("ComboBox.Select (UIA)", () => combo.AsComboBox().Select(text)));
        foreach (var (name, doit) in methods)
        {
            try
            {
                doit();
                Thread.Sleep(250);
                if (ComboText(combo) == text) return name;
                tried.Add($"{name}: 読み戻し='{ComboText(combo)}'");
            }
            catch (Exception ex) { tried.Add($"{name}: {ex.GetType().Name}: {ex.Message}"); }
        }

        throw new AssertFailedException($"コンボで '{text}' を選べない。試した方法: " + string.Join(" / ", tried));
    }

    /// <summary>リストボックスの、index 番目を、選ぶ。ウィンドウを持つリスト: LB_SETCURSEL + 親へ WM_COMMAND(LBN_SELCHANGE) (UIA の Select では、通知が、アプリへ飛ばない)。WPF: UIA の Select。</summary>
    public static string SelectListItem(AutomationElement list, int index)
    {
        var hwnd = Hwnd(list);
        if (hwnd != IntPtr.Zero)
        {
            SendMessage(hwnd, LB_SETCURSEL, (IntPtr)index, IntPtr.Zero);
            SendMessage(GetParent(hwnd), WM_COMMAND, (IntPtr)((1 << 16) | (GetDlgCtrlID(hwnd) & 0xFFFF)), hwnd);   // LBN_SELCHANGE = 1
            Thread.Sleep(250);
            return "LB_SETCURSEL + WM_COMMAND(LBN_SELCHANGE)";
        }

        list.AsListBox().Items[index].Select();
        Thread.Sleep(250);
        return "SelectionItem.Select (UIA)";
    }

    /// <summary>スライダー (TrackBar / Slider) の、いまの値。ウィンドウを持つ: TBM_GETPOS。WPF: RangeValue。</summary>
    public static int SliderValue(AutomationElement slider)
    {
        var hwnd = Hwnd(slider);
        return hwnd != IntPtr.Zero
            ? (int)SendMessage(hwnd, TBM_GETPOS, IntPtr.Zero, IntPtr.Zero)
            : (int)slider.Patterns.RangeValue.Pattern.Value.Value;
    }

    /// <summary>スライダーの値を設定する。RangeValue → LegacyIAccessible.SetValue → TBM_SETPOS + WM_HSCROLL の順に試し、読み戻して、確かめる (WinForms の TrackBar は、RangeValue がない)。</summary>
    public static string SetSlider(AutomationElement slider, int value)
    {
        var methods = new (string Name, Action Do)[]
        {
            ("RangeValue.SetValue", () => slider.Patterns.RangeValue.Pattern.SetValue(value)),
            ("LegacyIAccessible.SetValue", () => slider.Patterns.LegacyIAccessible.Pattern.SetValue(value.ToString())),
            ("TBM_SETPOS + WM_HSCROLL", () =>
            {
                var hwnd = Hwnd(slider);
                SendMessage(hwnd, TBM_SETPOS, (IntPtr)1, (IntPtr)value);
                SendMessage(GetParent(hwnd), WM_HSCROLL, (IntPtr)((value << 16) | 4 /* TB_THUMBPOSITION */), hwnd);
            }),
        };
        return TryUntil("スライダー", value, methods, () => SliderValue(slider));
    }

    /// <summary>スクロールバーの、いまの位置。ウィンドウを持つ: SBM_GETPOS (UIA の RangeValue は、MFC では 0〜100 に正規化された値)。WPF: RangeValue。</summary>
    public static int ScrollBarValue(AutomationElement scrollBar)
    {
        var hwnd = Hwnd(scrollBar);
        return hwnd != IntPtr.Zero
            ? (int)SendMessage(hwnd, SBM_GETPOS, IntPtr.Zero, IntPtr.Zero)
            : (int)scrollBar.Patterns.RangeValue.Pattern.Value.Value;
    }

    /// <summary>スクロールバーの位置を設定する。RangeValue → SBM_SETPOS + WM_HSCROLL(SB_THUMBPOSITION) の順に試し、SBM_GETPOS で読み戻して、確かめる。</summary>
    public static string SetScrollBar(AutomationElement scrollBar, int value)
    {
        var methods = new (string Name, Action Do)[]
        {
            ("RangeValue.SetValue", () => scrollBar.Patterns.RangeValue.Pattern.SetValue(value)),
            ("SBM_SETPOS + WM_HSCROLL(SB_THUMBPOSITION)", () =>
            {
                var hwnd = Hwnd(scrollBar);
                SendMessage(hwnd, SBM_SETPOS, (IntPtr)value, (IntPtr)1);
                SendMessage(GetParent(hwnd), WM_HSCROLL, (IntPtr)((value << 16) | 4 /* SB_THUMBPOSITION */), hwnd);
            }),
        };
        return TryUntil("スクロールバー", value, methods, () => ScrollBarValue(scrollBar));
    }

    private static string TryUntil(string what, int expected, (string Name, Action Do)[] methods, Func<int> read)
    {
        var tried = new List<string>();
        foreach (var (name, doit) in methods)
        {
            try
            {
                doit();
                Thread.Sleep(250);
                var actual = read();
                if (actual == expected) return name;
                tried.Add($"{name}: 読み戻し={actual}");
            }
            catch (Exception ex) { tried.Add($"{name}: {ex.GetType().Name}: {ex.Message}"); }
        }

        throw new AssertFailedException($"{what}を {expected} にできない。試した方法: " + string.Join(" / ", tried));
    }

    /// <summary>タブを、名前で選ぶ (WinForms / WPF / MFC とも、UIA の SelectTabItem で、切り替わる)。選ばれていないタブの中の要素は、UIA のツリーに出ない。</summary>
    public static void SelectTab(AutomationElement tab, string name)
    {
        tab.AsTab().SelectTabItem(name);
        Thread.Sleep(300);
    }

    // ---------------------------------------------------------------- OS 標準のダイアログ (MessageBox・ファイルダイアログ)

    /// <summary>標準ダイアログ (#32770) の、コントロール ID のボタンを、押して、ダイアログが閉じるのを待つ。UIA では、ボタンのウィンドウハンドルが、0 になることがある (ファイルダイアログ)。
    /// ダイアログのハンドルから GetDlgItem で探して BM_CLICK → ダイアログへ WM_COMMAND → UIA の Invoke、の順に試す。使った方法を、返す。
    /// MessageBox の ID: はい = 6、いいえ = 7、OK = 1、キャンセル = 2。ファイルダイアログの 開く / 保存 = 1、キャンセル = 2。</summary>
    public static string PressDialogButton(Window main, AutomationElement dialog, int id)
    {
        var methods = new (string Name, Action Do)[]
        {
            ("BM_CLICK (GetDlgItem)", () =>
            {
                var b = GetDlgItem(Hwnd(dialog), id);
                if (b == IntPtr.Zero) throw new InvalidOperationException($"GetDlgItem({id}) が 0");
                PostMessage(b, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
            }),
            ("WM_COMMAND (ダイアログへ)", () => PostMessage(Hwnd(dialog), WM_COMMAND, (IntPtr)id, GetDlgItem(Hwnd(dialog), id))),
            ("Invoke (UIA、別スレッド)", () =>
            {
                var b = dialog.FindFirstDescendant(cf => cf.ByAutomationId(id.ToString())) ?? throw new InvalidOperationException($"ボタン {id} が、見つからない");
                Task.Run(() => b.AsButton().Invoke()).Wait(TimeSpan.FromSeconds(1));
            }),
        };
        var tried = new List<string>();
        foreach (var (name, doit) in methods)
        {
            try
            {
                doit();
                if (WaitModalClosed(main, TimeSpan.FromSeconds(3))) return name;
                tried.Add($"{name}: 閉じない");
            }
            catch (Exception ex) { tried.Add($"{name}: {ex.GetType().Name}: {ex.Message}"); }
        }

        throw new AssertFailedException($"ダイアログのボタン {id} で、閉じない。試した方法: " + string.Join(" / ", tried));
    }

    /// <summary>MessageBox の、文言 (Static の文字を、連結)。</summary>
    public static string MessageBoxText(AutomationElement box) =>
        string.Join(" | ", box.FindAllDescendants(cf => cf.ByControlType(ControlType.Text)).Select(t => t.Name).Where(n => !string.IsNullOrEmpty(n)));

    /// <summary>MessageBox の、はい / いいえ (OK / キャンセルなら、PressDialogButton で、1 / 2) を押して、閉じるのを待つ。</summary>
    public static string AnswerMessageBox(Window main, AutomationElement box, bool yes) => PressDialogButton(main, box, yes ? 6 : 7);

    /// <summary>ファイルダイアログの、ファイル名の入力欄。「開く」は id 1148、「名前を付けて保存」は id 1001 (ComboBox FileNameControlHost の中)。
    /// Edit を、ControlType だけで探すと、一覧の項目の、読み取り専用の Edit を拾う。</summary>
    public static AutomationElement FileNameEdit(AutomationElement dialog) =>
        new[] { "1148", "1001" }.Select(id => dialog.FindFirstDescendant(cf => cf.ByAutomationId(id).And(cf.ByControlType(ControlType.Edit)))).FirstOrDefault(e => e != null)
        ?? dialog.FindFirstDescendant(cf => cf.ByAutomationId("FileNameControlHost"))?.FindFirstDescendant(cf => cf.ByControlType(ControlType.Edit))
        ?? throw new AssertFailedException("ファイル名の入力欄が、見つからない");

    /// <summary>ファイルダイアログに、パスを入れて、開く / 保存 (accept = true) か、キャンセル (false) を押す。</summary>
    public static string PickFile(Window main, AutomationElement dialog, string path, bool accept = true)
    {
        if (accept) FileNameEdit(dialog).Patterns.Value.Pattern.SetValue(path);
        Thread.Sleep(300);
        return PressDialogButton(main, dialog, accept ? 1 : 2);
    }

    // ---------------------------------------------------------------- 診断

    /// <summary>要素のツリーを、AutomationId / ControlType / Name / ClassName 付きで、文字列にする。Win32 のダイアログは、ツリーが深く・重複することがあるので、深さと、ノード数に、上限を付ける。</summary>
    public static string DumpTree(AutomationElement root, int maxDepth = 12, int maxNodes = 1500)
    {
        var sb = new System.Text.StringBuilder();
        var nodes = 0;
        void Walk(AutomationElement e, int depth)
        {
            if (depth > maxDepth || ++nodes > maxNodes)
            {
                if (nodes == maxNodes + 1) sb.AppendLine($"... (上限: 深さ {maxDepth} / {maxNodes} ノード)");
                return;
            }

            string P(Func<string?> f) { try { return f() ?? ""; } catch (Exception) { return "?"; } }
            sb.AppendLine($"{new string(' ', depth * 2)}[{P(() => e.Properties.ControlType.ValueOrDefault.ToString())}] id='{P(() => e.Properties.AutomationId.ValueOrDefault)}' name='{P(() => e.Properties.Name.ValueOrDefault)}' class='{P(() => e.Properties.ClassName.ValueOrDefault)}'");
            AutomationElement[] kids;
            try { kids = e.FindAllChildren(); } catch (Exception) { return; }
            foreach (var k in kids) Walk(k, depth + 1);
        }

        Walk(root, 0);
        return sb.ToString();
    }

    /// <summary>ウィンドウ (ダイアログ) の、スクリーンショットを、ui-screenshots に残す (<名前>-window.png)。</summary>
    public static void Shot(AutomationElement window, string name) => Screenshots.Save(window, name);
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


def settings_text(kind):
    # フレームワークごとの違いは、ウォッチャーでなく、このファイルが持つ (WPF のメニューのポップアップは、別のデスクトップで開かない: DESIGN 4.36)
    desktop = 'visible' if kind == 'wpf' else 'separate'
    why = ('WPF のメニューのポップアップは、別のデスクトップでは、開かない (実機で確認)。メニューを使わなければ、separate でよい'
           if kind == 'wpf' else 'ウィンドウが画面に出ず、PC を普通に使える。目で確かめたいときは、uitest_once.sh --visible')
    return (f'# UI テストの既定 (ウォッチャーが読む)。1 回ごとの指定 (uitest_once.sh --visible / --separate) が、これより優先される。\n'
            f'# desktop: visible = ユーザーのデスクトップ (実行中は、PC に触らない) / separate (または invisible) = 別のデスクトップ\n'
            f'# {why}\n'
            f'desktop={desktop}\n'
            f'# slowmo: 操作の間の待ち (ミリ秒)。目で確かめるときだけ (例: 800)\n'
            f'slowmo=0\n')


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
    ap.add_argument('--refresh-support-files', action='store_true', help='すでにある <アプリ名>.UITests の、UiTestBase.cs / AppLocator.cs / Screenshots.cs / UiNative.cs / UiDialogs.cs を、最新のひな形で上書きする (テストの本体 MainWindowUiTests.cs は、触らない)。CLAUDE.md の節も、更新する')
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
               f'{ui}/Screenshots.cs': fill(SHOTS_CS, **kv0), f'{ui}/UiNative.cs': fill(NATIVE_CS, **kv0),
               f'{ui}/UiDialogs.cs': fill(DIALOGS_CS, **kv0)}
        settings_rel = f'{ui}/uitest.settings'
        settings_new = not os.path.exists(os.path.join(sln_dir, settings_rel))   # 既存の設定 (利用者の選択) は、上書きしない
        for r in sup:
            print(f'  ~ {r}')
        if settings_new:
            print(f'  + {settings_rel} (desktop={"visible" if kind == "wpf" else "separate"})')
        if a.dry_run:
            print('(dry-run: 何も書いていない)')
            return
        if settings_new:
            sup[settings_rel] = settings_text(kind)
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
        f'{ui}/UiDialogs.cs': fill(DIALOGS_CS, **kv),
        f'{ui}/uitest.settings': settings_text(kind),
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
- **ダイアログ・メニュー・コンボなどを操作するときは、`UiDialogs` (と、`UiTestBase.OpenModal`) を使う。** フレームワークに合う方法に、自動で切り替わる (自分で、`Invoke` / `Select` を、直接呼ばない): ボタンは `BM_CLICK` (WinForms / MFC)、WPF は `Invoke` を別スレッド。コンボは `SelectComboItem` (WinForms / MFC は、項目の一覧を渡す)、リストは `SelectListItem`、スライダーは `SetSlider`、スクロールバーは `SetScrollBar`、MessageBox は `AnswerMessageBox`、ファイルダイアログは `PickFile`、モードレスは `WaitWindow`。
- **画面の連動の規則 (チェックで入力欄が有効になる、など) は、純粋な関数の単体テストで確かめる。UI テストは、ダイアログごとに、煙テスト 1 件** (開く → 規則の結果が、実画面に反映されている → OK / キャンセルの結果が、メインに返る)。
- **どのデスクトップで実行するか:** `{ui}/uitest.settings` の `desktop=visible` (ユーザーのデスクトップ。実行中は、PC に触らない) / `separate` (別のデスクトップ)。作成時に、WPF は visible、それ以外は separate が入る。1 回だけ変えるには、`uitest_once.sh --visible` / `--separate` (`--invisible`)。
- **メニュー:** WPF のメニューは、別のデスクトップでは、ポップアップが開かない → WPF は、`uitest.settings` が visible (`uitest_once.sh --visible` で、明示もできる。古いウォッチャーは、`run_watcher_visible.cmd`。`UiDialogs.ExpandMenu` が、分かりやすい失敗にする)。WinForms は、ダイアログを開く処理を、アプリ側で `BeginInvoke` で遅らせる。MFC は、`UiDialogs.MenuCommand` (`WM_COMMAND`)。
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
