#!/usr/bin/env python3
"""add_layer.py - ソリューションに、「DLL プロジェクト」と、(必要なら) 「対応するテスト exe (GoogleTest)」を追加する。

Usage: python3 add_layer.py <SLN_DIR> <Name> [--kind dll|lib|mfc-ext-dll|mfc-std-dll] [--tests none|gtest] [--tests-only] [--namespace NS] [--uses OTHER ...]
                            [--toolset v145] [--dry-run]

  SLN_DIR      .sln または .slnx があるフォルダ (Claude Code を起動したフォルダ)
  Name         DLL のプロジェクト名 (例: DataLayer)。テストは <Name>Test になる
  --tests      gtest (既定): DLL + テスト exe を作る。none: DLL だけを作る (テスト・GoogleTest は作らない)
  --kind       dll (既定) / lib / mfc-ext-dll: DLL を作るか、静的ライブラリ (公開マクロなし。テスト exe や UI に、リンクで取り込まれる) を作るか、
               MFC 拡張 DLL (UseOfMfc=Dynamic、_AFXEXT、pch.h、dllmain.cpp の定型コード。MFC の型・シリアライズを持ち込む層のとき。メインが MFC のとき)か、
               MFC 標準 DLL (mfc-std-dll。UseOfMfc=Dynamic、_USRDLL、pch.h、CWinApp 派生の theApp。エクスポート関数の先頭に AFX_MANAGE_STATE。どの exe からでも使える)か
  --tests-only すでにある DLL / 静的ライブラリ <Name> に、テスト exe だけを足す (DLL の名前空間・参照は、既存のファイルから読む)
  --gtest      auto (既定) / vcpkg / source: GoogleTest の入れ方 (旧 NuGet 方式 (nuget) は、v2.31.0 で廃止)。
               auto: 既存の gtest プロジェクト → source / それ以外 → vcpkg。
               vcpkg: vcpkg.json (ソリューション直下) に gtest を入れ、テスト exe に main.cpp (自前の main()) を置く。x64-windows-static-md。
                      builtin-baseline の固定と gtest の取得は、ウォッチャー経由 (package_once.sh 'vcpkg baseline' 'vcpkg install')
               source: ThirdParty/googletest のソースを、静的ライブラリ gtest としてビルドする (vcpkg が使えないとき)
               (packages\\ に旧 NuGet 方式のテストがあるソリューションは、そのまま使える。新しいテストは vcpkg 方式で作り、注意の行 (NOTE) を出す)
  --namespace  C++ の名前空間 (既定: ソリューション名の、大文字の頭文字を、小文字にしたもの。例: ThreeLayerSample -> tls)
  --uses       この DLL が、ヘッダ (インターフェース) を参照する、別のプロジェクトのフォルダ名 (複数可)。
               インクルードパスに追加するだけで、リンクはしない (例: ロジック DLL が --uses DataLayer)
  --toolset    PlatformToolset (既定: 既存の .vcxproj から検出。なければ v145)
  --dry-run    何も書かず、行う内容だけを表示する

作るもの (すべて x64 の Debug / Release):
  <Name>/<Name>.vcxproj, <Name>Api.h (公開マクロ), <Name>ModuleInfo.h/.cpp (ビルド確認用の、小さな公開関数)
  <Name>Test/<Name>Test.vcxproj, main.cpp (vcpkg 方式のとき), Test<Name>ModuleInfo.cpp (ベースライン用の、1 件のテスト)
  ソリューション (.sln / .slnx) に、プロジェクトを追加する。
テストを作るとき (--tests gtest):
  - vcpkg 方式: vcpkg.json に gtest を入れ、.gitignore に vcpkg_installed/ を足す (出力: GTEST_VCPKG)。
  - exe のメインプロジェクトの名前が Test / Tests で終わる場合は、<TargetName> を、<名前>_Main にする
    (ウォッチャーが *Test.exe を、テストとして実行するので、アプリが起動されるのを防ぐ)。

終了コード: 0 成功 / 2 引数・ソリューションの問題 / 3 すでに存在する (何も書かない)
規約は、同梱の DLL-LAYOUT.md を参照。
"""
import argparse
import glob
import json
import os
import re
import shutil
import sys
import uuid

BOM = b'\xef\xbb\xbf'
CPP_TYPE = '{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}'
GTEST_ID = 'Microsoft.googletest.v140.windesktop.msvcstl.static.rt-dyn'
GTEST_VER = '1.8.1.8'
VCPKG_TRIPLET = 'x64-windows-static-md'
VCPKG_TRIPLETS = {'x64': 'x64-windows-static-md', 'Win32': 'x86-windows-static-md'}
# プロジェクトのプラットフォーム。.vcxproj の名前は Win32 (ソリューションの .slnx / .sln では x86)。並びは、ウィザードと同じ (Win32、x64)。
PLATFORM_ORDER = ('Win32', 'x64')
_PLATFORMS = ('x64',)


def normalize_platforms(values):
    """['x86', 'x64'] や 'x64,Win32' を、('Win32', 'x64') の形にそろえる (x86 は Win32 の別名)。不正な値は、ValueError。"""
    if isinstance(values, str):
        values = [v for v in re.split(r'[,\s]+', values) if v]
    out = set()
    for v in values:
        key = {'x64': 'x64', 'win32': 'Win32', 'x86': 'Win32'}.get(str(v).strip().lower())
        if key is None:
            raise ValueError(f'プラットフォームは、x64 / Win32 (x86) のどれか: {v}')
        out.add(key)
    if not out:
        raise ValueError('プラットフォームが、空')
    return tuple(p for p in PLATFORM_ORDER if p in out)


