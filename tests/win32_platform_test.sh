#!/usr/bin/env bash
# win32_platform_test.sh - C++ のソリューションの、プラットフォーム (x64 / Win32) の指定と、あとからの追加を、疑似フォルダで検証する (Windows 不要)。v2.62.0。
#   - /new-solution --platforms (x64 既定 / x64,Win32 / Win32)
#   - add_platform.py (/add-project platform): あとから Win32 (または x64) を足す。最初から両方で作ったものと、同じ結果になること
#   - 層・テストを、あとから足すとき、既存のソリューションのプラットフォームに、そろうこと
#
# Usage: tests/win32_platform_test.sh
# 終了コード: 0 すべて OK / 1 失敗あり
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$REPO/skills/new-solution/scripts/new_solution.py"
ADD="$REPO/skills/add-project/scripts/add_platform.py"
LAYER="$REPO/skills/cpp-test-first/scripts/add_layer.py"
MFC_CHK="$REPO/skills/mfc-check/scripts/mfc_check.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/win32_platform_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0
ok() { echo "OK  $1"; }
ng() { echo "NG  $1"; fail=1; }
rc_is() { local want="$1" d="$2"; shift 2; "$@" >"$WORK/last.out" 2>&1; local rc=$?; if [ "$rc" -eq "$want" ]; then ok "$d"; else ng "$d (rc=$rc, 期待 $want)"; head -3 "$WORK/last.out"; fi; }

# 比べやすいように、GUID とソリューション名を、そろえる
norm() { python3 - "$1" "$2" <<'PYX'
import re, sys
t = open(sys.argv[1], encoding='utf-8-sig').read().replace('\r\n', '\n')
name = sys.argv[2]
# 名前は、先頭が英字 1 文字 + _ の形 (G_mfc / F_mfc など)。_AFXEXT のような、名前を含む別の語を、壊さないために、
# 「<大文字 1 字>_」を含む名前だけを置き換える (名前の前に別の英字が付いても、置き換える: TestG_dllModuleInfo.cpp)
for nm in (name, name.upper()):
    t = t.replace(nm, 'X')
t = re.sub(r'<ProjectGuid>\{[^}]*\}</ProjectGuid>', '<ProjectGuid>G</ProjectGuid>', t)
t = re.sub(r'<Project>\{[^}]*\}</Project>', '<Project>G</Project>', t)
t = re.sub(r'Id="[0-9a-f-]{36}"', 'Id="X"', t)
sys.stdout.write(t)
PYX
}
same_tree() { # $1=A のフォルダ名 $2=B のフォルダ名。.vcxproj と .slnx が、同じか
    local a="$1" b="$2" f rel
    for f in $(cd "$WORK/$a" && find . -name '*.vcxproj' -o -name '*.slnx' | sort); do
        rel="${f#./}"
        local fb="${rel//$a/$b}"
        [ -f "$WORK/$b/$fb" ] || { echo "ない: $b/$fb"; return 1; }
        [ "$(norm "$WORK/$a/$rel" "$a")" = "$(norm "$WORK/$b/$fb" "$b")" ] || { echo "違う: $rel"; return 1; }
    done
    return 0
}
mk() { # $1=名前 $2.. = new_solution の引数
    local n="$1"; shift; mkdir -p "$WORK/$n"; python3 "$NEW" "$WORK/$n" "$@" >"$WORK/$n.out" 2>&1
}
nplat() { grep -c '<ProjectConfiguration Include=' "$1"; }

echo "== 新規作成の --platforms"
# 1. 既定 (x64)
mk Def --type mfc --layers logic,data --tests gtest --gtest vcpkg
[ "$(nplat "$WORK/Def/Def/Def.vcxproj")" = 2 ] && ! grep -q 'Win32' "$WORK/Def/Def/Def.vcxproj" && ok "既定: x64 だけ (2 構成)" || ng "既定: x64 だけでない"
grep -q 'Platform Name="x64"' "$WORK/Def/Def.slnx" && ! grep -q 'x86' "$WORK/Def/Def.slnx" && ok "既定: .slnx は x64 だけ" || ng "既定: .slnx が x64 だけでない"
grep -q 'プラットフォームは x64 だけ。Win32 は、あとから `/add-project platform Win32`' "$WORK/Def/CLAUDE.md" && ok "既定: CLAUDE.md に、あとから足せる案内" || ng "既定: CLAUDE.md の案内がない"
grep -q '^Win32/' "$WORK/Def/.gitignore" && ok ".gitignore に Win32/" || ng ".gitignore に Win32/ がない"

