#!/usr/bin/env python3
"""msbuild_source.py - msbuild-common (共通の Directory.Build.props / .targets の元) の、場所の決め方と、ソリューションへの置き方 (v2.66.0)。

new_solution.py (新規のソリューション) と、add-project の add_common.py (すでにあるソリューション) が、共通で使う。
Claude は、共通ファイルの中身を決めない。外の正本を読んで、ソリューションに合わせて置く (加工する)。

正本の場所 (WSL 側のパス。Claude が読む) を決める順:
  1. ソリューションの CLAUDE.md の行  `- MSBuild 共通: /mnt/c/Tools/msbuild-common`
  2. 環境変数 MSBUILD_COMMON_DIR
  3. 配布用のコピー (new-solution/msbuild-common/。いまの正本の複製)

置き方 (モード):
  reference (参照型)  ソリューション直下に、外の正本を参照する薄いファイルだけを置く (templates/reference/)。コピーしない。
                      MSBuild (Visual Studio とウォッチャー) は、Windows 側の環境変数 MSBUILD_COMMON_DIR で、正本を探す。
  copy (コピー型)     薄いファイルと build/common/ (正本のコピー) を置く。ソリューションだけで完結する。
  auto (既定)         場所が、1 または 2 で決まれば reference、3 (配布用のコピー) なら copy。
  reference は、場所が 3 のときは、使えない (配布用のコピーは、Windows のビルドから見えない)。
"""
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
BUNDLED = os.path.normpath(os.path.join(HERE, '..', 'msbuild-common'))
ENV_NAME = 'MSBUILD_COMMON_DIR'
COMMON_FILES = ('Common.props', 'Dotnet.props', 'Common.targets', 'VERSION')
THIN = ('Directory.Build.props', 'Directory.Build.targets')
LINE_KEY = 'MSBuild 共通'
SECTION = '## MSBuild の共通設定'
IMPORT_LINE = {'Directory.Build.props': '<Import Project="$(MSBuildThisFileDirectory)build\\common\\Common.props" />',
               'Directory.Build.targets': '<Import Project="$(MSBuildThisFileDirectory)build\\common\\Common.targets" />'}
REF_MARK = '$(MSBUILD_COMMON_DIR)'   # 参照型の薄いファイルが、持つ印


class SourceError(Exception):
    pass


def claude_md_dir(sln_dir):
    """ソリューションの CLAUDE.md の `- MSBuild 共通: <パス>` の、パス。なければ None。"""
    p = os.path.join(sln_dir, 'CLAUDE.md')
    if not os.path.isfile(p):
        return None
    try:
        text = open(p, encoding='utf-8-sig').read()
    except OSError:
        return None
    m = re.search(r'^\s*[-*]\s*' + LINE_KEY + r'\s*[:：]\s*`?([^\s`(（]+)', text, re.M)
    if not m:
        return None
    v = m.group(1)
    return v if (v.startswith('/') or re.match(r'^[A-Za-z]:[\\/]', v)) else None


def to_wsl_path(p):
    """Windows のパス (C:\\Tools\\x) は、WSL のパス (/mnt/c/Tools/x) にする。WSL のパスは、そのまま。"""
    m = re.match(r'^([A-Za-z]):[\\/](.*)$', p)
    if not m:
        return p
    return '/mnt/' + m.group(1).lower() + '/' + m.group(2).replace('\\', '/')


def resolve(sln_dir=None, explicit=None):
    """戻り値: (正本のフォルダ, 決めた元)。元は 'option' / 'claude-md' / 'env' / 'bundled'。"""
    if explicit:
        return os.path.abspath(to_wsl_path(explicit)), 'option'
    if sln_dir:
        v = claude_md_dir(sln_dir)
        if v:
            return to_wsl_path(v), 'claude-md'
    v = os.environ.get(ENV_NAME, '').strip()
    if v:
        return to_wsl_path(v), 'env'
    return BUNDLED, 'bundled'


def decide_mode(requested, origin):
    """requested: auto / copy / reference。戻り値: copy か reference。"""
    if requested == 'reference':
        if origin == 'bundled':
            raise SourceError('参照型は、外の正本の場所が要る (環境変数 MSBUILD_COMMON_DIR、または、CLAUDE.md の「- MSBuild 共通: <パス>」)。'
                              '配布用のコピーは、Windows のビルドから見えないので、参照できない')
        return 'reference'
    if requested == 'copy':
        return 'copy'
    return 'copy' if origin == 'bundled' else 'reference'


def need_files(mode):
    if mode == 'reference':
        return ['Common.props', 'Common.targets', 'VERSION', 'templates/reference/Directory.Build.props', 'templates/reference/Directory.Build.targets']
    return list(COMMON_FILES) + ['templates/Directory.Build.props', 'templates/Directory.Build.targets']


