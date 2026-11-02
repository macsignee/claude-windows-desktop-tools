#!/usr/bin/env bash
# new_solution_winforms_test.sh - new_solution.py の WinForms (--type winforms) を、疑似フォルダで検証する。
# Windows も .NET も不要 (コンパイルは、実機で確認する)。
# Usage: tests/new_solution_winforms_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
T="${TMPDIR:-/tmp}/nswf_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
mk() { mkdir -p "$T/$1"; echo "$T/$1"; }
wellformed() { python3 -c "import xml.etree.ElementTree as ET,sys; ET.parse(sys.argv[1])" "$1" 2>/dev/null; }
bom_crlf() { [ "$(head -c3 "$1" | xxd -p)" = efbbbf ] && [ "$(grep -vc $'\r$' "$1")" = 0 ]; }
cs() { tr -d '\r' < "$1" | sed '1s/^\xef\xbb\xbf//'; }

# ---------------------------------------------------------------- 層 + テスト
D="$(mk WfApp)"
python3 "$NS" "$D" --type winforms --layers data,logic --tests mstest >/dev/null; rc=$?
ok "full: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "full: app + 2 layers + 2 test projects (the app is not tested)" "$(for p in WfApp DataLayer LogicLayer DataLayer.Tests LogicLayer.Tests; do [ -f "$D/$p/$p.csproj" ] || exit 1; done; [ ! -d "$D/WfApp.Tests" ] && echo 1 || echo 0)"
ok "full: slnx has 5 projects, the app is the default startup" "$([ "$(grep -c '<Project Path=' "$D/WfApp.slnx")" = 5 ] && grep -q 'WfApp/WfApp.csproj" Id="[0-9a-f-]*" DefaultStartup="true"' "$D/WfApp.slnx" && echo 1 || echo 0)"
ok "full: app is WinExe + UseWindowsForms + net10.0-windows, no UseWPF; layers are plain net10.0" "$(c="$D/WfApp/WfApp.csproj"; grep -q '<OutputType>WinExe' "$c" && grep -q '<UseWindowsForms>true' "$c" && grep -q 'net10.0-windows' "$c" && ! grep -q 'UseWPF' "$c" && ! grep -q 'UseWindowsForms\|windows\|UseWPF' "$D/LogicLayer/LogicLayer.csproj" "$D/DataLayer/DataLayer.csproj" && echo 1 || echo 0)"
ok "full: the app references both layers; Logic -> Data" "$(grep -q 'LogicLayer.csproj' "$D/WfApp/WfApp.csproj" && grep -q 'DataLayer.csproj' "$D/WfApp/WfApp.csproj" && grep -q 'DataLayer.csproj' "$D/LogicLayer/LogicLayer.csproj" && echo 1 || echo 0)"
ok "full: IMainView and MainPresenter are in the Logic layer (namespace WfApp.Logic), not in the app" "$(grep -q 'namespace WfApp.Logic;' "$D/LogicLayer/IMainView.cs" && grep -q 'namespace WfApp.Logic;' "$D/LogicLayer/MainPresenter.cs" && [ ! -d "$D/WfApp/Presenters" ] && echo 1 || echo 0)"
ok "full: the Logic layer does not use WinForms types (comments aside)" "$(! cat "$D/LogicLayer/IMainView.cs" "$D/LogicLayer/MainPresenter.cs" | grep -v '^ *///' | grep -q 'Windows.Forms\|System.Drawing\|MessageBox\|Control\b' && echo 1 || echo 0)"
ok "full: MainPresenterTests (4 tests) is in LogicLayer.Tests, with a fake view" "$(grep -c '\[TestMethod\]' "$D/LogicLayer.Tests/MainPresenterTests.cs" | grep -q 4 && grep -q 'FakeMainView : IMainView' "$D/LogicLayer.Tests/MainPresenterTests.cs" && grep -q 'namespace WfApp.Logic.Tests;' "$D/LogicLayer.Tests/MainPresenterTests.cs" && echo 1 || echo 0)"
ok "full: Program.cs is the composition root (creates the form, binds the presenter, Application.Run), STAThread, usings sorted" "$(f="$D/WfApp/Program.cs"; grep -q '\[STAThread\]' "$f" && grep -q 'ApplicationConfiguration.Initialize' "$f" && grep -q 'new MainPresenter(form)' "$f" && grep -q 'Application.Run(form)' "$f" && [ "$(cs "$f" | grep '^using' | tr '\n' ' ')" = "using WfApp.Forms; using WfApp.Logic; " ] && echo 1 || echo 0)"
ok "full: MainForm implements IMainView and exposes values and events only" "$(f="$D/WfApp/Forms/MainForm.cs"; grep -q 'partial class MainForm : Form, IMainView' "$f" && grep -q 'string PersonName' "$f" && grep -q 'event EventHandler? NameChanged' "$f" && grep -q 'event EventHandler? ClearRequested' "$f" && echo 1 || echo 0)"
ok "full: Designer: controls are named (NameTextBox / GreetingLabel / ClearButton) and Name matches the field" "$(f="$D/WfApp/Forms/MainForm.Designer.cs"; for n in MainTable NameTextBox GreetingLabel ClearButton; do grep -q "private [A-Za-z]* $n;" "$f" && grep -q "$n.Name = \"$n\";" "$f" || exit 1; done; echo 1)"
ok "full: the Form is recognized by the VS designer: SubType Form in the csproj, and an explicit using System.Windows.Forms (VS did not recognize MainForm.cs without them)" "$(grep -q '<Compile Update="Forms\\MainForm.cs">' "$D/WfApp/WfApp.csproj" && grep -q '<SubType>Form</SubType>' "$D/WfApp/WfApp.csproj" && [ "$(cs "$D/WfApp/Forms/MainForm.cs" | grep '^using' | tr '\n' ' ')" = "using System.ComponentModel; using System.Windows.Forms; using WfApp.Logic; " ] && wellformed "$D/WfApp/WfApp.csproj" && echo 1 || echo 0)"
ok "full: the IMainView properties of MainForm are hidden from the designer (WFO1000 is a build error since .NET 9)" "$(c="$D/WfApp/Forms/MainForm.cs"; [ "$(grep -c 'DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)' "$c")" = 3 ] && [ "$(grep -c '\[Browsable(false)\]' "$c")" = 3 ] && echo 1 || echo 0)"
ok "full: Designer: every event handler (+=) exists in MainForm.cs" "$(h="$(grep -o '+= [A-Za-z_]*;' "$D/WfApp/Forms/MainForm.Designer.cs" | sed 's/+= //;s/;//')"; [ -n "$h" ] && for x in $h; do grep -q "void $x(" "$D/WfApp/Forms/MainForm.cs" || exit 1; done; echo 1)"
ok "full: Designer: InitializeComponent is called by the constructor; Dispose is overridden" "$(grep -q 'InitializeComponent();' "$D/WfApp/Forms/MainForm.cs" && grep -q 'protected override void Dispose' "$D/WfApp/Forms/MainForm.Designer.cs" && echo 1 || echo 0)"
ok "full: .cs / .csproj are BOM + CRLF" "$(for f in WfApp/WfApp.csproj WfApp/Program.cs WfApp/Forms/MainForm.cs WfApp/Forms/MainForm.Designer.cs LogicLayer/MainPresenter.cs LogicLayer.Tests/MainPresenterTests.cs; do bom_crlf "$D/$f" || exit 1; done; echo 1)"
ok "full: csproj are well-formed XML" "$(for f in WfApp/WfApp.csproj LogicLayer/LogicLayer.csproj LogicLayer.Tests/LogicLayer.Tests.csproj; do wellformed "$D/$f" || exit 1; done; echo 1)"
ok "full: CLAUDE.md records main / layers / tests, mentions MVP, Name and the Designer" "$(c="$D/CLAUDE.md"; grep -qx -- '- メイン: WfApp (WinForms (MVP))' "$c" && grep -qx -- '- 層: data,logic' "$c" && grep -qx -- '- テスト: あり (MSTest)' "$c" && grep -q 'IMainView' "$c" && grep -q 'Designer.cs' "$c" && grep -q 'AutomationId' "$c" && ! grep -q 'wpf-check\|XAML を編集' "$c" && echo 1 || echo 0)"

# ---------------------------------------------------------------- ロジック層なし (Presenter は、アプリの中)
D="$(mk NoLogic)"
python3 "$NS" "$D" --type winforms --layers data --tests mstest >/dev/null
ok "no logic layer: Presenter lives in the app (Presenters/), namespace NoLogic.Presenters" "$(grep -q 'namespace NoLogic.Presenters;' "$D/NoLogic/Presenters/MainPresenter.cs" && grep -q 'namespace NoLogic.Presenters;' "$D/NoLogic/Presenters/IMainView.cs" && grep -q 'using NoLogic.Presenters;' "$D/NoLogic/Forms/MainForm.cs" && echo 1 || echo 0)"
ok "no logic layer: CLAUDE.md says so" "$(grep -q 'ロジック層を作っていない' "$D/CLAUDE.md" && echo 1 || echo 0)"
ok "no logic layer + mstest: NoLogic.Tests targets the app's Presenters (windows tfm, references the app, namespace NoLogic.Presenters.Tests), plus DataLayer.Tests" "$(c="$D/NoLogic.Tests/NoLogic.Tests.csproj"; grep -q 'net10.0-windows' "$c" && grep -qF 'NoLogic\NoLogic.csproj' "$c" && grep -q 'Microsoft.NET.Test.Sdk' "$c" && grep -q 'namespace NoLogic.Presenters.Tests;' "$D/NoLogic.Tests/MainPresenterTests.cs" && [ "$(grep -c '\[TestMethod\]' "$D/NoLogic.Tests/MainPresenterTests.cs")" = 4 ] && [ ! -f "$D/NoLogic.Tests/NoLogicInfoTests.cs" ] && [ -f "$D/DataLayer.Tests/DataLayer.Tests.csproj" ] && [ "$(grep -c '<Project Path=' "$D/NoLogic.slnx")" = 4 ] && echo 1 || echo 0)"
ok "no logic layer + mstest: CLAUDE.md says the tests target Presenters/" "$(grep -q 'NoLogic.Tests' "$D/CLAUDE.md" && grep -q 'Presenters/' "$D/CLAUDE.md" && echo 1 || echo 0)"
D="$(mk AppOnly)"
python3 "$NS" "$D" --type winforms --layers none --tests none >/dev/null
ok "layers none + tests none: the app alone" "$([ -f "$D/AppOnly/Presenters/MainPresenter.cs" ] && [ "$(grep -c '<Project Path=' "$D/AppOnly.slnx")" = 1 ] && grep -qx -- '- 層: なし' "$D/CLAUDE.md" && echo 1 || echo 0)"
python3 "$NS" "$D" --tests mstest >/dev/null; rc=$?
ok "layers none: retrofit --tests mstest adds AppOnly.Tests for the app's Presenters" "$([ $rc = 0 ] && [ -f "$D/AppOnly.Tests/MainPresenterTests.cs" ] && grep -q 'net10.0-windows' "$D/AppOnly.Tests/AppOnly.Tests.csproj" && grep -q 'namespace AppOnly.Presenters.Tests;' "$D/AppOnly.Tests/MainPresenterTests.cs" && grep -q 'AppOnly.Tests/AppOnly.Tests.csproj' "$D/AppOnly.slnx" && grep -qx -- '- テスト: あり (MSTest)' "$D/CLAUDE.md" && echo 1 || echo 0)"
D="$(mk Solo)"
python3 "$NS" "$D" --type winforms --layers none --tests mstest >/dev/null; rc=$?
ok "layers none + mstest at creation: Solo + Solo.Tests (2 projects), tests target Presenters" "$([ $rc = 0 ] && [ "$(grep -c '<Project Path=' "$D/Solo.slnx")" = 2 ] && grep -q 'namespace Solo.Presenters.Tests;' "$D/Solo.Tests/MainPresenterTests.cs" && echo 1 || echo 0)"
ok "layers none + mstest: the retrofit finds nothing more to add (rc=3 or 2, nothing written)" "$(python3 "$NS" "$D" --tests mstest >/dev/null 2>&1; [ $? != 0 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 名前の指定、後付け
D="$(mk Named)"
python3 "$NS" "$D" --type winforms --layers data:OrderData,logic:OrderLogic --tests none --namespace Acme.Shop --tfm net10.0 >/dev/null
ok "custom names / namespace / tfm" "$(grep -q 'namespace Acme.Shop.Logic;' "$D/OrderLogic/MainPresenter.cs" && grep -q 'net10.0-windows' "$D/Named/Named.csproj" && grep -q 'using Acme.Shop.Logic;' "$D/Named/Program.cs" && echo 1 || echo 0)"
python3 "$NS" "$D" --tests mstest >/dev/null; rc=$?
ok "retrofit --tests mstest: LogicLayer's tests include MainPresenterTests" "$([ $rc = 0 ] && [ -f "$D/OrderLogic.Tests/MainPresenterTests.cs" ] && [ -f "$D/OrderData.Tests/OrderData.Tests.csproj" ] && [ ! -f "$D/OrderData.Tests/MainPresenterTests.cs" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 異常系
D="$(mk Bad1)"
python3 "$NS" "$D" --type winforms --layers viewmodel --tests none >/dev/null 2>&1; rc=$?
ok "viewmodel layer is rejected for winforms (rc=2)" "$([ $rc = 2 ] && echo 1 || echo 0)"
# ---------------------------------------------------------------- UI テスト (FlaUI)
D="$(mk WfUi)"
python3 "$NS" "$D" --type winforms --layers logic --tests mstest --ui-tests flaui >/dev/null; rc=$?
U="$D/WfUi.UITests"
ok "ui-tests: created together with the solution (rc=0), project registered in the slnx" "$([ $rc = 0 ] && [ -f "$U/WfUi.UITests.csproj" ] && grep -q 'WfUi.UITests/WfUi.UITests.csproj' "$D/WfUi.slnx" && echo 1 || echo 0)"
ok "ui-tests: net10.0-windows + FlaUI.UIA3 + MSTest, does not reference the app" "$(grep -q 'net10.0-windows' "$U/WfUi.UITests.csproj" && grep -q 'FlaUI.UIA3' "$U/WfUi.UITests.csproj" && grep -q 'MSTest.TestFramework' "$U/WfUi.UITests.csproj" && ! grep -q 'ProjectReference' "$U/WfUi.UITests.csproj" && echo 1 || echo 0)"
ok "ui-tests: the template targets the WinForms form (NameTextBox / GreetingLabel / ClearButton by AutomationId = Name)" "$(f="$U/MainWindowUiTests.cs"; grep -q 'Find("NameTextBox")' "$f" && grep -q 'Find("GreetingLabel")' "$f" && grep -q 'Find("ClearButton")' "$f" && ! grep -q 'GreetingText' "$f" && echo 1 || echo 0)"
ok "ui-tests: the controls named by the template exist in the generated Designer.cs" "$(for n in NameTextBox GreetingLabel ClearButton; do grep -q "$n.Name = \"$n\";" "$D/WfUi/Forms/MainForm.Designer.cs" || exit 1; done; echo 1)"
ok "ui-tests: the screenshot takes the larger of the UIA rectangle and GetWindowRect" "$(grep -q 'GetWindowRect' "$U/Screenshots.cs" && grep -q 'Math.Max(width' "$U/Screenshots.cs" && echo 1 || echo 0)"
ok "ui-tests: the test process is made DPI aware at load, with a fallback scale by the window's DPI (the screenshot was cut at 380x230 on a scaled display)" "$(f="$U/Screenshots.cs"; grep -q 'ModuleInitializer' "$f" && grep -q 'SetProcessDpiAwarenessContext(new IntPtr(-4))' "$f" && grep -q 'GetDpiForWindow' "$f" && grep -q 'IsProcessDPIAware' "$f" && echo 1 || echo 0)"
ok "ui-tests: CLAUDE.md has the UI test section and says WinForms uses Name" "$(grep -q '## UI テスト (FlaUI)' "$D/CLAUDE.md" && grep -q 'WinForms: コントロールの `Name`' "$D/CLAUDE.md" && echo 1 || echo 0)"
ok "ui-tests: the normal MSTest projects are not affected (LogicLayer.Tests exists, no WfUi.Tests)" "$([ -d "$D/LogicLayer.Tests" ] && [ ! -d "$D/WfUi.Tests" ] && echo 1 || echo 0)"
D="$(mk WfUiLate)"
python3 "$NS" "$D" --type winforms --layers none --tests none >/dev/null
python3 "$NS" "$D" --ui-tests flaui >/dev/null; rc=$?
ok "ui-tests: retrofit on an existing WinForms solution (no layers)" "$([ $rc = 0 ] && [ -f "$D/WfUiLate.UITests/MainWindowUiTests.cs" ] && grep -q 'GreetingLabel' "$D/WfUiLate.UITests/MainWindowUiTests.cs" && echo 1 || echo 0)"
D="$(mk WfUiCustom)"
python3 "$NS" "$D" --type winforms --layers none --tests none >/dev/null
sed -i 's/GreetingLabel.Name = "GreetingLabel";/GreetingLabel.Name = "label1";/' "$D/WfUiCustom/Forms/MainForm.Designer.cs"
out="$(python3 "$NS" "$D" --ui-tests flaui)"
ok "ui-tests: a form that is not the standard one gets the generic template and a NOTE about Name" "$(! grep -q 'GreetingLabel' "$D/WfUiCustom.UITests/MainWindowUiTests.cs" && grep -q 'MainWindow_Opens_WithTitle' "$D/WfUiCustom.UITests/MainWindowUiTests.cs" && grep -q 'Name を付ける' <<<"$out" && echo 1 || echo 0)"
D="$(mk Bad2)"
python3 "$NS" "$D" --type winforms --layers none --tests none --ui-tests flaui >/dev/null 2>&1; rc=$?
ok "layers none + tests none + ui-tests: the app + UITests (2 projects)" "$([ $rc = 0 ] && [ "$(grep -c '<Project Path=' "$D/Bad2.slnx")" = 2 ] && echo 1 || echo 0)"

