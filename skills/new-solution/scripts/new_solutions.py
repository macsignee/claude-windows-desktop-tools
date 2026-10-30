#!/usr/bin/env python3
"""new_solutions.py - 作業フォルダ (例: ...\\repos\\ToDo) の下に、候補ごとのソリューションを、宣言ファイル (solutions.md) から、まとめて作る。

Usage:
  python3 new_solutions.py create     <作業フォルダ> [--dry-run]     solutions.md の候補を作る (すでにある候補は、触らない)
  python3 new_solutions.py sync-spec  <作業フォルダ> [--dry-run]     作業フォルダの仕様書 (正本) を、各候補のコピーへ反映する
  python3 new_solutions.py resolve    <作業フォルダまたはソリューション> [<候補名>]   対象のソリューションのパスを、1 行で出す

作業フォルダ: docs/ (壁打ちのメモ・仕様書の正本) と solutions.md を置く。Claude は、ここで起動する。候補は、その下に作られる (候補ごとに、独立したソリューション)。
  <作業フォルダ>/docs/ideas/  docs/specs/   正本
  <作業フォルダ>/solutions.md              宣言 (下の形)
  <作業フォルダ>/<候補名>/                 候補のソリューション (フォルダ名 = ソリューション名。new_solution.py が作る)

solutions.md の形 (「- キー: 値」の行は、全候補の共通。表は、候補ごと。表の値は、new_solution.py の引数と同じ):
  - 仕様書: docs/specs/todo.md           (省略可。作業フォルダからの相対。全候補に、取り込む)
  - 名前空間: todo                        (省略可。表の「名前空間」列で、候補ごとに上書きできる)
  | 名前 | 種類 | 層 | テスト | UIテスト |
  |---|---|---|---|---|
  | TodoWpf | wpf | data,logic,viewmodel | mstest | none |
  | TodoMfc | mfc-dialog | logic | gtest | none |
  必須の列: 名前 / 種類 / 層 / テスト。省略できる列: UIテスト (既定 none)、層の種類、名前空間、TFM、備考。
  必須の値が空・未定なら、何も作らずに、エラーにする (質問して、埋める。特に「テスト」は、黙って既定にしない)。

create:
  1. solutions.md を検査し、新しく作る候補ごとに、new_solution.py --dry-run を実行する。**1 つでも不正なら、何も作らない** (終了コード 2)。
  2. 作る。すでに .sln / .slnx がある候補は、触らない (行を足して、再実行すると、足した分だけ作られる)。
  3. 仕様書 (と「元:」のメモ) を、各候補の docs/ に取り込み (spec_import.py)、取り込んだ内容のハッシュを docs/specs/.spec-sync.json に記録する。
  4. 全候補の CLAUDE.md の「## 比較の候補」の節 (自動生成) を、書く・更新する。
  GoogleTest (vcpkg) の仕上げと、最初のベースライン確認は、しない (候補ごとのウォッチャーが要る。各候補を扱うときに行う)。
  終了コード: 0 成功 / 2 宣言・組み合わせの問題 (何も作らない、または、途中で失敗) / 3 新しく作る候補がなかった

sync-spec:
  作業フォルダの仕様書 (と「元:」のメモ) が、取り込み時から変わっていたら、各候補のコピーへ反映する。
  **候補側で、編集されたコピーは、上書きしない (衝突として報告する)。** テストケースの種 (*.cases.md) は、更新しない (チェック済みを守る)。
  終了コード: 0 / 1 衝突あり / 2 宣言の問題

resolve:
  カレントに .sln / .slnx がある → そのフォルダ。ない → solutions.md の候補 (ソリューションがあるもの) から選ぶ。
  候補が 1 つなら、それ。複数で、名前がなければ、終了コード 2 (候補の一覧を、標準エラー出力に出す。質問する)。
  終了コード: 0 (標準出力の 1 行目が、パス) / 2 候補が複数で、選べない / 3 対象がない
"""
import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import spec_import as SI   # noqa: E402

