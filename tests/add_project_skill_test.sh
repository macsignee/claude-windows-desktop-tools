#!/usr/bin/env bash
# add_project_skill_test.sh - /add-project (skills/add-project) の補助スクリプト solution_state.py (読み取りだけ) を、生成したソリューションで検証する。
# Usage: tests/add_project_skill_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
# Windows / Visual Studio は不要 (生成した XML と CLAUDE.md を読む)。実機の確認は docs/TEST-PLAN.md 2-31。
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$ROOT/skills/new-solution/scripts/new_solution.py"
AL="$ROOT/skills/cpp-test-first/scripts/add_layer.py"
AUH="$ROOT/skills/cpp-test-first/scripts/add_ui_host.py"
SS="$ROOT/skills/add-project/scripts/solution_state.py"
SK="$ROOT/skills/add-project/SKILL.md"
T="${TMPDIR:-/tmp}/aprj_$$"
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
lines() { grep -c -- "$2" <<<"$1"; }
snapshot() { (cd "$1" && find . -type f | sort | xargs md5sum | md5sum); }

# ---- C++ (MFC ダイアログ + ロジック + データ + テスト)
D="$T/Cpp"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc-dialog --layers logic,data --tests gtest --gtest vcpkg >/dev/null 2>&1
before="$(snapshot "$D")"
out="$(python3 "$SS" "$D" 2>&1)"; rc=$?
ok "cpp: rc=0、何も書かない (読み取りだけ)" "$([ $rc = 0 ] && [ "$(snapshot "$D")" = "$before" ] && echo 1 || echo 0)"
ok "cpp: KIND=cpp、メインは CLAUDE.md の記述 (MFC ダイアログ)" "$([ "$(has "$out" 'KIND: cpp')" = 1 ] && [ "$(has "$out" 'MAIN: Cpp (MFC ダイアログ)')" = 1 ] && echo 1 || echo 0)"
ok "cpp: 層の役割とテストの対応 (DataLayer=data/DataLayerTest、LogicLayer=logic/LogicLayerTest)" "$([ "$(has "$out" 'PROJECT: DataLayer | dll | data | DataLayerTest')" = 1 ] && [ "$(has "$out" 'PROJECT: LogicLayer | dll | logic | LogicLayerTest')" = 1 ] && echo 1 || echo 0)"
ok "cpp: テスト exe は役割 test、参照 (ProjectReference) と include だけの参照を、分けて出す" "$([ "$(has "$out" 'PROJECT: LogicLayerTest | test | test | - | LogicLayer | LogicLayer,DataLayer')" = 1 ] && [ "$(has "$out" 'PROJECT: LogicLayer | dll | logic | LogicLayerTest | - | DataLayer')" = 1 ] && echo 1 || echo 0)"
ok "cpp: 食い違いなし (MISMATCH なし)、向きの違反なし" "$([ "$(lines "$out" '^MISMATCH')" = 0 ] && [ "$(lines "$out" '^REF_ISSUES')" = 0 ] && echo 1 || echo 0)"
ok "cpp: メインが、層を参照していない → SUGGEST_REF (メイン -> ロジック)。データは、ロジックが include で使うので、出ない" "$([ "$(has "$out" 'SUGGEST_REF: Cpp -> LogicLayer')" = 1 ] && [ "$(has "$out" '-> DataLayer')" = 0 ] && echo 1 || echo 0)"
ok "cpp: ADDABLE に、層・UI DLL + 画面ホスト・UI テスト (メインが画面あり)。テストは揃っているので、tests-for は出ない" "$([ "$(has "$out" 'ADDABLE: layer |')" = 1 ] && [ "$(has "$out" 'ADDABLE: ui-host |')" = 1 ] && [ "$(has "$out" 'ADDABLE: ui-tests:Cpp |')" = 1 ] && [ "$(has "$out" 'tests-for:')" = 0 ] && echo 1 || echo 0)"
ok "cpp: ADDABLE の例は、既存のスクリプトの --dry-run を指す (add_layer.py / add_ui_host.py)" "$([ "$(has "$out" 'add_layer.py "<SLN_DIR>" <Name>')" = 1 ] && [ "$(has "$out" 'add_ui_host.py "<SLN_DIR>"')" = 1 ] && echo 1 || echo 0)"

