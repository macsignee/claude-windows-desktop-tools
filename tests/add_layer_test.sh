#!/usr/bin/env bash
# add_layer_test.sh - skills/cpp-test-first/scripts/add_layer.py を、疑似のソリューション (.sln / .slnx) で検証する (Windows 不要)。
#
# Usage: tests/add_layer_test.sh
# 終了コード: 0 すべて OK / 1 失敗あり
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/skills/cpp-test-first/scripts/add_layer.py"
# 既定の auto は、既存の gtest プロジェクトがなければ vcpkg になる。層・テストの生成の検証は、vcpkg を明示する (旧 NuGet 方式は、v2.31.0 で廃止)
run_al() { python3 "$SCRIPT" "$@" --gtest vcpkg; }
run_al_auto() { python3 "$SCRIPT" "$@"; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/add_layer_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0

ok()  { echo "OK  $1"; }
ng()  { echo "NG  $1"; fail=1; }
check() { # $1=説明 $2...=コマンド
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else ng "$d"; fi
}

make_sln() { # $1=フォルダ。Visual Studio が作る形に近い、MFC アプリ 1 つの .sln (BOM + CRLF)
    mkdir -p "$1/ThreeLayerApp"
    cat > "$1/ThreeLayerApp/ThreeLayerApp.vcxproj" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup Label="Configuration"><PlatformToolset>v145</PlatformToolset></PropertyGroup>
</Project>
EOF
    {
        printf '\xef\xbb\xbf'
        cat <<'EOF'
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.14.37411.7
MinimumVisualStudioVersion = 10.0.40219.1
Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "ThreeLayerApp", "ThreeLayerApp\ThreeLayerApp.vcxproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|x64 = Debug|x64
		Debug|x86 = Debug|x86
		Release|x64 = Release|x64
		Release|x86 = Release|x86
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		{11111111-1111-1111-1111-111111111111}.Debug|x64.ActiveCfg = Debug|x64
		{11111111-1111-1111-1111-111111111111}.Debug|x64.Build.0 = Debug|x64
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
EndGlobal
EOF
    } | sed 's/$/\r/' > "$1/ThreeLayerSample.sln"
}

make_slnx() {
    mkdir -p "$1/ThreeLayerApp"
    cp "$WORK/sln/ThreeLayerApp/ThreeLayerApp.vcxproj" "$1/ThreeLayerApp/"
    cat > "$1/ThreeLayerSample.slnx" <<'EOF'
<Solution>
  <Configurations>
    <Platform Name="x64" />
  </Configurations>
  <Project Path="ThreeLayerApp/ThreeLayerApp.vcxproj" />
</Solution>
EOF
}

make_sln "$WORK/sln"
make_slnx "$WORK/slnx"

echo "== .sln"
S="$WORK/sln"
run_al "$S" DataLayer --dry-run >/dev/null 2>&1 && [ ! -e "$S/DataLayer" ] && ok "dry-run は、何も書かない" || ng "dry-run は、何も書かない"
run_al "$S" DataLayer >"$WORK/out1.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "DataLayer の追加が成功" || { ng "DataLayer の追加が成功 (rc=$rc)"; cat "$WORK/out1.txt"; }
run_al "$S" LogicLayer --uses DataLayer >"$WORK/out2.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "LogicLayer (--uses DataLayer) の追加が成功" || { ng "LogicLayer の追加が成功 (rc=$rc)"; cat "$WORK/out2.txt"; }

for f in DataLayer/DataLayer.vcxproj DataLayer/DataLayer.vcxproj.filters DataLayer/DataLayerApi.h DataLayer/DataLayerModuleInfo.h DataLayer/DataLayerModuleInfo.cpp \
         DataLayerTest/DataLayerTest.vcxproj DataLayerTest/DataLayerTest.vcxproj.filters DataLayerTest/main.cpp DataLayerTest/TestDataLayerModuleInfo.cpp \
         LogicLayer/LogicLayer.vcxproj LogicLayerTest/LogicLayerTest.vcxproj; do
    [ -f "$S/$f" ] && ok "生成: $f" || ng "生成: $f"
done
check ".filters が XML として正しい" python3 -c "
import glob, xml.dom.minidom as m
fs = glob.glob('$S/*/*.vcxproj.filters')
assert len(fs) == 4, fs
[m.parse(f) for f in fs]"
check ".h が「ヘッダー ファイル」フィルターに入る" grep -q '<ClInclude Include="DataLayerApi.h">' "$S/DataLayer/DataLayer.vcxproj.filters"
check "「ヘッダー ファイル」のフィルター定義がある" grep -q '<Filter Include="ヘッダー ファイル">' "$S/DataLayer/DataLayer.vcxproj.filters"
check "Api.h が、C4251 と C4275 の警告を抑止する (インターフェース + Fake を、同じ DLL に置いても、C4275 が出ない) (v2.80.0)" bash -c 'grep -q "disable : 4251" "$1/DataLayer/DataLayerApi.h" && grep -q "disable : 4275" "$1/DataLayer/DataLayerApi.h"' _ "$S"
check ".cpp が「ソース ファイル」フィルターに入る" grep -q '<ClCompile Include="DataLayerModuleInfo.cpp">' "$S/DataLayer/DataLayer.vcxproj.filters"
check "「ソース ファイル」のフィルター定義がある" grep -q '<Filter Include="ソース ファイル">' "$S/DataLayer/DataLayer.vcxproj.filters"
check "main.cpp は、「ソース ファイル」フィルターに入る (vcpkg 方式のテスト)" grep -q '<ClCompile Include="main.cpp">' "$S/DataLayerTest/DataLayerTest.vcxproj.filters"
check ".filters が BOM + CRLF" bash -c "head -c3 '$S/DataLayer/DataLayer.vcxproj.filters' | xxd -p | grep -q efbbbf && grep -q \$'\\r' '$S/DataLayer/DataLayer.vcxproj.filters'"
check "vcxproj が XML として正しい" python3 -c "
import glob, xml.dom.minidom as m
fs = glob.glob('$S/*/*.vcxproj')
assert len(fs) == 5, fs
[m.parse(f) for f in fs]"
check "名前空間が、ソリューション名の頭文字 (tls)" grep -q 'namespace tls' "$S/DataLayer/DataLayerModuleInfo.h"
check "DLL の定義 DATALAYER_EXPORTS" grep -q 'DATALAYER_EXPORTS' "$S/DataLayer/DataLayer.vcxproj"
check "DLL の種類" grep -q '<ConfigurationType>DynamicLibrary</ConfigurationType>' "$S/DataLayer/DataLayer.vcxproj"
check "テストは exe" grep -q '<ConfigurationType>Application</ConfigurationType>' "$S/DataLayerTest/DataLayerTest.vcxproj"
check "テストが DLL をプロジェクト参照" grep -q 'ProjectReference Include="..\\DataLayer\\DataLayer.vcxproj"' "$S/DataLayerTest/DataLayerTest.vcxproj"
check "ロジックのインクルードに、データ層が入る" grep -q 'ProjectDir)..\\DataLayer' "$S/LogicLayer/LogicLayer.vcxproj"
check "ロジックのテストにも、データ層が入る" grep -q 'ProjectDir)..\\DataLayer' "$S/LogicLayerTest/LogicLayerTest.vcxproj"
check "ロジック DLL は、データ DLL を ProjectReference しない" bash -c "! grep -q 'ProjectReference Include=\"..\\\\DataLayer' '$S/LogicLayer/LogicLayer.vcxproj'"
check "出力先がそろっている" grep -q 'OutDir>$(SolutionDir)$(Platform)\\$(Configuration)\\' "$S/LogicLayerTest/LogicLayerTest.vcxproj"
check "既存の toolset (v145) を使う" grep -q '<PlatformToolset>v145</PlatformToolset>' "$S/DataLayer/DataLayer.vcxproj"
check ".cpp が BOM + CRLF" bash -c "head -c3 '$S/DataLayer/DataLayerModuleInfo.cpp' | xxd -p | grep -q efbbbf && grep -q \$'\\r' '$S/DataLayer/DataLayerModuleInfo.cpp'"

check ".sln: BOM が残る" bash -c "head -c3 '$S/ThreeLayerSample.sln' | xxd -p | grep -q efbbbf"
check ".sln: 4 プロジェクトが増えた (計 5)" bash -c "[ \$(grep -c '^Project(' '$S/ThreeLayerSample.sln') -eq 5 ]"
check ".sln: 全行 CRLF のまま" bash -c "[ \$(grep -c -v \$'\\r\$' '$S/ThreeLayerSample.sln') -eq 0 ]"
check ".sln: Debug|x64 の Build.0 がある (DataLayerTest)" bash -c "grep -q 'Debug|x64.Build.0 = Debug|x64' '$S/ThreeLayerSample.sln' && [ \$(grep -c 'Build.0' '$S/ThreeLayerSample.sln') -eq 9 ]"
check ".sln: x86 構成には対応付けない (プロジェクトに Win32 がない)" bash -c "! grep -q 'Debug|x86.ActiveCfg' '$S/ThreeLayerSample.sln'"
check ".sln: 既存の行が壊れていない" grep -q 'EndGlobal' "$S/ThreeLayerSample.sln"

echo "== 重複・不正"
run_al "$S" DataLayer >/dev/null 2>&1; [ $? -eq 3 ] && ok "すでに存在 -> rc 3" || ng "すでに存在 -> rc 3"
run_al "$S" 'bad name' >/dev/null 2>&1; [ $? -eq 2 ] && ok "不正な名前 -> rc 2" || ng "不正な名前 -> rc 2"
run_al "$WORK/none" X >/dev/null 2>&1; [ $? -eq 2 ] && ok "フォルダなし -> rc 2" || ng "フォルダなし -> rc 2"
run_al "$S" Other --uses NoSuch >/dev/null 2>&1; [ $? -eq 2 ] && ok "--uses のフォルダなし -> rc 2" || ng "--uses のフォルダなし -> rc 2"

echo "== .slnx"
X="$WORK/slnx"
run_al "$X" DataLayer >"$WORK/out3.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "slnx への追加が成功" || { ng "slnx への追加が成功 (rc=$rc)"; cat "$WORK/out3.txt"; }
check ".slnx が XML として正しい" python3 -c "import xml.dom.minidom as m; m.parse('$X/ThreeLayerSample.slnx')"
check ".slnx: 2 プロジェクトが追加された" bash -c "[ \$(grep -c '<Project Path=' '$X/ThreeLayerSample.slnx') -eq 3 ]"
check ".slnx: DataLayerTest が登録された" grep -q 'DataLayerTest/DataLayerTest.vcxproj' "$X/ThreeLayerSample.slnx"

echo "== --tests none / --tests-only"
S2="$WORK/sln2"; make_sln "$S2"
run_al "$S2" DataLayer --tests none >/dev/null 2>&1; [ $? -eq 0 ] && ok "--tests none の追加が成功" || ng "--tests none の追加が成功"
check "DLL だけができ、テストはできない" bash -c "[ -f '$S2/DataLayer/DataLayer.vcxproj' ] && [ ! -e '$S2/DataLayerTest' ] && [ ! -e '$S2/packages' ]"
check "--tests none: .sln に、プロジェクトが 1 つ増えた (計 2)" bash -c "[ \$(grep -c '^Project(' '$S2/ThreeLayerSample.sln') -eq 2 ]"
run_al "$S2" DataLayer --tests-only >/dev/null 2>&1; [ $? -eq 0 ] && ok "--tests-only: 既存の DLL にテストを足せる" || ng "--tests-only: 既存の DLL にテストを足せる"
check "--tests-only: DataLayerTest ができ、DLL を参照する" grep -q 'ProjectReference Include="..\\DataLayer\\DataLayer.vcxproj"' "$S2/DataLayerTest/DataLayerTest.vcxproj"
check "--tests-only: .sln のプロジェクトが計 3" bash -c "[ \$(grep -c '^Project(' '$S2/ThreeLayerSample.sln') -eq 3 ]"
run_al "$S2" DataLayer --tests-only >/dev/null 2>&1; [ $? -eq 3 ] && ok "--tests-only: すでにテストがある -> rc 3" || ng "--tests-only: すでにテストがある -> rc 3"
run_al "$S2" DataLayer --tests none --tests-only >/dev/null 2>&1; [ $? -eq 2 ] && ok "--tests none と --tests-only の同時指定 -> rc 2" || ng "--tests none と --tests-only の同時指定 -> rc 2"
run_al "$S2" NoSuchDll --tests-only >/dev/null 2>&1; [ $? -eq 2 ] && ok "--tests-only: DLL がない -> rc 2" || ng "--tests-only: DLL がない -> rc 2"

echo "== --kind lib"
S3="$WORK/sln3"; make_sln "$S3"
run_al "$S3" CoreLib --kind lib >/dev/null 2>&1; [ $? -eq 0 ] && ok "--kind lib (テストあり) の追加が成功" || ng "--kind lib (テストあり) の追加が成功"
check "静的ライブラリで、<Link> がなく、公開マクロもない" bash -c "grep -q StaticLibrary '$S3/CoreLib/CoreLib.vcxproj' && ! grep -q '<Link>' '$S3/CoreLib/CoreLib.vcxproj' && [ ! -e '$S3/CoreLib/CoreLibApi.h' ]"
check "テストが、ライブラリをプロジェクト参照" grep -q 'ProjectReference Include="..\\CoreLib\\CoreLib.vcxproj"' "$S3/CoreLibTest/CoreLibTest.vcxproj"

echo "== GoogleTest のソース方式 (--gtest source)"
S4="$WORK/sln4"; make_sln "$S4"
python3 "$SCRIPT" "$S4" CoreLib --gtest source >"$WORK/out_src.txt" 2>&1; [ $? -eq 0 ] && ok "--gtest source で追加できる" || ng "--gtest source で追加できる"
check "出力: GTEST_MODE: source と to-fetch" bash -c "grep -q 'GTEST_MODE: source' '$WORK/out_src.txt' && grep -q 'to-fetch' '$WORK/out_src.txt'"
check "gtest プロジェクトができる (静的ライブラリ、警告オフ、ThirdParty のソース)" bash -c "grep -q StaticLibrary '$S4/gtest/gtest.vcxproj' && grep -q TurnOffAllWarnings '$S4/gtest/gtest.vcxproj' && grep -q 'ThirdParty\\\\googletest\\\\src\\\\gtest-all.cc' '$S4/gtest/gtest.vcxproj'"
check "テストは gtest をプロジェクト参照し、packages.config も NuGet もない" bash -c "grep -q 'ProjectReference Include=\"..\\\\gtest\\\\gtest.vcxproj\"' '$S4/CoreLibTest/CoreLibTest.vcxproj' && [ ! -e '$S4/CoreLibTest/packages.config' ] && ! grep -qi nuget '$S4/CoreLibTest/CoreLibTest.vcxproj'"
check "テストの include に、ThirdParty の include がある" grep -q 'ThirdParty\\googletest\\include' "$S4/CoreLibTest/CoreLibTest.vcxproj"
check ".sln: App + CoreLib + CoreLibTest + gtest = 4" bash -c "[ \$(grep -c '^Project(' '$S4/ThreeLayerSample.sln') -eq 4 ]"
check "XML が正しい" bash -c "python3 -c \"import glob,xml.dom.minidom as m; [m.parse(f) for f in glob.glob('$S4/*/*.vcxproj')+glob.glob('$S4/*/*.filters')]\""
run_al_auto "$S4" OtherLib --kind lib >/dev/null 2>&1; [ $? -eq 0 ] && ok "2 つ目の層: 既存の gtest を再利用する" || ng "2 つ目の層: 既存の gtest を再利用する"
check ".sln: gtest は 1 つだけ (計 6 プロジェクト)" bash -c "[ \$(grep -c '^Project(' '$S4/ThreeLayerSample.sln') -eq 6 ] && [ \$(grep -c '\"gtest\"' '$S4/ThreeLayerSample.sln') -eq 1 ]"
mkdir -p "$S4/ThirdParty/googletest/include/gtest" "$S4/ThirdParty/googletest/src"
touch "$S4/ThirdParty/googletest/include/gtest/gtest.h" "$S4/ThirdParty/googletest/src/gtest-all.cc" "$S4/ThirdParty/googletest/src/gtest_main.cc"
check "ソースがあれば、GTEST_SOURCE: present" bash -c "python3 '$SCRIPT' '$S4' ThirdLib --dry-run | grep -q 'GTEST_SOURCE: present'"
python3 "$SCRIPT" "$S4" NuLib --gtest nuget --dry-run >"$WORK/out_nu.txt" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q '廃止' "$WORK/out_nu.txt" && ok "--gtest nuget (旧 NuGet 方式) は、廃止: rc 2 と、理由" || ng "--gtest nuget の廃止 (rc=$rc)"
python3 "$SCRIPT" "$S4" NuLib --gtest-from "$WORK/x" --dry-run >/dev/null 2>&1; [ $? -eq 2 ] && ok "--gtest-from も、廃止 (rc 2)" || ng "--gtest-from の廃止"

echo "== GoogleTest の vcpkg 方式 (--gtest auto が既定)"
S5="$WORK/sln5"; make_sln "$S5"
python3 "$SCRIPT" "$S5" CoreLib >"$WORK/out_vcp.txt" 2>&1; [ $? -eq 0 ] && ok "auto: vcpkg で追加できる" || { ng "auto: vcpkg で追加できる"; cat "$WORK/out_vcp.txt"; }
check "出力: GTEST_MODE: vcpkg、GTEST_VCPKG: no-baseline" bash -c "grep -q 'GTEST_MODE: vcpkg' '$WORK/out_vcp.txt' && grep -q 'GTEST_VCPKG: no-baseline' '$WORK/out_vcp.txt'"
check "vcpkg.json に gtest、.gitignore に vcpkg_installed/" bash -c "grep -q '\"gtest\"' '$S5/vcpkg.json' && grep -qx 'vcpkg_installed/' '$S5/.gitignore'"
check "テスト: main.cpp あり、packages.config なし、gtest プロジェクトなし" bash -c "grep -q 'int main' '$S5/CoreLibTest/main.cpp' && [ ! -e '$S5/CoreLibTest/packages.config' ] && [ ! -e '$S5/gtest' ]"
check "テストの vcxproj: Vcpkg の設定 (x64-windows-static-md)、DLL にはない" bash -c "grep -q 'VcpkgEnableManifest>true' '$S5/CoreLibTest/CoreLibTest.vcxproj' && grep -q 'x64-windows-static-md' '$S5/CoreLibTest/CoreLibTest.vcxproj' && ! grep -q Vcpkg '$S5/CoreLib/CoreLib.vcxproj'"
check "XML が正しい" bash -c "python3 -c \"import glob,xml.dom.minidom as m; [m.parse(f) for f in glob.glob('$S5/*/*.vcxproj')+glob.glob('$S5/*/*.filters')]\""
python3 "$SCRIPT" "$S5" OtherLib --kind lib >/dev/null 2>&1; [ $? -eq 0 ] && ok "2 つ目の層: vcpkg.json は 1 つのまま、gtest は 1 回だけ" || ng "2 つ目の層"
check "vcpkg.json の gtest は 1 つ" bash -c "[ \$(grep -c '\"gtest\"' '$S5/vcpkg.json') -eq 1 ]"
python3 - "$S5" <<'EOF'
import json, sys
p = sys.argv[1] + '/vcpkg.json'
m = json.load(open(p)); m['builtin-baseline'] = '0' * 40
json.dump(m, open(p, 'w'))
EOF
check "baseline があれば、GTEST_VCPKG: present (dry-run)" bash -c "python3 '$SCRIPT' '$S5' ThirdLib --dry-run | grep -q 'GTEST_VCPKG: present'"
ID=Microsoft.googletest.v140.windesktop.msvcstl.static.rt-dyn; VER=1.8.1.8
S6="$WORK/sln6"; make_sln "$S6"; mkdir -p "$S6/packages/$ID.$VER/build/native"; echo '<Project/>' > "$S6/packages/$ID.$VER/build/native/$ID.targets"
python3 "$SCRIPT" "$S6" CoreLib >"$WORK/out_legacy.txt" 2>&1
grep -q 'GTEST_MODE: vcpkg' "$WORK/out_legacy.txt" && grep -q '旧 NuGet 方式' "$WORK/out_legacy.txt" && ok "auto: packages\\ に旧 NuGet 方式の GoogleTest があっても、新しいテストは vcpkg (NOTE で、既存のテストは、そのまま動くと案内)" || { ng "auto: 旧方式のソリューション"; cat "$WORK/out_legacy.txt"; }
check "旧方式の packages\\ は、そのまま (消さない・触らない)" bash -c "[ -f '$S6/packages/$ID.$VER/build/native/$ID.targets' ]"
check "新しいテストは、packages.config を持たない" bash -c "[ ! -e '$S6/CoreLibTest/packages.config' ] && [ -f '$S6/CoreLibTest/main.cpp' ]"

echo "== MFC 拡張 DLL (--kind mfc-ext-dll)"
S7="$WORK/sln7"; make_sln "$S7"
python3 "$SCRIPT" "$S7" ExtLogic --kind mfc-ext-dll --gtest vcpkg >"$WORK/out_ext.txt" 2>&1; rc=$?
check "mfc-ext-dll: 作成できる (rc=0)" test "$rc" -eq 0
EV="$S7/ExtLogic/ExtLogic.vcxproj"; ET="$S7/ExtLogicTest/ExtLogicTest.vcxproj"
check "拡張 DLL: UseOfMfc=Dynamic (Debug / Release の 2 か所)、DynamicLibrary" bash -c "[ \"\$(grep -c '<UseOfMfc>Dynamic</UseOfMfc>' '$EV')\" = 2 ] && grep -q '<ConfigurationType>DynamicLibrary</ConfigurationType>' '$EV'"
check "拡張 DLL: _AFXEXT を定義し、_USRDLL は付けない (LNK2005 の原因)" bash -c "[ \"\$(grep -c '_AFXEXT' '$EV')\" = 2 ] && ! grep -q '_USRDLL' '$EV' && grep -q 'EXTLOGIC_EXPORTS' '$EV'"
check "拡張 DLL: pch.h を使い (Use)、pch.cpp は Create、dllmain.cpp は NotUsing" bash -c "[ \"\$(grep -c '<PrecompiledHeader>Use</PrecompiledHeader>' '$EV')\" = 2 ] && grep -q '<PrecompiledHeaderFile>pch.h</PrecompiledHeaderFile>' '$EV' && tr -d '\r' < '$EV' | grep -A1 'ClCompile Include=\"pch.cpp\"' | grep -q Create && tr -d '\r' < '$EV' | grep -A1 'ClCompile Include=\"dllmain.cpp\"' | grep -q NotUsing"
check "拡張 DLL: dllmain.cpp に定型コード (AFX_EXTENSION_MODULE / AfxInitExtensionModule / CDynLinkLibrary / AfxTermExtensionModule)" bash -c "for k in AFX_EXTENSION_MODULE AfxInitExtensionModule CDynLinkLibrary AfxTermExtensionModule afxdllx.h; do grep -q \$k '$S7/ExtLogic/dllmain.cpp' || exit 1; done"
check "拡張 DLL: ModuleInfo.cpp は、先頭で pch.h を include (プリコンパイル済みヘッダーを使うため)" bash -c "tr -d '\r' < '$S7/ExtLogic/ExtLogicModuleInfo.cpp' | sed '1s/^\xef\xbb\xbf//' | head -1 | grep -q '#include \"pch.h\"'"
check "拡張 DLL: Api.h に、CObject 派生には AFX_EXT_CLASS を付ける注意" grep -q 'AFX_EXT_CLASS' "$S7/ExtLogic/ExtLogicApi.h"
check "拡張 DLL: 全ファイルが BOM + CRLF (BOM なし・LF だと、MFC のヘッダーで原因の分かりにくいエラー)" bash -c "for f in '$S7'/ExtLogic/*.cpp '$S7'/ExtLogic/*.h; do [ \"\$(head -c3 \$f | xxd -p)\" = efbbbf ] && [ \"\$(grep -vc \$'\\r\$' \$f)\" = 0 ] || exit 1; done"
check "テスト exe: UseOfMfc=Dynamic (同じ共有 MFC ランタイム)、_AFXEXT は付けない、DLL をプロジェクト参照" bash -c "[ \"\$(grep -c '<UseOfMfc>Dynamic</UseOfMfc>' '$ET')\" = 2 ] && ! grep -q '_AFXEXT' '$ET' && grep -q 'ProjectReference Include=\"..\\\\ExtLogic\\\\ExtLogic.vcxproj\"' '$ET'"
check "テスト exe: マニフェストの DPI は、付けない (UI のアプリではない)" bash -c "! grep -q 'EnableDpiAwareness' '$ET'"
check "ソリューションに、ExtLogic と ExtLogicTest が登録された" bash -c "grep -q 'ExtLogic.vcxproj' '$S7'/*.sln && grep -q 'ExtLogicTest.vcxproj' '$S7'/*.sln"
check "通常の DLL (--kind dll) は、変わらない: UseOfMfc なし、_USRDLL あり、PCH なし" bash -c "python3 '$SCRIPT' '$S7' PlainDll --gtest vcpkg >/dev/null 2>&1 && ! grep -q UseOfMfc '$S7/PlainDll/PlainDll.vcxproj' && grep -q '_USRDLL' '$S7/PlainDll/PlainDll.vcxproj' && ! grep -q '<PrecompiledHeader>Use' '$S7/PlainDll/PlainDll.vcxproj' && ! grep -q UseOfMfc '$S7/PlainDllTest/PlainDllTest.vcxproj'"
# テストの後付け (--tests-only): 拡張 DLL を検出して、テスト exe も UseOfMfc=Dynamic にする
S8="$WORK/sln8"; make_sln "$S8"; python3 "$SCRIPT" "$S8" ExtData --kind mfc-ext-dll --tests none --gtest vcpkg >/dev/null 2>&1
python3 "$SCRIPT" "$S8" ExtData --tests-only --gtest vcpkg >/dev/null 2>&1
check "--tests-only: 拡張 DLL を検出して、テスト exe も UseOfMfc=Dynamic にする" bash -c "[ \"\$(grep -c '<UseOfMfc>Dynamic</UseOfMfc>' '$S8/ExtDataTest/ExtDataTest.vcxproj')\" = 2 ]"

echo "== MFC 標準 DLL (--kind mfc-std-dll)"
S9="$WORK/sln9"; make_sln "$S9"
python3 "$SCRIPT" "$S9" StdLogic --kind mfc-std-dll --gtest vcpkg >"$WORK/out_std.txt" 2>&1; rc=$?
check "mfc-std-dll: 作成できる (rc=0)" test "$rc" -eq 0
SV="$S9/StdLogic/StdLogic.vcxproj"; ST="$S9/StdLogicTest/StdLogicTest.vcxproj"
check "標準 DLL: UseOfMfc=Dynamic (Debug / Release の 2 か所)、DynamicLibrary" bash -c "[ \"\$(grep -c '<UseOfMfc>Dynamic</UseOfMfc>' '$SV')\" = 2 ] && grep -q '<ConfigurationType>DynamicLibrary</ConfigurationType>' '$SV'"
check "標準 DLL: _USRDLL を定義し、_AFXEXT は付けない (拡張 DLL との違い)、<NAME>_EXPORTS" bash -c "[ \"\$(grep -c '_USRDLL' '$SV')\" = 2 ] && ! grep -q '_AFXEXT' '$SV' && grep -q 'STDLOGIC_EXPORTS' '$SV'"
check "標準 DLL: pch.h を使い (Use)、pch.cpp は Create。dllmain.cpp はない (CWinApp が入口)" bash -c "[ \"\$(grep -c '<PrecompiledHeader>Use</PrecompiledHeader>' '$SV')\" = 2 ] && tr -d '\r' < '$SV' | grep -A1 'ClCompile Include=\"pch.cpp\"' | grep -q Create && [ ! -e '$S9/StdLogic/dllmain.cpp' ]"
check "標準 DLL: CWinApp 派生クラスと theApp (StdLogic.h / .cpp)" bash -c "grep -q 'class CStdLogicApp : public CWinApp' '$S9/StdLogic/StdLogic.h' && grep -q 'CStdLogicApp theApp;' '$S9/StdLogic/StdLogic.cpp' && grep -q 'InitInstance' '$S9/StdLogic/StdLogic.cpp'"
check "標準 DLL: エクスポート関数 (ModuleInfo.cpp) の、最初の文 (コメントを除く) が AFX_MANAGE_STATE" python3 -c 'import re,sys; t=open(sys.argv[1],encoding="utf-8-sig").read().replace("\r",""); m=re.search(r"StdLogicModuleName\(\)\s*\{\s*((?://[^\n]*\n\s*)*)(\S[^\n]*)", t); sys.exit(0 if m and m.group(2).startswith("AFX_MANAGE_STATE(AfxGetStaticModuleState());") else 1)' "$S9/StdLogic/StdLogicModuleInfo.cpp"
check "標準 DLL: ModuleInfo.cpp は、先頭で pch.h を include" bash -c "tr -d '\r' < '$S9/StdLogic/StdLogicModuleInfo.cpp' | sed '1s/^\xef\xbb\xbf//' | head -1 | grep -q '#include \"pch.h\"'"
check "標準 DLL: Api.h に、AFX_MANAGE_STATE と、MFC オブジェクトを境界で渡さない注意" bash -c "grep -q 'AFX_MANAGE_STATE' '$S9/StdLogic/StdLogicApi.h' && grep -q 'mfc-ext-dll' '$S9/StdLogic/StdLogicApi.h'"
check "標準 DLL: 全ファイルが BOM + CRLF" bash -c "for f in '$S9'/StdLogic/*.cpp '$S9'/StdLogic/*.h; do [ \"\$(head -c3 \$f | xxd -p)\" = efbbbf ] && [ \"\$(grep -vc \$'\\r\$' \$f)\" = 0 ] || exit 1; done"
check "テスト exe: MFC なし (UseOfMfc なし、_AFXEXT なし)。DLL をプロジェクト参照" bash -c "! grep -q 'UseOfMfc' '$ST' && ! grep -q '_AFXEXT' '$ST' && grep -q 'ProjectReference Include=\"..\\\\StdLogic\\\\StdLogic.vcxproj\"' '$ST'"
check "拡張 DLL の出力は、変わらない (UseOfMfc、_AFXEXT、dllmain.cpp。_USRDLL なし)" bash -c "python3 '$SCRIPT' '$S9' ExtOk --kind mfc-ext-dll --gtest vcpkg >/dev/null 2>&1 && grep -q '_AFXEXT' '$S9/ExtOk/ExtOk.vcxproj' && ! grep -q '_USRDLL' '$S9/ExtOk/ExtOk.vcxproj' && [ -f '$S9/ExtOk/dllmain.cpp' ]"
S10="$WORK/sln10"; make_sln "$S10"; python3 "$SCRIPT" "$S10" StdData --kind mfc-std-dll --tests none --gtest vcpkg >/dev/null 2>&1
python3 "$SCRIPT" "$S10" StdData --tests-only --gtest vcpkg >/dev/null 2>&1
check "--tests-only: 標準 DLL のテスト exe は、MFC なし" bash -c "[ -f '$S10/StdDataTest/StdDataTest.vcxproj' ] && ! grep -q 'UseOfMfc' '$S10/StdDataTest/StdDataTest.vcxproj'"

echo
if [ "$fail" -eq 0 ]; then echo "すべて OK"; else echo "失敗あり"; fi
exit "$fail"
