#!/usr/bin/env bash
# ui_tests_gen_test.sh - add_ui_tests.py と、new_solution.py --ui-tests flaui を検証する (Windows も .NET も不要)。
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
UI="$ROOT/skills/new-solution/scripts/add_ui_tests.py"
WC="$ROOT/skills/wpf-check/scripts/wpf_check.py"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
b() { [ "$1" = 0 ] && echo 1 || echo 0; }   # rc=0 なら 1

# --- WPF: 作成と同時に
python3 -I "$NS" "$T/WpfUi" --type wpf --layers data,logic,viewmodel --tests mstest --ui-tests flaui >"$T/o1" 2>&1; rc=$?
ok "WPF: new-solution --ui-tests flaui succeeds" "$(b $rc)"
for f in WpfUi.UITests.csproj UiTestBase.cs AppLocator.cs Screenshots.cs UiNative.cs MainWindowUiTests.cs; do
    ok "WPF: WpfUi.UITests/$f exists" "$([ -f "$T/WpfUi/WpfUi.UITests/$f" ] && echo 1 || echo 0)"
done
ok "WPF: slnx has the UITests project" "$(grep -q 'WpfUi.UITests/WpfUi.UITests.csproj' "$T/WpfUi/WpfUi.slnx" && echo 1 || echo 0)"
ok "WPF: csproj references FlaUI 5.0.0 + MSTest, net10.0-windows" "$(grep -q 'FlaUI.UIA3" Version="5.0.0"' "$T/WpfUi/WpfUi.UITests/WpfUi.UITests.csproj" && grep -q 'MSTest.TestFramework' "$T/WpfUi/WpfUi.UITests/WpfUi.UITests.csproj" && grep -q '<TargetFramework>net10.0-windows</TargetFramework>' "$T/WpfUi/WpfUi.UITests/WpfUi.UITests.csproj" && echo 1 || echo 0)"
ok "WPF: standard View -> sample tests use AutomationId (NameTextBox / GreetingText / ClearButton)" "$(grep -q 'Find("NameTextBox")' "$T/WpfUi/WpfUi.UITests/MainWindowUiTests.cs" && grep -q 'ClearButton' "$T/WpfUi/WpfUi.UITests/MainWindowUiTests.cs" && echo 1 || echo 0)"
ok "WPF: generated View has AutomationIds" "$(grep -q 'AutomationId="NameTextBox"' "$T/WpfUi/WpfUi/Views/MainWindow.xaml" && grep -q 'AutomationId="GreetingText"' "$T/WpfUi/WpfUi/Views/MainWindow.xaml" && grep -q 'AutomationId="ClearButton"' "$T/WpfUi/WpfUi/Views/MainWindow.xaml" && echo 1 || echo 0)"
ok "WPF: no leftover placeholders (__X__) in generated files" "$(grep -rq '__[A-Z]*__' "$T/WpfUi/WpfUi.UITests" && echo 0 || echo 1)"
ok "WPF: files are UTF-8 BOM + CRLF" "$(head -c 3 "$T/WpfUi/WpfUi.UITests/UiTestBase.cs" | od -An -tx1 | tr -d ' \n' | grep -q '^efbbbf' && grep -q $'\r' "$T/WpfUi/WpfUi.UITests/UiTestBase.cs" && echo 1 || echo 0)"
ok "WPF: CLAUDE.md has the UI test section" "$(grep -q '## UI テスト (FlaUI)' "$T/WpfUi/CLAUDE.md" && echo 1 || echo 0)"
ok "WPF: CLAUDE.md tells to run uitest_once.sh after Green (imperative)" "$(grep -q 'uitest_once.sh "$PWD" 900' "$T/WpfUi/CLAUDE.md" && grep -q 'UI テストファースト' "$T/WpfUi/CLAUDE.md" && echo 1 || echo 0)"
# --refresh-claude-md: 古い節 (流れの指示がない) を、最新にする。後ろの節は、残る
python3 - "$T/WpfUi/CLAUDE.md" <<'PY'
import sys,re
p=sys.argv[1]; t=open(p,encoding="utf-8").read()
i=t.index("## UI テスト (FlaUI)")
t=t[:i]+"## UI テスト (FlaUI)\n- 古い説明\n\n## 後ろの節\n- 残る\n"
open(p,"w",encoding="utf-8").write(t)
PY
python3 -I "$UI" "$T/WpfUi" --refresh-claude-md >"$T/o6" 2>&1; rc=$?
ok "refresh-claude-md: old section replaced, following section kept, only one UI section" "$([ $rc = 0 ] && ! grep -q '古い説明' "$T/WpfUi/CLAUDE.md" && grep -q 'uitest_once.sh "$PWD" 900' "$T/WpfUi/CLAUDE.md" && grep -q '## 後ろの節' "$T/WpfUi/CLAUDE.md" && [ "$(grep -c '## UI テスト (FlaUI)' "$T/WpfUi/CLAUDE.md")" = 1 ] && echo 1 || echo 0)"
out="$(python3 -I "$WC" "$T/WpfUi" --all)"; rc=$?
ok "WPF: wpf-check finds nothing (UI002 satisfied by the standard View)" "$([ $rc = 0 ] && grep -qF 'error 0 / warning 0 / info 0' <<<"$out" && echo 1 || echo 0)"

