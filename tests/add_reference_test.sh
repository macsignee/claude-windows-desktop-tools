#!/usr/bin/env bash
# add_reference_test.sh - add_reference.py (使う側のプロジェクトに、使われる側への参照を足す) を、生成したソリューションで検証する。
# Usage: tests/add_reference_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
# Windows / Visual Studio は不要 (生成した XML を読む)。コンパイルとリンクは、実機: docs/TEST-PLAN.md 2-32。
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$ROOT/skills/new-solution/scripts/new_solution.py"
AL="$ROOT/skills/cpp-test-first/scripts/add_layer.py"
AP="$ROOT/skills/csharp-test-first/scripts/add_project.py"
SS="$ROOT/skills/add-project/scripts/solution_state.py"
AR="$ROOT/skills/add-project/scripts/add_reference.py"
MCK="$ROOT/skills/mfc-check/scripts/mfc_check.py"
T="${TMPDIR:-/tmp}/aref_$$"
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
snapshot() { (cd "$1" && find . -type f | sort | xargs md5sum | md5sum); }
filesums() { (cd "$1" && find . -type f | sort | xargs md5sum); }
xml_ok() { python3 -I -c "import sys, xml.dom.minidom as m; m.parse(sys.argv[1])" "$1" >/dev/null 2>&1 && echo 1 || echo 0; }
bom_crlf_same() { # <before ファイル> <after ファイル>: BOM の有無と、CRLF の行数 / 全行数が、変わらない
    [ "$(head -c3 "$1" | xxd -p)" = "$(head -c3 "$2" | xxd -p)" ] && [ "$(grep -c $'\r$' "$1")" -gt 0 ] && [ "$(grep -c $'\r$' "$2")" = "$(wc -l < "$2" | tr -d ' ')" ] && echo 1 || echo 0; }
guid() { grep -o '<ProjectGuid>{[^}]*}' "$1" | sed 's/<ProjectGuid>//'; }

# ---- C++: メイン (MFC) → ロジック層
D="$T/Cpp"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc-dialog --layers logic,data --tests gtest --gtest vcpkg >/dev/null 2>&1
cp "$D/Cpp/Cpp.vcxproj" "$T/Cpp.vcxproj.before"; filesums "$D" > "$T/Cpp.sums.before"; before="$(snapshot "$D")"
out="$(python3 "$AR" "$D" --from Cpp --to LogicLayer --dry-run 2>&1)"; rc=$?
ok "cpp dry-run: rc=0、何も書かない、行う内容を表示 (ProjectReference と、推移的な include)" "$([ $rc = 0 ] && [ "$(snapshot "$D")" = "$before" ] && [ "$(has "$out" 'REF: Cpp -> LogicLayer (ProjectReference)')" = 1 ] && [ "$(has "$out" '$(ProjectDir)..\LogicLayer;$(ProjectDir)..\DataLayer')" = 1 ] && [ "$(has "$out" 'dry-run')" = 1 ] && echo 1 || echo 0)"
out="$(python3 "$AR" "$D" --from Cpp --to LogicLayer 2>&1)"; rc=$?
ok "cpp: rc=0、XML として正しい、BOM と CRLF を保つ" "$([ $rc = 0 ] && [ "$(xml_ok "$D/Cpp/Cpp.vcxproj")" = 1 ] && [ "$(bom_crlf_same "$T/Cpp.vcxproj.before" "$D/Cpp/Cpp.vcxproj")" = 1 ] && echo 1 || echo 0)"
filesums "$D" > "$T/Cpp.sums.after"
ok "cpp: 変わるのは、使う側の .vcxproj 1 つだけ (層・テスト・ソリューション・CLAUDE.md は、そのまま)" "$([ "$(diff "$T/Cpp.sums.before" "$T/Cpp.sums.after" | grep -c '^>')" = 1 ] && diff "$T/Cpp.sums.before" "$T/Cpp.sums.after" | grep -q 'Cpp/Cpp.vcxproj' && echo 1 || echo 0)"
ok "cpp: ProjectReference の GUID が、ロジック層の ProjectGuid と一致する" "$(grep -qF "<Project>$(guid "$D/LogicLayer/LogicLayer.vcxproj")</Project>" "$D/Cpp/Cpp.vcxproj" && echo 1 || echo 0)"
ok "cpp: 全構成 (Debug / Release) の AdditionalIncludeDirectories に、ロジックとデータ (テスト exe と同じ形)。ProjectReference は 1 つ" "$([ "$(grep -c 'AdditionalIncludeDirectories>\$(ProjectDir)\.\.\\LogicLayer;\$(ProjectDir)\.\.\\DataLayer;%(AdditionalIncludeDirectories)' "$D/Cpp/Cpp.vcxproj")" = 2 ] && [ "$(grep -c '<ProjectReference Include' "$D/Cpp/Cpp.vcxproj")" = 1 ] && echo 1 || echo 0)"
ok "cpp: ItemGroup は、Microsoft.Cpp.targets の Import より前に入る" "$(awk '/ProjectReference Include/{r=NR} /Microsoft\.Cpp\.targets/{i=NR} END{exit !(r>0 && i>r)}' "$D/Cpp/Cpp.vcxproj" && echo 1 || echo 0)"
python3 "$AR" "$D" --from Cpp --to LogicLayer >/dev/null 2>&1; rc=$?
ok "cpp: 2 回目は、すでにある → rc=3、ファイルは変わらない (冪等)" "$([ $rc = 3 ] && [ "$(md5sum < "$D/Cpp/Cpp.vcxproj")" = "$(filesums "$D" | grep 'Cpp/Cpp.vcxproj' | head -1 | cut -d' ' -f1 | sed 's/$/  -/')" ] && echo 1 || echo 0)"
out="$(python3 "$SS" "$D" 2>&1)"
ok "cpp: solution_state.py が、参照ずみと認識 (SUGGEST_REF が消える)、MISMATCH・REF_ISSUES なし" "$([ "$(has "$out" 'SUGGEST_REF')" = 0 ] && [ "$(has "$out" 'PROJECT: Cpp | exe | main | - | LogicLayer | LogicLayer,DataLayer')" = 1 ] && [ "$(has "$out" 'MISMATCH')" = 0 ] && [ "$(has "$out" 'REF_ISSUES')" = 0 ] && echo 1 || echo 0)"
out="$(python3 -I "$MCK" "$D" --all 2>&1)"
ok "cpp: mfc-check は、error 0 / warning 0" "$([ "$(has "$out" 'error 0 / warning 0')" = 1 ] && echo 1 || echo 0)"

