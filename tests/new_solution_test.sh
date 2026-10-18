#!/usr/bin/env bash
# new_solution_test.sh - skills/new-solution/scripts/new_solution.py を、疑似フォルダで検証する (Windows 不要)。
# 層 (--layers) と、テスト (--tests) が、独立した軸として動くこと、テストの後付けができることを確かめる。
#
# Usage: tests/new_solution_test.sh
# 終了コード: 0 すべて OK / 1 失敗あり
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$REPO/skills/new-solution/scripts/new_solution.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/new_solution_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0
ID=Microsoft.googletest.v140.windesktop.msvcstl.static.rt-dyn

ok() { echo "OK  $1"; }
ng() { echo "NG  $1"; fail=1; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ng "$d"; fi; }
rc_is() { local want="$1" d="$2"; shift 2; "$@" >/dev/null 2>&1; local rc=$?; [ "$rc" -eq "$want" ] && ok "$d" || ng "$d (rc=$rc, 期待 $want)"; }
nprojects() { grep -c '<Project Path=' "$1"; }
xml_ok() { python3 - "$1" <<'EOF'
import glob, os, sys, xml.dom.minidom as m
d = sys.argv[1]
fs = glob.glob(os.path.join(d, '*.slnx')) + glob.glob(os.path.join(d, '*', '*.vcxproj')) + glob.glob(os.path.join(d, '*', '*.filters'))
assert fs
for f in fs: m.parse(f)
EOF
}

# GoogleTest の、疑似のパッケージ (兄弟フォルダ __other/packages/<ID>.1.8.1.8/build/native/<ID>.targets)
mkdir -p "$WORK/R/__other/packages/$ID.1.8.1.8/build/native"
echo '<Project/>' > "$WORK/R/__other/packages/$ID.1.8.1.8/build/native/$ID.targets"

echo "== 1. console / 層なし / テストなし"
D="$WORK/R/ConsoleOnly"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers none --tests none --dry-run >/dev/null 2>&1 && [ ! -e "$D/ConsoleOnly.slnx" ] && ok "dry-run は、何も書かない" || ng "dry-run は、何も書かない"
rc_is 0 "作成が成功" python3 "$NEW" "$D" --type console --layers none --tests none
check ".slnx は、フォルダ名と同名" test -f "$D/ConsoleOnly.slnx"
check "メインのプロジェクト名も、フォルダ名そのまま (App を付けない)" test -f "$D/ConsoleOnly/ConsoleOnly.vcxproj"
check "プロジェクトは 1 つだけ" bash -c "[ $(nprojects "$D/ConsoleOnly.slnx") -eq 1 ]"
check "テストのフォルダも、packages も、ない" bash -c "! ls '$D' | grep -q Test && [ ! -e '$D/packages' ]"
check "CLAUDE.md: テスト: なし / 層: なし" bash -c "grep -q '^- テスト: なし' '$D/CLAUDE.md' && grep -q '^- 層: なし' '$D/CLAUDE.md'"
check "CLAUDE.md に、テストの節がない" bash -c "! grep -q 'GoogleTest)\$' '$D/CLAUDE.md' || ! grep -q '^## テスト' '$D/CLAUDE.md'"
check "XML が正しい" xml_ok "$D"
rc_is 3 "すでにソリューションがある (--tests なし) -> rc 3" python3 "$NEW" "$D" --type console --layers none --tests none

echo "== 2. MFC / logic,data / テストなし (層だけ)"
D="$WORK/R/LayersOnly"; mkdir -p "$D"
rc_is 0 "作成が成功" python3 "$NEW" "$D" --type mfc --layers logic,data --tests none
check "プロジェクトは 3 つ (メイン + DataLayer + LogicLayer)" bash -c "[ $(nprojects "$D/LayersOnly.slnx") -eq 3 ]"
check "DLL が 2 つ" bash -c "grep -q DynamicLibrary '$D/DataLayer/DataLayer.vcxproj' && grep -q DynamicLibrary '$D/LogicLayer/LogicLayer.vcxproj'"
check "テストのプロジェクトは、ない" bash -c "! ls -d '$D'/*Test >/dev/null 2>&1"
check "packages も packages.config も、ない" bash -c "[ ! -e '$D/packages' ] && [ -z \"\$(find '$D' -name packages.config)\" ]"
check "ロジックは、データのヘッダを参照 (リンクはしない)" bash -c "grep -q 'ProjectDir)..\\\\DataLayer' '$D/LogicLayer/LogicLayer.vcxproj' && ! grep -q 'ProjectReference' '$D/LogicLayer/LogicLayer.vcxproj'"
check "MFC: UseOfMfc Dynamic" grep -q '<UseOfMfc>Dynamic</UseOfMfc>' "$D/LayersOnly/LayersOnly.vcxproj"
check "MFC: .rc が ASCII (BOM なし)" bash -c "! head -c3 '$D/LayersOnly/LayersOnly.rc' | xxd -p | grep -q efbbbf && ! grep -qP '[^\x00-\x7F]' '$D/LayersOnly/LayersOnly.rc'"
check "CLAUDE.md: 層: logic,data / テスト: なし" bash -c "grep -q '^- 層: data,logic' '$D/CLAUDE.md' && grep -q '^- テスト: なし' '$D/CLAUDE.md'"
check "XML が正しい" xml_ok "$D"

