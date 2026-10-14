#!/usr/bin/env python3
"""add_layer.py - ソリューションに、「DLL プロジェクト」と、(必要なら) 「対応するテスト exe (GoogleTest)」を追加する。

Usage: python3 add_layer.py <SLN_DIR> <Name> [--kind dll|lib] [--tests none|gtest] [--tests-only] [--namespace NS] [--uses OTHER ...]
                            [--toolset v145] [--gtest-from DIR] [--dry-run]

  SLN_DIR      .sln または .slnx があるフォルダ (Claude Code を起動したフォルダ)
  Name         DLL のプロジェクト名 (例: DataLayer)。テストは <Name>Test になる
  --tests      gtest (既定): DLL + テスト exe を作る。none: DLL だけを作る (テスト・GoogleTest は作らない)
  --kind       dll (既定) / lib: DLL を作るか、静的ライブラリ (公開マクロなし。テスト exe や UI に、リンクで取り込まれる) を作るか
  --tests-only すでにある DLL / 静的ライブラリ <Name> に、テスト exe だけを足す (DLL の名前空間・参照は、既存のファイルから読む)
  --gtest      auto (既定) / nuget / source: GoogleTest の入れ方。auto は、既存の gtest プロジェクト → source、パッケージがある・コピーできる → nuget、
               ソースがある → source、どれもない → source (ウォッチャーで取得: gtest_once.sh)。
               source: ThirdParty/googletest のソースを、静的ライブラリ gtest としてビルドする (NuGet 不要)
  --gtest-from GoogleTest の NuGet パッケージのコピー元 (packages フォルダ、または、パッケージのフォルダ)。
               省略時は、兄弟フォルダ (../*/packages/) から探す
  --namespace  C++ の名前空間 (既定: ソリューション名の、大文字の頭文字を、小文字にしたもの。例: ThreeLayerSample -> tls)
  --uses       この DLL が、ヘッダ (インターフェース) を参照する、別のプロジェクトのフォルダ名 (複数可)。
               インクルードパスに追加するだけで、リンクはしない (例: ロジック DLL が --uses DataLayer)
  --toolset    PlatformToolset (既定: 既存の .vcxproj から検出。なければ v145)
  --dry-run    何も書かず、行う内容だけを表示する

作るもの (すべて x64 の Debug / Release):
  <Name>/<Name>.vcxproj, <Name>Api.h (公開マクロ), <Name>ModuleInfo.h/.cpp (ビルド確認用の、小さな公開関数)
  <Name>Test/<Name>Test.vcxproj, packages.config (GoogleTest の NuGet), Test<Name>ModuleInfo.cpp (ベースライン用の、1 件のテスト)
  ソリューション (.sln / .slnx) に、プロジェクトを追加する。
テストを作るとき (--tests gtest):
  - packages\\ に GoogleTest がなければ、兄弟フォルダなどの既存のものを、コピーする (出力: GTEST_PACKAGE)。
  - exe のメインプロジェクトの名前が Test / Tests で終わる場合は、<TargetName> を、<名前>_Main にする
    (ウォッチャーが *Test.exe を、テストとして実行するので、アプリが起動されるのを防ぐ)。

終了コード: 0 成功 / 2 引数・ソリューションの問題 / 3 すでに存在する (何も書かない)
規約は、同梱の DLL-LAYOUT.md を参照。
"""
import argparse
import glob
import os
import re
import shutil
import sys
import uuid

BOM = b'\xef\xbb\xbf'
CPP_TYPE = '{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}'
GTEST_ID = 'Microsoft.googletest.v140.windesktop.msvcstl.static.rt-dyn'
GTEST_VER = '1.8.1.8'
GTEST_TARGETS = f'..\\packages\\{GTEST_ID}.{GTEST_VER}\\build\\native\\{GTEST_ID}.targets'

# 日本語版 Visual Studio のウィザードが生成するものと同じフィルター名・GUID・拡張子リスト。
# (フィルター名は、ロケールごとに異なる。ここを英語にすると、日本語版 VS で開いたときに
#  「ヘッダー ファイル」と「Header Files」が別物として扱われ、二重のフィルターができる)
FILTER_SOURCE = ('ソース ファイル', '{4FC737F1-C7A5-4376-A066-2A32D752A2FF}',
                  'cpp;c;cc;cxx;c++;cppm;ixx;def;odl;idl;hpj;bat;asm;asmx')
FILTER_HEADER = ('ヘッダー ファイル', '{93995380-89BD-4b04-88EB-625FBE52EBFB}',
                  'h;hh;hpp;hxx;h++;hm;inl;inc;ipp;xsd')
FILTER_RESOURCE = ('リソース ファイル', '{67DA6AB6-F800-4c08-8B7A-83BB121AAD01}',
                    'rc;ico;cur;bmp;dlg;rc2;rct;bin;rgs;gif;jpg;jpeg;jpe;resx;tiff;tif;png;wav;mfcribbon-ms')


