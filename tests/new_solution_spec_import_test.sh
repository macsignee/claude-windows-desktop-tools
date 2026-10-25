#!/usr/bin/env bash
# new_solution_spec_import_test.sh - new_solution.py --spec の、仕様書の取り込み (spec_import.py) と、構成案の拡張キー (UIテスト / TFM) を検証する。
# Windows も .NET も不要。
# Usage: tests/new_solution_spec_import_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
T="${TMPDIR:-/tmp}/nsspec_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }

# 仕様書 (表つき) を作る: spec_for <フォルダ> <構成案の行...>
spec_for() {
  local d="$1"; shift
  mkdir -p "$d/docs/specs" "$d/docs/ideas"
  {
    printf '# 税込み計算\n\n- 状態: 確定\n- 元: docs/ideas/tax.md\n\n'
    printf '## 具体例\n| 入力 | 期待する出力 | 補足 |\n|---|---|---|\n| 100円 x 3, 8%% | 324 | |\n| 0円 | 0 | 境界 |\n\n'
    printf '## 境界値と異常系\n| ケース | 振る舞い |\n|---|---|\n| 数量 0 | 例外 |\n|  |  |\n\n'
    printf '## 構成案\n'
    for l in "$@"; do printf -- '- %s\n' "$l"; done
  } > "$d/docs/specs/tax.md"
  echo memo > "$d/docs/ideas/tax.md"
}

# ---------------------------------------------------------------- WinForms: 拡張キー + 取り込み
D="$T/Wf"; spec_for "$D" 'メインの種類: winforms' '層: logic:OrderLogic,data' 'テスト: mstest' 'UIテスト: flaui' 'TFM: net9.0' '名前空間: tdd'
python3 -I "$NS" "$D" --spec "$D/docs/specs/tax.md" >"$T/wf.txt" 2>&1; rc=$?
ok "wf: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "wf: UIテスト / TFM を読んだ" "$(grep -q 'ui_tests=flaui' "$T/wf.txt" && grep -q 'tfm=net9.0' "$T/wf.txt" && echo 1 || echo 0)"
ok "wf: 層の名前 OrderLogic、UI テストのプロジェクト、net9.0" "$([ -f "$D/OrderLogic.Tests/OrderLogic.Tests.csproj" ] && [ -d "$D/Wf.UITests" ] && grep -q 'net9.0' "$D/Wf/Wf.csproj" && echo 1 || echo 0)"
C="$D/docs/specs/tax.cases.md"
ok "wf: ケースの種 (具体例 2 件、境界 1 件。空行は除く)" "$([ "$(grep -c -- '- \[ \] E' "$C")" = 2 ] && [ "$(grep -c -- '- \[ \] B' "$C")" = 1 ] && grep -q 'E1: 100円 x 3, 8% → 324' "$C" && grep -q 'E2: 0円 → 0 (境界)' "$C" && grep -q 'B1: 数量 0 → 例外' "$C" && grep -q '種類: MSTest' "$C" && echo 1 || echo 0)"
ok "wf: CLAUDE.md に「## 仕様書」の節と、2 つのパス" "$(grep -qx '## 仕様書' "$D/CLAUDE.md" && grep -q 'docs/specs/tax.md' "$D/CLAUDE.md" && grep -q 'docs/specs/tax.cases.md' "$D/CLAUDE.md" && echo 1 || echo 0)"
ok "wf: 取り込みの出力" "$(grep -q '仕様書の取り込み' "$T/wf.txt" && echo 1 || echo 0)"

# ---------------------------------------------------------------- 仕様書が、フォルダの外にある: コピーされる (メモも)
D="$T/Out"; mkdir -p "$D"; spec_for "$T/src" 'メインの種類: csharp-dll' '層: logic' 'テスト: mstest'
python3 -I "$NS" "$D" --spec "$T/src/docs/specs/tax.md" >/dev/null 2>&1; rc=$?
ok "out: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "out: 仕様書とメモが、docs/ にコピーされた" "$([ -f "$D/docs/specs/tax.md" ] && [ -f "$D/docs/ideas/tax.md" ] && [ -f "$D/docs/specs/tax.cases.md" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- C++: TFM は読み飛ばす。テストなしは、手動の確認項目
D="$T/Cpp"; spec_for "$D" 'メインの種類: console' '層: logic' 'テスト: none' 'TFM: net8.0'
python3 -I "$NS" "$D" --spec "$D/docs/specs/tax.md" >"$T/cpp.txt" 2>&1; rc=$?
ok "cpp: rc=0 (TFM は、読み飛ばす)" "$([ $rc = 0 ] && grep -q '読み飛ばす' "$T/cpp.txt" && echo 1 || echo 0)"
ok "cpp: テストなし -> 手動の確認項目" "$(grep -q '手動の確認項目' "$D/docs/specs/tax.cases.md" && echo 1 || echo 0)"

# ---------------------------------------------------------------- dry-run: 何も書かない。UIテストの不正な値は rc 2
D="$T/Dry"; spec_for "$D" 'メインの種類: wpf' '層: logic' 'テスト: mstest'
python3 -I "$NS" "$D" --spec "$D/docs/specs/tax.md" --dry-run >"$T/dry.txt" 2>&1; rc=$?
ok "dry: rc=0、予定を示し、cases を作らない" "$([ $rc = 0 ] && grep -q 'tax.cases.md' "$T/dry.txt" && [ ! -f "$D/docs/specs/tax.cases.md" ] && [ ! -f "$D/CLAUDE.md" ] && echo 1 || echo 0)"
D="$T/Bad"; spec_for "$D" 'メインの種類: wpf' '層: logic' 'テスト: mstest' 'UIテスト: selenium'
python3 -I "$NS" "$D" --spec "$D/docs/specs/tax.md" >/dev/null 2>&1; rc=$?
ok "bad: UIテストの不正な値 -> rc 2" $([ $rc = 2 ] && echo 1 || echo 0)

# ---------------------------------------------------------------- 既存の cases は、上書きしない (チェック済みを守る)
D="$T/Keep"; spec_for "$D" 'メインの種類: csharp-dll' 'テスト: none' '層: none'
printf 'CHECKED\n' > "$D/docs/specs/tax.cases.md"
python3 -I "$NS" "$D" --spec "$D/docs/specs/tax.md" >/dev/null 2>&1
ok "keep: 既存の .cases.md を、上書きしない" "$([ "$(cat "$D/docs/specs/tax.cases.md")" = CHECKED ] && echo 1 || echo 0)"

echo "PASS: $pass FAIL: $fail"
[ "$fail" = 0 ]