echo "== 3. MFC / logic,data / テストあり (既存の GoogleTest をコピー)"
D="$WORK/R/Full"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc --layers logic,data --tests gtest >"$WORK/out3.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "作成が成功" || { ng "作成が成功 (rc=$rc)"; cat "$WORK/out3.txt"; }
check "プロジェクトは 5 つ" bash -c "[ $(nprojects "$D/Full.slnx") -eq 5 ]"
check "DataLayerTest と LogicLayerTest がある" bash -c "[ -f '$D/DataLayerTest/DataLayerTest.vcxproj' ] && [ -f '$D/LogicLayerTest/LogicLayerTest.vcxproj' ]"
check "GoogleTest が、packages\\ にコピーされた" test -f "$D/packages/$ID.1.8.1.8/build/native/$ID.targets"
check "出力に GTEST_PACKAGE: copied" grep -q 'GTEST_PACKAGE: copied from' "$WORK/out3.txt"
check "CLAUDE.md: テスト: あり" grep -q '^- テスト: あり (GoogleTest)' "$D/CLAUDE.md"
check "名前が Test で終わらないメインは、TargetName を変えない" bash -c "! grep -q TargetName '$D/Full/Full.vcxproj'"
check "XML が正しい" xml_ok "$D"

echo "== 4. DLL がメイン / 層なし / テストあり"
D="$WORK/R/MainDll"; mkdir -p "$D"
rc_is 0 "作成が成功" python3 "$NEW" "$D" --type dll --layers none --tests gtest
check "プロジェクトは 2 つ (メイン DLL + MainDllTest)" bash -c "[ $(nprojects "$D/MainDll.slnx") -eq 2 ]"
check "メインは DLL で、公開マクロがある" bash -c "grep -q DynamicLibrary '$D/MainDll/MainDll.vcxproj' && grep -q MAINDLL_API '$D/MainDll/MainDllApi.h'"
check "テストは、メイン DLL をプロジェクト参照" grep -q 'ProjectReference Include="..\\MainDll\\MainDll.vcxproj"' "$D/MainDllTest/MainDllTest.vcxproj"

echo "== 5. 名前が Test で終わる exe のメイン (MFCTDDTest) + テスト"
D="$WORK/R/MFCTDDTest"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc --layers logic --tests gtest >"$WORK/out5.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "作成が成功" || { ng "作成が成功 (rc=$rc)"; cat "$WORK/out5.txt"; }
check "メインに <TargetName>\$(ProjectName)_Main がある" grep -q '<TargetName>$(ProjectName)_Main</TargetName>' "$D/MFCTDDTest/MFCTDDTest.vcxproj"
check "テスト exe (LogicLayerTest) には、付かない" bash -c "! grep -q TargetName '$D/LogicLayerTest/LogicLayerTest.vcxproj'"
check "メインの vcxproj が XML として正しい" xml_ok "$D"
check "名前空間の既定 (大文字の頭文字)" grep -q 'namespace mfctddt' "$D/LogicLayer/LogicLayerModuleInfo.h"