# ---- C++: 向き・循環・自分自身・存在しない・テスト
out="$(python3 "$AR" "$D" --from DataLayer --to LogicLayer 2>&1)"; rc=$?
ok "向き: データ層が、ロジック層を参照 → rc=2、書かない" "$([ $rc = 2 ] && [ "$(has "$out" '層の向きの違反')" = 1 ] && grep -qv 'LogicLayer' "$D/DataLayer/DataLayer.vcxproj" && echo 1 || echo 0)"
out="$(python3 "$AR" "$D" --from LogicLayer --to Cpp 2>&1)"; rc=$?
ok "向き: ロジック層が、メインを参照 → rc=2" "$([ $rc = 2 ] && [ "$(has "$out" '層の向きの違反')" = 1 ] && echo 1 || echo 0)"
python3 "$AR" "$D" --from Cpp --to Cpp >/dev/null 2>&1; r1=$?
python3 "$AR" "$D" --from Cpp --to NoSuch >/dev/null 2>&1; r2=$?
python3 "$AR" "$D" --from NoSuch --to Cpp >/dev/null 2>&1; r3=$?
python3 "$AR" "$D" --from Cpp --to LogicLayerTest >/dev/null 2>&1; r4=$?
ok "断る (rc=2): 自分自身、存在しない (どちら側も)、テストのプロジェクトを参照" "$([ $r1 = 2 ] && [ $r2 = 2 ] && [ $r3 = 2 ] && [ $r4 = 2 ] && echo 1 || echo 0)"
python3 "$AR" "$D" --from LogicLayerTest --to DataLayer >/dev/null 2>&1; rc=$?
ok "テスト exe (使う側) も、層を参照できる (ProjectReference が足される。include は、すでにある)" "$([ $rc = 0 ] && [ "$(grep -c '<ProjectReference Include' "$D/LogicLayerTest/LogicLayerTest.vcxproj")" = 2 ] && [ "$(xml_ok "$D/LogicLayerTest/LogicLayerTest.vcxproj")" = 1 ] && echo 1 || echo 0)"

# ---- C++: 循環 (役割が「その他」の層どうし)
D="$T/Cyc"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers none --tests none >/dev/null 2>&1
python3 "$AL" "$D" ReportA --tests none >/dev/null 2>&1
python3 "$AL" "$D" ReportB --tests none >/dev/null 2>&1
python3 "$AR" "$D" --from ReportA --to ReportB >/dev/null 2>&1; r1=$?
out="$(python3 "$AR" "$D" --from ReportB --to ReportA 2>&1)"; r2=$?
ok "循環: A → B のあと、B → A を断る (rc=2)" "$([ $r1 = 0 ] && [ $r2 = 2 ] && [ "$(has "$out" '循環')" = 1 ] && echo 1 || echo 0)"
python3 "$AR" "$D" --from NoLogicChk --to ReportA >/dev/null 2>&1
python3 "$AR" "$D" --from Cyc --to ReportA >/dev/null 2>&1; rc=$?
ok "メイン (console) → その他の層: 参照できる" "$([ $rc = 0 ] && [ "$(xml_ok "$D/Cyc/Cyc.vcxproj")" = 1 ] && echo 1 || echo 0)"