def check_source(src, mode):
    if not os.path.isdir(src):
        raise SourceError(f'正本のフォルダがない: {src}')
    missing = [f for f in need_files(mode) if not os.path.isfile(os.path.join(src, *f.split('/')))]
    if missing:
        raise SourceError(f'正本 ({src}) に、必要なファイルがない: {", ".join(missing)}')


def read(src, rel):
    with open(os.path.join(src, *rel.split('/')), 'rb') as f:
        return f.read()


def version_of(src):
    try:
        return read(src, 'VERSION').decode('utf-8-sig').strip()
    except OSError:
        return ''


def thin_template(src, mode, fn):
    return read(src, ('templates/reference/' if mode == 'reference' else 'templates/') + fn)


def files_for(src, mode):
    """置くファイル (相対パス -> bytes)。copy は、薄いファイル 2 つと build/common/ の 4 ファイル。reference は、薄いファイル 2 つだけ。"""
    out = {fn: thin_template(src, mode, fn) for fn in THIN}
    if mode == 'copy':
        for fn in COMMON_FILES:
            out['build/common/' + fn] = read(src, fn)
    return out


def windows_path(p):
    """WSL のパスを、Windows のパスにする (wslpath -w)。使えなければ None。"""
    try:
        r = subprocess.run(['wslpath', '-w', p], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def reference_note(src):
    """参照型で、ユーザーに伝える NOTE (Windows 側の環境変数の設定)。"""
    w = windows_path(src)
    s = f'NOTE: 参照型。Windows 側の環境変数 {ENV_NAME} を、'
    s += f'`{w}` に設定すること (Visual Studio は、設定後に再起動する。ウォッチャーは、起動し直す)' if w else 'この正本の、Windows のパスに設定すること (wslpath -w で求められなかった)'
    return s


_NOTE_BODY_DOTNET = "- 共通の .NET の設定 (`Nullable` / `ImplicitUsings` / `LangVersion`) は、共通ファイルの `Dotnet.props`。`TargetFramework` は、各 `.csproj` に置く。\n"
_NOTE_BODY_CHECK = "- コンパイルの前に、プロジェクトの設定だけで判定できる検査 (層の参照の向き LAY003、ロジック層・データ層の WPF / WinForms 依存 LAY001、MFC の DLL の設定 DLL001〜DLL003) を行い、違反は**警告**に出る (`warnings.log`)。層の役割は、プロジェクトの名前から決まる (決まらないときは、`.csproj` / `.vcxproj` に `<ClaudeLayerRole>data|logic|viewmodel|ui|other</ClaudeLayerRole>`)。エラーにするには `/p:ClaudeCheck=error`、止めるには `/p:ClaudeCheck=off` (または `<ClaudeCheck>` を各プロジェクトに書く)。ソースの中身の検査は、種類ごとの check Skill が行う。\n"
_NOTE_BODY_INFO = "- ビルドの情報 (構成・Platform・出力ファイル) は、`/p:ClaudeBuildInfo=true` を渡したときだけ、中間出力フォルダの `claude-build-info.txt` に書かれる (既定では、何もしない)。\n"


def claude_note(dotnet, mode, src=None):
    """CLAUDE.md に足す節 (先頭が改行。末尾が改行)。"""
    s = f"\n{SECTION}\n\n"
    if mode == 'reference':
        s += (f"- {LINE_KEY}: {src}\n"
              f"- ソリューション直下の `Directory.Build.props` / `Directory.Build.targets` (薄いファイル) が、上の**外の正本** (`msbuild-common`) を参照する。**コピーしない。** "
              f"MSBuild (Visual Studio とウォッチャー) は、Windows 側の環境変数 `{ENV_NAME}` で、正本を探す (WSL 側のパスと、同じフォルダを指して設定する。Visual Studio は、設定後に再起動する)。"
              f"設定されていないと、ビルドは `__MSBUILD_COMMON_DIR_NOT_SET__\\Common.props was not found` のエラーで止まる。\n"
              f"- **正本の中身は、Claude が決めない。** 読んで、ソリューションに合わせて置くだけ (書き換えない)。直すときは、正本の管理者に頼む。\n")
    else:
        s += ("- ソリューション直下の `Directory.Build.props` / `Directory.Build.targets` (薄いファイル) が、`build\\common\\` の共通ファイル (`msbuild-common`。版は `build\\common\\VERSION`) を読む。"
              "**`build\\common\\` は、コピー。手で編集しない** (更新は、新しい版で、差し替える)。\n")
    if dotnet:
        s += _NOTE_BODY_DOTNET
    return s + _NOTE_BODY_CHECK + _NOTE_BODY_INFO