# ---- C++: テストのない層 → tests-for、MFC の層の種類
D="$T/NoTests"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic,data --tests none >/dev/null 2>&1
out="$(python3 "$SS" "$D" 2>&1)"
ok "notests: テストのない層に、tests-for (DataLayer / LogicLayer)。メイン exe には出ない" "$([ "$(has "$out" 'ADDABLE: tests-for:DataLayer |')" = 1 ] && [ "$(has "$out" 'ADDABLE: tests-for:LogicLayer |')" = 1 ] && [ "$(has "$out" 'tests-for:NoTests')" = 0 ] && echo 1 || echo 0)"
ok "notests: 画面のないメイン (console) に、ui-tests は出ない" "$([ "$(has "$out" 'ui-tests:')" = 0 ] && echo 1 || echo 0)"
python3 "$AL" "$D" ExtLayer --kind mfc-ext-dll --tests none >/dev/null 2>&1
python3 "$AL" "$D" StdLayer --kind mfc-std-dll --tests none >/dev/null 2>&1
out="$(python3 "$SS" "$D" 2>&1)"
ok "mfc: 拡張 DLL / 標準 DLL を、種類で見分ける" "$([ "$(has "$out" 'PROJECT: ExtLayer | mfc-ext-dll |')" = 1 ] && [ "$(has "$out" 'PROJECT: StdLayer | mfc-std-dll |')" = 1 ] && echo 1 || echo 0)"
ok "mfc: add_layer.py は CLAUDE.md を更新しない → 追加した層が MISMATCH に出る (/add-project が CLAUDE.md を直す理由)" "$([ "$(has "$out" 'MISMATCH: ExtLayer')" = 1 ] && [ "$(has "$out" 'MISMATCH: StdLayer')" = 1 ] && echo 1 || echo 0)"

# ---- 画面を持つ DLL + 画面ホスト
D="$T/UiHost"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic,data --tests gtest --gtest vcpkg >/dev/null 2>&1
python3 "$AUH" "$D" >/dev/null 2>&1
out="$(python3 "$SS" "$D" 2>&1)"
ok "uihost: UI DLL は役割 ui、画面ホストの exe は main。UI DLL には、tests-for を出さない" "$([ "$(has "$out" 'PROJECT: UiLayer | mfc-std-dll | ui |')" = 1 ] && [ "$(has "$out" 'tests-for:UiLayer')" = 0 ] && echo 1 || echo 0)"
ok "uihost: UI テスト (<ホスト>.UITests) は uitest と認識し、すでにあるホストに、ui-tests を出さない。KIND は cpp のまま (C# の UI テストがあっても mixed にしない)" "$([ "$(has "$out" 'UiLayerHost.UITests | uitest | uitest')" = 1 ] && [ "$(has "$out" 'KIND: cpp')" = 1 ] && [ "$(has "$out" 'ui-tests:UiLayerHost')" = 0 ] && echo 1 || echo 0)"

# ---- 参照の向きの違反 (下の層が、上の層を参照)
D="$T/BadDir"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic,data --tests none >/dev/null 2>&1
python3 -I - "$D/DataLayer/DataLayer.vcxproj" <<'PY'
import sys
p = sys.argv[1]
raw = open(p, 'rb').read(); bom = raw.startswith(b'\xef\xbb\xbf'); s = raw[3:].decode() if bom else raw.decode()
add = '  <ItemGroup>\r\n    <ProjectReference Include="..\\LogicLayer\\LogicLayer.vcxproj" />\r\n  </ItemGroup>\r\n'
i = s.rfind('</Project>'); s = s[:i] + add + s[i:]
open(p, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + s.encode())
PY
out="$(python3 "$SS" "$D" 2>&1)"
ok "baddir: データ層がロジック層を参照 → REF_ISSUES" "$([ "$(has "$out" 'REF_ISSUES: DataLayer (data) が、上の層 LogicLayer (logic) を参照している')" = 1 ] && echo 1 || echo 0)"