def filter_name_for(path):
    ext = path.rsplit('.', 1)[-1].lower() if '.' in path else ''
    if ext in ('h', 'hh', 'hpp', 'hxx'):
        return FILTER_HEADER[0]
    if ext in ('cpp', 'c', 'cc', 'cxx'):
        return FILTER_SOURCE[0]
    if ext == 'rc':
        return FILTER_RESOURCE[0]
    return None


def die(msg, code=2):
    print(f'ERROR: {msg}')
    sys.exit(code)


def new_guid():
    return '{' + str(uuid.uuid4()).upper() + '}'


def find_solution(sln_dir):
    found = [f for f in sorted(os.listdir(sln_dir)) if f.lower().endswith(('.sln', '.slnx'))]
    if not found:
        die(f'.sln / .slnx が見つからない: {sln_dir}')
    if len(found) > 1:
        die(f'ソリューションが複数ある ({", ".join(found)})。どれを使うか、ユーザーに確認すること')
    return os.path.join(sln_dir, found[0])


def default_namespace(sln_path):
    stem = os.path.splitext(os.path.basename(sln_path))[0]
    caps = re.findall(r'[A-Z]', stem)
    return (''.join(caps).lower() if len(caps) >= 2 else re.sub(r'\W', '', stem).lower()) or 'app'


def detect_toolset(sln_dir):
    for root, dirs, files in os.walk(sln_dir):
        dirs[:] = [d for d in dirs if d not in ('packages', 'obj', '.vs', '.git', 'x64', 'Debug', 'Release')]
        for f in files:
            if f.endswith('.vcxproj'):
                try:
                    text = open(os.path.join(root, f), encoding='utf-8-sig').read()
                except OSError:
                    continue
                m = re.search(r'<PlatformToolset>(v\d+)</PlatformToolset>', text)
                if m:
                    return m.group(1)
    return 'v145'


def to_crlf(text):
    return text.replace('\r\n', '\n').replace('\n', '\r\n')


def vcxproj(name, guid, cfgtype, toolset, items, refs, incs, defs, subsystem, tail='', mfc=False, third_party=False):
    mfcx = '\n    <UseOfMfc>Dynamic</UseOfMfc>' if mfc else ''
    sub = f'\n      <SubSystem>{subsystem}</SubSystem>'
    inc = ''
    if incs:
        inc = '\n      <AdditionalIncludeDirectories>' + ';'.join(incs) + ';%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>'

    def cfg(c, debug):
        return f'''  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='{c}|x64'" Label="Configuration">
    <ConfigurationType>{cfgtype}</ConfigurationType>
    <UseDebugLibraries>{'true' if debug else 'false'}</UseDebugLibraries>
    <PlatformToolset>{toolset}</PlatformToolset>
    <CharacterSet>Unicode</CharacterSet>{mfcx}
  </PropertyGroup>
'''

    def props(c):
        return f'''  <ImportGroup Label="PropertySheets" Condition="'$(Configuration)|$(Platform)'=='{c}|x64'">
    <Import Project="$(UserRootDir)\\Microsoft.Cpp.$(Platform).user.props" Condition="exists('$(UserRootDir)\\Microsoft.Cpp.$(Platform).user.props')" Label="LocalAppDataPlatform" />
  </ImportGroup>
'''

    def defs_group(c, debug):
        d = ('_DEBUG;' if debug else 'NDEBUG;') + defs
        opt = '' if debug else '\n      <FunctionLevelLinking>true</FunctionLevelLinking>\n      <IntrinsicFunctions>true</IntrinsicFunctions>'
        lnk = '' if debug else '\n      <EnableCOMDATFolding>true</EnableCOMDATFolding>\n      <OptimizeReferences>true</OptimizeReferences>'
        # 静的ライブラリは、リンカーを使わない (<Link> は、意味を持たない)
        link_xml = '' if cfgtype == 'StaticLibrary' else f'''    <Link>{sub}
      <GenerateDebugInformation>true</GenerateDebugInformation>{lnk}
    </Link>
'''
        return f'''  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='{c}|x64'">
    <ClCompile>
      <WarningLevel>{'TurnOffAllWarnings' if third_party else 'Level3'}</WarningLevel>
      <SDLCheck>{'false' if third_party else 'true'}</SDLCheck>
      <ConformanceMode>true</ConformanceMode>
      <LanguageStandard>stdcpp20</LanguageStandard>
      <PrecompiledHeader>NotUsing</PrecompiledHeader>
      <PreprocessorDefinitions>{d}%(PreprocessorDefinitions)</PreprocessorDefinitions>{opt}{inc}
    </ClCompile>
{link_xml}  </ItemDefinitionGroup>
'''

    out = f'''<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup Label="ProjectConfigurations">
    <ProjectConfiguration Include="Debug|x64">
      <Configuration>Debug</Configuration>
      <Platform>x64</Platform>
    </ProjectConfiguration>
    <ProjectConfiguration Include="Release|x64">
      <Configuration>Release</Configuration>
      <Platform>x64</Platform>
    </ProjectConfiguration>
  </ItemGroup>
  <PropertyGroup Label="Globals">
    <VCProjectVersion>17.0</VCProjectVersion>
    <ProjectGuid>{guid}</ProjectGuid>
    <Keyword>Win32Proj</Keyword>
    <RootNamespace>{name}</RootNamespace>
    <WindowsTargetPlatformVersion>10.0</WindowsTargetPlatformVersion>
  </PropertyGroup>
  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.Default.props" />
''' + cfg('Debug', True) + cfg('Release', False) + '''  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.props" />
  <ImportGroup Label="ExtensionSettings">
  </ImportGroup>
  <ImportGroup Label="Shared">
  </ImportGroup>
''' + props('Debug') + props('Release') + '''  <PropertyGroup Label="UserMacros" />
  <PropertyGroup>
    <!-- ウォッチャーが、<ソリューション>\\x64\\<Configuration>\\ の *Test.exe を探す。DLL も同じ場所に出す (実行時に、exe と同じフォルダが必要)。 -->
    <OutDir>$(SolutionDir)$(Platform)\\$(Configuration)\\</OutDir>
    <IntDir>$(SolutionDir)obj\\$(ProjectName)\\$(Platform)\\$(Configuration)\\</IntDir>
  </PropertyGroup>
''' + defs_group('Debug', True) + defs_group('Release', False)
    hd = [i for i in items if i.endswith('.h')]
    cl = [i for i in items if i.endswith(('.cpp', '.cc', '.cxx', '.c'))]
    rc = [i for i in items if i.endswith('.rc')]
    out += '  <ItemGroup>\n' + ''.join(f'    <ClInclude Include="{h}" />\n' for h in hd) + '  </ItemGroup>\n'
    out += '  <ItemGroup>\n' + ''.join(f'    <ClCompile Include="{c}" />\n' for c in cl) + '  </ItemGroup>\n'
    if rc:
        out += '  <ItemGroup>\n' + ''.join(f'    <ResourceCompile Include="{r}" />\n' for r in rc) + '  </ItemGroup>\n'
    if 'packages.config' in items:
        out += '  <ItemGroup>\n    <None Include="packages.config" />\n  </ItemGroup>\n'
    if refs:
        out += '  <ItemGroup>\n' + ''.join(
            f'    <ProjectReference Include="..\\{n}\\{n}.vcxproj">\n      <Project>{g}</Project>\n    </ProjectReference>\n'
            for n, g in refs) + '  </ItemGroup>\n'
    out += '  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.targets" />\n' + tail + '</Project>\n'
    return out


