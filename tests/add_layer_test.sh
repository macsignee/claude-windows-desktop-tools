#!/usr/bin/env bash
# add_layer_test.sh - skills/cpp-test-first/scripts/add_layer.py を、疑似のソリューション (.sln / .slnx) で検証する (Windows 不要)。
#
# Usage: tests/add_layer_test.sh
# 終了コード: 0 すべて OK / 1 失敗あり
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/skills/cpp-test-first/scripts/add_layer.py"
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
python3 "$SCRIPT" "$S" DataLayer --dry-run >/dev/null 2>&1 && [ ! -e "$S/DataLayer" ] && ok "dry-run は、何も書かない" || ng "dry-run は、何も書かない"
python3 "$SCRIPT" "$S" DataLayer >"$WORK/out1.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "DataLayer の追加が成功" || { ng "DataLayer の追加が成功 (rc=$rc)"; cat "$WORK/out1.txt"; }
python3 "$SCRIPT" "$S" LogicLayer --uses DataLayer >"$WORK/out2.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "LogicLayer (--uses DataLayer) の追加が成功" || { ng "LogicLayer の追加が成功 (rc=$rc)"; cat "$WORK/out2.txt"; }

for f in DataLayer/DataLayer.vcxproj DataLayer/DataLayer.vcxproj.filters DataLayer/DataLayerApi.h DataLayer/DataLayerModuleInfo.h DataLayer/DataLayerModuleInfo.cpp \
         DataLayerTest/DataLayerTest.vcxproj DataLayerTest/DataLayerTest.vcxproj.filters DataLayerTest/packages.config DataLayerTest/TestDataLayerModuleInfo.cpp \
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
check ".cpp が「ソース ファイル」フィルターに入る" grep -q '<ClCompile Include="DataLayerModuleInfo.cpp">' "$S/DataLayer/DataLayer.vcxproj.filters"
check "「ソース ファイル」のフィルター定義がある" grep -q '<Filter Include="ソース ファイル">' "$S/DataLayer/DataLayer.vcxproj.filters"
check "packages.config は、フィルターに入らない (None のまま)" bash -c "! grep -q 'packages.config' '$S/DataLayerTest/DataLayerTest.vcxproj.filters'"
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
python3 "$SCRIPT" "$S" DataLayer >/dev/null 2>&1; [ $? -eq 3 ] && ok "すでに存在 -> rc 3" || ng "すでに存在 -> rc 3"
python3 "$SCRIPT" "$S" 'bad name' >/dev/null 2>&1; [ $? -eq 2 ] && ok "不正な名前 -> rc 2" || ng "不正な名前 -> rc 2"
python3 "$SCRIPT" "$WORK/none" X >/dev/null 2>&1; [ $? -eq 2 ] && ok "フォルダなし -> rc 2" || ng "フォルダなし -> rc 2"
python3 "$SCRIPT" "$S" Other --uses NoSuch >/dev/null 2>&1; [ $? -eq 2 ] && ok "--uses のフォルダなし -> rc 2" || ng "--uses のフォルダなし -> rc 2"

echo "== .slnx"
X="$WORK/slnx"
python3 "$SCRIPT" "$X" DataLayer >"$WORK/out3.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "slnx への追加が成功" || { ng "slnx への追加が成功 (rc=$rc)"; cat "$WORK/out3.txt"; }
check ".slnx が XML として正しい" python3 -c "import xml.dom.minidom as m; m.parse('$X/ThreeLayerSample.slnx')"
check ".slnx: 2 プロジェクトが追加された" bash -c "[ \$(grep -c '<Project Path=' '$X/ThreeLayerSample.slnx') -eq 3 ]"
check ".slnx: DataLayerTest が登録された" grep -q 'DataLayerTest/DataLayerTest.vcxproj' "$X/ThreeLayerSample.slnx"

echo
if [ "$fail" -eq 0 ]; then echo "すべて OK"; else echo "失敗あり"; fi
exit "$fail"
