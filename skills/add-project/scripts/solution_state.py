#!/usr/bin/env python3
"""solution_state.py - ソリューションの現状を読む (読み取りだけ。何も書かない)。/add-project が、何を足せるかを決めるために使う。

Usage: python3 solution_state.py <SLN_DIR>

  SLN_DIR  .sln または .slnx があるフォルダ。プロジェクトは、<SLN_DIR>/<名前>/<名前>.vcxproj (C++) または .csproj (.NET) の形だけを読む
           (add_layer.py / add_project.py / new_solution.py が作る形)。

出力 (1 行が 1 項目。`キー: 値`):
  SOLUTION       ソリューションのパス
  KIND           cpp / dotnet / mixed (C++ のプロジェクトと、UI テスト以外の C# のプロジェクトが、両方ある)
  MAIN           メイン (CLAUDE.md の `- メイン:` があればそれ。なければ、最初の exe)
  CLAUDE_MD      present / absent と、読み取った 3 行 (メイン / 層 / テスト)
  PROJECT        名前 | 種類 | 役割 | テスト | プロジェクト参照 | include だけの参照 (C++)
                 種類: exe / console-exe / dll / lib / mfc-ext-dll / mfc-std-dll / wpf-app / winforms-app / console-app / classlib / test / uitest
                 役割: main / data / logic / viewmodel / ui / test / uitest / other
  MISMATCH       CLAUDE.md と、実際の構成の食い違い (層の記録、テストの有無、「追加した層」の行のテストの有無)
  REF_ISSUES     層の参照の向きの違反 (下の層が、上の層を参照している。メイン → 画面 → ViewModel → ロジック → データ)
  SUGGEST_REF    どこからも参照されていない層と、参照するのが自然なプロジェクト (使う側 -> 層)
  ADDABLE        足せるもの | 説明 | dry-run の例 (そのまま、実行できる形ではない。< > を埋める)

終了コード: 0 / 2 ソリューションが見つからない / 3 ソリューションが複数ある
"""
import argparse
import os
import re
import sys

UI_WORDS = ('ui', 'view', 'views', 'dialog', 'dialogs')
RANK = {'main': 0, 'ui': 1, 'viewmodel': 2, 'logic': 3, 'data': 4}
SCRIPTS = '~/.claude/skills'


def read_text(path):
    try:
        return open(path, encoding='utf-8-sig').read().replace('\r\n', '\n')
    except OSError:
        return ''