def vcxproj_filters(items):
    hd = [i for i in items if filter_name_for(i) == FILTER_HEADER[0]]
    cl = [i for i in items if filter_name_for(i) == FILTER_SOURCE[0]]
    rc = [i for i in items if filter_name_for(i) == FILTER_RESOURCE[0]]
    defs = [d for d, present in ((FILTER_SOURCE, cl), (FILTER_HEADER, hd), (FILTER_RESOURCE, rc)) if present]

    out = '<?xml version="1.0" encoding="utf-8"?>\n'
    out += '<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
    out += '  <ItemGroup>\n' + ''.join(
        f'    <Filter Include="{n}">\n      <UniqueIdentifier>{g}</UniqueIdentifier>\n      <Extensions>{e}</Extensions>\n    </Filter>\n'
        for n, g, e in defs) + '  </ItemGroup>\n'

    def group(tag, paths, filt):
        if not paths:
            return ''
        return '  <ItemGroup>\n' + ''.join(
            f'    <{tag} Include="{p}">\n      <Filter>{filt}</Filter>\n    </{tag}>\n' for p in paths) + '  </ItemGroup>\n'

    out += group('ClInclude', hd, FILTER_HEADER[0])
    out += group('ClCompile', cl, FILTER_SOURCE[0])
    out += group('ResourceCompile', rc, FILTER_RESOURCE[0])
    out += '</Project>\n'
    return out


GTEST_SRC_INCLUDE = '$(ProjectDir)..\\ThirdParty\\googletest\\include'


def gtest_source_dir(sln_dir):
    return os.path.join(sln_dir, 'ThirdParty', 'googletest')


def gtest_source_present(sln_dir):
    d = gtest_source_dir(sln_dir)
    return (os.path.isfile(os.path.join(d, 'include', 'gtest', 'gtest.h')) and
            os.path.isfile(os.path.join(d, 'src', 'gtest-all.cc')) and
            os.path.isfile(os.path.join(d, 'src', 'gtest_main.cc')))


