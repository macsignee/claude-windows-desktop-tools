#!/usr/bin/env python3
"""add_reference.py - 使う側のプロジェクト (--from) に、使われる側のプロジェクト (--to) への参照を足す。

Usage: python3 add_reference.py <SLN_DIR> --from <使う側> --to <使われる側> [--include-only] [--dry-run]

  SLN_DIR        .sln または .slnx があるフォルダ。プロジェクトは <SLN_DIR>/<名前>/<名前>.vcxproj (C++) または .csproj (.NET)
  --from         使う側のプロジェクト名 (例: メインの exe、上の層、テスト)
  --to           使われる側のプロジェクト名 (例: 新しく足した層)
  --include-only C++ だけ: インクルードパスだけを足す (ProjectReference は足さない。ヘッダ (インターフェース) だけを使う層向け。
                 add_layer.py の --uses と同じ)
  --dry-run      何も書かず、行う内容だけを表示する

足すもの:
  .NET (.csproj):  <ProjectReference Include="..\\<to>\\<to>.csproj" /> (すでにある ProjectReference の並びに、1 行足す)
  C++ (.vcxproj):  <ProjectReference Include="..\\<to>\\<to>.vcxproj"><Project>{GUID}</Project></ProjectReference> (DLL はインポートライブラリ、
                   静的ライブラリは .lib が、リンクされる。ビルド順も、決まる) と、全構成の ClCompile の
                   AdditionalIncludeDirectories に、$(ProjectDir)..\\<to> と、<to> が (さらに) 参照している層のフォルダ
                   (テスト exe と同じ形。ヘッダの #include が、たどれるように)。

断る (何も書かない。終了コード 2): 使う側と使われる側が同じ・言語が違う (C++ と C#)・存在しない・UI テストのプロジェクト /
  層の向きの違反 (メイン → 画面 → ViewModel → ロジック → データ。下の層が、上の層を参照する)・循環 (使われる側が、すでに、
  使う側を参照している)・MFC 拡張 DLL を、UseOfMfc のない使う側から参照する。
すでに参照がある: 何も書かない (終了コード 3。--include-only で、パスだけが足りないときは、パスだけを足して 0)。

終了コード: 0 成功 / 2 引数・構成の問題 / 3 すでに参照がある
ファイルの BOM・改行コード (CRLF / LF) は、そのまま保つ。プロジェクトの、ほかの内容は、変えない。
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import solution_state as ss   # noqa: E402

BOM = b'\xef\xbb\xbf'


def die(msg, code=2):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(code)


def load(path):
    raw = open(path, 'rb').read()
    bom = raw.startswith(BOM)
    text = (raw[3:] if bom else raw).decode('utf-8')
    crlf = '\r\n' in text
    return bom, crlf, text.replace('\r\n', '\n')


def save(path, bom, crlf, text):
    if crlf:
        text = text.replace('\n', '\r\n')
    open(path, 'wb').write((BOM if bom else b'') + text.encode('utf-8'))


def project_file(sln_dir, name, p):
    return os.path.join(sln_dir, name, name + ('.vcxproj' if p['lang'] == 'cpp' else '.csproj'))


def reachable(projects, start, goal, seen=None):
    """start から、プロジェクト参照 (と include だけの参照) をたどって、goal に着くか。"""
    seen = seen if seen is not None else set()
    if start == goal:
        return True
    if start in seen or start not in projects:
        return False
    seen.add(start)
    p = projects[start]
    return any(reachable(projects, d, goal, seen) for d in p['refs'] + p['uses'])


def closure(projects, name, seen=None):
    """name が、(推移的に) 参照している、テストでないプロジェクトの名前 (名前順)。"""
    seen = seen if seen is not None else set()
    for d in projects[name]['refs'] + projects[name]['uses']:
        q = projects.get(d)
        if q and q['role'] not in ('test', 'uitest') and d not in seen:
            seen.add(d)
            closure(projects, d, seen)
    return sorted(seen)


def check(projects, frm, to, sln_dir, include_only):
    if frm == to:
        die('--from と --to が、同じプロジェクト')
    for n, label in ((frm, '--from'), (to, '--to')):
        if n not in projects:
            die(f'{label} のプロジェクトがない: {n} (<SLN_DIR>/{n}/{n}.vcxproj または .csproj)')
    a, b = projects[frm], projects[to]
    if 'uitest' in (a['role'], b['role']):
        die('UI テストのプロジェクトは、扱わない (FlaUI が、exe を起動して操作する。参照しない)')
    if a['lang'] != b['lang']:
        die(f'言語が違う ({frm} = {a["lang"]}、{to} = {b["lang"]})。C++ と C# の間の参照は、扱わない')
    if b['role'] == 'test':
        die(f'テストのプロジェクト {to} を、参照できない')
    if a['role'] in ss.RANK and b['role'] in ss.RANK and ss.RANK[a['role']] > ss.RANK[b['role']]:
        die(f'層の向きの違反: {frm} ({a["role"]}) は、上の層 {to} ({b["role"]}) を参照できない '
            f'(メイン → 画面 → ViewModel → ロジック → データ)')
    if reachable(projects, to, frm):
        die(f'循環になる: {to} が、すでに、{frm} を参照している')
    if a['lang'] == 'cpp':
        if include_only is False and b['kind'] == 'mfc-ext-dll' and not a['mfc']:
            die(f'MFC 拡張 DLL {to} を参照する {frm} は、UseOfMfc (Dynamic) が必要 (mfc-check の DLL008)。先に、{frm} の MFC の設定を直す')
    elif include_only:
        die('--include-only は、C++ だけ')


def add_cpp_reference(text, to, guid):
    if re.search(r'<ProjectReference Include="\.\.\\' + re.escape(to) + r'\\' + re.escape(to) + r'\.vcxproj"', text):
        return text, False
    ref = (f'    <ProjectReference Include="..\\{to}\\{to}.vcxproj">\n'
           f'      <Project>{guid}</Project>\n'
           f'    </ProjectReference>\n')
    last = text.rfind('<ProjectReference ')
    if last >= 0:
        end = text.find('</ItemGroup>', last)
        line_start = text.rfind('\n', 0, end) + 1
        return text[:line_start] + ref + text[line_start:], True
    m = re.search(r'^[ \t]*<Import Project="\$\(VCTargetsPath\)\\Microsoft\.Cpp\.targets"', text, re.M)
    if not m:
        die('.vcxproj に Microsoft.Cpp.targets の Import がない (想定外の形式)')
    group = '  <ItemGroup>\n' + ref + '  </ItemGroup>\n'
    return text[:m.start()] + group + text[m.start():], True


def add_cpp_includes(text, paths):
    """全構成の ClCompile の AdditionalIncludeDirectories に、paths (まだないもの) を、先頭へ足す。-> (text, 足したパスの一覧)"""
    added = {}

    def fix_group(m):
        g = m.group(0)
        cm = re.search(r'<ClCompile>(.*?)</ClCompile>', g, re.S)
        if not cm:
            return g
        body = cm.group(1)
        em = re.search(r'<AdditionalIncludeDirectories>([^<]*)</AdditionalIncludeDirectories>', body)
        if em:
            parts = em.group(1).split(';')
            new = [p for p in paths if p not in parts]
            if not new:
                return g
            added.update(dict.fromkeys(new))
            body2 = body[:em.start(1)] + ';'.join(new) + ';' + em.group(1) + body[em.end(1):]
        else:
            im = re.search(r'\n([ \t]*)<', body)
            indent = im.group(1) if im else '      '
            added.update(dict.fromkeys(paths))
            body2 = ('\n' + indent + '<AdditionalIncludeDirectories>' + ';'.join(paths)
                     + ';%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>' + body)
        return g[:cm.start(1)] + body2 + g[cm.end(1):]

    text2 = re.sub(r'<ItemDefinitionGroup\b[^>]*>.*?</ItemDefinitionGroup>', fix_group, text, flags=re.S)
    return text2, list(added)


def add_cs_reference(text, to):
    inc = f'..\\{to}\\{to}.csproj'
    if f'<ProjectReference Include="{inc}"' in text:
        return text, False
    last = text.rfind('<ProjectReference ')
    if last >= 0:
        line_start = text.rfind('\n', 0, last) + 1
        indent = re.match(r'[ \t]*', text[line_start:]).group(0)
        line_end = text.find('\n', last) + 1
        new = f'{indent}<ProjectReference Include="{inc}" />\n'
        return text[:line_end] + new + text[line_end:], True
    end = text.rfind('</Project>')
    if end < 0:
        die('.csproj に </Project> がない (想定外の形式)')
    group = f'  <ItemGroup>\n    <ProjectReference Include="{inc}" />\n  </ItemGroup>\n\n'
    return text[:end] + group + text[end:], True


def guid_of(path):
    m = re.search(r'<ProjectGuid>(\{[0-9A-Fa-f-]+\})</ProjectGuid>', ss.read_text(path))
    if not m:
        die(f'ProjectGuid がない: {path}')
    return m.group(1).upper()


def main():
    ap = argparse.ArgumentParser(description='使う側のプロジェクトに、使われる側への参照を足す')
    ap.add_argument('sln_dir')
    ap.add_argument('--from', dest='frm', required=True)
    ap.add_argument('--to', required=True)
    ap.add_argument('--include-only', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    sln_dir = os.path.abspath(a.sln_dir)
    if not os.path.isdir(sln_dir):
        die(f'フォルダがない: {sln_dir}')
    slns = ss.find_solutions(sln_dir)
    if not slns:
        die(f'.sln / .slnx が見つからない: {sln_dir}')
    if len(slns) > 1:
        die(f'ソリューションが複数ある ({", ".join(slns)})。どれを使うか、ユーザーに確認すること')
    projects = ss.scan(sln_dir)
    main_name, _ = ss.main_of(projects, ss.claude_settings(sln_dir))
    ss.assign_roles(projects, main_name)
    check(projects, a.frm, a.to, sln_dir, a.include_only)

    src = project_file(sln_dir, a.frm, projects[a.frm])
    bom, crlf, text = load(src)
    changed = []
    if projects[a.frm]['lang'] == 'cpp':
        if not a.include_only:
            text, did = add_cpp_reference(text, a.to, guid_of(project_file(sln_dir, a.to, projects[a.to])))
            if did:
                changed.append(f'REF: {a.frm} -> {a.to} (ProjectReference)')
        paths = [f'$(ProjectDir)..\\{n}' for n in [a.to] + closure(projects, a.to)]
        text, added = add_cpp_includes(text, paths)
        if added:
            changed.append(f'INCLUDE: {a.frm}: ' + ';'.join(added))
    else:
        text, did = add_cs_reference(text, a.to)
        if did:
            changed.append(f'REF: {a.frm} -> {a.to} (ProjectReference)')

    if not changed:
        print(f'すでに参照がある: {a.frm} -> {a.to} (何も書かない)')
        return 3
    for c in changed:
        print(c)
    if a.dry_run:
        print('dry-run: 何も書いていない')
        return 0
    save(src, bom, crlf, text)
    print(f'DONE: {os.path.relpath(src, sln_dir)} を更新した (ほかのファイルは、変えていない)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