def split_words(name):
    return [w.lower() for w in re.findall(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+', name)]


def role_of_name(name):
    low = name.lower()
    words = split_words(name)
    if 'viewmodel' in low:          # ViewModels は 'View' を含むが、画面の層ではない (先に判定する)
        return 'viewmodel'
    if any(w in UI_WORDS for w in words):
        return 'ui'
    if 'logic' in low:
        return 'logic'
    if 'data' in low:
        return 'data'
    return 'other'


def find_solutions(sln_dir):
    return [f for f in sorted(os.listdir(sln_dir)) if f.lower().endswith(('.sln', '.slnx'))]


def classify_vcx(name, text):
    cfg = re.search(r'<ConfigurationType>(\w+)</ConfigurationType>', text)
    cfg = cfg.group(1) if cfg else ''
    mfc = re.search(r'<UseOfMfc>(Dynamic|Static)</UseOfMfc>', text) is not None
    defs = ' '.join(re.findall(r'<PreprocessorDefinitions>([^<]*)</PreprocessorDefinitions>', text))
    console = re.search(r'<SubSystem>Console</SubSystem>', text) is not None
    if cfg == 'Application':
        kind = 'console-exe' if console else 'exe'
    elif cfg == 'DynamicLibrary':
        kind = 'dll'
        if '_AFXEXT' in defs:
            kind = 'mfc-ext-dll'
        elif '_USRDLL' in defs and mfc:
            kind = 'mfc-std-dll'
    elif cfg == 'StaticLibrary':
        kind = 'lib'
    else:
        kind = 'other'
    refs = re.findall(r'<ProjectReference Include="\.\.\\([\w.]+)\\', text)
    uses = [u for u in dict.fromkeys(re.findall(r'\$\(ProjectDir\)\.\.\\([\w.]+)', text)) if u != name]
    return {'kind': kind, 'mfc': mfc, 'refs': list(dict.fromkeys(refs)), 'uses': uses, 'lang': 'cpp'}


def classify_cs(name, text):
    out_type = re.search(r'<OutputType>(\w+)</OutputType>', text)
    out_type = out_type.group(1) if out_type else 'Library'
    wpf = re.search(r'<UseWPF>\s*true\s*</UseWPF>', text, re.I) is not None
    wf = re.search(r'<UseWindowsForms>\s*true\s*</UseWindowsForms>', text, re.I) is not None
    is_ui_test = re.search(r'(UI|Ui)Tests$', name) is not None or 'FlaUI.' in text
    is_test = (not is_ui_test) and (name.endswith(('.Tests', 'Test', 'Tests'))
                                    or 'Microsoft.NET.Test.Sdk' in text
                                    or re.search(r'<IsTestProject>\s*true', text) is not None)
    if is_ui_test:
        kind = 'uitest'
    elif is_test:
        kind = 'test'
    elif wpf and out_type in ('WinExe', 'Exe'):
        kind = 'wpf-app'
    elif wf and out_type in ('WinExe', 'Exe'):
        kind = 'winforms-app'
    elif out_type in ('WinExe', 'Exe'):
        kind = 'console-app'
    else:
        kind = 'classlib'
    refs = re.findall(r'<ProjectReference Include="\.\.\\([\w.]+)\\', text)
    return {'kind': kind, 'mfc': False, 'refs': list(dict.fromkeys(refs)), 'uses': [], 'lang': 'cs'}


def test_target(name):
    for suf in ('.UITests', '.UiTests', '.Tests', 'Tests', 'Test'):
        if name.endswith(suf) and len(name) > len(suf):
            return name[:-len(suf)]
    return None


def scan(sln_dir):
    projects = {}
    for d in sorted(os.listdir(sln_dir)):
        full = os.path.join(sln_dir, d)
        if not os.path.isdir(full):
            continue
        for ext, fn in (('.vcxproj', classify_vcx), ('.csproj', classify_cs)):
            p = os.path.join(full, d + ext)
            if os.path.isfile(p):
                info = fn(d, read_text(p))
                if info['lang'] == 'cpp' and test_target(d) and d.endswith(('Test', 'Tests')):
                    info['kind'] = 'test'
                info['name'] = d
                projects[d] = info
                break
    return projects


def claude_settings(sln_dir):
    text = read_text(os.path.join(sln_dir, 'CLAUDE.md'))
    if not text:
        return None
    def line(key):
        m = re.search(r'^- ' + key + r':\s*(.+)$', text, re.M)
        return m.group(1).strip() if m else None
    return {'text': text, 'main': line('メイン'), 'layers': line('層'), 'tests': line('テスト')}


def main_of(projects, settings):
    if settings and settings['main']:
        m = re.match(r'(\S+)', settings['main'])
        return m.group(1), settings['main']
    for n, p in projects.items():
        if p['kind'] in ('exe', 'console-exe', 'wpf-app', 'winforms-app', 'console-app'):
            return n, f'{n} ({p["kind"]})'
    return None, None


EXPLICIT_ROLES = ('data', 'logic', 'viewmodel', 'ui')


def explicit_roles(settings):
    """CLAUDE.md の「- 層:」の行の、「役割:名前」(例 logic:ExtLayer) -> {名前: 役割}。名前に役割の語がない層の、役割を決める。"""
    out = {}
    for item in re.split(r'[,、]', (settings or {}).get('layers') or ''):
        m = re.match(r'\s*(data|logic|viewmodel|ui)\s*:\s*([\w.]+)', item)
        if m:
            out[m.group(2)] = m.group(1)
    return out


def assign_roles(projects, main_name, settings=None):
    explicit = explicit_roles(settings)
    for n, p in projects.items():
        if p['kind'] == 'test':
            p['role'] = 'test'
        elif p['kind'] == 'uitest':
            p['role'] = 'uitest'
        elif n == main_name or p['kind'] in ('exe', 'console-exe', 'wpf-app', 'winforms-app', 'console-app'):
            p['role'] = 'main'
        else:
            p['role'] = explicit.get(n) or role_of_name(n)


def tests_of(projects):
    """{対象の名前: テストプロジェクトの名前}"""
    out = {}
    for n, p in projects.items():
        if p['role'] == 'test':
            t = test_target(n)
            if t:
                out[t] = n
    return out


def uitests_of(projects):
    out = {}
    for n, p in projects.items():
        if p['role'] == 'uitest':
            t = test_target(n)
            if t:
                out[t] = n
    return out


def mismatches(projects, settings, main_name):
    out = []
    if not settings:
        return ['CLAUDE.md がない (設定の 3 行を読めない)']
    text = settings['text']
    libs = [n for n, p in projects.items() if p['role'] in ('data', 'logic', 'viewmodel', 'ui', 'other') and n != main_name]
    layers_line = settings['layers'] or ''
    default = {'data': 'DataLayer', 'logic': 'LogicLayer', 'viewmodel': 'ViewModels'}
    for n in libs:
        role = projects[n]['role']
        if n in text:
            continue
        if role in default and default[role] == n and role in layers_line:
            continue
        out.append(f'{n} ({projects[n]["kind"]}) が、CLAUDE.md のどこにも書かれていない (「- 層:」の行か、構成の表)')
    has_tests = any(p['role'] == 'test' for p in projects.values())
    t = settings['tests'] or ''
    if has_tests and t.startswith('なし'):
        out.append('テストプロジェクトがあるのに、CLAUDE.md の「- テスト:」が「なし」')
    if not has_tests and t.startswith('あり'):
        out.append('テストプロジェクトがないのに、CLAUDE.md の「- テスト:」が「あり」')
    if settings['layers'] is None:
        out.append('CLAUDE.md に「- 層:」の行がない')
    # 「- 追加した層: <名前> ...」の行 (層の表がないとき、/add-project が足す) の、テストの有無
    tests = tests_of(projects)
    for m in re.finditer(r'^- 追加した層:\s*([\w.]+)[^\n]*$', text, re.M):
        name, line = m.group(1), m.group(0)
        if name not in projects:
            continue
        if 'テストなし' in line and name in tests:
            out.append(f'CLAUDE.md の「追加した層: {name}」が「テストなし」だが、テスト {tests[name]} がある (後付けしたとき、この行を直す)')
        if 'テストあり' in line and name not in tests:
            out.append(f'CLAUDE.md の「追加した層: {name}」が「テストあり」だが、テストプロジェクトがない')
    return out


def ref_issues(projects):
    out = []
    for n, p in projects.items():
        if p['role'] not in RANK:
            continue
        for d in p['refs'] + p['uses']:
            q = projects.get(d)
            if q and q['role'] in RANK and RANK[p['role']] > RANK[q['role']]:
                out.append(f'{n} ({p["role"]}) が、上の層 {d} ({q["role"]}) を参照している')
    return out


def suggest_refs(projects):
    """どこからも参照されていない層 (data / logic / viewmodel / ui) と、参照するのが自然なプロジェクト。"""
    referenced = set()
    for n, p in projects.items():
        if p['role'] in ('test', 'uitest'):
            continue
        referenced.update(p['refs'])
        referenced.update(p['uses'])
    out = []
    for n, p in projects.items():
        if p['role'] not in ('data', 'logic', 'viewmodel', 'ui') or n in referenced:
            continue
        rank = RANK[p['role']]
        cands = [(RANK[q['role']], m) for m, q in projects.items()
                 if q['role'] in RANK and RANK[q['role']] < rank and m != n]
        if not cands:
            continue
        best = max(r for r, _ in cands)       # すぐ上の層。同じ高さが複数なら、名前順の先頭
        user = sorted(m for r, m in cands if r == best)[0]
        out.append(f'{user} -> {n}')
    return out


def addables(sln_dir, projects, kind, main_name):
    out = []
    tests = tests_of(projects)
    cpp = kind in ('cpp', 'mixed')
    sd = '<SLN_DIR>'
    if cpp:
        out.append(('layer', '層 (DLL / 静的ライブラリ / MFC 拡張・標準 DLL) と、そのテストを足す',
                    f'python3 {SCRIPTS}/cpp-test-first/scripts/add_layer.py "{sd}" <Name> [--kind dll|lib|mfc-ext-dll|mfc-std-dll] [--tests gtest|none] [--uses <Other>...] --dry-run'))
        for n, p in projects.items():
            if p['kind'] in ('dll', 'lib', 'mfc-ext-dll', 'mfc-std-dll') and p['role'] != 'ui' and n not in tests:
                out.append((f'tests-for:{n}', f'{n} に、テスト (GoogleTest) を後付けする',
                            f'python3 {SCRIPTS}/cpp-test-first/scripts/add_layer.py "{sd}" {n} --tests-only --dry-run'))
        out.append(('ui-host', '画面を持つ DLL (UI DLL) と、画面ホストの exe を足す',
                    f'python3 {SCRIPTS}/cpp-test-first/scripts/add_ui_host.py "{sd}" [--name UiLayer] [--kind mfc-std-dll|mfc-ext-dll] --dry-run'))
    else:
        out.append(('layer', '層 (クラスライブラリ) と、そのテストを足す',
                    f'python3 {SCRIPTS}/csharp-test-first/scripts/add_project.py "{sd}" <Name> [--kind lib|data|logic|viewmodel] [--tests mstest|none] [--uses <Other>...] --dry-run'))
        for n, p in projects.items():
            if p['kind'] == 'classlib' and n not in tests:
                out.append((f'tests-for:{n}', f'{n} に、テスト (MSTest) を後付けする',
                            f'python3 {SCRIPTS}/csharp-test-first/scripts/add_project.py "{sd}" {n} --tests-only --dry-run'))
    uitests = uitests_of(projects)
    for n, p in projects.items():
        gui = p['kind'] in ('wpf-app', 'winforms-app') or (p['lang'] == 'cpp' and p['kind'] == 'exe')
        if gui and p['role'] == 'main' and n not in uitests:
            out.append((f'ui-tests:{n}', f'{n} に、UI テスト (FlaUI) を後付けする',
                        f'python3 {SCRIPTS}/new-solution/scripts/new_solution.py "{sd}" --ui-tests flaui --dry-run'))
    return out


def main():
    ap = argparse.ArgumentParser(description='ソリューションの現状を読む (読み取りだけ)')
    ap.add_argument('sln_dir')
    a = ap.parse_args()
    sln_dir = os.path.abspath(a.sln_dir)
    if not os.path.isdir(sln_dir):
        print(f'ERROR: フォルダがない: {sln_dir}', file=sys.stderr)
        return 2
    slns = find_solutions(sln_dir)
    if not slns:
        print(f'ERROR: .sln / .slnx が見つからない: {sln_dir}', file=sys.stderr)
        return 2
    if len(slns) > 1:
        print(f'ERROR: ソリューションが複数ある ({", ".join(slns)})。どれを使うか、ユーザーに確認すること', file=sys.stderr)
        return 3
    projects = scan(sln_dir)
    settings = claude_settings(sln_dir)
    main_name, main_label = main_of(projects, settings)
    assign_roles(projects, main_name, settings)
    has_cpp = any(p['lang'] == 'cpp' for p in projects.values())
    has_cs = any(p['lang'] == 'cs' and p['kind'] != 'uitest' for p in projects.values())
    kind = 'mixed' if has_cpp and has_cs else ('cpp' if has_cpp else 'dotnet')
    tests = tests_of(projects)
    uitests = uitests_of(projects)

    print(f'SOLUTION: {os.path.join(sln_dir, slns[0])}')
    print(f'KIND: {kind}')
    print(f'MAIN: {main_label or "(なし)"}')
    if settings:
        print(f'CLAUDE_MD: present (メイン={settings["main"]} / 層={settings["layers"]} / テスト={settings["tests"]})')
    else:
        print('CLAUDE_MD: absent')
    for n, p in projects.items():
        t = tests.get(n) or uitests.get(n) or '-'
        print(f'PROJECT: {n} | {p["kind"]} | {p["role"]} | {t} | {",".join(p["refs"]) or "-"} | {",".join(p["uses"]) or "-"}')
    for m in mismatches(projects, settings, main_name):
        print(f'MISMATCH: {m}')
    for m in ref_issues(projects):
        print(f'REF_ISSUES: {m}')
    for m in suggest_refs(projects):
        print(f'SUGGEST_REF: {m}')
    for i, d, c in addables(sln_dir, projects, kind, main_name):
        print(f'ADDABLE: {i} | {d} | {c}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
