#!/usr/bin/env bash
# new_solution_csharp_dll_test.sh - new_solution.py の C# クラスライブラリ (--type csharp-dll) を、疑似フォルダで検証する。
# Windows も .NET も不要。
# Usage: tests/new_solution_csharp_dll_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
T="${TMPDIR:-/tmp}/nsdll_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
mk() { mkdir -p "$T/$1"; echo "$T/$1"; }
bom_crlf() { [ "$(head -c3 "$1" | xxd -p)" = efbbbf ] && [ "$(grep -vc $'\r$' "$1")" = 0 ]; }

# ---------------------------------------------------------------- 層 + テスト
D="$(mk MyLib)"
python3 "$NS" "$D" --type csharp-dll --layers data,logic --tests mstest >/dev/null; rc=$?
ok "full: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "full: main + 2 layers + 3 test projects (the main is a test target itself)" "$(for p in MyLib DataLayer LogicLayer MyLib.Tests DataLayer.Tests LogicLayer.Tests; do [ -f "$D/$p/$p.csproj" ] || exit 1; done; echo 1)"
ok "full: slnx has 6 projects and no DefaultStartup (no exe)" "$([ "$(grep -c '<Project Path=' "$D/MyLib.slnx")" = 6 ] && ! grep -q DefaultStartup "$D/MyLib.slnx" && echo 1 || echo 0)"
ok "full: the main is a plain library (no OutputType, no windows tfm, no UseWPF) that references the layers" "$(! grep -q 'OutputType\|windows\|UseWPF' "$D/MyLib/MyLib.csproj" && grep -q 'LogicLayer.csproj' "$D/MyLib/MyLib.csproj" && grep -q 'DataLayer.csproj' "$D/MyLib/MyLib.csproj" && echo 1 || echo 0)"
ok "full: MyLib.Tests references MyLib and is an MSTest project" "$(grep -q '\.\.\\MyLib\\MyLib.csproj' "$D/MyLib.Tests/MyLib.Tests.csproj" && grep -q 'MSTest.TestFramework' "$D/MyLib.Tests/MyLib.Tests.csproj" && grep -q '\[TestMethod\]' "$D/MyLib.Tests/MyLibInfoTests.cs" && echo 1 || echo 0)"
ok "full: namespaces MyLib / MyLib.Data / MyLib.Logic" "$(grep -q 'namespace MyLib;' "$D/MyLib/MyLibInfo.cs" && grep -q 'namespace MyLib.Data;' "$D/DataLayer/DataLayerInfo.cs" && grep -q 'namespace MyLib.Logic;' "$D/LogicLayer/LogicLayerInfo.cs" && echo 1 || echo 0)"
ok "full: .cs / .csproj are BOM + CRLF" "$(for f in MyLib/MyLib.csproj MyLib/MyLibInfo.cs MyLib.Tests/MyLibInfoTests.cs Directory.Build.props; do bom_crlf "$D/$f" || exit 1; done; echo 1)"
ok "full: CLAUDE.md records main / layers / tests (3 lines the other commands read)" "$(grep -qx -- '- メイン: MyLib (C# クラスライブラリ)' "$D/CLAUDE.md" && grep -qx -- '- 層: data,logic' "$D/CLAUDE.md" && grep -qx -- '- テスト: あり (MSTest)' "$D/CLAUDE.md" && ! grep -q 'wpf-check\|XAML を編集' "$D/CLAUDE.md" && echo 1 || echo 0)"

# ---------------------------------------------------------------- 層なし + テストあり (メイン自身がテストの対象)
D="$(mk Solo)"
python3 "$NS" "$D" --type csharp-dll --layers none --tests mstest >/dev/null; rc=$?
ok "layers none + mstest: Solo + Solo.Tests only" "$([ $rc = 0 ] && [ -f "$D/Solo.Tests/Solo.Tests.csproj" ] && [ "$(grep -c '<Project Path=' "$D/Solo.slnx")" = 2 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- テストなし → 後付け
D="$(mk Later)"
python3 "$NS" "$D" --type csharp-dll --layers logic --tests none >/dev/null
ok "tests none: no test project, CLAUDE.md says テスト: なし" "$([ ! -d "$D/Later.Tests" ] && grep -qx -- '- テスト: なし' "$D/CLAUDE.md" && echo 1 || echo 0)"
python3 "$NS" "$D" --tests mstest >/dev/null; rc=$?
ok "retrofit --tests mstest: adds Later.Tests and LogicLayer.Tests" "$([ $rc = 0 ] && [ -f "$D/Later.Tests/Later.Tests.csproj" ] && [ -f "$D/LogicLayer.Tests/LogicLayer.Tests.csproj" ] && grep -qx -- '- テスト: あり (MSTest)' "$D/CLAUDE.md" && echo 1 || echo 0)"

# ---------------------------------------------------------------- 異常系
D="$(mk Bad1)"
python3 "$NS" "$D" --type csharp-dll --layers viewmodel --tests none >/dev/null 2>&1; rc=$?
ok "viewmodel layer is rejected for csharp-dll (rc=2)" "$([ $rc = 2 ] && echo 1 || echo 0)"
D="$(mk Bad2)"
python3 "$NS" "$D" --type csharp-dll --layers none --tests none --ui-tests flaui >/dev/null 2>&1; rc=$?
ok "--ui-tests flaui is rejected for csharp-dll (rc=2)" "$([ $rc = 2 ] && echo 1 || echo 0)"
D="$(mk Bad3)"
python3 "$NS" "$D" --type csharp-dll --layers none --tests gtest >/dev/null 2>&1; rc=$?
ok "--tests gtest is rejected for csharp-dll (rc=2)" "$([ $rc = 2 ] && echo 1 || echo 0)"
D="$(mk Spec)"; mkdir -p "$D/docs/specs"
printf '# s\n\n## 構成案\n- メインの種類: csharp-dll\n- 層: logic\n- テスト: mstest\n' > "$D/docs/specs/f.md"
python3 "$NS" "$D" --spec "$D/docs/specs/f.md" >/dev/null; rc=$?
ok "--spec: csharp-dll is accepted from the 構成案" "$([ $rc = 0 ] && [ -f "$D/LogicLayer.Tests/LogicLayer.Tests.csproj" ] && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