# ---- CLAUDE.md との食い違い
D="$T/Mis"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic,data --tests gtest --gtest vcpkg >/dev/null 2>&1
sed -i 's/^- テスト: .*/- テスト: なし/' "$D/CLAUDE.md"
out="$(python3 "$SS" "$D" 2>&1)"
ok "mismatch: テストがあるのに「テスト: なし」" "$([ "$(has "$out" 'MISMATCH: テストプロジェクトがあるのに')" = 1 ] && echo 1 || echo 0)"
mv "$D/CLAUDE.md" "$D/CLAUDE.md.bak"
out="$(python3 "$SS" "$D" 2>&1)"
ok "mismatch: CLAUDE.md がない → absent と MISMATCH、ほかの項目は読める" "$([ "$(has "$out" 'CLAUDE_MD: absent')" = 1 ] && [ "$(has "$out" 'MISMATCH: CLAUDE.md がない')" = 1 ] && [ "$(has "$out" 'PROJECT: LogicLayer')" = 1 ] && echo 1 || echo 0)"

# ---- .NET (WPF)、WinForms、C# クラスライブラリ
D="$T/Wpf"; mkdir -p "$D"
python3 "$NEW" "$D" --type wpf --layers data,logic,viewmodel --tests mstest >/dev/null 2>&1
out="$(python3 "$SS" "$D" 2>&1)"
ok "wpf: KIND=dotnet、wpf-app、ViewModels は viewmodel (画面の層 ui と、取り違えない)" "$([ "$(has "$out" 'KIND: dotnet')" = 1 ] && [ "$(has "$out" 'PROJECT: Wpf | wpf-app | main')" = 1 ] && [ "$(has "$out" 'PROJECT: ViewModels | classlib | viewmodel | ViewModels.Tests')" = 1 ] && echo 1 || echo 0)"
ok "wpf: 参照の向きの違反なし、MISMATCH なし、SUGGEST_REF なし (アプリが、すべての層を参照している)" "$([ "$(lines "$out" '^REF_ISSUES')" = 0 ] && [ "$(lines "$out" '^MISMATCH')" = 0 ] && [ "$(lines "$out" '^SUGGEST_REF')" = 0 ] && echo 1 || echo 0)"
ok "wpf: ADDABLE は add_project.py (層)、UI テスト。C++ 用 (add_layer.py / add_ui_host.py) は出ない" "$([ "$(has "$out" 'add_project.py "<SLN_DIR>" <Name>')" = 1 ] && [ "$(has "$out" 'ui-tests:Wpf |')" = 1 ] && [ "$(has "$out" 'add_layer.py')" = 0 ] && [ "$(has "$out" 'ui-host')" = 0 ] && echo 1 || echo 0)"
D="$T/Wf"; mkdir -p "$D"
python3 "$NEW" "$D" --type winforms --layers data,logic --tests none >/dev/null 2>&1
out="$(python3 "$SS" "$D" 2>&1)"
ok "winforms: winforms-app を見分ける。テストのない層に tests-for" "$([ "$(has "$out" 'PROJECT: Wf | winforms-app | main')" = 1 ] && [ "$(has "$out" 'ADDABLE: tests-for:LogicLayer |')" = 1 ] && echo 1 || echo 0)"
D="$T/Cd"; mkdir -p "$D"
python3 "$NEW" "$D" --type csharp-dll --layers logic --tests mstest >/dev/null 2>&1
out="$(python3 "$SS" "$D" 2>&1)"
ok "csharp-dll: メインがクラスライブラリ (画面なし)。ui-tests は出ない" "$([ "$(has "$out" 'KIND: dotnet')" = 1 ] && [ "$(has "$out" 'ui-tests:')" = 0 ] && echo 1 || echo 0)"

