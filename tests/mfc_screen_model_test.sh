#!/usr/bin/env bash
# mfc_screen_model_test.sh - mfc-check の SCM001 / SCM002 / LAY004 (画面モデル): 画面モデルが、ウィンドウのラッパー・Document/View・HWND・リソース ID を使っていないか、
# ダイアログが、リポジトリを直接参照していないか、の検証 (Windows 不要)。
# Usage: tests/mfc_screen_model_test.sh      終了コード: 0 すべて OK / 1 失敗あり
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$ROOT/skills"
W="$(mktemp -d "${TMPDIR:-/tmp}/scm.XXXXXX")"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
chk() { python3 "$SK/mfc-check/scripts/mfc_check.py" "$1" 2>&1; }

mkdir -p "$W/a/ScreenModels"
# 許される: CString・コレクション・データ / モデルの CObject 派生
cat > "$W/a/ScreenModels/GreetingScreenModel.h" <<'H'
#pragma once
#include <afxtempl.h>

class GreetingData : public CObject
{
    DECLARE_DYNAMIC(GreetingData)
public:
    CString name;
};

class GreetingScreenModel
{
public:
    CString GetName() const { return m_name; }
    bool IsValid() const { return !m_name.IsEmpty(); }
private:
    CString m_name;
    CArray<CString> m_history;
};
H
# 許されない: ウィンドウのラッパー・HWND・リソース ID
cat > "$W/a/ScreenModels/BadScreenModel.h" <<'H'
#pragma once
#include <afxwin.h>

class BadScreenModel
{
public:
    void Bind(CWnd* wnd) { m_wnd = wnd; }
    void Alert() { AfxMessageBox(_T("x")); }
    int GetId() const { return IDC_NAME_EDIT; }
private:
    CWnd* m_wnd = nullptr;
    HWND m_hwnd = nullptr;
};
H
# フォルダに関係なく、名前が ScreenModel を含むクラス (インターフェースを含む)
cat > "$W/a/ReportScreen.h" <<'H'
#pragma once
class ReportScreenModelInterface
{
public:
    virtual void Fill(CEdit& edit) = 0;
};
H
# ダイアログが、リポジトリを直接参照している
cat > "$W/a/GreetingDlg.h" <<'H'
#pragma once
class CGreetingDlg : public CDialog
{
    DECLARE_DYNAMIC(CGreetingDlg)
public:
    explicit CGreetingDlg(GreetingRepositoryInterface& repo);
private:
    GreetingRepositoryInterface& m_repo;
};
H
# 正しいダイアログ: 画面モデルのインターフェース経由
cat > "$W/a/GoodDlg.h" <<'H'
#pragma once
class CGoodDlg : public CDialog
{
    DECLARE_DYNAMIC(CGoodDlg)
public:
    explicit CGoodDlg(GreetingScreenModelInterface& model);
private:
    GreetingScreenModelInterface& m_model;
};
H
# 組み立てる場所 (App) は、リポジトリを使ってよい
cat > "$W/a/MyApp.cpp" <<'H'
#include "pch.h"
BOOL CMyApp::InitInstance()
{
    auto* repo = new SqlGreetingRepository();
    return TRUE;
}
H
out="$(chk "$W/a")"
ok "SCM001: CWnd / HWND / AfxMessageBox in a ScreenModel file (BadScreenModel)" "$(echo "$out" | grep -A1 'SCM001' | grep -q 'BadScreenModel.h' && echo 1 || echo 0)"
ok "SCM001: a class named *ScreenModelInterface in any file (CEdit)" "$(echo "$out" | grep -A1 'SCM001' | grep -q 'ReportScreen.h' && echo 1 || echo 0)"
ok "SCM002: a resource ID (IDC_NAME_EDIT) in a ScreenModel file" "$(echo "$out" | grep -q 'SCM002.*IDC_NAME_EDIT' && echo 1 || echo 0)"
ok "SCM001 / SCM002: CString / CArray / CObject-derived data in GreetingScreenModel are allowed" "$(echo "$out" | grep -A1 'SCM00' | grep -q 'GreetingScreenModel.h' && echo 0 || echo 1)"
ok "LAY004: a dialog class refers to a Repository (GreetingDlg.h)" "$(echo "$out" | grep -q 'LAY004.*GreetingRepositoryInterface' && echo 1 || echo 0)"
ok "LAY004: a dialog using only the ScreenModel interface is not reported (GoodDlg.h)" "$(echo "$out" | grep -A1 'LAY004' | grep -q 'GoodDlg' && echo 0 || echo 1)"
ok "LAY004: the composition root (MyApp.cpp) may use a Repository" "$(echo "$out" | grep -A1 'LAY004' | grep -q 'MyApp' && echo 0 || echo 1)"
ok "all three are warnings, not errors (exit code 0 when there is no error)" "$(python3 "$SK/mfc-check/scripts/mfc_check.py" "$W/a" >/dev/null 2>&1; [ $? = 0 ] && echo 1 || echo 0)"
ok "SCM001 / SCM002 / LAY004 are documented (mfc-check SKILL.md, rules/mfc-cpp.md)" "$(grep -q 'SCM001' "$SK/mfc-check/SKILL.md" && grep -q 'SCM002' "$SK/mfc-check/SKILL.md" && grep -q 'LAY004' "$SK/mfc-check/SKILL.md" && grep -q 'SCM001' "$ROOT/rules/mfc-cpp.md" && echo 1 || echo 0)"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
