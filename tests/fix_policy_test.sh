#!/usr/bin/env bash
# fix_policy_test.sh - 修正の方針 (build-test-loop/references/fix-policy.md) と、auto-build / build-test-loop からの参照を検証する (v2.50.0)。
# Usage: tests/fix_policy_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FP="$ROOT/skills/build-test-loop/references/fix-policy.md"
BTL="$ROOT/skills/build-test-loop/SKILL.md"
AB="$ROOT/skills/auto-build/SKILL.md"
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }

ok "fix-policy.md exists with the 5 sections (前の確認 / ビルドエラー / 警告 / テスト失敗 / 完了報告)" "$(yes_if bash -c "grep -q '^## 1. 修正の前の確認' '$FP' && grep -q '^## 2. ビルドエラー' '$FP' && grep -q '^## 3. 警告の方針' '$FP' && grep -q '^## 4. テスト失敗' '$FP' && grep -q '^## 5. 完了報告の項目' '$FP'")"
ok "pre-fix check: read-only git status / diff --stat (core.fileMode=false, no-optional-locks); stops when the target overlaps the user's uncommitted changes; asks no question" "$(yes_if bash -c "grep -q 'status --short' '$FP' && grep -q 'diff --stat' '$FP' && grep -q 'core.fileMode=false' '$FP' && grep -q 'no-optional-locks' '$FP' && grep -q '修正せずに停止して報告する' '$FP' && grep -q '確認のための質問は、しない' '$FP'")"
ok "the pre-fix check never stages or commits" "$(yes_if bash -c "! grep -E 'git (add|commit|stash|checkout|reset)' '$FP'")"
ok "warning policy: ignore / report / fix, default is report, fix only for safe warnings, never suppress" "$(yes_if bash -c "grep -q '指定がなければ、\`report\`' '$FP' && grep -q '\`ignore\`' '$FP' && grep -q '\`fix\`' '$FP' && grep -q 'size_t' '$FP' && grep -q 'ABI に影響し得るもの' '$FP' && grep -q '#pragma warning disable' '$FP' && grep -q 'NoWarn' '$FP'")"
ok "test failures: environment-dependent / flaky / unclear-spec cases stop (focus, DPI, locale, time zone, flaky, external, async race, crash, same test twice)" "$(yes_if bash -c "for w in フォーカス DPI ロケール タイムゾーン フレーク 外部機器 非同期の競合 アクセス違反 '2 回続けて失敗'; do grep -q \"\$w\" '$FP' || exit 1; done")"
ok "test failures: deleting / disabling / weakening tests stays forbidden and points to test_guard" "$(yes_if bash -c "grep -q 'DISABLED_' '$FP' && grep -q 'EXPECT_' '$FP' && grep -q 'test_guard.py' '$FP'")"
ok "the report items: environment / run / fix / warnings / logs / stop reason" "$(yes_if bash -c "sec=\$(sed -n '/^## 5. 完了報告の項目/,\$p' '$FP'); for w in '環境' '実行' '修正' '警告' 'ログ' '停止したとき'; do echo \"\$sec\" | grep -q \"\\*\\*\$w\" || exit 1; done")"
ok "build-test-loop SKILL.md points to fix-policy.md in the 止めどき section" "$(yes_if bash -c "sed -n '/^## 止めどき/,/^## トークン節約/p' '$BTL' | grep -q 'references/fix-policy.md'")"
ok "auto-build SKILL.md points to fix-policy.md (loop rule and report)" "$(yes_if bash -c "[ \"\$(grep -c 'fix-policy.md' '$AB')\" -ge 2 ]")"
ok "the pointer path in auto-build exists (skills/build-test-loop/references/fix-policy.md)" "$(yes_if bash -c "grep -o '~/.claude/skills/[a-z-]*/references/fix-policy.md' '$AB' | sed 's#~/.claude/skills#$ROOT/skills#' | while read -r p; do [ -f \"\$p\" ] || exit 1; done")"
ok "build-test-loop SKILL.md stays small (<= 32000 bytes)" "$([ "$(wc -c < "$BTL" | tr -d ' ')" -le 32000 ] && echo 1 || echo 0)"
ok "no fictional fixed paths in fix-policy.md" "$(yes_if bash -c "! grep -E 'C:\\\\|/mnt/c/|/home/' '$FP'")"
echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