# ---- エラーの終了コード
E="$T/Empty"; mkdir -p "$E"
python3 "$SS" "$E" >/dev/null 2>&1; rc1=$?
python3 "$SS" "$T/none_such" >/dev/null 2>&1; rc2=$?
M="$T/Two"; mkdir -p "$M"; : > "$M/A.slnx"; : > "$M/B.slnx"
python3 "$SS" "$M" >/dev/null 2>&1; rc3=$?
ok "exit codes: ソリューションなし=2、フォルダなし=2、ソリューションが複数=3" "$([ $rc1 = 2 ] && [ $rc2 = 2 ] && [ $rc3 = 3 ] && echo 1 || echo 0)"
ok "solution_state.py: Python 3 の標準ライブラリだけ (外部のパッケージなし)" "$(! grep -qE '^(import|from) (yaml|requests|lxml|numpy)' "$SS" && echo 1 || echo 0)"

# ---- 「追加した層」の行の、テストの有無の食い違い (v2.53.1。AP3 の発見)
D="$T/Note"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic --tests gtest --gtest vcpkg >/dev/null 2>&1
python3 "$AL" "$D" NoteData --tests none >/dev/null 2>&1
printf -- '- 追加した層: NoteData (dll)。データ役割。テストなし。\n' >> "$D/CLAUDE.md"
out="$(python3 "$SS" "$D" 2>&1)"
ok "note: テストのない層の「追加した層: ... テストなし」は、食い違いではない" "$([ "$(has "$out" 'MISMATCH: CLAUDE.md の「追加した層')" = 0 ] && echo 1 || echo 0)"
python3 "$AL" "$D" NoteData --tests-only >/dev/null 2>&1
out="$(python3 "$SS" "$D" 2>&1)"
ok "note: テストを後付けしたのに「追加した層: ... テストなし」のまま → MISMATCH (AP3 の発見)" "$([ "$(has "$out" 'MISMATCH: CLAUDE.md の「追加した層: NoteData」が「テストなし」だが、テスト NoteDataTest がある')" = 1 ] && echo 1 || echo 0)"
sed -i 's/テストなし。/テストあり (NoteDataTest)。/' "$D/CLAUDE.md"
out="$(python3 "$SS" "$D" 2>&1)"
ok "note: 「テストあり (NoteDataTest)」に直すと、MISMATCH が消える" "$([ "$(has "$out" 'MISMATCH')" = 0 ] && echo 1 || echo 0)"
D="$T/Note2"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic --tests gtest --gtest vcpkg >/dev/null 2>&1
printf -- '- 追加した層: NoSuchLayer (dll)。テストあり。\n- 追加した層: LogicLayer (dll)。ロジック役割。テストあり。\n' >> "$D/CLAUDE.md"
out="$(python3 "$SS" "$D" 2>&1)"
ok "note: 存在しない層の行は、無視する。テストのある層の「テストあり」は、食い違いではない" "$([ "$(has "$out" 'MISMATCH: CLAUDE.md の「追加した層')" = 0 ] && echo 1 || echo 0)"
ok "SKILL.md: テストを後付けしたとき、層の行の「テストなし」を「テストあり (<名前>Test)」に直す。層を足すとき、テストの有無を書く" "$(grep -q 'テストなし」を、`テストあり (<名前>Test)` に直す' "$SK" && grep -q 'テストの有無を、必ず書く' "$SK" && echo 1 || echo 0)"

