#!/usr/bin/env bash
# new_solution_wpf_test.sh - new_solution.py の WPF (--type wpf / --tests mstest) を、疑似フォルダで検証する。
# Windows も .NET も不要。生成されたソリューションを、wpf-check にかけて、指摘が出ないことも確認する。
# Usage: tests/new_solution_wpf_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
WC="$ROOT/skills/wpf-check/scripts/wpf_check.py"
T="${TMPDIR:-/tmp}/nswpf_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
mk() { mkdir -p "$T/$1"; echo "$T/$1"; }
wellformed() { python3 -c "import xml.etree.ElementTree as ET,sys; ET.parse(sys.argv[1])" "$1" 2>/dev/null; }
nobom() { [ "$(head -c3 "$1" | xxd -p)" != efbbbf ]; }
bom_crlf() { [ "$(head -c3 "$1" | xxd -p)" = efbbbf ] && [ "$(grep -vc $'\r$' "$1")" = 0 ]; }

# ---------------------------------------------------------------- 4 層 + テスト
D="$(mk MyApp)"
out="$(python3 "$NS" "$D" --type wpf --layers data,logic,viewmodel --tests mstest)"; rc=$?
ok "full: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "full: all projects exist (app, 3 layers, 3 test projects)" "$(for p in MyApp DataLayer LogicLayer ViewModels DataLayer.Tests LogicLayer.Tests ViewModels.Tests; do [ -f "$D/$p/$p.csproj" ] || exit 1; done; echo 1)"
ok "full: slnx has 7 projects, the WPF app is the default startup" "$([ "$(grep -c '<Project Path=' "$D/MyApp.slnx")" = 7 ] && grep -q 'MyApp/MyApp.csproj" Id="[0-9a-f-]*" DefaultStartup="true"' "$D/MyApp.slnx" && echo 1 || echo 0)"
ok "full: dependency chain app -> {ViewModels,Logic,Data}, ViewModels -> Logic -> Data, Data -> none" "$(r() { grep -o '\.\.\\[A-Za-z.]*\\' "$1" | tr -d '.\\' | sort | tr '\n' ' '; }
    [ "$(r "$D/ViewModels/ViewModels.csproj")" = "LogicLayer " ] && [ "$(r "$D/LogicLayer/LogicLayer.csproj")" = "DataLayer " ] && [ -z "$(r "$D/DataLayer/DataLayer.csproj")" ] && [ "$(r "$D/MyApp/MyApp.csproj")" = "DataLayer LogicLayer ViewModels " ] && echo 1 || echo 0)"
