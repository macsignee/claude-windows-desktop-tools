#!/usr/bin/env bash
# mfc_mdi_wizard_look_test.sh - MDI のひな形 (`--type mfc-mdi`) の初期状態が、Visual Studio のウィザード (MFC アプリケーション、MDI、
# メニュー バーとツール バー、ステータス バー、タブ付き MDI) の見た目と操作に近いことを検証する (v2.104.0)。SDI は mfc_sdi_wizard_look_test.sh。
# 寄せる: CWinAppEx / CMDIFrameWndEx / CMDIChildWndEx、メニュー バー・ツール バー・ステータス バー、タブ付き MDI、2 つのメニュー
#         (IDR_MAINFRAME・IDR_SAMPLETYPE)、ウィンドウ メニューと「ウィンドウ」ダイアログ、アクセラレータ、バージョン情報、MRU、ビットマップ。
# 寄せない (決定済み): C 接頭辞、x64 のみ、印刷・プレビュー、OLE、SHARED_HANDLERS、Win32 の構成、l.JPN の afxres.rc。
# 注意: CMDIFrameWndEx::OnCreateClient は、クライアント領域をサブクラス化する。MainFrame が OnCreateClient を上書きして
#       CreateClient(lpcs, nullptr) を直接呼ぶと、それを飛ばす。ウィザードと同じく、上書きしない (IDR_MAINFRAME のメニューが 3 項目あるので、MDI001 も出ない)。
# Usage: tests/mfc_mdi_wizard_look_test.sh      終了コード: 0 すべて OK / 1 失敗あり
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$ROOT/skills"
W="$(mktemp -d "${TMPDIR:-/tmp}/mfcmdilook.XXXXXX")"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$1" "$2" 2>/dev/null && echo 1 || echo 0; }
hasre() { grep -qE -- "$1" "$2" 2>/dev/null && echo 1 || echo 0; }
all() { local f=$1; shift; for p in "$@"; do [ "$(has "$p" "$f")" = 1 ] || { echo 0; return; }; done; echo 1; }  # all <ファイル> <固定文字列>...

for ty in mfc mfc-mdi mfc-dialog; do
  n="app_${ty//-/_}"
  python3 "$SK/new-solution/scripts/new_solution.py" "$W/$n" --type "$ty" --layers none --tests none >/dev/null 2>&1
done
D="$W/app_mfc_mdi/app_mfc_mdi"
RC="$D/app_mfc_mdi.rc"

# --- framework.h ---
ok "MDI framework.h includes afxcontrolbars.h and keeps the Common Controls 6.0 directive" "$(all "$D/framework.h" '#include <afxcontrolbars.h>' 'Microsoft.Windows.Common-Controls')"
ok "MDI framework.h has no OLE automation (afxdisp.h)" "$([ "$(has '#include <afxdisp.h>' "$D/framework.h")" = 0 ] && echo 1 || echo 0)"

# --- SampleApp ---
ok "MDI: SampleApp derives from CWinAppEx with m_bHiColorIcons, PreLoadState / LoadCustomState / SaveCustomState / OnAppAbout, extern theApp" "$(all "$D/SampleApp.h" 'class SampleApp : public CWinAppEx' 'BOOL  m_bHiColorIcons;' 'virtual void PreLoadState();' 'virtual void LoadCustomState();' 'virtual void SaveCustomState();' 'afx_msg void OnAppAbout();' 'extern SampleApp theApp;')"
ok "MDI: message map on CWinAppEx with ID_APP_ABOUT / ID_FILE_NEW / ID_FILE_OPEN (and the TN022 comment)" "$(all "$D/SampleApp.cpp" 'BEGIN_MESSAGE_MAP(SampleApp, CWinAppEx)' 'ON_COMMAND(ID_APP_ABOUT, &SampleApp::OnAppAbout)' 'ON_COMMAND(ID_FILE_NEW, &CWinAppEx::OnFileNew)' 'ON_COMMAND(ID_FILE_OPEN, &CWinAppEx::OnFileOpen)' 'TN022')"
ok "MDI: InitInstance has InitCommonControlsEx, SetRegistryKey, LoadStdProfileSettings(4) (MRU), the managers, ParseCommandLine" "$(all "$D/SampleApp.cpp" 'InitCommonControlsEx(' 'SetRegistryKey(' 'LoadStdProfileSettings(4)' 'InitContextMenuManager();' 'InitKeyboardManager();' 'InitTooltipManager();' 'ParseCommandLine(cmdInfo)')"
ok "MDI: CMultiDocTemplate(IDR_SAMPLETYPE, SampleDoc, ChildFrame, SampleView), MainFrame::LoadFrame(IDR_MAINFRAME), ShowWindow(m_nCmdShow)" "$(all "$D/SampleApp.cpp" 'new CMultiDocTemplate(' 'IDR_SAMPLETYPE' 'RUNTIME_CLASS(ChildFrame)' 'LoadFrame(IDR_MAINFRAME)' 'ShowWindow(m_nCmdShow)')"
ok "MDI: no OLE; the about box is AboutDlg (no C prefix) with DECLARE_DYNAMIC; DPI comment kept" "$([ "$(has 'AfxOle' "$D/SampleApp.cpp")" = 0 ] && [ "$(all "$D/SampleApp.cpp" 'class AboutDlg : public CDialogEx' 'DECLARE_DYNAMIC(AboutDlg)' 'IMPLEMENT_DYNAMIC(AboutDlg, CDialogEx)' 'EnableDpiAwareness' '#include "afxdialogex.h"')" = 1 ] && [ "$(has 'CAboutDlg' "$D/SampleApp.cpp")" = 0 ] && echo 1 || echo 0)"