# --- 目で確かめる (スローモーション) とトレース
ok "visible mode: UiTestBase reads UITEST_SLOWMO_MS, writes the trace, brings the window to front" "$(grep -q 'UITEST_SLOWMO_MS' "$T/WpfUi/WpfUi.UITests/UiTestBase.cs" && grep -q 'UiTrace.Write' "$T/WpfUi/WpfUi.UITests/UiTestBase.cs" && grep -q 'BringToFront' "$T/WpfUi/WpfUi.UITests/UiTestBase.cs" && grep -q 'ui-trace.txt' "$T/WpfUi/WpfUi.UITests/UiNative.cs" && echo 1 || echo 0)"
ok "Screenshots falls back to a screen capture on the user's desktop when PrintWindow is blank" "$(grep -q 'IsBlank' "$T/WpfUi/WpfUi.UITests/Screenshots.cs" && grep -q 'Capture.Element' "$T/WpfUi/WpfUi.UITests/Screenshots.cs" && echo 1 || echo 0)"
# --refresh-support-files: ツールが持つファイルだけを最新にし、テストの本体は触らない
echo '// old' > "$T/WpfUi/WpfUi.UITests/UiTestBase.cs"; rm -f "$T/WpfUi/WpfUi.UITests/UiNative.cs"
echo '// my test' > "$T/WpfUi/WpfUi.UITests/MainWindowUiTests.cs"
python3 -I "$UI" "$T/WpfUi" --refresh-support-files >"$T/o7" 2>&1; rc=$?
ok "refresh-support-files: support files regenerated, the test body untouched" "$([ $rc = 0 ] && grep -q 'UITEST_SLOWMO_MS' "$T/WpfUi/WpfUi.UITests/UiTestBase.cs" && [ -f "$T/WpfUi/WpfUi.UITests/UiNative.cs" ] && [ "$(cat "$T/WpfUi/WpfUi.UITests/MainWindowUiTests.cs")" = '// my test' ] && echo 1 || echo 0)"

# --- 二重実行は、何も書かない (rc=3)
python3 -I "$UI" "$T/WpfUi" >/dev/null 2>&1; rc=$?
ok "WPF: running again refuses (rc=3, nothing overwritten)" "$([ $rc = 3 ] && echo 1 || echo 0)"

# --- WPF: 後付け (--ui-tests flaui だけ)
python3 -I "$NS" "$T/WpfLate" --type wpf --layers logic,viewmodel --tests none >/dev/null 2>&1
python3 -I "$NS" "$T/WpfLate" --ui-tests flaui >"$T/o2" 2>&1; rc=$?
ok "WPF: retrofit (--ui-tests flaui only) succeeds" "$(b $rc)"
ok "WPF: retrofit created WpfLate.UITests" "$([ -f "$T/WpfLate/WpfLate.UITests/WpfLate.UITests.csproj" ] && echo 1 || echo 0)"

# --- dry-run は、何も書かない
python3 -I "$NS" "$T/WpfDry" --type wpf --layers none --tests none --ui-tests flaui --dry-run >"$T/o3" 2>&1; rc=$?
ok "dry-run for a new solution writes nothing" "$([ $rc = 0 ] && [ ! -e "$T/WpfDry" ] && grep -q 'UITests' "$T/o3" && echo 1 || echo 0)"