echo "== 6. 矛盾する組み合わせ・不正な入力"
mkdir -p "$WORK/R/Bad1"; rc_is 2 "exe + 層なし + テストあり -> rc 2" python3 "$NEW" "$WORK/R/Bad1" --type console --layers none --tests gtest
[ ! -e "$WORK/R/Bad1/Bad1.slnx" ] && ok "  何も書いていない" || ng "  何も書いていない"
mkdir -p "$WORK/R/Bad2"; rc_is 2 "--tests の省略 -> rc 2" python3 "$NEW" "$WORK/R/Bad2" --type console --layers none
mkdir -p "$WORK/R/Bad3"; rc_is 2 "--layers の値が不正 -> rc 2" python3 "$NEW" "$WORK/R/Bad3" --type mfc --layers other --tests none
mkdir -p "$WORK/R/bad name"; rc_is 2 "フォルダ名が不正 -> rc 2" python3 "$NEW" "$WORK/R/bad name" --type mfc --layers none --tests none
rc_is 2 "親フォルダもない -> rc 2" python3 "$NEW" "$WORK/none/none/Sample" --type mfc --layers none --tests none
mkdir -p "$WORK/R/Keep"; echo mine > "$WORK/R/Keep/CLAUDE.md"
python3 "$NEW" "$WORK/R/Keep" --type console --layers none --tests none >/dev/null 2>&1; grep -q mine "$WORK/R/Keep/CLAUDE.md" && ok "既存の CLAUDE.md を上書きしない" || ng "既存の CLAUDE.md を上書きしない"
mkdir -p "$WORK/R/Nogtest"; python3 "$NEW" "$WORK/R/Nogtest" --type dll --layers none --tests gtest --gtest-from "$WORK/nonexistent" >"$WORK/out6.txt" 2>&1
check "コピー元がなくても成功し、missing と案内する" bash -c "grep -q 'GTEST_PACKAGE: copied' '$WORK/out6.txt' || grep -q 'GTEST_PACKAGE: missing' '$WORK/out6.txt'"
mkdir -p "$WORK/Q/Lonely"; python3 "$NEW" "$WORK/Q/Lonely" --type dll --layers none --tests gtest --gtest nuget >"$WORK/out6b.txt" 2>&1
check "--gtest nuget で、兄弟に GoogleTest がなければ、missing" grep -q 'GTEST_PACKAGE: missing' "$WORK/out6b.txt"
mkdir -p "$WORK/Q/Lonely2"; python3 "$NEW" "$WORK/Q/Lonely2" --type dll --layers none --tests gtest >"$WORK/out6c.txt" 2>&1
check "auto: コピーできなければ source (to-fetch)" bash -c "grep -q 'GTEST_MODE: source' '$WORK/out6c.txt' && grep -q 'GTEST_SOURCE: to-fetch' '$WORK/out6c.txt'"

echo "== 7. テストの後付け (--tests gtest の再実行)"
D="$WORK/R/LateTest"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc --layers logic,data --tests none >/dev/null 2>&1
python3 "$NEW" "$D" --tests gtest --dry-run >/dev/null 2>&1 && [ ! -e "$D/LogicLayerTest" ] && ok "dry-run は、何も書かない" || ng "dry-run は、何も書かない"
python3 "$NEW" "$D" --tests gtest >"$WORK/out7.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "後付けが成功" || { ng "後付けが成功 (rc=$rc)"; cat "$WORK/out7.txt"; }
check "DataLayerTest と LogicLayerTest が増えた (計 5 プロジェクト)" bash -c "[ -f '$D/DataLayerTest/DataLayerTest.vcxproj' ] && [ -f '$D/LogicLayerTest/LogicLayerTest.vcxproj' ] && [ $(nprojects "$D/LateTest.slnx") -eq 5 ]"
check "CLAUDE.md が、テスト: あり に更新された" grep -q '^- テスト: あり (GoogleTest)' "$D/CLAUDE.md"
check "ロジックのテストが、データ層のヘッダを参照 (既存の DLL から読み取り)" grep -q 'ProjectDir)..\\DataLayer' "$D/LogicLayerTest/LogicLayerTest.vcxproj"
check "既存の名前空間を、DLL のヘッダから読み取る" grep -q 'namespace lt' "$D/LogicLayer/LogicLayerModuleInfo.h"
check "XML が正しい" xml_ok "$D"
rc_is 2 "もう一度 --tests gtest -> テストを足せる DLL がない (rc 2)" python3 "$NEW" "$D" --tests gtest
rc_is 2 "後付けに --type は指定できない (rc 2)" python3 "$NEW" "$D" --tests gtest --type mfc

D="$WORK/R/NoDllTest"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers none --tests none >/dev/null 2>&1
rc_is 2 "exe だけのソリューションに --tests gtest -> rc 2 (層を先に作る)" python3 "$NEW" "$D" --tests gtest

D="$WORK/R/LateTestTest"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic --tests none >/dev/null 2>&1
python3 "$NEW" "$D" --tests gtest >/dev/null 2>&1
check "後付けでも、名前が Test で終わるメインを保護する" grep -q '<TargetName>$(ProjectName)_Main</TargetName>' "$D/LateTestTest/LateTestTest.vcxproj"