# 2. x64,Win32 (種類ごと)
for t in mfc mfc-mdi mfc-dialog win32 console dll lib; do
    n="B_${t//-/_}"
    mk "$n" --type "$t" --layers logic,data --tests gtest --gtest vcpkg --platforms x64,Win32
    out=$(python3 - "$WORK/$n" "$n" <<'PYX'
import glob, os, re, sys
root, n = sys.argv[1:3]
errs = []
files = [f for f in glob.glob(os.path.join(root, '*', '*.vcxproj'))]
if not files: errs.append('vcxproj がない')
for f in files:
    t = open(f, encoding='utf-8-sig').read()
    b = os.path.basename(f)
    if t.count('<ProjectConfiguration Include=') != 4: errs.append(b + ': 構成が 4 つでない')
    for c in ('Debug|Win32', 'Release|Win32', 'Debug|x64', 'Release|x64'):
        if f"'$(Configuration)|$(Platform)'=='{c}'" not in t: errs.append(b + ': ' + c + ' の構成がない')
    if t.count('WIN32;') != 2: errs.append(b + ': WIN32; の定義が 2 つ (Debug・Release) でない')
    if 'VcpkgEnableManifest' in t and ("'x86-windows-static-md'" in t or 'x86-windows-static-md</VcpkgTriplet>' not in t): errs.append(b + ': Win32 のトリプレットがない')
    if 'x86-windows-static-md' in t and "'$(Platform)'=='Win32'\">x86-windows-static-md" not in t: errs.append(b + ': トリプレットの条件が違う')
s = open(glob.glob(os.path.join(root, '*.slnx'))[0], encoding='utf-8-sig').read()
if 'Platform Name="x64"' not in s or 'Platform Name="x86"' not in s: errs.append('.slnx に x64 と x86 がない')
print('\n'.join(errs))
PYX
)
    if [ -z "$out" ]; then ok "$t: 全部の .vcxproj が 4 構成 (Debug・Release x Win32・x64)、WIN32;、トリプレット、.slnx は x64 と x86"; else ng "$t: $out"; fi
done
grep -q 'x64 と Win32' "$WORK/B_mfc/CLAUDE.md" && grep -q 'run_watcher.cmd <フォルダ> "" Win32' "$WORK/B_mfc/CLAUDE.md" && ok "x64,Win32: CLAUDE.md にウォッチャーの起動の案内" || ng "x64,Win32: CLAUDE.md の案内がない"
python3 "$MFC_CHK" "$WORK/B_mfc" --all 2>&1 | grep -q 'error 0 / warning 0' && ok "x64,Win32 (MFC): mfc-check が error 0 / warning 0" || ng "x64,Win32 (MFC): mfc-check が指摘を出した"

# 3. Win32 のみ (x86 は別名)
mk Wo --type mfc --layers logic,data --tests gtest --gtest vcpkg --platforms x86
if [ "$(nplat "$WORK/Wo/Wo/Wo.vcxproj")" = 2 ] && ! grep -q "|x64'" "$WORK/Wo/Wo/Wo.vcxproj" && grep -q 'Platform Name="x86"' "$WORK/Wo/Wo.slnx" && ! grep -q 'Platform Name="x64"' "$WORK/Wo/Wo.slnx"; then ok "Win32 のみ (x86 は別名): Win32 の 2 構成、.slnx は x86 だけ"; else ng "Win32 のみ: 構成か .slnx が違う"; fi
grep -q 'Win32 のみ' "$WORK/Wo/CLAUDE.md" && grep -q '必ず' "$WORK/Wo/CLAUDE.md" && ok "Win32 のみ: CLAUDE.md に、必ず Win32 で起動する案内" || ng "Win32 のみ: CLAUDE.md の案内がない"

# 4. エラー
mkdir -p "$WORK/E1"; rc_is 2 "不正なプラットフォーム (--platforms arm) は rc 2" python3 "$NEW" "$WORK/E1" --type mfc --layers none --tests none --platforms arm
mkdir -p "$WORK/E2"; rc_is 2 ".NET (--type wpf) に --platforms は rc 2" python3 "$NEW" "$WORK/E2" --type wpf --layers none --tests none --platforms x64
rc_is 2 "すでにあるソリューションに --platforms は rc 2 (あとから足すのは add_platform.py)" python3 "$NEW" "$WORK/Def" --tests gtest --platforms Win32

