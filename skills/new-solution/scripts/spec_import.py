#!/usr/bin/env python3
"""spec_import.py - new_solution.py --spec が、仕様書 (docs/specs/*.md) の内容を、新しいソリューションへ取り込む。

  1. 仕様書 (と、「元:」のメモ) を、ソリューションのフォルダの docs/specs/ (docs/ideas/) に置く (すでにそこにあれば、何もしない)。
  2. 仕様書の「具体例」「境界値と異常系」の表から、テストケースの種 (docs/specs/<名前>.cases.md) を作る。
     /add-feature の計画が、これを読んで、テスト名と期待値に確定する (テストなしなら、手動の確認項目になる)。
  3. CLAUDE.md に、「## 仕様書」の節を足す (仕様書とケースの種へのリンク。すでにあれば、足さない)。

このモジュールは、new_solution.py が読み込む。単独では、実行しない。コードやテストは、書かない。
"""
import os
import re
import shutil

SECTION_MARK = '## 仕様書'
PLACEHOLDER = {'', '-', 'ー', '...', '…', '(なし)', 'なし', 'TBD'}


def _section(text, title):
    m = re.search(r'^## ' + re.escape(title) + r'[^\n]*\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    return m.group(1) if m else ''


def _rows(body):
    """Markdown の表の、データ行 (見出し行と区切り行を除く)。すべて空・プレースホルダの行も除く。"""
    out = []
    lines = [ln.strip() for ln in body.split('\n') if ln.strip().startswith('|')]
    for i, ln in enumerate(lines):
        cells = [c.strip() for c in ln.strip('|').split('|')]
        if i == 0 or all(re.match(r'^:?-{2,}:?$', c) for c in cells if c):
            continue
        if all(c in PLACEHOLDER for c in cells):
            continue
        out.append(cells)
    return out


def read_cases(spec_text):
    """-> (具体例の行のリスト, 境界値の行のリスト)。行は、セルのリスト。"""
    return _rows(_section(spec_text, '具体例')), _rows(_section(spec_text, '境界値と異常系'))


def _title(spec_text, fallback):
    m = re.match(r'^#\s+(.+)$', spec_text.lstrip('﻿'), re.M)
    return m.group(1).strip() if m else fallback


def cases_text(spec_rel, title, examples, bounds, kind):
    out = [f'# {title}: テストケースの種', '',
           f'- 仕様書: {spec_rel}',
           f'- 種類: {kind}',
           '- 作成: new_solution.py --spec (自動生成)。**テストコードではない。** /add-feature の計画が、テスト名・入力・期待値に確定する。確定したら、チェックを付ける', '']
    out.append('## 具体例 (E)')
    if examples:
        for i, c in enumerate(examples, 1):
            inp, exp = (c + ['', ''])[:2]
            note = f' ({c[2]})' if len(c) > 2 and c[2] not in PLACEHOLDER else ''
            out.append(f'- [ ] E{i}: {inp} → {exp}{note}')
    else:
        out.append('- (仕様書の表に、行がない。/update-from-ideas で、具体例を足す)')
    out += ['', '## 境界値と異常系 (B)']
    if bounds:
        for i, c in enumerate(bounds, 1):
            case, beh = (c + ['', ''])[:2]
            out.append(f'- [ ] B{i}: {case} → {beh}')
    else:
        out.append('- (仕様書の表に、行がない。/update-from-ideas で、境界値と異常系を足す)')
    return '\n'.join(out) + '\n'


def plan(folder, spec_path, tests_label):
    """何を書くかを、決める (書かない)。-> dict: {'copies': [(src, rel)], 'cases_rel', 'cases', 'spec_rel', 'counts'}"""
    spec_path = os.path.abspath(spec_path)
    text = open(spec_path, encoding='utf-8-sig').read().replace('\r\n', '\n')
    folder = os.path.abspath(folder)
    spec_rel = 'docs/specs/' + os.path.basename(spec_path)
    copies = []
    if os.path.abspath(os.path.join(folder, spec_rel)) != spec_path:
        copies.append((spec_path, spec_rel))
    m = re.search(r'^- 元:\s*(\S+)', text, re.M)
    if m and m.group(1).startswith('docs/ideas/'):
        # 仕様書の 2 つ上 (docs/specs/x.md -> プロジェクトのルート) からの、相対パス
        root = os.path.dirname(os.path.dirname(os.path.dirname(spec_path)))
        src = os.path.join(root, m.group(1))
        if os.path.isfile(src) and os.path.abspath(os.path.join(folder, m.group(1))) != os.path.abspath(src):
            copies.append((src, m.group(1)))
    examples, bounds = read_cases(text)
    stem = os.path.splitext(os.path.basename(spec_path))[0]
    cases_rel = f'docs/specs/{stem}.cases.md'
    kind = tests_label if tests_label else '手動の確認項目 (テストなし)'
    return {'copies': copies, 'spec_rel': spec_rel, 'cases_rel': cases_rel,
            'cases': cases_text(spec_rel, _title(text, stem), examples, bounds, kind),
            'counts': (len(examples), len(bounds))}


def describe(p):
    out = [f'  + {p["cases_rel"]} (テストケースの種: 具体例 {p["counts"][0]} 件、境界値・異常系 {p["counts"][1]} 件)']
    out += [f'  + {rel} (仕様書の取り込み)' for _, rel in p['copies']]
    out.append('  ~ CLAUDE.md (「## 仕様書」の節)')
    return out


def apply(folder, p):
    for src, rel in p['copies']:
        dst = os.path.join(folder, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.exists(dst):
            shutil.copyfile(src, dst)
    dst = os.path.join(folder, p['cases_rel'])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.exists(dst):   # 確定済みのチェックを、上書きしない
        with open(dst, 'w', encoding='utf-8', newline='\n') as f:
            f.write(p['cases'])
    append_claude_md(folder, p)


def append_claude_md(folder, p):
    path = os.path.join(folder, 'CLAUDE.md')
    if not os.path.isfile(path):
        return
    raw = open(path, 'rb').read().decode('utf-8-sig')
    if SECTION_MARK in raw:
        return
    nl = '\r\n' if '\r\n' in raw else '\n'
    add = (f'{nl}{SECTION_MARK}{nl}'
           f'- 仕様書: `{p["spec_rel"]}` (`/add-feature` は、これを読む){nl}'
           f'- テストケースの種: `{p["cases_rel"]}` (テスト名・期待値に確定したら、チェックを付ける){nl}')
    with open(path, 'wb') as f:
        f.write((raw.rstrip('\r\n') + nl + add).encode('utf-8'))
