#!/usr/bin/env bash
# add_ui_host_test.sh - add_ui_host.py (画面を持つ MFC の DLL + 画面ホストの exe + UI テスト) の、生成物と、mfc-check との整合を検証する。
# Usage: tests/add_ui_host_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
# Windows / Visual Studio は不要 (生成した XML と、ソースの文字列を調べる。コンパイルと実行は、実機: docs/TEST-PLAN.md 2-29)。
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$ROOT/skills/new-solution/scripts/new_solution.py"
AUH="$ROOT/skills/cpp-test-first/scripts/add_ui_host.py"
MCK="$ROOT/skills/mfc-check/scripts/mfc_check.py"
T="${TMPDIR:-/tmp}/auh_$$"
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
xml_ok() { python3 -I - "$1" <<'PY'
import glob, sys, xml.dom.minidom as m
for f in glob.glob(sys.argv[1] + '/**/*.vcxproj', recursive=True) + glob.glob(sys.argv[1] + '/**/*.filters', recursive=True) + glob.glob(sys.argv[1] + '/*.slnx'):
    m.parse(f)
PY
}
snapshot() { (cd "$1" && find . -type f | sort | xargs md5sum | md5sum); }

# ---- 標準 DLL (既定): console のメイン + ロジック層 + データ層 + テスト
D="$T/StdChk"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic,data --tests gtest --gtest vcpkg >/dev/null 2>&1
before="$(snapshot "$D")"
out="$(python3 "$AUH" "$D" --dry-run 2>&1)"; rc=$?
ok "dry-run: rc=0、何も書かない" "$([ $rc = 0 ] && [ "$(snapshot "$D")" = "$before" ] && [ "$(has "$out" 'dry-run')" = 1 ] && echo 1 || echo 0)"
out="$(python3 "$AUH" "$D" 2>&1)"; rc=$?
ok "std: rc=0" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "std: ファイル一式 (UI DLL、ホスト、ロジックの画面モデル (ヘッダーだけ)、単体テスト、UI テスト)" "$(yes_if bash -c "cd '$D' && for f in UiLayer/GreetingDialog.h UiLayer/GreetingDialog.cpp UiLayer/UiLayer.rc UiLayer/Resource.h UiLayer/ShowGreeting.h UiLayer/UiLayer.cpp UiLayerHost/main.cpp UiLayerHost/UiLayerHost.vcxproj UiLayer/ScreenModelUi.h LogicLayer/Observable.h LogicLayer/ScreenModelSupport.h LogicLayer/GreetingScreenModelInterface.h LogicLayer/GreetingScreenModel.h LogicLayer/GreetingMessages.h LogicLayerTest/TestGreetingScreenModel.cpp UiLayerHost.UITests/GreetingDialogUiTests.cs UiLayerHost.UITests/UiTestBase.cs; do [ -f \$f ] || exit 1; done")"
ok "std: UI DLL は標準 DLL (_USRDLL、UseOfMfc、_AFXEXT なし、.rc、ロジックへの参照)" "$(yes_if bash -c "v='$D/UiLayer/UiLayer.vcxproj'; grep -q '_USRDLL' \$v && grep -q 'UseOfMfc' \$v && ! grep -q '_AFXEXT' \$v && grep -q 'ResourceCompile Include=\"UiLayer.rc\"' \$v && grep -q 'ProjectReference Include=\"..\\\\LogicLayer\\\\LogicLayer.vcxproj\"' \$v && grep -q 'AdditionalIncludeDirectories>\$(ProjectDir)..\\\\LogicLayer' \$v")"
ok "std: 公開関数 ShowGreetingDialog は、先頭の文が AFX_MANAGE_STATE" "$(yes_if python3 -I -c "
import re,sys
t=open('$D/UiLayer/GreetingDialog.cpp',encoding='utf-8-sig').read()
m=re.search(r'int ShowGreetingDialog\(HWND parent\)\s*\{(.*?)\}',t,re.S)
sys.exit(0 if m and re.match(r'\s*(//[^\n]*\n\s*)*AFX_MANAGE_STATE\(AfxGetStaticModuleState\(\)\);',m.group(1)) else 1)")"
ok "std: ホストは MFC なしの Win32 exe (UseOfMfc なし、UI DLL を参照、wWinMain)" "$(yes_if bash -c "v='$D/UiLayerHost/UiLayerHost.vcxproj'; ! grep -q 'UseOfMfc' \$v && grep -q 'ProjectReference Include=\"..\\\\UiLayer\\\\UiLayer.vcxproj\"' \$v && grep -q '<SubSystem>Windows' \$v && grep -q 'wWinMain' '$D/UiLayerHost/main.cpp' && ! grep -q 'afx' '$D/UiLayerHost/main.cpp'")"
ok "std: ロジック層と単体テストに、項目が足された (vcxproj と filters)" "$(yes_if bash -c "cd '$D' && for h in Observable.h ScreenModelSupport.h GreetingScreenModelInterface.h GreetingScreenModel.h GreetingMessages.h; do grep -q \"ClInclude Include=\\\"\$h\\\"\" LogicLayer/LogicLayer.vcxproj && grep -q \"\$h\" LogicLayer/LogicLayer.vcxproj.filters || exit 1; done && grep -q 'ClCompile Include=\"TestGreetingScreenModel.cpp\"' LogicLayerTest/LogicLayerTest.vcxproj && grep -q 'TestGreetingScreenModel.cpp' LogicLayerTest/LogicLayerTest.vcxproj.filters")"
ok "std: 画面モデルは画面に依存しない (MFC の型・afx・HWND・リソース ID を使わない。コメントを除く)" "$(yes_if bash -c "! cat '$D'/LogicLayer/*.h | grep -v '^ *//' | grep -q 'afx\|CString\|CWnd\|HWND\|IDC_\|IDD_'")"
ok "std: 単体テストの期待値と、画面の文が一致 (空: 名前を入力してください / 名前あり: こんにちは、太郎 さん)" "$(yes_if bash -c "grep -q '名前を入力してください' '$D/LogicLayerTest/TestGreetingScreenModel.cpp' '$D/LogicLayer/GreetingMessages.h' '$D/UiLayerHost.UITests/GreetingDialogUiTests.cs' && grep -q 'こんにちは、太郎 さん' '$D/LogicLayerTest/TestGreetingScreenModel.cpp' '$D/UiLayerHost.UITests/GreetingDialogUiTests.cs'")"
ok "std: UI テストの部品 ID が、Resource.h と一致 (3002 / 3003 / 3004)" "$(yes_if bash -c "grep -q 'IDC_GREETING_NAME_EDIT *3002' '$D/UiLayer/Resource.h' && grep -q 'IDC_GREETING_TEXT *3003' '$D/UiLayer/Resource.h' && grep -q 'IDC_GREETING_CLEAR_BUTTON *3004' '$D/UiLayer/Resource.h' && grep -q '\"3002\"' '$D/UiLayerHost.UITests/GreetingDialogUiTests.cs' && grep -q '\"3003\"' '$D/UiLayerHost.UITests/GreetingDialogUiTests.cs' && grep -q '\"3004\"' '$D/UiLayerHost.UITests/GreetingDialogUiTests.cs'")"
ok "std: ダイアログは、画面モデルのインターフェースを受け取り、OnInitDialog で AddHandler、OnDestroy で RemoveHandler、境界の変換は ToWString / ToCString" "$(yes_if bash -c "c='$D/UiLayer/GreetingDialog.cpp'; h='$D/UiLayer/GreetingDialog.h'; grep -q 'GreetingScreenModelInterface& model' \$h && grep -q 'AddHandler' \$c && grep -q 'RemoveHandler' \$c && grep -q 'ON_WM_DESTROY' \$c && grep -q 'ToWString' \$c && grep -q 'ToCString' \$c && grep -q 'IDC_GREETING_ERROR_TEXT' \$c && ! grep -q 'MakeGreeting' \$c")"
ok "std: ScreenModelUi.h の ToCString / ToWString (CString の揺らぎを、境界で吸収)、ShowGreetingDialog が画面モデルを作る" "$(yes_if bash -c "grep -q 'inline CString ToCString' '$D/UiLayer/ScreenModelUi.h' && grep -q 'inline std::wstring ToWString' '$D/UiLayer/ScreenModelUi.h' && grep -q 'GreetingScreenModel model;' '$D/UiLayer/GreetingDialog.cpp'")"
ok "std: 共通ヘッダー Observable.h / ScreenModelSupport.h は、Skill の実物のコピー (BOM と CRLF を除いて同じ)" "$(yes_if python3 -I -c "
import sys
for f in ('Observable.h','ScreenModelSupport.h'):
    a=open('$D/LogicLayer/'+f,encoding='utf-8-sig',newline='').read().replace('\r\n','\n')
    b=open('$ROOT/skills/cpp-test-first/assets/'+f,encoding='utf-8').read()
    sys.exit(0 if True else 1) if a==b else sys.exit(1)