echo "== 8. 静的ライブラリ (--type lib)"
D="$WORK/R/MainLib"; mkdir -p "$D"
python3 "$NEW" "$D" --type lib --layers none --tests gtest >"$WORK/out8.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "lib / 層なし / テストあり: 作成が成功" || { ng "lib / 層なし / テストあり: 作成が成功 (rc=$rc)"; cat "$WORK/out8.txt"; }
check "メインは StaticLibrary" grep -q '<ConfigurationType>StaticLibrary</ConfigurationType>' "$D/MainLib/MainLib.vcxproj"
check "静的ライブラリに、<Link> がない" bash -c "! grep -q '<Link>' '$D/MainLib/MainLib.vcxproj'"
check "公開マクロ (Api.h) がない" bash -c "[ ! -e '$D/MainLib/MainLibApi.h' ] && ! grep -q '_API' '$D/MainLib/MainLibModuleInfo.h'"
check "プロジェクトは 2 つ (メイン lib + MainLibTest)" bash -c "[ $(nprojects "$D/MainLib.slnx") -eq 2 ]"
check "テストは、ライブラリをプロジェクト参照" grep -q 'ProjectReference Include="..\\MainLib\\MainLib.vcxproj"' "$D/MainLibTest/MainLibTest.vcxproj"
check "テストはコンソール exe" grep -q '<ConfigurationType>Application</ConfigurationType>' "$D/MainLibTest/MainLibTest.vcxproj"
check "CLAUDE.md: メインが静的ライブラリ" grep -q '^- メイン: MainLib (静的ライブラリ)' "$D/CLAUDE.md"
check "XML が正しい" xml_ok "$D"

D="$WORK/R/LibLayers"; mkdir -p "$D"
rc_is 0 "lib / logic,data / テストあり: 作成が成功" python3 "$NEW" "$D" --type lib --layers logic,data --tests gtest
check "プロジェクトは 6 つ (lib + 2 層 + 3 テスト)" bash -c "[ $(nprojects "$D/LibLayers.slnx") -eq 6 ]"
check "層は DLL のまま" grep -q DynamicLibrary "$D/LogicLayer/LogicLayer.vcxproj"

D="$WORK/R/LibLate"; mkdir -p "$D"
python3 "$NEW" "$D" --type lib --layers none --tests none >/dev/null 2>&1
rc_is 0 "lib の、テストの後付け" python3 "$NEW" "$D" --tests gtest
check "LibLateTest ができ、既存の名前空間を使う" bash -c "[ -f '$D/LibLateTest/LibLateTest.vcxproj' ] && grep -q 'll::LibLateModuleName' '$D/LibLateTest/TestLibLateModuleInfo.cpp'"
rc_is 2 "exe + 層なしは、依然として、後付けできない" bash -c "mkdir -p '$WORK/R/ExeOnly2' && python3 '$NEW' '$WORK/R/ExeOnly2' --type win32 --layers none --tests none && python3 '$NEW' '$WORK/R/ExeOnly2' --tests gtest"

echo "== 9. GoogleTest のソース方式 (--gtest source)"
D="$WORK/Q/SrcMode"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc --layers logic,data --tests gtest --gtest source >"$WORK/out9.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "source 方式で作成が成功" || { ng "source 方式で作成が成功 (rc=$rc)"; cat "$WORK/out9.txt"; }
check "gtest プロジェクトが 1 つ (計 6 プロジェクト: メイン + 2 層 + 2 テスト + gtest)" bash -c "[ -f '$D/gtest/gtest.vcxproj' ] && [ $(nprojects "$D/SrcMode.slnx") -eq 6 ]"
check "テストは、gtest を参照し、NuGet を使わない" bash -c "grep -q 'gtest.vcxproj' '$D/LogicLayerTest/LogicLayerTest.vcxproj' && [ ! -e '$D/LogicLayerTest/packages.config' ] && [ ! -e '$D/packages' ]"
check "出力に GTEST_SOURCE: to-fetch" grep -q 'GTEST_SOURCE: to-fetch' "$WORK/out9.txt"
check "CLAUDE.md に、ソース方式の説明" grep -q 'ThirdParty' "$D/CLAUDE.md"
check ".gitignore に ThirdParty/googletest/" grep -q 'ThirdParty/googletest/' "$D/.gitignore"
check ".gitignore に、ウォッチャーの一時ファイル (.claude-logs/ と *_result.txt など)" bash -c "grep -q '^\.claude-logs/$' '$D/.gitignore' && grep -q '^test_result.txt$' '$D/.gitignore' && grep -q '^trigger_\*.flag$' '$D/.gitignore'"
check "XML が正しい" xml_ok "$D"
D="$WORK/Q/SrcLate"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic --tests none >/dev/null 2>&1
python3 "$NEW" "$D" --tests gtest --gtest source >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "source 方式の後付け" || ng "source 方式の後付け (rc=$rc)"
check "後付けで gtest と LogicLayerTest が増え、CLAUDE.md がソース方式になる" bash -c "[ -f '$D/gtest/gtest.vcxproj' ] && [ -f '$D/LogicLayerTest/LogicLayerTest.vcxproj' ] && grep -q 'ThirdParty' '$D/CLAUDE.md'"

