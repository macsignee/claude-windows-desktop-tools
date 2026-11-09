#!/usr/bin/env python3
"""add_common.py - すでにあるソリューションに、共通の Directory.Build.props / .targets (msbuild-common) を足す。

使い方:
  python3 add_common.py <SLN_DIR> [--common auto|copy|reference] [--common-dir <WSL のパス>] [--dry-run]

  /new-solution が新規のソリューションに作るものと、同じものを、すでにあるソリューション (C++ も .NET も) に足す (v2.66.0)。
  Claude は、共通ファイルの中身を決めない。外の正本を読んで、ソリューションに合わせて置く。
  正本の場所と、置き方 (参照型 / コピー型) の決め方は、new-solution/scripts/msbuild_source.py:
    場所: ソリューションの CLAUDE.md の「- MSBuild 共通: <パス>」 → 環境変数 MSBUILD_COMMON_DIR → 配布用のコピー (new-solution/msbuild-common/)
    置き方: 参照型 = 薄いファイル (外の正本を参照) だけ。コピー型 = 薄いファイルと build/common/ (正本のコピー)。
            auto (既定) は、すでにある薄いファイルの型を、そのまま保つ。ないときは、場所が、CLAUDE.md か環境変数なら参照型、配布用のコピーならコピー型。

  出力の行頭: `+` 足す / `~` 書き換える / `=` すでに同じ / `!` 止まる理由。
  書き換えてよいのは、次のものだけ:
    - 薄いファイルが、ない → 足す。すでに同じ → 何もしない。
    - Directory.Build.props が、以前の /new-solution が作ったもの (Nullable / ImplicitUsings / LangVersion だけ。Dotnet.props と同じ設定) → 薄い版に書き換える (効果は同じ)。
    - --common で、型を切り替えるとき、すでにある薄いファイルが、もう一方の型の薄い版と同じ → 書き換える。
    - build/common/ (コピー型) が、古い版 → 新しい版に差し替える (コピーなので)。
    - CLAUDE.md の「## MSBuild の共通設定」の節 (自動生成の節。なければ末尾に足す。CLAUDE.md がなければ、作らない)。
  **手で書いた Directory.Build.props / .targets は、書き換えない。** 止まって (終了コード 2)、手で足す Import の行を示す。
  build/common/ が、配る版より新しいときも、止まる。参照型のときは、build/common/ を、使わない (残っていても、触らない)。

終了コード:
  0 成功 (書いた / --dry-run)
  2 引数・入力の問題、または、止まる理由がある (何も書いていない)
  3 すべて、すでに最新 (何も書いていない)
"""
import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET

BOM = b'\xef\xbb\xbf'
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'new-solution', 'scripts'))
import msbuild_source as MS   # noqa: E402


def die(msg, code=2):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(code)


def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()


def norm(b):
    """BOM と改行 (CRLF) の違いを、無視して比べるための形。"""
    if b.startswith(BOM):
        b = b[3:]
    return b.replace(b'\r\n', b'\n')


def ver_tuple(text):
    m = re.match(r'\s*(\d+)\.(\d+)\.(\d+)', text)
    return tuple(int(x) for x in m.groups()) if m else None


def props_of(xml_bytes):
    """PropertyGroup の中の (名前 -> 値)。PropertyGroup 以外の要素があれば、None。"""
    try:
        root = ET.fromstring(norm(xml_bytes).decode('utf-8'))
    except (ET.ParseError, UnicodeDecodeError):
        return None
    out = {}
    for ch in root:
        if ch.tag != 'PropertyGroup':
            return None
        for e in ch:
            out[e.tag] = (e.text or '').strip()
    return out


def has_dotnet(sln_dir):
    for d in sorted(os.listdir(sln_dir)):
        p = os.path.join(sln_dir, d)
        if os.path.isdir(p) and os.path.isfile(os.path.join(p, d + '.csproj')):
            return True
    return False


def optional_template(src, mode, fn):
    try:
        return MS.thin_template(src, mode, fn)
    except OSError:
        return None


def existing_mode(sln_dir, src):
    """すでにある薄い Directory.Build.props が、どちらの型か (copy / reference)。どちらでもなければ None。"""
    p = os.path.join(sln_dir, 'Directory.Build.props')
    if not os.path.exists(p):
        return None
    cur = norm(read_bytes(p))
    for mode in ('copy', 'reference'):
        t = optional_template(src, mode, 'Directory.Build.props')
        if t is not None and cur == norm(t):
            return mode
    if MS.REF_MARK.encode() in cur:
        return 'reference'
    if MS.IMPORT_LINE['Directory.Build.props'].encode() in cur:
        return 'copy'
    return None