echo "== あとから追加 (add_platform.py)"
for t in mfc mfc-mdi mfc-dialog win32 console dll lib; do
    g="G_${t//-/_}"; f="F_${t//-/_}"
    mk "$g" --type "$t" --layers logic,data --tests gtest --gtest vcpkg
    mk "$f" --type "$t" --layers logic,data --tests gtest --gtest vcpkg --platforms x64,Win32
    rc_is 0 "$t: x64 だけのソリューションに、Win32 を足せる" python3 "$ADD" "$WORK/$g" --platform Win32
    r=$(same_tree "$g" "$f") && ok "$t: あとから足した結果が、最初から両方で作ったものと、同じ (全部の .vcxproj と .slnx)" || ng "$t: 最初から両方で作ったものと違う: $r"
done
# MFC の拡張 DLL・標準 DLL の層 (あとから足す)
mk G_xext --type mfc --layers logic --tests gtest --gtest vcpkg --layer-kind mfc-ext-dll
mk F_xext --type mfc --layers logic --tests gtest --gtest vcpkg --layer-kind mfc-ext-dll --platforms x64,Win32
rc_is 0 "mfc-ext-dll の層: Win32 を足せる" python3 "$ADD" "$WORK/G_xext" --platform Win32
r=$(same_tree G_xext F_xext) && ok "mfc-ext-dll の層: あとから足した結果が、最初から両方のものと、同じ" || ng "mfc-ext-dll の層: 違う: $r"
mk G_xstd --type win32 --layers logic --tests gtest --gtest vcpkg --layer-kind mfc-std-dll
mk F_xstd --type win32 --layers logic --tests gtest --gtest vcpkg --layer-kind mfc-std-dll --platforms x64,Win32
rc_is 0 "mfc-std-dll の層: Win32 を足せる" python3 "$ADD" "$WORK/G_xstd" --platform Win32
r=$(same_tree G_xstd F_xstd) && ok "mfc-std-dll の層: あとから足した結果が、最初から両方のものと、同じ" || ng "mfc-std-dll の層: 違う: $r"

# 冪等・dry-run・逆向き
rc_is 3 "すでに両方ある: 何もせず rc 3 (冪等)" python3 "$ADD" "$WORK/G_mfc" --platform Win32
mk Dr --type mfc --layers logic --tests none
before=$(find "$WORK/Dr" -type f | sort | xargs md5sum | md5sum)
rc_is 0 "--dry-run は rc 0" python3 "$ADD" "$WORK/Dr" --platform Win32 --dry-run
after=$(find "$WORK/Dr" -type f | sort | xargs md5sum | md5sum)
[ "$before" = "$after" ] && ok "--dry-run は、何も書かない" || ng "--dry-run が、ファイルを書いた"
mk Wr --type mfc --layers logic,data --tests gtest --gtest vcpkg --platforms Win32
mk Br --type mfc --layers logic,data --tests gtest --gtest vcpkg --platforms x64,Win32
rc_is 0 "Win32 だけのソリューションに、x64 を足せる" python3 "$ADD" "$WORK/Wr" --platform x64
r=$(same_tree Wr Br) && ok "x64 を足した結果が、最初から両方で作ったものと、同じ" || ng "x64 を足した結果が違う: $r"

# 想定外の形式 -> 何も書かずに止まる (全部か、何もか)
mk Bad --type mfc --layers logic,data --tests none
printf '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n<PropertyGroup Label="Globals"/>\n</Project>\n' > "$WORK/Bad/DataLayer/DataLayer.vcxproj"
before=$(find "$WORK/Bad" -type f | sort | xargs md5sum | md5sum)
rc_is 2 "想定外の .vcxproj が 1 つでもあれば、rc 2" python3 "$ADD" "$WORK/Bad" --platform Win32
after=$(find "$WORK/Bad" -type f | sort | xargs md5sum | md5sum)
[ "$before" = "$after" ] && ok "想定外の形式があるとき、ほかのファイルも、1 つも書かない (全部か、何もか)" || ng "想定外の形式なのに、一部を書いた"
mkdir -p "$WORK/Net"; mkdir -p "$WORK/Net/App"; printf '<Solution>\n  <Project Path="App/App.csproj" />\n</Solution>\n' > "$WORK/Net/Net.slnx"
rc_is 2 "C++ のプロジェクトがなければ rc 2 (.NET は対象外)" python3 "$ADD" "$WORK/Net" --platform Win32
rc_is 2 "不正な --platform は rc 2" python3 "$ADD" "$WORK/Dr" --platform arm64