def gtest_project_files(toolset, guid):
    """ソリューションに含める、GoogleTest の静的ライブラリ (gtest)。ソースは ThirdParty/googletest (ホスト側が取得する)。
    gtest_main.cc も同じライブラリに入れる (テスト exe に main がなければ、リンカーが取り込む)。"""
    items = ['..\\ThirdParty\\googletest\\src\\gtest-all.cc', '..\\ThirdParty\\googletest\\src\\gtest_main.cc']
    files = {}
    files['gtest/gtest.vcxproj'] = vcxproj(
        'gtest', guid, 'StaticLibrary', toolset, items, [],
        [GTEST_SRC_INCLUDE, '$(ProjectDir)..\\ThirdParty\\googletest'], '_LIB;', 'Windows', third_party=True)
    files['gtest/gtest.vcxproj.filters'] = vcxproj_filters(items)
    return files


def read_project_guid(vcxproj_path):
    text = open(vcxproj_path, encoding='utf-8-sig').read()
    m = re.search(r'<ProjectGuid>(\{[0-9A-Fa-f-]+\})</ProjectGuid>', text)
    return m.group(1).upper() if m else None


def resolve_gtest_mode(sln_dir, requested='auto'):
    """GoogleTest の入れ方を決める。戻り値: (mode, status)。ファイルは、書かない。
      nuget : NuGet パッケージ (packages\\ に、あるか、既存のものをコピーできる)。status は ensure_gtest(dry=True) の値
      source: ソース (ThirdParty/googletest) を、静的ライブラリ gtest として、ビルドする。status は present / to-fetch
    auto: 既存の gtest プロジェクト → source / パッケージがある・コピーできる → nuget / ソースがある → source / どれもない → source (to-fetch)"""
    if requested == 'nuget':
        return 'nuget', ensure_gtest(sln_dir, None, dry=True)
    src_status = 'present' if gtest_source_present(sln_dir) else 'to-fetch'
    if requested == 'source':
        return 'source', src_status
    if os.path.isfile(os.path.join(sln_dir, 'gtest', 'gtest.vcxproj')):
        return 'source', src_status
    return None, None   # 呼び出し側 (gtest_from を知っている) が、決める


def decide_gtest_mode(sln_dir, requested, gtest_from):
    mode, status = resolve_gtest_mode(sln_dir, requested)
    if mode:
        if mode == 'nuget':
            status = ensure_gtest(sln_dir, gtest_from, dry=True)
        return mode, status
    st = ensure_gtest(sln_dir, gtest_from, dry=True)
    if st != 'missing':
        return 'nuget', st
    if gtest_source_present(sln_dir):
        return 'source', 'present'
    return 'source', 'to-fetch'


def plan_gtest(sln_dir, mode, toolset):
    """source 方式のとき、gtest プロジェクトを足す必要があるか。戻り値: (files, projects, gtest_guid)"""
    if mode != 'source':
        return {}, [], None
    existing = os.path.join(sln_dir, 'gtest', 'gtest.vcxproj')
    if os.path.isfile(existing):
        return {}, [], read_project_guid(existing)
    g = new_guid()
    return gtest_project_files(toolset, g), [('gtest', g)], g


def nuget_tail():
    t = GTEST_TARGETS
    return f'''  <ImportGroup Label="ExtensionTargets">
    <Import Project="{t}" Condition="Exists('{t}')" />
  </ImportGroup>
  <Target Name="EnsureNuGetPackageBuildImports" BeforeTargets="PrepareForBuild">
    <PropertyGroup>
      <ErrorText>GoogleTest の NuGet パッケージがありません。Visual Studio で [NuGet パッケージの復元] を実行してください。見つからないファイル: {{0}}</ErrorText>
    </PropertyGroup>
    <Error Condition="!Exists('{t}')" Text="$([System.String]::Format('$(ErrorText)', '{t}'))" />
  </Target>
'''


def dll_files(name, ns, uses, toolset, dg, kind='dll'):
    """DLL (kind='dll') か、静的ライブラリ (kind='lib') の、プロジェクト一式。"""
    if kind == 'lib':
        return lib_files(name, ns, uses, toolset, dg)
    up = name.upper()
    use_inc = [f'$(ProjectDir)..\\{u}' for u in uses]
    api = f'{name}Api.h'
    info_h = f'{name}ModuleInfo.h'
    info_cpp = f'{name}ModuleInfo.cpp'
    func = f'{name}ModuleName'

    files = {}
    files[f'{name}/{name}.vcxproj'] = vcxproj(
        name, dg, 'DynamicLibrary', toolset, [api, info_h, info_cpp], [], use_inc,
        f'{up}_EXPORTS;_WINDOWS;_USRDLL;', 'Windows')
    files[f'{name}/{name}.vcxproj.filters'] = vcxproj_filters([api, info_h, info_cpp])
    files[f'{name}/{api}'] = f'''#pragma once

// DLL の公開 (エクスポート) マクロ。{name} 自身をビルドするときだけ {up}_EXPORTS が定義される。
// テスト exe や UI から使うクラス・関数には、{up}_API を付ける (例: class {up}_API Foo)。
// 付け忘れると、利用側でリンクエラー (LNK2019) になる。
#ifdef {up}_EXPORTS
#define {up}_API __declspec(dllexport)
#else
#define {up}_API __declspec(dllimport)
#endif

// 公開クラスが std:: のメンバを持つことの警告。同じコンパイラ・同じ CRT で、まとめてビルドする前提で、抑止する。
#pragma warning(disable : 4251)
'''
    files[f'{name}/{info_h}'] = f'''#pragma once
#include "{api}"

namespace {ns}
{{
    // ビルドの確認用 (DLL の公開・リンク・実行時の読み込みを確かめる)。本物の機能を入れたら、削除してよい。
    {up}_API const char* {func}();
}}
'''
    files[f'{name}/{info_cpp}'] = f'''#include "{info_h}"

namespace {ns}
{{
    const char* {func}()
    {{
        return "{name}";
    }}
}}
'''
    return files


