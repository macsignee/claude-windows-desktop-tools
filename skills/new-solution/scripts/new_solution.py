#!/usr/bin/env python3
"""new_solution.py - フォルダの中に、「フォルダ名と同名の .slnx」と、メインのプロジェクト (と、必要なら層・テスト) を作る。

Usage:
  新規:        python3 new_solution.py <FOLDER> --type mfc|win32|console|dll|lib --layers none|logic|data|logic,data
                                       --tests none|gtest [--layer-kind dll|lib] [--namespace NS] [--toolset v145]
                                       [--gtest auto|nuget|source] [--gtest-from DIR] [--dry-run]
               または、--spec <仕様書> で、仕様書の「構成案」から、省略した項目を読み取る (明示した引数が優先)
  改行コードの規則 (.gitattributes) の確認と追加 (すでにあるプロジェクト用):
               python3 new_solution.py <FOLDER> --check-git          (読み取りだけ。状態と、提案の要否を出す)
               python3 new_solution.py <FOLDER> --add-gitattributes  (最小版の .gitattributes を作る。git の操作は、しない)
  テストの後付け: python3 new_solution.py <FOLDER> --tests gtest [--gtest auto|nuget|source] [--gtest-from DIR] [--dry-run]
                 (すでにソリューションがあるフォルダで。テストのない DLL に、対応するテスト exe を足す)

  FOLDER   ソリューションを作るフォルダ。**フォルダ名が、ソリューション名・メインのプロジェクト名になる**
           (例: .../MFCTDDTest -> MFCTDDTest.slnx と、MFCTDDTest/MFCTDDTest.vcxproj)
  --type   メインの種類: mfc (MFC SDI) / win32 (Win32 デスクトップ) / console / dll / lib (静的ライブラリ)
  --layers 作る層: logic -> LogicLayer、data -> DataLayer。none は、層を作らない。
           名前を変えるなら logic:OrderLogic,data:OrderData のように指定する (省略時の既定の名前は、作成後に変更もできる)
  --layer-kind 層の種類: dll (既定) / lib (静的ライブラリ)。全部の層に、同じ種類を使う
  --tests  gtest: 作った DLL / 静的ライブラリ (層と、メインが dll / lib ならメイン) に、<名前>Test (GoogleTest の exe) を作る。none: テストを作らない
  --gtest  GoogleTest の入れ方: auto (既定。パッケージをコピーできれば nuget、なければ source) / nuget / source (ThirdParty/googletest をビルド。
           ソースは、ウォッチャー経由で取得する: gtest_once.sh)
  --spec   仕様書 (docs/specs/*.md) の「## 構成案」の、次の行を読む: - メインの種類: / - 層: / - 層の種類: / - テスト: / - 名前空間:

組み合わせの注意: メインが exe で --layers none のとき、--tests gtest は、テスト対象がないので、エラー (終了コード 2)。
          メインが dll / lib なら、メイン自身がテスト対象。
新規作成では、CLAUDE.md / .gitignore / .gitattributes (改行コードの規則。拡張子を列挙しない最小版) も作る (どれも、すでにあれば、上書きしない)。
テストの後付け (すでにソリューションがある) では、これらを作らない。
x64 の Debug / Release だけ。GoogleTest の nuget 方式は、既存の packages\\ をコピーする (このスクリプトは、ネットワークを使わない)。

終了コード: 0 成功 / 2 引数・組み合わせ・フォルダの問題 / 3 すでにある (何も書かない)
このスクリプトは、同じ skills フォルダの cpp-test-first/scripts/add_layer.py を、読み込んで使う。
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
KIND = {'mfc': 'MFC SDI', 'win32': 'Win32 デスクトップ', 'console': 'コンソール', 'dll': 'DLL', 'lib': '静的ライブラリ'}
LIBRARY_TYPES = ('dll', 'lib')   # メイン自身が、テストの対象になる種類
LAYER_NAMES = {'data': 'DataLayer', 'logic': 'LogicLayer'}   # 作る順 (依存される側から)

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

GITIGNORE = '''.vs/
x64/
obj/
*.user
# GoogleTest: NuGet 方式のパッケージ (packages\\ にコピーしたもの) と、ソース方式のソース (ウォッチャーが取得したもの)
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


def claude_md(name, kind, layers, tests, layer_kind='dll', gtest_mode='nuget'):
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
- Windows 側のウォッチャー (`run_watcher.cmd`) 経由で、Skill (`cpp-auto-build` / `cpp-build-test-loop`) が行う。出力先: `x64\Debug\`。
- 新しい `.cpp` / `.h` は、`.vcxproj` (と `.filters`) に追加する。
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
        else:
            out += r"""- GoogleTest は、NuGet のパッケージを `packages\` にコピーしたもの。ウォッチャーは、NuGet を復元しない。
"""
    out += """
## 規約
- C++20。ファイルは UTF-8 (BOM 付き)、改行は CRLF。`.rc` は ASCII。
- `git commit` / `git push` は、ユーザーの指示があるときだけ。
"""
    return out


def update_claude_md_tests(folder, name, gmode='nuget'):
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
                 '- GoogleTest は、NuGet のパッケージを `packages\\` にコピーしたもの。ウォッチャーは、NuGet を復元しない。')
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


def parse_layers(v):
    """'none' / 'logic' / 'data' / 'logic,data' / 'logic:OrderLogic,data:OrderData' -> [(key, 名前), ...] (データが先)"""
    if v == 'none':
        return []
    got = {}
    for t in v.split(','):
        key, _, nm = t.strip().partition(':')
        if key not in LAYER_NAMES:
            die(f'--layers の値が不正: {t.strip()} (none / logic / data / logic,data。名前は logic:OrderLogic のように指定できる)')
        nm = nm.strip() or LAYER_NAMES[key]
        if not IDENT.match(nm):
            die(f'層の名前が不正 (英数字と _ のみ、先頭は英字か _): {nm}')
        got[key] = nm
    return [(k, got[k]) for k in ('data', 'logic') if k in got]


def existing_solutions(folder):
    return [f for f in sorted(os.listdir(folder)) if f.lower().endswith(('.sln', '.slnx'))]


def slnx_text(projects):
    out = '<Solution>\n  <Configurations>\n    <BuildType Name="Debug" />\n    <BuildType Name="Release" />\n    <Platform Name="x64" />\n  </Configurations>\n'
    for n, g in projects:
        out += f'  <Project Path="{n}/{n}.vcxproj" Id="{g.strip("{}").lower()}" />\n'
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
        for fn, body in MFC_FILES.items():
            files[f'{name}/{fn}'] = body.replace('@@NAME@@', name)
        rc = f'{name}.rc'
        files[f'{name}/{rc}'] = MFC_RC.replace('@@NAME@@', name)
        plain.add(f'{name}/{rc}')
        items = list(MFC_FILES) + [rc]
        files[f'{name}/{name}.vcxproj'] = AL.vcxproj(name, guid, 'Application', toolset, items, [], [], '_WINDOWS;', 'Windows', mfc=True)
        files[f'{name}/{name}.vcxproj.filters'] = AL.vcxproj_filters(items)
    return files, plain


def create_mode(a, folder, name):
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
            if a.type in ('mfc', 'win32', 'console') and re.search(r'(Test|Tests)$', name):
                print(f'MAIN_EXE_TARGETNAME: {name} -> {name}_Main (予定)')
        print('(dry-run: 何も書いていない)')
        return

    os.makedirs(folder, exist_ok=True)
    AL.write_files(folder, {k: v for k, v in files.items() if k not in plain})
    for rel in plain:
        write_plain(folder, rel, files[rel], crlf=True)
    write_plain(folder, f'{name}.slnx', slnx_text(projects), crlf=True)
    if 'CLAUDE.md' in extras:
        write_plain(folder, 'CLAUDE.md', claude_md(name, KIND[a.type], layers, tests, lkind, gmode or 'nuget'))
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


SPEC_KEYS = {'メインの種類': 'type', '層': 'layers', '層の種類': 'layer_kind', 'テスト': 'tests', '名前空間': 'namespace'}
SPEC_ALLOWED = {'type': ('mfc', 'win32', 'console', 'dll', 'lib'), 'layer_kind': ('dll', 'lib'), 'tests': ('none', 'gtest')}


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
        if getattr(a, key, None) is None:
            setattr(a, key, val)
            used.append(f'{key}={val}')
    print(f'構成案 ({a.spec}) から読み取った: {", ".join(used) if used else "(なし。すべて、引数で指定済み、または、構成案で未定)"}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('folder')
    ap.add_argument('--type', choices=['mfc', 'win32', 'console', 'dll', 'lib'])
    ap.add_argument('--layers')
    ap.add_argument('--tests', choices=['none', 'gtest'])
    ap.add_argument('--namespace')
    ap.add_argument('--toolset')
    ap.add_argument('--gtest-from')
    ap.add_argument('--gtest', choices=['auto', 'nuget', 'source'])
    ap.add_argument('--layer-kind', choices=['dll', 'lib'])
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
    if sols:
        if a.tests == 'gtest':
            add_tests_mode(a, folder, name, sols[0])
        else:
            die(f'すでにソリューションがある ({sols[0]})。何も書いていない。テストを後付けするなら、--tests gtest だけを指定する', 3)
    else:
        create_mode(a, folder, name)


if __name__ == '__main__':
    main()
