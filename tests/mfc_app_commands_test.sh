#!/usr/bin/env bash
# mfc_app_commands_test.sh - SDI のひな形 (`--type mfc`) の SampleApp が、ID_FILE_NEW / ID_FILE_OPEN を、自分のメッセージマップに結びつける (v2.100.1)。
# 結びつけがないと、「開く」「新規作成」のメニュー項目を足したとき、常にグレーアウトする (CWinApp は、この 2 つの ID を割り当てない。TN022。MDI のひな形は、ID_FILE_NEW を、すでに結びつけている)。
# ダイアログ ベースは、ドキュメントを持たないので、メッセージマップを持たない (DECLARE だけ足すと、BEGIN がなく、リンクエラー = MAP004)。
# Usage: tests/mfc_app_commands_test.sh      終了コード: 0 すべて OK / 1 失敗あり
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$ROOT/skills"
W="$(mktemp -d "${TMPDIR:-/tmp}/mfcapp.XXXXXX")"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }

for ty in mfc mfc-mdi mfc-dialog; do
  n="app_${ty//-/_}"
  python3 "$SK/new-solution/scripts/new_solution.py" "$W/$n" --type "$ty" --layers none --tests none >/dev/null 2>&1
done
H() { echo "$W/$1/$1/SampleApp.h"; }
C() { echo "$W/$1/$1/SampleApp.cpp"; }

# SDI: ID_FILE_NEW と ID_FILE_OPEN を、SampleApp のメッセージマップで結びつける
ok "SDI: SampleApp.h declares the message map" "$(grep -q 'DECLARE_MESSAGE_MAP()' "$(H app_mfc)" && echo 1 || echo 0)"
ok "SDI: SampleApp.cpp has BEGIN_MESSAGE_MAP(SampleApp, CWinAppEx) ... END_MESSAGE_MAP()" "$(grep -q 'BEGIN_MESSAGE_MAP(SampleApp, CWinAppEx)' "$(C app_mfc)" && grep -q 'END_MESSAGE_MAP()' "$(C app_mfc)" && echo 1 || echo 0)"
ok "SDI: ON_COMMAND(ID_FILE_NEW, &CWinAppEx::OnFileNew) and ON_COMMAND(ID_FILE_OPEN, &CWinAppEx::OnFileOpen) are in the map" "$(grep -q 'ON_COMMAND(ID_FILE_NEW, &CWinAppEx::OnFileNew)' "$(C app_mfc)" && grep -q 'ON_COMMAND(ID_FILE_OPEN, &CWinAppEx::OnFileOpen)' "$(C app_mfc)" && echo 1 || echo 0)"
ok "SDI: the comment explains why (CWinApp does not assign these IDs; the menu item stays grayed out; TN022)" "$(grep -q 'TN022' "$(C app_mfc)" && grep -q 'グレーアウト' "$(C app_mfc)" && echo 1 || echo 0)"
ok "SDI: the map is placed before InitInstance (same order as the wizard)" "$(python3 - "$(C app_mfc)" <<'PYEOF' && echo 1 || echo 0
import sys,re
t=open(sys.argv[1],encoding='utf-8-sig').read()
b=t.index('BEGIN_MESSAGE_MAP'); c=t.index('BOOL SampleApp::InitInstance')
sys.exit(0 if b<c else 1)
PYEOF
)"

# MDI: 変えない (ID_FILE_NEW は、すでにある)
ok "MDI: ID_FILE_NEW is still tied (unchanged)" "$(grep -q 'ON_COMMAND(ID_FILE_NEW, &CWinApp::OnFileNew)' "$(C app_mfc_mdi)" && grep -q 'DECLARE_MESSAGE_MAP()' "$(H app_mfc_mdi)" && echo 1 || echo 0)"

# ダイアログ ベース: メッセージマップを持たない。DECLARE と BEGIN の数が、合っている (0 と 0)
d_decl=$(grep -c 'DECLARE_MESSAGE_MAP' "$(H app_mfc_dialog)"); d_begin=$(grep -c 'BEGIN_MESSAGE_MAP(SampleApp' "$(C app_mfc_dialog)")
ok "dialog-based: SampleApp has no message map (DECLARE $d_decl / BEGIN $d_begin): it has no document, so no File menu commands" "$([ "$d_decl" = 0 ] && [ "$d_begin" = 0 ] && echo 1 || echo 0)"

# どの種類でも、DECLARE_MESSAGE_MAP と BEGIN_MESSAGE_MAP は、対応している (SampleApp)
for ty in mfc mfc-mdi mfc-dialog; do
  n="app_${ty//-/_}"
  d=$(grep -c 'DECLARE_MESSAGE_MAP' "$(H $n)"); b=$(grep -c 'BEGIN_MESSAGE_MAP(SampleApp' "$(C $n)")
  ok "$ty: SampleApp DECLARE_MESSAGE_MAP ($d) and BEGIN_MESSAGE_MAP ($b) match" "$([ "$d" = "$b" ] && echo 1 || echo 0)"
done

# mfc-check: 指摘なし (特に MAP004 = DECLARE があって BEGIN がない)
for ty in mfc mfc-mdi mfc-dialog; do
  n="app_${ty//-/_}"
  out="$(python3 "$SK/mfc-check/scripts/mfc_check.py" "$W/$n" 2>&1)"; rc=$?
  ok "$ty: mfc-check has no error and no MAP004 / MAP00x" "$([ $rc = 0 ] && ! grep -q 'MAP00' <<<"$out" && echo 1 || echo 0)"
done

# 文書
ok "CHANGELOG.md: the fix is recorded" "$(grep -q 'ID_FILE_OPEN' "$ROOT/CHANGELOG.md" && echo 1 || echo 0)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