MANIFEST = 'solutions.md'
SYNC_RECORD = os.path.join('docs', 'specs', '.spec-sync.json')
SECTION = '## 比較の候補'
NAME_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
TYPES = ('wpf', 'winforms', 'csharp-dll', 'mfc', 'mfc-mdi', 'mfc-dialog', 'win32', 'console', 'dll', 'lib')
DOTNET = ('wpf', 'winforms', 'csharp-dll')
TESTS = ('none', 'gtest', 'mstest')
UITESTS = ('none', 'flaui')
MISSING = {'', '?', '？', '未定', '未決', 'TBD'}
NONE_WORDS = {'-', 'ー', 'なし', 'none'}
HEADERS = {'名前': 'name', 'ソリューション名': 'name', '種類': 'type', 'メインの種類': 'type', '層': 'layers', 'テスト': 'tests',
           'UIテスト': 'ui_tests', '層の種類': 'layer_kind', '名前空間': 'namespace', 'TFM': 'tfm', '備考': 'note', 'メモ': 'note'}
SHARED = {'仕様書': 'spec', '名前空間': 'namespace', 'TFM': 'tfm', '層の種類': 'layer_kind'}
TESTS_LABEL = {'gtest': 'GoogleTest (自動テスト)', 'mstest': 'MSTest (自動テスト)'}


def die(msg, code=2):
    print(msg)
    sys.exit(code)


def sha1_file(path):
    with open(path, 'rb') as f:
        return hashlib.sha1(f.read()).hexdigest()


def to_windows_path(p):
    m = re.match(r'^/mnt/([a-zA-Z])/(.*)$', p)
    return f'{m.group(1).lower()}:\\' + m.group(2).replace('/', '\\') if m else p


def solutions_in(folder):
    return sorted(glob.glob(os.path.join(folder, '*.slnx')) + glob.glob(os.path.join(folder, '*.sln')))


# ---------------------------------------------------------------- solutions.md
def _clean(v):
    return v.strip().strip('`').strip()


def read_manifest(parent):
    path = os.path.join(parent, MANIFEST)
    if not os.path.isfile(path):
        die(f'{MANIFEST} がない: {parent} (候補の宣言。形は、このスクリプトの先頭を参照)', 3)
    text = open(path, encoding='utf-8-sig').read().replace('\r\n', '\n')
    shared, header, rows, errors = {}, None, [], []
    for no, ln in enumerate(text.split('\n'), 1):
        s = ln.strip()
        if s.startswith('|'):
            cells = [_clean(c) for c in s.strip('|').split('|')]
            if all(re.match(r'^:?-{2,}:?$', c) for c in cells if c):
                continue
            if header is None:
                if '名前' in cells or 'ソリューション名' in cells:
                    unknown = [c for c in cells if c not in HEADERS]
                    if unknown:
                        errors.append(f'{MANIFEST}:{no}: 知らない列がある: {", ".join(unknown)}')
                    header = [HEADERS.get(c) for c in cells]
                continue
            row = {'_line': no}
            for key, val in zip(header, cells):
                if key:
                    row[key] = val
            rows.append(row)
            continue
        m = re.match(r'^-\s*([^:：|]+)[:：]\s*(.*)$', s)
        if m and m.group(1).strip() in SHARED and header is None:
            v = _clean(m.group(2))
            if v:
                shared[SHARED[m.group(1).strip()]] = v.split()[0] if SHARED[m.group(1).strip()] != 'spec' else re.match(r'^[^\s]+', v).group(0)
    if header is None:
        errors.append(f'{MANIFEST}: 候補の表がない (見出しの行に「名前」「種類」「層」「テスト」の列が要る)')
    else:
        for need in ('name', 'type', 'layers', 'tests'):
            if need not in header:
                errors.append(f'{MANIFEST}: 必須の列がない: {[k for k, v in HEADERS.items() if v == need][0]}')
    if not rows and header is not None:
        errors.append(f'{MANIFEST}: 候補の行がない')
    return shared, rows, errors


