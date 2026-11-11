#!/usr/bin/env bash
# mfc_lib_test.sh - MFC の静的ライブラリ (mfc-lib。v2.87.0) の検証 (Windows 不要。プロジェクトファイルの生成と、参照の規則、mfc-check の LIB001)。
# Usage: tests/mfc_lib_test.sh      終了コード: 0 すべて OK / 1 失敗あり
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$ROOT/skills"
W="$(mktemp -d "${TMPDIR:-/tmp}/mfclib.XXXXXX")"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
has() { grep -q -F "$2" "$1" && echo 1 || echo 0; }

# --- 生成: MFC ダイアログのメイン + MFC の静的ライブラリの層 (ロジック・データ)
S="$W/app"
python3 "$SK/new-solution/scripts/new_solution.py" "$S" --type mfc-dialog --layers logic,data --tests gtest --layer-kind mfc-lib --gtest vcpkg >/dev/null 2>&1
ok "new-solution: --layer-kind mfc-lib creates LogicLayer / DataLayer as StaticLibrary with UseOfMfc=Dynamic" "$([ "$(grep -c '<ConfigurationType>StaticLibrary' "$S/LogicLayer/LogicLayer.vcxproj")" -ge 2 ] && [ "$(grep -c '<UseOfMfc>Dynamic' "$S/LogicLayer/LogicLayer.vcxproj")" -ge 2 ] && echo 1 || echo 0)"
ok "mfc-lib has no export macro / dllmain / _AFXEXT / _USRDLL" "$([ ! -f "$S/LogicLayer/LogicLayerApi.h" ] && [ ! -f "$S/LogicLayer/dllmain.cpp" ] && ! grep -q '_AFXEXT\|_USRDLL' "$S/LogicLayer/LogicLayer.vcxproj" && echo 1 || echo 0)"
ok "mfc-lib uses pch.h (pch.cpp creates it, the module info includes it first)" "$([ -f "$S/LogicLayer/pch.h" ] && grep -q '#include "pch.h"' "$S/LogicLayer/LogicLayerModuleInfo.cpp" && grep -q 'Create' "$S/LogicLayer/LogicLayer.vcxproj" && echo 1 || echo 0)"
ok "the test exe of an mfc-lib layer uses the same shared MFC (UseOfMfc=Dynamic)" "$([ "$(grep -c '<UseOfMfc>Dynamic' "$S/LogicLayerTest/LogicLayerTest.vcxproj")" -ge 2 ] && echo 1 || echo 0)"
ok "CLAUDE.md describes the MFC static library (and LIB001)" "$(has "$S/CLAUDE.md" 'MFC の静的ライブラリ')"
ok "solution_state: the layers are kind mfc-lib; suggests referencing from the main" "$(python3 "$SK/add-project/scripts/solution_state.py" "$S" 2>&1 | grep -q 'PROJECT: LogicLayer | mfc-lib' && echo 1 || echo 0)"

# --- 拒否: MFC なしのメインでは、mfc-lib を指定できない
python3 "$SK/new-solution/scripts/new_solution.py" "$W/bad" --type console --layers logic --tests none --layer-kind mfc-lib >/dev/null 2>&1; rc=$?
ok "new-solution: --layer-kind mfc-lib with a non-MFC main is refused (exit 2) and writes nothing" "$([ "$rc" = 2 ] && [ ! -e "$W/bad" ] && echo 1 || echo 0)"

# --- 参照: MFC の exe と、MFC 標準 DLL から、MFC の静的ライブラリへ
python3 "$SK/add-project/scripts/add_reference.py" "$S" --from app --to LogicLayer >/dev/null 2>&1
ok "add_reference: an MFC exe can reference the MFC static library (ProjectReference)" "$(has "$S/app/app.vcxproj" 'LogicLayer.vcxproj')"
python3 "$SK/cpp-test-first/scripts/add_layer.py" "$S" StdLayer --kind mfc-std-dll --tests none --gtest vcpkg >/dev/null 2>&1
python3 "$SK/add-project/scripts/add_reference.py" "$S" --from StdLayer --to LogicLayer >/dev/null 2>&1
ok "add_reference: an MFC standard DLL can reference the MFC static library" "$(has "$S/StdLayer/StdLayer.vcxproj" 'LogicLayer.vcxproj')"
out="$(python3 "$SK/mfc-check/scripts/mfc_check.py" "$S" 2>&1 | tail -1)"
ok "mfc-check: no error for the exe and the MFC standard DLL that use the MFC static library" "$(echo "$out" | grep -q 'error 0' && echo 1 || echo 0)"

# --- 拒否: MFC なしの exe から、MFC の静的ライブラリへ
N="$W/nonmfc"
python3 "$SK/new-solution/scripts/new_solution.py" "$N" --type win32 --layers none --tests none >/dev/null 2>&1
python3 "$SK/cpp-test-first/scripts/add_layer.py" "$N" MfcLib --kind mfc-lib --tests none --gtest vcpkg >/dev/null 2>&1
out="$(python3 "$SK/add-project/scripts/add_reference.py" "$N" --from nonmfc --to MfcLib 2>&1)"; rc=$?
ok "add_reference: a non-MFC exe cannot reference an MFC static library (refused, exit 2, names LIB001)" "$([ "$rc" = 2 ] && echo "$out" | grep -q 'LIB001' && echo 1 || echo 0)"

# --- mfc-check の LIB001: UseOfMfc が違う参照
sed -i 's#<UseOfMfc>Dynamic</UseOfMfc>#<UseOfMfc>Static</UseOfMfc>#g' "$S/app/app.vcxproj"
out="$(python3 "$SK/mfc-check/scripts/mfc_check.py" "$S" 2>&1)"
ok "mfc-check LIB001: an exe with UseOfMfc=Static referencing a UseOfMfc=Dynamic MFC static library is an error" "$(echo "$out" | grep -q 'LIB001' && echo 1 || echo 0)"
ok "mfc-check LIB001 is documented in SKILL.md" "$(has "$SK/mfc-check/SKILL.md" 'LIB001')"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
