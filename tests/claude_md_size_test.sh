#!/bin/bash
# 生成する CLAUDE.md は、毎セッション・毎ターン、文脈に入る (v2.105.0 で、Token 削減のために短くした)。
# 長さの上限と、短くしても残すべき文言を、検査する。詳しい手順は、build-test-loop の references/ui-tests.md を読ませる。
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SC="$ROOT/skills/new-solution/scripts"
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }

OUT="$(python3 -I - "$SC" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import add_ui_tests as A, msbuild_source as M
ui = A.claude_md_section('X.UITests', 'X')
print('UI_LEN', len(ui))
print('MS_REF_DOTNET', len(M.claude_note(True, 'reference', '/mnt/c/T')))
print('MS_COPY_DOTNET', len(M.claude_note(True, 'copy', None)))
open(sys.argv[1] + '/../../../.ui_section.tmp', 'w', encoding='utf-8').write(ui)
open(sys.argv[1] + '/../../../.ms_section.tmp', 'w', encoding='utf-8').write(M.claude_note(True, 'reference', '/mnt/c/T'))
PY
)"
UI="$ROOT/.ui_section.tmp"; MS="$ROOT/.ms_section.tmp"
val() { printf '%s\n' "$OUT" | awk -v k="$1" '$1==k{print $2}'; }
trap 'rm -f "$UI" "$MS"' EXIT

ok "UI テストの節は、1500 文字以下 (今は $(val UI_LEN))" "$([ "$(val UI_LEN)" -le 1500 ] && echo 1 || echo 0)"
ok "MSBuild の節 (参照型・.NET) は、700 文字以下 (今は $(val MS_REF_DOTNET))" "$([ "$(val MS_REF_DOTNET)" -le 700 ] && echo 1 || echo 0)"
ok "MSBuild の節 (コピー型・.NET) は、600 文字以下 (今は $(val MS_COPY_DOTNET))" "$([ "$(val MS_COPY_DOTNET)" -le 600 ] && echo 1 || echo 0)"

# 短くしても残す (知らないと、間違った動きをするもの)
has() { grep -qF -- "$2" "$1" && echo 1 || echo 0; }
ok "UI: ビルド → テストの流れに含めない・uitest_once.sh・/ui-test-first・--filter・--ui-timeout が残る" "$([ "$(has $UI 'ビルド → テスト (`build_test_once.sh`) の流れには、含めない')$(has $UI 'uitest_once.sh "$PWD" 900')$(has $UI '/ui-test-first')$(has $UI -- '--filter')$(has $UI -- '--ui-timeout')" = 11111 ] && echo 1 || echo 0)"
ok "UI: UiDialogs を使う・煙テスト・run_watcher_visible.cmd・AutomationId・スクリーンショットが残る" "$([ "$(has $UI 'UiDialogs')$(has $UI '煙テスト')$(has $UI 'run_watcher_visible.cmd')$(has $UI 'AutomationId')$(has $UI 'ui-screenshots')" = 11111 ] && echo 1 || echo 0)"
ok "UI: WinForms は Name を使う、アサーションを弱めない、が残る" "$([ "$(has $UI 'コントロールの `Name`')$(has $UI 'アサーションを弱めない')" = 11 ] && echo 1 || echo 0)"
ok "UI: 詳細は references/ui-tests.md を読ませる" "$(has $UI 'references/ui-tests.md')"
ok "MSBuild(参照型): MSBuild 共通の行・MSBUILD_COMMON_DIR・NOT_SET のエラー・コピーしない・Claude が決めない が残る" "$([ "$(has $MS '- MSBuild 共通: /mnt/c/T')$(has $MS 'MSBUILD_COMMON_DIR')$(has $MS '__MSBUILD_COMMON_DIR_NOT_SET__')$(has $MS 'コピーしない')$(has $MS 'Claude が決めない')" = 11111 ] && echo 1 || echo 0)"
ok "MSBuild: Dotnet.props・警告 (warnings.log)・ClaudeCheck・ClaudeLayerRole が残る" "$([ "$(has $MS 'Dotnet.props')$(has $MS 'warnings.log')$(has $MS 'ClaudeCheck')$(has $MS 'ClaudeLayerRole')" = 1111 ] && echo 1 || echo 0)"

# WPF の CLAUDE.md の「規約」の行に、同じ文が 2 回続かない (重複していた)
DUP="$(grep -c '機械で判定できる項目は、`wpf-check` が確かめる。機械で判定できる項目は、`wpf-check` が確かめる。' "$ROOT/skills/new-solution/scripts/new_solution.py")"
ok "new_solution.py: 「機械で判定できる項目は、wpf-check が確かめる」が、2 回続かない" "$([ "$DUP" = 0 ] && echo 1 || echo 0)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