# ---- 参照の生成 (v2.53.0)
AR="$ROOT/skills/add-project/scripts/add_reference.py"
ok "SKILL.md: 参照は、承認された分だけ add_reference.py で足す (手順 3 で案を示す、--dry-run、--include-only、断られたら回避しない)" "$(r=1; for k in 'add_reference.py' '参照の案 (使う側 → 新しい層)' '承認された参照だけ' '--include-only' '勝手に回避しない' 'MFC 拡張 DLL を、`UseOfMfc` のない使う側から参照する'; do grep -qF -- "$k" "$SK" || r=0; done; [ -f "$AR" ] || r=0; echo $r)"
ok "SKILL.md: 参照を足したあと、solution_state.py で SUGGEST_REF / REF_ISSUES が残らないことを確かめる" "$(grep -q 'SUGGEST_REF` と `REF_ISSUES` が、残っていないこと' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: 「案内だけ」の記述 (v2.52.0) が、残っていない" "$(! grep -q 'この版では、案内だけ' "$SK" && echo 1 || echo 0)"

# ---- SKILL.md と、既存の文書からの案内
ok "SKILL.md: name: add-project、スラッシュだけで起動 (disable-model-invocation)、配布先 (install.sh) は skills/*/ を全部コピーするので、追加の設定は要らない" "$([ "$(sed -n 2p "$SK")" = "name: add-project" ] && grep -q '^disable-model-invocation: true$' "$SK" && grep -q 'for d in "\$REPO"/skills/\*/' "$ROOT/install/install.sh" && echo 1 || echo 0)"
ok "SKILL.md: 現状を読む → 質問 → 案 (dry-run) → 承認で必ず止まる → 作る → 参照 → CLAUDE.md → 確かめる → 報告" "$(r=1; for k in '### 1. 現状を読む' '### 2. 何を足すかを決める' '### 3. 案を示して、承認を得る' '**承認が出るまで、何も作らない。**' '### 4. 作る' '### 5. 参照' '### 6. CLAUDE.md' '### 7. 確かめる' '### 8. 報告して、終わる'; do grep -qF -- "$k" "$SK" || r=0; done; echo $r)"
ok "SKILL.md: 既存のスクリプトを使う (add_layer.py / add_project.py / add_ui_host.py / new_solution.py)、手書きしない" "$(r=1; for k in add_layer.py add_project.py add_ui_host.py new_solution.py 'を、自分で手書きしない'; do grep -qF -- "$k" "$SK" || r=0; done; echo $r)"
ok "SKILL.md: 参照の向きを守る (下の層から上の層へは、参照しない)、既存のプロジェクトを無断で書き換えない" "$(grep -q '下の層は、上の層を参照しない' "$SK" && grep -q 'それ以外の既存のプロジェクトは、書き換えない' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: CLAUDE.md は決まった場所だけ書き換える (- 層: / 層の表または「追加した層」の行 / - テスト:)、書いてある層は消さない" "$(grep -q '書き換えるのは、次の場所だけ' "$SK" && grep -q '消さない・並べ替えない' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: 参照されていない層 (SUGGEST_REF) と MISMATCH / REF_ISSUES を、手順の中で使う。commit / push はユーザーの指示があるときだけ" "$(grep -q 'SUGGEST_REF' "$SK" && grep -q 'MISMATCH' "$SK" && grep -q 'REF_ISSUES' "$SK" && grep -q '`git commit` / `git push` は、ユーザーの指示があるときだけ' "$SK" && echo 1 || echo 0)"
ok "既存の文書から /add-project を案内 (DLL-LAYOUT.md / PROJECT-LAYOUT.md / new-solution の SKILL.md)" "$(grep -q '/add-project' "$ROOT/skills/cpp-test-first/DLL-LAYOUT.md" && grep -q '/add-project' "$ROOT/skills/csharp-test-first/PROJECT-LAYOUT.md" && grep -q '/add-project' "$ROOT/skills/new-solution/SKILL.md" && echo 1 || echo 0)"
ok "SKILL.md の呼ぶ solution_state.py と、ADDABLE の例が指すスクリプトが、実在する" "$([ -f "$SS" ] && [ -f "$AL" ] && [ -f "$AUH" ] && [ -f "$ROOT/skills/csharp-test-first/scripts/add_project.py" ] && [ -f "$NEW" ] && echo 1 || echo 0)"