def set_platforms(values):
    """これ以降に作る .vcxproj のプラットフォームを決める (1 回の実行の、最初に呼ぶ。既定は x64 だけ)。"""
    global _PLATFORMS
    _PLATFORMS = normalize_platforms(values)
    return _PLATFORMS


def get_platforms():
    return _PLATFORMS


def detect_platforms(sln_dir):
    """すでにあるソリューションの、プラットフォームを、.vcxproj の ProjectConfiguration から読む。読めなければ x64。
    (新しい層・テストを、そのソリューションに、そろえるために使う。複数のプロジェクトのうち、プラットフォームが多いものを採る。)"""
    best = ()
    for root, dirs, files in os.walk(sln_dir):
        dirs[:] = [d for d in dirs if d not in ('packages', 'obj', '.vs', '.git', 'x64', 'x86', 'Win32', 'Debug', 'Release', 'vcpkg_installed', 'ThirdParty')]
        for f in files:
            if not f.endswith('.vcxproj'):
                continue
            try:
                text = open(os.path.join(root, f), encoding='utf-8-sig').read()
            except OSError:
                continue
            found = set(re.findall(r'<Platform>(x64|Win32)</Platform>', text))
            cand = tuple(p for p in PLATFORM_ORDER if p in found)
            if len(cand) > len(best):
                best = cand
    return best or ('x64',)
VCPKG_MAIN_CPP = '''#include <gtest/gtest.h>

// vcpkg の GoogleTest は、gtest_main を自動でリンクしないので、main() をここに書く (出力の「Running main() from ...」の行は出ない)。
int main(int argc, char** argv)
{
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
'''

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
    if ext in ('rc', 'rc2', 'ico', 'bmp', 'cur', 'png'):
        return FILTER_RESOURCE[0]
    return None


GTEST_NUGET_REMOVED = ('--gtest nuget / --gtest-from (旧 NuGet 方式) は、v2.31.0 で廃止した。GoogleTest は、vcpkg (既定。--gtest vcpkg) か、'
                       'source (--gtest source) で入れる。packages\\ に旧方式のテストがあるソリューションは、そのまま使えるが、新しいテストは、vcpkg になる')


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