# --- MainFrame / ChildFrame ---
ok "MDI: MainFrame derives from CMDIFrameWndEx (DECLARE_DYNAMIC) with the menu bar / toolbar / status bar and OnWindowManager" "$(all "$D/MainFrame.h" 'class MainFrame : public CMDIFrameWndEx' 'DECLARE_DYNAMIC(MainFrame)' 'CMFCMenuBar' 'CMFCToolBar' 'CMFCStatusBar' 'afx_msg void OnWindowManager();' 'afx_msg void OnViewCustomize();' 'afx_msg LRESULT OnToolbarCreateNew(WPARAM wp, LPARAM lp);')"
ok "MDI: MainFrame.cpp: IMPLEMENT_DYNAMIC on CMDIFrameWndEx, message map with ID_WINDOW_MANAGER / ID_VIEW_CUSTOMIZE / AFX_WM_CREATETOOLBAR" "$(all "$D/MainFrame.cpp" 'IMPLEMENT_DYNAMIC(MainFrame, CMDIFrameWndEx)' 'BEGIN_MESSAGE_MAP(MainFrame, CMDIFrameWndEx)' 'ON_WM_CREATE()' 'ON_COMMAND(ID_WINDOW_MANAGER, &MainFrame::OnWindowManager)' 'ON_COMMAND(ID_VIEW_CUSTOMIZE, &MainFrame::OnViewCustomize)' 'ON_REGISTERED_MESSAGE(AFX_WM_CREATETOOLBAR, &MainFrame::OnToolbarCreateNew)')"
ok "MDI: MainFrame.cpp: tabbed MDI (CMDITabInfo, EnableMDITabbedGroups), EnableWindowsDialog, ShowWindowsDialog, FWS_PREFIXTITLE" "$(all "$D/MainFrame.cpp" 'CMDITabInfo mdiTabParams;' 'EnableMDITabbedGroups(TRUE, mdiTabParams);' 'EnableWindowsDialog(ID_WINDOW_MANAGER, ID_WINDOW_MANAGER, TRUE);' 'ShowWindowsDialog();' 'ModifyStyle(0, FWS_PREFIXTITLE);')"
ok "MDI: MainFrame.cpp: status bar indicators, DockPane, VS2008 visual manager, pane menu, toolbar loads IDR_MAINFRAME_256" "$(all "$D/MainFrame.cpp" 'ID_INDICATOR_CAPS' 'DockPane(&m_wndToolBar)' 'CMFCVisualManagerVS2008' 'EnablePaneMenu(TRUE, ID_VIEW_CUSTOMIZE' 'theApp.m_bHiColorIcons ? IDR_MAINFRAME_256 : IDR_MAINFRAME' '#include "SampleApp.h"')"
ok "MDI: MainFrame does NOT override OnCreateClient (CMDIFrameWndEx::OnCreateClient subclasses the client area; a direct CreateClient call would skip it)" "$([ "$(has 'OnCreateClient' "$D/MainFrame.h")" = 0 ] && [ "$(has 'CreateClient(' "$D/MainFrame.cpp")" = 0 ] && echo 1 || echo 0)"
ok "MDI: ChildFrame derives from CMDIChildWndEx (DECLARE_DYNCREATE) with the wizard's PreCreateWindow style" "$(all "$D/ChildFrame.h" 'class ChildFrame : public CMDIChildWndEx' 'DECLARE_DYNCREATE(ChildFrame)' 'virtual BOOL PreCreateWindow(CREATESTRUCT& cs);')"
ok "MDI: ChildFrame.cpp: IMPLEMENT_DYNCREATE on CMDIChildWndEx, message map, style WS_CHILD | WS_VISIBLE ... WS_THICKFRAME" "$(all "$D/ChildFrame.cpp" 'IMPLEMENT_DYNCREATE(ChildFrame, CMDIChildWndEx)' 'BEGIN_MESSAGE_MAP(ChildFrame, CMDIChildWndEx)' 'cs.style = WS_CHILD | WS_VISIBLE | WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU' 'FWS_ADDTOTITLE | WS_THICKFRAME;')"

