#!/usr/bin/env python3
"""new_solution.py - フォルダの中に、「フォルダ名と同名の .slnx」と、メインのプロジェクト (と、必要なら層・テスト) を作る。

Usage:
  新規:        python3 new_solution.py <FOLDER> --type mfc|mfc-mdi|mfc-dialog|win32|console|dll|lib --layers none|logic|data|logic,data
                                       --tests none|gtest [--layer-kind dll|lib] [--namespace NS] [--toolset v145]
                                       [--gtest auto|vcpkg|source|nuget] [--gtest-from DIR] [--dry-run]
               WPF (.NET): python3 new_solution.py <FOLDER> --type wpf --layers none|data|logic|viewmodel の組み合わせ --tests none|mstest
                                       [--namespace NS] [--tfm net10.0] [--mstest-version V] [--testsdk-version V] [--dry-run]
                           (層は、WPF 非依存のクラスライブラリ。viewmodel を作らないと、ViewModel は、アプリの中)
               または、--spec <仕様書> で、仕様書の「構成案」から、省略した項目を読み取る (明示した引数が優先)
  改行コードの規則 (.gitattributes) の確認と追加 (すでにあるプロジェクト用):
               python3 new_solution.py <FOLDER> --check-git          (読み取りだけ。状態と、提案の要否を出す)
               python3 new_solution.py <FOLDER> --add-gitattributes  (最小版の .gitattributes を作る。git の操作は、しない)
  テストの後付け: python3 new_solution.py <FOLDER> --tests gtest [--gtest auto|vcpkg|source|nuget] [--gtest-from DIR] [--dry-run]
                 (すでにソリューションがあるフォルダで。テストのない DLL に、対応するテスト exe を足す)
                 .NET のソリューションなら: python3 new_solution.py <FOLDER> --tests mstest [--dry-run]
                 (テストのないクラスライブラリに、<名前>.Tests を足す)

  FOLDER   ソリューションを作るフォルダ。**フォルダ名が、ソリューション名・メインのプロジェクト名になる**
           (例: .../MFCTDDTest -> MFCTDDTest.slnx と、MFCTDDTest/MFCTDDTest.vcxproj)
  --type   メインの種類: mfc (MFC SDI) / mfc-mdi (MFC MDI) / mfc-dialog (MFC ダイアログベース) / win32 (Win32 デスクトップ) / console / dll / lib (静的ライブラリ)
           / winforms (WinForms、MVP。.NET。Form は IMainView を実装し、MainPresenter が振る舞いを持つ。層は data / logic だけ)
           / csharp-dll (C# のクラスライブラリ。.NET。メイン自身が、テスト (MSTest) の対象。層は data / logic だけ)
           / wpf (WPF、MVVM。.NET。ソリューションは .slnx、各プロジェクトは SDK 形式の .csproj。NuGet の復元は、ウォッチャーのビルドが行う)
  --layers 作る層: logic -> LogicLayer、data -> DataLayer。none は、層を作らない。
           名前を変えるなら logic:OrderLogic,data:OrderData のように指定する (省略時の既定の名前は、作成後に変更もできる)
  --layer-kind 層の種類: dll (既定) / lib (静的ライブラリ)。全部の層に、同じ種類を使う
  --tests  gtest: 作った DLL / 静的ライブラリ (層と、メインが dll / lib ならメイン) に、<名前>Test (GoogleTest の exe) を作る。none: テストを作らない
  --gtest  GoogleTest の入れ方: auto (既定。vcpkg。すでに gtest プロジェクトがあれば source、packages\\ に NuGet パッケージがあれば nuget) /
           vcpkg (vcpkg.json に gtest を入れ、テスト exe に main.cpp を置く。baseline と install は、ウォッチャー経由: package_once.sh) /
           source (ThirdParty/googletest をビルド。ソースは、ウォッチャー経由で取得する: gtest_once.sh) / nuget (旧方式。既存の packages\\ をコピーする)
  --spec   仕様書 (docs/specs/*.md) の「## 構成案」の、次の行を読む: - メインの種類: / - 層: / - 層の種類: / - テスト: / - 名前空間: / - UIテスト: (none | flaui) / - TFM: (.NET のみ。例 net10.0)
           新規作成のときは、さらに、仕様書を取り込む (spec_import.py): 仕様書と「元:」のメモを docs/specs/・docs/ideas/ に置く (すでにあれば、そのまま)、
           「具体例」「境界値と異常系」の表から、テストケースの種 docs/specs/<名前>.cases.md を作る、CLAUDE.md に「## 仕様書」の節を足す

組み合わせの注意: メインが exe で --layers none のとき、--tests gtest は、テスト対象がないので、エラー (終了コード 2)。
          メインが dll / lib なら、メイン自身がテスト対象。
新規作成では、CLAUDE.md / .gitignore / .gitattributes (改行コードの規則。拡張子を列挙しない最小版) も作る (どれも、すでにあれば、上書きしない)。
テストの後付け (すでにソリューションがある) では、これらを作らない。
x64 の Debug / Release だけ。GoogleTest の vcpkg 方式は、vcpkg.json を書くだけで、取得はしない (このスクリプトは、ネットワークを使わない)。nuget 方式は、既存の packages\\ をコピーする。

終了コード: 0 成功 / 2 引数・組み合わせ・フォルダの問題 / 3 すでにある (何も書かない)
このスクリプトは、同じ skills フォルダの cpp-test-first/scripts/add_layer.py (C++) と、wpf-test-first/scripts/add_project.py (WPF) を、読み込んで使う
(WPF のものは、--type wpf / --tests mstest のときだけ、読み込む)。
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'cpp-test-first', 'scripts'))
try:
    import add_layer as AL
except ImportError:
    print('ERROR: cpp-test-first/scripts/add_layer.py が見つからない (cpp-test-first Skill も、配布されている必要がある)')
    sys.exit(2)

die = AL.die
KIND = {'wpf': 'WPF (MVVM)', 'winforms': 'WinForms (MVP)', 'csharp-dll': 'C# クラスライブラリ', 'mfc': 'MFC SDI', 'mfc-mdi': 'MFC MDI', 'mfc-dialog': 'MFC ダイアログ', 'win32': 'Win32 デスクトップ', 'console': 'コンソール', 'dll': 'DLL', 'lib': '静的ライブラリ'}
DOTNET_TYPES = ('wpf', 'winforms', 'csharp-dll')
MFC_TYPES = ('mfc', 'mfc-mdi', 'mfc-dialog')   # MFC の exe (mfc は SDI)
EXE_TYPES = ('console', 'win32') + MFC_TYPES    # exe の種類 (名前が Test で終わると、出力名を変える)
LIBRARY_TYPES = ('dll', 'lib')   # メイン自身が、テストの対象になる種類
LAYER_NAMES = {'data': 'DataLayer', 'logic': 'LogicLayer'}   # 作る順 (依存される側から)
WPF_LAYER_NAMES = {'data': 'DataLayer', 'logic': 'LogicLayer', 'viewmodel': 'ViewModels'}
WPF_LAYER_ORDER = ('data', 'logic', 'viewmodel')

# ---------------- メイン (exe) のソース ----------------
CONSOLE_MAIN = '''#include <iostream>

int main()
{
    std::cout << "@@NAME@@" << std::endl;
    return 0;
}
'''

WIN32_MAIN = '''#include <windows.h>
#include <cwchar>

namespace
{
    const wchar_t kClassName[] = L"@@NAME@@Window";

    LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
    {
        switch (msg)
        {
        case WM_PAINT:
        {
            PAINTSTRUCT ps;
            HDC hdc = ::BeginPaint(hWnd, &ps);
            const wchar_t text[] = L"@@NAME@@";
            ::TextOutW(hdc, 10, 10, text, static_cast<int>(std::wcslen(text)));
            ::EndPaint(hWnd, &ps);
            return 0;
        }
        case WM_DESTROY:
            ::PostQuitMessage(0);
            return 0;
        }
        return ::DefWindowProcW(hWnd, msg, wParam, lParam);
    }
}

int APIENTRY wWinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE, _In_ LPWSTR, _In_ int nCmdShow)
{
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.lpszClassName = kClassName;
    if (!::RegisterClassExW(&wc))
    {
        return 0;
    }

    HWND hWnd = ::CreateWindowW(kClassName, L"@@NAME@@", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, 0, CW_USEDEFAULT, 0, nullptr, nullptr, hInstance, nullptr);
    if (hWnd == nullptr)
    {
        return 0;
    }
    ::ShowWindow(hWnd, nCmdShow);
    ::UpdateWindow(hWnd);

    MSG msg;
    while (::GetMessageW(&msg, nullptr, 0, 0) > 0)
    {
        ::TranslateMessage(&msg);
        ::DispatchMessageW(&msg);
    }
    return static_cast<int>(msg.wParam);
}
'''

MFC_FILES = {
    'pch.h': '''#pragma once
#include <SDKDDKVer.h>
#include <afxwin.h>
#include <afxext.h>
''',
    'Resource.h': '''#pragma once
#define IDR_MAINFRAME           128
''',
    'SampleApp.h': '''#pragma once
#include "pch.h"

// アプリケーション本体 (UI 層)。
class CSampleApp : public CWinApp
{
public:
    BOOL InitInstance() override;
};
''',
    'SampleApp.cpp': '''#include "pch.h"
#include "SampleApp.h"
#include "MainFrame.h"
#include "SampleDoc.h"
#include "SampleView.h"
#include "Resource.h"

CSampleApp theApp;

BOOL CSampleApp::InitInstance()
{
    CWinApp::InitInstance();

    auto* pDocTemplate = new CSingleDocTemplate(
        IDR_MAINFRAME,
        RUNTIME_CLASS(CSampleDoc),
        RUNTIME_CLASS(CMainFrame),
        RUNTIME_CLASS(CSampleView));
    AddDocTemplate(pDocTemplate);

    CCommandLineInfo cmdInfo;
    cmdInfo.m_nShellCommand = CCommandLineInfo::FileNew;
    if (!ProcessShellCommand(cmdInfo))
    {
        return FALSE;
    }

    m_pMainWnd->ShowWindow(SW_SHOW);
    m_pMainWnd->UpdateWindow();
    return TRUE;
}
''',
    'MainFrame.h': '''#pragma once
#include "pch.h"

class CMainFrame : public CFrameWnd
{
    DECLARE_DYNCREATE(CMainFrame)
};
''',
    'MainFrame.cpp': '''#include "pch.h"
#include "MainFrame.h"

IMPLEMENT_DYNCREATE(CMainFrame, CFrameWnd)
''',
    'SampleDoc.h': '''#pragma once
#include "pch.h"

class CSampleDoc : public CDocument
{
    DECLARE_DYNCREATE(CSampleDoc)
};
''',
    'SampleDoc.cpp': '''#include "pch.h"
#include "SampleDoc.h"

IMPLEMENT_DYNCREATE(CSampleDoc, CDocument)
''',
    'SampleView.h': '''#pragma once
#include "pch.h"

class CSampleView : public CView
{
    DECLARE_DYNCREATE(CSampleView)

public:
    void OnDraw(CDC* pDC) override;
};
''',
    'SampleView.cpp': '''#include "pch.h"
#include "SampleView.h"

IMPLEMENT_DYNCREATE(CSampleView, CView)

void CSampleView::OnDraw(CDC* pDC)
{
    pDC->TextOut(10, 10, _T("@@NAME@@"));
}
''',
}

MFC_RC = '''#include "Resource.h"
#include "afxres.h"

LANGUAGE LANG_ENGLISH, SUBLANG_ENGLISH_US

IDR_MAINFRAME MENU
BEGIN
    POPUP "&File"
    BEGIN
        MENUITEM "E&xit",                   ID_APP_EXIT
    END
END

STRINGTABLE
BEGIN
    IDR_MAINFRAME           "@@NAME@@\\n\\n@@NAME@@\\n\\n\\n@@NAME@@.Document\\n@@NAME@@ Document"
END
'''

# ---- MFC MDI ----
MFC_MDI_FILES = {
    'pch.h': MFC_FILES['pch.h'],
    'Resource.h': '''#pragma once
#define IDR_MAINFRAME           128
#define IDR_SAMPLETYPE          129
''',
    'SampleApp.h': MFC_FILES['SampleApp.h'],
    'SampleApp.cpp': '''#include "pch.h"
#include "SampleApp.h"
#include "MainFrame.h"
#include "ChildFrame.h"
#include "SampleDoc.h"
#include "SampleView.h"
#include "Resource.h"

CSampleApp theApp;

BOOL CSampleApp::InitInstance()
{
    CWinApp::InitInstance();

    auto* pDocTemplate = new CMultiDocTemplate(
        IDR_SAMPLETYPE,
        RUNTIME_CLASS(CSampleDoc),
        RUNTIME_CLASS(CChildFrame),
        RUNTIME_CLASS(CSampleView));
    AddDocTemplate(pDocTemplate);

    auto* pMainFrame = new CMainFrame;
    if (!pMainFrame->LoadFrame(IDR_MAINFRAME))
    {
        delete pMainFrame;
        return FALSE;
    }
    m_pMainWnd = pMainFrame;

    CCommandLineInfo cmdInfo;
    cmdInfo.m_nShellCommand = CCommandLineInfo::FileNew;
    if (!ProcessShellCommand(cmdInfo))
    {
        return FALSE;
    }

    m_pMainWnd->ShowWindow(SW_SHOW);
    m_pMainWnd->UpdateWindow();
    return TRUE;
}
''',
    'MainFrame.h': '''#pragma once
#include "pch.h"

class CMainFrame : public CMDIFrameWnd
{
    DECLARE_DYNAMIC(CMainFrame)
};
''',
    'MainFrame.cpp': '''#include "pch.h"
#include "MainFrame.h"

IMPLEMENT_DYNAMIC(CMainFrame, CMDIFrameWnd)
''',
    'ChildFrame.h': '''#pragma once
#include "pch.h"

class CChildFrame : public CMDIChildWnd
{
    DECLARE_DYNCREATE(CChildFrame)
};
''',
    'ChildFrame.cpp': '''#include "pch.h"
#include "ChildFrame.h"

IMPLEMENT_DYNCREATE(CChildFrame, CMDIChildWnd)
''',
    'SampleDoc.h': MFC_FILES['SampleDoc.h'],
    'SampleDoc.cpp': MFC_FILES['SampleDoc.cpp'],
    'SampleView.h': MFC_FILES['SampleView.h'],
    'SampleView.cpp': MFC_FILES['SampleView.cpp'],
}

MFC_MDI_RC = '''#include "Resource.h"
#include "afxres.h"

LANGUAGE LANG_ENGLISH, SUBLANG_ENGLISH_US

IDR_MAINFRAME MENU
BEGIN
    POPUP "&File"
    BEGIN
        MENUITEM "E&xit",                   ID_APP_EXIT
    END
END

IDR_SAMPLETYPE MENU
BEGIN
    POPUP "&File"
    BEGIN
        MENUITEM "&New\\tCtrl+N",            ID_FILE_NEW
        MENUITEM "&Close",                  ID_FILE_CLOSE
        MENUITEM SEPARATOR
        MENUITEM "E&xit",                   ID_APP_EXIT
    END
    POPUP "&Window"
    BEGIN
        MENUITEM "&New Window",             ID_WINDOW_NEW
        MENUITEM "&Cascade",                ID_WINDOW_CASCADE
        MENUITEM "&Tile",                   ID_WINDOW_TILE_HORZ
        MENUITEM "&Arrange Icons",          ID_WINDOW_ARRANGE
    END
END

STRINGTABLE
BEGIN
    IDR_MAINFRAME           "@@NAME@@"
    IDR_SAMPLETYPE          "\\n@@NAME@@\\n@@NAME@@\\n\\n\\n@@NAME@@.Document\\n@@NAME@@ Document"
END
'''

# ---- MFC ダイアログベース ----
MFC_DIALOG_FILES = {
    'pch.h': MFC_FILES['pch.h'],
    'Resource.h': '''#pragma once
#define IDD_SAMPLE_DIALOG       101
''',
    'SampleApp.h': MFC_FILES['SampleApp.h'],
    'SampleApp.cpp': '''#include "pch.h"
#include "SampleApp.h"
#include "SampleDlg.h"

CSampleApp theApp;

BOOL CSampleApp::InitInstance()
{
    CWinApp::InitInstance();

    CSampleDlg dlg;
    m_pMainWnd = &dlg;
    dlg.DoModal();

    // ダイアログを閉じたら、メッセージループに入らずに、アプリケーションを終える。
    return FALSE;
}
''',
    'SampleDlg.h': '''#pragma once
#include "pch.h"
#include "Resource.h"

class CSampleDlg : public CDialog
{
public:
    enum { IDD = IDD_SAMPLE_DIALOG };

    explicit CSampleDlg(CWnd* pParent = nullptr);

protected:
    void DoDataExchange(CDataExchange* pDX) override;
    BOOL OnInitDialog() override;

    DECLARE_MESSAGE_MAP()
};
''',
    'SampleDlg.cpp': '''#include "pch.h"
#include "SampleDlg.h"

CSampleDlg::CSampleDlg(CWnd* pParent)
    : CDialog(IDD, pParent)
{
}

void CSampleDlg::DoDataExchange(CDataExchange* pDX)
{
    CDialog::DoDataExchange(pDX);
}

BOOL CSampleDlg::OnInitDialog()
{
    CDialog::OnInitDialog();
    return TRUE;
}

BEGIN_MESSAGE_MAP(CSampleDlg, CDialog)
END_MESSAGE_MAP()
''',
}

MFC_DIALOG_RC = '''#include "Resource.h"
#include "afxres.h"

LANGUAGE LANG_ENGLISH, SUBLANG_ENGLISH_US

IDD_SAMPLE_DIALOG DIALOGEX 0, 0, 240, 100
STYLE DS_SETFONT | DS_MODALFRAME | DS_FIXEDSYS | WS_POPUP | WS_CAPTION | WS_SYSMENU
CAPTION "@@NAME@@"
FONT 9, "MS Shell Dlg", 0, 0, 0x1
BEGIN
    DEFPUSHBUTTON   "OK",IDOK,129,79,50,14
    PUSHBUTTON      "Cancel",IDCANCEL,183,79,50,14
    LTEXT           "@@NAME@@",IDC_STATIC,7,7,226,8
END
'''

# --type -> (ソースの一式, .rc)
MFC_VARIANTS = {
    'mfc': (MFC_FILES, MFC_RC),
    'mfc-mdi': (MFC_MDI_FILES, MFC_MDI_RC),
    'mfc-dialog': (MFC_DIALOG_FILES, MFC_DIALOG_RC),
}

GITIGNORE = '''.vs/
x64/
obj/
*.user
# GoogleTest: vcpkg の取得結果 (vcpkg_installed/)、旧 NuGet 方式のパッケージ (packages\\ にコピーしたもの)、ソース方式のソース (ウォッチャーが取得したもの)
vcpkg_installed/
packages/
ThirdParty/googletest/
# ウォッチャーと Claude (Skill) が、ソリューションのフォルダに作る一時ファイル
.claude-logs/
trigger_*.flag
build_result.txt
build_error.log
test_result.txt
test_error.log
gtest_result.txt
gtest_error.log
'''


GITATTRIBUTES = """# 改行コードの規則。保存 (リポジトリ内) は LF に正規化し、作業フォルダは CRLF にする (Visual Studio の既定に合わせる)。
# WSL の git と Windows の Git の、どちらで操作しても、同じ結果になる (設定 core.autocrlf より、こちらが優先される)。
# 拡張子は列挙しない: text=auto が、中身から、テキストかバイナリかを自動で判定する (バイナリ・UTF-16 は、変換されない)。
* text=auto eol=crlf