ok "full: app is WinExe + UseWPF + net10.0-windows; layers are plain net10.0 without UseWPF" "$(grep -q '<OutputType>WinExe' "$D/MyApp/MyApp.csproj" && grep -q 'net10.0-windows' "$D/MyApp/MyApp.csproj" && grep -q '<UseWPF>true' "$D/MyApp/MyApp.csproj" && ! grep -q 'UseWPF\|windows' "$D/ViewModels/ViewModels.csproj" "$D/LogicLayer/LogicLayer.csproj" "$D/DataLayer/DataLayer.csproj" && echo 1 || echo 0)"
ok "full: namespaces MyApp / MyApp.Data / MyApp.Logic / MyApp.ViewModels, tests <ns>.Tests" "$(grep -q 'namespace MyApp.Data;' "$D/DataLayer/DataLayerInfo.cs" && grep -q 'namespace MyApp.Logic.Tests;' "$D/LogicLayer.Tests/LogicLayerInfoTests.cs" && grep -q 'namespace MyApp.ViewModels;' "$D/ViewModels/MainViewModel.cs" && grep -q 'x:Class="MyApp.Views.MainWindow"' "$D/MyApp/Views/MainWindow.xaml" && echo 1 || echo 0)"
ok "full: the window refers to the ViewModels assembly (clr-namespace ...;assembly=ViewModels)" "$(grep -q 'clr-namespace:MyApp.ViewModels;assembly=ViewModels' "$D/MyApp/Views/MainWindow.xaml" && echo 1 || echo 0)"
ok "full: XAML and csproj are well-formed XML" "$(for f in MyApp/App.xaml MyApp/Resources/Styles.xaml MyApp/Views/MainWindow.xaml MyApp/MyApp.csproj ViewModels.Tests/ViewModels.Tests.csproj Directory.Build.props; do wellformed "$D/$f" || exit 1; done; echo 1)"
ok "full: .cs / .xaml / .csproj / .props are BOM + CRLF" "$(for f in MyApp/Views/MainWindow.xaml MyApp/Views/MainWindow.xaml.cs MyApp/App.xaml.cs MyApp/Resources/Styles.xaml MyApp/MyApp.csproj ViewModels/MainViewModel.cs Directory.Build.props; do bom_crlf "$D/$f" || exit 1; done; echo 1)"
ok "full: .editorconfig is CRLF without BOM, .slnx is without BOM" "$(nobom "$D/.editorconfig" && nobom "$D/MyApp.slnx" && [ "$(grep -vc $'\r$' "$D/.editorconfig")" = 0 ] && echo 1 || echo 0)"
ok "full: Directory.Build.props sets Nullable / ImplicitUsings" "$(grep -q '<Nullable>enable' "$D/Directory.Build.props" && grep -q '<ImplicitUsings>enable' "$D/Directory.Build.props" && echo 1 || echo 0)"
ok "full: CLAUDE.md records main / layers / tests (3 lines the other commands read)" "$([ "$(grep -c '^- メイン: MyApp (WPF (MVVM))$' "$D/CLAUDE.md")" = 1 ] && [ "$(grep -c '^- 層: data,logic,viewmodel$' "$D/CLAUDE.md")" = 1 ] && [ "$(grep -c '^- テスト: あり (MSTest)$' "$D/CLAUDE.md")" = 1 ] && echo 1 || echo 0)"
ok "full: .gitignore (bin/ obj/ and watcher files) and .gitattributes created" "$(grep -qx 'bin/' "$D/.gitignore" && grep -qx 'obj/' "$D/.gitignore" && grep -q 'package_result.txt' "$D/.gitignore" && grep -q 'text=auto eol=crlf' "$D/.gitattributes" && echo 1 || echo 0)"
ok "full (convention): App / Views / ViewModels / Resources layout, no StartupUri" "$([ -f "$D/MyApp/Views/MainWindow.xaml" ] && [ -f "$D/MyApp/Resources/Styles.xaml" ] && [ ! -f "$D/MyApp/MainWindow.xaml" ] && ! grep -q 'StartupUri' "$D/MyApp/App.xaml" && grep -q 'Resources/Styles.xaml' "$D/MyApp/App.xaml" && echo 1 || echo 0)"
ok "full (convention): the composition root (App.OnStartup) creates the window and sets the DataContext; the code-behind has neither DataContext nor logic" "$(grep -q 'override void OnStartup' "$D/MyApp/App.xaml.cs" && grep -q 'DataContext = new MainViewModel()' "$D/MyApp/App.xaml.cs" && ! grep -q 'DataContext =' "$D/MyApp/Views/MainWindow.xaml.cs" && grep -q 'InitializeComponent' "$D/MyApp/Views/MainWindow.xaml.cs" && echo 1 || echo 0)"
ok "full (convention): Grid layout, Auto / * rows, MinWidth / MinHeight, shared margin and style from the ResourceDictionary" "$(f="$D/MyApp/Views/MainWindow.xaml"; grep -q '<Grid>' "$f" && grep -q 'Height="Auto"' "$f" && grep -q 'Height="\*"' "$f" && grep -q 'MinWidth=' "$f" && grep -q 'MinHeight=' "$f" && grep -q 'StaticResource DefaultControlMargin' "$f" && grep -q 'StaticResource PrimaryButtonStyle' "$f" && ! grep -q '<Canvas' "$f" && echo 1 || echo 0)"
ok "full (convention): bindings state their Mode (TwoWay for input, OneWay for display)" "$(f="$D/MyApp/Views/MainWindow.xaml"; grep -q 'Binding Name, Mode=TwoWay' "$f" && grep -q 'Binding Greeting, Mode=OneWay' "$f" && echo 1 || echo 0)"
w="$(python3 -I "$WC" "$D" --all)"; wrc=$?
ok "full: wpf-check finds nothing (error 0 / warning 0 / info 0)" "$([ $wrc = 0 ] && [ "$(has "$w" 'error 0 / warning 0 / info 0')" = 1 ] && echo 1 || echo 0)"
ok "full: the generated MSTest project has the baseline test and the ViewModel tests" "$(grep -c '\[TestMethod\]' "$D/ViewModels.Tests/MainViewModelTests.cs" | grep -q 5 && grep -q '\[TestMethod\]' "$D/DataLayer.Tests/DataLayerInfoTests.cs" && echo 1 || echo 0)"