def check_rows(parent, shared, rows, errors):
    """行を検査して、(正規化した行のリスト) を返す。問題は errors に足す。"""
    seen, out = {}, []
    for r in rows:
        where = f'{MANIFEST}:{r["_line"]}'
        name = r.get('name', '')
        e = len(errors)
        if not NAME_RE.match(name):
            errors.append(f'{where}: 名前が使えない (英数字と _ のみ、先頭は英字か _): "{name}"')
        elif name.lower() in seen:
            errors.append(f'{where}: 名前が重複している: {name} (行 {seen[name.lower()]})')
        seen[name.lower()] = r['_line']

        t = r.get('type', '').lower()
        if t in MISSING or not t:
            errors.append(f'{where}: {name}: 種類が未定 (使える値: {", ".join(TYPES)})')
        elif t not in TYPES:
            errors.append(f'{where}: {name}: 種類が不正: {t} (使える値: {", ".join(TYPES)})')
        layers = r.get('layers', '')
        if layers in MISSING:
            errors.append(f'{where}: {name}: 層が未定 (none / logic / data / logic,data。wpf は viewmodel も)')
        elif layers.lower() in NONE_WORDS:
            layers = 'none'
        tests = r.get('tests', '').lower()
        if tests in MISSING:
            errors.append(f'{where}: {name}: テストが未定 (none / gtest / mstest)。**質問して、決める (黙って既定にしない)**')
        elif tests not in TESTS:
            errors.append(f'{where}: {name}: テストが不正: {tests} (使える値: {", ".join(TESTS)})')
        ui = r.get('ui_tests', '').lower()
        ui = 'none' if ui in MISSING or ui in NONE_WORDS else ui
        if ui not in UITESTS:
            errors.append(f'{where}: {name}: UIテストが不正: {ui} (使える値: {", ".join(UITESTS)})')
        if len(errors) == e:
            out.append({'name': name, 'type': t, 'layers': layers, 'tests': tests, 'ui_tests': ui,
                        'namespace': (r.get('namespace') if r.get('namespace', '') not in MISSING else None) or shared.get('namespace'),
                        'tfm': (r.get('tfm') if r.get('tfm', '') not in MISSING else None) or shared.get('tfm'),
                        'layer_kind': (r.get('layer_kind') if r.get('layer_kind', '') not in MISSING else None) or shared.get('layer_kind'),
                        'folder': os.path.join(parent, name)})
    spec = shared.get('spec')
    if spec and not os.path.isfile(os.path.join(parent, spec)):
        errors.append(f'{MANIFEST}: 仕様書がない: {spec} (作業フォルダからの相対)')
    return out


def load(parent):
    shared, rows, errors = read_manifest(parent)
    cands = check_rows(parent, shared, rows, errors)
    if errors:
        die('宣言の問題 (何も作っていない):\n' + '\n'.join('  - ' + e for e in errors))
    return shared, cands


# ---------------------------------------------------------------- 作る
def ns_args(c):
    args = ['--type', c['type'], '--layers', c['layers'], '--tests', c['tests']]
    if c['ui_tests'] != 'none':
        args += ['--ui-tests', c['ui_tests']]
    if c['namespace']:
        args += ['--namespace', c['namespace']]
    if c['type'] in DOTNET:
        if c['tfm']:
            args += ['--tfm', c['tfm']]
    elif c['layer_kind']:
        args += ['--layer-kind', c['layer_kind']]
    return args


def run_new_solution(c, dry):
    cmd = [sys.executable, os.path.join(HERE, 'new_solution.py'), c['folder']] + ns_args(c) + (['--dry-run'] if dry else [])
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return p.returncode, p.stdout