echo "== 10. 層の種類 (--layer-kind lib) と、層の名前"
D="$WORK/Q/LayerLib"; mkdir -p "$D"
rc_is 0 "層を静的ライブラリで作成" python3 "$NEW" "$D" --type console --layers logic,data --layer-kind lib --tests gtest --gtest nuget
check "層が StaticLibrary (公開マクロなし)" bash -c "grep -q StaticLibrary '$D/LogicLayer/LogicLayer.vcxproj' && grep -q StaticLibrary '$D/DataLayer/DataLayer.vcxproj' && [ ! -e '$D/DataLayer/DataLayerApi.h' ]"
check "テストは、ライブラリをプロジェクト参照" grep -q 'ProjectReference Include="..\\LogicLayer\\LogicLayer.vcxproj"' "$D/LogicLayerTest/LogicLayerTest.vcxproj"
check "CLAUDE.md: 静的ライブラリ" grep -q '静的ライブラリ' "$D/CLAUDE.md"
D="$WORK/Q/Named"; mkdir -p "$D"
rc_is 0 "層の名前を指定して作成" python3 "$NEW" "$D" --type mfc --layers logic:OrderLogic,data:OrderData --tests gtest --gtest nuget
check "OrderLogic / OrderData / OrderLogicTest / OrderDataTest ができる" bash -c "[ -f '$D/OrderLogic/OrderLogic.vcxproj' ] && [ -f '$D/OrderData/OrderData.vcxproj' ] && [ -f '$D/OrderLogicTest/OrderLogicTest.vcxproj' ] && [ -f '$D/OrderDataTest/OrderDataTest.vcxproj' ] && [ ! -e '$D/LogicLayer' ]"
check "ロジックは、指定した名前のデータ層を参照" grep -q 'ProjectDir)..\\OrderData' "$D/OrderLogic/OrderLogic.vcxproj"
check "CLAUDE.md: 名前つきで記録" grep -q '^- 層: data:OrderData,logic:OrderLogic' "$D/CLAUDE.md"
mkdir -p "$WORK/Q/BadName"; rc_is 2 "層の名前が不正 -> rc 2" python3 "$NEW" "$WORK/Q/BadName" --type mfc --layers 'logic:bad-name' --tests none
mkdir -p "$WORK/Q/Dup"; rc_is 2 "層の名前が重複 -> rc 2" python3 "$NEW" "$WORK/Q/Dup" --type mfc --layers logic:Same,data:Same --tests none

echo "== 11. 構成案から (--spec)"
mkdir -p "$WORK/Q/SpecA/docs/specs"
cat > "$WORK/Q/SpecA/docs/specs/tax.md" <<'SPEC'
# tax

- 状態: 確定

## 目的
税込み合計

## 構成案 (ソリューションがまだないときだけ)
- メインの種類: console (画面なしのため)
- 層: logic,data (計算と保存)
- 層の種類: dll
- テスト: gtest (TDD の練習)
- 名前空間: tdd

## 変更履歴
SPEC
D="$WORK/Q/SpecA"
python3 "$NEW" "$D" --spec docs/specs/tax.md --dry-run >"$WORK/out11.txt" 2>&1; rc=$?
cd "$D" && python3 "$NEW" "$D" --spec "$D/docs/specs/tax.md" --gtest nuget --dry-run >"$WORK/out11.txt" 2>&1; rc=$?; cd "$REPO"
[ "$rc" -eq 0 ] && ok "構成案から、dry-run が成功" || { ng "構成案から、dry-run が成功 (rc=$rc)"; cat "$WORK/out11.txt"; }
check "構成案の内容が、反映される (console / 2 層 / テスト / tdd)" bash -c "grep -q 'メイン .*コンソール' '$WORK/out11.txt' && grep -q 'テスト .*あり' '$WORK/out11.txt' && grep -q '名前空間 .*tdd' '$WORK/out11.txt'"
check "dry-run は、何も書かない" bash -c "[ ! -e '$D/SpecA.slnx' ]"
python3 "$NEW" "$D" --spec "$D/docs/specs/tax.md" --tests none --layers none --dry-run >"$WORK/out11b.txt" 2>&1
check "明示した引数が、構成案より優先される" grep -q 'テスト .*なし' "$WORK/out11b.txt"
rc_is 0 "構成案から、作成が成功" python3 "$NEW" "$D" --spec "$D/docs/specs/tax.md" --gtest nuget
check "作成された (3 層 + 2 テスト)" bash -c "[ -f '$D/SpecA.slnx' ] && [ -f '$D/LogicLayerTest/LogicLayerTest.vcxproj' ]"