# ---- 質問と ui-host の書き方 (v2.53.3。AP5・AR5 の発見)
ok "SKILL.md: 質問のツールは、選択肢が 2 つ以上のときだけ。自由入力はチャットの文章で聞く" "$(grep -q '質問のツールは、選択肢が 2 つ以上のときだけ使う' "$SK" && grep -q 'チャットの文章で聞く' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: C++ の役割の選択肢 (データ / ロジック / 画面 (UI) / その他)。画面 (UI) は ui-host へ" "$(grep -q '「データ」「ロジック」「画面 (UI)」「その他」' "$SK" && grep -q 'ui-host` の流れ' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: 「やめる」と「進める」を混ぜない" "$(grep -q '「やめる」と「進める」を混ぜない' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: 手順 3 の「変わるのは…だけ」に ui-host の例外 (Greeting.h/.cpp と TestGreeting.cpp) を書く" "$(grep -q 'ui-host` は、指定したロジック層に `Greeting.h`' "$SK" && grep -q 'TestGreeting.cpp' "$SK" && echo 1 || echo 0)"

# ---- 「- 層:」の「役割:名前」で、名前に役割の語がない層の役割を決める (v2.54.0。AR3 の発見)
D="$T/Role"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc-dialog --layers data --tests none >/dev/null 2>&1
python3 "$AL" "$D" ExtLayer --kind mfc-ext-dll --tests none >/dev/null 2>&1
out="$(python3 "$SS" "$D" 2>&1)"
ok "role: 名前に役割の語がない ExtLayer は、「- 層:」に書かれていないと other" "$(has "$out" 'PROJECT: ExtLayer | mfc-ext-dll | other |')"
msg_other="$(python3 "$AR" "$D" --from DataLayer --to ExtLayer --dry-run 2>&1)"
sed -i 's/^- 層: .*/- 層: data,logic:ExtLayer/' "$D/CLAUDE.md"
out="$(python3 "$SS" "$D" 2>&1)"
ok "role: 「- 層: data,logic:ExtLayer」と書くと、ExtLayer は logic、DataLayer は data" "$([ "$(has "$out" 'PROJECT: ExtLayer | mfc-ext-dll | logic |')" = 1 ] && [ "$(has "$out" 'PROJECT: DataLayer | dll | data |')" = 1 ] && echo 1 || echo 0)"
msg_logic="$(python3 "$AR" "$D" --from DataLayer --to ExtLayer --dry-run 2>&1)"
ok "role: add_reference.py の向きの検査も、明示した役割に従う (other のときは向きの違反が出ず、logic にすると、データ → ロジックの違反)" "$([ "$(has "$msg_other" '層の向きの違反')" = 0 ] && [ "$(has "$msg_logic" '層の向きの違反: DataLayer (data) は、上の層 ExtLayer (logic)')" = 1 ] && echo 1 || echo 0)"
MCK="$ROOT/skills/mfc-check/scripts/mfc_check.py"
mck="$(python3 -I - "$MCK" "$D" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("mck", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.claude_layer_roles(sys.argv[2]))
PYEOF
)"
ok "role: mfc_check.py も、「- 層:」の「役割:名前」を読む (logic = ExtLayer)" "$([ "$mck" = "(['ExtLayer'], [], [])" ] && echo 1 || echo 0)"
ok "SKILL.md: 名前に役割の語がない層も、選んだ役割で、「- 層:」に logic:名前 の形で書く。「なし」は置き換える" "$(grep -q '名前に役割の語' "$SK" && grep -q '`logic:ExtLayer` の形で書く' "$SK" && grep -q '`なし` を、足す層に置き換える' "$SK" && echo 1 || echo 0)"