# ---------------------------------------------------------------- ViewModel 層なし (アプリの中)
D="$(mk NoVm)"
out="$(python3 "$NS" "$D" --type wpf --layers data,logic --tests mstest)"
ok "no viewmodel layer: ViewModel lives in the app (ViewModels/ folder), no assembly= in the XAML" "$([ -f "$D/NoVm/ViewModels/MainViewModel.cs" ] && grep -q 'clr-namespace:NoVm.ViewModels"' "$D/NoVm/Views/MainWindow.xaml" && ! grep -q 'assembly=' "$D/NoVm/Views/MainWindow.xaml" && [ ! -d "$D/ViewModels" ] && echo 1 || echo 0)"
ok "no viewmodel layer: CLAUDE.md says so" "$(grep -q 'ViewModel 層を作っていない' "$D/CLAUDE.md" && echo 1 || echo 0)"
w="$(python3 -I "$WC" "$D" --all)"; wrc=$?
ok "no viewmodel layer: wpf-check finds nothing" "$([ $wrc = 0 ] && [ "$(has "$w" 'error 0 / warning 0 / info 0')" = 1 ] && echo 1 || echo 0)"

D="$(mk AppOnly)"
out="$(python3 "$NS" "$D" --type wpf --layers none --tests none)"
ok "layers none + tests none: the app alone (4 files + csproj, ViewModel inside)" "$([ -f "$D/AppOnly/AppOnly.csproj" ] && [ -f "$D/AppOnly/ViewModels/MainViewModel.cs" ] && [ "$(grep -c '<Project Path=' "$D/AppOnly.slnx")" = 1 ] && grep -q '^- 層: なし$' "$D/CLAUDE.md" && grep -q '^- テスト: なし$' "$D/CLAUDE.md" && echo 1 || echo 0)"
ok "app only: wpf-check finds nothing" "$([ "$(has "$(python3 -I "$WC" "$D" --all)" 'error 0 / warning 0 / info 0')" = 1 ] && echo 1 || echo 0)"

D="$(mk Named)"
out="$(python3 "$NS" "$D" --type wpf --layers data:OrderData,logic:OrderLogic,viewmodel:AppViewModels --tests mstest --namespace Acme.Shop --tfm net10.0)"; rc=$?
ok "custom layer names / namespace / tfm: created" "$([ $rc = 0 ] && [ -f "$D/AppViewModels.Tests/AppViewModels.Tests.csproj" ] && grep -q 'namespace Acme.Shop.Data;' "$D/OrderData/OrderDataInfo.cs" && grep -q 'namespace Acme.Shop.ViewModels;' "$D/AppViewModels/MainViewModel.cs" && grep -q 'net10.0-windows' "$D/Named/Named.csproj" && grep -q '>net10.0<' "$D/OrderLogic/OrderLogic.csproj" && echo 1 || echo 0)"
ok "custom names: recorded as key:name in CLAUDE.md" "$(grep -q '^- 層: data:OrderData,logic:OrderLogic,viewmodel:AppViewModels$' "$D/CLAUDE.md" && echo 1 || echo 0)"
w="$(python3 -I "$WC" "$D" --all)"; wrc=$?
ok "custom names: wpf-check finds nothing" "$([ $wrc = 0 ] && [ "$(has "$w" 'error 0 / warning 0 / info 0')" = 1 ] && echo 1 || echo 0)"