mkdir -p "$WORK/Q/SpecB"; printf '# x\n\n## 目的\nfoo\n' > "$WORK/Q/SpecB/x.md"
rc_is 2 "構成案の節がない -> rc 2" python3 "$NEW" "$WORK/Q/SpecB" --spec "$WORK/Q/SpecB/x.md"
mkdir -p "$WORK/Q/SpecC"; printf '## 構成案\n- メインの種類: mfc\n- 層: none\n- テスト: 未定\n' > "$WORK/Q/SpecC/x.md"
python3 "$NEW" "$WORK/Q/SpecC" --spec "$WORK/Q/SpecC/x.md" >"$WORK/out11c.txt" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q -- '--tests' "$WORK/out11c.txt" && ok "テストが「未定」なら、--tests が足りないとして止まる (質問する)" || ng "テストが「未定」 (rc=$rc)"
mkdir -p "$WORK/Q/SpecD"; printf '## 構成案\n- メインの種類: spreadsheet\n' > "$WORK/Q/SpecD/x.md"
rc_is 2 "構成案の値が不正 -> rc 2" python3 "$NEW" "$WORK/Q/SpecD" --spec "$WORK/Q/SpecD/x.md"

echo "== 12. .gitattributes (改行コードの規則)"
D="$WORK/Q/GitAttr"; mkdir -p "$D"
rc_is 0 "新規作成が成功" python3 "$NEW" "$D" --type console --layers none --tests none
check ".gitattributes が作られる" test -f "$D/.gitattributes"
check "最小の規則: * text=auto eol=crlf" grep -q '^\* text=auto eol=crlf$' "$D/.gitattributes"
check "拡張子を列挙しない (例外の *.sh の 1 行だけ)" bash -c "[ \$(grep -c '^\*\.' '$D/.gitattributes') -eq 1 ] && grep -q '^\*\.sh text eol=lf$' '$D/.gitattributes'"
check ".gitattributes 自身は LF、BOM なし" bash -c "! grep -q \$'\r' '$D/.gitattributes' && ! head -c3 '$D/.gitattributes' | xxd -p | grep -q efbbbf && grep -q '^\.gitattributes text eol=lf$' '$D/.gitattributes'"
mkdir -p "$WORK/Q/GitAttrKeep"; echo '# mine' > "$WORK/Q/GitAttrKeep/.gitattributes"
python3 "$NEW" "$WORK/Q/GitAttrKeep" --type console --layers none --tests none >/dev/null 2>&1
check "既存の .gitattributes を上書きしない" bash -c "[ \"\$(cat '$WORK/Q/GitAttrKeep/.gitattributes')\" = '# mine' ]"
D="$WORK/Q/GitAttrLate"; mkdir -p "$D"
python3 "$NEW" "$D" --type console --layers logic --tests none >/dev/null 2>&1
rm -f "$D/.gitattributes"
python3 "$NEW" "$D" --tests gtest >/dev/null 2>&1
check "テストの後付けでは、.gitattributes を作らない (提案のみの方針)" test ! -e "$D/.gitattributes"
python3 "$NEW" "$WORK/Q/GitAttr" --type console --layers none --tests none --dry-run >/dev/null 2>&1
mkdir -p "$WORK/Q/GitAttrDry"; python3 "$NEW" "$WORK/Q/GitAttrDry" --type console --layers none --tests none --dry-run >"$WORK/out12.txt" 2>&1
check "dry-run の一覧に .gitattributes がある" grep -q '+ .gitattributes' "$WORK/out12.txt"

# 実際の git で、規則どおりに動くか (WSL の git: autocrlf 未設定でも、.gitattributes が効く)
if command -v git >/dev/null 2>&1; then
    G="$WORK/Q/GitRepo"; mkdir -p "$G"; cp "$WORK/Q/GitAttr/.gitattributes" "$G/"
    ( cd "$G" && git init -q . >/dev/null 2>&1
      printf 'int a;\r\nint b;\r\n' > crlf.cpp
      printf 'int a;\nint b;\n' > lf.cpp
      printf '#!/bin/sh\r\necho x\r\n' > run.sh
      printf 'x\r\ny\r\n' > newtype.xyz2
      printf '\x89PNG\x00\x01\r\n\x02' > image.bin
      git -c core.autocrlf=false add -A >/dev/null 2>&1
      git ls-files --eol > "$WORK/eol.txt" )
    [ -n "${DEBUG_EOL:-}" ] && cat "$WORK/eol.txt"
    check "git: CRLF の .cpp は、LF で保存される (作業フォルダは CRLF)" grep -Eq 'i/lf +w/crlf +attr/text=auto eol=crlf.*crlf.cpp' "$WORK/eol.txt"
    check "git: LF の .cpp も、LF で保存される" grep -Eq 'i/lf +w/lf +attr/text=auto eol=crlf.*lf.cpp' "$WORK/eol.txt"
    check "git: 列挙していない新しい拡張子 (.xyz2) も、テキストとして扱われる" grep -Eq 'i/lf +w/crlf .*newtype.xyz2' "$WORK/eol.txt"
    check "git: .sh は、保存が LF (例外。作業フォルダの CRLF は、次の checkout で LF になる)" grep -Eq 'i/lf +w/(crlf|lf) +attr/text eol=lf.*run.sh' "$WORK/eol.txt"
    check "git: バイナリは、変換されない" grep -Eq 'i/-text +w/-text .*image.bin' "$WORK/eol.txt"
