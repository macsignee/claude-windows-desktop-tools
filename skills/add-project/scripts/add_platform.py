#!/usr/bin/env python3
"""add_platform.py - すでにある C++ のソリューションに、プラットフォーム (Win32 / x64) の構成を足す。

使い方:
  python3 add_platform.py <SLN_DIR> --platform Win32|x64 [--dry-run]

  x64 だけのソリューションに Win32 を足す (または、Win32 だけのソリューションに x64 を足す)。
  ソリューションの、すべての C++ プロジェクト (.vcxproj) の、元のプラットフォームの、構成のブロックを、複製して、新しいプラットフォームの
  ブロックにする (Condition の `|x64'` → `|Win32'`。Win32 は、ClCompile の PreprocessorDefinitions に `WIN32;`。VcpkgTriplet は、x86 / x64 のトリプレット)。
  .slnx には `<Platform Name="x86" />` (または x64) を足す。.sln には、ソリューションの構成と、プロジェクトの対応づけを足す。
  私たちが作った .vcxproj と、Visual Studio のウィザードが作った .vcxproj の、両方を対象にする。

  すでに、そのプラットフォームがあるプロジェクトは、何もしない (何度、実行しても、同じ結果)。
  **形が想定と違うプロジェクトが 1 つでもあれば、何も書かずに、止まる** (書きかけを残さない)。

終了コード:
  0 成功 (変更を書いた / --dry-run)
  2 引数・入力の問題、または、想定外の形式のプロジェクト (何も書いていない)
  3 すべて、すでにある (何も書いていない)
"""
import argparse
import os
import re
import sys
import xml.dom.minidom

BOM = b'\xef\xbb\xbf'
SKIP = {'packages', 'obj', '.vs', '.git', 'x64', 'x86', 'Win32', 'Debug', 'Release', 'vcpkg_installed', 'ThirdParty', '.claude-logs'}
TRIPLET_PREFIX = {'x64': 'x64', 'Win32': 'x86'}
BLOCK_TAGS = 'PropertyGroup|ImportGroup|ItemDefinitionGroup'


def die(msg, code=2):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(code)


def read_keep(path):
    raw = open(path, 'rb').read()
    bom = raw.startswith(BOM)
    text = (raw[3:] if bom else raw).decode('utf-8')
    nl = '\r\n' if '\r\n' in text else '\n'
    return text.replace('\r\n', '\n'), bom, nl


def write_keep(path, text, bom, nl):
    data = text.replace('\n', nl).encode('utf-8')
    with open(path, 'wb') as f:
        f.write((BOM if bom else b'') + data)


def find_vcxprojs(root):
    out = []
    for cur, ds, fs in os.walk(root):
        ds[:] = [d for d in ds if d not in SKIP]
        out += [os.path.join(cur, f) for f in fs if f.lower().endswith('.vcxproj')]
    return sorted(out)


def has_platform(text, plat):
    return re.search(r'<Platform>' + re.escape(plat) + r'</Platform>', text) is not None


def other(plat):
    return 'Win32' if plat == 'x64' else 'x64'


def convert_block(block, src, dst):
    """構成のブロックを、元のプラットフォームから、新しいプラットフォームへ、書き換える。"""
    b = block.replace(f"|{src}'", f"|{dst}'").replace(f"=='{src}'", f"=='{dst}'")

    def fix_cl(m):
        def d(mm):
            v = mm.group(1)
            if dst == 'Win32' and 'WIN32;' not in v:
                v = 'WIN32;' + v
            if dst == 'x64':
                v = v.replace('WIN32;', '')
            return f'<PreprocessorDefinitions>{v}</PreprocessorDefinitions>'
        # ClCompile の PreprocessorDefinitions だけ (Midl・ResourceCompile は、変えない)
        return re.sub(r'<PreprocessorDefinitions>([^<]*)</PreprocessorDefinitions>', d, m.group(0), count=1)
    return re.sub(r'<ClCompile>.*?</ClCompile>', fix_cl, b, flags=re.S)


