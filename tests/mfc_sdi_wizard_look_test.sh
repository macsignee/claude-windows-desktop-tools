#!/usr/bin/env bash
# mfc_sdi_wizard_look_test.sh - SDI のひな形 (`--type mfc`) の初期状態が、Visual Studio のウィザード (MFC アプリケーション、SDI、
# メニュー バーとツール バー、ステータス バー) の見た目と操作に近いことを検証する (v2.103.0)。
# 寄せる: CWinAppEx / CFrameWndEx、メニュー バー・ツール バー・ステータス バー、メニュー (ファイル・編集・表示・ヘルプ)、
#         アクセラレータ、バージョン情報、MRU、ツール バーのビットマップ、文字列リソース、右クリック メニュー。
# 寄せない (決定済み): C 接頭辞 (自作クラスは付けない)、x64 のみ、印刷・プレビュー、OLE、SHARED_HANDLERS、Win32 の構成。
# ダイアログのひな形は、変えない。MDI は、v2.104.0 で寄せた (mfc_mdi_wizard_look_test.sh)。
# Usage: tests/mfc_sdi_wizard_look_test.sh      終了コード: 0 すべて OK / 1 失敗あり
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$ROOT/skills"
W="$(mktemp -d "${TMPDIR:-/tmp}/mfcsdilook.XXXXXX")"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$1" "$2" 2>/dev/null && echo 1 || echo 0; }     # has <固定文字列> <ファイル>
hasre() { grep -qE -- "$1" "$2" 2>/dev/null && echo 1 || echo 0; }  # hasre <正規表現> <ファイル>

for ty in mfc mfc-mdi mfc-dialog; do
  n="app_${ty//-/_}"
  python3 "$SK/new-solution/scripts/new_solution.py" "$W/$n" --type "$ty" --layers none --tests none >/dev/null 2>&1
done
D="$W/app_mfc/app_mfc"
RC="$D/app_mfc.rc"

# --- framework.h ---
ok "SDI framework.h includes afxcontrolbars.h (menu bar / toolbar / status bar)" "$(has '#include <afxcontrolbars.h>' "$D/framework.h")"
ok "SDI framework.h still has the Common Controls 6.0 directive" "$(has 'Microsoft.Windows.Common-Controls' "$D/framework.h")"
ok "SDI framework.h does not pull in OLE automation (afxdisp.h)" "$([ "$(has '#include <afxdisp.h>' "$D/framework.h")" = 0 ] && echo 1 || echo 0)"

# --- SampleApp ---
ok "SDI: SampleApp derives from CWinAppEx and keeps m_bHiColorIcons" "$([ "$(has 'class SampleApp : public CWinAppEx' "$D/SampleApp.h")" = 1 ] && [ "$(has 'BOOL  m_bHiColorIcons;' "$D/SampleApp.h")" = 1 ] && echo 1 || echo 0)"
ok "SDI: SampleApp declares PreLoadState / LoadCustomState / SaveCustomState / OnAppAbout" "$([ "$(has 'virtual void PreLoadState();' "$D/SampleApp.h")" = 1 ] && [ "$(has 'virtual void LoadCustomState();' "$D/SampleApp.h")" = 1 ] && [ "$(has 'virtual void SaveCustomState();' "$D/SampleApp.h")" = 1 ] && [ "$(has 'afx_msg void OnAppAbout();' "$D/SampleApp.h")" = 1 ] && echo 1 || echo 0)"
ok "SDI: SampleApp.cpp has the message map on CWinAppEx with ID_APP_ABOUT / ID_FILE_NEW / ID_FILE_OPEN" "$([ "$(has 'BEGIN_MESSAGE_MAP(SampleApp, CWinAppEx)' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'ON_COMMAND(ID_APP_ABOUT, &SampleApp::OnAppAbout)' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'ON_COMMAND(ID_FILE_NEW, &CWinAppEx::OnFileNew)' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'ON_COMMAND(ID_FILE_OPEN, &CWinAppEx::OnFileOpen)' "$D/SampleApp.cpp")" = 1 ] && echo 1 || echo 0)"
ok "SDI: the TN022 comment (why FILE_NEW/OPEN are tied) is kept" "$([ "$(has 'TN022' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'グレーアウト' "$D/SampleApp.cpp")" = 1 ] && echo 1 || echo 0)"
ok "SDI: InitInstance has SetRegistryKey, LoadStdProfileSettings(4) (MRU) and the managers" "$([ "$(has 'SetRegistryKey(' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'LoadStdProfileSettings(4)' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'InitContextMenuManager();' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'InitKeyboardManager();' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'InitTooltipManager();' "$D/SampleApp.cpp")" = 1 ] && echo 1 || echo 0)"
ok "SDI: InitInstance has InitCommonControlsEx and the command line (ParseCommandLine) like the wizard" "$([ "$(has 'InitCommonControlsEx(' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'ParseCommandLine(cmdInfo)' "$D/SampleApp.cpp")" = 1 ] && echo 1 || echo 0)"
ok "SDI: no OLE (AfxOleInit / AfxOleTerm are not used)" "$([ "$(has 'AfxOle' "$D/SampleApp.cpp")" = 0 ] && echo 1 || echo 0)"
ok "SDI: the about box class has no C prefix (AboutDlg), uses CDialogEx, ID IDD_ABOUTBOX" "$([ "$(has 'class AboutDlg : public CDialogEx' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'IDD_ABOUTBOX' "$D/SampleApp.cpp")" = 1 ] && [ "$(has 'CAboutDlg' "$D/SampleApp.cpp")" = 0 ] && echo 1 || echo 0)"
ok "SDI: SampleApp.cpp includes afxdialogex.h" "$(has '#include "afxdialogex.h"' "$D/SampleApp.cpp")"
ok "SDI: the DPI comment is kept (EnableDpiAwareness in .vcxproj)" "$(has 'EnableDpiAwareness' "$D/SampleApp.cpp")"