# このファイル自身は、LF のまま
.gitattributes text eol=lf

# LF でないと動かないものだけを、例外として足す
*.sh text eol=lf

# 変換したくないものは、ここに足す (例: *.xyz -text)。後ろの行が、前の行より優先される。
"""


def claude_md(name, kind, layers, tests, layer_kind='dll', gtest_mode='vcpkg'):
    """layers: [(key, 名前), ...]"""
    default = all(nm == LAYER_NAMES[k] for k, nm in layers)
    layer_txt = ('なし' if not layers else
                 ','.join(k if default else f'{k}:{nm}' for k, nm in layers))
    test_txt = 'あり (GoogleTest)' if tests else 'なし'
    lk = '静的ライブラリ' if layer_kind == 'lib' else 'DLL'
    out = f"""# CLAUDE.md ({name})

C++ のプロトタイプ。ソリューション: `{name}.slnx` (フォルダ名と同名)。

## このソリューションの設定
- メイン: {name} ({kind})
- 層: {layer_txt}
- テスト: {test_txt}

(この 3 行は、スラッシュコマンド (`/brainstorm` `/add-feature` `/update-from-ideas`) が読む。手で変えるときは、実際の構成と合わせること。)

## 進め方 (スラッシュコマンド)
1. `/brainstorm`: 壁打ちで、考えを広げる (`docs/ideas/<機能名>.md`)。
2. `/update-from-ideas`: メモを整理して、正式な仕様書にする (`docs/specs/<機能名>.md`)。
3. `/add-feature <仕様書>`: 計画 → 承認 → 実装 (テストありなら、テスト先行の Red → Green) → 検証。
4. `/ui-test-first [画面の説明]`: (UI テストのプロジェクトがあるとき) 画面を、プロンプトで作りながら、UI テストを先に書いて、絞って (`--filter`)、繰り返し実行する。**UI テストは、ビルド → テストの流れには、含まれない** (求めたときと、このループだけ)。
"""
    if layers:
        out += f"""