def resolve_plan(sln_dir, requested, explicit):
    """戻り値: (正本, 決めた元, モード)。決められなければ、終了。"""
    src, origin = MS.resolve(sln_dir, explicit)
    mode = None
    if requested == 'auto':
        mode = existing_mode(sln_dir, src)
    try:
        mode = mode or MS.decide_mode(requested, origin)
        MS.check_source(src, mode)
    except MS.SourceError as e:
        die(str(e))
    return src, origin, mode


def plan(sln_dir, requested='auto', explicit=None):
    """戻り値: ([(相対パス, 種類 add/replace/skip/error, 説明, 新しい bytes または None)], 正本, 元, モード)。CLAUDE.md の行は、別 (plan_claude)。"""
    src, origin, mode = resolve_plan(sln_dir, requested, explicit)
    other = 'copy' if mode == 'reference' else 'reference'
    dotnet_props = props_of(MS.read(src, 'Dotnet.props')) if os.path.isfile(os.path.join(src, 'Dotnet.props')) else None
    out = []
    for fn in MS.THIN:
        path = os.path.join(sln_dir, fn)
        want = MS.thin_template(src, mode, fn)
        if not os.path.exists(path):
            out.append((fn, 'add', f'薄いファイル ({"参照型" if mode == "reference" else "コピー型"}) を、足す', want))
            continue
        cur = norm(read_bytes(path))
        theirs = optional_template(src, other, fn)
        if cur == norm(want):
            out.append((fn, 'skip', 'すでに同じ', None))
        elif theirs is not None and cur == norm(theirs):
            out.append((fn, 'replace', f'{"コピー型" if other == "copy" else "参照型"}の薄いファイルを、{"参照型" if mode == "reference" else "コピー型"}に、書き換える (型の切り替え)', want))
        elif mode == 'reference' and MS.REF_MARK.encode() in cur:
            out.append((fn, 'skip', f'すでに、外の正本を参照している (手で書いたもの。そのまま)', None))
        elif mode == 'copy' and MS.IMPORT_LINE[fn].encode() in cur:
            out.append((fn, 'skip', 'すでに、build\\common\\ を読んでいる (手で足したもの。そのまま)', None))
        elif fn == 'Directory.Build.props' and dotnet_props and props_of(cur) == dotnet_props:
            out.append((fn, 'replace', '以前の /new-solution が作ったもの (Nullable などを直接書く) を、薄い版に書き換える。設定は、共通ファイルの Dotnet.props に移る (効果は同じ)', want))
        else:
            line = '<Import Project="$(MsbuildCommonDir)\\Common.props" /> (と、その前に、MsbuildCommonDir の定義)' if mode == 'reference' else MS.IMPORT_LINE[fn]
            out.append((fn, 'error', f'手で書いたファイルが、すでにある。書き換えない。共通ファイルを使うには、`<Project>` の中に、手で次の行を足すこと: {line}', None))
    bc = os.path.join(sln_dir, 'build', 'common')
    if mode == 'reference':
        if os.path.isdir(bc):
            out.append(('build/common/', 'skip', '参照型では使わない (残っている。触らない。要らなければ、手で消してよい)', None))
        return out, src, origin, mode
    new_ver = MS.version_of(src)
    cur_ver_path = os.path.join(bc, 'VERSION')
    cur_ver = open(cur_ver_path, encoding='utf-8-sig').read().strip() if os.path.isfile(cur_ver_path) else None
    older = bool(cur_ver and ver_tuple(cur_ver) and ver_tuple(new_ver) and ver_tuple(cur_ver) < ver_tuple(new_ver))
    newer = bool(cur_ver and ver_tuple(cur_ver) and ver_tuple(new_ver) and ver_tuple(cur_ver) > ver_tuple(new_ver))
    for fn in MS.COMMON_FILES:
        rel = 'build/common/' + fn
        path = os.path.join(bc, fn)
        data = MS.read(src, fn)
        if not os.path.exists(path):
            out.append((rel, 'add', '共通ファイルを、足す', data))
        elif read_bytes(path) == data:
            out.append((rel, 'skip', 'すでに同じ', None))
        elif newer:
            out.append((rel, 'error', f'build\\common\\ の版 ({cur_ver}) が、配る版 ({new_ver}) より新しい。書き換えない', None))
        elif older:
            out.append((rel, 'replace', f'版 {cur_ver} → {new_ver} に、差し替える (コピーなので)', data))
        else:
            out.append((rel, 'error', f'版 ({cur_ver or "不明"}) は同じか判定できないが、内容が違う (手で編集された可能性)。書き換えない', None))
    return out, src, origin, mode


