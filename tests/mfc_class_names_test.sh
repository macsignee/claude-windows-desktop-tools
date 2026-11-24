#!/usr/bin/env bash
# mfc_class_names_test.sh - /new-solution が作る MFC の自作クラスに、C 接頭辞を付けない (rules/cpp-common.md の「自分で作るクラスには、C 接頭辞を付けない。クラスウィザードで作るクラスも同じ」)。
# 対象: SDI・MDI・ダイアログのメイン (SampleApp / SampleDoc / SampleView / MainFrame / ChildFrame / SampleDlg)。MFC の標準クラス (CWinApp・CDocument・CView・CDialog ほか) は、そのまま。
# Usage: tests/mfc_class_names_test.sh      終了コード: 0 すべて OK / 1 失敗あり
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$ROOT/skills"
W="$(mktemp -d "${TMPDIR:-/tmp}/mfcnames.XXXXXX")"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }

for ty in mfc mfc-mdi mfc-dialog; do
  n="app_${ty//-/_}"
  python3 "$SK/new-solution/scripts/new_solution.py" "$W/$n" --type "$ty" --layers logic --tests none --layer-kind mfc-std-dll >/dev/null 2>&1
done

# 自作クラスの名前 (ソースの class 宣言と、DECLARE_/IMPLEMENT_/RUNTIME_CLASS/メッセージマップ)
own() { # $1=フォルダ。生成された .h / .cpp の、C で始まる識別子のうち、MFC の標準クラスでないもの
    find "$1" -type f \( -name '*.h' -o -name '*.cpp' \) -not -path '*/vcpkg_installed/*' -print0 \
      | xargs -0 grep -ohE '\bC[A-Z][A-Za-z0-9]+\b' 2>/dev/null | sort -u \
      | grep -vxE 'CWinApp|CWinAppEx|CDocument|CView|CFormView|CFrameWnd|CMDIFrameWnd|CMDIChildWnd|CDialog|CDialogEx|CWnd|CObject|CString|CStringA|CStringW|CDC|CRect|CPoint|CSize|CEdit|CButton|CStatic|CCmdUI|CCmdTarget|CDataExchange|CRuntimeClass|CCommandLineInfo|CSingleDocTemplate|CMultiDocTemplate|CDocTemplate|CCreateContext|CDynLinkLibrary|CPaintDC|CClientDC|CBrush|CFont|CMenu|CToolBar|CStatusBar|CMemoryException|CException|CWaitCursor|CFile|CArchive|CTime|CPtrArray|CObArray|CMap|CArray|CList|CStringArray|CTypedPtrArray|CComPtr|CCriticalSection|CSingleLock|CWinThread|CMFCButton|CShellManager|CAfx[A-Za-z]*|CMFC[A-Za-z0-9]*|CFrameWndEx|CMDI[A-Za-z]*|CDockingManager|CDumpContext|CREATESTRUCT|CRT|CTL'
}
for ty in mfc mfc-mdi mfc-dialog; do
  n="app_${ty//-/_}"
  left="$(own "$W/$n" | tr '\n' ' ')"
  ok "generated $ty: no own class keeps the C prefix (left: ${left:-none})" "$([ -z "$left" ] && echo 1 || echo 0)"
done

# 個別の名前 (旧: CSampleApp ほか。新: C なし)
f="$W/app_mfc/app_mfc"
ok "SDI: SampleApp / SampleDoc / SampleView / MainFrame exist without C" "$(grep -q 'class SampleApp : public CWinApp' "$f/SampleApp.h" && grep -q 'class SampleDoc : public CDocument' "$f/SampleDoc.h" && grep -q 'class SampleView : public CView' "$f/SampleView.h" && grep -q 'class MainFrame : public CFrameWnd' "$f/MainFrame.h" && echo 1 || echo 0)"
ok "SDI: the macros use the new names (DECLARE_DYNCREATE / IMPLEMENT_DYNCREATE / RUNTIME_CLASS / message map)" "$(grep -q 'IMPLEMENT_DYNCREATE(SampleDoc, CDocument)' "$f/SampleDoc.cpp" && grep -q 'IMPLEMENT_DYNCREATE(SampleView, CView)' "$f/SampleView.cpp" && grep -q 'RUNTIME_CLASS(SampleDoc)' "$f/SampleApp.cpp" && grep -q 'RUNTIME_CLASS(SampleView)' "$f/SampleApp.cpp" && echo 1 || echo 0)"
f="$W/app_mfc_mdi/app_mfc_mdi"
ok "MDI: ChildFrame and MainFrame exist without C" "$(grep -q 'class ChildFrame : public CMDIChildWnd' "$f/ChildFrame.h" && grep -q 'class MainFrame : public CMDIFrameWnd' "$f/MainFrame.h" && echo 1 || echo 0)"
f="$W/app_mfc_dialog/app_mfc_dialog"
ok "dialog: SampleDlg exists without C, with DECLARE_DYNAMIC / IMPLEMENT_DYNAMIC and its message map" "$(grep -q 'class SampleDlg : public CDialog' "$f/SampleDlg.h" && grep -q 'DECLARE_DYNAMIC(SampleDlg)' "$f/SampleDlg.h" && grep -q 'IMPLEMENT_DYNAMIC(SampleDlg, CDialog)' "$f/SampleDlg.cpp" && grep -q 'BEGIN_MESSAGE_MAP(SampleDlg, CDialog)' "$f/SampleDlg.cpp" && echo 1 || echo 0)"
ok "no generated file still mentions the old names" "$(grep -rlE '\bC(SampleApp|SampleDoc|SampleView|SampleDlg|MainFrame|ChildFrame)\b' "$W" --include=*.h --include=*.cpp --include=*.md --include=*.rc --include=*.vcxproj* 2>/dev/null | head -1 | grep -q . && echo 0 || echo 1)"

# mfc-check は、新しい名前で、指摘を出さない (NSP001 / DEC001 / MDI001 は、名前に依存しない)
for ty in mfc mfc-mdi mfc-dialog; do
  n="app_${ty//-/_}"
  out="$(python3 "$SK/mfc-check/scripts/mfc_check.py" "$W/$n" 2>&1)"; rc=$?
  ok "generated $ty: mfc-check has no error and no NSP001 / DEC001 / MDI001" "$([ $rc = 0 ] && ! grep -q 'NSP001\|DEC001\|MDI001' <<<"$out" && echo 1 || echo 0)"
done

# 規約と文書の例も、同じ名前にそろえる
ok "rules/mfc-cpp.md: the sample dialog is named SampleDlg (no C)" "$(! grep -qE '\bCSampleDlg\b' "$ROOT/rules/mfc-cpp.md" && grep -q 'SampleDlg' "$ROOT/rules/mfc-cpp.md" && echo 1 || echo 0)"
ok "rules/cpp-common.md: still says existing C-prefixed own classes (wizard-made) are left alone until a separate rename commit" "$(grep -q '既存の `C` 付きの自作クラス' "$ROOT/rules/cpp-common.md" && echo 1 || echo 0)"
ok "the C-prefix rule itself is unchanged in cpp-common.md" "$(grep -q '自分で作るクラスには、`C` 接頭辞を付けない。\*\*クラスウィザードで作るクラスも同じ\*\*' "$ROOT/rules/cpp-common.md" && echo 1 || echo 0)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