def read_record(folder):
    p = os.path.join(folder, SYNC_RECORD)
    if os.path.isfile(p):
        try:
            return json.load(open(p, encoding='utf-8')).get('copies', {})
        except (ValueError, OSError):
            return {}
    return {}


def write_record(folder, copies):
    p = os.path.join(folder, SYNC_RECORD)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'copies': copies}, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write('\n')


def spec_plan(parent, shared, c):
    spec = shared.get('spec')
    if not spec:
        return None
    return SI.plan(c['folder'], os.path.join(parent, spec), TESTS_LABEL.get(c['tests']))


def import_spec_for(parent, shared, c):
    p = spec_plan(parent, shared, c)
    if not p:
        return []
    SI.apply(c['folder'], p)
    rec = {}
    for src, rel in p['copies']:
        rec[rel] = {'src': os.path.relpath(src, parent).replace('\\', '/'), 'sha1': sha1_file(src)}
    write_record(c['folder'], rec)
    return SI.describe(p)


def candidates_section(parent, shared, cands, me):
    pname = os.path.basename(parent.rstrip('/\\'))
    others = ' / '.join('`%s` (%s%s)' % (x['name'], x['type'], '、この候補' if x['name'] == me['name'] else '') for x in cands)
    lines = [SECTION,
             f'- このソリューション (`{me["name"]}`) は、`{pname}` の比較の候補の 1 つ (宣言: `../{MANIFEST}`)。候補ごとに、独立して検討する。',
             f'- 候補 (種類): {others}']
    spec = shared.get('spec')
    if spec:
        lines.append(f'- 仕様書の正本: `../{spec}` (この候補のコピー: `docs/specs/{os.path.basename(spec)}`)。仕様を変えるときは、正本を直して、'
                     '`new_solutions.py sync-spec` で反映する。この候補だけで直した場合は、同期のとき「衝突」として報告される (上書きされない)。')
    lines.append('- 他の候補のフォルダは、読まない・書かない。')
    return lines


def write_candidates_section(parent, shared, cands):
    """全候補 (ソリューションがあるもの) の CLAUDE.md の、自動生成の節を、書く・更新する。更新した候補の名前を返す。"""
    done = []
    existing = [c for c in cands if solutions_in(c['folder'])]
    for c in existing:
        path = os.path.join(c['folder'], 'CLAUDE.md')
        if not os.path.isfile(path):
            continue
        raw = open(path, 'rb').read().decode('utf-8-sig')
        nl = '\r\n' if '\r\n' in raw else '\n'
        body = nl.join(candidates_section(parent, shared, existing, c)) + nl
        m = re.search(r'^' + re.escape(SECTION) + r'[^\n]*\n.*?(?=^## |\Z)', raw, re.M | re.S)
        if m:
            new = raw[:m.start()] + body + (nl if raw[m.end():] else '') + raw[m.end():]
        else:
            new = raw.rstrip('\r\n') + nl + nl + body
        if new.replace('\r\n', '\n').rstrip('\n') != raw.replace('\r\n', '\n').rstrip('\n'):
            with open(path, 'wb') as f:
                f.write(new.encode('utf-8'))
            done.append(c['name'])
    return done