def lib_files(name, ns, uses, toolset, dg):
    """静的ライブラリ。公開マクロは、不要 (リンク時に、テスト exe や UI に、取り込まれる)。"""
    use_inc = [f'$(ProjectDir)..\\{u}' for u in uses]
    info_h = f'{name}ModuleInfo.h'
    info_cpp = f'{name}ModuleInfo.cpp'
    func = f'{name}ModuleName'
    files = {}
    files[f'{name}/{name}.vcxproj'] = vcxproj(
        name, dg, 'StaticLibrary', toolset, [info_h, info_cpp], [], use_inc, '_LIB;', 'Windows')
    files[f'{name}/{name}.vcxproj.filters'] = vcxproj_filters([info_h, info_cpp])
    files[f'{name}/{info_h}'] = f'''#pragma once

namespace {ns}
{{
    // ビルドの確認用 (静的ライブラリが、リンクできることを確かめる)。本物の機能を入れたら、削除してよい。
    // 静的ライブラリなので、公開マクロ (dllexport / dllimport) は、不要。
    const char* {func}();
}}
'''
    files[f'{name}/{info_cpp}'] = f'''#include "{info_h}"

namespace {ns}
{{
    const char* {func}()
    {{
        return "{name}";
    }}
}}
'''
    return files


def test_files(name, ns, uses, toolset, dg, tg, baseline_link=True, gtest_mode='nuget', gtest_guid=None):
    test = name + 'Test'
    use_inc = [f'$(ProjectDir)..\\{u}' for u in uses]
    info_h = f'{name}ModuleInfo.h'
    test_cpp = f'Test{name}ModuleInfo.cpp'
    func = f'{name}ModuleName'

    files = {}
    if gtest_mode == 'source':
        # ソースから、ソリューション内でビルドした静的ライブラリ (gtest) を、プロジェクト参照でリンクする (NuGet 不要)
        files[f'{test}/{test}.vcxproj'] = vcxproj(
            test, tg, 'Application', toolset, [test_cpp], [(name, dg), ('gtest', gtest_guid)],
            [f'$(ProjectDir)..\\{name}'] + use_inc + [GTEST_SRC_INCLUDE], '_CONSOLE;', 'Console')
    else:
        files[f'{test}/{test}.vcxproj'] = vcxproj(
            test, tg, 'Application', toolset, [test_cpp, 'packages.config'], [(name, dg)],
            [f'$(ProjectDir)..\\{name}'] + use_inc, '_CONSOLE;', 'Console', tail=nuget_tail())
        files[f'{test}/packages.config'] = f'''<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="{GTEST_ID}" version="{GTEST_VER}" targetFramework="native" />
</packages>
'''
    if baseline_link:
        files[f'{test}/{test_cpp}'] = f'''#include <gtest/gtest.h>
#include "{info_h}"

// ベースライン (ビルド・リンク・実行ができることの確認)。本物のテストが増えたら、削除してよい。
TEST({name}ModuleInfoTest, ModuleName_ReturnsProjectName)
{{
    EXPECT_STREQ("{name}", {ns}::{func}());
}}
'''
    else:
        files[f'{test}/{test_cpp}'] = f'''#include <gtest/gtest.h>

// ベースライン (テスト exe が、ビルド・実行できることだけの確認)。{name} の公開関数を呼んでいないので、DLL のリンクは確かめていない。
// {name} の公開関数のテストに置き換えること。
TEST({name}BaselineTest, TestExeRuns)
{{
    SUCCEED();
}}
'''
    files[f'{test}/{test}.vcxproj.filters'] = vcxproj_filters([test_cpp])
    return files


def build_files(name, ns, uses, toolset, tests=True, kind='dll', gtest_mode='nuget', gtest_guid=None):
    dg, tg = new_guid(), new_guid()
    files = dll_files(name, ns, uses, toolset, dg, kind)
    projects = [(name, dg)]
    if tests:
        files.update(test_files(name, ns, uses, toolset, dg, tg, gtest_mode=gtest_mode, gtest_guid=gtest_guid))
        projects.append((name + 'Test', tg))
    return files, projects


