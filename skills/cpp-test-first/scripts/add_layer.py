#!/usr/bin/env python3
"""add_layer.py - ソリューションに、「DLL プロジェクト + 対応するテスト exe (GoogleTest)」を、組で追加する。

Usage: python3 add_layer.py <SLN_DIR> <Name> [--namespace NS] [--uses OTHER ...] [--toolset v145] [--dry-run]

  SLN_DIR      .sln または .slnx があるフォルダ (Claude Code を起動したフォルダ)
  Name         DLL のプロジェクト名 (例: DataLayer)。テストは <Name>Test になる
  --namespace  C++ の名前空間 (既定: ソリューション名の、大文字の頭文字を、小文字にしたもの。例: ThreeLayerSample -> tls)
  --uses       この DLL が、ヘッダ (インターフェース) を参照する、別のプロジェクトのフォルダ名 (複数可)。
               インクルードパスに追加するだけで、リンクはしない (例: ロジック DLL が --uses DataLayer)
  --toolset    PlatformToolset (既定: 既存の .vcxproj から検出。なければ v145)
  --dry-run    何も書かず、行う内容だけを表示する

作るもの (すべて x64 の Debug / Release):
  <Name>/<Name>.vcxproj, <Name>Api.h (公開マクロ), <Name>ModuleInfo.h/.cpp (ビルド確認用の、小さな公開関数)
  <Name>Test/<Name>Test.vcxproj, packages.config (GoogleTest の NuGet), Test<Name>ModuleInfo.cpp (ベースライン用の、1 件のテスト)
  ソリューション (.sln / .slnx) に、2 プロジェクトを追加する。

終了コード: 0 成功 / 2 引数・ソリューションの問題 / 3 すでに存在する (何も書かない)
規約は、同梱の DLL-LAYOUT.md を参照。
"""
import argparse
import os
import re
import sys
import uuid

BOM = b'\xef\xbb\xbf'
CPP_TYPE = '{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}'
GTEST_ID = 'Microsoft.googletest.v140.windesktop.msvcstl.static.rt-dyn'
GTEST_VER = '1.8.1.8'
GTEST_TARGETS = f'..\\packages\\{GTEST_ID}.{GTEST_VER}\\build\\native\\{GTEST_ID}.targets'


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


def vcxproj(name, guid, cfgtype, toolset, items, refs, incs, defs, subsystem, tail=''):
    sub = f'\n      <SubSystem>{subsystem}</SubSystem>'
    inc = ''
    if incs:
        inc = '\n      <AdditionalIncludeDirectories>' + ';'.join(incs) + ';%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>'

    def cfg(c, debug):
        return f'''  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='{c}|x64'" Label="Configuration">
    <ConfigurationType>{cfgtype}</ConfigurationType>
    <UseDebugLibraries>{'true' if debug else 'false'}</UseDebugLibraries>
    <PlatformToolset>{toolset}</PlatformToolset>
    <CharacterSet>Unicode</CharacterSet>
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
        return f'''  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='{c}|x64'">
    <ClCompile>
      <WarningLevel>Level3</WarningLevel>
      <SDLCheck>true</SDLCheck>
      <ConformanceMode>true</ConformanceMode>
      <LanguageStandard>stdcpp20</LanguageStandard>
      <PrecompiledHeader>NotUsing</PrecompiledHeader>
      <PreprocessorDefinitions>{d}%(PreprocessorDefinitions)</PreprocessorDefinitions>{opt}{inc}
    </ClCompile>
    <Link>{sub}
      <GenerateDebugInformation>true</GenerateDebugInformation>{lnk}
    </Link>
  </ItemDefinitionGroup>
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
    cl = [i for i in items if i.endswith('.cpp')]
    out += '  <ItemGroup>\n' + ''.join(f'    <ClInclude Include="{h}" />\n' for h in hd) + '  </ItemGroup>\n'
    out += '  <ItemGroup>\n' + ''.join(f'    <ClCompile Include="{c}" />\n' for c in cl) + '  </ItemGroup>\n'
    if 'packages.config' in items:
        out += '  <ItemGroup>\n    <None Include="packages.config" />\n  </ItemGroup>\n'
    if refs:
        out += '  <ItemGroup>\n' + ''.join(
            f'    <ProjectReference Include="..\\{n}\\{n}.vcxproj">\n      <Project>{g}</Project>\n    </ProjectReference>\n'
            for n, g in refs) + '  </ItemGroup>\n'
    out += '  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.targets" />\n' + tail + '</Project>\n'
    return out


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