def cmd_create(parent, dry):
    shared, cands = load(parent)
    new = [c for c in cands if not solutions_in(c['folder'])]
    skipped = [c for c in cands if c not in new]
    fails = []
    for c in new:
        rc, out = run_new_solution(c, True)
        if rc != 0:
            fails.append(f'  - {c["name"]} (終了コード {rc}):\n' + '\n'.join('      ' + ln for ln in out.strip().split('\n')[-6:]))
    if fails:
        die('作れない候補がある (何も作っていない):\n' + '\n'.join(fails))
    print(f'作業フォルダ: {parent}')
    print(f'候補 {len(cands)} 件: 新しく作る {len(new)} 件 / すでにある {len(skipped)} 件 (触らない)')
    for c in skipped:
        print(f'  = {c["name"]} (すでにある)')
    if dry:
        for c in new:
            rc, out = run_new_solution(c, True)
            print(f'\n[{c["name"]}] ({c["type"]}, 層 {c["layers"]}, テスト {c["tests"]}, UI テスト {c["ui_tests"]})')
            print('\n'.join('  ' + ln for ln in out.strip().split('\n')[:14]))
            p = spec_plan(parent, shared, c)
            if p:
                print('  仕様書の取り込み:')
                print('\n'.join('  ' + ln for ln in SI.describe(p)))
        print('\n(dry-run: 何も書いていない)')
        return 0 if new else 3
    created = []
    for c in new:
        rc, out = run_new_solution(c, False)
        if rc != 0:
            print(f'[{c["name"]}] 作成に失敗 (終了コード {rc}):')
            print('\n'.join('  ' + ln for ln in out.strip().split('\n')[-10:]))
            print(f'作成済み: {", ".join(created) or "(なし)"}。原因を直して、もう一度実行すると、残りが作られる (作成済みは、触らない)')
            return 2
        import_spec_for(parent, shared, c)
        created.append(c['name'])
        print(f'  + {c["name"]} を作った')
    refreshed = write_candidates_section(parent, shared, cands)
    if refreshed:
        print(f'CLAUDE.md の「{SECTION}」を、書いた・更新した: {", ".join(refreshed)}')
    if created:
        print('\n次の手順 (候補ごとに、独立して進める):')
        print('  (run_watcher.cmd は、ホスト側ツール (install.sh --host-only で配置したフォルダ) にある。そのフォルダで実行するか、パスを付けて実行する)')
        for c in new:
            wp = to_windows_path(os.path.abspath(c['folder']))
            print(f'  [{c["name"]}] {wp}')
            print(f'      ウォッチャー: run_watcher.cmd "{wp}"   (候補ごとに 1 つ)')
            if c['tests'] == 'gtest':
                print('      GoogleTest (vcpkg): この候補を扱うとき、package_once.sh "vcpkg baseline" "vcpkg install" で仕上げる (GTEST_VCPKG: no-baseline)')
        if len(cands) >= 2:
            pw = to_windows_path(os.path.abspath(parent))
            print(f'  候補をまとめて起動する (候補ごとに、別のウィンドウ): run_watchers.cmd "{pw}"   (一覧だけ見る: 末尾に /list)')
        print('  この作業フォルダの Claude から、`resolve` で対象を決めて、候補ごとに、ビルド・テストできる (build_once.sh など。パスを渡す)。')
    return 0 if new else 3


# ---------------------------------------------------------------- sync-spec
def classify(src, dst, rec):
    """-> (状態, メッセージ)。状態: same / update / restore / keep-local / conflict / adopt"""
    sh = sha1_file(src)
    if not os.path.exists(dst):
        return 'restore', 'コピーがない (再コピーする)'
    dh = sha1_file(dst)
    base = rec.get('sha1') if rec else None
    if dh == sh:
        return ('same' if base == sh else 'adopt'), '最新' if base == sh else '正本と同じ (記録を更新する)'
    if base is None:
        return 'conflict', '取り込みの記録がなく、正本と違う'
    if dh == base:
        return 'update', '候補側は、未編集 (正本に更新する)'
    if sh == base:
        return 'keep-local', '候補側だけが変更されている (そのまま。正本には、反映していない)'
    return 'conflict', '正本も、候補側も、変更されている'