D="$(mk Spec)"; mkdir -p "$D/docs/specs"
printf '# s\n\n## 構成案\n- メインの種類: winforms\n- 層: logic\n- テスト: mstest\n' > "$D/docs/specs/f.md"
python3 "$NS" "$D" --spec "$D/docs/specs/f.md" >/dev/null; rc=$?
ok "--spec: winforms is accepted from the 構成案" "$([ $rc = 0 ] && [ -f "$D/LogicLayer.Tests/MainPresenterTests.cs" ] && echo 1 || echo 0)"

# csharp-test-first: WinForms の読み替え表 (v2.34.0)
CTF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills/csharp-test-first/SKILL.md"
ok "csharp-test-first: has the WPF -> WinForms mapping table (Presenter / IView Fake / Form / Program.cs / winforms-check / winforms-csharp.md)" "$(grep -q '^| 本文の用語 (WPF) | WinForms での読み替え |' "$CTF" && grep -q 'IView` の \*\*Fake\*\*' "$CTF" && grep -q '`Program.cs` (`Form` と Presenter を作って結ぶ' "$CTF" && grep -q '| `wpf-check` | `winforms-check` |' "$CTF" && grep -q 'winforms-csharp.md` (「13 テスト規約」)' "$CTF" && echo 1 || echo 0)"
ok "csharp-test-first: WinForms has no ViewModel layer; fixing the Fake and call sites must not change assertions" "$(grep -q 'WinForms に、ViewModel 層は、ない' "$CTF" && grep -q '期待値とアサーションは、変えない' "$CTF" && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