# --- AutomationId のない View (標準でない) -> 一般のひな形 + NOTE
mkdir -p "$T/Plain"; python3 -I "$NS" "$T/Plain" --type wpf --layers logic --tests none >/dev/null 2>&1
sed -i 's/ AutomationProperties.AutomationId="[A-Za-z]*"//' "$T/Plain/Plain/Views/MainWindow.xaml" 2>/dev/null
python3 -I "$UI" "$T/Plain" >"$T/o4" 2>&1; rc=$?
ok "non-standard View: generic sample (window opens only) and a NOTE about AutomationId" "$([ $rc = 0 ] && ! grep -q 'Find("NameTextBox")' "$T/Plain/Plain.UITests/MainWindowUiTests.cs" && grep -q 'NOTE: View に' "$T/o4" && echo 1 || echo 0)"
out="$(python3 -I "$WC" "$T/Plain" --all)"
ok "non-standard View: wpf-check UI002 warns about the controls (UITests project exists)" "$(grep -qF 'UI002' <<<"$out" && echo 1 || echo 0)"

# --- MFC (C++): 混在になる
python3 -I "$NS" "$T/MfcDlg" --type mfc-dialog --layers none --tests none --ui-tests flaui >"$T/o5" 2>&1; rc=$?
ok "MFC: new-solution --ui-tests flaui succeeds" "$(b $rc)"
ok "MFC: UITests project added to the slnx (mixed C++ + .NET)" "$(grep -q 'MfcDlg.vcxproj' "$T/MfcDlg/MfcDlg.slnx" && grep -q 'MfcDlg.UITests/MfcDlg.UITests.csproj' "$T/MfcDlg/MfcDlg.slnx" && echo 1 || echo 0)"
ok "MFC: generic sample (window opens only)" "$(grep -q 'MainWindow_Opens_WithTitle' "$T/MfcDlg/MfcDlg.UITests/MainWindowUiTests.cs" && ! grep -q 'NameTextBox' "$T/MfcDlg/MfcDlg.UITests/MainWindowUiTests.cs" && echo 1 || echo 0)"
ok "MFC: NOTE about the mixed solution" "$(grep -q '混在' "$T/o5" && echo 1 || echo 0)"

# --- 異常系
python3 -I "$UI" "$T/Plain" --app NoSuchApp >/dev/null 2>&1; rc=$?
ok "unknown --app is rejected" "$([ $rc != 0 ] && echo 1 || echo 0)"
python3 -I "$UI" "/no/such/dir" >/dev/null 2>&1; rc=$?
ok "missing folder is rejected" "$([ $rc != 0 ] && echo 1 || echo 0)"