# --- MainFrame ---
ok "SDI: MainFrame derives from CFrameWndEx and has CMFCMenuBar / CMFCToolBar / CMFCStatusBar" "$([ "$(has 'class MainFrame : public CFrameWndEx' "$D/MainFrame.h")" = 1 ] && [ "$(has 'CMFCMenuBar' "$D/MainFrame.h")" = 1 ] && [ "$(has 'CMFCToolBar' "$D/MainFrame.h")" = 1 ] && [ "$(has 'CMFCStatusBar' "$D/MainFrame.h")" = 1 ] && echo 1 || echo 0)"
ok "SDI: MainFrame.cpp: IMPLEMENT_DYNCREATE / message map on CFrameWndEx, OnCreate, OnViewCustomize, OnToolbarCreateNew" "$([ "$(has 'IMPLEMENT_DYNCREATE(MainFrame, CFrameWndEx)' "$D/MainFrame.cpp")" = 1 ] && [ "$(has 'BEGIN_MESSAGE_MAP(MainFrame, CFrameWndEx)' "$D/MainFrame.cpp")" = 1 ] && [ "$(has 'ON_WM_CREATE()' "$D/MainFrame.cpp")" = 1 ] && [ "$(has 'ON_COMMAND(ID_VIEW_CUSTOMIZE, &MainFrame::OnViewCustomize)' "$D/MainFrame.cpp")" = 1 ] && [ "$(has 'ON_REGISTERED_MESSAGE(AFX_WM_CREATETOOLBAR, &MainFrame::OnToolbarCreateNew)' "$D/MainFrame.cpp")" = 1 ] && echo 1 || echo 0)"
ok "SDI: MainFrame.cpp: status bar indicators, DockPane, VS2008 visual manager, pane menu" "$([ "$(has 'ID_INDICATOR_CAPS' "$D/MainFrame.cpp")" = 1 ] && [ "$(has 'DockPane(&m_wndToolBar)' "$D/MainFrame.cpp")" = 1 ] && [ "$(has 'CMFCVisualManagerVS2008' "$D/MainFrame.cpp")" = 1 ] && [ "$(has 'EnablePaneMenu(TRUE, ID_VIEW_CUSTOMIZE' "$D/MainFrame.cpp")" = 1 ] && echo 1 || echo 0)"
ok "SDI: MainFrame.cpp: the toolbar loads IDR_MAINFRAME_256 when m_bHiColorIcons" "$(has 'theApp.m_bHiColorIcons ? IDR_MAINFRAME_256 : IDR_MAINFRAME' "$D/MainFrame.cpp")"
ok "SDI: MainFrame.cpp includes SampleApp.h (for theApp)" "$(has '#include "SampleApp.h"' "$D/MainFrame.cpp")"