# ---- 「その他」の層の使う側の既定はメイン、名前を囲んだ行の検出、SKILL の書き方 (v2.55.0。AP4・AR4 の発見)
D="$T/Other"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc-dialog --layers none --tests none >/dev/null 2>&1
python3 "$AL" "$D" ExtLayer --kind mfc-ext-dll --tests none >/dev/null 2>&1
out="$(python3 "$SS" "$D" 2>&1)"
ok "other: 役割が other の層 (ExtLayer) も、参照されていなければ、SUGGEST_REF (メイン -> ExtLayer)" "$(has "$out" 'SUGGEST_REF: Other -> ExtLayer')"
python3 "$AR" "$D" --from Other --to ExtLayer >/dev/null 2>&1
out="$(python3 "$SS" "$D" 2>&1)"
ok "other: メインから参照すると、SUGGEST_REF が消える" "$([ "$(lines "$out" '^SUGGEST_REF')" = 0 ] && echo 1 || echo 0)"
D="$T/Tick"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic --tests gtest --gtest vcpkg >/dev/null 2>&1
python3 "$AL" "$D" NoteData --tests none >/dev/null 2>&1
python3 "$AL" "$D" NoteData --tests-only >/dev/null 2>&1
printf -- '- 追加した層: `NoteData` (dll)。データ役割。テストなし。\n' >> "$D/CLAUDE.md"
out="$(python3 "$SS" "$D" 2>&1)"
ok "tick: 名前をバッククォートで囲んだ「追加した層」の行も、テストの食い違いを検出する" "$(has "$out" 'MISMATCH: CLAUDE.md の「追加した層: NoteData」が「テストなし」だが')"
ok "SKILL.md: 層を足すときの質問の順 (名前 → 役割 → 種類 → --uses → テスト → 使う側)。名前を聞かずに既定の名前で案を出さない" "$(grep -q '名前 → 役割 → 種類 → 参照する層' "$SK" && grep -q '名前を聞かずに、既定の名前で案を出さない' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: 「その他」の層の使う側の既定はメイン (「いまはどこからも参照しない」は、ユーザーが選んだときだけ)" "$(grep -q '使う側の既定は、メイン' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: 切り出し (名前空間の衝突の検出、範囲外の変更として案に書く、削除の前に diff、同一でなければ削除せず止まる)" "$(r=1; for k in '切り出し: アプリの中に' '範囲外の変更として、別に書く' '削除の前に、アプリ側のファイルが' '同一でないファイル' '削除せず、止まって'; do grep -qF -- "$k" "$SK" || r=0; done; echo $r)"
ok "SKILL.md: 「追加した層」の行の名前は、バッククォートで囲まない" "$(grep -qF '行の名前は、`` ` `` で囲まない' "$SK" && echo 1 || echo 0)"

# ---- 承認の取り違え、一部だけ同一、質問のツールの失敗、CLAUDE.md の範囲 (v2.55.1。CUT-A・CUT-B の発見)
ok "SKILL.md: 承認は、はっきりした肯定の返事だけ。ほかの質問への答えや、案への修正は、承認ではない" "$(grep -q '承認は、はっきりした肯定の返事' "$SK" && grep -q 'ほかの質問への答え' "$SK" && grep -q 'もう一度、承認を求める' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: 同一でないファイルが 1 つでもあれば、どのファイルも削除しない。編集を捨てて上書きする選択肢は出さない" "$(grep -q '1 つでもあれば、どのファイルも削除せず' "$SK" && grep -q '上書きする選択肢は、出さない' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: 質問のツールが失敗したときも、既定の名前で黙って進まず、チャットで名前を聞く" "$(grep -q '既定の名前で黙って進まず' "$SK" && echo 1 || echo 0)"
ok "SKILL.md: ViewModel の層を作ったとき、「アプリの構成」の行と「ViewModel 層を作っていない」の行も直す" "$(grep -q 'ViewModel の層を作ったとき' "$SK" && grep -q 'ViewModel 層を作っていないので' "$SK" && echo 1 || echo 0)"

ok "SKILL.md: 「移す」を選んだあと、層のサンプルのテストが失敗しうる。黙って直さず・弱めず、ユーザーに確認する" "$(grep -q '層の側に生成されたサンプルのテスト' "$SK" && grep -q 'テストを、黙って直さず、弱めない' "$SK" && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