# --- SampleDoc / SampleView (SDI と同じ) ---
ok "MDI: SampleDoc has OnNewDocument and Serialize; SampleView has the right-click context menu (IDR_POPUP_EDIT) and OnDraw draws nothing, like the wizard (no TextOut of the app name)" "$([ "$(all "$D/SampleDoc.h" 'virtual BOOL OnNewDocument();' 'virtual void Serialize(CArchive& ar);')" = 1 ] && [ "$(all "$D/SampleView.cpp" 'ON_WM_RBUTTONUP()' 'ON_WM_CONTEXTMENU()' 'ShowPopupMenu' 'void SampleView::OnDraw(CDC* pDC)')" = 1 ] && [ "$(has 'TextOut' "$D/SampleView.cpp")" = 0 ] && echo 1 || echo 0)"
ok "MDI: no printing, no SHARED_HANDLERS" "$([ "$(has 'OnFilePrint' "$D/SampleView.cpp")" = 0 ] && [ "$(has 'OnPreparePrinting' "$D/SampleView.cpp")" = 0 ] && [ "$(has 'SHARED_HANDLERS' "$D/SampleDoc.cpp")" = 0 ] && echo 1 || echo 0)"

# --- Resource.h ---
ok "MDI: Resource.h has the wizard's IDs (about box, popup, panes, toolbar strings, customize, 256 bitmap, ID_WINDOW_MANAGER)" "$(python3 - "$D/Resource.h" <<'PYEOF' && echo 1 || echo 0
import sys,re
t=open(sys.argv[1],encoding='utf-8-sig').read()
need=['IDD_ABOUTBOX','IDR_POPUP_EDIT','IDR_HELP_MENU','IDS_STATUS_PANE1','IDS_STATUS_PANE2','IDS_TOOLBAR_STANDARD','IDS_TOOLBAR_CUSTOMIZE','ID_VIEW_CUSTOMIZE','IDR_MAINFRAME','IDR_MAINFRAME_256','IDR_SAMPLETYPE','IDS_EDIT_MENU','ID_WINDOW_MANAGER','_APS_NEXT_RESOURCE_VALUE','_APS_NEXT_COMMAND_VALUE']
sys.exit(0 if all(re.search(r'#define\s+'+k+r'\b',t) for k in need) else 1)
PYEOF
)"
ok "MDI: Resource.h has no duplicate numbers within a prefix (IDR_ / IDD_ / ID_ / IDS_)" "$(python3 - "$D/Resource.h" <<'PYEOF' && echo 1 || echo 0
import sys,re,collections
t=open(sys.argv[1],encoding='utf-8-sig').read()
seen=collections.defaultdict(list)
for m in re.finditer(r'#define\s+((?:IDR|IDD|IDS|ID)_\w+)\s+(\d+)',t):
    seen[(m.group(1).split('_')[0], m.group(2))].append(m.group(1))
sys.exit(0 if all(len(v)==1 for v in seen.values()) else 1)
PYEOF
)"