# --- SampleDoc / SampleView ---
ok "SDI: SampleDoc has OnNewDocument and Serialize (File > Save / Open work as in the wizard)" "$([ "$(has 'virtual BOOL OnNewDocument();' "$D/SampleDoc.h")" = 1 ] && [ "$(has 'virtual void Serialize(CArchive& ar);' "$D/SampleDoc.h")" = 1 ] && [ "$(has 'void SampleDoc::Serialize(CArchive& ar)' "$D/SampleDoc.cpp")" = 1 ] && echo 1 || echo 0)"
ok "SDI: SampleDoc / SampleView keep the names and the macros (no C)" "$([ "$(has 'IMPLEMENT_DYNCREATE(SampleDoc, CDocument)' "$D/SampleDoc.cpp")" = 1 ] && [ "$(has 'IMPLEMENT_DYNCREATE(SampleView, CView)' "$D/SampleView.cpp")" = 1 ] && echo 1 || echo 0)"
ok "SDI: SampleView has a right-click context menu (IDR_POPUP_EDIT) and OnDraw draws nothing, like the wizard (no TextOut of the app name: the view was blank in the wizard's SDI, 2026-11-28)" "$([ "$(has 'ON_WM_RBUTTONUP()' "$D/SampleView.cpp")" = 1 ] && [ "$(has 'ON_WM_CONTEXTMENU()' "$D/SampleView.cpp")" = 1 ] && [ "$(has 'ShowPopupMenu' "$D/SampleView.cpp")" = 1 ] && [ "$(has 'void SampleView::OnDraw(CDC* pDC)' "$D/SampleView.cpp")" = 1 ] && [ "$(has 'TextOut' "$D/SampleView.cpp")" = 0 ] && echo 1 || echo 0)"
ok "SDI: no printing (OnFilePrint / OnPreparePrinting are not generated)" "$([ "$(has 'OnFilePrint' "$D/SampleView.cpp")" = 0 ] && [ "$(has 'OnPreparePrinting' "$D/SampleView.cpp")" = 0 ] && [ "$(has 'SHARED_HANDLERS' "$D/SampleDoc.cpp")" = 0 ] && echo 1 || echo 0)"

# --- Resource.h ---
ok "SDI: Resource.h has the IDs the wizard defines (about box, popup, status bar panes, toolbar strings, customize, 256 bitmap)" "$(python3 - "$D/Resource.h" <<'PYEOF' && echo 1 || echo 0
import sys,re
t=open(sys.argv[1],encoding='utf-8-sig').read()
need=['IDD_ABOUTBOX','IDR_POPUP_EDIT','IDR_HELP_MENU','IDS_STATUS_PANE1','IDS_STATUS_PANE2','IDS_TOOLBAR_STANDARD','IDS_TOOLBAR_CUSTOMIZE','ID_VIEW_CUSTOMIZE','IDR_MAINFRAME','IDR_MAINFRAME_256','IDR_SAMPLETYPE','IDS_EDIT_MENU','_APS_NEXT_RESOURCE_VALUE','_APS_NEXT_COMMAND_VALUE']
sys.exit(0 if all(re.search(r'#define\s+'+k+r'\b',t) for k in need) else 1)
PYEOF
)"
ok "SDI: Resource.h defines no duplicate numbers among the same prefix (IDR_ / IDD_ / ID_ / IDS_)" "$(python3 - "$D/Resource.h" <<'PYEOF' && echo 1 || echo 0
import sys,re,collections
t=open(sys.argv[1],encoding='utf-8-sig').read()
seen=collections.defaultdict(list)
for m in re.finditer(r'#define\s+((?:IDR|IDD|IDS|ID)_\w+)\s+(\d+)',t):
    k=m.group(1); pre=k.split('_')[0]
    seen[(pre if pre!='ID' else 'ID', m.group(2))].append(k)
sys.exit(0 if all(len(v)==1 for v in seen.values()) else 1)
PYEOF
)"