def vcxproj(name, guid, cfgtype, toolset, items, refs, incs, defs, subsystem, tail='', mfc=False, third_party=False, vcpkg=False, pch=False, mfc_only=False, wizard=False):
    # mfc: MFC のプロジェクト (UseOfMfc=Dynamic。Application なら DPI のマニフェストも)。mfc_only: UseOfMfc=Dynamic だけ (MFC 拡張 DLL を参照するテスト exe)。
    # pch: プリコンパイル済みヘッダー (pch.h) を使う (pch.cpp が Create、dllmain.cpp が NotUsing。MFC 拡張 DLL)。
    # wizard: MFC アプリ (exe) を、Visual Studio のウィザードが作る構成に合わせる (Keyword MFCProj、PCH を Use / pch.cpp を Create、
    #   Midl・ResourceCompile・LinkIncremental・EnableSegmentHeap、Release の WholeProgramOptimization、res\ の Image / None)。mfc=True と一緒に使う。
    pch = pch or wizard
    mfcx = '\n    <UseOfMfc>Dynamic</UseOfMfc>' if (mfc or mfc_only) else ''
    sub = f'\n      <SubSystem>{subsystem}</SubSystem>'
    inc = ''
    if incs:
        inc = '\n      <AdditionalIncludeDirectories>' + ';'.join(incs) + ';%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>'

    plats = get_platforms()

    def cfg(c, debug, plat):
        wpo = '\n    <WholeProgramOptimization>true</WholeProgramOptimization>' if (wizard and not debug) else ''
        return f'''  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='{c}|{plat}'" Label="Configuration">
    <ConfigurationType>{cfgtype}</ConfigurationType>
    <UseDebugLibraries>{'true' if debug else 'false'}</UseDebugLibraries>
    <PlatformToolset>{toolset}</PlatformToolset>{wpo}
    <CharacterSet>Unicode</CharacterSet>{mfcx}
  </PropertyGroup>
'''

    def props(c, plat):
        return f'''  <ImportGroup Label="PropertySheets" Condition="'$(Configuration)|$(Platform)'=='{c}|{plat}'">
    <Import Project="$(UserRootDir)\\Microsoft.Cpp.$(Platform).user.props" Condition="exists('$(UserRootDir)\\Microsoft.Cpp.$(Platform).user.props')" Label="LocalAppDataPlatform" />
  </ImportGroup>
'''

    pch_file = '\n      <PrecompiledHeaderFile>pch.h</PrecompiledHeaderFile>' if pch else ''

    def defs_group(c, debug, plat):
        d = ('WIN32;' if plat == 'Win32' else '') + ('_DEBUG;' if debug else 'NDEBUG;') + defs
        opt = '' if debug else '\n      <FunctionLevelLinking>true</FunctionLevelLinking>\n      <IntrinsicFunctions>true</IntrinsicFunctions>'
        lnk = '' if debug else '\n      <EnableCOMDATFolding>true</EnableCOMDATFolding>\n      <OptimizeReferences>true</OptimizeReferences>'
        # 静的ライブラリは、リンカーを使わない (<Link> は、意味を持たない)
        link_xml = '' if cfgtype == 'StaticLibrary' else f'''    <Link>{sub}
      <GenerateDebugInformation>true</GenerateDebugInformation>{lnk}
    </Link>
'''
        # MFC のアプリは、DPI 認識モード (システム DPI 対応) を、マニフェストツールの設定で、明示する (UI-DPI-002。MFC の既定も、true)
        manifest_xml = '    <Manifest>\n      <EnableDpiAwareness>true</EnableDpiAwareness>\n    </Manifest>\n' if (mfc and cfgtype == 'Application') else ''
        wiz_xml = ''
        if wizard:
            manifest_xml = '    <Manifest>\n      <EnableSegmentHeap>true</EnableSegmentHeap>\n      <EnableDpiAwareness>true</EnableDpiAwareness>\n    </Manifest>\n'
            dd = '_DEBUG;' if debug else 'NDEBUG;'
            wiz_xml = f'''    <Midl>
      <MkTypLibCompatible>false</MkTypLibCompatible>
      <ValidateAllParameters>true</ValidateAllParameters>
      <PreprocessorDefinitions>{dd}%(PreprocessorDefinitions)</PreprocessorDefinitions>
    </Midl>
    <ResourceCompile>
      <Culture>0x0411</Culture>
      <PreprocessorDefinitions>{dd}%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <AdditionalIncludeDirectories>$(IntDir);%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
    </ResourceCompile>
'''
        return f'''  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='{c}|{plat}'">
    <ClCompile>
      <WarningLevel>{'TurnOffAllWarnings' if third_party else 'Level3'}</WarningLevel>
      <SDLCheck>{'false' if third_party else 'true'}</SDLCheck>
      <ConformanceMode>true</ConformanceMode>
      <LanguageStandard>stdcpp20</LanguageStandard>
      <PrecompiledHeader>{'Use' if pch else 'NotUsing'}</PrecompiledHeader>{pch_file}
      <PreprocessorDefinitions>{d}%(PreprocessorDefinitions)</PreprocessorDefinitions>{opt}{inc}
    </ClCompile>
{link_xml}{manifest_xml}{wiz_xml}  </ItemDefinitionGroup>
'''

    out = f'''<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup Label="ProjectConfigurations">
''' + ''.join(f'''    <ProjectConfiguration Include="{c}|{pl}">
      <Configuration>{c}</Configuration>
      <Platform>{pl}</Platform>
    </ProjectConfiguration>
''' for pl in plats for c in ('Debug', 'Release')) + f'''  </ItemGroup>
  <PropertyGroup Label="Globals">
    <VCProjectVersion>17.0</VCProjectVersion>
    <ProjectGuid>{guid}</ProjectGuid>
    <Keyword>{'MFCProj' if wizard else 'Win32Proj'}</Keyword>
    <RootNamespace>{name}</RootNamespace>
    <WindowsTargetPlatformVersion>10.0</WindowsTargetPlatformVersion>
  </PropertyGroup>
''' + (f'''  <PropertyGroup Label="Vcpkg">
    <!-- GoogleTest: ソリューション直下の vcpkg.json の gtest を使う -->
    <VcpkgEnableManifest>true</VcpkgEnableManifest>
''' + ''.join(f'''    <VcpkgTriplet Condition="'$(Platform)'=='{pl}'">{VCPKG_TRIPLETS[pl]}</VcpkgTriplet>
''' for pl in plats) + '''  </PropertyGroup>
''' if vcpkg else '') + '''  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.Default.props" />
''' + ''.join(cfg(c, c == 'Debug', pl) for pl in plats for c in ('Debug', 'Release')) + '''  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.props" />
  <ImportGroup Label="ExtensionSettings">
  </ImportGroup>
  <ImportGroup Label="Shared">
  </ImportGroup>
''' + ''.join(props(c, pl) for pl in plats for c in ('Debug', 'Release')) + '''  <PropertyGroup Label="UserMacros" />
  <PropertyGroup>
    <!-- ウォッチャーが、<ソリューション>\\x64\\<Configuration>\\ の *Test.exe を探す。DLL も同じ場所に出す (実行時に、exe と同じフォルダが必要)。 -->
    <OutDir>$(SolutionDir)$(Platform)\\$(Configuration)\\</OutDir>
    <IntDir>$(SolutionDir)obj\\$(ProjectName)\\$(Platform)\\$(Configuration)\\</IntDir>
  </PropertyGroup>
''' + ''.join(
        ''.join(f'''  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='{c}|{pl}'">
    <LinkIncremental>{'true' if c == 'Debug' else 'false'}</LinkIncremental>
  </PropertyGroup>
''' for c in ('Debug', 'Release') if wizard) + ''.join(defs_group(c, c == 'Debug', pl) for c in ('Debug', 'Release'))
        for pl in plats)
    hd = [i for i in items if i.endswith('.h')]
    cl = [i for i in items if i.endswith(('.cpp', '.cc', '.cxx', '.c'))]
    rc = [i for i in items if i.endswith('.rc')]
    out += '  <ItemGroup>\n' + ''.join(f'    <ClInclude Include="{h}" />\n' for h in hd) + '  </ItemGroup>\n'
    def cl_item(c):
        if pch and c in ('pch.cpp', 'dllmain.cpp'):
            return f'    <ClCompile Include="{c}">\n      <PrecompiledHeader>{"Create" if c == "pch.cpp" else "NotUsing"}</PrecompiledHeader>\n    </ClCompile>\n'
        return f'    <ClCompile Include="{c}" />\n'
    out += '  <ItemGroup>\n' + ''.join(cl_item(c) for c in cl) + '  </ItemGroup>\n'
    if rc:
        out += '  <ItemGroup>\n' + ''.join(f'    <ResourceCompile Include="{r}" />\n' for r in rc) + '  </ItemGroup>\n'
    img = [i for i in items if i.lower().endswith(('.ico', '.bmp', '.cur', '.png'))]
    non = [i for i in items if i.lower().endswith('.rc2')]
    if img:
        out += '  <ItemGroup>\n' + ''.join(f'    <Image Include="{i}" />\n' for i in img) + '  </ItemGroup>\n'
    if non:
        out += '  <ItemGroup>\n' + ''.join(f'    <None Include="{i}" />\n' for i in non) + '  </ItemGroup>\n'
    if refs:
        out += '  <ItemGroup>\n' + ''.join(
            f'    <ProjectReference Include="..\\{n}\\{n}.vcxproj">\n      <Project>{g}</Project>\n    </ProjectReference>\n'
            for n, g in refs) + '  </ItemGroup>\n'
    out += '  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.targets" />\n'
    if wizard:
        out += '  <ImportGroup Label="ExtensionTargets">\n  </ImportGroup>\n'
    out += tail + '</Project>\n'
    return out