# x64 に固有の記述 (例: ライブラリのフォルダ) は、Win32 に、そのまま写るので、注意を出す (止めない)
mk Sp --type mfc --layers none --tests none
python3 - "$WORK/Sp/Sp/Sp.vcxproj" <<'PYX'
import sys
p = sys.argv[1]
t = open(p, encoding='utf-8-sig').read()          # 改行は、\n に直って読める
t = t.replace('<Link>\n      <SubSystem>', '<Link>\n      <AdditionalLibraryDirectories>..\\lib\\x64;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>\n      <SubSystem>', 1)
open(p, 'wb').write(b'\xef\xbb\xbf' + t.replace('\n', '\r\n').encode('utf-8'))
PYX
grep -q 'lib\\x64' "$WORK/Sp/Sp/Sp.vcxproj" && ok "(準備) x64 固有のライブラリのフォルダを、Link に足した" || ng "(準備) x64 固有のライブラリのフォルダを足せなかった"
python3 "$ADD" "$WORK/Sp" --platform Win32 --dry-run > "$WORK/sp.out" 2>&1
grep -q '【注意】x64 を含む記述が、そのまま Win32 に写った' "$WORK/sp.out" && ok "x64 固有の記述が写るとき、注意を出す" || ng "x64 固有の記述の注意が出ない"
rc_is 0 "注意は出しても、止めない (rc 0)" python3 "$ADD" "$WORK/Sp" --platform Win32
mk Nn --type mfc --layers none --tests none
python3 "$ADD" "$WORK/Nn" --platform Win32 --dry-run 2>&1 | grep -q '【注意】' && ng "固有の記述がないのに、注意が出た" || ok "固有の記述がなければ、注意は出ない"

# ウィザードで作った形 (x64 と Win32 の両方) は、何もしない
mkdir -p "$WORK/Wz/Wz"
cp "$WORK/F_mfc/F_mfc/F_mfc.vcxproj" "$WORK/Wz/Wz/Wz.vcxproj"; cp "$WORK/F_mfc/F_mfc.slnx" "$WORK/Wz/Wz.slnx"
rc_is 3 "ウィザードと同じ形 (Win32 と x64) は、何もしない (rc 3)" python3 "$ADD" "$WORK/Wz" --platform Win32

echo "== .sln (ソリューション構成の対応づけ)"
mkdir -p "$WORK/Sl/Sl"
cp "$WORK/G_mfc/G_mfc/G_mfc.vcxproj" "$WORK/Sl/Sl/Sl.vcxproj"
python3 - "$WORK/Sl" <<'PYX'
import re, sys
d = sys.argv[1]
guid = re.search(r'<ProjectGuid>(\{[^}]*\})</ProjectGuid>', open(d + '/Sl/Sl.vcxproj', encoding='utf-8-sig').read()).group(1)
sln = ('﻿Microsoft Visual Studio Solution File, Format Version 12.00\r\n'
       'Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "Sl", "Sl\\Sl.vcxproj", "' + guid + '"\r\nEndProject\r\nGlobal\r\n'
       '\tGlobalSection(SolutionConfigurationPlatforms) = preSolution\r\n\t\tDebug|x64 = Debug|x64\r\n\t\tRelease|x64 = Release|x64\r\n\tEndGlobalSection\r\n'
       '\tGlobalSection(ProjectConfigurationPlatforms) = postSolution\r\n'
       '\t\t' + guid + '.Debug|x64.ActiveCfg = Debug|x64\r\n\t\t' + guid + '.Debug|x64.Build.0 = Debug|x64\r\n'
       '\t\t' + guid + '.Release|x64.ActiveCfg = Release|x64\r\n\t\t' + guid + '.Release|x64.Build.0 = Release|x64\r\n\tEndGlobalSection\r\nEndGlobal\r\n')
open(d + '/Sl.sln', 'wb').write(sln.encode('utf-8'))
PYX
rc_is 0 ".sln: Win32 を足せる" python3 "$ADD" "$WORK/Sl" --platform Win32
if grep -q 'Debug|x86 = Debug|x86' "$WORK/Sl/Sl.sln" && grep -q '\.Debug|x86\.ActiveCfg = Debug|Win32' "$WORK/Sl/Sl.sln" && grep -q '\.Release|x86\.Build\.0 = Release|Win32' "$WORK/Sl/Sl.sln"; then ok ".sln: ソリューションの x86 を、プロジェクトの Win32 に対応づける"; else ng ".sln: x86 → Win32 の対応づけがない"; fi
head -c3 "$WORK/Sl/Sl.sln" | xxd -p | grep -q efbbbf && grep -q $'\r' "$WORK/Sl/Sl.sln" && ok ".sln: BOM と CRLF が残る" || ng ".sln: BOM か CRLF が失われた"

