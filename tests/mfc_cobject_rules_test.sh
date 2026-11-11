#!/usr/bin/env bash
# mfc_cobject_rules_test.sh - mfc-check の NSP001 / DEC001 (v2.89.0): CObject 派生のクラスを、名前空間に入れない・DECLARE_DYNAMIC などを書く、の検証 (Windows 不要)。
# Usage: tests/mfc_cobject_rules_test.sh      終了コード: 0 すべて OK / 1 失敗あり
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$ROOT/skills"
W="$(mktemp -d "${TMPDIR:-/tmp}/cobj.XXXXXX")"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
chk() { python3 "$SK/mfc-check/scripts/mfc_check.py" "$1" 2>&1; }

mkdir -p "$W/a"
cat > "$W/a/classes.h" <<'H'
#pragma once
#include "pch.h"

namespace app
{
    class CInNs : public CDialog                 // NSP001: 名前空間の中の CObject 派生
    {
        DECLARE_DYNAMIC(CInNs)
    };

    class PlainLogic                              // 名前空間の中でも、CObject 派生でないので、指摘なし
    {
    public:
        int Value() const { return 1; }
    };
}

class CNoDecl : public CObject                    // DEC001: DECLARE がない
{
};

class CBaseView : public CView                    // DECLARE_DYNCREATE があるので、指摘なし
{
    DECLARE_DYNCREATE(CBaseView)
};

class CDerivedView : public CBaseView             // DEC001: 基底 (プロジェクト内) をたどって、CObject 派生。DECLARE がない
{
};

class CSerial : public CObject                    // DECLARE_SERIAL があるので、指摘なし
{
    DECLARE_SERIAL(CSerial)
};

class CMyApp : public CWinApp                     // CWinApp 派生は、DECLARE がなくてよい
{
public:
    BOOL InitInstance() override;
};
H
out="$(chk "$W/a")"
ok "NSP001: a CObject-derived class inside a namespace is a warning (CInNs)" "$(echo "$out" | grep -q 'NSP001.*CInNs' && echo 1 || echo 0)"
ok "NSP001: a plain (non-CObject) class inside a namespace is not reported" "$(echo "$out" | grep -q 'NSP001.*PlainLogic' && echo 0 || echo 1)"
ok "DEC001: a CObject-derived class without DECLARE_* is a warning (CNoDecl)" "$(echo "$out" | grep -q 'DEC001.*CNoDecl' && echo 1 || echo 0)"
ok "DEC001: found through a base class in the project (CDerivedView : CBaseView : CView)" "$(echo "$out" | grep -q 'DEC001.*CDerivedView' && echo 1 || echo 0)"
ok "DEC001: not reported for classes with DECLARE_DYNCREATE / DECLARE_SERIAL / DECLARE_DYNAMIC" "$(echo "$out" | grep 'DEC001' | grep -q 'CBaseView\|CSerial\|CInNs' && echo 0 || echo 1)"
ok "DEC001: CWinApp-derived class is exempt" "$(echo "$out" | grep 'DEC001' | grep -q 'CMyApp' && echo 0 || echo 1)"
ok "both are warnings, not errors (exit code 0 when there is no error)" "$(python3 "$SK/mfc-check/scripts/mfc_check.py" "$W/a" >/dev/null 2>&1; [ $? = 0 ] && echo 1 || echo 0)"

# 生成物: MFC の 3 種類のメイン (SDI・MDI・ダイアログ) と、画面ホストは、指摘なし
for ty in mfc mfc-mdi mfc-dialog; do
  n="app_${ty//-/_}"
  python3 "$SK/new-solution/scripts/new_solution.py" "$W/$n" --type "$ty" --layers logic --tests none --layer-kind mfc-std-dll >/dev/null 2>&1
  ok "generated $ty solution: mfc-check reports no NSP001 / DEC001" "$(chk "$W/$n" | grep -q 'NSP001\|DEC001' && echo 0 || echo 1)"
done
python3 "$SK/cpp-test-first/scripts/add_ui_host.py" "$W/app_mfc_dialog" --name UiLayer --kind mfc-std-dll --logic none >/dev/null 2>&1
ok "generated UI host dialog (GreetingDialog) has DECLARE_DYNAMIC / IMPLEMENT_DYNAMIC and no NSP001 / DEC001" "$(grep -q 'DECLARE_DYNAMIC(GreetingDialog)' "$W/app_mfc_dialog/UiLayer/GreetingDialog.h" && grep -q 'IMPLEMENT_DYNAMIC(GreetingDialog, CDialog)' "$W/app_mfc_dialog/UiLayer/GreetingDialog.cpp" && ! chk "$W/app_mfc_dialog" | grep -q 'NSP001\|DEC001' && echo 1 || echo 0)"
ok "generated CSampleDlg has DECLARE_DYNAMIC / IMPLEMENT_DYNAMIC" "$(grep -q 'DECLARE_DYNAMIC(CSampleDlg)' "$W/app_mfc_dialog/app_mfc_dialog/SampleDlg.h" && grep -q 'IMPLEMENT_DYNAMIC(CSampleDlg, CDialog)' "$W/app_mfc_dialog/app_mfc_dialog/SampleDlg.cpp" && echo 1 || echo 0)"
ok "NSP001 / DEC001 are documented (SKILL.md, rules/mfc-cpp.md)" "$(grep -q 'NSP001' "$SK/mfc-check/SKILL.md" && grep -q 'DEC001' "$SK/mfc-check/SKILL.md" && grep -q 'CObject 派生' "$ROOT/rules/mfc-cpp.md" && grep -q '名前空間' "$ROOT/rules/mfc-cpp.md" && echo 1 || echo 0)"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