def cmd_sync(parent, dry):
    shared, cands = load(parent)
    if not shared.get('spec'):
        die(f'{MANIFEST} に「- 仕様書: <パス>」がない。同期する仕様書が、決まっていない')
    conflicts, changed = 0, 0
    for c in cands:
        if not solutions_in(c['folder']):
            print(f'  ? {c["name"]}: まだ作られていない (create で作る)')
            continue
        plan = spec_plan(parent, shared, c)
        rec = read_record(c['folder'])
        newrec = dict(rec)
        for src, rel in plan['copies']:
            dst = os.path.join(c['folder'], rel)
            state, msg = classify(src, dst, rec.get(rel))
            mark = {'same': '=', 'update': '~', 'restore': '+', 'adopt': '=', 'keep-local': '!', 'conflict': 'X'}[state]
            print(f'  {mark} {c["name"]}: {rel}: {msg}')
            if state == 'conflict':
                conflicts += 1
                continue
            if state in ('update', 'restore', 'adopt'):
                changed += state != 'adopt'
                if not dry:
                    if state != 'adopt':
                        os.makedirs(os.path.dirname(dst), exist_ok=True)
                        with open(src, 'rb') as f, open(dst, 'wb') as g:
                            g.write(f.read())
                    newrec[rel] = {'src': os.path.relpath(src, parent).replace('\\', '/'), 'sha1': sha1_file(src)}
        if not dry and newrec != rec:
            write_record(c['folder'], newrec)
    print(f'\n更新 {changed} 件 / 衝突 {conflicts} 件' + (' (dry-run: 何も書いていない)' if dry else ''))
    print('テストケースの種 (*.cases.md) は、更新しない (チェック済みを守る)。仕様の変更に合わせて、各候補の /add-feature の計画で、見直す')
    if conflicts:
        print('衝突は、上書きしていない。候補側の変更が、不要なら、そのファイルを消して、もう一度 sync-spec する (正本から、再コピーされる)')
    return 1 if conflicts else 0


# ---------------------------------------------------------------- resolve
def cmd_resolve(target, name):
    target = os.path.abspath(target)
    if solutions_in(target):
        print(target)
        return 0
    if not os.path.isfile(os.path.join(target, MANIFEST)):
        print(f'対象のソリューションがない: {target} には、.sln / .slnx も、{MANIFEST} もない', file=sys.stderr)
        return 3
    shared, rows, errors = read_manifest(target)
    cands = check_rows(target, shared, rows, [])
    have = [c for c in cands if solutions_in(c['folder'])]
    if name:
        want = os.path.basename(name.rstrip('/\\')).lower()
        hit = [c for c in have if c['name'].lower() == want]
        if not hit:
            print(f'候補 "{name}" がない (作られている候補: {", ".join(c["name"] for c in have) or "なし"})', file=sys.stderr)
            return 3
        print(hit[0]['folder'])
        return 0
    if not have:
        print(f'{MANIFEST} の候補が、まだ作られていない (new_solutions.py create)', file=sys.stderr)
        return 3
    if len(have) == 1:
        print(have[0]['folder'])
        return 0
    print('CANDIDATES: ' + ', '.join(c['name'] for c in have), file=sys.stderr)
    print('候補が複数ある。どの候補を対象にするか、ユーザーに質問する (または、候補名を指定する)', file=sys.stderr)
    return 2


def main():
    ap = argparse.ArgumentParser(description='候補ごとのソリューションを、宣言ファイルから作る')
    sub = ap.add_subparsers(dest='cmd', required=True)
    for n in ('create', 'sync-spec'):
        sp = sub.add_parser(n)
        sp.add_argument('folder')
        sp.add_argument('--dry-run', action='store_true')
    sp = sub.add_parser('resolve')
    sp.add_argument('folder')
    sp.add_argument('name', nargs='?')
    try:
        a = ap.parse_args()
    except SystemExit:
        sys.exit(2)
    if not os.path.isdir(a.folder):
        die(f'フォルダがない: {a.folder}')
    folder = os.path.abspath(a.folder)
    if a.cmd == 'resolve':
        sys.exit(cmd_resolve(folder, a.name))
    sys.exit(cmd_create(folder, a.dry_run) if a.cmd == 'create' else cmd_sync(folder, a.dry_run))


if __name__ == '__main__':
    main()