def replace_runs(text, matches, make_copy, dst):
    """隣り合うマッチ (連続したブロック) を、ひとまとまりとして、複製をまとめて、前 (dst が Win32) か後 (dst が x64) に置く。
    (ウィザードや、私たちの生成物と、同じ並び: Debug|Win32、Release|Win32、Debug|x64、Release|x64)"""
    runs, cur = [], []
    for m in matches:
        if cur and m.start() == cur[-1].end():
            cur.append(m)
        else:
            if cur:
                runs.append(cur)
            cur = [m]
    if cur:
        runs.append(cur)
    out, pos = [], 0
    for run in runs:
        out.append(text[pos:run[0].start()])
        orig = text[run[0].start():run[-1].end()]
        copies = ''.join(make_copy(m.group(0)) for m in run)
        out.append((copies + orig) if dst == 'Win32' else (orig + copies))
        pos = run[-1].end()
    out.append(text[pos:])
    return ''.join(out)


def transform(text, src, dst):
    """.vcxproj のテキストに、dst の構成を足す。戻り値: (新しいテキスト, 足したブロックの数)。形が想定と違えば、ValueError。"""
    n_added = 0

    # 1. ProjectConfiguration (Include="Debug|x64")
    pc = re.compile(r'(?m)^([ \t]*)<ProjectConfiguration Include="(\w+)\|' + src + r'">.*?</ProjectConfiguration>\n', re.S)
    pcs = list(pc.finditer(text))
    if not pcs:
        raise ValueError(f'ProjectConfiguration に {src} がない')
    text = replace_runs(text, pcs, lambda blk: blk.replace(f'|{src}"', f'|{dst}"').replace(f'<Platform>{src}</Platform>', f'<Platform>{dst}</Platform>'), dst)
    n_added += len(pcs)

    # 2. 構成のブロック (PropertyGroup / ImportGroup / ItemDefinitionGroup で、Condition に src のプラットフォームを含むもの)
    blk_re = re.compile(r'(?m)^  <(' + BLOCK_TAGS + r')\b[^>\n]*Condition="[^"]*(?:\|' + src + r"'|=='" + src + r"')[^\"]*\"[^>\n]*>\n.*?^  </\1>\n", re.S)
    blocks = list(blk_re.finditer(text))
    if not blocks:
        raise ValueError(f'構成のブロック (Condition に {src}) が、見つからない (インデントが、想定と違う?)')
    text = replace_runs(text, blocks, lambda blk: convert_block(blk, src, dst), dst)
    n_added += len(blocks)

    # 3. 1 行の、構成ごとの要素 (例: <PrecompiledHeader Condition="...|x64'">Create</PrecompiledHeader>)
    line_re = re.compile(r'(?m)^([ \t]*)<(\w+) Condition="[^"]*(?:\|' + src + r"'|=='" + src + r"')[^\"]*\"[^>]*>[^<\n]*</\2>\n")
    ls = list(line_re.finditer(text))
    out, pos = [], 0
    for m in ls:
        out.append(text[pos:m.end()])
        pos = m.end()
        if m.group(2) == 'VcpkgTriplet':     # 値が違うので、下で、別に足す
            continue
        out.append(m.group(0).replace(f"|{src}'", f"|{dst}'").replace(f"=='{src}'", f"=='{dst}'"))
        n_added += 1
    out.append(text[pos:])
    text = ''.join(out)

    # 3b. VcpkgTriplet (x64 と x86 で、値の頭が違う)。dst の行が、まだなければ、足す
    if not re.search(r"<VcpkgTriplet Condition=\"'\$\(Platform\)'=='" + dst + r"'\"", text):
        def trip(m):
            val = m.group(3)
            pre = TRIPLET_PREFIX[src]
            newval = TRIPLET_PREFIX[dst] + val[len(pre):] if val.startswith(pre) else val
            add = f"{m.group(1)}<VcpkgTriplet Condition=\"'$(Platform)'=='{dst}'\">{newval}</VcpkgTriplet>\n"
            return (add + m.group(0)) if dst == 'Win32' else (m.group(0) + add)
        text = re.sub(r"(?m)^([ \t]*)<VcpkgTriplet Condition=\"'\$\(Platform\)'=='" + src + r"'\"([^>]*)>([^<\n]*)</VcpkgTriplet>\n", trip, text)
    return text, n_added