## 層と依存の向き
UI / メイン → ロジック → データ (のインターフェース)
- ロジック層・データ層は、{lk}。生成される既定は、MFC を使わない通常の{lk}。MFC の型 (`CObject` 派生・シリアライズ) を持ち込む場合は、MFC 拡張 DLL にする (`cpp-test-first` の `DLL-LAYOUT.md`)。
- UI 層には、業務ルールを書かない。
- 層のプロジェクト名は、作成時に決めた名前 (既定は `LogicLayer` / `DataLayer`)。変更したら、この文書も直す。
"""
    out += r"""
## ビルド
- Windows 側のウォッチャー (`run_watcher.cmd`) 経由で、Skill (`auto-build` / `build-test-loop`) が行う。出力先: `x64\Debug\`。
- 新しい `.cpp` / `.h` は、`.vcxproj` (と `.filters`) に追加する。
"""
    if layers and kind not in (KIND['dll'], KIND['lib']):
        out += f"""- Visual Studio で実行 (F5) するときは、メインの `{name}` を、**スタートアッププロジェクトに設定する** (層は DLL / ライブラリなので、単体では起動できない)。`{name}.slnx` の `DefaultStartup="true"` で、最初に開くときは、メインが選ばれる。ただし、`.vs/` の個人の設定 (`.suo`) が、すでにあれば、そちらが優先される (DLL が選ばれていたら、メインを、右クリックの「スタートアップ プロジェクトに設定」で選び直す)。
"""
    if tests:
        out += r"""
## テスト (GoogleTest)
- DLL (または静的ライブラリ) ごとに、`<名前>Test.exe`。ウォッチャーは、`*Test.exe` を、すべて、テストとして実行する。
  メインが exe で、名前が `Test` で終わる場合は、出力名を `<名前>_Main.exe` にしてある (アプリが、テストとして起動されないように)。
"""
        if gtest_mode == 'source':
            out += r"""- GoogleTest は、**ソース** (`ThirdParty\googletest\`) を、ソリューション内の静的ライブラリ `gtest` としてビルドしている (NuGet 不要)。
  ソースは、ウォッチャー経由で取得する (`trigger_gtest.flag`。`gtest_once.sh`)。`ThirdParty/googletest/` は、`.gitignore` 済み (クローンし直したら、再取得する)。
"""
        elif gtest_mode == 'nuget':
            out += r"""- GoogleTest は、NuGet のパッケージを `packages\` にコピーしたもの (旧方式)。ウォッチャーは、NuGet を復元しない。
"""
        else:
            out += r"""- GoogleTest は、**vcpkg** (マニフェストモード。ソリューション直下の `vcpkg.json`、トリプレット `x64-windows-static-md`)。取得は、ウォッチャー経由
  (`package_once.sh <dir> --timeout 1800 'vcpkg baseline' 'vcpkg install'`。初回は、数十秒から数分)。`vcpkg_installed/` は、`.gitignore` 済み。
- テスト exe は、自前の `main.cpp` (`main()` を書いたもの) を持つ。vcpkg の `gtest_main` は、自動ではリンクされない。出力に「Running main() from ...」の行は出ない。
- GoogleTest は C++17 以上が必要 (プロジェクトは C++20)。
"""
    out += """
## 規約
- C++20。ファイルは UTF-8 (BOM 付き)、改行は CRLF。`.rc` は ASCII。
- `git commit` / `git push` は、ユーザーの指示があるときだけ。
"""
    return out


def update_claude_md_tests(folder, name, gmode='vcpkg'):
    """既存の CLAUDE.md の「テスト:」の行を、「あり (GoogleTest)」にする。なければ、追記する。"""
    p = os.path.join(folder, 'CLAUDE.md')
    if not os.path.isfile(p):
        return 'CLAUDE.md がない (何も更新していない)'
    text = open(p, encoding='utf-8').read()
    changed = False
    if re.search(r'^- テスト: .*$', text, re.M):
        new = re.sub(r'^- テスト: .*$', '- テスト: あり (GoogleTest)', text, count=1, flags=re.M)
        changed = new != text
        text = new
    else:
        text += '\n## このソリューションの設定 (追記)\n- テスト: あり (GoogleTest)\n'
        changed = True
    if '## テスト (GoogleTest)' not in text:
        gline = ('- GoogleTest は、ソース (`ThirdParty\\googletest\\`) を、静的ライブラリ `gtest` としてビルドしている (NuGet 不要)。取得は、`gtest_once.sh`。'
                 if gmode == 'source' else
                 '- GoogleTest は、NuGet のパッケージを `packages\\` にコピーしたもの (旧方式)。ウォッチャーは、NuGet を復元しない。'
                 if gmode == 'nuget' else
                 "- GoogleTest は、vcpkg (マニフェストモード、`vcpkg.json`、`x64-windows-static-md`)。取得は、`package_once.sh <dir> --timeout 1800 'vcpkg baseline' 'vcpkg install'`。"
                 'テスト exe は、自前の `main.cpp` を持つ (`gtest_main` は、自動ではリンクされない)。')
        text += '''
## テスト (GoogleTest)
- DLL (または静的ライブラリ) ごとに、`<名前>Test.exe`。ウォッチャーは、`*Test.exe` を、すべて、テストとして実行する。
''' + gline + '\n'
        changed = True
    if changed:
        with open(p, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
    return 'CLAUDE.md の「テスト:」を更新した' if changed else 'CLAUDE.md は、すでに「テスト: あり」'


# ---------------- 既存のプロジェクト: 改行コードの規則 (.gitattributes) の確認と追加 ----------------
def _git(folder, *args):
    """読み取り専用の git 呼び出し。戻り値: (終了コード, 標準出力, 標準エラー)"""
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
    try:
        r = subprocess.run(['git', '-c', 'core.quotepath=false', '-C', folder] + list(args),
                           capture_output=True, text=True, encoding='utf-8', errors='replace', env=env, timeout=60)
        return r.returncode, r.stdout, r.stderr.strip()
    except FileNotFoundError:
        return 127, '', 'git が見つからない'
    except subprocess.TimeoutExpired:
        return 124, '', 'git が、時間内に終わらない'


def check_git(folder):
    """改行コードの規則があるかを、読み取りだけで調べる。1 行目: GITATTRIBUTES: <状態>。
    状態: ok / propose / lf-only / declined / not-a-repo / unknown。提案が要るのは propose だけ。"""
    if not os.path.isdir(folder):
        die(f'フォルダがない: {folder}')
    # 見送りの記録 (CLAUDE.md の「- 改行コードの提案: 見送り」)
    cm = os.path.join(folder, 'CLAUDE.md')
    declined = os.path.isfile(cm) and re.search(r'^- 改行コードの提案: 見送り', open(cm, encoding='utf-8-sig').read(), re.M)
    rc, top, err = _git(folder, 'rev-parse', '--show-toplevel')
    if rc != 0:
        if 'not a git repository' in err.lower():
            print('GITATTRIBUTES: not-a-repo')
            print('git のリポジトリではない (提案しない)。')
        else:
            print('GITATTRIBUTES: unknown')
            print(f'git の確認に失敗した: {err} (WSL から /mnt/c のリポジトリを読むと、safe.directory の警告が出ることがある)')
        return
    rc, files, err = _git(folder, 'ls-files')
    tracked = [f for f in files.split('\n') if f][:20]
    ruled = None
    for f in tracked:
        rc2, out, _ = _git(folder, 'check-attr', 'text', 'eol', '--', f)
        if rc2 == 0 and re.search(r': text: (?!unspecified)', out):
            ruled = out.strip().replace('\n', ' / ')
            break
    if ruled:
        print('GITATTRIBUTES: ok')
        print(f'改行コードの規則がある ({ruled})。')
        return
    rc, eol, err = _git(folder, 'ls-files', '--eol')
    if rc != 0:
        print('GITATTRIBUTES: unknown')
        print(f'git ls-files --eol に失敗した: {err}')
        return
    stored_crlf = working_crlf = mixed = 0
    for ln in eol.split('\n'):
        m = re.match(r'i/(\S+)\s+w/(\S+)\s', ln)
        if not m:
            continue
        i, w = m.group(1), m.group(2)
        stored_crlf += i == 'crlf'
        working_crlf += w == 'crlf'
        mixed += (i == 'mixed') + (w == 'mixed')
    total = len([x for x in eol.split('\n') if x])
    if declined:
        print('GITATTRIBUTES: declined')
        print('規則はないが、CLAUDE.md に「改行コードの提案: 見送り」とある (提案しない)。')
        return
    if stored_crlf + working_crlf + mixed == 0:
        print('GITATTRIBUTES: lf-only')
        print(f'規則はないが、CRLF のファイルがない ({total} ファイル。提案しない)。Visual Studio で保存して、CRLF が混ざるようになったら、改めて確認する。')
        return
    print('GITATTRIBUTES: propose')
    print(f'改行コードの規則 (.gitattributes) がない。保存が CRLF={stored_crlf} / 作業フォルダが CRLF={working_crlf} / 混在={mixed} (追跡中 {total} ファイル)。')
    print('WSL の git と、Windows の Git (+ Visual Studio) で、同じファイルを触ると、改行だけの差分が、全行変更に見えることがある。')
    print('提案: 次の最小版 (拡張子を列挙しない) を、このフォルダの .gitattributes にする。')
    for ln in GITATTRIBUTES.split('\n'):
        if ln and not ln.startswith('#'):
            print(f'    {ln}')
    print('導入の手順 (追加すると、保存が CRLF のファイルが、一斉に「変更あり」に見える。1 回だけ、正規化が要る):')
    print('    1. .gitattributes を作る (このコマンドの --add-gitattributes)')
    print('    2. ユーザーが、git add --renormalize . を実行して、git status で、改行だけの変更であることを確認し、1 回コミットする')
    print('    (このコマンドは、git のステージ・コミットを、しない)')


def add_gitattributes(folder):
    if not os.path.isdir(folder):
        die(f'フォルダがない: {folder}')
    p = os.path.join(folder, '.gitattributes')
    if os.path.exists(p):
        die('すでに .gitattributes がある (何も書いていない)', 3)
    write_plain(folder, '.gitattributes', GITATTRIBUTES)
    print(f'+ {p}')
    print('作成した (git の操作は、していない)。次は、ユーザーが、git add --renormalize . を実行して、git status で、')
    print('改行だけの変更であることを確認し、1 回コミットする。それまでは、git diff に、改行だけの差分が、大量に出る。')
    print('完了。')


IDENT = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


def parse_layers(v, names=None, order=('data', 'logic'), ident=None):
    """'none' / 'logic' / 'data' / 'logic,data' / 'logic:OrderLogic,data:OrderData' -> [(key, 名前), ...] (データが先)。
    WPF は、names=WPF_LAYER_NAMES、order=WPF_LAYER_ORDER (viewmodel も許す)"""
    names = names or LAYER_NAMES
    if v == 'none':
        return []
    got = {}
    for t in v.split(','):
        key, _, nm = t.strip().partition(':')
        if key not in names:
            die(f'--layers の値が不正: {t.strip()} (none / {" / ".join(order)} の組み合わせ。名前は logic:OrderLogic のように指定できる)')
        nm = nm.strip() or names[key]
        if not (ident or IDENT).match(nm):
            die(f'層の名前が不正 (英数字と _ のみ、先頭は英字か _{"。WPF は、SampleApp.Domain のように、. で区切ってもよい" if ident else ""}): {nm}')
        got[key] = nm
    return [(k, got[k]) for k in order if k in got]


def existing_solutions(folder):
    return [f for f in sorted(os.listdir(folder)) if f.lower().endswith(('.sln', '.slnx'))]


def slnx_text(projects, startup=None):
    """startup: 最初に開くときの、スタートアッププロジェクトの名前 (DefaultStartup="true")。個人の設定 (.suo) が、あれば、そちらが優先される"""
    out = '<Solution>\n  <Configurations>\n    <BuildType Name="Debug" />\n    <BuildType Name="Release" />\n    <Platform Name="x64" />\n  </Configurations>\n'
    for n, g in projects:
        mark = ' DefaultStartup="true"' if n == startup else ''
        out += f'  <Project Path="{n}/{n}.vcxproj" Id="{g.strip("{}").lower()}"{mark} />\n'
    return out + '</Solution>\n'


def write_plain(folder, rel, text, crlf=False):
    p = os.path.join(folder, *rel.split('/'))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    text = text.replace('\r\n', '\n')
    if crlf:
        text = text.replace('\n', '\r\n')
    with open(p, 'wb') as f:
        f.write(text.encode('utf-8'))


def main_files(name, mtype, ns, toolset, guid):
    """メインのプロジェクトのファイル一式を返す: (files, rc の相対パス (BOM なしで書く))"""
    files, plain = {}, set()
    if mtype in LIBRARY_TYPES:
        files.update(AL.dll_files(name, ns, [], toolset, guid, kind=mtype))
    elif mtype == 'console':
        files[f'{name}/main.cpp'] = CONSOLE_MAIN.replace('@@NAME@@', name)
        files[f'{name}/{name}.vcxproj'] = AL.vcxproj(name, guid, 'Application', toolset, ['main.cpp'], [], [], '_CONSOLE;', 'Console')
        files[f'{name}/{name}.vcxproj.filters'] = AL.vcxproj_filters(['main.cpp'])
    elif mtype == 'win32':
        files[f'{name}/main.cpp'] = WIN32_MAIN.replace('@@NAME@@', name)
        files[f'{name}/{name}.vcxproj'] = AL.vcxproj(name, guid, 'Application', toolset, ['main.cpp'], [], [], '_WINDOWS;', 'Windows')
        files[f'{name}/{name}.vcxproj.filters'] = AL.vcxproj_filters(['main.cpp'])
    else:
        mfc_files, mfc_rc = MFC_VARIANTS[mtype]
        for fn, body in mfc_files.items():
            files[f'{name}/{fn}'] = body.replace('@@NAME@@', name)
        rc = f'{name}.rc'
        files[f'{name}/{rc}'] = mfc_rc.replace('@@NAME@@', name)
        plain.add(f'{name}/{rc}')
        items = list(mfc_files) + [rc]
        files[f'{name}/{name}.vcxproj'] = AL.vcxproj(name, guid, 'Application', toolset, items, [], [], '_WINDOWS;', 'Windows', mfc=True)
        files[f'{name}/{name}.vcxproj.filters'] = AL.vcxproj_filters(items)
    return files, plain


# ---------------- WPF (.NET) ----------------
def load_ap():
    """wpf-test-first/scripts/add_project.py を、読み込む (WPF のときだけ)。"""
    d = os.path.join(HERE, '..', '..', 'wpf-test-first', 'scripts')
    if d not in sys.path:
        sys.path.insert(0, d)
    try:
        import add_project as AP
    except ImportError:
        die('wpf-test-first/scripts/add_project.py が見つからない (wpf-test-first Skill も、配布されている必要がある)')
    return AP


def add_ui_tests_flaui(folder, dry_run=False, new=False):
    """--ui-tests flaui: 同じフォルダの add_ui_tests.py で、<アプリ名>.UITests (MSTest + FlaUI) を足す。"""
    script = os.path.join(HERE, 'add_ui_tests.py')
    if not os.path.isfile(script):
        die('add_ui_tests.py が見つからない (new-solution/scripts/ に、ある)')
    if dry_run and new:
        print('UI テスト       : <アプリ名>.UITests (MSTest + FlaUI) を足す (ウォッチャーの trigger_uitest.flag で実行。通常のテストには、含まれない)')
        return
    import subprocess
    sys.stdout.flush()   # 出力が、パイプのとき、親の出力が、子の出力より後に出ないように
    cmd = [sys.executable, '-I', script, folder] + (['--dry-run'] if dry_run else [])
    r = subprocess.run(cmd)
    if r.returncode != 0:
        sys.exit(r.returncode)


def claude_md_wpf(name, layers, tests, tfm, vm_in_app, ns):
    """layers: [(key, 名前), ...]"""
    default = all(nm == WPF_LAYER_NAMES[k] for k, nm in layers)
    layer_txt = ('なし' if not layers else ','.join(k if default else f'{k}:{nm}' for k, nm in layers))
    test_txt = 'あり (MSTest)' if tests else 'なし'
    out = f"""# CLAUDE.md ({name})

WPF (.NET、MVVM) のプロトタイプ。ソリューション: `{name}.slnx` (フォルダ名と同名)。

## このソリューションの設定
- メイン: {name} (WPF (MVVM))
- 層: {layer_txt}
- テスト: {test_txt}

(この 3 行は、スラッシュコマンド (`/brainstorm` `/add-feature` `/update-from-ideas`) が読む。手で変えるときは、実際の構成と合わせること。)

## 進め方 (スラッシュコマンド)
1. `/brainstorm`: 壁打ちで、考えを広げる (`docs/ideas/<機能名>.md`)。
2. `/update-from-ideas`: メモを整理して、正式な仕様書にする (`docs/specs/<機能名>.md`)。
3. `/add-feature <仕様書>`: 計画 → 承認 → 実装 (テストありなら、テスト先行の Red → Green) → 検証。

## 層と依存の向き
View (WPF アプリ) → ViewModel → ロジック → データ (のインターフェース)。逆向きの参照は禁止。
"""
    if layers:
        labels = {'viewmodel': 'ViewModel', 'logic': 'ロジック', 'data': 'データ'}
        out += "\n| 層 | プロジェクト | 種類 | テスト |\n|---|---|---|---|\n"
        out += f"| View | `{name}` | WPF アプリ (`{tfm}-windows`) | しない (画面。ビルドと、`wpf-check` と、目視) |\n"
        for k, nm in reversed(layers):
            tcell = f'`{nm}.Tests` (MSTest)' if tests else 'なし'
            out += f"| {labels[k]} | `{nm}` | クラスライブラリ (`{tfm}`。**WPF 非依存**) | {tcell} |\n"
    out += f"""
- 名前空間: `{ns}` (ライブラリは `{ns}.<Data|Logic|ViewModels>`。名前が `SampleApp.Domain` のように `.` を含むときは、その名前)。
- アプリの構成: `App.xaml` / `Views/` / `ViewModels/` (ViewModel 層がないとき) / `Resources/` (共通の色・余白・スタイル)。**`DataContext` は、`App.xaml.cs` の `OnStartup` (組み立てる場所) で設定する** (`MainWindow` のコードビハインドには、書かない)。
- **ViewModel は、WPF の型 (`Window` / `MessageBox` / `Application.Current` / `Dispatcher`) を使わない。** ダイアログなどは、インターフェース (`IDialogService` など) に分ける。
"""
    if vm_in_app:
        out += "- ViewModel 層を作っていないので、ViewModel は、アプリの `ViewModels/` フォルダにある (テストできない。テストしたくなったら、`ViewModels` ライブラリに切り出す)。\n"
    out += f"""- MVVM の基底クラス (`ObservableObject` / `RelayCommand`) は、**自前の最小実装** (NuGet 不要)。CommunityToolkit.Mvvm などを使うときは、`add-package` Skill で追加して、置き換える。

## ビルドとテスト
- Windows 側のウォッチャー (`run_watcher.cmd`) 経由で、Skill (`auto-build` / `build-test-loop`) が行う。NuGet の復元は、ビルドが行う (`/restore`)。
- **パッケージの追加は、`add-package` Skill** (`.csproj` を、手で書き換えない)。
- XAML / ViewModel を編集したら、`wpf-check` (画面に何も出ない、起動時に例外、などの、コンパイルでは見つからない不具合の静的検査)。
- 新しい `.cs` / `.xaml` は、SDK 形式なので、`.csproj` に追加しなくてよい (自動で含まれる)。
- Visual Studio で実行 (F5) するときは、`{name}` が、スタートアッププロジェクト (`{name}.slnx` の `DefaultStartup="true"`)。ただし、`.vs/` の個人の設定が、すでにあれば、そちらが優先される。
"""
    if tests:
        out += """
## テスト (MSTest)
- ライブラリごとに、`<名前>.Tests` (MSTest v3、`Microsoft.NET.Test.Sdk`)。ウォッチャーは、`dotnet test --no-build` で、すべて実行する。
- テストファイルは、`<クラス名>Tests.cs`。テスト名は、`メソッド_条件_期待` の形。テスト先行は、`wpf-test-first` Skill。
"""
    out += """
## 規約
- 規約 (**WPF プログラミング規約**) の全文は、ユーザー共通の `~/.claude/rules/wpf-csharp.md` (C# / XAML のファイルを扱うときに、自動で読み込まれる)。`.editorconfig` が、書式を定める。機械で判定できる項目は、`wpf-check` が確かめる。
- ファイルは UTF-8 (BOM 付き)、改行は CRLF、インデントはスペース 4 (`.csproj` は 2)。括弧は Allman。コメントは日本語。
- `git commit` / `git push` は、ユーザーの指示があるときだけ。
"""
    return out


def claude_md_winforms(name, layers, tests, tfm, ns):
    """layers: [(key, 名前), ...]"""
    default = all(nm == WPF_LAYER_NAMES[k] for k, nm in layers)
    layer_txt = ('なし' if not layers else ','.join(k if default else f'{k}:{nm}' for k, nm in layers))
    test_txt = 'あり (MSTest)' if tests else 'なし'
    lnames = dict(layers)
    out = f"""# CLAUDE.md ({name})

WinForms (.NET、MVP) のプロトタイプ。ソリューション: `{name}.slnx` (フォルダ名と同名)。

## このソリューションの設定
- メイン: {name} (WinForms (MVP))
- 層: {layer_txt}
- テスト: {test_txt}

(この 3 行は、スラッシュコマンド (`/brainstorm` `/add-feature` `/update-from-ideas`) が読む。手で変えるときは、実際の構成と合わせること。)

## 進め方 (スラッシュコマンド)
1. `/brainstorm`: 壁打ちで、考えを広げる (`docs/ideas/<機能名>.md`)。
2. `/update-from-ideas`: メモを整理して、正式な仕様書にする (`docs/specs/<機能名>.md`)。
3. `/add-feature <仕様書>`: 計画 → 承認 → 実装 (テストありなら、テスト先行の Red → Green) → 検証。

## 層と依存の向き
View (WinForms アプリ) → Presenter (ロジック) → データ (のインターフェース)。逆向きの参照は禁止。
"""
    if layers:
        labels = {'logic': 'ロジック (Presenter)', 'data': 'データ'}
        out += "\n| 層 | プロジェクト | 種類 | テスト |\n|---|---|---|---|\n"
        out += f"| View | `{name}` | WinForms アプリ (`{tfm}-windows`) | しない (画面。ビルドと、目視) |\n"
        for k, nm in reversed(layers):
            tcell = f'`{nm}.Tests` (MSTest)' if tests else 'なし'
            out += f"| {labels[k]} | `{nm}` | クラスライブラリ (`{tfm}`。**WinForms 非依存**) | {tcell} |\n"
    out += f"""
- 名前空間: `{ns}` (ライブラリは `{ns}.<Data|Logic>`。名前が `SampleApp.Domain` のように `.` を含むときは、その名前)。
- アプリの構成: `Program.cs` (**組み立てる場所 = composition root**。`Form` と `Presenter` を作って結ぶ) / `Forms/` (`Form` と `*.Designer.cs`){'' if 'logic' in lnames else ' / `Presenters/` (ロジック層がないとき)'}。
- **画面の振る舞い (入力の検査、表示する文字、ボタンの有効・無効) は、Presenter に置く。** `Form` は `IMainView` (インターフェース) を実装して、**値の出し入れとイベントの通知だけ**をする。Presenter は、WinForms の型 (`Form` / `Control` / `MessageBox` / `Application`) を使わない。ダイアログなども、インターフェース (`IDialogService` など) に分ける。
- **操作する (UI テストで探す) コントロールには、`Name` を付ける** (`NameTextBox` / `ClearButton` のように、役割が分かる名前。UI Automation の `AutomationId` になる)。
"""
    if 'logic' not in lnames:
        if tests:
            out += f"- ロジック層を作っていないので、`IMainView` / `MainPresenter` は、アプリの `Presenters/` フォルダにある。**テストは、`{name}.Tests` (アプリを参照する。TFM は、アプリと同じ `{tfm}-windows`) が、`Presenters/` を対象にする。** `Form` (`Forms/`) は、テストしない。業務ロジックが増えたら、ロジック層 (クラスライブラリ) に切り出す。\n"
        else:
            out += "- ロジック層を作っていないので、`IMainView` / `MainPresenter` は、アプリの `Presenters/` フォルダにある。テストするなら、`--tests mstest` (後付けもできる。`<アプリ名>.Tests` が、`Presenters/` を対象にする)、または、ロジック層に切り出す。\n"
    out += f"""
## ビルドとテスト
- Windows 側のウォッチャー (`run_watcher.cmd`) 経由で、Skill (`auto-build` / `build-test-loop`) が行う。NuGet の復元は、ビルドが行う (`/restore`)。
- **パッケージの追加は、`add-package` Skill** (`.csproj` を、手で書き換えない)。
- 新しい `.cs` は、SDK 形式なので、`.csproj` に追加しなくてよい (自動で含まれる)。
- **Form / `*.Designer.cs` / Presenter を編集したら、`winforms-check`** (画面が空になる、UI テストが要素を探せない、Presenter に WinForms が混ざる、などの、コンパイルでは見つからない不具合の静的検査。`~/.claude/skills/winforms-check/scripts/winforms_check.py "$PWD"`)。
- **`*.Designer.cs` は、Visual Studio のデザイナーが書き直す。** 手で編集するときは、`InitializeComponent` の形 (`// コントロール名` のコメント、プロパティの代入、`Controls.Add`) を保つ。イベントは、Designer の `+=` と、`Form` のハンドラーの名前を、そろえる。
- Visual Studio で実行 (F5) するときは、`{name}` が、スタートアッププロジェクト (`{name}.slnx` の `DefaultStartup="true"`)。ただし、`.vs/` の個人の設定が、すでにあれば、そちらが優先される。
"""
    if tests:
        out += """
