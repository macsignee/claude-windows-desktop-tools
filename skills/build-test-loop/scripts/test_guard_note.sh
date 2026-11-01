#!/usr/bin/env bash
# test_guard_note.sh - テストの改変の検査 (test_guard.py check) の結果を、`TEST_GUARD:` の行で、出力の末尾に出す。
#
# Usage: test_guard_note.sh <solution_dir>
# 何も出さない場合: 基準 (.claude-logs/test_guard_base/) がない / テストファイルがない / python3 がない / フォルダがない。
#   基準がないときに「作れ」と促さないのは、Green のあとに snapshot を取られると、改変が、基準に取り込まれてしまうため
#   (基準を作るのは、Red を確認した直後だけ。cpp-test-first / csharp-test-first / ui-test-first の手順)。
# 出力 (1〜6 行。終了コードは、常に 0。ビルドとテストの結果には、影響しない):
#   TEST_GUARD: OK (error 0 / warning 0 / review 0)
#   TEST_GUARD: REVIEW (warning N / review N) -- 全文は、`test_guard.py check` で
#   TEST_GUARD: ERROR (error N / ...)  + error の行 (最大 5 行) + 「元に戻すか、止まって確認する」
# build_test_once.sh (uitest_once.sh は、自分の出力の末尾で呼ぶ) が、終了時に呼ぶ。
DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR/.claude-logs/test_guard_base" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
guard="$(dirname "${BASH_SOURCE[0]}")/test_guard.py"
[ -f "$guard" ] || exit 0

out="$(python3 -I "$guard" check "$DIR" --max-lines 400 2>/dev/null)"
rc=$?
summary="$(printf '%s\n' "$out" | head -n 1)"
case "$summary" in "test_guard: error "*) ;; *) exit 0 ;; esac   # 基準なし (rc 3)・引数の誤りなどは、出さない
counts="${summary#test_guard: }"; counts="${counts%% (*}"      # error N / warning N / review N

if [ "$rc" = 1 ]; then
    echo "TEST_GUARD: ERROR ($counts)"
    printf '%s\n' "$out" | grep -a -E '^TMG[0-9]+ +error ' | head -n 5
    echo "  -> Red のあとに、テストが改変された。ユーザーの明示的な許可なしに、通してはいけない: 元に戻すか、止まって確認する (承認されたら snapshot をやり直す)。全文: python3 -I ~/.claude/skills/build-test-loop/scripts/test_guard.py check \"\$SLN\""
else
    warn="$(printf '%s' "$counts" | sed -n 's/.*warning \([0-9]*\).*/\1/p')"
    rev="$(printf '%s' "$counts" | sed -n 's/.*review \([0-9]*\).*/\1/p')"
    if [ "${warn:-0}" != 0 ] || [ "${rev:-0}" != 0 ]; then
        echo "TEST_GUARD: REVIEW ($counts) -- warning / review は、変更前後を、ユーザーに見せる。全文: python3 -I ~/.claude/skills/build-test-loop/scripts/test_guard.py check \"\$SLN\""
    else
        echo "TEST_GUARD: OK ($counts)"
    fi
fi
exit 0