else
    echo "SKIP  git がないので、git での確認は、省略"
fi

echo "== 13. 既存プロジェクトの、改行コードの規則の検出と提案 (--check-git / --add-gitattributes)"
if command -v git >/dev/null 2>&1; then
    first() { python3 "$NEW" "$@" 2>&1 | head -n 1; }
    # a. リポジトリではない
    mkdir -p "$WORK/Q/NoRepo"; [ "$(first "$WORK/Q/NoRepo" --check-git)" = "GITATTRIBUTES: not-a-repo" ] && ok "リポジトリではない -> not-a-repo" || ng "リポジトリではない -> not-a-repo"
    # b. CRLF のファイルがあり、規則がない -> propose
    R="$WORK/Q/GitCrlf"; mkdir -p "$R"
    ( cd "$R" && git init -q . && printf 'int a;\r\nint b;\r\n' > a.cpp && printf '<P/>\r\n' > a.vcxproj && git -c core.autocrlf=false add -A )
    python3 "$NEW" "$R" --check-git > "$WORK/chk_b.txt" 2>&1
    [ "$(head -n 1 "$WORK/chk_b.txt")" = "GITATTRIBUTES: propose" ] && ok "CRLF あり + 規則なし -> propose" || { ng "CRLF あり + 規則なし -> propose"; cat "$WORK/chk_b.txt"; }
    check "  提案の内容 (最小版) と、導入の手順が出る" bash -c "grep -q 'text=auto eol=crlf' '$WORK/chk_b.txt' && grep -q 'git add --renormalize' '$WORK/chk_b.txt'"
    check "  CRLF の件数が出る" grep -Eq '保存が CRLF=2' "$WORK/chk_b.txt"
    # 読み取りだけ: 何も作らない・変えない
    check "  --check-git は、何も作らない" bash -c "[ ! -e '$R/.gitattributes' ] && [ \$(cd '$R' && git status --porcelain | wc -l) -eq 2 ]"
    # c. LF のみ
    L="$WORK/Q/GitLf"; mkdir -p "$L"
    ( cd "$L" && git init -q . && printf 'int a;\nint b;\n' > a.cpp && git -c core.autocrlf=false add -A )
    [ "$(first "$L" --check-git)" = "GITATTRIBUTES: lf-only" ] && ok "LF のみ -> lf-only (提案しない)" || ng "LF のみ -> lf-only"
    # d. 見送りの記録
    mkdir -p "$WORK/Q/GitDecl"; D2="$WORK/Q/GitDecl"
    ( cd "$D2" && git init -q . && printf 'x\r\n' > a.cpp && git -c core.autocrlf=false add -A ) ; printf '# x\n- 改行コードの提案: 見送り\n' > "$D2/CLAUDE.md"
    [ "$(first "$D2" --check-git)" = "GITATTRIBUTES: declined" ] && ok "見送りの記録 -> declined (提案しない)" || ng "見送りの記録 -> declined"
    # e. 追加 -> ok
    rc_is 0 "--add-gitattributes で作成" python3 "$NEW" "$R" --add-gitattributes
    check "  最小版が作られる" bash -c "grep -q '^\* text=auto eol=crlf$' '$R/.gitattributes'"
    rc_is 3 "  すでにあれば、上書きしない (rc 3)" python3 "$NEW" "$R" --add-gitattributes
    [ "$(first "$R" --check-git)" = "GITATTRIBUTES: ok" ] && ok "追加後は ok" || ng "追加後は ok"
    check "  git の操作はしていない (ステージされていない)" bash -c "cd '$R' && ! git status --porcelain | grep -q '^A  .gitattributes' && git status --porcelain | grep -q '?? .gitattributes'"
    # f. 既存の規則 (別の形) があれば ok
    A="$WORK/Q/GitHas"; mkdir -p "$A"
    ( cd "$A" && git init -q . && printf '*.cpp text eol=crlf\n' > .gitattributes && printf 'x\r\n' > a.cpp && git -c core.autocrlf=false add -A )
    [ "$(first "$A" --check-git)" = "GITATTRIBUTES: ok" ] && ok "自分で書いた規則がある -> ok" || ng "自分で書いた規則がある -> ok"
    # g. /new-solution が作ったプロジェクトは、最初から ok
    N="$WORK/Q/GitNew"; mkdir -p "$N"
    python3 "$NEW" "$N" --type console --layers none --tests none >/dev/null 2>&1
    ( cd "$N" && git init -q . && git -c core.autocrlf=false add -A )
    [ "$(first "$N" --check-git)" = "GITATTRIBUTES: ok" ] && ok "/new-solution で作った直後 -> ok" || ng "/new-solution で作った直後 -> ok"
    rc_is 2 "存在しないフォルダ -> rc 2" python3 "$NEW" "$WORK/nonexistent_dir" --check-git