def plan_project(path, dst):
    """戻り値: ('skip' | 'add' | 'error', メッセージ, 新しいテキスト)"""
    text, bom, nl = read_keep(path)
    if has_platform(text, dst):
        return 'skip', 'すでに、' + dst + ' の構成がある', None
    src = other(dst)
    if not has_platform(text, src):
        return 'error', f'{src} の構成もない (想定外の形式)', None
    try:
        new, n = transform(text, src, dst)
        xml.dom.minidom.parseString(new.encode('utf-8'))
    except ValueError as e:
        return 'error', str(e), None
    except Exception as e:     # XML として壊れた
        return 'error', f'変換後の XML が、壊れた ({e})', None
    if not has_platform(new, dst):
        return 'error', '変換後に、構成がない', None
    return 'add', f'{src} のブロック {n} か所を、{dst} に複製する', new


# ---------------------------------------------------------------- ソリューション
def plan_slnx(path, dst):
    text, bom, nl = read_keep(path)
    name = 'x86' if dst == 'Win32' else 'x64'
    if re.search(r'<Platform Name="' + name + r'"\s*/>', text):
        return 'skip', f'すでに、<Platform Name="{name}" /> がある', None
    if '<Configurations>' not in text:
        new = text.replace('<Solution>\n', f'<Solution>\n  <Configurations>\n    <BuildType Name="Debug" />\n    <BuildType Name="Release" />\n    <Platform Name="{name}" />\n  </Configurations>\n', 1)
        if new == text:
            return 'error', '.slnx の形式が想定と違う (<Solution> がない)', None
        return 'add', f'<Configurations> を作って、<Platform Name="{name}" /> を足す', new
    m = re.search(r'(?m)^([ \t]*)<Platform Name="[^"]+"\s*/>\n', text)
    if m:
        ins = f'{m.group(1)}<Platform Name="{name}" />\n'
        # 並びは、私たちの生成物 (x64、x86) と同じ: x64 は先頭、x86 は後ろ
        new = (text[:m.start()] + ins + text[m.start():]) if name == 'x64' else (text[:m.end()] + ins + text[m.end():])
        if name == 'x86':
            last = list(re.finditer(r'(?m)^([ \t]*)<Platform Name="[^"]+"\s*/>\n', text))[-1]
            new = text[:last.end()] + ins + text[last.end():]
    else:
        new = text.replace('</Configurations>', f'  <Platform Name="{name}" />\n  </Configurations>', 1)
    return 'add', f'<Platform Name="{name}" /> を足す', new


def plan_sln(path, dst, vcx_guids):
    text, bom, nl = read_keep(path)
    sp = 'x86' if dst == 'Win32' else 'x64'
    src_sp = 'x64' if dst == 'Win32' else 'x86'
    if re.search(r'\|' + sp + r'\s*=\s*\w+\|' + sp, text):
        return 'skip', f'すでに、{sp} のソリューション構成がある', None
    lines = text.split('\n')
    out, added = [], 0
    in_cfg = in_map = False
    for ln in lines:
        out.append(ln)
        if 'GlobalSection(SolutionConfigurationPlatforms)' in ln:
            in_cfg = True
            continue
        if 'GlobalSection(ProjectConfigurationPlatforms)' in ln:
            in_map = True
            continue
        if 'EndGlobalSection' in ln:
            in_cfg = in_map = False
            continue
        if in_cfg:
            m = re.match(r'(\s*)(\w+)\|' + src_sp + r'\s*=\s*\w+\|' + src_sp + r'\s*$', ln)
            if m:
                out.append(f'{m.group(1)}{m.group(2)}|{sp} = {m.group(2)}|{sp}')
                added += 1
        if in_map:
            m = re.match(r'(\s*)(\{[0-9A-Fa-f-]+\})\.(\w+)\|' + src_sp + r'\.(ActiveCfg|Build\.0)\s*=\s*(\w+)\|(x64|Win32)\s*$', ln)
            if m and m.group(2).upper() in vcx_guids:
                pj = 'Win32' if dst == 'Win32' else 'x64'
                out.append(f'{m.group(1)}{m.group(2)}.{m.group(3)}|{sp}.{m.group(4)} = {m.group(5)}|{pj}')
                added += 1
    if not added:
        return 'error', f'.sln に {src_sp} の構成が見つからない (対応づけを、Visual Studio の構成マネージャーで、足す)', None
    return 'add', f'{added} 行を足す', '\n'.join(out)