def vcxproj_filters(items):
    hd = [i for i in items if filter_name_for(i) == FILTER_HEADER[0]]
    cl = [i for i in items if filter_name_for(i) == FILTER_SOURCE[0]]
    rc = [i for i in items if i.lower().endswith('.rc')]
    res_all = [i for i in items if filter_name_for(i) == FILTER_RESOURCE[0]]
    defs = [d for d, present in ((FILTER_SOURCE, cl), (FILTER_HEADER, hd), (FILTER_RESOURCE, res_all)) if present]

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
    out += group('Image', [i for i in items if i.lower().endswith(('.ico', '.bmp', '.cur', '.png'))], FILTER_RESOURCE[0])
    out += group('None', [i for i in items if i.lower().endswith('.rc2')], FILTER_RESOURCE[0])
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


def vcpkg_manifest(sln_dir):
    """<ソリューション>/vcpkg.json を、読む。戻り値: dict / なければ None / 壊れていれば {}"""
    p = os.path.join(sln_dir, 'vcpkg.json')
    if not os.path.isfile(p):
        return None
    try:
        return json.load(open(p, encoding='utf-8-sig'))
    except ValueError:
        return {}


def _dep_name(dep):
    return dep if isinstance(dep, str) else dep.get('name')


def vcpkg_status(sln_dir):
    """vcpkg 方式の状態: 'present' (vcpkg.json に gtest と builtin-baseline がある) / 'no-baseline' (gtest はあるが、baseline がない) /
    'to-add' (vcpkg.json がない、または gtest が入っていない)"""
    m = vcpkg_manifest(sln_dir)
    if not m or 'gtest' not in [_dep_name(d) for d in m.get('dependencies', [])]:
        return 'to-add'
    return 'present' if m.get('builtin-baseline') else 'no-baseline'


def legacy_nuget_gtest(sln_dir):
    """旧 NuGet 方式 (廃止。v2.31.0) の GoogleTest が、packages\\ にあるか。あれば、既存のテストは、そのまま動く (新しいテストは、vcpkg)"""
    return _is_gtest_package(gtest_package_dir(sln_dir))


def legacy_note(sln_dir):
    """旧 NuGet 方式のソリューションに、新しいテストを足すときの注意 (1 行)。なければ、空文字"""
    if not legacy_nuget_gtest(sln_dir):
        return ''
    return ('NOTE: このソリューションには、旧 NuGet 方式 (廃止。packages\\ の GoogleTest 1.8.1.8) のテストがある。既存のテストは、そのまま動く。'
            '新しいテストは、vcpkg 方式で作る (移行したいときは、既存のテストを、vcpkg 方式に作り直す)')


def resolve_gtest_mode(sln_dir, requested='auto'):
    """GoogleTest の入れ方を決める。戻り値: (mode, status)。ファイルは、書かない。
      vcpkg : vcpkg (マニフェスト、x64-windows-static-md)。既定。status は vcpkg_status() の値
      source: ソース (ThirdParty/googletest) を、静的ライブラリ gtest として、ビルドする (vcpkg が使えないとき)。status は present / to-fetch
    (旧 NuGet 方式は、v2.31.0 で廃止。packages\\ に旧方式のテストがあっても、新しいテストは vcpkg)
    auto: 既存の gtest プロジェクト → source / それ以外 → vcpkg"""
    if requested == 'vcpkg':
        return 'vcpkg', vcpkg_status(sln_dir)
    src_status = 'present' if gtest_source_present(sln_dir) else 'to-fetch'
    if requested == 'source':
        return 'source', src_status
    if os.path.isfile(os.path.join(sln_dir, 'gtest', 'gtest.vcxproj')):
        return 'source', src_status
    return 'vcpkg', vcpkg_status(sln_dir)


def decide_gtest_mode(sln_dir, requested):
    return resolve_gtest_mode(sln_dir, requested)


def plan_gtest(sln_dir, mode, toolset):
    """source 方式のとき、gtest プロジェクトを足す必要があるか。戻り値: (files, projects, gtest_guid)"""
    if mode != 'source':
        return {}, [], None
    existing = os.path.join(sln_dir, 'gtest', 'gtest.vcxproj')
    if os.path.isfile(existing):
        return {}, [], read_project_guid(existing)
    g = new_guid()
    return gtest_project_files(toolset, g), [('gtest', g)], g



def dll_files(name, ns, uses, toolset, dg, kind='dll'):
    """DLL (kind='dll') か、静的ライブラリ (kind='lib') の、プロジェクト一式。"""
    if kind == 'lib':
        return lib_files(name, ns, uses, toolset, dg)
    if kind == 'mfc-ext-dll':
        return mfc_ext_files(name, ns, uses, toolset, dg)
    if kind == 'mfc-std-dll':
        return mfc_std_files(name, ns, uses, toolset, dg)
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