def build_files(name, ns, uses, toolset):
    up = name.upper()
    dg, tg = new_guid(), new_guid()
    test = name + 'Test'
    use_inc = [f'$(ProjectDir)..\\{u}' for u in uses]
    api = f'{name}Api.h'
    info_h = f'{name}ModuleInfo.h'
    info_cpp = f'{name}ModuleInfo.cpp'
    test_cpp = f'Test{name}ModuleInfo.cpp'
    func = f'{name}ModuleName'

    files = {}
    files[f'{name}/{name}.vcxproj'] = vcxproj(
        name, dg, 'DynamicLibrary', toolset, [api, info_h, info_cpp], [], use_inc,
        f'{up}_EXPORTS;_WINDOWS;_USRDLL;', 'Windows')
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
    files[f'{test}/{test}.vcxproj'] = vcxproj(
        test, tg, 'Application', toolset, [test_cpp, 'packages.config'], [(name, dg)],
        [f'$(ProjectDir)..\\{name}'] + use_inc, '_CONSOLE;', 'Console', tail=nuget_tail())
    files[f'{test}/packages.config'] = f'''<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="{GTEST_ID}" version="{GTEST_VER}" targetFramework="native" />
</packages>
'''
    files[f'{test}/{test_cpp}'] = f'''#include <gtest/gtest.h>
#include "{info_h}"

// ベースライン (ビルド・リンク・実行ができることの確認)。本物のテストが増えたら、削除してよい。
TEST({name}ModuleInfoTest, ModuleName_ReturnsProjectName)
{{
    EXPECT_STREQ("{name}", {ns}::{func}());
}}
'''
    return files, [(name, dg), (test, tg)]


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


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('sln_dir')
    ap.add_argument('name')
    ap.add_argument('--namespace')
    ap.add_argument('--uses', nargs='*', default=[])
    ap.add_argument('--toolset')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    if not re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', a.name):
        die(f'プロジェクト名が不正 (英数字と _ のみ、先頭は英字か _): {a.name}')
    sln_dir = os.path.abspath(a.sln_dir)
    if not os.path.isdir(sln_dir):
        die(f'フォルダがない: {sln_dir}')
    sln = find_solution(sln_dir)
    for u in a.uses:
        if not os.path.isdir(os.path.join(sln_dir, u)):
            die(f'--uses のフォルダがない: {u}')
    for d in (a.name, a.name + 'Test'):
        if os.path.exists(os.path.join(sln_dir, d)):
            die(f'すでに存在する: {d} (何も書いていない)', 3)
    sln_text = open(sln, 'rb').read().decode('utf-8-sig')
    for d in (a.name, a.name + 'Test'):
        if re.search(r'["/\\]' + re.escape(d) + r'\.vcxproj', sln_text):
            die(f'ソリューションに、すでに登録されている: {d} (何も書いていない)', 3)

    ns = a.namespace or default_namespace(sln)
    toolset = a.toolset or detect_toolset(sln_dir)
    files, projects = build_files(a.name, ns, a.uses, toolset)

    print(f'ソリューション : {os.path.basename(sln)}')
    print(f'名前空間       : {ns}')
    print(f'PlatformToolset: {toolset}')
    for rel in files:
        print(f'  + {rel}')
    print(f'  ~ {os.path.basename(sln)} (2 プロジェクトを追加: {", ".join(n for n, _ in projects)})')
    if a.dry_run:
        print('(dry-run: 何も書いていない)')
        return

    for rel, content in files.items():
        p = os.path.join(sln_dir, *rel.split('/'))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'wb') as f:
            f.write(BOM + to_crlf(content).encode('utf-8'))
    (edit_slnx if sln.lower().endswith('.slnx') else edit_sln)(sln, projects)

    pkg = os.path.join(sln_dir, 'packages', f'{GTEST_ID}.{GTEST_VER}', 'build', 'native', f'{GTEST_ID}.targets')
    print('GTEST_PACKAGE: ' + ('present' if os.path.isfile(pkg) else
          'missing (Visual Studio で、ソリューションを開いて、NuGet パッケージを復元する。またはほかの場所の packages\\ をコピーする)'))
    print('完了。')


if __name__ == '__main__':
    main()