def vcx_guids_in(paths):
    g = set()
    for p in paths:
        text, _b, _n = read_keep(p)
        m = re.search(r'<ProjectGuid>(\{[0-9A-Fa-f-]+\})</ProjectGuid>', text)
        if m:
            g.add(m.group(1).upper())
    return g


def main():
    ap = argparse.ArgumentParser(description='C++ のソリューションに、プラットフォームを足す')
    ap.add_argument('sln_dir')
    ap.add_argument('--platform', required=True, help='足すプラットフォーム: Win32 (x86) / x64')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    dst = {'x64': 'x64', 'win32': 'Win32', 'x86': 'Win32'}.get(a.platform.strip().lower())
    if dst is None:
        die('--platform は、Win32 (x86) か x64')
    root = os.path.abspath(a.sln_dir)
    if not os.path.isdir(root):
        die(f'フォルダがない: {root}')
    slns = [f for f in sorted(os.listdir(root)) if f.lower().endswith(('.sln', '.slnx'))]
    if not slns:
        die(f'.sln / .slnx が見つからない: {root}')
    if len(slns) > 1:
        die(f'ソリューションが複数ある ({", ".join(slns)})。どれを使うか、ユーザーに確認すること')
    sln = os.path.join(root, slns[0])
    vcxs = find_vcxprojs(root)
    if not vcxs:
        die('C++ のプロジェクト (.vcxproj) が、ない (.NET は、AnyCPU で、この機能の対象外)')

    results = []        # (path, kind, msg, newtext)
    for p in vcxs:
        kind, msg, new = plan_project(p, dst)
        results.append((p, kind, msg, new))
    if sln.lower().endswith('.slnx'):
        kind, msg, new = plan_slnx(sln, dst)
    else:
        kind, msg, new = plan_sln(sln, dst, vcx_guids_in(vcxs))
    results.append((sln, kind, msg, new))

    print(f'ソリューション : {os.path.basename(sln)}')
    print(f'足すもの       : {dst} の構成' + (' (.slnx / .sln では x86)' if dst == 'Win32' else ''))
    for p, kind, msg, _n in results:
        mark = {'add': '+', 'skip': '=', 'error': '!'}[kind]
        print(f'  {mark} {os.path.relpath(p, root).replace(os.sep, "/")}: {msg}')
    errors = [r for r in results if r[1] == 'error']
    if errors:
        die('想定と違う形式のファイルがある。何も書いていない。上の「!」の行を、確かめること', 2)
    todo = [r for r in results if r[1] == 'add']
    if not todo:
        print('すべて、すでにある。何も書いていない')
        sys.exit(3)
    if a.dry_run:
        print('(dry-run: 何も書いていない)')
        return
    for p, _k, _m, new in todo:
        _text, bom, nl = read_keep(p)
        write_keep(p, new, bom, nl)
    print(f'完了。{len(todo)} ファイルを書き換えた')
    if dst == 'Win32':
        print('NOTE: Win32 でビルドするには、ウォッチャーを `run_watcher.cmd <フォルダ> "" Win32` で起動する (引数なしは x64)')


if __name__ == '__main__':
    main()