else
    echo "SKIP  git がないので、検出の確認は、省略"
fi

echo "== MFC の種類 (SDI / MDI / ダイアログベース)"
MFC_CHK="$REPO/skills/mfc-check/scripts/mfc_check.py"
for t in mfc mfc-mdi mfc-dialog; do
    D="$WORK/R/V_${t//-/_}"; mkdir -p "$D"
    rc_is 0 "$t: 作成が成功" python3 "$NEW" "$D" --type "$t" --layers logic,data --tests none
    check "$t: XML が正しい" xml_ok "$D"
    check "$t: .vcxproj は MFC (UseOfMfc) と、.rc を持つ" bash -c "grep -q UseOfMfc '$D/V_${t//-/_}/V_${t//-/_}.vcxproj' && grep -q 'V_${t//-/_}.rc' '$D/V_${t//-/_}/V_${t//-/_}.vcxproj'"
    check "$t: .rc は、BOM なし・CRLF" bash -c "f='$D/V_${t//-/_}/V_${t//-/_}.rc'; ! head -c3 \"\$f\" | grep -q \$'\\xef\\xbb\\xbf' && grep -q \$'\\r' \"\$f\""
    check "$t: CLAUDE.md の種類の表記" bash -c "grep -q '^- メイン: V_${t//-/_} (MFC' '$D/CLAUDE.md'"
    check "$t: mfc-check が、error / warning 0" bash -c "python3 '$MFC_CHK' '$D' --all | grep -q 'error 0 / warning 0'"
done
check "exe のメイン: .slnx で、メインだけに DefaultStartup" bash -c "[ \$(grep -c 'DefaultStartup=\"true\"' '$WORK/R/V_mfc_mdi/V_mfc_mdi.slnx') -eq 1 ] && grep 'V_mfc_mdi/V_mfc_mdi.vcxproj' '$WORK/R/V_mfc_mdi/V_mfc_mdi.slnx' | grep -q DefaultStartup"
D="$WORK/R/V_dllmain"; mkdir -p "$D"; python3 "$NEW" "$D" --type dll --layers none --tests none >/dev/null 2>&1
check "DLL がメイン: DefaultStartup は付けない" bash -c "! grep -q DefaultStartup '$D/V_dllmain.slnx'"
check "層がある exe: CLAUDE.md に、スタートアッププロジェクトの注意" bash -c "grep -q 'スタートアッププロジェクト' '$WORK/R/V_mfc_mdi/CLAUDE.md'"
check "mfc-mdi: CMultiDocTemplate と、MDI の枠" bash -c "grep -q CMultiDocTemplate '$WORK/R/V_mfc_mdi/V_mfc_mdi/SampleApp.cpp' && grep -q CMDIFrameWnd '$WORK/R/V_mfc_mdi/V_mfc_mdi/MainFrame.h' && grep -q CMDIChildWnd '$WORK/R/V_mfc_mdi/V_mfc_mdi/ChildFrame.h'"
check "mfc-dialog: ダイアログ (IDD) と、DoModal" bash -c "grep -q 'IDD_SAMPLE_DIALOG' '$WORK/R/V_mfc_dialog/V_mfc_dialog/V_mfc_dialog.rc' && grep -q DoModal '$WORK/R/V_mfc_dialog/V_mfc_dialog/SampleApp.cpp'"
check "mfc-dialog: ドキュメント・ビューは、作らない" bash -c "[ ! -e '$WORK/R/V_mfc_dialog/V_mfc_dialog/SampleDoc.h' ]"
mkdir -p "$WORK/R/V_Bad"; rc_is 2 "不明な種類 -> rc 2" python3 "$NEW" "$WORK/R/V_Bad" --type mfc-wizard --layers none --tests none
mkdir -p "$WORK/R/V_Spec"; printf '## 構成案\n- メインの種類: mfc-mdi\n- 層: none\n- テスト: none\n' > "$WORK/R/V_Spec/x.md"
rc_is 0 "--spec で mfc-mdi を読める" python3 "$NEW" "$WORK/R/V_Spec" --spec "$WORK/R/V_Spec/x.md"
check "層がない exe: 注意は書かない" bash -c "! grep -q 'スタートアッププロジェクト' '$WORK/R/V_Spec/CLAUDE.md'"
D="$WORK/R/V_dlgtests"; mkdir -p "$D"
python3 "$NEW" "$D" --type mfc-dialog --layers logic --tests gtest --gtest nuget >/dev/null 2>&1
check "mfc-dialog + テスト: テストのプロジェクトができる" test -f "$D/LogicLayerTest/LogicLayerTest.vcxproj"

echo
if [ "$fail" -eq 0 ]; then echo "すべて OK"; else echo "失敗あり"; fi
exit "$fail"