MFC_EXT_FRAMEWORK_H = '''#pragma once

#ifndef VC_EXTRALEAN
#define VC_EXTRALEAN            // Windows ヘッダーから使用されていない部分を除外します。
#endif

#include "targetver.h"

#define _ATL_CSTRING_EXPLICIT_CONSTRUCTORS      // 一部の CString コンストラクターは明示的です。

#include <afxwin.h>         // MFC のコアおよび標準コンポーネント
#include <afxext.h>         // MFC の拡張部分
'''

MFC_EXT_TARGETVER_H = '''#pragma once

// SDKDDKVer.h をインクルードすると、利用できる最も上位の Windows プラットフォームが定義されます。
// 以前の Windows プラットフォーム用にビルドする場合は、WinSDKVer.h をインクルードし、
// SDKDDKVer.h をインクルードする前に、サポート対象とするプラットフォームを示すように _WIN32_WINNT マクロを設定します。

#include <SDKDDKVer.h>
'''


def mfc_ext_files(name, ns, uses, toolset, dg):
    """MFC 拡張 DLL のプロジェクト一式 (Visual Studio の「MFC DLL」ウィザード (拡張 DLL) の出力に合わせる。
    UseOfMfc=Dynamic、_AFXEXT (_USRDLL は付けない)、pch.h (pch.cpp が Create、dllmain.cpp が NotUsing)、dllmain.cpp の定型コード)。"""
    up = name.upper()
    use_inc = [f'$(ProjectDir)..\\{u}' for u in uses]
    api = f'{name}Api.h'
    info_h = f'{name}ModuleInfo.h'
    info_cpp = f'{name}ModuleInfo.cpp'
    func = f'{name}ModuleName'
    items = [api, info_h, 'pch.h', 'framework.h', 'targetver.h', info_cpp, 'pch.cpp', 'dllmain.cpp']

    files = {}
    files[f'{name}/{name}.vcxproj'] = vcxproj(
        name, dg, 'DynamicLibrary', toolset, items, [], use_inc,
        f'{up}_EXPORTS;_WINDOWS;_AFXEXT;', 'Windows', mfc=True, pch=True)
    files[f'{name}/{name}.vcxproj.filters'] = vcxproj_filters(items)
    files[f'{name}/{api}'] = f'''#pragma once

// DLL の公開 (エクスポート) マクロ。{name} 自身をビルドするときだけ {up}_EXPORTS が定義される。
// テスト exe や UI から使う関数・値のクラスには、{up}_API を付ける (例: class {up}_API Foo)。
// **CObject 派生クラス (シリアライズ対象など) には、{up}_API ではなく、MFC の AFX_EXT_CLASS を付ける**
// (例: class AFX_EXT_CLASS Foo : public CObject。{name} の中では _AFXEXT により、エクスポートになる)。
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
    files[f'{name}/{info_cpp}'] = f'''#include "pch.h"
#include "{info_h}"

namespace {ns}
{{
    const char* {func}()
    {{
        return "{name}";
    }}
}}
'''
    files[f'{name}/pch.h'] = f'''// pch.h: プリコンパイル済みヘッダー ファイルです。
// ここに一覧表示されているファイルは、ビルド間でいずれかが更新されると、すべてが再コンパイルされます。
// 頻繁に更新するファイルをここに追加しないでください。追加すると、パフォーマンス上の利点がなくなります。
// **このプロジェクトの .cpp は、先頭で #include "pch.h" する (dllmain.cpp と pch.cpp を除き、プリコンパイル済みヘッダーを使うため)。**

#ifndef PCH_H
#define PCH_H

// プリコンパイルするヘッダーをここに追加します
#include "framework.h"

#endif //PCH_H
'''
    files[f'{name}/pch.cpp'] = '''// pch.cpp: プリコンパイル済みヘッダーに対応するソース ファイル

#include "pch.h"

// プリコンパイル済みヘッダーを使用している場合、コンパイルを成功させるにはこのソース ファイルが必要です。
'''
    files[f'{name}/framework.h'] = MFC_EXT_FRAMEWORK_H
    files[f'{name}/targetver.h'] = MFC_EXT_TARGETVER_H
    files[f'{name}/dllmain.cpp'] = f'''// dllmain.cpp : MFC 拡張 DLL の初期化ルーチンを定義します。
//

#include "pch.h"
#include "framework.h"
#include <afxwin.h>
#include <afxdllx.h>

#ifdef _DEBUG
#define new DEBUG_NEW
#endif

static AFX_EXTENSION_MODULE {name}DLL = {{ false, nullptr }};