# --- .rc: 2 つのメニュー ---
menus() { python3 - "$RC" "$1" <<'PYEOF'
import sys,re
t=open(sys.argv[1],encoding='utf-8-sig').read()
m=re.search(r'^'+sys.argv[2]+r' MENU\s*\nBEGIN\n(.*?)\nEND\n', t, re.S|re.M)
print(m.group(1) if m else '')
PYEOF
}
MAIN_MENU="$(menus IDR_MAINFRAME)"; DOC_MENU="$(menus IDR_SAMPLETYPE)"
ok "MDI .rc: IDR_MAINFRAME menu (no child open) has File / View / Help (3 popups: the default OnCreateClient is satisfied, no MDI001), no Edit / Window" "$(python3 - "$MAIN_MENU" <<'PYEOF' && echo 1 || echo 0
import sys,re
t=sys.argv[1]
top=re.findall(r'^    POPUP "([^"]+)"', t, re.M)
sys.exit(0 if top==['ファイル(&F)','表示(&V)','ヘルプ(&H)'] else 1)
PYEOF
)"
ok "MDI .rc: IDR_MAINFRAME's File menu has New / Open / Close / MRU / Exit; View has the toolbar placeholder and status bar" "$([ "$(grep -c 'ID_FILE_NEW\|ID_FILE_OPEN\|ID_FILE_CLOSE\|ID_FILE_MRU_FILE1\|ID_APP_EXIT\|ID_VIEW_TOOLBAR\|ID_VIEW_STATUS_BAR\|ID_APP_ABOUT' <<<"$MAIN_MENU")" = 8 ] && echo 1 || echo 0)"
ok "MDI .rc: IDR_SAMPLETYPE menu (a child open) has File / Edit / View / Window / Help; File has Save / Save As; Window has New Window" "$(python3 - "$DOC_MENU" <<'PYEOF' && echo 1 || echo 0
import sys,re
t=sys.argv[1]
top=re.findall(r'^    POPUP "([^"]+)"', t, re.M)
need=['ID_FILE_SAVE','ID_FILE_SAVE_AS','ID_WINDOW_NEW','ID_EDIT_UNDO','ID_EDIT_CUT','ID_EDIT_COPY','ID_EDIT_PASTE','ID_FILE_CLOSE','ID_FILE_MRU_FILE1','ID_VIEW_STATUS_BAR','ID_APP_ABOUT']
sys.exit(0 if top==['ファイル(&F)','編集(&E)','表示(&V)','ウィンドウ(&W)','ヘルプ(&H)'] and all(k in t for k in need) else 1)
PYEOF
)"
ok "MDI .rc: the edit popup and help menus; accelerators; toolbars with the 16x15 bitmaps; no print button" "$([ "$(has 'IDR_POPUP_EDIT MENU' "$RC")" = 1 ] && [ "$(has 'IDR_HELP_MENU MENU' "$RC")" = 1 ] && [ "$(has 'IDR_MAINFRAME ACCELERATORS' "$RC")" = 1 ] && [ "$(has 'IDR_MAINFRAME TOOLBAR 16, 15' "$RC")" = 1 ] && [ "$(has 'IDR_MAINFRAME_256 TOOLBAR 16, 15' "$RC")" = 1 ] && [ "$(has 'res\\Toolbar.bmp' "$RC")" = 1 ] && [ "$(has 'res\\Toolbar256.bmp' "$RC")" = 1 ] && [ "$(has 'ID_FILE_PRINT' "$RC")" = 0 ] && echo 1 || echo 0)"
ok "MDI .rc: about box, version info, Japanese string tables (idle message, indicators, hints)" "$(all "$RC" 'IDD_ABOUTBOX DIALOGEX' 'MS UI Gothic' 'VS_VERSION_INFO' '0x0411, 1200' 'AFX_IDS_IDLEMESSAGE' '準備完了' 'ID_INDICATOR_CAPS' 'IDS_TOOLBAR_STANDARD')"
ok "MDI .rc: window hints (ID_WINDOW_NEW / CASCADE / TILE_HORZ / TILE_VERT / ARRANGE), AFX_IDS_MDICHILD, ID_WINDOW_MANAGER" "$(all "$RC" 'ID_WINDOW_NEW ' 'ID_WINDOW_CASCADE' 'ID_WINDOW_TILE_HORZ' 'ID_WINDOW_TILE_VERT' 'ID_WINDOW_ARRANGE' 'AFX_IDS_MDICHILD' 'ID_WINDOW_MANAGER ')"
ok "MDI .rc: IDR_MAINFRAME is the app title string; IDR_SAMPLETYPE is the document type string; both icons" "$([ "$(hasre 'IDR_MAINFRAME +"app_mfc_mdi"' "$RC")" = 1 ] && [ "$(hasre 'IDR_SAMPLETYPE +"\\napp_mfc_mdi\\napp_mfc_mdi' "$RC")" = 1 ] && [ "$(hasre 'IDR_MAINFRAME +ICON' "$RC")" = 1 ] && [ "$(hasre 'IDR_SAMPLETYPE +ICON' "$RC")" = 1 ] && echo 1 || echo 0)"
ok "MDI .rc: no l.JPN dependency; UTF-8 with code_page(65001); rc2 include" "$([ "$(has 'l.JPN' "$RC")" = 0 ] && [ "$(has '#pragma code_page(65001)' "$RC")" = 1 ] && [ "$(has 'res\app_mfc_mdi.rc2' "$RC")" = 1 ] && echo 1 || echo 0)"