# --- .rc ---
ok "SDI .rc: menus File / Edit / View / Help, and the edit popup and help menus" "$([ "$(has 'POPUP "ファイル(&F)"' "$RC")" = 1 ] && [ "$(has 'POPUP "編集(&E)"' "$RC")" = 1 ] && [ "$(has 'POPUP "表示(&V)"' "$RC")" = 1 ] && [ "$(has 'POPUP "ヘルプ(&H)"' "$RC")" = 1 ] && [ "$(has 'IDR_POPUP_EDIT MENU' "$RC")" = 1 ] && [ "$(has 'IDR_HELP_MENU MENU' "$RC")" = 1 ] && echo 1 || echo 0)"
ok "SDI .rc: File menu has New / Open / Save / Save As / MRU / Exit; View has the toolbar placeholder and status bar" "$([ "$(has 'ID_FILE_NEW' "$RC")" = 1 ] && [ "$(has 'ID_FILE_OPEN' "$RC")" = 1 ] && [ "$(has 'ID_FILE_SAVE_AS' "$RC")" = 1 ] && [ "$(has 'ID_FILE_MRU_FILE1' "$RC")" = 1 ] && [ "$(has 'ID_APP_EXIT' "$RC")" = 1 ] && [ "$(has 'ID_VIEW_TOOLBAR' "$RC")" = 1 ] && [ "$(has 'ID_VIEW_STATUS_BAR' "$RC")" = 1 ] && [ "$(has 'ID_APP_ABOUT' "$RC")" = 1 ] && echo 1 || echo 0)"
ok "SDI .rc: accelerators (Ctrl+N / O / S / Z / X / C / V, F6)" "$([ "$(has 'IDR_MAINFRAME ACCELERATORS' "$RC")" = 1 ] && [ "$(hasre '"N",\s+ID_FILE_NEW' "$RC")" = 1 ] && [ "$(hasre '"S",\s+ID_FILE_SAVE' "$RC")" = 1 ] && [ "$(hasre 'VK_F6,\s+ID_NEXT_PANE' "$RC")" = 1 ] && echo 1 || echo 0)"
ok "SDI .rc: toolbars IDR_MAINFRAME and IDR_MAINFRAME_256 with the 16x15 bitmaps; no print button" "$([ "$(has 'IDR_MAINFRAME TOOLBAR 16, 15' "$RC")" = 1 ] && [ "$(has 'IDR_MAINFRAME_256 TOOLBAR 16, 15' "$RC")" = 1 ] && [ "$(has 'res\\Toolbar.bmp' "$RC")" = 1 ] && [ "$(has 'res\\Toolbar256.bmp' "$RC")" = 1 ] && [ "$(has 'ID_FILE_PRINT' "$RC")" = 0 ] && echo 1 || echo 0)"
ok "SDI .rc: about box (DIALOGEX IDD_ABOUTBOX, font MS UI Gothic) and version info (VS_VERSION_INFO, 0x0411)" "$([ "$(has 'IDD_ABOUTBOX DIALOGEX' "$RC")" = 1 ] && [ "$(has 'MS UI Gothic' "$RC")" = 1 ] && [ "$(has 'VS_VERSION_INFO' "$RC")" = 1 ] && [ "$(has '0x0411, 1200' "$RC")" = 1 ] && echo 1 || echo 0)"
ok "SDI .rc: string tables (idle message, indicators, command hints, toolbar names) in Japanese" "$([ "$(has 'AFX_IDS_IDLEMESSAGE' "$RC")" = 1 ] && [ "$(has '準備完了' "$RC")" = 1 ] && [ "$(has 'ID_INDICATOR_CAPS' "$RC")" = 1 ] && [ "$(has 'ID_FILE_SAVE' "$RC")" = 1 ] && [ "$(has 'IDS_TOOLBAR_STANDARD' "$RC")" = 1 ] && [ "$(has 'IDS_TOOLBAR_CUSTOMIZE' "$RC")" = 1 ] && echo 1 || echo 0)"
ok "SDI .rc: the document string table (IDR_MAINFRAME) is kept; the document icon is kept" "$([ "$(hasre 'IDR_MAINFRAME +"app_mfc' "$RC")" = 1 ] && [ "$(hasre 'IDR_SAMPLETYPE +ICON' "$RC")" = 1 ] && echo 1 || echo 0)"
ok "SDI .rc: no dependency on the localized afxres.rc (l.JPN) — it may be missing on a machine" "$([ "$(has 'l.JPN' "$RC")" = 0 ] && echo 1 || echo 0)"
ok "SDI .rc: still UTF-8 with #pragma code_page(65001) and the rc2 include" "$([ "$(has '#pragma code_page(65001)' "$RC")" = 1 ] && [ "$(has 'res\app_mfc.rc2' "$RC")" = 1 ] && echo 1 || echo 0)"