# ---- C++: --include-only、MFC 拡張 DLL
D="$T/Inc"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers none --tests none >/dev/null 2>&1
python3 "$AL" "$D" ReportA --tests none >/dev/null 2>&1
python3 "$AR" "$D" --from Inc --to ReportA --include-only >/dev/null 2>&1; rc=$?
ok "include-only: ProjectReference を足さず、インクルードパスだけを足す" "$([ $rc = 0 ] && [ "$(grep -c '<ProjectReference' "$D/Inc/Inc.vcxproj")" = 0 ] && [ "$(grep -c 'AdditionalIncludeDirectories>\$(ProjectDir)\.\.\\ReportA;' "$D/Inc/Inc.vcxproj")" = 2 ] && echo 1 || echo 0)"
python3 "$AR" "$D" --from Inc --to ReportA --include-only >/dev/null 2>&1; r2=$?
python3 "$AR" "$D" --from Inc --to ReportA >/dev/null 2>&1; r3=$?
ok "include-only のあと: もう一度は rc=3。ProjectReference を足す呼び出しは、足りない ProjectReference だけを足す (rc=0)" "$([ $r2 = 3 ] && [ $r3 = 0 ] && [ "$(grep -c '<ProjectReference Include' "$D/Inc/Inc.vcxproj")" = 1 ] && [ "$(grep -c 'AdditionalIncludeDirectories>\$(ProjectDir)\.\.\\ReportA;' "$D/Inc/Inc.vcxproj")" = 2 ] && echo 1 || echo 0)"
python3 "$AL" "$D" ExtLayer --kind mfc-ext-dll --tests none >/dev/null 2>&1
out="$(python3 "$AR" "$D" --from Inc --to ExtLayer 2>&1)"; rc=$?
ok "MFC 拡張 DLL を、UseOfMfc のない使う側 (console) から参照 → rc=2 (DLL008)。include-only なら通る" "$([ $rc = 2 ] && [ "$(has "$out" 'UseOfMfc')" = 1 ] && python3 "$AR" "$D" --from Inc --to ExtLayer --include-only >/dev/null 2>&1 && echo 1 || echo 0)"
D="$T/MfcExt"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc-dialog --layers none --tests none >/dev/null 2>&1
python3 "$AL" "$D" ExtLayer --kind mfc-ext-dll --tests none >/dev/null 2>&1
python3 "$AR" "$D" --from MfcExt --to ExtLayer >/dev/null 2>&1; rc=$?
out="$(python3 -I "$MCK" "$D" --all 2>&1)"
ok "MFC のメイン → MFC 拡張 DLL: 参照できる。mfc-check は、DLL008 を出さない (error 0)" "$([ $rc = 0 ] && [ "$(has "$out" 'DLL008')" = 0 ] && [ "$(has "$out" 'error 0')" = 1 ] && echo 1 || echo 0)"

# ---- C++ と、UI テスト (C#) の組み合わせ
D="$T/UiT"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc-dialog --layers logic --tests none --ui-tests flaui >/dev/null 2>&1
out="$(python3 "$AR" "$D" --from UiT --to UiT.UITests 2>&1)"; rc=$?
ok "UI テストのプロジェクト (C#) への参照は、断る (rc=2)。言語も違う" "$([ $rc = 2 ] && echo 1 || echo 0)"
out="$(python3 "$AR" "$D" --from UiT.UITests --to LogicLayer 2>&1)"; rc=$?
ok "UI テストのプロジェクトからの参照も、断る (rc=2)" "$([ $rc = 2 ] && [ "$(has "$out" 'UI テスト')" = 1 ] && echo 1 || echo 0)"