# --- res\ と .vcxproj ---
bmp_ok() { python3 - "$1" "$2" "$3" <<'PYEOF' && echo 1 || echo 0
import sys,struct
p,w,h=sys.argv[1],int(sys.argv[2]),int(sys.argv[3])
try: b=open(p,'rb').read()
except OSError: sys.exit(1)
if b[:2]!=b'BM' or len(b)<54: sys.exit(1)
size=struct.unpack('<I',b[2:6])[0]
bw,bh,planes,bpp=struct.unpack('<iiHH',b[18:30])
sys.exit(0 if size==len(b) and bw==w and abs(bh)==h and planes==1 and bpp in (8,24,32) else 1)
PYEOF
}
ok "MDI res: Toolbar.bmp and Toolbar256.bmp are valid bitmaps (7 buttons x 16 wide, 15 high); userimages.bmp exists" "$([ "$(bmp_ok "$D/res/Toolbar.bmp" 112 15)" = 1 ] && [ "$(bmp_ok "$D/res/Toolbar256.bmp" 112 15)" = 1 ] && [ "$(head -c2 "$D/res/userimages.bmp")" = BM ] && echo 1 || echo 0)"
V="$D/app_mfc_mdi.vcxproj"; F="$D/app_mfc_mdi.vcxproj.filters"
ok "MDI .vcxproj / .filters: the bitmaps are in the project; ChildFrame is compiled; still x64 only, DPI aware, stdcpp20" "$([ "$(all "$V" 'Image Include="res\Toolbar.bmp"' 'Image Include="res\Toolbar256.bmp"' 'Image Include="res\userimages.bmp"' 'ClCompile Include="ChildFrame.cpp"' 'EnableDpiAwareness' 'stdcpp20')" = 1 ] && [ "$(all "$F" 'res\Toolbar.bmp' 'res\userimages.bmp')" = 1 ] && [ "$(has 'Win32' "$V")" = 0 ] && echo 1 || echo 0)"

# --- mfc-check ---
out="$(python3 "$SK/mfc-check/scripts/mfc_check.py" "$W/app_mfc_mdi" 2>&1)"; rc=$?
ok "MDI: mfc-check has no error, and no MAP / RES / DEC / NSP / MDI001 finding" "$([ $rc = 0 ] && ! grep -qE 'MAP00|RES00|DEC001|NSP001|MDI001' <<<"$out" && echo 1 || echo 0)"

# --- SDI・ダイアログは、このテストでは、変えない ---
ok "SDI is still CWinAppEx / CFrameWndEx (unchanged by the MDI work)" "$([ "$(has 'class MainFrame : public CFrameWndEx' "$W/app_mfc/app_mfc/MainFrame.h")" = 1 ] && echo 1 || echo 0)"
ok "dialog-based is unchanged: no control bars header, no Toolbar.bmp" "$([ "$(has 'afxcontrolbars.h' "$W/app_mfc_dialog/app_mfc_dialog/framework.h")" = 0 ] && [ ! -e "$W/app_mfc_dialog/app_mfc_dialog/res/Toolbar.bmp" ] && echo 1 || echo 0)"

# --- 文書 ---
ok "CHANGELOG.md records the MDI wizard look (2.104.0)" "$(grep -q '2.104.0' "$ROOT/CHANGELOG.md" && echo 1 || echo 0)"
ok "VERSION is 2.104.0 or later" "$(python3 -c "
v=tuple(int(x) for x in open('$ROOT/VERSION').read().split('.'))
print(1 if v>=(2,104,0) else 0)")"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
