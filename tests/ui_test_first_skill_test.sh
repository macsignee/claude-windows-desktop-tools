#!/usr/bin/env bash
# ui_test_first_skill_test.sh - /ui-test-first (UI のテストファースト) の Skill と、「UI テストは、ビルド → テストの流れに含めない」の方針が、
# Skill / 規約 / ひな形の間で、そろっているかを検証する (文字列による構造の確認。Windows 不要)。
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/ui-test-first/SKILL.md"
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }

ok "SKILL.md exists with name: ui-test-first, user-invocable only (disable-model-invocation)" "$([ -f "$S" ] && head -n 6 "$S" | grep -q '^name: ui-test-first$' && head -n 6 "$S" | grep -q '^disable-model-invocation: true$' && head -n 6 "$S" | grep -q '^description: ' && echo 1 || echo 0)"
ok "the loop: plan with one approval -> write UI tests first (Red) -> stub View -> implement (Green) -> full run -> report" "$(grep -q '承認を取る' "$S" && grep -q 'UI テストを、先に書く (Red)' "$S" && grep -q '最小の View' "$S" && grep -q '実装して、Green' "$S" && grep -q '全 UI テスト' "$S" && echo 1 || echo 0)"
ok "uses --filter and --ui-timeout, runs in the background, reads screenshots, does not weaken assertions" "$(grep -q -- '--filter' "$S" && grep -q -- '--ui-timeout' "$S" && grep -q 'run_in_background: true' "$S" && grep -q 'ui-screenshots' "$S" && grep -q 'アサーションを、弱めない' "$S" && echo 1 || echo 0)"
ok "stops after 3 identical failures; names the per-framework identifiers (WinForms Name / WPF AutomationId / MFC numeric ID)" "$(grep -q '3 回続いたら' "$S" && grep -q 'AutomationProperties.AutomationId' "$S" && grep -q '数値' "$S" && echo 1 || echo 0)"
ok "tells the user not to touch the PC when uitest.settings is desktop=visible" "$(grep -q 'マウスとキーボードに触らないでください' "$S" && echo 1 || echo 0)"

# 方針: UI テストは、ビルド → テストの流れに、含めない (ユーザーが求めたときと /ui-test-first だけ)
for f in skills/add-feature/SKILL.md skills/cpp-test-first/SKILL.md skills/wpf-test-first/SKILL.md skills/build-test-loop/SKILL.md skills/new-solution/SKILL.md rules/winforms-csharp.md; do
    ok "$f: UI tests are not run automatically after PASSED; points to /ui-test-first" "$(grep -q 'ui-test-first' "$ROOT/$f" && ! grep -q '続けて `uitest_once.sh`' "$ROOT/$f" && ! grep -q 'Green になってから 1 回' "$ROOT/$f" && echo 1 || echo 0)"
done
ok "build-test-loop: documents --filter / --ui-timeout and that UI tests are not part of build -> test" "$(grep -q -- '--filter' "$ROOT/skills/build-test-loop/SKILL.md" && grep -q -- '--ui-timeout' "$ROOT/skills/build-test-loop/SKILL.md" && grep -q 'ビルド → テスト (`build_test_once.sh`) の流れに、含めない' "$ROOT/skills/build-test-loop/SKILL.md" && echo 1 || echo 0)"

# 配布: install.sh が、skills/* をコピーする (新しい Skill も、対象)
out="$(bash "$ROOT/install/install.sh" --skills-only --dry-run --skills-dir "${TMPDIR:-/tmp}/uitf_skills_$$" 2>&1)"
ok "install.sh --dry-run lists skills/ui-test-first/SKILL.md" "$(echo "$out" | grep -q 'ui-test-first' && echo 1 || echo 0)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