def edit_sln(path, projects):
    raw = open(path, 'rb').read()
    bom = raw.startswith(BOM)
    text = raw[3:].decode('utf-8') if bom else raw.decode('utf-8')
    nl = '\r\n' if '\r\n' in text else '\n'
    lines = text.replace('\r\n', '\n').split('\n')

    # ソリューション構成 (x64 だけ対応)
    cfgs, in_sec = [], False
    for ln in lines:
        if 'GlobalSection(SolutionConfigurationPlatforms)' in ln:
            in_sec = True
            continue
        if in_sec and 'EndGlobalSection' in ln:
            break
        m = re.match(r'\s*(\w+)\|x64\s*=', ln) if in_sec else None
        if m:
            cfgs.append(m.group(1))
    if not cfgs:
        print('WARNING: ソリューションに x64 の構成がない。プロジェクトは追加するが、構成の対応付けは、Visual Studio で行うこと')

    def idx(pred, start=0):
        for i in range(start, len(lines)):
            if pred(lines[i]):
                return i
        return -1

    g = idx(lambda s: s.strip() == 'Global')
    if g < 0:
        die('.sln に Global セクションがない (想定外の形式)')
    proj_lines = []
    for n, gd in projects:
        proj_lines += [f'Project("{CPP_TYPE}") = "{n}", "{n}\\{n}.vcxproj", "{gd}"', 'EndProject']
    lines[g:g] = proj_lines

    map_lines = []
    for n, gd in projects:
        for c in cfgs:
            map_lines += [f'\t\t{gd}.{c}|x64.ActiveCfg = {c}|x64', f'\t\t{gd}.{c}|x64.Build.0 = {c}|x64']
    if map_lines:
        s = idx(lambda x: 'GlobalSection(ProjectConfigurationPlatforms)' in x)
        if s >= 0:
            e = idx(lambda x: 'EndGlobalSection' in x, s)
            lines[e:e] = map_lines
        else:
            at = idx(lambda x: 'GlobalSection(SolutionProperties)' in x)
            if at < 0:
                at = idx(lambda x: x.strip() == 'EndGlobal')
            lines[at:at] = ['\tGlobalSection(ProjectConfigurationPlatforms) = postSolution'] + map_lines + ['\tEndGlobalSection']
    out = nl.join(lines).encode('utf-8')
    open(path, 'wb').write((BOM if bom else b'') + out)


def edit_slnx(path, projects):
    raw = open(path, 'rb').read()
    bom = raw.startswith(BOM)
    text = raw[3:].decode('utf-8') if bom else raw.decode('utf-8')
    nl = '\r\n' if '\r\n' in text else '\n'
    end = text.rfind('</Solution>')
    if end < 0:
        die('.slnx に </Solution> がない (想定外の形式)')
    add = ''.join(f'  <Project Path="{n}/{n}.vcxproj" Id="{gd.strip("{}").lower()}" />{nl}' for n, gd in projects)
    # 直前の行頭に挿入する
    line_start = text.rfind('\n', 0, end) + 1
    text = text[:line_start] + add + text[line_start:]
    open(path, 'wb').write((BOM if bom else b'') + text.encode('utf-8'))


def write_files(sln_dir, files):
    """BOM 付き UTF-8、CRLF で書く (Visual Studio の既定に合わせる)。"""
    for rel, content in files.items():
        p = os.path.join(sln_dir, *rel.split('/'))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'wb') as f:
            f.write(BOM + to_crlf(content).encode('utf-8'))


def register(sln, projects):
    (edit_slnx if sln.lower().endswith('.slnx') else edit_sln)(sln, projects)


def gtest_package_dir(sln_dir):
    return os.path.join(sln_dir, 'packages', f'{GTEST_ID}.{GTEST_VER}')


def _is_gtest_package(d):
    return os.path.isfile(os.path.join(d, 'build', 'native', f'{GTEST_ID}.targets'))


def ensure_gtest(sln_dir, gtest_from=None, dry=False):
    """packages\\ に GoogleTest (NuGet) がなければ、既存のコピーを探して、コピーする (ネットワークは使わない)。
    戻り値: 'present' / 'copied from <src>' / 'would copy from <src>' / 'missing'"""
    dest = gtest_package_dir(sln_dir)
    if _is_gtest_package(dest):
        return 'present'
    cands = []
    if gtest_from:
        g = os.path.abspath(gtest_from)
        cands += [g, os.path.join(g, f'{GTEST_ID}.{GTEST_VER}')]
    parent = os.path.dirname(sln_dir)
    cands += sorted(glob.glob(os.path.join(parent, '*', 'packages', f'{GTEST_ID}.{GTEST_VER}')))
    for c in cands:
        if os.path.abspath(c) != os.path.abspath(dest) and _is_gtest_package(c):
            if dry:
                return f'would copy from {c}'
            shutil.copytree(c, dest)
            return f'copied from {c}'
    return 'missing'


