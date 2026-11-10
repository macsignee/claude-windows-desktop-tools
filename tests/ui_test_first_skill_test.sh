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

# new-solution: 了承の質問の選択肢に、UI テストを足さない (v2.63.2)
ok "new-solution: the approval question has no UI-test option when ui-tests is none" "$(grep -q '了承の質問の選択肢に、UI テストを足さない' "$ROOT/skills/new-solution/SKILL.md" && echo 1 || echo 0)"

# new-solution: --ui-tests は、質問しない。指定がなければ、どの種類でも none。flaui と明示されたときだけ作る (v2.63.0)
NS="$ROOT/skills/new-solution/SKILL.md"
ok "new-solution: never asks about --ui-tests; defaults to none for every type; builds flaui only when explicit" "$(grep -q '`--ui-tests`: \*\*質問しない。' "$NS" && grep -q 'どの種類でも、既定の `none`' "$NS" && grep -q '`flaui` と明示されたときだけ、作る' "$NS" && ! grep -q '種類によって、質問を省かない' "$NS" && echo 1 || echo 0)"

ok "dialogs / sub-windows (v2.69.0): the plan adds 種類 / 開き方 / 閉じ方と結果 / 開くときの前提 for non-main screens, the opener button is a part in the main View, dialog parts are found with Find(window, \"Id\"), the design record has the opener section" "$(grep -q '画面の種類 (メインウィンドウか、ダイアログ・サブウィンドウか)' "$S" && grep -q '開き方' "$S" && grep -q '閉じ方と結果' "$S" && grep -q '開くときの前提' "$S" && grep -q '開くボタンも、部品として' "$S" && grep -q 'Find(dlg, \"OkButton\")' "$S" && grep -q '## 開き方と閉じ方 (メインウィンドウ以外のときだけ)' "$S" && grep -q 'モーダルなダイアログ | モードレスなウィンドウ' "$S" && echo 1 || echo 0)"
ok "dialogs (v2.69.0): build-test-loop's UI test reference tells to use Find(window, \"Id\") inside dialogs" "$(grep -q 'Find(window, \"Id\")' "$ROOT/skills/build-test-loop/references/ui-tests.md" && echo 1 || echo 0)"
ok "Model switch + integration (v2.70.0): APP_MODEL fake/real, switched at the composition root, not read in Release, UITEST_MODEL > uitest.settings model= > fake, Fake lives in the app/data layer, integration = same UI tests with model=real after the real Model's unit tests PASSED, Fake kept, contract tests align Fake and the real Model" "$(grep -q '## Model の差し替え (Fake ↔ 本物)' "$S" && grep -q '## 結合 (Fake → 本物)' "$S" && grep -q 'APP_MODEL' "$S" && grep -q 'UITEST_MODEL' "$S" && grep -q 'model=real' "$S" && grep -q 'Release のビルドでは、`APP_MODEL` を読まない' "$S" && grep -q 'InMemory<名前>Repository' "$S" && grep -q 'Fake と本物は、契約テスト (同じテストを、両方に通す) で、合わせる' "$S" && grep -q '契約テスト (Fake と本物の両方) が `PASSED`' "$S" && grep -q '契約テスト (クラス名)' "$S" && grep -q 'Fake を、捨てない' "$S" && grep -q '依存する Model' "$S" && grep -q '## 依存する Model (Fake を使うときだけ)' "$S" && echo 1 || echo 0)"
ok "Model switch (v2.70.0): build-test-loop's UI test reference mentions APP_MODEL" "$(grep -q 'APP_MODEL' "$ROOT/skills/build-test-loop/references/ui-tests.md" && echo 1 || echo 0)"
ok "contract tests (v2.71.0): CONTRACT-TESTS.md for C# (abstract base + one concrete class per implementation, Create(), real class added Red -> Green, no Ignore/Inconclusive, dev connection only) and C++ (TYPED_TEST / TEST_P, no GTEST_SKIP), linked from PROJECT-LAYOUT.md / DLL-LAYOUT.md" "$(C="$ROOT/skills/csharp-test-first/CONTRACT-TESTS.md"; P="$ROOT/skills/cpp-test-first/CONTRACT-TESTS.md"; [ -f "$C" ] && [ -f "$P" ] && grep -q 'public abstract class OrderRepositoryContractTests' "$C" && grep -q 'protected abstract IOrderRepository Create()' "$C" && grep -q 'InMemoryOrderRepositoryContractTests : OrderRepositoryContractTests' "$C" && grep -q '本物の具体クラス' "$C" && grep -q 'Assert.Inconclusive' "$C" && grep -q '本番の接続先で、実行しない' "$C" && grep -q 'test_guard.py' "$C" && grep -q 'TYPED_TEST_SUITE' "$P" && grep -q 'INSTANTIATE_TEST_SUITE_P' "$P" && grep -q 'GTEST_SKIP' "$P" && grep -q 'CONTRACT-TESTS.md' "$ROOT/skills/csharp-test-first/PROJECT-LAYOUT.md" && grep -q 'CONTRACT-TESTS.md' "$ROOT/skills/cpp-test-first/DLL-LAYOUT.md" && echo 1 || echo 0)"
ok "contract tests (v2.71.0): test_guard really flags what the docs forbid (Ignore / Inconclusive / GTEST_SKIP / DISABLED_ -> TMG002)" "$(grep -q 'TMG002 error   \[Ignore\] / Assert.Inconclusive / GTEST_SKIP / DISABLED_' "$ROOT/skills/build-test-loop/scripts/test_guard.py" && echo 1 || echo 0)"
ok "desktop speed (v2.73.0): the reference lists the measured fixed cost of --separate for WPF and when to use --visible; the SKILL points to it" "$(grep -q 'WPF は、別のデスクトップ (`--separate`) だと、1 件あたり、固定費がかかる' "$ROOT/skills/build-test-loop/references/ui-tests.md" && grep -q 'exit: killed after N ms' "$ROOT/skills/build-test-loop/references/ui-tests.md" && grep -q '1 件 約 5〜10 秒遅い' "$S" && echo 1 || echo 0)"
# 配布: install.sh が、skills/* をコピーする (新しい Skill も、対象)
out="$(bash "$ROOT/install/install.sh" --skills-only --dry-run --skills-dir "${TMPDIR:-/tmp}/uitf_skills_$$" 2>&1)"
ok "install.sh --dry-run lists skills/ui-test-first/SKILL.md" "$(echo "$out" | grep -q 'ui-test-first' && echo 1 || echo 0)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