# --- UiDialogs.cs (ダイアログ・メニュー・コンボなどの、操作の道具): 3 つのフレームワークで、同じファイルが作られる
D="$T/WpfUi/WpfUi.UITests/UiDialogs.cs"
ok "UiDialogs.cs exists in WPF UITests (and is listed in the add_ui_tests output)" "$([ -f "$D" ] && grep -q 'UiDialogs.cs' "$T/o1" && echo 1 || echo 0)"
ok "UiDialogs: key API present (Click / WaitModal / ExpandMenu / MenuCommand / SelectComboItem / SelectListItem / SetSlider / SetScrollBar / SelectTab / PressDialogButton / AnswerMessageBox / PickFile / FindWindow / DumpTree)" "$(ok_all=1; for m in 'string Click(' 'Window? WaitModal(' 'void ExpandMenu(' 'void MenuCommand(' 'string SelectComboItem(' 'string SelectListItem(' 'string SetSlider(' 'string SetScrollBar(' 'void SelectTab(' 'string PressDialogButton(' 'string AnswerMessageBox(' 'string PickFile(' 'Window? FindWindow(' 'string DumpTree('; do grep -qF "$m" "$D" || ok_all=0; done; echo $ok_all)"
ok "UiDialogs: switches by FrameworkId / window handle (WPF / WinForm / Win32)" "$(grep -q 'FrameworkId' "$D" && grep -q 'BM_CLICK' "$D" && grep -q 'CB_SETCURSEL' "$D" && grep -q 'WM_COMMAND' "$D" && echo 1 || echo 0)"
ok "UiDialogs: WPF menu on a separate desktop gives an actionable failure (run_watcher_visible.cmd)" "$(grep -q 'run_watcher_visible.cmd' "$D" && echo 1 || echo 0)"
ok "UiDialogs: braces are balanced" "$(python3 - "$D" <<'PY'
import sys
t=open(sys.argv[1],encoding='utf-8-sig').read()
print(1 if t.count('{')==t.count('}') and t.count('(')==t.count(')') else 0)
PY
)"
ok "UiDialogs: UTF-8 BOM + CRLF, namespace filled" "$(head -c 3 "$D" | od -An -tx1 | tr -d ' \n' | grep -q '^efbbbf' && grep -q $'\r' "$D" && grep -q 'namespace WpfUi.UITests;' "$D" && echo 1 || echo 0)"
ok "UiTestBase: OpenModal / WaitWindow wrappers" "$(grep -q 'Window OpenModal(' "$T/WpfUi/WpfUi.UITests/UiTestBase.cs" && grep -q 'WaitWindow(string title)' "$T/WpfUi/WpfUi.UITests/UiTestBase.cs" && echo 1 || echo 0)"
ok "CLAUDE.md: tells to use UiDialogs and the pure-function + smoke-test split" "$(grep -q 'UiDialogs' "$T/WpfUi/CLAUDE.md" && grep -q '煙テスト' "$T/WpfUi/CLAUDE.md" && grep -q 'run_watcher_visible.cmd' "$T/WpfUi/CLAUDE.md" && echo 1 || echo 0)"
# refresh-support-files は、UiDialogs.cs も、作り直す (古いプロジェクトへ、後から、足せる)
rm -f "$D"
python3 -I "$UI" "$T/WpfUi" --refresh-support-files >"$T/o8" 2>&1; rc=$?
ok "refresh-support-files: UiDialogs.cs is (re)created" "$([ $rc = 0 ] && [ -f "$D" ] && echo 1 || echo 0)"
# WinForms / MFC (C++) でも、同じファイル
python3 -I "$NS" "$T/WfUi" --type winforms --layers logic --tests mstest --ui-tests flaui >/dev/null 2>&1
ok "WinForms: UiDialogs.cs generated" "$([ -f "$T/WfUi/WfUi.UITests/UiDialogs.cs" ] && echo 1 || echo 0)"
python3 -I "$NS" "$T/MfcUi" --type mfc-dialog --layers logic --tests none --ui-tests flaui >/dev/null 2>&1
ok "MFC (C++): UiDialogs.cs generated" "$([ -f "$T/MfcUi/MfcUi.UITests/UiDialogs.cs" ] && echo 1 || echo 0)"

# uitest.settings: UI テストの既定 (ウォッチャーが読む)。WPF は visible (WPF のメニューは別のデスクトップで開かない)、それ以外は separate
sv() { sed 's/\r$//; s/^\xEF\xBB\xBF//; s/#.*$//' "$1" | grep -E '^[[:space:]]*desktop[[:space:]]*=' | tr -d ' \n'; }
ok "uitest.settings: WPF -> desktop=visible" "$([ "$(sv "$T/WpfUi/WpfUi.UITests/uitest.settings")" = 'desktop=visible' ] && echo 1 || echo 0)"
ok "uitest.settings: WinForms -> desktop=separate" "$([ "$(sv "$T/WfUi/WfUi.UITests/uitest.settings")" = 'desktop=separate' ] && echo 1 || echo 0)"
ok "uitest.settings: MFC (C++) -> desktop=separate" "$([ "$(sv "$T/MfcUi/MfcUi.UITests/uitest.settings")" = 'desktop=separate' ] && echo 1 || echo 0)"
ok "uitest.settings: has slowmo=0 and explains the options (comments)" "$(grep -q '^slowmo=0' "$T/WpfUi/WpfUi.UITests/uitest.settings" && grep -q 'uitest_once.sh --visible' "$T/WfUi/WfUi.UITests/uitest.settings" && echo 1 || echo 0)"
# refresh-support-files: 既存の設定 (利用者の選択) は、上書きしない。なければ、足す
printf 'desktop=separate\n' > "$T/WpfUi/WpfUi.UITests/uitest.settings"
python3 -I "$UI" "$T/WpfUi" --refresh-support-files >/dev/null 2>&1
ok "refresh-support-files: an existing uitest.settings is kept" "$([ "$(sv "$T/WpfUi/WpfUi.UITests/uitest.settings")" = 'desktop=separate' ] && echo 1 || echo 0)"
rm -f "$T/WpfUi/WpfUi.UITests/uitest.settings"
python3 -I "$UI" "$T/WpfUi" --refresh-support-files >/dev/null 2>&1
ok "refresh-support-files: a missing uitest.settings is added (WPF: visible)" "$([ "$(sv "$T/WpfUi/WpfUi.UITests/uitest.settings")" = 'desktop=visible' ] && echo 1 || echo 0)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
