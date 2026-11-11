#!/usr/bin/env python3
"""add_ui_host.py - 既存の C++ のソリューションに、「画面を持つ MFC の DLL (UI DLL)」と、その画面を開くだけの「画面ホストの exe」と、
UI テスト (FlaUI) を足す。呼び出し側の exe がない (DLL だけの) 構成で、DLL が提供する画面を、UI テストで確かめるため。

Usage:
  python3 add_ui_host.py <SLN_DIR> [--name UiLayer] [--kind mfc-std-dll|mfc-ext-dll] [--logic 名前|none]
                         [--host-name 名前] [--namespace NS] [--no-ui-tests] [--dry-run]

  --name      UI DLL の名前 (既定: UiLayer)。名前に Ui / View / Dialog の語を含める (mfc-check が、画面を持つ層として扱う)
  --kind      mfc-std-dll (既定。標準 DLL。共有 MFC。ホストは MFC なしの Win32 exe) / mfc-ext-dll (拡張 DLL。ホストは MFC の exe)
  --logic     画面の規則 (挨拶の文) を置く、ロジック層の名前。省略時は、名前に Logic を含む DLL を探す。none: 置かない (ダイアログの中に書く)
  --host-name 画面ホストの exe の名前 (既定: <UI DLL の名前>Host)

作るもの:
  <UI DLL>/            標準 DLL / 拡張 DLL の一式 (add_layer.py と同じ) + サンプルのダイアログ (GreetingDialog.h/.cpp、<名前>.rc、Resource.h)
                       標準 DLL: 公開関数 ShowGreetingDialog(HWND) (先頭で AFX_MANAGE_STATE)。拡張 DLL: AFX_EXT_CLASS のクラス GreetingDialog
  <ホスト>/            画面を開くだけの exe (標準 DLL: MFC なしの Win32。拡張 DLL: MFC)。ダイアログが、そのまま、メインウィンドウになる
  <ロジック層>/        Greeting.h / Greeting.cpp (MakeGreeting: 画面に依存しない規則) と、<ロジック層>Test/TestGreeting.cpp (単体テスト)
  <ホスト>.UITests/    add_ui_tests.py が作る UI テストのプロジェクトと、GreetingDialogUiTests.cs
.slnx / .sln にも登録する。UI テストは、ウォッチャーの trigger_uitest.flag (uitest_once.sh) で実行する。
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import add_layer as AL  # noqa: E402

DLG_ID = {'IDD_GREETING_DIALOG': 3001, 'IDC_GREETING_NAME_EDIT': 3002, 'IDC_GREETING_TEXT': 3003, 'IDC_GREETING_CLEAR_BUTTON': 3004}
UI_WORDS = ('ui', 'view', 'views', 'dialog', 'dialogs')     # mfc_check.py の、画面を持つ層の名前の語と、同じ
EMPTY_TEXT = '名前を入力してください'


def die(msg, code=2):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(code)


# ------------------------------------------------------------------ vcxproj の編集 (既存のプロジェクトに、項目を足す)
def _nl(text):
    return '\r\n' if '\r\n' in text else '\n'


def add_group(text, element_lines):
    """Microsoft.Cpp.targets の import の前に、新しい ItemGroup を足す。"""
    nl = _nl(text)
    tgt = text.rfind('<Import Project="$(VCTargetsPath)\\Microsoft.Cpp.targets"')
    if tgt < 0:
        die('.vcxproj に Microsoft.Cpp.targets の import がない (想定外の形式)')
    ls = text.rfind('\n', 0, tgt) + 1
    return text[:ls] + f'  <ItemGroup>{nl}' + ''.join(element_lines) + f'  </ItemGroup>{nl}' + text[ls:]


def add_item(text, tag, element_lines):
    """同じ種類 (tag) の最後の項目の、ItemGroup の末尾に足す。なければ、新しい ItemGroup。"""
    ms = list(re.finditer(r'<%s Include="' % tag, text))
    if not ms:
        return add_group(text, element_lines)
    end = text.index('</ItemGroup>', ms[-1].start())
    ls = text.rfind('\n', 0, end) + 1
    return text[:ls] + ''.join(element_lines) + text[ls:]


def item_lines(tag, include, nl, filt=None):
    if filt:
        return [f'    <{tag} Include="{include}">{nl}', f'      <Filter>{filt}</Filter>{nl}', f'    </{tag}>{nl}']
    return [f'    <{tag} Include="{include}" />{nl}']


def ref_lines(name, guid, nl):
    return [f'    <ProjectReference Include="..\\{name}\\{name}.vcxproj">{nl}', f'      <Project>{guid}</Project>{nl}', f'    </ProjectReference>{nl}']


def read_text(path):
    return open(path, 'rb').read().decode('utf-8-sig')


def write_bom(path, text):
    with open(path, 'wb') as f:
        f.write(AL.BOM + text.encode('utf-8'))


def tag_of(path):
    return 'ClInclude' if path.endswith('.h') else ('ResourceCompile' if path.endswith('.rc') else 'ClCompile')


def add_to_vcxproj(text, paths):
    nl = _nl(text)
    for p in paths:
        text = add_item(text, tag_of(p), item_lines(tag_of(p), p, nl))
    return text


def add_to_filters(text, paths):
    """フィルターのファイルに足す (そのフィルターが定義されているときだけ。なければ、プロジェクト直下に出る)。"""
    nl = _nl(text)
    for p in paths:
        filt = AL.filter_name_for(p)
        if f'<Filter Include="{filt}">' not in text or not re.search(r'<%s Include="' % tag_of(p), text):
            continue
        text = add_item(text, tag_of(p), item_lines(tag_of(p), p, nl, filt))
    return text


# ------------------------------------------------------------------ ソリューションの読み取り
def solution_projects(sln_path):
    text = read_text(sln_path)
    if sln_path.lower().endswith('.slnx'):
        return [os.path.splitext(os.path.basename(m.group(1)))[0] for m in re.finditer(r'<Project\s+[^>]*?Path="([^"]+\.vcxproj)"', text, re.I)]
    return [os.path.splitext(os.path.basename(m.group(1).replace('\\', '/')))[0]
            for m in re.finditer(r'Project\("\{[^}]+\}"\)\s*=\s*"[^"]*"\s*,\s*"([^"]+\.vcxproj)"', text, re.I)]


def logic_info(sln_dir, sln_path, logic_arg):
    """ロジック層の情報 (なければ None)。"""
    if logic_arg == 'none':
        return None
    names = solution_projects(sln_path)
    if logic_arg:
        if logic_arg not in names:
            die(f'--logic のプロジェクトが、ソリューションにない: {logic_arg}')
        name = logic_arg
    else:
        def is_lib(n):
            vp = os.path.join(sln_dir, n, f'{n}.vcxproj')
            return os.path.isfile(vp) and re.search(r'<ConfigurationType>(?:DynamicLibrary|StaticLibrary)</ConfigurationType>', read_text(vp)) is not None
        found = [n for n in names if re.search(r'logic', n, re.I) and not re.search(r'Tests?$', n) and is_lib(n)]
        if not found:
            return None
        name = found[0]
    info = AL.read_dll_info(sln_dir, name)
    vtext = read_text(os.path.join(sln_dir, name, f'{name}.vcxproj'))
    lib = '<ConfigurationType>StaticLibrary</ConfigurationType>' in vtext
    mfc_std = (not lib) and '_USRDLL' in vtext and '_AFXEXT' not in vtext and 'UseOfMfc' in vtext
    ns = info['ns'] or AL.default_namespace(sln_path)
    return {'name': name, 'guid': info['guid'], 'ns': ns, 'lib': lib, 'mfc_std': mfc_std,
            'api': os.path.isfile(os.path.join(sln_dir, name, f'{name}Api.h')),
            'pch': os.path.isfile(os.path.join(sln_dir, name, 'pch.h')),
            'test': name + 'Test' if os.path.isfile(os.path.join(sln_dir, name + 'Test', f'{name}Test.vcxproj')) else None}


# ------------------------------------------------------------------ ひな形
GREETING_H = '''#pragma once
#include <string>
@@API_INCLUDE@@
namespace @@NS@@
{
    // 画面 (ダイアログ) に表示する挨拶の文を決める規則。画面に依存しない (MFC の型を使わない) ので、単体テストで確かめる。
    @@API@@std::wstring MakeGreeting(const std::wstring& name);
}
'''

GREETING_CPP = '''@@PCH@@#include "Greeting.h"

namespace @@NS@@
{
    std::wstring MakeGreeting(const std::wstring& name)
    {
@@MANAGE@@        if (name.empty())
        {
            return L"@@EMPTY@@";
        }
        return L"こんにちは、" + name + L" さん";
    }
}
'''

GREETING_TEST = '''#include <gtest/gtest.h>
#include "Greeting.h"

TEST(GreetingTest, MakeGreeting_EmptyName_AsksForName)
{
    EXPECT_EQ(@@NS@@::MakeGreeting(L""), L"@@EMPTY@@");
}

TEST(GreetingTest, MakeGreeting_Name_GreetsWithName)
{
    EXPECT_EQ(@@NS@@::MakeGreeting(L"太郎"), L"こんにちは、太郎 さん");
}
'''

RESOURCE_H = '''#pragma once
// ダイアログのリソース ID。値は、呼び出す側の exe の ID と、重ならない範囲 (3000 台) にしてある
// (拡張 DLL は、exe のリソースと、同じ検索の列に入る)。UI テストは、コントロール ID の数値で部品を探す。
#define IDD_GREETING_DIALOG             3001
#define IDC_GREETING_NAME_EDIT          3002
#define IDC_GREETING_TEXT               3003
#define IDC_GREETING_CLEAR_BUTTON       3004

#ifdef APSTUDIO_INVOKED
#ifndef APSTUDIO_READONLY_SYMBOLS
#define _APS_NEXT_RESOURCE_VALUE        3002
#define _APS_NEXT_COMMAND_VALUE         32771
#define _APS_NEXT_CONTROL_VALUE         3005
#define _APS_NEXT_SYMED_VALUE           3000
#endif
#endif
'''

RC = '''#include "Resource.h"
#include "afxres.h"

LANGUAGE LANG_ENGLISH, SUBLANG_ENGLISH_US

IDD_GREETING_DIALOG DIALOGEX 0, 0, 240, 100
STYLE DS_SETFONT | DS_MODALFRAME | DS_FIXEDSYS | WS_POPUP | WS_CAPTION | WS_SYSMENU
CAPTION "Greeting"
FONT 9, "MS Shell Dlg", 0, 0, 0x1
BEGIN
    LTEXT           "&Name:",IDC_STATIC,7,9,30,8
    EDITTEXT        IDC_GREETING_NAME_EDIT,40,7,193,14,ES_AUTOHSCROLL
    LTEXT           "",IDC_GREETING_TEXT,7,30,226,8
    PUSHBUTTON      "&Clear",IDC_GREETING_CLEAR_BUTTON,7,79,50,14
    DEFPUSHBUTTON   "OK",IDOK,129,79,50,14
    PUSHBUTTON      "Cancel",IDCANCEL,183,79,50,14
END
'''

DIALOG_H = '''#pragma once
#include <afxwin.h>
#include "Resource.h"

// DLL が提供する画面 (名前を入れると、挨拶を表示する)。表示する文は、画面に依存しない規則 (MakeGreeting) が決める。
class @@EXPORT@@GreetingDialog : public CDialog
{
    DECLARE_DYNAMIC(GreetingDialog)

public:
    enum { IDD = IDD_GREETING_DIALOG };

    explicit GreetingDialog(CWnd* parent = nullptr);

protected:
    BOOL OnInitDialog() override;

    afx_msg void OnNameChanged();
    afx_msg void OnClear();
    DECLARE_MESSAGE_MAP()

private:
    // 入力欄の内容から、挨拶の表示と、クリアボタンの有効・無効を更新する。
    void Refresh();
};
'''

DIALOG_CPP = '''#include "pch.h"
#include "GreetingDialog.h"
@@INCLUDES@@
IMPLEMENT_DYNAMIC(GreetingDialog, CDialog)

GreetingDialog::GreetingDialog(CWnd* parent)
    : CDialog(IDD, parent)
{
}

BOOL GreetingDialog::OnInitDialog()
{
    CDialog::OnInitDialog();
    Refresh();
    return TRUE;
}

void GreetingDialog::OnNameChanged()
{
    Refresh();
}

void GreetingDialog::OnClear()
{
    // 入力欄を空にすると、EN_CHANGE で Refresh() が呼ばれる。
    SetDlgItemText(IDC_GREETING_NAME_EDIT, L"");
    // クリアボタンが無効になるので、フォーカスを入力欄へ戻す。
    GetDlgItem(IDC_GREETING_NAME_EDIT)->SetFocus();
}

void GreetingDialog::Refresh()
{
    CString name;
    GetDlgItemText(IDC_GREETING_NAME_EDIT, name);
@@GREETING@@
    GetDlgItem(IDC_GREETING_CLEAR_BUTTON)->EnableWindow(!name.IsEmpty());
}

BEGIN_MESSAGE_MAP(GreetingDialog, CDialog)
    ON_EN_CHANGE(IDC_GREETING_NAME_EDIT, &GreetingDialog::OnNameChanged)
    ON_BN_CLICKED(IDC_GREETING_CLEAR_BUTTON, &GreetingDialog::OnClear)
END_MESSAGE_MAP()
@@SHOW@@'''

GREETING_VIA_LOGIC = '''    const std::wstring greeting = @@LNS@@::MakeGreeting(std::wstring(name.GetString()));
    SetDlgItemText(IDC_GREETING_TEXT, greeting.c_str());'''

GREETING_INLINE = '''    // ロジック層がないので、挨拶の文を、ここで決めている (ロジック層を作ったら、画面に依存しない関数に、切り出す)。
    CString greeting;
    if (name.IsEmpty())
    {
        greeting = L"@@EMPTY@@";
    }
    else
    {
        greeting.Format(L"こんにちは、%s さん", static_cast<LPCWSTR>(name));
    }
    SetDlgItemText(IDC_GREETING_TEXT, greeting);'''

SHOW_H = '''#pragma once
#include <windows.h>
#include "@@NAME@@Api.h"

namespace @@NS@@
{
    // 画面 (GreetingDialog) を、モーダルで開く。戻り値は、IDOK か IDCANCEL。parent は、nullptr でよい。
    @@UP@@_API int ShowGreetingDialog(HWND parent);
}
'''

SHOW_CPP = '''
namespace @@NS@@
{
    int ShowGreetingDialog(HWND parent)
    {
        // 共有 MFC の標準 DLL: エクスポートする関数は、先頭で、これを呼ぶ (オブジェクト変数の宣言よりも前)。
        AFX_MANAGE_STATE(AfxGetStaticModuleState());
        GreetingDialog dialog(CWnd::FromHandle(parent));
        return static_cast<int>(dialog.DoModal());
    }
}
'''

HOST_STD_MAIN = '''#include <windows.h>
#include "ShowGreeting.h"

// 画面ホスト: UI DLL の画面を開くだけの exe。ダイアログが、そのまま、メインウィンドウになる (UI テストが、この exe を起動する)。
int APIENTRY wWinMain(_In_ HINSTANCE, _In_opt_ HINSTANCE, _In_ LPWSTR, _In_ int)
{
    return @@NS@@::ShowGreetingDialog(nullptr) == IDOK ? 0 : 1;
}
'''

HOST_EXT_PCH = '''#pragma once
#include <SDKDDKVer.h>
#define VC_EXTRALEAN
#include <afxwin.h>
#include <afxext.h>
'''

HOST_EXT_APP_H = '''#pragma once
#include "pch.h"

// 画面ホスト: UI DLL (MFC 拡張 DLL) の画面を開くだけの exe。ダイアログが、そのまま、メインウィンドウになる。
class HostApp : public CWinApp
{
public:
    BOOL InitInstance() override;
};
'''

HOST_EXT_APP_CPP = '''#include "pch.h"
#include "HostApp.h"
#include "GreetingDialog.h"

HostApp theApp;

BOOL HostApp::InitInstance()
{
    // DPI 認識モードは、.vcxproj のマニフェストツールの設定 (EnableDpiAwareness) で、宣言している。
    CWinApp::InitInstance();

    GreetingDialog dialog;
    m_pMainWnd = &dialog;
    dialog.DoModal();

    // ダイアログを閉じたら、メッセージループに入らずに、アプリケーションを終える。
    return FALSE;
}
'''

UITESTS_CS = '''using FlaUI.Core.AutomationElements;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace @@NS@@;

/// <summary>@@UI@@ (@@KIND@@) が提供する画面 (GreetingDialog) の、煙テスト。
/// 画面ホスト (@@HOST@@.exe) が、ダイアログを、そのまま、メインウィンドウとして開く。部品は、リソースのコントロール ID の数値で探す (@@UI@@/Resource.h)。
/// 挨拶の文の規則は、ロジック層の単体テスト (TestGreeting.cpp) で確かめる。ここは、画面と規則が、つながっていることを確かめる。</summary>
[TestClass]
public class GreetingDialogUiTests : UiTestBase
{
    private const string NameEdit = "3002";
    private const string GreetingText = "3003";
    private const string ClearButton = "3004";

    [TestMethod]
    public void GreetingDialog_Opened_AsksForName()
    {
        Assert.IsTrue(WaitFor(() => Find(GreetingText).Name == "@@EMPTY@@"));
        Assert.IsFalse(Find(ClearButton).IsEnabled);
    }

    [TestMethod]
    public void GreetingDialog_NameEntered_ShowsGreeting()
    {
        Find(NameEdit).AsTextBox().Text = "太郎";   // ValuePattern (キー入力を使わない)
        Assert.IsTrue(WaitFor(() => Find(GreetingText).Name == "こんにちは、太郎 さん"));
        Assert.IsTrue(Find(ClearButton).IsEnabled);
    }

    [TestMethod]
    public void GreetingDialog_ClearClicked_EmptiesNameAndAsksForName()
    {
        Find(NameEdit).AsTextBox().Text = "太郎";
        Assert.IsTrue(WaitFor(() => Find(ClearButton).IsEnabled));
        UiDialogs.Click(Find(ClearButton));
        Assert.IsTrue(WaitFor(() => Find(NameEdit).AsTextBox().Text == ""));
        Assert.IsTrue(WaitFor(() => Find(GreetingText).Name == "@@EMPTY@@"));
    }
}
'''


def fill(t, **kv):
    for k, v in kv.items():
        t = t.replace(f'@@{k}@@', v)
    return t


def claude_md_section(ui, host, kind, logic):
    lk = 'MFC 標準 DLL (共有 MFC)' if kind == 'mfc-std-dll' else 'MFC 拡張 DLL'
    out = f'''
## 画面を持つ DLL (UI DLL) と、画面ホスト
- `{ui}`: {lk}。サンプルのダイアログ (`GreetingDialog`。`{ui}/Resource.h` の ID は 3000 台) を提供する。**画面を持つ層なので、`mfc-check` の LAY001 / LAY002 (ライブラリの GUI) の対象外** (名前に Ui / View / Dialog を含む DLL)。
- `{host}`: 画面ホストの exe。UI DLL の画面を開くだけで、ダイアログが、そのまま、メインウィンドウになる。**UI テスト (`{host}.UITests`) は、この exe を起動する。**
'''
    if kind == 'mfc-std-dll':
        out += '- 標準 DLL の公開関数 (`ShowGreetingDialog`) は、先頭で `AFX_MANAGE_STATE(AfxGetStaticModuleState());` を呼ぶ。ホストは、MFC なしの Win32 exe。\n'
    else:
        out += '- 拡張 DLL の画面は、ホスト (MFC の exe。`UseOfMfc=Dynamic`) のリソースの検索の列に入る。ホストの ID は、3000 より小さい値にする。\n'
    if logic:
        out += f'- 画面の規則 (挨拶の文) は、ロジック層 `{logic["name"]}` の `Greeting.h` (`MakeGreeting`)。画面に依存しないので、単体テスト (`TestGreeting.cpp`) で確かめ、UI テストは、つながりと主要な操作だけを確かめる。\n'
    else:
        out += '- ロジック層がないので、挨拶の文は、ダイアログの中に書いてある。ロジック層を作ったら、画面に依存しない関数に切り出す。\n'
    return out


def main():
    ap = argparse.ArgumentParser(description='画面を持つ MFC の DLL と、画面ホストの exe と、UI テストを足す')
    ap.add_argument('sln_dir')
    ap.add_argument('--name', default='UiLayer')
    ap.add_argument('--kind', choices=['mfc-std-dll', 'mfc-ext-dll'], default='mfc-std-dll')
    ap.add_argument('--logic')
    ap.add_argument('--host-name')
    ap.add_argument('--namespace')
    ap.add_argument('--toolset')
    ap.add_argument('--no-ui-tests', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    ident = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
    ui = a.name
    host = a.host_name or f'{ui}Host'
    for n in (ui, host):
        if not ident.match(n):
            die(f'名前が不正 (英数字と _ のみ、先頭は英字か _): {n}')
    if 'viewmodel' in ui.lower() or not any(t.lower() in UI_WORDS for t in re.findall(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+', ui)):
        print(f'NOTE: {ui} の名前に Ui / View / Dialog の語がないので、mfc-check は、ライブラリの GUI (LAY001) を、指摘する。--ui {ui} で、画面を持つ層として、指定する')
    if re.search(r'Tests?$', ui) or re.search(r'Tests?$', host):
        die('名前が Test で終わるものは、使えない (ウォッチャーが、テストとして実行する)')
    sln_dir = os.path.abspath(a.sln_dir)
    if not os.path.isdir(sln_dir):
        die(f'フォルダがない: {sln_dir}')
    sln = AL.find_solution(sln_dir)
    sln_text = read_text(sln)
    for d in (ui, host):
        if os.path.exists(os.path.join(sln_dir, d)) or re.search(r'["/\\]' + re.escape(d) + r'\.vcxproj', sln_text):
            die(f'すでに存在する: {d} (何も書いていない)', 3)

    toolset = a.toolset or AL.detect_toolset(sln_dir)
    AL.set_platforms(AL.detect_platforms(sln_dir))   # 新しい画面ホストは、このソリューションのプラットフォームに、そろえる
    ns = a.namespace or AL.default_namespace(sln)
    up = ui.upper()
    logic = logic_info(sln_dir, sln, a.logic)
    if logic:
        gh, gc = (os.path.join(sln_dir, logic['name'], f) for f in ('Greeting.h', 'Greeting.cpp'))
        if os.path.exists(gh) or os.path.exists(gc):
            die(f'すでに存在する: {logic["name"]}/Greeting.h または Greeting.cpp (何も書いていない)', 3)

    ug, hg = AL.new_guid(), AL.new_guid()
    files, plain, edits = {}, {}, {}      # 新しいファイル (BOM 付き) / 新しいファイル (BOM なし。.rc) / 既存のファイルの編集 (パス -> 関数)

    # ---- UI DLL
    uses = [logic['name']] if logic else []
    base = AL.dll_files(ui, ns, uses, toolset, ug, kind=a.kind)
    std = a.kind == 'mfc-std-dll'
    new_items = ['GreetingDialog.h', 'GreetingDialog.cpp', f'{ui}.rc', 'Resource.h'] + (['ShowGreeting.h'] if std else [])
    vtext = base[f'{ui}/{ui}.vcxproj']
    vtext = add_to_vcxproj(vtext, new_items)
    if logic:
        vtext = add_group(vtext, ref_lines(logic['name'], logic['guid'], _nl(vtext)))
    base[f'{ui}/{ui}.vcxproj'] = vtext
    all_items = [m.group(1) for m in re.finditer(r'<(?:ClInclude|ClCompile|ResourceCompile) Include="([^"]+)"', vtext)]
    base[f'{ui}/{ui}.vcxproj.filters'] = AL.vcxproj_filters(all_items)
    files.update(base)
    includes = ('#include "Greeting.h"\n' if logic else '') + ('#include "ShowGreeting.h"\n' if std else '')
    greeting = (fill(GREETING_VIA_LOGIC, LNS=logic['ns']) if logic else fill(GREETING_INLINE, EMPTY=EMPTY_TEXT))
    files[f'{ui}/GreetingDialog.h'] = fill(DIALOG_H, EXPORT='' if std else 'AFX_EXT_CLASS ')
    files[f'{ui}/GreetingDialog.cpp'] = fill(DIALOG_CPP, INCLUDES=includes, GREETING=greeting,
                                             SHOW=fill(SHOW_CPP, NS=ns) if std else '')
    files[f'{ui}/Resource.h'] = RESOURCE_H
    plain[f'{ui}/{ui}.rc'] = RC
    if std:
        files[f'{ui}/ShowGreeting.h'] = fill(SHOW_H, NAME=ui, NS=ns, UP=up)

    # ---- 画面ホスト
    if std:
        items = ['main.cpp']
        files[f'{host}/main.cpp'] = fill(HOST_STD_MAIN, NS=ns)
        files[f'{host}/{host}.vcxproj'] = AL.vcxproj(host, hg, 'Application', toolset, items, [(ui, ug)], [f'$(ProjectDir)..\\{ui}'], '_WINDOWS;', 'Windows')
    else:
        items = ['pch.h', 'HostApp.h', 'HostApp.cpp']
        files[f'{host}/pch.h'] = HOST_EXT_PCH
        files[f'{host}/HostApp.h'] = HOST_EXT_APP_H
        files[f'{host}/HostApp.cpp'] = HOST_EXT_APP_CPP
        files[f'{host}/{host}.vcxproj'] = AL.vcxproj(host, hg, 'Application', toolset, items, [(ui, ug)], [f'$(ProjectDir)..\\{ui}'], '_WINDOWS;', 'Windows', mfc=True)
    files[f'{host}/{host}.vcxproj.filters'] = AL.vcxproj_filters(items)
    projects = [(ui, ug), (host, hg)]

    # ---- ロジック層 (規則) と、その単体テスト
    notes = []
    if logic:
        ln = logic['name']
        manage = '        // 共有 MFC の標準 DLL: エクスポートする関数は、先頭で、これを呼ぶ (オブジェクト変数の宣言よりも前)。\n' \
                 '        AFX_MANAGE_STATE(AfxGetStaticModuleState());\n' if logic['mfc_std'] else ''
        api = '' if logic['lib'] or not logic['api'] else f'{ln.upper()}_API '
        files[f'{ln}/Greeting.h'] = fill(GREETING_H, NS=logic['ns'], API=api, API_INCLUDE=f'#include "{ln}Api.h"\n' if api else '')
        files[f'{ln}/Greeting.cpp'] = fill(GREETING_CPP, NS=logic['ns'], EMPTY=EMPTY_TEXT, MANAGE=manage,
                                           PCH='#include "pch.h"\n' if logic['pch'] else '')
        for fn in ('.vcxproj', '.vcxproj.filters'):
            p = f'{ln}/{ln}{fn}'
            if os.path.isfile(os.path.join(sln_dir, p)):
                edits[p] = (lambda t, fn=fn: (add_to_vcxproj if fn == '.vcxproj' else add_to_filters)(t, ['Greeting.h', 'Greeting.cpp']))
        if logic['test']:
            tn = logic['test']
            files[f'{tn}/TestGreeting.cpp'] = fill(GREETING_TEST, NS=logic['ns'], EMPTY=EMPTY_TEXT)
            for fn in ('.vcxproj', '.vcxproj.filters'):
                p = f'{tn}/{tn}{fn}'
                if os.path.isfile(os.path.join(sln_dir, p)):
                    edits[p] = (lambda t, fn=fn: (add_to_vcxproj if fn == '.vcxproj' else add_to_filters)(t, ['TestGreeting.cpp']))
        else:
            notes.append(f'NOTE: {ln} のテストのプロジェクトがないので、Greeting の単体テストは、作らない (cpp-test-first の add_layer.py --tests-only で、足せる)')
    else:
        notes.append('NOTE: ロジック層がないので、挨拶の文は、ダイアログの中に書いた。ロジック層を作ったら、画面に依存しない関数に、切り出す')

    print(f'ソリューション : {os.path.basename(sln)}')
    print(f'UI DLL         : {ui} ({"MFC 標準 DLL (共有 MFC)" if std else "MFC 拡張 DLL"})')
    print(f'画面ホスト     : {host} ({"MFC なしの Win32 exe" if std else "MFC の exe (UseOfMfc=Dynamic)"})')
    print(f'ロジック層     : {logic["name"] if logic else "なし"}')
    print(f'名前空間       : {ns}')
    for rel in list(files) + list(plain):
        print(f'  + {rel}')
    for rel in edits:
        print(f'  ~ {rel}')
    print(f'  ~ {os.path.basename(sln)} ({len(projects)} プロジェクトを追加: {", ".join(n for n, _ in projects)})')
    if not a.no_ui_tests:
        print(f'  + {host}.UITests/ (add_ui_tests.py --app {host}) と GreetingDialogUiTests.cs')
    for n in notes:
        print(n)
    if a.dry_run:
        print('(dry-run: 何も書いていない)')
        return

    AL.write_files(sln_dir, files)
    for rel, text in plain.items():
        p = os.path.join(sln_dir, *rel.split('/'))
        with open(p, 'wb') as f:
            f.write(AL.to_crlf(text).encode('ascii'))
    for rel, fn in edits.items():
        p = os.path.join(sln_dir, *rel.split('/'))
        write_bom(p, fn(read_text(p)))
    AL.register(sln, projects)

    md = os.path.join(sln_dir, 'CLAUDE.md')
    if os.path.isfile(md):
        t = read_text(md)
        if '## 画面を持つ DLL (UI DLL)' not in t:
            bom = open(md, 'rb').read(3) == AL.BOM
            with open(md, 'wb') as f:
                f.write((AL.BOM if bom else b'') + (t.rstrip('\n') + '\n' + claude_md_section(ui, host, a.kind, logic)).encode('utf-8'))

    if not a.no_ui_tests:
        script = os.path.join(HERE, '..', '..', 'new-solution', 'scripts', 'add_ui_tests.py')
        if not os.path.isfile(script):
            die('add_ui_tests.py が見つからない (new-solution Skill も、配布されている必要がある)')
        sys.stdout.flush()
        r = subprocess.run([sys.executable, '-I', script, sln_dir, '--app', host])
        if r.returncode != 0:
            sys.exit(r.returncode)
        csproj = os.path.join(sln_dir, f'{host}.UITests', f'{host}.UITests.csproj')
        m = re.search(r'<RootNamespace>([^<]+)</RootNamespace>', read_text(csproj)) if os.path.isfile(csproj) else None
        root = m.group(1) if m else f'{host}.UITests'
        AL.write_files(sln_dir, {f'{host}.UITests/GreetingDialogUiTests.cs': fill(
            UITESTS_CS, NS=root, UI=ui, KIND='MFC 標準 DLL' if std else 'MFC 拡張 DLL', HOST=host, EMPTY=EMPTY_TEXT)})
        print(f'  + {host}.UITests/GreetingDialogUiTests.cs')
    print('完了。')


if __name__ == '__main__':
    main()