# --- res\ のビットマップ ---
bmp_ok() { python3 - "$1" "$2" "$3" <<'PYEOF' && echo 1 || echo 0
import sys,struct
p,w,h=sys.argv[1],int(sys.argv[2]),int(sys.argv[3])
try:
    b=open(p,'rb').read()
except OSError:
    sys.exit(1)
if b[:2]!=b'BM' or len(b)<54: sys.exit(1)
size,off=struct.unpack('<II',b[2:6]+b[10:14])
bw,bh,planes,bpp=struct.unpack('<iiHH',b[18:30])
sys.exit(0 if size==len(b) and bw==w and abs(bh)==h and planes==1 and bpp in (8,24,32) else 1)
PYEOF
}
ok "SDI res: Toolbar.bmp is a valid bitmap, 7 buttons x 16 wide, 15 high" "$(bmp_ok "$D/res/Toolbar.bmp" 112 15)"
ok "SDI res: Toolbar256.bmp is a valid bitmap, 7 buttons x 16 wide, 15 high" "$(bmp_ok "$D/res/Toolbar256.bmp" 112 15)"
ok "SDI res: userimages.bmp exists and is a valid bitmap" "$([ -s "$D/res/userimages.bmp" ] && [ "$(head -c2 "$D/res/userimages.bmp")" = BM ] && echo 1 || echo 0)"

# --- .vcxproj / .filters ---
V="$D/app_mfc.vcxproj"; F="$D/app_mfc.vcxproj.filters"
ok "SDI .vcxproj: the bitmaps are in the project (Image)" "$([ "$(has 'Image Include="res\Toolbar.bmp"' "$V")" = 1 ] && [ "$(has 'Image Include="res\Toolbar256.bmp"' "$V")" = 1 ] && [ "$(has 'Image Include="res\userimages.bmp"' "$V")" = 1 ] && echo 1 || echo 0)"
ok "SDI .filters: the bitmaps are in the resource filter" "$([ "$(has 'res\Toolbar.bmp' "$F")" = 1 ] && [ "$(has 'res\Toolbar256.bmp' "$F")" = 1 ] && [ "$(has 'res\userimages.bmp' "$F")" = 1 ] && echo 1 || echo 0)"
ok "SDI .vcxproj: still x64 only, DPI aware, stdcpp20 (project rules are kept)" "$([ "$(has 'EnableDpiAwareness' "$V")" = 1 ] && [ "$(has 'stdcpp20' "$V")" = 1 ] && [ "$(has 'Win32' "$V")" = 0 ] && echo 1 || echo 0)"
ok "SDI: the bitmaps are binary files (not rewritten with a BOM / CRLF)" "$([ "$(head -c2 "$D/res/Toolbar.bmp")" = BM ] && echo 1 || echo 0)"

# --- mfc-check ---
out="$(python3 "$SK/mfc-check/scripts/mfc_check.py" "$W/app_mfc" 2>&1)"; rc=$?
ok "SDI: mfc-check has no error ($(grep -cE '^(ERROR|エラー)' <<<"$out") errors)" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "SDI: mfc-check reports no MAP / RES / DEC / NSP finding" "$(! grep -qE 'MAP00|RES00|DEC001|NSP001' <<<"$out" && echo 1 || echo 0)"

# --- ダイアログは、変えない (MDI は、v2.104.0 で寄せた。mfc_mdi_wizard_look_test.sh) ---
G="$W/app_mfc_dialog/app_mfc_dialog"
ok "dialog-based is unchanged: no control bars header, no Toolbar.bmp" "$([ "$(has 'afxcontrolbars.h' "$G/framework.h")" = 0 ] && [ ! -e "$G/res/Toolbar.bmp" ] && echo 1 || echo 0)"

# --- 文書 ---
ok "CHANGELOG.md records the SDI wizard look (2.103.0)" "$(grep -q '2.103.0' "$ROOT/CHANGELOG.md" && grep -q 'ウィザード' "$ROOT/CHANGELOG.md" && echo 1 || echo 0)"
ok "VERSION is 2.103.0 or later" "$(python3 -c "
v=tuple(int(x) for x in open('$ROOT/VERSION').read().split('.'))
print(1 if v>=(2,103,0) else 0)")"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
