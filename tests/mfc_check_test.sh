#!/usr/bin/env bash
# mfc_check_test.sh - mfc_check.py の、各ルールの検出と、誤検出のなさ (正常なプロジェクト) を検証する。
# Usage: tests/mfc_check_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
# 疑似の MFC プロジェクトを、$TMPDIR に作る (.rc は UTF-16)。Windows / Visual Studio は不要。
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/mfc-check/scripts/mfc_check.py"
T="${TMPDIR:-/tmp}/mfcck_$$"
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }

python3 -I - "$T" <<'PYEOF'
import os, sys
T = sys.argv[1]
def w(path, text, enc="utf-8"):
    path = os.path.join(T, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = text.replace("\n", "\r\n")
    open(path, "wb").write(data.encode("utf-16") if enc == "utf-16" else data.encode(enc))
VCX = '<?xml version="1.0" encoding="utf-8"?>\n<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n<PropertyGroup Label="Configuration"><ConfigurationType>%s</ConfigurationType><UseOfMfc>Dynamic</UseOfMfc></PropertyGroup>\n%s</Project>\n'
def defs(d):
    return f"<ItemDefinitionGroup><ClCompile><PreprocessorDefinitions>{d};%(PreprocessorDefinitions)</PreprocessorDefinitions></ClCompile></ItemDefinitionGroup>\n"
def vcx(kind, extra="", mfc="Dynamic"):
    return (VCX % (kind, extra)).replace("<UseOfMfc>Dynamic</UseOfMfc>", f"<UseOfMfc>{mfc}</UseOfMfc>")
EXT_MAIN = '''#include <afxwin.h>
#include <afxdllx.h>
static AFX_EXTENSION_MODULE ExtDLL = { false, nullptr };
extern "C" int APIENTRY DllMain(HINSTANCE hInstance, DWORD dwReason, LPVOID)
{
    if (dwReason == DLL_PROCESS_ATTACH)
    {
        if (!AfxInitExtensionModule(ExtDLL, hInstance)) return 0;
        new CDynLinkLibrary(ExtDLL);
    }
    else if (dwReason == DLL_PROCESS_DETACH)
    {
        AfxTermExtensionModule(ExtDLL);
    }
    return 1;
}
'''
STD_APP = "#include <afxwin.h>\nclass CStdApp : public CWinApp\n{\n};\nCStdApp theApp;\n"
STD_API_H = "#ifdef STD_EXPORTS\n#define STD_API __declspec(dllexport)\n#else\n#define STD_API __declspec(dllimport)\n#endif\nSTD_API int Foo();\nSTD_API const char* Bar(int x);\n"
STD_OK_CPP = '#include "Api.h"\n#include <afxwin.h>\nint Foo()\n{\n    // 先頭で呼ぶ\n    AFX_MANAGE_STATE(AfxGetStaticModuleState());\n    return 1;\n}\nconst char* Bar(int x)\n{\n    AFX_MANAGE_STATE(AfxGetStaticModuleState());\n    return "a";\n}\n'
def refs(*names):
    return "<ItemGroup>" + "".join(f'<ProjectReference Include="..\\{n}\\{n}.vcxproj" />' for n in names) + "</ItemGroup>\n"

# ---------------- 正常なプロジェクト ----------------
w("good/App/App.vcxproj", VCX % ("Application", ""))
w("good/App/resource.h", "#define IDR_MAINFRAME 128\n#define IDD_ABOUT 100\n#define IDC_RUN_BTN 1000\n#define IDC_NAME_EDIT 1001\n#define ID_TOOLS_RUN 32771\n")
w("good/App/App.rc", '''#include "resource.h"
#include "afxres.h"
IDR_MAINFRAME MENU
BEGIN
    POPUP "&Tools"
    BEGIN
        MENUITEM "&Run\\tCtrl+R",            ID_TOOLS_RUN
        MENUITEM "E&xit",                    ID_APP_EXIT
    END
END
IDR_MAINFRAME ACCELERATORS
BEGIN
    "R",            ID_TOOLS_RUN,           VIRTKEY, CONTROL, NOINVERT
END
IDD_ABOUT DIALOGEX 0, 0, 200, 100
CAPTION "About"
FONT 9, "MS Shell Dlg", 0, 0, 0x1
BEGIN
    DEFPUSHBUTTON   "OK",IDOK,10,10,50,14
    PUSHBUTTON      "Run",IDC_RUN_BTN,10,30,50,14
    EDITTEXT        IDC_NAME_EDIT,10,50,80,14,ES_AUTOHSCROLL
    LTEXT           "THE END of the dialog",IDC_STATIC,10,70,40,8
END
''', "utf-16")
w("good/App/MainView.h", '''#pragma once
class MainView : public CView
{
    DECLARE_MESSAGE_MAP()
public:
    afx_msg void OnToolsRun();
    afx_msg void OnUpdateToolsRun(CCmdUI* pCmdUI);
    afx_msg void OnBnClickedRunBtn();
    afx_msg void OnSize(UINT nType, int cx, int cy);
};
''')
w("good/App/MainView.cpp", '''#include "MainView.h"
// ON_COMMAND(ID_COMMENTED_OUT, OnNothing)  <- コメント内は無視される
BEGIN_MESSAGE_MAP(MainView, CView)
    ON_COMMAND(ID_TOOLS_RUN, &MainView::OnToolsRun)
    ON_UPDATE_COMMAND_UI(ID_TOOLS_RUN, &MainView::OnUpdateToolsRun)
    ON_BN_CLICKED(IDC_RUN_BTN, &MainView::OnBnClickedRunBtn)
    ON_WM_SIZE()
    ON_COMMAND(ID_APP_EXIT, &CWinApp::OnAppExit)
END_MESSAGE_MAP()
void MainView::OnToolsRun() {}
void MainView::OnUpdateToolsRun(CCmdUI* pCmdUI) {}
void MainView::OnBnClickedRunBtn() {}
void MainView::OnSize(UINT nType, int cx, int cy) {}
''')

w("good/App/AboutDlg.h", '''#pragma once
class AboutDlg : public CDialogEx
{
public:
    AboutDlg();
    enum { IDD = IDD_ABOUT };
    CEdit m_name;
    CWnd m_any;
protected:
    virtual void DoDataExchange(CDataExchange* pDX);
    virtual BOOL OnInitDialog();
    DECLARE_MESSAGE_MAP()
public:
    afx_msg void OnBnClickedRunBtn();
};
''')
w("good/App/AboutDlg.cpp", '''#include "AboutDlg.h"
AboutDlg::AboutDlg() : CDialogEx(IDD_ABOUT) {}
void AboutDlg::DoDataExchange(CDataExchange* pDX)
{
    CDialogEx::DoDataExchange(pDX);
    DDX_Control(pDX, IDC_NAME_EDIT, m_name);
    if (UseEdit())
        DDX_Control(pDX, IDC_NAME_EDIT, m_any);
    else
        DDX_Control(pDX, IDC_RUN_BTN, m_any);
}
BOOL AboutDlg::OnInitDialog()
{
    CDialogEx::OnInitDialog();
    return TRUE;
}
BEGIN_MESSAGE_MAP(AboutDlg, CDialogEx)
    ON_BN_CLICKED(IDC_RUN_BTN, &AboutDlg::OnBnClickedRunBtn)
END_MESSAGE_MAP()
void AboutDlg::OnBnClickedRunBtn() {}
''')

# 実プロジェクト (DoubleBufferSample) で見つかった誤検出の形: 継承したハンドラ・宣言の末尾の final・入れ子クラスのマップ・
# 基底 (MFC) が持つ ON_WM_xxx・ON_WM_CTLCOLOR_REFLECT。いずれも、指摘が出てはならない
w("good/App/Derived.h", '''#pragma once
class BaseView : public CView
{
    DECLARE_MESSAGE_MAP()
public:
    afx_msg void OnKeyDown(UINT nChar, UINT nRepCnt, UINT nFlags);
    afx_msg virtual void OnRButtonDblClk(UINT nFlags, CPoint point) final;
};
class DerivedView : public BaseView
{
    DECLARE_MESSAGE_MAP()
};
class Outer
{
    class InnerEdit : public CEdit
    {
        DECLARE_MESSAGE_MAP()
    public:
        afx_msg HBRUSH CtlColor(CDC* pDC, UINT nCtlColor);
        afx_msg void OnEnChange();
    };
};
''')
w("good/App/Derived.cpp", '''#include "Derived.h"
BEGIN_MESSAGE_MAP(BaseView, CView)
    ON_WM_RBUTTONDBLCLK()
    ON_WM_PAINT()
END_MESSAGE_MAP()
BEGIN_MESSAGE_MAP(DerivedView, BaseView)
    ON_WM_KEYDOWN()
END_MESSAGE_MAP()
BEGIN_MESSAGE_MAP(Outer::InnerEdit, CEdit)
    ON_WM_CTLCOLOR_REFLECT()
    ON_CONTROL_REFLECT(EN_CHANGE, &Outer::InnerEdit::OnEnChange)
END_MESSAGE_MAP()
void BaseView::OnKeyDown(UINT nChar, UINT nRepCnt, UINT nFlags) {}
void BaseView::OnRButtonDblClk(UINT nFlags, CPoint point) {}
HBRUSH Outer::InnerEdit::CtlColor(CDC* pDC, UINT nCtlColor) { return nullptr; }
void Outer::InnerEdit::OnEnChange() {}
''')

# ---------------- 問題だらけのプロジェクト ----------------
w("bad/App/App.vcxproj", VCX % ("Application", ""))
w("bad/App/resource.h", '''#define IDR_MAINFRAME 128
#define IDD_ONE 101
#define IDD_TWO 101
#define IDC_X 1000
#define IDC_Y 1000
#define IDC_NODLG 1002
#define IDC_NOCTRL 1003
#define ID_A 32771
#define ID_B 32771
#define ID_NOUI 32773
#define ID_UNUSED 32799
#define IDD_FORM 102
#define IDC_EDIT1 1010
#define IDC_GO 1011
#define IDC_DEF2 1012
#define IDC_CHK 1013
#define IDC_GONE 1014
''')
w("bad/App/App.rc", '''#include "resource.h"
IDR_MAINFRAME MENU
BEGIN
    POPUP "&T"
    BEGIN
        MENUITEM "A",   ID_A
        MENUITEM "B",   ID_B
        MENUITEM "U",   ID_UNDEFINED
    END
END
IDR_NAMED MENU
BEGIN
    MENUITEM "N",   ID_A
END
IDD_ONE DIALOGEX 0, 0, 100, 100
BEGIN
    PUSHBUTTON      "X",IDC_X,10,10,50,14
    PUSHBUTTON      "Y",IDC_Y,10,30,50,14
END
IDD_TWO DIALOGEX 0, 0, 100, 100
BEGIN
    DEFPUSHBUTTON   "OK",IDOK,10,10,50,14
END
IDD_FORM DIALOGEX 0, 0, 100, 120
BEGIN
    EDITTEXT        IDC_EDIT1,10,10,50,14
    PUSHBUTTON      "Go",IDC_GO,10,30,50,14
    DEFPUSHBUTTON   "OK",IDOK,10,50,50,14
    DEFPUSHBUTTON   "&Alt",IDC_DEF2,10,70,50,14
    CHECKBOX        "&Allow",IDC_CHK,10,90,50,14
END
IDD_OLD AFX_DIALOG_LAYOUT
BEGIN
    0
END
GUIDELINES DESIGNINFO
BEGIN
    IDD_GHOST, DIALOG
    BEGIN
        LEFTMARGIN, 7
    END
END
''', "utf-16")
w("bad/App/BadView.h", '''#pragma once
class BadView : public CView
{
    DECLARE_MESSAGE_MAP()
public:
    afx_msg void OnB();
    afx_msg void OnWrong(int x);
    afx_msg void OnOrphan();
    void OnNoAfx();
    afx_msg void OnNoUi();
    afx_msg void OnNoDlg();
    afx_msg void OnA();
    afx_msg void OnA2();
    void DoDataExchange(CDataExchange* pDX);
};
class NoDecl : public CView
{
public:
    int x;
};
class NoMap : public CView
{
    DECLARE_MESSAGE_MAP()
};
''')
w("bad/App/BadView.cpp", '''#include "BadView.h"
BEGIN_MESSAGE_MAP(BadView, CView)
    ON_COMMAND(ID_A, &BadView::OnA)
    ON_COMMAND(ID_A, &BadView::OnA2)
    ON_COMMAND(ID_B, &BadView::OnB)
    ON_COMMAND(ID_NOUI, &BadView::OnNoUi)
    ON_COMMAND(ID_NOTDECLARED, &BadView::OnNotDeclared)
    ON_COMMAND(ID_WRONG, &BadView::OnWrong)
    ON_COMMAND(ID_NOAFX, &BadView::OnNoAfx)
    ON_BN_CLICKED(IDC_NODLG, &BadView::OnNoDlg)
END_MESSAGE_MAP()
BEGIN_MESSAGE_MAP(NoDecl, CView)
END_MESSAGE_MAP()
void BadView::OnA() {}
void BadView::OnA2() {}
void BadView::OnWrong(int x) {}
void BadView::OnNoAfx() {}
void BadView::OnNoUi() {}
void BadView::OnNoDlg() {}
void BadView::DoDataExchange(CDataExchange* pDX)
{
    DDX_Control(pDX, IDC_NOCTRL, m_ctrl);
}
''')

w("bad/App/BadDlg.h", '''#pragma once
class FormDlg : public CDialog
{
public:
    enum { IDD = IDD_FORM };
    CListCtrl m_edit;
    CButton m_a;
    CString m_text;
    virtual BOOL OnInitDialog();
    virtual void DoDataExchange(CDataExchange* pDX);
};
class MissingDlg : public CDialogEx
{
public:
    enum { IDD = IDD_MISSING };
};
''')
w("bad/App/BadDlg.cpp", '''#include "BadDlg.h"
BOOL FormDlg::OnInitDialog() { return TRUE; }
void FormDlg::DoDataExchange(CDataExchange* pDX)
{
    DDX_Control(pDX, IDC_EDIT1, m_edit);
    DDX_Text(pDX, IDC_GONE, m_text);
    DDX_Control(pDX, IDC_DEF2, m_a);
    DDX_Control(pDX, IDC_CHK, m_a);
}
''')

# ---------------- 層の依存 ----------------
w("layers/Main/Main.vcxproj", VCX % ("Application", ""))
w("layers/Main/Main.cpp", "int main() { return 0; }\n")
w("layers/LogicLayer/LogicLayer.vcxproj", VCX % ("DynamicLibrary", refs("Main")))
w("layers/LogicLayer/Logic.cpp", '#include <afxwin.h>\nvoid f() { CWnd* w = nullptr; }\n')
w("layers/LogicLayer/pch.h", '#include <afxwin.h>\n')
w("layers/DataLayer/DataLayer.vcxproj", VCX % ("StaticLibrary", refs("LogicLayer")))
w("layers/DataLayer/Data.cpp", "int g() { return 1; }\n")
w("ok-layers/Main/Main.vcxproj", VCX % ("Application", refs("LogicLayer")))
w("ok-layers/LogicLayer/LogicLayer.vcxproj", VCX % ("DynamicLibrary", refs("DataLayer") + defs("_AFXEXT")))
w("ok-layers/LogicLayer/Logic.cpp", '#include <afx.h>\n#include <afxtempl.h>\nCString f() { return CString(); }\n')
w("ok-layers/LogicLayer/dllmain.cpp", EXT_MAIN)
w("ok-layers/DataLayer/DataLayer.vcxproj", VCX % ("StaticLibrary", ""))
w("ok-layers/DataLayer/Data.cpp", "int g() { return 1; }\n")

# ---------------- MFC の DLL の設定 (DLL001〜DLL008) ----------------
w("dll-ok/App/App.vcxproj", vcx("Application", refs("ExtOk", "StdOk")))
w("dll-ok/App/main.cpp", "int main() { return 0; }\n")
w("dll-ok/ExtOk/ExtOk.vcxproj", vcx("DynamicLibrary", defs("_AFXEXT")))
w("dll-ok/ExtOk/dllmain.cpp", EXT_MAIN)
w("dll-ok/StdOk/StdOk.vcxproj", vcx("DynamicLibrary", defs("_USRDLL")))
w("dll-ok/StdOk/StdOk.cpp", STD_APP)
w("dll-ok/StdOk/Api.h", STD_API_H)
w("dll-ok/StdOk/Func.cpp", STD_OK_CPP)
w("dll-ok/StdStaticOk/StdStaticOk.vcxproj", vcx("DynamicLibrary", defs("_USRDLL"), "Static"))
w("dll-ok/StdStaticOk/StdStaticOk.cpp", STD_APP)
w("dll-ok/StdStaticOk/Api.h", STD_API_H)
w("dll-ok/StdStaticOk/Func.cpp", '#include "Api.h"\nint Foo()\n{\n    return 1;\n}\nconst char* Bar(int x)\n{\n    return "a";\n}\n')
w("dll-ok/Plain/Plain.vcxproj", vcx("DynamicLibrary", defs("_USRDLL"), "false"))
w("dll-ok/Plain/Plain.cpp", "int Plain() { return 1; }\n")

w("dll-bad/Both/Both.vcxproj", vcx("DynamicLibrary", defs("_USRDLL;_AFXEXT")))
w("dll-bad/Both/dllmain.cpp", EXT_MAIN)
w("dll-bad/ExtStatic/ExtStatic.vcxproj", vcx("DynamicLibrary", defs("_AFXEXT"), "Static"))
w("dll-bad/ExtStatic/dllmain.cpp", EXT_MAIN)
w("dll-bad/ExtNoInit/ExtNoInit.vcxproj", vcx("DynamicLibrary", defs("_AFXEXT")))
w("dll-bad/ExtNoInit/a.cpp", "int f() { return 1; }\n")
w("dll-bad/ExtNoTerm/ExtNoTerm.vcxproj", vcx("DynamicLibrary", defs("_AFXEXT")))
w("dll-bad/ExtNoTerm/dllmain.cpp", '#include <afxwin.h>\n#include <afxdllx.h>\nstatic AFX_EXTENSION_MODULE ExtDLL = { false, nullptr };\nextern "C" int APIENTRY DllMain(HINSTANCE h, DWORD r, LPVOID)\n{\n    if (r == DLL_PROCESS_ATTACH) { AfxInitExtensionModule(ExtDLL, h); }\n    return 1;\n}\n')
w("dll-bad/NoKind/NoKind.vcxproj", vcx("DynamicLibrary"))
w("dll-bad/NoKind/a.cpp", "int f() { return 1; }\n")
w("dll-bad/StdNoApp/StdNoApp.vcxproj", vcx("DynamicLibrary", defs("_USRDLL")))
w("dll-bad/StdNoApp/a.cpp", "int f() { return 1; }\n")
w("dll-bad/StdNoState/StdNoState.vcxproj", vcx("DynamicLibrary", defs("_USRDLL")))
w("dll-bad/StdNoState/App.cpp", STD_APP)
w("dll-bad/StdNoState/Api.h", STD_API_H)
w("dll-bad/StdNoState/Func.cpp", '#include "Api.h"\n#include <afxwin.h>\nint Foo()\n{\n    return 1;\n}\nconst char* Bar(int x)\n{\n    CString s;\n    AFX_MANAGE_STATE(AfxGetStaticModuleState());\n    return "a";\n}\n')
w("dll-bad/MainStatic/MainStatic.vcxproj", vcx("Application", refs("ExtOk"), "Static"))
w("dll-bad/MainStatic/main.cpp", "int main() { return 0; }\n")
w("dll-bad/MainNoMfc/MainNoMfc.vcxproj", vcx("Application", refs("ExtOk"), "false"))
w("dll-bad/MainNoMfc/main.cpp", "int main() { return 0; }\n")
w("dll-bad/ExtOk/ExtOk.vcxproj", vcx("DynamicLibrary", defs("_AFXEXT")))
w("dll-bad/ExtOk/dllmain.cpp", EXT_MAIN)
# ---------------- UI004 (UI テストのプロジェクトがあるときの、IDC_STATIC のままの操作対象) ----------------
RC_UI = '''#include "resource.h"
#include "afxres.h"
IDD_MAIN DIALOGEX 0, 0, 200, 120
CAPTION "Main"
FONT 9, "MS Shell Dlg", 0, 0, 0x1
BEGIN
    DEFPUSHBUTTON   "OK",IDOK,10,10,50,14
    PUSHBUTTON      "Run",IDC_STATIC,10,30,50,14
    EDITTEXT        -1,10,50,80,14,ES_AUTOHSCROLL
    COMBOBOX        IDC_COMBO1,10,70,80,60,CBS_DROPDOWN
    COMBOBOX        IDC_COMBO1,10,90,80,60,CBS_DROPDOWN
    GROUPBOX        "Group",IDC_STATIC,5,5,190,100
    LTEXT           "label",IDC_STATIC,100,10,40,8
    CONTROL         "check",IDC_STATIC,"Button",BS_AUTOCHECKBOX | WS_TABSTOP,100,30,50,10
    CONTROL         "box",IDC_STATIC,"Button",BS_GROUPBOX,100,50,50,30
END
'''
RC_UI_OK = RC_UI.replace('PUSHBUTTON      "Run",IDC_STATIC', 'PUSHBUTTON      "Run",IDC_RUN_BTN').replace('EDITTEXT        -1', 'EDITTEXT        IDC_NAME_EDIT').replace('COMBOBOX        IDC_COMBO1,10,90', 'COMBOBOX        IDC_COMBO2,10,90').replace('"check",IDC_STATIC', '"check",IDC_CHECK1')
RES_UI = "#define IDD_MAIN 101\n#define IDC_RUN_BTN 1001\n#define IDC_NAME_EDIT 1002\n#define IDC_COMBO1 1003\n#define IDC_COMBO2 1004\n#define IDC_CHECK1 1005\n"
UITESTS = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0-windows</TargetFramework></PropertyGroup></Project>'
for d, rc, ut in (("ui1", RC_UI, True), ("ui2", RC_UI, False), ("ui3", RC_UI_OK, True)):
    w(d + "/App/App.vcxproj", VCX % ("Application", ""))
    w(d + "/App/App.rc", rc, "utf-16")
    w(d + "/App/resource.h", RES_UI)
    w(d + "/App/App.cpp", "int main() { return 0; }\n")
    if ut:
        w(d + "/App.UITests/App.UITests.csproj", UITESTS)
w("empty/readme.txt", "no mfc here\n")
PYEOF

# ---- 正常なプロジェクト: 指摘なし (誤検出なし) ----
out="$(python3 -I "$S" "$T/good" --all)"; rc=$?
ok "good: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "good: no findings (error 0 / warning 0 / info 0)" "$(has "$out" 'error 0 / warning 0 / info 0')"

# ---- UI004: UI テストのプロジェクトがあるとき、操作するコントロールの ID が IDC_STATIC のまま ----
out="$(python3 -I "$S" "$T/ui1" --all --max-lines 100)"
ok "UI004: PUSHBUTTON with IDC_STATIC" "$(has "$out" 'warning UI004 ダイアログ IDD_MAIN の操作できるコントロール (PUSHBUTTON "Run") の ID が IDC_STATIC のまま')"
ok "UI004: EDITTEXT with -1" "$(has "$out" '(EDITTEXT) の ID が -1 のまま')"
ok "UI004: CONTROL Button (checkbox) with IDC_STATIC" "$(has "$out" '(CONTROL "check") の ID が IDC_STATIC のまま')"
ok "UI004: duplicated control ID" "$(has "$out" 'コントロール ID IDC_COMBO1 が重複している')"
ok "UI004: exactly 4 findings (group box, static text and group-box CONTROL are not reported)" "$([ "$(grep -c ' UI004 ' <<<"$out")" = 4 ] && echo 1 || echo 0)"
out="$(python3 -I "$S" "$T/ui2" --all --max-lines 100)"
ok "UI004: not reported without a UITests project" "$([ "$(has "$out" ' UI004 ')" = 0 ] && echo 1 || echo 0)"
out="$(python3 -I "$S" "$T/ui3" --all --max-lines 100)"
ok "UI004: not reported when the controls have their own IDs" "$([ "$(has "$out" ' UI004 ')" = 0 ] && echo 1 || echo 0)"

# ---- 問題だらけのプロジェクト: 各ルールが、検出される ----
out="$(python3 -I "$S" "$T/bad" --all --max-lines 200 --json "$T/bad.json")"; rc=$?
ok "bad: rc=1 (error あり)" $([ $rc = 1 ] && echo 1 || echo 0)
for code in RES001 RES002 RES003 RES004 RES005 MAP001 MAP002 MAP003 MAP004 MAP005 MAP006 MAP007 MAP008 UI001 UI002 UI003 DLG001 DLG002 DLG003 DLG004 DLG005 DLG006 DLG007 DLG008 DLG009 DLG010; do
    ok "bad: $code detected" "$(has "$out" " $code ")"
done
ok "bad: RES001 undefined ID is an error" "$(has "$out" 'error   RES001 未定義の ID: ID_UNDEFINED')"
ok "bad: RES001 named resource is only a warning" "$(has "$out" 'warning RES001 名前付きリソース: IDR_NAMED')"
ok "bad: RES002 names both IDs" "$(has "$out" 'ID_A=32771 と ID_B=32771')"
ok "bad: RES003 names the dialog" "$(has "$out" 'ダイアログ IDD_ONE')"
ok "bad: MAP001 for the undeclared handler" "$(has "$out" 'BadView::OnNotDeclared: メッセージマップにあるが、クラス (とプロジェクト内の基底クラス) に宣言されていない')"
ok "bad: MAP002 for the declared-only handler" "$(has "$out" 'BadView::OnB: 宣言されているが、定義が見つからない')"
ok "bad: MAP006 reports the parameter count" "$(has "$out" 'BadView::OnWrong: 引数の数が 1 個。ON_COMMAND の想定は 0 個')"
ok "bad: DLG001 DDX ID missing in the class's own dialog" "$(has "$out" 'FormDlg: DDX_Text の ID IDC_GONE が、ダイアログ IDD_FORM にない')"
ok "bad: DLG002 IDD not in .rc" "$(has "$out" 'MissingDlg: ダイアログ ID IDD_MISSING が .rc にない')"
ok "bad: DLG003 DDX_Control type vs control kind" "$(has "$out" 'DDX_Control(IDC_EDIT1, m_edit) の型 CListCtrl')"
ok "bad: DLG004 button without handler" "$(has "$out" 'ボタン IDC_GO に、ハンドラがない')"
ok "bad: DLG004 not reported for IDOK / default buttons handled by the base" "$([ "$(grep -c 'ボタン IDOK' <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "bad: DLG010 same member bound twice (names both IDs)" "$(has "$out" 'DDX_Control のメンバー m_a が、IDC_DEF2 と IDC_CHK の両方に渡されている')"
ok "bad: DLG010 is not reported for a member bound once" "$([ "$(grep -c 'DLG010' <<<"$out")" = 1 ] && echo 1 || echo 0)"
ok "bad: DLG005 two default buttons" "$(has "$out" 'ダイアログ IDD_FORM に、既定ボタンが 2 個ある')"
ok "bad: DLG006 OnInitDialog without base call" "$(has "$out" 'FormDlg::OnInitDialog が、基底クラスの OnInitDialog を呼んでいない')"
ok "bad: DLG007 DoDataExchange without base call" "$(has "$out" 'FormDlg::DoDataExchange が、基底クラスの DoDataExchange を呼んでいない')"
ok "bad: DLG008 duplicate mnemonic" "$(has "$out" 'ニーモニック &A が重複')"
ok "bad: UI003 skipped for DDX already checked as DLG001 (no double report)" "$([ "$(grep -c 'DDX/DDV のコントロール ID IDC_GONE' <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "bad: UI003 still reported for DDX in a non-dialog class" "$(has "$out" 'DDX/DDV のコントロール ID IDC_NOCTRL')"
ok "bad: DLG009 stale AFX_DIALOG_LAYOUT" "$(has "$out" 'AFX_DIALOG_LAYOUT IDD_OLD に対応するダイアログがない')"
ok "bad: stale layout is not reported as RES001" "$([ "$(grep -c 'RES001.*IDD_OLD' <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "bad: IDs in DESIGNINFO are not 'used' (no RES001 for IDD_GHOST)" "$([ "$(grep -c 'IDD_GHOST' <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "bad: standard IDs (IDOK) are not reported as undefined" "$([ "$(grep -c '未定義の ID: IDOK' <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "bad: json written" "$(python3 -c "import json,sys; d=json.load(open('$T/bad.json')); sys.exit(0 if d['counts']['error']>=8 and d['findings'] else 1)" && echo 1 || echo 0)"
out="$(python3 -I "$S" "$T/bad")"
ok "bad: info hidden by default" "$([ "$(grep -c ' info ' <<<"$out")" = 0 ] && echo 1 || echo 0)"

# ---- 層の依存 ----
out="$(python3 -I "$S" "$T/layers" --all --max-lines 100)"; rc=$?
ok "layers: rc=1" $([ $rc = 1 ] && echo 1 || echo 0)
ok "layers: LAY003 logic -> main" "$(has "$out" 'LogicLayer (logic) が Main (main) を参照している')"
ok "layers: LAY003 data -> logic" "$(has "$out" 'DataLayer (data) が LogicLayer (logic) を参照している')"
ok "layers: LAY001 GUI class in a library" "$(has "$out" 'GUI のクラス/関数 CWnd')"
ok "layers: LAY002 GUI header in a source file is a warning" "$(has "$out" 'warning LAY002')"
ok "layers: LAY002 in pch.h is only info" "$(has "$out" 'info    LAY002')"
out="$(python3 -I "$S" "$T/ok-layers" --all)"; rc=$?
ok "ok-layers: rc=0, no findings" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 / warning 0')" = 1 ] && echo 1 || echo 0)"

# ---- MFC の DLL の設定 ----
out="$(python3 -I "$S" "$T/dll-ok" --all --max-lines 100)"; rc=$?
ok "dll-ok: rc=0, error / warning なし、DLL の指摘なし (拡張 DLL・標準 DLL (共有/静的)・MFC なしの DLL が、正常。MFC の DLL の afxwin.h は、info の LAY002 だけ)" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 / warning 0')" = 1 ] && [ "$(grep -c ' DLL0' <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "dll-ok: MFC の DLL の LAY002 は info (warning にしない)" "$([ "$(has "$out" 'info    LAY002')" = 1 ] && [ "$(has "$out" 'warning LAY002')" = 0 ] && echo 1 || echo 0)"
out="$(python3 -I "$S" "$T/dll-bad" --all --max-lines 100)"; rc=$?
ok "dll-bad: rc=1" "$([ $rc = 1 ] && echo 1 || echo 0)"
ok "dll-bad: DLL001 _USRDLL と _AFXEXT の併用" "$(has "$out" 'Both: _USRDLL と _AFXEXT が、同じ構成で、両方')"
ok "dll-bad: DLL002 拡張 DLL で UseOfMfc が Dynamic でない" "$(has "$out" 'ExtStatic: MFC 拡張 DLL (_AFXEXT) だが、UseOfMfc が Dynamic でない')"
ok "dll-bad: DLL003 MFC 有効なのに _USRDLL も _AFXEXT もない" "$(has "$out" 'NoKind: UseOfMfc が有効だが')"
ok "dll-bad: DLL004 標準 DLL に CWinApp 派生がない" "$(has "$out" 'StdNoApp: MFC 標準 DLL に、CWinApp 派生')"
ok "dll-bad: DLL005 拡張 DLL に AfxInitExtensionModule がない" "$(has "$out" 'ExtNoInit: MFC 拡張 DLL に、DllMain の AfxInitExtensionModule がない')"
ok "dll-bad: DLL006 CDynLinkLibrary がない" "$(has "$out" 'ExtNoTerm: MFC 拡張 DLL に、new CDynLinkLibrary がない')"
ok "dll-bad: DLL006 AfxTermExtensionModule がない" "$(has "$out" 'ExtNoTerm: MFC 拡張 DLL に、AfxTermExtensionModule がない')"
ok "dll-bad: DLL007 AFX_MANAGE_STATE がない公開関数 (Foo)" "$(has "$out" '公開関数 Foo が、先頭で AFX_MANAGE_STATE を呼んでいない')"
ok "dll-bad: DLL007 AFX_MANAGE_STATE が先頭でない公開関数 (Bar)" "$(has "$out" '公開関数 Bar が、先頭で AFX_MANAGE_STATE を呼んでいない')"
ok "dll-bad: DLL008 静的 MFC のメインが拡張 DLL を参照" "$(has "$out" 'MainStatic: MFC 拡張 DLL ExtOk を参照しているが')"
ok "dll-bad: DLL008 MFC なしのメインが拡張 DLL を参照" "$(has "$out" 'MainNoMfc: MFC 拡張 DLL ExtOk を参照しているが')"
ok "dll-bad: 正常なプロジェクト (ExtOk) には、指摘が出ない" "$([ "$(grep -c 'ExtOk: ' <<<"$out")" = 0 ] && echo 1 || echo 0)"

# ---- 例外系 ----
out="$(python3 -I "$S" "$T/empty")"; rc=$?
ok "empty dir: rc=3, 'nothing to check'" "$([ $rc = 3 ] && [ "$(has "$out" 'nothing to check')" = 1 ] && echo 1 || echo 0)"
out="$(python3 -I "$S" "$T/no-such-dir")"; rc=$?
ok "bad args: rc=2" $([ $rc = 2 ] && echo 1 || echo 0)

# ---- 実プロジェクト (あれば。クラッシュしないこと。件数は問わない) ----
REAL="/mnt/c/workspace/macsignee/source/repos/cppsamples"
if [ -d "$REAL/GDiGraphicsSample" ]; then
    for d in CppSamples GDiGraphicsSample XMLiteSampleApp CharEncordingSample; do
        python3 -I "$S" "$REAL/$d" >/dev/null 2>"$T/err.txt"; rc=$?
        ok "real project $d: no crash (rc=$rc)" "$([ $rc -le 1 ] && [ ! -s "$T/err.txt" ] && echo 1 || echo 0)"
    done
fi

REAL2="/mnt/c/workspace/macsignee/source/repos/DoubleBufferSample"
if [ -d "$REAL2/DoubleBufferSample" ]; then
    out="$(python3 -I "$S" "$REAL2" 2>"$T/err2.txt")"; rc=$?
    # ソースに未コミットの変更がある間 (例: 確認のための一時的な編集) は、error が出てよい。クラッシュしないことだけを見る
    dirty="$(git -C "$REAL2" --no-optional-locks -c core.fileMode=false status --porcelain -- 'DoubleBufferSample/*.cpp' 'DoubleBufferSample/*.h' 'DoubleBufferSample/*.rc' 2>/dev/null)"
    if [ -z "$dirty" ]; then
        ok "real DoubleBufferSample: no crash, rc=0 (誤検出で error が出ない)" "$([ $rc = 0 ] && [ ! -s "$T/err2.txt" ] && echo 1 || echo 0)"
    else
        ok "real DoubleBufferSample: no crash (ソースに未コミットの変更があるので、rc は問わない)" "$([ $rc -le 1 ] && [ ! -s "$T/err2.txt" ] && echo 1 || echo 0)"
    fi
fi

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