## テスト (MSTest)
- ライブラリごとに、`<名前>.Tests` (MSTest v3、`Microsoft.NET.Test.Sdk`)。ウォッチャーは、`dotnet test --no-build` で、すべて実行する。
- Presenter のテストは、`IMainView` の偽物 (Fake) を作って、イベントを起こし、表示の結果を確かめる (`MainPresenterTests`)。
- テストファイルは、`<クラス名>Tests.cs`。テスト名は、`メソッド_条件_期待` の形。テスト先行は、`wpf-test-first` Skill (WPF 以外の .NET のソリューションでも、同じ手順)。
"""
    out += """
## 規約
- 規約 (**WinForms プログラミング規約**) の全文は、ユーザー共通の `~/.claude/rules/winforms-csharp.md` (C# のファイルを扱うときに、自動で読み込まれる)。C# の共通部分 (5 / 10 / 12 / 13 / 15 / 16 / 17 章) は、`wpf-csharp.md` を使う。**`wpf-csharp.md` の、WPF / XAML / MVVM の節 (6 / 7 / 8 / 9 / 14 章) は、適用しない。** 機械で判定できる項目は、`winforms-check` が確かめる。`.editorconfig` が、書式を定める。
- ファイルは UTF-8 (BOM 付き)、改行は CRLF、インデントはスペース 4 (`.csproj` は 2)。括弧は Allman。コメントは日本語。
- `git commit` / `git push` は、ユーザーの指示があるときだけ。
"""
    return out


def claude_md_csharp_dll(name, layers, tests, tfm, ns):
    """layers: [(key, 名前), ...]"""
    default = all(nm == WPF_LAYER_NAMES[k] for k, nm in layers)
    layer_txt = ('なし' if not layers else ','.join(k if default else f'{k}:{nm}' for k, nm in layers))
    test_txt = 'あり (MSTest)' if tests else 'なし'
    out = f"""# CLAUDE.md ({name})

C# のクラスライブラリ (.NET)。ソリューション: `{name}.slnx` (フォルダ名と同名)。画面 (UI) は、持たない。

## このソリューションの設定
- メイン: {name} (C# クラスライブラリ)
- 層: {layer_txt}
- テスト: {test_txt}

(この 3 行は、スラッシュコマンド (`/brainstorm` `/add-feature` `/update-from-ideas`) が読む。手で変えるときは、実際の構成と合わせること。)

## 進め方 (スラッシュコマンド)
1. `/brainstorm`: 壁打ちで、考えを広げる (`docs/ideas/<機能名>.md`)。
2. `/update-from-ideas`: メモを整理して、正式な仕様書にする (`docs/specs/<機能名>.md`)。
3. `/add-feature <仕様書>`: 計画 → 承認 → 実装 (テストありなら、テスト先行の Red → Green) → 検証。

## 構成と依存の向き
"""
    out += "\n| 種類 | プロジェクト | 対象 | テスト |\n|---|---|---|---|\n"
    tcell = lambda nm: f'`{nm}.Tests` (MSTest)' if tests else 'なし'
    out += f"| メイン | `{name}` | クラスライブラリ (`{tfm}`) | {tcell(name)} |\n"
    for k, nm in reversed(layers):
        out += f"| {'ロジック' if k == 'logic' else 'データ'}層 | `{nm}` | クラスライブラリ (`{tfm}`) | {tcell(nm)} |\n"
    out += f"""
- 依存の向き: メイン → ロジック → データ。逆向きの参照は禁止。
- 名前空間: `{ns}` (層は `{ns}.<Data|Logic>`。名前が `SampleApp.Domain` のように `.` を含むときは、その名前)。
- 公開する型・メンバーは、テストから使える形にする (テストできない公開 API を作らない)。

## ビルドとテスト
- Windows 側のウォッチャー (`run_watcher.cmd`) 経由で、Skill (`auto-build` / `build-test-loop`) が行う。NuGet の復元は、ビルドが行う (`/restore`)。
- **パッケージの追加は、`add-package` Skill** (`.csproj` を、手で書き換えない)。
- 新しい `.cs` は、SDK 形式なので、`.csproj` に追加しなくてよい (自動で含まれる)。
"""
    if tests:
        out += """
## テスト (MSTest)
- プロジェクトごとに、`<名前>.Tests` (MSTest v3、`Microsoft.NET.Test.Sdk`)。ウォッチャーは、`dotnet test --no-build` で、すべて実行する。
- テストファイルは、`<クラス名>Tests.cs`。テスト名は、`メソッド_条件_期待` の形。テスト先行は、`wpf-test-first` Skill (WPF 以外の .NET のソリューションでも、同じ手順)。
"""
    out += """
## 規約
- C# の規約は、ユーザー共通の `~/.claude/rules/wpf-csharp.md` のうち、C# の部分 (5 C# コーディング規約 / 10 非同期 / 12 例外 / 15 コメント / 16 テスト / 17 禁止事項)。WPF / XAML / MVVM の節は、適用しない。`.editorconfig` が、書式を定める。
- ファイルは UTF-8 (BOM 付き)、改行は CRLF、インデントはスペース 4 (`.csproj` は 2)。括弧は Allman。コメントは日本語。
- `git commit` / `git push` は、ユーザーの指示があるときだけ。
"""
    return out


def create_wpf(a, folder, name):
    AP = load_ap()
    dll = a.type == 'csharp-dll'   # メイン自身が、クラスライブラリ (テストの対象になる)
    winforms = a.type == 'winforms'
    kind_label = KIND[a.type]
    missing = [k for k, v in (('--layers', a.layers), ('--tests', a.tests)) if v is None]
    if missing:
        die(f'新規作成には、{" / ".join(missing)} が必要 (省略した項目は、ユーザーに質問して、決めること)')
    if a.tests == 'gtest':
        die('--tests gtest は C++ 用。WPF (.NET) は、--tests mstest (または none)')
    if a.layer_kind or a.gtest or a.gtest_from or a.toolset:
        die('--layer-kind / --gtest / --gtest-from / --toolset は C++ 用。WPF では、指定できない')
    if dll and a.ui_tests == 'flaui':
        die('--ui-tests flaui は、画面のあるアプリ (wpf) 用。csharp-dll には、画面がない')
    if dll or winforms:
        layer_names_all = {k: v for k, v in WPF_LAYER_NAMES.items() if k != 'viewmodel'}
        layers = parse_layers(a.layers, layer_names_all, ('data', 'logic'), AP.PROJ_NAME)
    else:
        layers = parse_layers(a.layers, WPF_LAYER_NAMES, WPF_LAYER_ORDER, AP.PROJ_NAME)
    tests = a.tests == 'mstest'
    # アプリ (View) は、テストしない。ただし WinForms でロジック層がないときは、アプリの Presenters/ が、テストの対象 (<名前>.Tests)
    app_tested = winforms and 'logic' not in dict(layers)
    if tests and not layers and not dll and not winforms:
        die('--tests mstest は、テスト対象 (層) が必要。WPF のアプリ (View) は、テストしない。--layers を指定するか、--tests none にする')
    ns = a.namespace or AP.default_namespace(name + '.slnx')
    if not all(IDENT.match(x) for x in ns.split('.')):
        die(f'名前空間が不正 (英数字と _ のみ。. で区切る): {ns}')
    tfm = a.tfm or AP.DEFAULT_TFM
    if not re.match(r'^net\d+\.\d+$', tfm):
        die(f'--tfm が不正 (例: net8.0): {tfm}')
    mver = a.mstest_version or AP.MSTEST_VER
    sver = a.testsdk_version or AP.TESTSDK_VER
    for v in (mver, sver):
        if not re.match(r'^[0-9][0-9A-Za-z.+-]{0,63}$', v):
            die(f'バージョンが不正: {v}')

    lnames = dict(layers)
    layer_names = [nm for _, nm in layers]
    test_targets = ([name] if dll or (app_tested and tests) else []) + layer_names   # テストを作る対象 (csharp-dll は、メイン自身も)
    dirs = [name] + layer_names + ([nm + '.Tests' for nm in test_targets] if tests else [])
    if len(set(dirs)) != len(dirs):
        die('プロジェクト名が重複している (フォルダ名が、層の名前などと同じ?)')
    for d in dirs:
        if os.path.exists(os.path.join(folder, d)):
            die(f'すでに存在する: {d} (何も書いていない)', 3)

    # 層の依存: データ ← ロジック ← ViewModel ← View。上の層は、すぐ下の層 (なければ、その下) を参照する
    uses_of = {}
    for k, nm in layers:
        below = [lnames[x] for x in ('logic', 'data') if x in lnames and WPF_LAYER_ORDER.index(x) < WPF_LAYER_ORDER.index(k)]
        uses_of[k] = below[:1]
    vm_in_app = 'viewmodel' not in lnames
    presenter_ns = AP.layer_namespace(ns, 'logic', lnames['logic']) if 'logic' in lnames else f'{ns}.Presenters'
    app_uses = [nm for _, nm in reversed(layers)]
    files = {}
    projects = [(name, AP.new_guid())]
    if dll:
        files.update(AP.lib_files(name, ns, app_uses, tfm))
        if tests:
            files.update(AP.test_files(name, ns, tfm, mver, sver))
            projects.append((name + '.Tests', AP.new_guid()))
    elif winforms:
        files.update(AP.winforms_app_files(name, ns, tfm, app_uses, presenter_ns, 'logic' not in lnames))
        if app_tested and tests:
            files.update(AP.test_files(name, presenter_ns, tfm, mver, sver, 'app-presenter'))
            projects.append((name + '.Tests', AP.new_guid()))
    else:
        files.update(AP.wpf_app_files(name, ns, tfm, app_uses, vm_in_app, lnames.get('viewmodel')))
    for k, nm in layers:
        lns = AP.layer_namespace(ns, k, nm)
        lkind = 'viewmodel' if k == 'viewmodel' else ('presenter' if winforms and k == 'logic' else 'lib')
        files.update(AP.lib_files(nm, lns, uses_of[k], tfm, lkind))
        projects.append((nm, AP.new_guid()))
        if tests:
            files.update(AP.test_files(nm, lns, tfm, mver, sver, lkind))
            projects.append((nm + '.Tests', AP.new_guid()))
    files['Directory.Build.props'] = AP.DIRECTORY_BUILD_PROPS

    vm_where = 'アプリの ViewModels フォルダ' if vm_in_app else lnames.get('viewmodel')
    layer_desc = ', '.join(f'{nm} ({k})' for k, nm in layers) + f' (クラスライブラリ、{tfm}、{"WinForms" if winforms else "WPF"} 非依存)' if layers else 'なし'
    print(f'フォルダ       : {folder}')
    print(f'ソリューション : {name}.slnx (フォルダ名と同名)')
    if dll:
        print(f'メイン         : {name} ({kind_label}、{tfm}。テストの対象)')
    elif winforms:
        print(f'メイン         : {name} ({kind_label}、{AP.windows_tfm(tfm)}。Presenter は、{lnames["logic"] if "logic" in lnames else "アプリの Presenters フォルダ"})')
    else:
        print(f'メイン         : {name} ({kind_label}、{AP.windows_tfm(tfm)}。ViewModel は、{vm_where})')
    print(f'層             : {layer_desc}')
    print(f'テスト         : {"あり (MSTest): " + ", ".join(nm + ".Tests" for nm in test_targets) if tests else "なし"}')
    print(f'名前空間       : {ns}')
    if tests:
        print(f'MSTest         : MSTest {mver} / Microsoft.NET.Test.Sdk {sver} (新しい版は、add-package の nuget versions で確認する)')
    print(f'  + {name}.slnx ({len(projects)} プロジェクト)')
    for rel in files:
        print(f'  + {rel}')
    extras = [x for x in ('.editorconfig', 'CLAUDE.md', '.gitignore', '.gitattributes') if not os.path.exists(os.path.join(folder, x))]
    for e in extras:
        print(f'  + {e}')
    if a.dry_run:
        print('NUGET: 初回のビルドで、MSTest を復元する (ホストが nuget.org に届くこと)' if tests else 'NUGET: パッケージなし')
        print('(dry-run: 何も書いていない)')
        return

    os.makedirs(folder, exist_ok=True)
    AP.write_files(folder, files)
    write_plain(folder, f'{name}.slnx', AP.slnx_text(projects, None if dll else name), crlf=True)
    if '.editorconfig' in extras:
        write_plain(folder, '.editorconfig', AP.EDITORCONFIG, crlf=True)
    if 'CLAUDE.md' in extras:
        write_plain(folder, 'CLAUDE.md', claude_md_csharp_dll(name, layers, tests, tfm, ns) if dll
                    else claude_md_winforms(name, layers, tests, tfm, ns) if winforms
                    else claude_md_wpf(name, layers, tests, tfm, vm_in_app, ns))
    if '.gitignore' in extras:
        write_plain(folder, '.gitignore', AP.GITIGNORE)
    if '.gitattributes' in extras:
        write_plain(folder, '.gitattributes', GITATTRIBUTES)
    print('完了。')


def update_claude_md_mstest(folder):
    p = os.path.join(folder, 'CLAUDE.md')
    if not os.path.isfile(p):
        return 'CLAUDE.md がない (何も更新していない)'
    text = open(p, encoding='utf-8').read()
    changed = False
    if re.search(r'^- テスト: .*$', text, re.M):
        new = re.sub(r'^- テスト: .*$', '- テスト: あり (MSTest)', text, count=1, flags=re.M)
        changed, text = new != text, new
    else:
        text += '\n## このソリューションの設定 (追記)\n- テスト: あり (MSTest)\n'
        changed = True
    if '## テスト (MSTest)' not in text:
        text += ('\n## テスト (MSTest)\n'
                 '- ライブラリごとに、`<名前>.Tests` (MSTest v3、`Microsoft.NET.Test.Sdk`)。ウォッチャーは、`dotnet test --no-build` で、すべて実行する。\n')
        changed = True
    if changed:
        with open(p, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
    return 'CLAUDE.md の「テスト:」を更新した' if changed else 'CLAUDE.md は、すでに「テスト: あり」'


def has_dotnet_projects(folder):
    return any(os.path.isfile(os.path.join(folder, d, f'{d}.csproj')) for d in os.listdir(folder)
               if os.path.isdir(os.path.join(folder, d)))


def add_tests_wpf(a, folder, name, sln_name):
    if a.type is not None or a.layers is not None or a.spec is not None:
        die('すでにソリューションがあるフォルダでは、--tests mstest だけを指定できる (--type / --layers / --spec は、指定できない)')
    AP = load_ap()
    sln = os.path.join(folder, sln_name)
    todo = AP.libraries_without_tests(folder)
    if not todo:
        die('テストを足せるクラスライブラリがない (ないか、すべてに、すでに <名前>.Tests がある)。'
            'WPF のアプリ (View) は、テストしない (WinForms は、ロジック層がなければ、アプリの Presenters/ をテストする)。先に、層 (クラスライブラリ) を作ること')
    mver = a.mstest_version or AP.MSTEST_VER
    sver = a.testsdk_version or AP.TESTSDK_VER
    files, projects = {}, []
    for ln in todo:
        info = AP.read_lib_info(folder, ln)
        lns = a.namespace or info['ns'] or AP.default_namespace(sln_name)
        if info['is_exe']:   # ロジック層のない WinForms のアプリ (Presenters/ が、テストの対象)
            files.update(AP.test_files(ln, (info['ns'] or AP.default_namespace(sln_name)) + '.Presenters', info['tfm'], mver, sver, 'app-presenter'))
        else:
            files.update(AP.test_files(ln, lns, info['tfm'], mver, sver, 'viewmodel' if info['is_vm'] else ('presenter' if info['is_presenter'] else 'lib')))
        projects.append((ln + '.Tests', AP.new_guid()))
    print(f'ソリューション : {sln_name} (すでにある)')
    print(f'テストの後付け : {", ".join(todo)} に、<名前>.Tests を足す (MSTest {mver})')
    for rel in files:
        print(f'  + {rel}')
    print(f'  ~ {sln_name} ({len(projects)} プロジェクトを追加)')
    if a.dry_run:
        print('(dry-run: 何も書いていない)')
        return
    AP.write_files(folder, files)
    AP.register(sln, projects)
    print(update_claude_md_mstest(folder))
    print('完了。NuGet の復元は、ウォッチャーのビルド (/restore) が行う。')


def create_mode(a, folder, name):
    if a.type in DOTNET_TYPES:
        create_wpf(a, folder, name)
        return
    if a.tests == 'mstest':
        die('--tests mstest は .NET (wpf / csharp-dll) 用。C++ は、--tests gtest')
    if a.tfm or a.mstest_version or a.testsdk_version:
        die('--tfm / --mstest-version / --testsdk-version は WPF (.NET) 用')
    missing = [k for k, v in (('--type', a.type), ('--layers', a.layers), ('--tests', a.tests)) if v is None]
    if missing:
        die(f'新規作成には、{" / ".join(missing)} が必要 (省略した項目は、ユーザーに質問して、決めること)')
    layers = parse_layers(a.layers)
    tests = a.tests == 'gtest'
    if tests and not layers and a.type not in LIBRARY_TYPES:
        die('--tests gtest は、テスト対象 (DLL / 静的ライブラリ) が必要。メインが exe で --layers none のときは、指定できない '
            '(層を作るか、--tests none にする)')
    ns = a.namespace or AL.default_namespace(name + '.slnx')
    toolset = a.toolset or 'v145'
    lkind = a.layer_kind or 'dll'

    # 事前の確認 (何も書く前に、すべて確かめる)
    layer_names = [nm for _, nm in layers]
    targets = ([name] if a.type in LIBRARY_TYPES else []) + layer_names   # テストの対象
    dirs = [name] + layer_names + ([t + 'Test' for t in targets] if tests else [])
    if len(set(dirs)) != len(dirs):
        die('プロジェクト名が重複している (フォルダ名が、層の名前などと同じ?)')
    for d in dirs:
        if os.path.exists(os.path.join(folder, d)):
            die(f'すでに存在する: {d} (何も書いていない)', 3)

    gmode, gstat, gfiles, gprojects, gguid = None, None, {}, [], None
    if tests:
        gmode, gstat = AL.decide_gtest_mode(folder, a.gtest or 'auto', a.gtest_from)
        if gmode == 'source' and os.path.exists(os.path.join(folder, 'gtest')) and \
                not os.path.isfile(os.path.join(folder, 'gtest', 'gtest.vcxproj')):
            die('すでに存在する: gtest (GoogleTest の静的ライブラリの、フォルダ名と重なる)', 3)
        gfiles, gprojects, gguid = AL.plan_gtest(folder, gmode, toolset)

    mg = AL.new_guid()
    files, plain = main_files(name, a.type, ns, toolset, mg)
    projects = [(name, mg)]
    dll_list = [(name, mg, [], a.type)] if a.type in LIBRARY_TYPES else []
    data_name = dict(layers).get('data')
    for k, ln in layers:
        lg = AL.new_guid()
        uses = [data_name] if (k == 'logic' and data_name) else []
        files.update(AL.dll_files(ln, ns, uses, toolset, lg, kind=lkind))
        projects.append((ln, lg))
        dll_list.append((ln, lg, uses, lkind))
    if tests:
        for dn, dg, uses, _kind in dll_list:
            tg = AL.new_guid()
            files.update(AL.test_files(dn, ns, uses, toolset, dg, tg, gtest_mode=gmode, gtest_guid=gguid))
            projects.append((dn + 'Test', tg))
        files.update(gfiles)
        projects += gprojects

    print(f'フォルダ       : {folder}')
    print(f'ソリューション : {name}.slnx (フォルダ名と同名)')
    print(f'メイン         : {name} ({KIND[a.type]}、x64 の Debug / Release)')
    print(f'層             : {", ".join(f"{nm} ({k})" for k, nm in layers) + f" ({KIND[lkind]})" if layers else "なし"}')
    print(f'テスト         : {"あり (GoogleTest): " + ", ".join(t + "Test" for t in targets) if tests else "なし"}')
    print(f'名前空間       : {ns}')
    print(f'PlatformToolset: {toolset}')
    print(f'  + {name}.slnx ({len(projects)} プロジェクト)')
    for rel in files:
        print(f'  + {rel}')
    extras = [x for x in ('CLAUDE.md', '.gitignore', '.gitattributes') if not os.path.exists(os.path.join(folder, x))]
    for e in extras:
        print(f'  + {e}')
    if a.dry_run:
        if tests:
            print(AL.describe_gtest(gmode, gstat))
            if a.type in EXE_TYPES and re.search(r'(Test|Tests)$', name):
                print(f'MAIN_EXE_TARGETNAME: {name} -> {name}_Main (予定)')
        print('(dry-run: 何も書いていない)')
        return

    os.makedirs(folder, exist_ok=True)
    AL.write_files(folder, {k: v for k, v in files.items() if k not in plain})
    for rel in plain:
        write_plain(folder, rel, files[rel], crlf=True)
    write_plain(folder, f'{name}.slnx', slnx_text(projects, name if a.type in EXE_TYPES else None), crlf=True)
    if 'CLAUDE.md' in extras:
        write_plain(folder, 'CLAUDE.md', claude_md(name, KIND[a.type], layers, tests, lkind, gmode or 'vcpkg'))
    if '.gitignore' in extras:
        write_plain(folder, '.gitignore', GITIGNORE)
    if '.gitattributes' in extras:
        write_plain(folder, '.gitattributes', GITATTRIBUTES)
    if tests:
        finish_tests(folder, gmode, a.gtest_from)
    print('完了。')


def finish_tests(folder, gmode, gtest_from):
    print(AL.finish_gtest(folder, gmode, gtest_from))
    for n in AL.protect_main_exes(folder):
        print(f'MAIN_EXE_TARGETNAME: {n} -> {n}_Main (ウォッチャーが、アプリをテストとして実行しないため)')


def add_tests_mode(a, folder, name, sln_name):
    if a.type is not None or a.layers is not None or a.spec is not None:
        die('すでにソリューションがあるフォルダでは、--tests gtest だけを指定できる (--type / --layers / --spec は、指定できない)')
    sln = os.path.join(folder, sln_name)
    toolset = a.toolset or AL.detect_toolset(folder)
    todo = []
    for vp in sorted(os.listdir(folder)):
        pf = os.path.join(folder, vp, f'{vp}.vcxproj')
        if not os.path.isfile(pf) or vp == 'gtest':
            continue
        text = open(pf, encoding='utf-8-sig').read()
        if '<ConfigurationType>DynamicLibrary</ConfigurationType>' not in text and \
                '<ConfigurationType>StaticLibrary</ConfigurationType>' not in text:
            continue
        if os.path.exists(os.path.join(folder, vp + 'Test')):
            continue
        todo.append(vp)
    if not todo:
        die('テストを足せる DLL / 静的ライブラリ がない (ないか、すべてに、すでに <名前>Test がある)。'
            'メインが exe なら、先に層 (DLL) を作ること')
    gmode, gstat = AL.decide_gtest_mode(folder, a.gtest or 'auto', a.gtest_from)
    gfiles, gprojects, gguid = AL.plan_gtest(folder, gmode, toolset)
    files, projects = {}, []
    for dn in todo:
        info = AL.read_dll_info(folder, dn)
        ns = a.namespace or info['ns'] or AL.default_namespace(sln_name)
        tg = AL.new_guid()
        files.update(AL.test_files(dn, ns, info['uses'], toolset, info['guid'], tg, baseline_link=info['has_info'],
                                   gtest_mode=gmode, gtest_guid=gguid))
        projects.append((dn + 'Test', tg))
        if not info['has_info']:
            print(f'NOTE: {dn}ModuleInfo.h がないので、{dn}Test のベースラインは、DLL を呼ばない (リンクは、確かめられない)')
    files.update(gfiles)
    projects += gprojects
    print(f'ソリューション : {sln_name} (すでにある)')
    print(f'テストの後付け : {", ".join(todo)} に、<名前>Test を足す (GoogleTest)')
    for rel in files:
        print(f'  + {rel}')
    print(f'  ~ {sln_name} ({len(projects)} プロジェクトを追加)')
    if a.dry_run:
        print(AL.describe_gtest(gmode, gstat))
        for n in AL.protect_main_exes(folder, dry=True):
            print(f'MAIN_EXE_TARGETNAME: {n} -> {n}_Main (予定)')
        print('(dry-run: 何も書いていない)')
        return
    AL.write_files(folder, files)
    AL.register(sln, projects)
    finish_tests(folder, gmode, a.gtest_from)
    print(update_claude_md_tests(folder, name, gmode))
    print('完了。')


SPEC_KEYS = {'メインの種類': 'type', '層': 'layers', '層の種類': 'layer_kind', 'テスト': 'tests', '名前空間': 'namespace',
             'UIテスト': 'ui_tests', 'TFM': 'tfm'}
SPEC_ALLOWED = {'type': ('wpf', 'winforms', 'csharp-dll', 'mfc', 'mfc-mdi', 'mfc-dialog', 'win32', 'console', 'dll', 'lib'), 'layer_kind': ('dll', 'lib'),
                'tests': ('none', 'gtest', 'mstest'), 'ui_tests': ('none', 'flaui')}


def read_spec_config(path):
    """仕様書の「## 構成案」から、`- <キー>: <値>` の行を読む。値は、最初の空白までの 1 語 (後ろは、根拠の説明として無視する)。
    決まっていない項目 (未定・未決・?・空) は、読み飛ばす (呼び出し側が、ユーザーに質問する)。戻り値: dict"""
    if not os.path.isfile(path):
        die(f'仕様書がない: {path}')
    text = open(path, encoding='utf-8-sig').read().replace('\r\n', '\n')
    m = re.search(r'^## 構成案[^\n]*\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    if not m:
        die(f'仕様書に「## 構成案」の節がない: {path} (/update-from-ideas で、構成案を作る)')
    cfg = {}
    for ln in m.group(1).split('\n'):
        mm = re.match(r'^\s*-\s*([^:：]+)[:：]\s*(.*)$', ln)
        if not mm or mm.group(1).strip() not in SPEC_KEYS:
            continue
        key = SPEC_KEYS[mm.group(1).strip()]
        val = mm.group(2).strip()
        val = val.split()[0] if val else ''
        if val in ('', '未定', '未決', '?', '？', '-', 'ー'):
            continue
        if key in SPEC_ALLOWED and val not in SPEC_ALLOWED[key]:
            die(f'構成案の値が不正: {mm.group(1).strip()}: {val} (使える値: {", ".join(SPEC_ALLOWED[key])})')
        cfg[key] = val
    return cfg


def apply_spec(a):
    """--spec の値を、省略された引数に入れる (明示した引数が優先)。読み取った内容を表示する。"""
    cfg = read_spec_config(a.spec)
    used = []
    for key, val in cfg.items():
        if key == 'tfm' and (a.type or cfg.get('type')) not in DOTNET_TYPES:
            print(f'注意: 構成案の TFM ({val}) は、.NET 用。C++ では、読み飛ばす')
            continue
        if key == 'tfm' and not re.match(r'^net\d+\.\d+$', val):
            die(f'構成案の値が不正: TFM: {val} (例: net8.0)')
        if getattr(a, key, None) is None:
            setattr(a, key, val)
            used.append(f'{key}={val}')
    print(f'構成案 ({a.spec}) から読み取った: {", ".join(used) if used else "(なし。すべて、引数で指定済み、または、構成案で未定)"}')


def import_spec(a, folder):
    """--spec の仕様書を、新しいソリューションへ取り込む (spec_import.py。仕様書・メモの配置、テストケースの種、CLAUDE.md の節)。"""
    sys.path.insert(0, HERE)
    import spec_import as SI
    label = {'gtest': 'GoogleTest (自動テスト)', 'mstest': 'MSTest (自動テスト)'}.get(a.tests)
    p = SI.plan(folder, a.spec, label)
    print('仕様書の取り込み:')
    for ln in SI.describe(p):
        print(ln)
    if a.dry_run:
        print('(dry-run: 何も書いていない)')
        return
    SI.apply(folder, p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('folder')
    ap.add_argument('--type', choices=['wpf', 'winforms', 'csharp-dll', 'mfc', 'mfc-mdi', 'mfc-dialog', 'win32', 'console', 'dll', 'lib'])
    ap.add_argument('--layers')
    ap.add_argument('--tests', choices=['none', 'gtest', 'mstest'])
    ap.add_argument('--tfm')
    ap.add_argument('--mstest-version')
    ap.add_argument('--testsdk-version')
    ap.add_argument('--namespace')
    ap.add_argument('--toolset')
    ap.add_argument('--gtest-from')
    ap.add_argument('--gtest', choices=['auto', 'vcpkg', 'source', 'nuget'])
    ap.add_argument('--layer-kind', choices=['dll', 'lib'])
    ap.add_argument('--ui-tests', choices=['none', 'flaui'])
    ap.add_argument('--spec')
    ap.add_argument('--check-git', action='store_true')
    ap.add_argument('--add-gitattributes', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    folder = os.path.abspath(a.folder)
    if a.check_git:
        check_git(folder)
        return
    if a.add_gitattributes:
        add_gitattributes(folder)
        return
    name = os.path.basename(folder.rstrip('/\\'))
    if not re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', name):
        die(f'フォルダ名が、ソリューション名として使えない (英数字と _ のみ、先頭は英字か _): {name}')
    if not os.path.isdir(folder):
        if not os.path.isdir(os.path.dirname(folder)):
            die(f'フォルダも、その親も、ない: {folder}')
    sols = existing_solutions(folder) if os.path.isdir(folder) else []
    if a.spec and not sols:
        apply_spec(a)
    if len(sols) > 1:
        die(f'ソリューションが複数ある ({", ".join(sols)})。どれを使うか、ユーザーに確認すること')
    if sols and a.ui_tests == 'flaui' and a.tests is None:
        add_ui_tests_flaui(folder, a.dry_run)
        return
    if sols:
        dotnet = has_dotnet_projects(folder)
        if a.tests == 'mstest':
            if not dotnet:
                die('--tests mstest は、.NET (WPF) のソリューション用。このソリューションには、.csproj のプロジェクトがない。C++ は --tests gtest')
            add_tests_wpf(a, folder, name, sols[0])
        elif a.tests == 'gtest':
            if dotnet:
                die('--tests gtest は、C++ 用。.NET (WPF) のソリューションは、--tests mstest')
            add_tests_mode(a, folder, name, sols[0])
        else:
            die(f'すでにソリューションがある ({sols[0]})。何も書いていない。テストを後付けするなら、--tests gtest (C++) か --tests mstest (.NET) だけを指定する', 3)
    else:
        create_mode(a, folder, name)
        if a.ui_tests == 'flaui':
            add_ui_tests_flaui(folder, a.dry_run, new=True)
        if a.spec:
            import_spec(a, folder)


if __name__ == '__main__':
    main()