")"
ok "std: 画面モデルの単体テスト (8 件) と、ValidationError の properties / 通知 (All) を確かめる" "$(yes_if bash -c "t='$D/LogicLayerTest/TestGreetingScreenModel.cpp'; [ \"\$(grep -c '^TEST(' \$t)\" = 8 ] && grep -q 'GreetingProperty::All' \$t && grep -q 'RemoveHandler' \$t")"
ok "std: UI テストは、画面ホストを起動する (AppName)" "$(yes_if bash -c "grep -q 'AppName => \"UiLayerHost\"' '$D/UiLayerHost.UITests/UiTestBase.cs'")"
ok "std: .slnx に、UI DLL・ホスト・UI テストが登録された" "$(yes_if bash -c "grep -q 'UiLayer/UiLayer.vcxproj' '$D/UiHostChk.slnx' 2>/dev/null || grep -q 'UiLayer/UiLayer.vcxproj' '$D'/*.slnx; grep -q 'UiLayerHost/UiLayerHost.vcxproj' '$D'/*.slnx && grep -q 'UiLayerHost.UITests' '$D'/*.slnx")"
ok "std: XML として読める (slnx / vcxproj / filters)" "$(yes_if xml_ok "$D")"
ok "std: CLAUDE.md に、UI DLL と画面ホストの節" "$(yes_if bash -c "grep -q '画面を持つ DLL (UI DLL)' '$D/CLAUDE.md' && grep -q 'AFX_MANAGE_STATE' '$D/CLAUDE.md'")"
ok "std: C++ は BOM 付き + CRLF、.rc は ASCII (BOM なし) + CRLF" "$(yes_if bash -c "[ \"\$(head -c3 '$D/UiLayer/GreetingDialog.cpp' | xxd -p)\" = efbbbf ] && grep -q \$'\\r' '$D/UiLayer/GreetingDialog.cpp' && [ \"\$(head -c3 '$D/UiLayer/UiLayer.rc' | xxd -p)\" != efbbbf ] && grep -q \$'\\r' '$D/UiLayer/UiLayer.rc' && ! grep -qP '[^\\x00-\\x7F]' '$D/UiLayer/UiLayer.rc'")"
out="$(python3 -I "$MCK" "$D" --all 2>&1)"; rc=$?
ok "std: mfc-check は、error 0 / warning 0 (画面を持つ層で LAY001 を出さない。DLL007 も出ない)" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 / warning 0')" = 1 ] && echo 1 || echo 0)"
before="$(snapshot "$D")"
python3 "$AUH" "$D" >/dev/null 2>&1; rc=$?
ok "std: 2 回目は、rc=3 で、何も変えない" "$([ $rc = 3 ] && [ "$(snapshot "$D")" = "$before" ] && echo 1 || echo 0)"

# ---- 拡張 DLL: MFC ダイアログベースのメイン
D="$T/ExtChk"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc-dialog --layers logic,data --tests gtest --gtest vcpkg >/dev/null 2>&1
python3 "$AUH" "$D" --name DialogLayer --kind mfc-ext-dll >/dev/null 2>&1; rc=$?
ok "ext: rc=0" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "ext: UI DLL は拡張 DLL (_AFXEXT、UseOfMfc、_USRDLL なし。dllmain.cpp。ShowGreeting.h なし)" "$(yes_if bash -c "v='$D/DialogLayer/DialogLayer.vcxproj'; grep -q '_AFXEXT' \$v && grep -q 'UseOfMfc' \$v && ! grep -q '_USRDLL' \$v && [ -f '$D/DialogLayer/dllmain.cpp' ] && [ ! -f '$D/DialogLayer/ShowGreeting.h' ]")"
ok "ext: ダイアログのクラスは AFX_EXT_CLASS" "$(yes_if bash -c "grep -q 'class AFX_EXT_CLASS GreetingDialog' '$D/DialogLayer/GreetingDialog.h'")"
ok "ext: ホストは MFC の exe (UseOfMfc=Dynamic、拡張 DLL を参照、GreetingDialog を開く)" "$(yes_if bash -c "v='$D/DialogLayerHost/DialogLayerHost.vcxproj'; grep -q 'UseOfMfc>Dynamic' \$v && grep -q 'ProjectReference Include=\"..\\\\DialogLayer\\\\DialogLayer.vcxproj\"' \$v && grep -q 'GreetingDialog dialog' '$D/DialogLayerHost/HostApp.cpp' && grep -q 'EnableDpiAwareness' \$v")"
out="$(python3 -I "$MCK" "$D" --all 2>&1)"; rc=$?
ok "ext: mfc-check は、error 0 / warning 0 (DLL005 / DLL008 も出ない)" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 / warning 0')" = 1 ] && echo 1 || echo 0)"
ok "ext: XML として読める" "$(yes_if xml_ok "$D")"

# ---- ロジック層がない / --logic none
D="$T/NoLogic"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers none --tests none >/dev/null 2>&1
out="$(python3 "$AUH" "$D" --no-ui-tests 2>&1)"; rc=$?
ok "ロジック層なし: rc=0、NOTE (画面モデルは UI DLL に置いた)、Greeting.h なし、画面モデルのヘッダーは UI DLL にある" "$([ $rc = 0 ] && [ "$(has "$out" 'ロジック層がないので')" = 1 ] && [ ! -e "$D/UiLayer/Greeting.h" ] && [ -f "$D/UiLayer/GreetingScreenModel.h" ] && [ -f "$D/UiLayer/Observable.h" ] && grep -q 'ClInclude Include="GreetingScreenModel.h"' "$D/UiLayer/UiLayer.vcxproj" && grep -q 'GreetingScreenModelInterface& model' "$D/UiLayer/GreetingDialog.h" && echo 1 || echo 0)"
ok "ロジック層なし: メインの名前に Logic を含んでも、メイン (exe) は、ロジック層として使わない" "$(yes_if bash -c "! grep -q 'ProjectReference Include=\"..\\\\NoLogic' '$D/UiLayer/UiLayer.vcxproj'")"
ok "ロジック層なし: UI テストは、--no-ui-tests で作らない" "$([ ! -d "$D/UiLayerHost.UITests" ] && echo 1 || echo 0)"
D="$T/LogicNone"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic --tests none >/dev/null 2>&1
python3 "$AUH" "$D" --logic none --no-ui-tests >/dev/null 2>&1
ok "--logic none: ロジック層があっても、画面モデルを足さない (UI DLL に置く)" "$([ ! -e "$D/LogicLayer/GreetingScreenModel.h" ] && ! grep -q 'Greeting' "$D/LogicLayer/LogicLayer.vcxproj" && [ -f "$D/UiLayer/GreetingScreenModel.h" ] && echo 1 || echo 0)"

# ---- ロジック層が MFC 標準 DLL
D="$T/LogicStd"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc-dialog --layers logic --layer-kind mfc-std-dll --tests gtest --gtest vcpkg >/dev/null 2>&1
python3 "$AUH" "$D" --no-ui-tests >/dev/null 2>&1; rc=$?
ok "ロジックが標準 DLL: rc=0。画面モデルは、ヘッダーだけ (.cpp を足さない。DLL の境界に、関数を出さない)" "$([ $rc = 0 ] && [ -f "$D/LogicLayer/GreetingScreenModel.h" ] && [ ! -e "$D/LogicLayer/Greeting.cpp" ] && ! grep -q 'Greeting.*\.cpp' "$D/LogicLayer/LogicLayer.vcxproj" && echo 1 || echo 0)"
out="$(python3 -I "$MCK" "$D" --all 2>&1)"; rc=$?
ok "ロジックが標準 DLL: mfc-check は、error 0 / warning 0 (画面モデルを足しても、DLL の指摘が出ない)" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 / warning 0')" = 1 ] && echo 1 || echo 0)"

# ---- 名前に Ui / View / Dialog を含まない UI DLL: mfc-check の LAY001 と、--ui
D="$T/PanelChk"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers none --tests none >/dev/null 2>&1
out="$(python3 "$AUH" "$D" --name PanelLayer --no-ui-tests 2>&1)"
ok "名前に Ui / View / Dialog がない: NOTE が出る" "$(has "$out" 'Ui / View / Dialog の語がない')"
out="$(python3 -I "$MCK" "$D" --all 2>&1)"; rc=$?
ok "名前に Ui / View / Dialog がない: mfc-check は LAY001 (error) を出す" "$([ $rc = 1 ] && [ "$(has "$out" 'LAY001')" = 1 ] && echo 1 || echo 0)"
out="$(python3 -I "$MCK" "$D" --all --ui PanelLayer 2>&1)"; rc=$?
ok "--ui PanelLayer を渡すと、LAY001 は出ない" "$([ $rc = 0 ] && [ "$(has "$out" 'LAY001')" = 0 ] && echo 1 || echo 0)"

# ---- ViewModel を含む名前は、画面を持つ層の名前としない (v2.53.4)
D="$T/VmChk"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers none --tests none >/dev/null 2>&1
out="$(python3 "$AUH" "$D" --name ReportViewModel --no-ui-tests --dry-run 2>&1)"
ok "名前に ViewModel を含む: 画面を持つ層の名前としない (NOTE が出る)" "$(has "$out" 'Ui / View / Dialog の語がない')"

# ---- 不正な引数
out="$(python3 "$AUH" "$T/PanelChk" --name 'Bad-Name' 2>&1)"; rc=$?
ok "不正な名前: rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
out="$(python3 "$AUH" "$T/PanelChk" --name FooTest 2>&1)"; rc=$?
ok "Test で終わる名前: rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
mkdir -p "$T/empty"
out="$(python3 "$AUH" "$T/empty" 2>&1)"; rc=$?
ok "ソリューションがないフォルダ: rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