echo "== 層・テストを、あとから足すとき、既存のソリューションのプラットフォームにそろう"
mk LW --type mfc --layers none --tests none --platforms Win32
rc_is 0 "Win32 のソリューションに、層とテストを足せる" python3 "$LAYER" "$WORK/LW" LogicLayer --tests gtest --gtest vcpkg
if [ "$(nplat "$WORK/LW/LogicLayer/LogicLayer.vcxproj")" = 2 ] && ! grep -q "|x64'" "$WORK/LW/LogicLayer/LogicLayer.vcxproj" && ! grep -q "|x64'" "$WORK/LW/LogicLayerTest/LogicLayerTest.vcxproj"; then ok "足した層とテストは、Win32 だけ (ソリューションに、そろう)"; else ng "足した層・テストが、ソリューションのプラットフォームと違う"; fi
mk LB --type mfc --layers none --tests none --platforms x64,Win32
rc_is 0 "x64 と Win32 のソリューションに、層とテストを足せる" python3 "$LAYER" "$WORK/LB" LogicLayer --tests gtest --gtest vcpkg
[ "$(nplat "$WORK/LB/LogicLayer/LogicLayer.vcxproj")" = 4 ] && [ "$(nplat "$WORK/LB/LogicLayerTest/LogicLayerTest.vcxproj")" = 4 ] && ok "足した層とテストは、4 構成 (ソリューションに、そろう)" || ng "足した層・テストが 4 構成でない"
mk LD --type mfc --layers none --tests none
python3 "$LAYER" "$WORK/LD" LogicLayer --tests gtest --gtest vcpkg >/dev/null 2>&1
[ "$(nplat "$WORK/LD/LogicLayer/LogicLayer.vcxproj")" = 2 ] && ! grep -q "|Win32'" "$WORK/LD/LogicLayer/LogicLayer.vcxproj" && ok "x64 だけのソリューションに足した層は、x64 だけ (いままでと同じ)" || ng "x64 だけのソリューションの層が、x64 だけでない"

echo "== solution_state.py と SKILL"
STATE="$REPO/skills/add-project/scripts/solution_state.py"
python3 "$STATE" "$WORK/Def" > "$WORK/st_def.txt" 2>&1; python3 "$STATE" "$WORK/B_mfc" > "$WORK/st_both.txt" 2>&1; python3 "$STATE" "$WORK/Wo" > "$WORK/st_wo.txt" 2>&1
grep -q '^PLATFORMS: x64$' "$WORK/st_def.txt" && grep -q '^ADDABLE: platform:Win32 ' "$WORK/st_def.txt" && ! grep -q '^ADDABLE: platform:x64' "$WORK/st_def.txt" && ok "x64 だけ: PLATFORMS: x64、ADDABLE に platform:Win32 (x64 は、すでにあるので、出ない)" || ng "x64 だけ: PLATFORMS / ADDABLE が違う"
grep -q '^PLATFORMS: Win32, x64$' "$WORK/st_both.txt" && ! grep -q '^ADDABLE: platform' "$WORK/st_both.txt" && ok "両方ある: PLATFORMS: Win32, x64、ADDABLE に platform は出ない" || ng "両方ある: PLATFORMS / ADDABLE が違う"
grep -q '^PLATFORMS: Win32$' "$WORK/st_wo.txt" && grep -q '^ADDABLE: platform:x64 ' "$WORK/st_wo.txt" && ok "Win32 だけ: ADDABLE に platform:x64" || ng "Win32 だけ: PLATFORMS / ADDABLE が違う"
SK="$REPO/skills/add-project/SKILL.md"; NS="$REPO/skills/new-solution/SKILL.md"
grep -q 'platform' "$SK" && grep -q 'add_platform.py' "$SK" && grep -q 'MSB4126' "$SK" && grep -q '何も書かずに止まる' "$SK" && ok "add-project の SKILL: platform の手順 (add_platform.py、承認、想定外の形式で止まる、Win32 のビルドは Platform 引数の注意 (MSB4126))" || ng "add-project の SKILL に platform の手順がない"
grep -q -- '--platforms' "$NS" && grep -q '質問しない' "$NS" && grep -q '/add-project platform Win32' "$NS" && ok "new-solution の SKILL: --platforms (既定 x64、質問しない、あとから /add-project platform)" || ng "new-solution の SKILL に --platforms がない"
grep -q -- '--platforms' "$REPO/README.md" && grep -q 'add_platform.py' "$REPO/README.md" && ok "README: --platforms と /add-project platform" || ng "README に --platforms / platform がない"

echo
if [ "$fail" -eq 0 ]; then echo "すべて OK"; else echo "失敗あり"; fi
exit "$fail"