def protect_main_exes(sln_dir, dry=False):
    """exe で、名前が Test / Tests で終わるメインプロジェクト (GoogleTest を使わないもの) に、<TargetName> を足す。
    ウォッチャーは *Test.exe をテストとして実行するので、アプリの exe が起動されるのを防ぐ。パッチした名前の一覧を返す。"""
    patched = []
    for path in sorted(glob.glob(os.path.join(sln_dir, '*', '*.vcxproj'))):
        name = os.path.splitext(os.path.basename(path))[0]
        if not re.search(r'(Test|Tests)$', name):
            continue
        raw = open(path, 'rb').read()
        bom = raw.startswith(BOM)
        text = (raw[3:] if bom else raw).decode('utf-8')
        low = text.lower()
        if 'googletest' in low or 'gtest' in low or '<TargetName>' in text:
            continue
        if '<ConfigurationType>Application</ConfigurationType>' not in text:
            continue
        nl = '\r\n' if '\r\n' in text else '\n'
        block = nl.join(['  <PropertyGroup>', '    <TargetName>$(ProjectName)_Main</TargetName>', '  </PropertyGroup>']) + nl
        m = re.search(r'^[ \t]*<ItemDefinitionGroup', text, re.M) or \
            re.search(r'^[ \t]*<Import Project="\$\(VCTargetsPath\)\\Microsoft\.Cpp\.targets"', text, re.M)
        if not m:
            continue
        if not dry:
            text = text[:m.start()] + block + text[m.start():]
            open(path, 'wb').write((BOM if bom else b'') + text.encode('utf-8'))
        patched.append(name)
    return patched


def read_dll_info(sln_dir, name):
    """既存の DLL プロジェクト <name> から、GUID・参照先 (--uses)・名前空間・ビルド確認用の関数の有無を読む。"""
    vp = os.path.join(sln_dir, name, f'{name}.vcxproj')
    if not os.path.isfile(vp):
        die(f'DLL のプロジェクトがない: {name}/{name}.vcxproj')
    text = open(vp, encoding='utf-8-sig').read()
    if '<ConfigurationType>DynamicLibrary</ConfigurationType>' not in text and \
            '<ConfigurationType>StaticLibrary</ConfigurationType>' not in text:
        die(f'{name} は DLL / 静的ライブラリ (DynamicLibrary / StaticLibrary) ではない')
    m = re.search(r'<ProjectGuid>(\{[0-9A-Fa-f-]+\})</ProjectGuid>', text)
    if not m:
        die(f'{name}.vcxproj に ProjectGuid がない')
    uses = [u for u in dict.fromkeys(re.findall(r'\$\(ProjectDir\)\.\.\\(\w+)', text)) if u != name]
    ns, has_info = None, False
    hp = os.path.join(sln_dir, name, f'{name}ModuleInfo.h')
    if os.path.isfile(hp):
        ht = open(hp, encoding='utf-8-sig').read()
        mn = re.search(r'namespace\s+(\w+)', ht)
        if mn and f'{name}ModuleName' in ht:
            ns, has_info = mn.group(1), True
    return {'guid': m.group(1).upper(), 'uses': uses, 'ns': ns, 'has_info': has_info}


def gstat_for(sln_dir, gmode, gtest_from):
    return ensure_gtest(sln_dir, gtest_from, dry=True) if gmode == 'nuget' else \
        ('present' if gtest_source_present(sln_dir) else 'to-fetch')


def describe_gtest(mode, status):
    """dry-run 用の、GoogleTest の説明 (1 行)"""
    if mode == 'source':
        return f'GTEST_MODE: source (ThirdParty/googletest をビルド)  GTEST_SOURCE: {status}' + \
            ('' if status == 'present' else ' (ウォッチャーで取得: gtest_once.sh)')
    return f'GTEST_MODE: nuget  GTEST_PACKAGE: {status}'