D="$(mk Std)"
out="$(python3 "$NS" "$D" --type wpf --layers data:Std.Domain,logic:Std.Application,viewmodel:Std.Presentation --tests mstest)"; rc=$?
ok "dotted layer names (Std.Domain / Std.Application / Std.Presentation): created, namespace = the name, type names without dots" "$([ $rc = 0 ] && [ -f "$D/Std.Domain/Std.Domain.csproj" ] && [ -f "$D/Std.Domain.Tests/Std.Domain.Tests.csproj" ] && grep -q 'namespace Std.Domain;' "$D/Std.Domain/StdDomainInfo.cs" && grep -q 'public static class StdDomainInfo' "$D/Std.Domain/StdDomainInfo.cs" && grep -q 'StdDomainInfo.Name' "$D/Std.Domain.Tests/StdDomainInfoTests.cs" && grep -q 'Assert.AreEqual("Std.Domain"' "$D/Std.Domain.Tests/StdDomainInfoTests.cs" && echo 1 || echo 0)"
ok "dotted names: dependency chain and the XAML assembly name follow the project names" "$(grep -q 'Std.Application' "$D/Std.Presentation/Std.Presentation.csproj" && grep -q 'assembly=Std.Presentation' "$D/Std/Views/MainWindow.xaml" && echo 1 || echo 0)"
ok "dotted names: the app's using / xmlns use the ViewModel project's namespace (WS19: not <root>.ViewModels)" "$(grep -q '^using Std.Presentation;' "$D/Std/App.xaml.cs" && grep -q 'clr-namespace:Std.Presentation;assembly=Std.Presentation' "$D/Std/Views/MainWindow.xaml" && ! grep -rq 'Std.ViewModels' "$D/Std" && echo 1 || echo 0)"
w="$(python3 -I "$WC" "$D" --all)"; wrc=$?
ok "dotted names: wpf-check finds nothing (standard layer rules are satisfied)" "$([ $wrc = 0 ] && [ "$(has "$w" 'error 0 / warning 0 / info 0')" = 1 ] && echo 1 || echo 0)"
D="$(mk Ver)"
out="$(python3 "$NS" "$D" --type wpf --layers logic --tests mstest --mstest-version 3.9.3 --testsdk-version 17.14.1)"
ok "--mstest-version / --testsdk-version are written" "$(grep -q 'MSTest.TestFramework" Version="3.9.3"' "$D/LogicLayer.Tests/LogicLayer.Tests.csproj" && grep -q 'Test.Sdk" Version="17.14.1"' "$D/LogicLayer.Tests/LogicLayer.Tests.csproj" && echo 1 || echo 0)"

# ---------------------------------------------------------------- dry-run / 引数の検証
D="$(mk Dry)"
out="$(python3 "$NS" "$D" --type wpf --layers logic --tests mstest --dry-run)"
ok "dry-run: shows the plan (MSTest versions, NuGet note), writes nothing" "$([ "$(has "$out" 'MSTest 3.6.4 / Microsoft.NET.Test.Sdk 17.12.0')" = 1 ] && [ "$(has "$out" 'NUGET:')" = 1 ] && [ "$(ls -A "$D" | wc -l)" = 0 ] && echo 1 || echo 0)"
err() {  # $1=説明 残り=引数。rc=2 で、何も書かないこと
    local why="$1"; shift; local d; d="$(mk "e_$RANDOM")"
    local o rc; o="$(python3 "$NS" "$d" "$@")"; rc=$?
    ok "error: $why (rc=2, nothing written)" "$([ $rc = 2 ] && [ "$(ls -A "$d" | wc -l)" = 0 ] && echo 1 || echo 0)"
}
err "gtest with wpf" --type wpf --layers logic --tests gtest
err "mstest with a C++ type" --type console --layers none --tests mstest
err "mstest without layers (the app is not tested)" --type wpf --layers none --tests mstest
err "wpf without --tests" --type wpf --layers logic
err "wpf without --layers" --type wpf --tests none
err "--layer-kind with wpf" --type wpf --layers logic --tests none --layer-kind lib
err "--gtest with wpf" --type wpf --layers logic --tests none --gtest source
err "--toolset with wpf" --type wpf --layers logic --tests none --toolset v145
err "unknown layer key for wpf" --type wpf --layers domain --tests none
err "viewmodel layer for a C++ type" --type mfc --layers viewmodel --tests none
err "layer name with a bad character" --type wpf --layers 'data:Bad..Name' --tests none
err "bad tfm" --type wpf --layers logic --tests none --tfm net8
err "bad namespace" --type wpf --layers logic --tests none --namespace '1bad'
err "bad MSTest version" --type wpf --layers logic --tests mstest --mstest-version '3.0; calc'
err "--tfm with a C++ type" --type console --layers none --tests none --tfm net10.0
D="$(mk Exists)"; mkdir "$D/LogicLayer"
out="$(python3 "$NS" "$D" --type wpf --layers logic --tests none)"; rc=$?
ok "an existing project folder -> rc=3, nothing overwritten" "$([ $rc = 3 ] && [ ! -f "$D/Exists.slnx" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- テストの後付け
D="$(mk Later)"
python3 "$NS" "$D" --type wpf --layers data,logic,viewmodel --tests none >/dev/null
out="$(python3 "$NS" "$D" --tests mstest --dry-run)"
ok "later: dry-run lists the libraries without tests (not the app)" "$([ "$(has "$out" 'DataLayer, LogicLayer, ViewModels')" = 1 ] && [ ! -d "$D/DataLayer.Tests" ] && echo 1 || echo 0)"
out="$(python3 "$NS" "$D" --tests mstest)"; rc=$?
ok "later: .Tests projects added for 3 libraries, ViewModels gets MainViewModelTests" "$([ $rc = 0 ] && [ -f "$D/DataLayer.Tests/DataLayer.Tests.csproj" ] && [ -f "$D/LogicLayer.Tests/LogicLayer.Tests.csproj" ] && [ -f "$D/ViewModels.Tests/MainViewModelTests.cs" ] && [ ! -d "$D/Later.Tests" ] && [ "$(grep -c '<Project Path=' "$D/Later.slnx")" = 7 ] && echo 1 || echo 0)"
ok "later: CLAUDE.md test line updated, MSTest section added" "$(grep -q '^- テスト: あり (MSTest)$' "$D/CLAUDE.md" && grep -q '^## テスト (MSTest)' "$D/CLAUDE.md" && echo 1 || echo 0)"
ok "later: namespaces read from the existing csproj" "$(grep -q 'RootNamespace>Later.Logic.Tests<' "$D/LogicLayer.Tests/LogicLayer.Tests.csproj" && echo 1 || echo 0)"
out="$(python3 "$NS" "$D" --tests mstest)"; rc=$?
ok "later: again -> rc=2 (nothing left to add)" "$([ $rc = 2 ] && echo 1 || echo 0)"
out="$(python3 "$NS" "$D" --tests gtest)"; rc=$?
ok "later: --tests gtest on a .NET solution -> rc=2 (use mstest)" "$([ $rc = 2 ] && [ "$(has "$out" 'mstest')" = 1 ] && echo 1 || echo 0)"
out="$(python3 "$NS" "$D" --type wpf --tests mstest)"; rc=$?
ok "later: --type with an existing solution -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
w="$(python3 -I "$WC" "$D" --all)"; wrc=$?
ok "later: wpf-check still finds nothing" "$([ $wrc = 0 ] && [ "$(has "$w" 'error 0 / warning 0 / info 0')" = 1 ] && echo 1 || echo 0)"