extern "C" int APIENTRY
DllMain(HINSTANCE hInstance, DWORD dwReason, LPVOID lpReserved)
{{
    UNREFERENCED_PARAMETER(lpReserved);

    if (dwReason == DLL_PROCESS_ATTACH)
    {{
        TRACE0("{name}.DLL を初期化しています。\\n");

        // 拡張 DLL を 1 回だけ初期化します。
        if (!AfxInitExtensionModule({name}DLL, hInstance))
            return 0;

        // この DLL をリソース チェーンへ挿入します。
        // メモ : この拡張 DLL が、MFC アプリケーションではなく、ActiveX コントロールなどの
        //  MFC 標準 DLL によって、暗黙的にリンクされる場合は、次の行を DllMain から削除し、
        //  この拡張 DLL からエクスポートする別の関数の中に配置してください。
        //  その標準 DLL は、その関数を明示的に呼び出して、この拡張 DLL を初期化します。
        //  そうしないと、CDynLinkLibrary オブジェクトが標準 DLL のリソース チェーンへ
        //  アタッチされず、重大な問題になります。

        new CDynLinkLibrary({name}DLL);
    }}
    else if (dwReason == DLL_PROCESS_DETACH)
    {{
        TRACE0("{name}.DLL を終了しています。\\n");

        // デストラクターが呼び出される前にライブラリを終了します
        AfxTermExtensionModule({name}DLL);
    }}
    return 1;   // OK
}}
'''
    return files


def mfc_std_files(name, ns, uses, toolset, dg):
    """MFC 標準 DLL (Regular DLL。共有 MFC) のプロジェクト一式 (Visual Studio の「MFC DLL」ウィザード (標準 DLL) の出力に合わせる。
    UseOfMfc=Dynamic、_USRDLL (_AFXEXT は付けない)、pch.h (pch.cpp が Create)、CWinApp 派生クラスと、グローバルな theApp)。
    エクスポートする関数は、先頭で AFX_MANAGE_STATE(AfxGetStaticModuleState()) を呼ぶ (共有 MFC のとき必須)。"""
    up = name.upper()
    use_inc = [f'$(ProjectDir)..\\{u}' for u in uses]
    api = f'{name}Api.h'
    info_h = f'{name}ModuleInfo.h'
    info_cpp = f'{name}ModuleInfo.cpp'
    func = f'{name}ModuleName'
    app = f'C{name}App'
    items = [api, info_h, f'{name}.h', 'pch.h', 'framework.h', 'targetver.h', info_cpp, f'{name}.cpp', 'pch.cpp']

    files = {}
    files[f'{name}/{name}.vcxproj'] = vcxproj(
        name, dg, 'DynamicLibrary', toolset, items, [], use_inc,
        f'{up}_EXPORTS;_WINDOWS;_USRDLL;', 'Windows', mfc=True, pch=True)
    files[f'{name}/{name}.vcxproj.filters'] = vcxproj_filters(items)
    files[f'{name}/{api}'] = f'''#pragma once

// DLL の公開 (エクスポート) マクロ。{name} 自身をビルドするときだけ {up}_EXPORTS が定義される。
// テスト exe や UI から使う関数・値のクラスには、{up}_API を付ける (例: {up}_API int Foo())。
// **MFC 標準 DLL (共有 MFC) では、エクスポートする関数の先頭で、AFX_MANAGE_STATE(AfxGetStaticModuleState()); を呼ぶ**
// (オブジェクト変数の宣言よりも前。呼ばないと、MFC のリソースやモジュールの状態が、呼び出し元の exe のものになる)。
// **MFC のオブジェクト (CObject 派生、CString など) を、DLL の境界で、受け渡さない** (標準 DLL は、MFC の型を共有しない。それが必要なら、拡張 DLL (mfc-ext-dll))。
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
    files[f'{name}/{info_cpp}'] = f'''#include "pch.h"
#include "{info_h}"

namespace {ns}
{{
    const char* {func}()
    {{
        // 共有 MFC の標準 DLL: エクスポートする関数は、先頭で、これを呼ぶ (オブジェクト変数の宣言よりも前)。
        AFX_MANAGE_STATE(AfxGetStaticModuleState());
        return "{name}";
    }}
}}
'''
    files[f'{name}/{name}.h'] = f'''// {name}.h : {name} DLL のメイン ヘッダー ファイル
//

#pragma once

#ifndef __AFXWIN_H__
	#error "PCH に対してこのファイルをインクルードする前に 'pch.h' をインクルードしてください"
#endif

// {app}
// このクラスの実装に関しては {name}.cpp をご覧ください
//

class {app} : public CWinApp
{{
public:
	{app}();

// オーバーライド
public:
	virtual BOOL InitInstance();

	DECLARE_MESSAGE_MAP()
}};
'''
    files[f'{name}/{name}.cpp'] = f'''// {name}.cpp : MFC 標準 DLL の初期化ルーチンを定義します。
//

#include "pch.h"
#include "framework.h"
#include "{name}.h"

#ifdef _DEBUG
#define new DEBUG_NEW
#endif

// この DLL が MFC DLL に対して動的にリンクされる場合 (共有 MFC)、MFC 内で呼び出される
// この DLL からエクスポートされたどの関数も、関数の最初のステートメントとして
// AFX_MANAGE_STATE(AfxGetStaticModuleState()); を呼ぶこと (オブジェクト変数の宣言よりも前)。
// 詳細については MFC テクニカル ノート 33 および 58 を参照。

// {app}

BEGIN_MESSAGE_MAP({app}, CWinApp)
END_MESSAGE_MAP()


// {app} の構築

{app}::{app}()
{{
	// TODO: この位置に構築用コードを追加してください。
	// ここに InitInstance 中の重要な初期化処理をすべて記述してください。
}}


// 唯一の {app} オブジェクト

{app} theApp;


// {app} の初期化

BOOL {app}::InitInstance()
{{
	CWinApp::InitInstance();

	return TRUE;
}}
'''
    files[f'{name}/pch.h'] = f'''// pch.h: プリコンパイル済みヘッダー ファイルです。
// ここに一覧表示されているファイルは、ビルド間でいずれかが更新されると、すべてが再コンパイルされます。
// 頻繁に更新するファイルをここに追加しないでください。追加すると、パフォーマンス上の利点がなくなります。
// **このプロジェクトの .cpp は、先頭で #include "pch.h" する (pch.cpp を含め、すべて、プリコンパイル済みヘッダーを使うため)。**

#ifndef PCH_H
#define PCH_H

// プリコンパイルするヘッダーをここに追加します
#include "framework.h"

#endif //PCH_H
'''
    files[f'{name}/pch.cpp'] = '''// pch.cpp: プリコンパイル済みヘッダーに対応するソース ファイル

#include "pch.h"

// プリコンパイル済みヘッダーを使用している場合、コンパイルを成功させるにはこのソース ファイルが必要です。
'''
    files[f'{name}/framework.h'] = MFC_EXT_FRAMEWORK_H
    files[f'{name}/targetver.h'] = MFC_EXT_TARGETVER_H
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