def finish_gtest(sln_dir, mode, gtest_from):
    """プロジェクトを書いたあとの、GoogleTest の仕上げ (nuget: パッケージのコピー / source: 取得が必要かの案内)。出力する文字列を返す。"""
    if mode == 'source':
        if gtest_source_present(sln_dir):
            return 'GTEST_MODE: source\nGTEST_SOURCE: present'
        return ('GTEST_MODE: source\nGTEST_SOURCE: to-fetch (ウォッチャーを起動して、gtest_once.sh で、GoogleTest のソースを取得する。'
                'または、ThirdParty/googletest/{include,src} に、手でコピーする)')
    st = ensure_gtest(sln_dir, gtest_from)
    return 'GTEST_MODE: nuget\nGTEST_PACKAGE: ' + (st if st != 'missing' else
        'missing (Visual Studio で、ソリューションを開いて、NuGet パッケージを復元する。またはほかの場所の packages\\ を、--gtest-from で指定する)')


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('sln_dir')
    ap.add_argument('name')
    ap.add_argument('--tests', choices=['none', 'gtest'], default='gtest')
    ap.add_argument('--tests-only', action='store_true')
    ap.add_argument('--kind', choices=['dll', 'lib'], default='dll')
    ap.add_argument('--namespace')
    ap.add_argument('--uses', nargs='*', default=None)
    ap.add_argument('--toolset')
    ap.add_argument('--gtest-from')
    ap.add_argument('--gtest', choices=['auto', 'nuget', 'source'], default='auto')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    if not re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', a.name):
        die(f'プロジェクト名が不正 (英数字と _ のみ、先頭は英字か _): {a.name}')
    if a.tests_only and a.tests == 'none':
        die('--tests-only と --tests none は、同時に指定できない')
    sln_dir = os.path.abspath(a.sln_dir)
    if not os.path.isdir(sln_dir):
        die(f'フォルダがない: {sln_dir}')
    sln = find_solution(sln_dir)
    sln_text = open(sln, 'rb').read().decode('utf-8-sig')

    def registered(d):
        return re.search(r'["/\\]' + re.escape(d) + r'\.vcxproj', sln_text) is not None

    test = a.name + 'Test'
    toolset = a.toolset or detect_toolset(sln_dir)

    if a.tests_only:
        info = read_dll_info(sln_dir, a.name)
        if not registered(a.name):
            die(f'{a.name} が、ソリューションに登録されていない')
        if os.path.exists(os.path.join(sln_dir, test)) or registered(test):
            die(f'すでに存在する: {test} (何も書いていない)', 3)
        uses = a.uses if a.uses is not None else info['uses']
        ns = a.namespace or info['ns'] or default_namespace(sln)
        tg = new_guid()
        gmode, gstat = decide_gtest_mode(sln_dir, a.gtest, a.gtest_from)
        gfiles, gprojects, gguid = plan_gtest(sln_dir, gmode, toolset)
        files = test_files(a.name, ns, uses, toolset, info['guid'], tg, baseline_link=info['has_info'],
                           gtest_mode=gmode, gtest_guid=gguid)
        files.update(gfiles)
        projects = [(test, tg)] + gprojects
        if not info['has_info']:
            print(f'NOTE: {a.name}ModuleInfo.h がないので、ベースラインのテストは、DLL を呼ばない (リンクは、確かめられない)')
    else:
        uses = a.uses or []
        for u in uses:
            if not os.path.isdir(os.path.join(sln_dir, u)):
                die(f'--uses のフォルダがない: {u}')
        names = (a.name, test) if a.tests == 'gtest' else (a.name,)
        for d in names:
            if os.path.exists(os.path.join(sln_dir, d)):
                die(f'すでに存在する: {d} (何も書いていない)', 3)
            if registered(d):
                die(f'ソリューションに、すでに登録されている: {d} (何も書いていない)', 3)
        ns = a.namespace or default_namespace(sln)
        gmode, gstat, gfiles, gprojects, gguid = 'nuget', None, {}, [], None
        if a.tests == 'gtest':
            gmode, gstat = decide_gtest_mode(sln_dir, a.gtest, a.gtest_from)
            gfiles, gprojects, gguid = plan_gtest(sln_dir, gmode, toolset)
        files, projects = build_files(a.name, ns, uses, toolset, tests=(a.tests == 'gtest'), kind=a.kind,
                                      gtest_mode=gmode, gtest_guid=gguid)
        files.update(gfiles)
        projects = projects + gprojects

    with_tests = a.tests_only or a.tests == 'gtest'
    if not with_tests:
        gmode = None
    print(f'ソリューション : {os.path.basename(sln)}')
    print(f'名前空間       : {ns}')
    print(f'PlatformToolset: {toolset}')
    print(f'テスト         : {"あり (GoogleTest)" if with_tests else "なし"}')
    for rel in files:
        print(f'  + {rel}')
    print(f'  ~ {os.path.basename(sln)} ({len(projects)} プロジェクトを追加: {", ".join(n for n, _ in projects)})')
    if a.dry_run:
        if with_tests:
            print(describe_gtest(gmode, gstat if not a.tests_only else gstat_for(sln_dir, gmode, a.gtest_from)))
            for n in protect_main_exes(sln_dir, dry=True):
                print(f'MAIN_EXE_TARGETNAME: {n} -> {n}_Main (予定)')
        print('(dry-run: 何も書いていない)')
        return

    write_files(sln_dir, files)
    register(sln, projects)

    if with_tests:
        print(finish_gtest(sln_dir, gmode, a.gtest_from))
        for n in protect_main_exes(sln_dir):
            print(f'MAIN_EXE_TARGETNAME: {n} -> {n}_Main (ウォッチャーが、アプリをテストとして実行しないため)')
    print('完了。')


if __name__ == '__main__':
    main()