D="$(mk Cpp)"
python3 "$NS" "$D" --type console --layers none --tests none >/dev/null
out="$(python3 "$NS" "$D" --tests mstest)"; rc=$?
ok "mstest on a C++ solution -> rc=2 (use gtest)" "$([ $rc = 2 ] && [ "$(has "$out" 'gtest')" = 1 ] && echo 1 || echo 0)"
out="$(python3 "$NS" "$D" --check-git)"
ok "C++ paths still work (--check-git runs)" "$([ -n "$out" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- --spec
D="$(mk FromSpec)"
mkdir -p "$D/docs/specs"
cat > "$D/docs/specs/f.md" <<'MD'
# 機能
## 構成案
- メインの種類: wpf (画面が要る)
- 層: data,logic,viewmodel
- テスト: mstest
- 名前空間: Spec
MD
out="$(python3 "$NS" "$D" --spec "$D/docs/specs/f.md" --dry-run)"
ok "--spec: reads wpf / layers / mstest / namespace from the plan" "$([ "$(has "$out" 'type=wpf')" = 1 ] && [ "$(has "$out" 'tests=mstest')" = 1 ] && [ "$(has "$out" '名前空間       : Spec')" = 1 ] && [ "$(has "$out" 'ViewModels.Tests')" = 1 ] && echo 1 || echo 0)"

# new-solution: WPF で --layers を省略したときの推奨は data,logic (viewmodel は、選択肢に出さず、テストしたいときに足す) (v2.38.0)
NSK="$ROOT/skills/new-solution/SKILL.md"
ok "new-solution SKILL.md: WPF recommends data,logic when --layers is omitted; viewmodel is offered only when the user wants to test the ViewModel; an explicit --layers is used as given" "$(grep -q 'WPF でも、推奨は `data,logic`' "$NSK" && grep -q '選択肢に、`viewmodel` を出さない' "$NSK" && grep -q 'data,logic,viewmodel` を提案する' "$NSK" && grep -q '`--layers` の指定がある場合は、そのまま使う' "$NSK" && echo 1 || echo 0)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