# ---- .NET (WPF)
D="$T/Wpf"; mkdir -p "$D"
python3 "$NEW" "$D" --type wpf --layers data,logic --tests mstest >/dev/null 2>&1
python3 "$AP" "$D" ReportLib --tests none >/dev/null 2>&1
cp "$D/Wpf/Wpf.csproj" "$T/Wpf.csproj.before"; filesums "$D" > "$T/Wpf.sums.before"
out="$(python3 "$SS" "$D" 2>&1)"
ok "wpf: 追加した ReportLib は、どこからも参照されない → SUGGEST_REF (足す前)" "$([ "$(has "$out" 'SUGGEST_REF')" = 0 ] && echo 1 || echo 0)"
python3 "$AR" "$D" --from Wpf --to ReportLib >/dev/null 2>&1; rc=$?
filesums "$D" > "$T/Wpf.sums.after"
ok "wpf: rc=0、XML として正しい、BOM と CRLF を保つ、変わるのは使う側の .csproj 1 つだけ" "$([ $rc = 0 ] && [ "$(xml_ok "$D/Wpf/Wpf.csproj")" = 1 ] && [ "$(bom_crlf_same "$T/Wpf.csproj.before" "$D/Wpf/Wpf.csproj")" = 1 ] && [ "$(diff "$T/Wpf.sums.before" "$T/Wpf.sums.after" | grep -c '^>')" = 1 ] && echo 1 || echo 0)"
ok "wpf: 既存の ProjectReference の並びに、同じ字下げで 1 行足される (ItemGroup は、増えない)" "$([ "$(grep -c '<ProjectReference Include' "$D/Wpf/Wpf.csproj")" = 3 ] && grep -q $'^    <ProjectReference Include="..\\\\ReportLib\\\\ReportLib.csproj" />' "$D/Wpf/Wpf.csproj" && [ "$(grep -c '<ItemGroup>' "$D/Wpf/Wpf.csproj")" = 1 ] && echo 1 || echo 0)"
python3 "$AR" "$D" --from Wpf --to ReportLib >/dev/null 2>&1; rc=$?
ok "wpf: 2 回目は rc=3 (冪等)" "$([ $rc = 3 ] && [ "$(grep -c '<ProjectReference Include' "$D/Wpf/Wpf.csproj")" = 3 ] && echo 1 || echo 0)"
python3 "$AR" "$D" --from ReportLib --to DataLayer >/dev/null 2>&1; rc=$?
ok "wpf: ProjectReference のない csproj には、ItemGroup ごと足す。XML として正しい、BOM と CRLF を保つ" "$([ $rc = 0 ] && [ "$(xml_ok "$D/ReportLib/ReportLib.csproj")" = 1 ] && grep -q 'ProjectReference Include="..\\DataLayer\\DataLayer.csproj"' "$D/ReportLib/ReportLib.csproj" && [ "$(head -c3 "$D/ReportLib/ReportLib.csproj" | xxd -p)" = efbbbf ] && [ "$(grep -c $'\r$' "$D/ReportLib/ReportLib.csproj")" = "$(wc -l < "$D/ReportLib/ReportLib.csproj" | tr -d ' ')" ] && echo 1 || echo 0)"
out="$(python3 "$AR" "$D" --from DataLayer --to LogicLayer 2>&1)"; rc=$?
ok "wpf: 向きの違反 (データ → ロジック) を断る (rc=2)" "$([ $rc = 2 ] && [ "$(has "$out" '層の向きの違反')" = 1 ] && echo 1 || echo 0)"
python3 "$AR" "$D" --from Wpf --to DataLayer --include-only >/dev/null 2>&1; rc=$?
ok "wpf: --include-only は C++ だけ (rc=2)" "$([ $rc = 2 ] && echo 1 || echo 0)"
python3 "$AR" "$D" --from LogicLayer.Tests --to DataLayer >/dev/null 2>&1; rc=$?
ok "wpf: テストプロジェクトからの参照は、できる (rc=0)" "$([ $rc = 0 ] && [ "$(xml_ok "$D/LogicLayer.Tests/LogicLayer.Tests.csproj")" = 1 ] && echo 1 || echo 0)"
out="$(python3 "$SS" "$D" 2>&1)"
ok "wpf: ReportLib を足したあとの solution_state: SUGGEST_REF も REF_ISSUES もない" "$([ "$(has "$out" 'SUGGEST_REF')" = 0 ] && [ "$(has "$out" 'REF_ISSUES')" = 0 ] && echo 1 || echo 0)"

# ---- 終了コード・ほかの入力
python3 "$AR" "$T/none_such" --from A --to B >/dev/null 2>&1; r1=$?
E="$T/Empty"; mkdir -p "$E"; python3 "$AR" "$E" --from A --to B >/dev/null 2>&1; r2=$?
M="$T/Two"; mkdir -p "$M"; : > "$M/A.slnx"; : > "$M/B.slnx"; python3 "$AR" "$M" --from A --to B >/dev/null 2>&1; r3=$?
python3 "$AR" "$D" --from Wpf >/dev/null 2>&1; r4=$?
ok "rc=2: フォルダなし・ソリューションなし・ソリューションが複数・--to なし" "$([ $r1 = 2 ] && [ $r2 = 2 ] && [ $r3 = 2 ] && [ $r4 = 2 ] && echo 1 || echo 0)"
ok "add_reference.py: Python 3 の標準ライブラリだけ (solution_state.py の読み込みを除く)" "$(! grep -qE '^(import|from) (yaml|requests|lxml|numpy)' "$AR" && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