def test_files(name, ns, uses, toolset, dg, tg, baseline_link=True, gtest_mode='vcpkg', gtest_guid=None, mfc_ext=False):
    # mfc_ext: テスト対象が MFC 拡張 DLL のとき、テスト exe も、同じ共有 MFC ランタイム (UseOfMfc=Dynamic) にリンクする
    test = name + 'Test'
    use_inc = [f'$(ProjectDir)..\\{u}' for u in uses]
    info_h = f'{name}ModuleInfo.h'
    test_cpp = f'Test{name}ModuleInfo.cpp'
    func = f'{name}ModuleName'

    files = {}
    if gtest_mode == 'vcpkg':
        # vcpkg の GoogleTest (マニフェスト: ソリューション直下の vcpkg.json)。gtest_main は自動でリンクされないので、main.cpp を置く
        files[f'{test}/{test}.vcxproj'] = vcxproj(
            test, tg, 'Application', toolset, [test_cpp, 'main.cpp'], [(name, dg)],
            [f'$(ProjectDir)..\\{name}'] + use_inc, '_CONSOLE;', 'Console', vcpkg=True, mfc_only=mfc_ext)
        files[f'{test}/main.cpp'] = VCPKG_MAIN_CPP
    elif gtest_mode == 'source':
        # ソースから、ソリューション内でビルドした静的ライブラリ (gtest) を、プロジェクト参照でリンクする (NuGet 不要)
        files[f'{test}/{test}.vcxproj'] = vcxproj(
            test, tg, 'Application', toolset, [test_cpp], [(name, dg), ('gtest', gtest_guid)],
            [f'$(ProjectDir)..\\{name}'] + use_inc + [GTEST_SRC_INCLUDE], '_CONSOLE;', 'Console', mfc_only=mfc_ext)
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
    files[f'{test}/{test}.vcxproj.filters'] = vcxproj_filters([test_cpp, 'main.cpp'] if gtest_mode == 'vcpkg' else [test_cpp])
    return files


def build_files(name, ns, uses, toolset, tests=True, kind='dll', gtest_mode='vcpkg', gtest_guid=None):
    dg, tg = new_guid(), new_guid()
    files = dll_files(name, ns, uses, toolset, dg, kind)
    projects = [(name, dg)]
    if tests:
        files.update(test_files(name, ns, uses, toolset, dg, tg, gtest_mode=gtest_mode, gtest_guid=gtest_guid, mfc_ext=(kind == 'mfc-ext-dll')))
        projects.append((name + 'Test', tg))
    return files, projects


def edit_sln(path, projects):
    raw = open(path, 'rb').read()
    bom = raw.startswith(BOM)
    text = raw[3:].decode('utf-8') if bom else raw.decode('utf-8')
    nl = '\r\n' if '\r\n' in text else '\n'
    lines = text.replace('\r\n', '\n').split('\n')

    # ソリューション構成 (x64 と x86。.sln の x86 は、プロジェクトの Win32 に対応づける)。(構成, ソリューションのプラットフォーム, プロジェクトのプラットフォーム)
    cfgs, in_sec = [], False
    for ln in lines:
        if 'GlobalSection(SolutionConfigurationPlatforms)' in ln:
            in_sec = True
            continue
        if in_sec and 'EndGlobalSection' in ln:
            break
        m = re.match(r'\s*(\w+)\|(x64|x86|Win32)\s*=', ln) if in_sec else None
        if m:
            pj = 'x64' if m.group(2) == 'x64' else 'Win32'
            if pj in get_platforms():
                cfgs.append((m.group(1), m.group(2), pj))
    if not cfgs:
        print('WARNING: ソリューションに、対応するプラットフォーム (x64 / x86) の構成がない。プロジェクトは追加するが、構成の対応付けは、Visual Studio で行うこと')

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
        for c, sp, pj in cfgs:
            map_lines += [f'\t\t{gd}.{c}|{sp}.ActiveCfg = {c}|{pj}', f'\t\t{gd}.{c}|{sp}.Build.0 = {c}|{pj}']
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


