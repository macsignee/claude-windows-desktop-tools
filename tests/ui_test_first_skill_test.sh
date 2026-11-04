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

ok "visual check: Preview tests + --preview / --hold, tell the user before showing, Snap for Claude's own check, background tests use --separate" "$(grep -q 'TestCategory("Preview")' "$S" && grep -q -- '--preview' "$S" && grep -q 'HoldForViewing' "$S" && grep -q 'Snap(' "$S" && grep -q -- '--separate' "$S" && grep -q '実行の前に、ユーザーに伝える' "$S" && echo 1 || echo 0)"
ok "design record: checks docs/design/<screen>.md first, optional 2-3 option comparison (text only), saves it after the approval, and ui-design-review points to it" "$(grep -q 'docs/design/<画面>.md' "$S" && grep -q '2〜3 案' "$S" && grep -q '選ばなかった案と理由' "$S" && grep -q '画像や外部のツールは、使わない' "$S" && grep -q 'docs/design/<画面>.md' "$ROOT/skills/ui-design-review/SKILL.md" && echo 1 || echo 0)"
ok "design record: does not overwrite a decided design (edits changed rows, appends 変更履歴) and never writes it from guesses" "$(grep -q '変わった行だけを直し' "$S" && grep -q '推測して書かない' "$S" && echo 1 || echo 0)"
BTLU="$ROOT/skills/build-test-loop/references/ui-tests.md"
ok "build-test-loop (references/ui-tests.md) documents --hold / --preview and PreviewUiTests" "$(grep -q -- '--hold' "$BTLU" && grep -q -- '--preview' "$BTLU" && grep -q 'PreviewUiTests' "$BTLU" && echo 1 || echo 0)"

ok "demo playback: --present documented (needs --filter) in the skill and build-test-loop (references/ui-tests.md)" "$(grep -q -- '--present' "$S" && grep -q -- '--present' "$BTLU" && grep -q '赤い枠' "$S" && echo 1 || echo 0)"
# build-test-loop の SKILL.md から、UI テストの詳細を references/ui-tests.md に分離 (v2.40.0)
BTLS="$ROOT/skills/build-test-loop/SKILL.md"
ok "build-test-loop: SKILL.md keeps a short UI-test entry (not part of build -> test; only when asked or in /ui-test-first; uitest_once.sh; read references/ui-tests.md first) and the details moved out" "$(grep -q '^## UI テスト (FlaUI): ビルド → テストの流れとは、別に、指定されたときだけ実行する' "$BTLS" && grep -q '自動では、続けて実行しない' "$BTLS" && grep -q '求められていなければ、実行しない' "$BTLS" && grep -q '先に `references/ui-tests.md` を読む' "$BTLS" && ! grep -q '^### ' "$BTLS" && [ -f "$BTLU" ] && grep -q 'UiDialogs' "$BTLU" && grep -q '^## 失敗したら' "$BTLU" && grep -q '^## いつ実行するか' "$BTLU" && echo 1 || echo 0)"
ok "build-test-loop: SKILL.md stays small (<= 32000 bytes; was 53294 before the split)" "$([ "$(wc -c < "$BTLS" | tr -d ' ')" -le 32000 ] && echo 1 || echo 0)"
ok "every skill / rule that pointed to the UI-test section now points to references/ui-tests.md (no old wording)" "$(! grep -rIq '`build-test-loop` の「UI テスト」' "$ROOT/skills" "$ROOT/rules" && grep -q 'references/ui-tests.md' "$ROOT/skills/ui-test-first/SKILL.md" && echo 1 || echo 0)"
CSF2="${TMPDIR:-/tmp}/btl_$$"; bash "$ROOT/install/install.sh" --skills-only --skills-dir "$CSF2" >/dev/null 2>&1
ok "install.sh --skills-only copies build-test-loop/references/ui-tests.md (identical to the repo)" "$([ -f "$CSF2/build-test-loop/references/ui-tests.md" ] && cmp -s "$CSF2/build-test-loop/references/ui-tests.md" "$BTLU" && echo 1 || echo 0)"
rm -rf "$CSF2" 2>/dev/null

# 方針: UI テストは、ビルド → テストの流れに、含めない (ユーザーが求めたときと /ui-test-first だけ)
for f in skills/cpp-test-first/SKILL.md skills/csharp-test-first/SKILL.md skills/build-test-loop/SKILL.md skills/new-solution/SKILL.md rules/winforms-csharp.md; do
    ok "$f: UI tests are not run automatically after PASSED; points to /ui-test-first" "$(grep -q 'ui-test-first' "$ROOT/$f" && ! grep -q '続けて `uitest_once.sh`' "$ROOT/$f" && ! grep -q 'Green になってから 1 回' "$ROOT/$f" && echo 1 || echo 0)"
done
ok "build-test-loop: documents --filter / --ui-timeout and that UI tests are not part of build -> test" "$(grep -q -- '--filter' "$ROOT/skills/build-test-loop/SKILL.md" && grep -q -- '--ui-timeout' "$ROOT/skills/build-test-loop/SKILL.md" && grep -q 'ビルド → テスト (`build_test_once.sh`) の流れに、含めない' "$ROOT/skills/build-test-loop/SKILL.md" && echo 1 || echo 0)"

# new-solution: --ui-tests は、画面つきの種類で、指定がなければ、種類によらず、必ず質問する (v2.33.0)
NS="$ROOT/skills/new-solution/SKILL.md"
ok "new-solution: asks about --ui-tests for every GUI type (wpf / winforms / mfc / mfc-mdi / mfc-dialog) when unspecified; not for csharp-dll / win32 / console / dll / lib" "$(grep -q '`--ui-tests`: \*\*`wpf` / `winforms` / `mfc` / `mfc-mdi` / `mfc-dialog` のとき' "$NS" && grep -q '種類によって、質問を省かない' "$NS" && grep -q '`csharp-dll` / `win32` / `console` / `dll` / `lib` では、質問しない' "$NS" && echo 1 || echo 0)"

# 配布: install.sh が、skills/* をコピーする (新しい Skill も、対象)
out="$(bash "$ROOT/install/install.sh" --skills-only --dry-run --skills-dir "${TMPDIR:-/tmp}/uitf_skills_$$" 2>&1)"
ok "install.sh --dry-run lists skills/ui-test-first/SKILL.md" "$(echo "$out" | grep -q 'ui-test-first' && echo 1 || echo 0)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