SECTION_RE = re.compile(r'\n' + re.escape(MS.SECTION) + r'\n.*?(?=\n## |\Z)', re.S)


def plan_claude(sln_dir, mode, src):
    """CLAUDE.md の節を足す (または、書き換える) 案: (種類, 説明, 新しい bytes または None)。"""
    path = os.path.join(sln_dir, 'CLAUDE.md')
    if not os.path.isfile(path):
        return 'skip', 'CLAUDE.md がないので、作らない', None
    raw = read_bytes(path)
    text = raw.decode('utf-8-sig')
    nl = '\r\n' if '\r\n' in text else '\n'
    body = text.replace('\r\n', '\n')
    note = MS.claude_note(has_dotnet(sln_dir), mode, src)
    m = SECTION_RE.search(body)
    if m:
        if m.group(0).strip('\n') == note.strip('\n'):
            return 'skip', f'「{MS.SECTION}」の節が、すでにある (同じ)', None
        body = body[:m.start()] + body[m.end():]
        kind, msg = 'replace', f'「{MS.SECTION}」の節を、いまの置き方に書き換える'
    else:
        kind, msg = 'add', f'「{MS.SECTION}」の節を、末尾に足す'
    new = (body.rstrip('\n') + '\n' + note).replace('\n', nl)
    return kind, msg, (BOM if raw.startswith(BOM) else b'') + new.encode('utf-8')


def main():
    ap = argparse.ArgumentParser(description='すでにあるソリューションに、共通の Directory.Build.props / .targets を足す')
    ap.add_argument('sln_dir')
    ap.add_argument('--common', choices=['auto', 'copy', 'reference'], default='auto', help='置き方 (既定 auto)')
    ap.add_argument('--common-dir', help='外の正本 (msbuild-common) のフォルダ (WSL のパス)')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    root = os.path.abspath(a.sln_dir)
    if not os.path.isdir(root):
        die(f'フォルダがない: {root}')
    slns = [f for f in sorted(os.listdir(root)) if f.lower().endswith(('.sln', '.slnx'))]
    if not slns:
        die(f'.sln / .slnx が見つからない: {root}')
    if len(slns) > 1:
        die(f'ソリューションが複数ある ({", ".join(slns)})。どれを使うか、ユーザーに確認すること')

    results, src, origin, mode = plan(root, a.common, a.common_dir)
    ck, cmsg, cnew = plan_claude(root, mode, src)
    results.append(('CLAUDE.md', ck, cmsg, cnew))
    origin_label = {'option': '--common-dir', 'claude-md': 'CLAUDE.md の「- MSBuild 共通:」', 'env': f'環境変数 {MS.ENV_NAME}', 'bundled': '配布用のコピー'}[origin]
    print(f'ソリューション : {slns[0]}')
    print(f'正本           : {src} (決めた元: {origin_label}。版 {MS.version_of(src) or "不明"})')
    print(f'置き方         : {"参照型 (薄いファイルだけ。コピーしない)" if mode == "reference" else "コピー型 (薄いファイルと build\\common\\)"}')
    mark = {'add': '+', 'replace': '~', 'skip': '=', 'error': '!'}
    for rel, kind, msg, _n in results:
        print(f'  {mark[kind]} {rel}: {msg}')
    errors = [r for r in results if r[1] == 'error']
    if errors:
        die('止まる理由がある。何も書いていない。上の「!」の行を、確かめること', 2)
    todo = [r for r in results if r[1] in ('add', 'replace')]
    if not todo:
        print('すべて、すでに最新。何も書いていない')
        sys.exit(3)
    if mode == 'reference':
        print(MS.reference_note(src))
    if a.dry_run:
        print('(dry-run: 何も書いていない)')
        return
    for rel, _k, _m, new in todo:
        p = os.path.join(root, *rel.split('/'))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'wb') as f:
            f.write(new)
    print(f'完了。{len(todo)} ファイルを書いた')
    print('NOTE: ビルドして、確かめること (build-test-loop / auto-build)' + ('' if mode == 'reference' else '。`build\\common\\` は、コピー。手で編集しない'))


if __name__ == '__main__':
    main()