def protect_main_exes(sln_dir, dry=False):
    """exe で、名前が Test / Tests で終わるメインプロジェクト (GoogleTest (NuGet / ソース / vcpkg のどれでも) を使わないもの) に、<TargetName> を足す。
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
    return {'guid': m.group(1).upper(), 'uses': uses, 'ns': ns, 'has_info': has_info,
            'mfc_ext': '_AFXEXT' in text}   # MFC 拡張 DLL (テスト exe も UseOfMfc=Dynamic にする)


def gstat_for(sln_dir, gmode):
    if gmode == 'vcpkg':
        return vcpkg_status(sln_dir)
    return 'present' if gtest_source_present(sln_dir) else 'to-fetch'


VCPKG_NEXT = ("ウォッチャーを起動して、package_once.sh <dir> --timeout 1800 'vcpkg baseline' 'vcpkg install' を実行する "
              "(builtin-baseline の固定と、gtest の取得。初回は、数十秒から数分)")


def describe_gtest(mode, status):
    """dry-run 用の、GoogleTest の説明 (1 行)"""
    if mode == 'vcpkg':
        return f'GTEST_MODE: vcpkg ({VCPKG_TRIPLET})  GTEST_VCPKG: {status}' + \
            ('' if status == 'present' else ' (vcpkg.json を作る / 更新する。baseline と install は、ウォッチャーで)')
    return f'GTEST_MODE: source (ThirdParty/googletest をビルド)  GTEST_SOURCE: {status}' + \
        ('' if status == 'present' else ' (ウォッチャーで取得: gtest_once.sh)')


def ensure_vcpkg_manifest(sln_dir):
    """vcpkg.json に gtest を入れる (なければ作る)。.gitignore に vcpkg_installed/ を足す。ネットワークは使わない。"""
    p = os.path.join(sln_dir, 'vcpkg.json')
    m = vcpkg_manifest(sln_dir)
    if m == {}:
        die('vcpkg.json が、JSON として読めない: ' + p)
    if m is None:
        name = re.sub(r'[^a-z0-9-]+', '-', os.path.basename(sln_dir).lower()).strip('-') or 'app'
        m = {'$schema': 'https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json',
             'name': name, 'version': '0.1.0', 'dependencies': []}
    deps = m.setdefault('dependencies', [])
    if 'gtest' not in [_dep_name(d) for d in deps]:
        deps.append('gtest')
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(m, f, indent=2, ensure_ascii=False)
        f.write('\n')
    gi = os.path.join(sln_dir, '.gitignore')
    text = open(gi, encoding='utf-8').read() if os.path.isfile(gi) else ''
    if 'vcpkg_installed/' not in text:
        with open(gi, 'a', encoding='utf-8', newline='\n') as f:
            f.write(('' if text == '' or text.endswith('\n') else '\n') + 'vcpkg_installed/\n')


def finish_gtest(sln_dir, mode):
    """プロジェクトを書いたあとの、GoogleTest の仕上げ (vcpkg: vcpkg.json に gtest を入れる / source: 取得が必要かの案内)。出力する文字列を返す。
    旧 NuGet 方式のテストが残るソリューションには、注意の行を足す。"""
    note = legacy_note(sln_dir)
    tail = ('\n' + note) if note else ''
    if mode == 'vcpkg':
        ensure_vcpkg_manifest(sln_dir)
        after = vcpkg_status(sln_dir)
        if after == 'present':
            return 'GTEST_MODE: vcpkg\nGTEST_VCPKG: present' + tail
        return f'GTEST_MODE: vcpkg\nGTEST_VCPKG: no-baseline ({VCPKG_NEXT})' + tail
    if gtest_source_present(sln_dir):
        return 'GTEST_MODE: source\nGTEST_SOURCE: present' + tail
    return ('GTEST_MODE: source\nGTEST_SOURCE: to-fetch (ウォッチャーを起動して、gtest_once.sh で、GoogleTest のソースを取得する。'
            'または、ThirdParty/googletest/{include,src} に、手でコピーする)' + tail)


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('sln_dir')
    ap.add_argument('name')
    ap.add_argument('--tests', choices=['none', 'gtest'], default='gtest')
    ap.add_argument('--tests-only', action='store_true')
    ap.add_argument('--kind', choices=['dll', 'lib', 'mfc-ext-dll', 'mfc-std-dll'], default='dll')
    ap.add_argument('--namespace')
    ap.add_argument('--uses', nargs='*', default=None)
    ap.add_argument('--toolset')
    ap.add_argument('--gtest-from')
    ap.add_argument('--gtest', choices=['auto', 'vcpkg', 'source', 'nuget'], default='auto')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    if a.gtest == 'nuget' or a.gtest_from:
        die(GTEST_NUGET_REMOVED)

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
    set_platforms(detect_platforms(sln_dir))   # 新しい層・テストは、このソリューションのプラットフォームに、そろえる

    if a.tests_only:
        info = read_dll_info(sln_dir, a.name)
        if not registered(a.name):
            die(f'{a.name} が、ソリューションに登録されていない')
        if os.path.exists(os.path.join(sln_dir, test)) or registered(test):
            die(f'すでに存在する: {test} (何も書いていない)', 3)
        uses = a.uses if a.uses is not None else info['uses']
        ns = a.namespace or info['ns'] or default_namespace(sln)
        tg = new_guid()
        gmode, gstat = decide_gtest_mode(sln_dir, a.gtest)
        gfiles, gprojects, gguid = plan_gtest(sln_dir, gmode, toolset)
        files = test_files(a.name, ns, uses, toolset, info['guid'], tg, baseline_link=info['has_info'],
                           gtest_mode=gmode, gtest_guid=gguid, mfc_ext=info['mfc_ext'])
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
        gmode, gstat, gfiles, gprojects, gguid = 'vcpkg', None, {}, [], None
        if a.tests == 'gtest':
            gmode, gstat = decide_gtest_mode(sln_dir, a.gtest)
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
            print(describe_gtest(gmode, gstat if not a.tests_only else gstat_for(sln_dir, gmode)))
            for n in protect_main_exes(sln_dir, dry=True):
                print(f'MAIN_EXE_TARGETNAME: {n} -> {n}_Main (予定)')
        print('(dry-run: 何も書いていない)')
        return

    write_files(sln_dir, files)
    register(sln, projects)

    if with_tests:
        print(finish_gtest(sln_dir, gmode))
        for n in protect_main_exes(sln_dir):
            print(f'MAIN_EXE_TARGETNAME: {n} -> {n}_Main (ウォッチャーが、アプリをテストとして実行しないため)')
    print('完了。')


if __name__ == '__main__':
    main()
