#!/usr/bin/env bash
# build_test_once.sh - ホスト側ウォッチャーに「ビルド + テスト (GoogleTest / MSTest) 実行」を1回させ、完了まで待って結果を返す。
#
# Usage: build_test_once.sh <solution_dir> [timeout_sec=300]
#   <solution_dir>: .sln/.slnx のあるフォルダ (ウォッチャーの TargetDir)
#
# 標準出力の1行目と終了コード:
#   PASSED               rc=0  ビルド成功・全テスト成功 (2 行目に、`build: SUCCESS / tests: 6 passed (...)` の要約。警告があれば、その次の行に件数)
#   FAILED               rc=1  テスト失敗 (失敗テスト一覧 + 詳細)
#   BUILD_FAILED         rc=6  ビルド失敗 (build_error.log)
#   TEST_TIMEOUT         rc=7  テストがホスト側の制限時間内に終わらない (無限ループ等の疑い)
#   ENV_ERROR            rc=4  環境エラー (ソース/テストの問題ではない)
#   WATCHER_NOT_RUNNING  rc=3  フラグが回収されない = ウォッチャー未起動
#   TIMEOUT              rc=5  完了マーカー (test_result.txt) が出ない
#   BAD_ARGS             rc=2  引数/フォルダ不正
set -u

DIR="${1:-}"
TIMEOUT="${2:-300}"
PICKUP_WAIT=15   # フラグが回収されるまでの許容秒数 (ウォッチャーは1秒周期)
MAX_DETAIL=60    # 詳細ログの最大行数 (トークン節約)

if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
    echo "BAD_ARGS: solution dir not found: $DIR"
    exit 2
fi
# 数値でない制限時間だと、待機ループの比較が毎回エラーになり、永久に待ち続けてしまう
case "$TIMEOUT" in
    ''|*[!0-9]*) echo "BAD_ARGS: timeout must be a positive integer (seconds): $TIMEOUT"; exit 2 ;;
esac

FLAG="$DIR/${BUILD_TEST_FLAG:-trigger_test.flag}"   # uitest_once.sh は、trigger_uitest.flag を指定する
BUILD_RESULT="$DIR/build_result.txt"
BUILD_ERR="$DIR/build_error.log"
TEST_RESULT="$DIR/test_result.txt"
TEST_ERR="$DIR/test_error.log"

# ログ表示: BOM/CR 除去、1行400文字、最大 N 行
show_log() {  # $1=file $2=max_lines
    [ -f "$1" ] || return 0
    local total
    total=$(wc -l < "$1")
    sed 's/^\xEF\xBB\xBF//; s/\r$//' "$1" | cut -c1-400 | head -n "${2:-$MAX_DETAIL}"
    if [ "$total" -gt "${2:-$MAX_DETAIL}" ]; then
        echo "... ($total lines total; see $1)"
    fi
    return 0
}

# コンパイル/リンクエラーの要約。解釈できない/python3 がなければ生ログ (show_log)
show_build_summary() {  # $1=build_error.log
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$1" ] && command -v python3 >/dev/null 2>&1; then
        mkdir -p "$DIR/.claude-logs" 2>/dev/null
        python3 -I "$here/summarize_build_log.py" "$1" --json "$DIR/.claude-logs/build_summary.json" && return 0
    fi
    show_log "$1"
}

# テスト失敗の要約 (同じメッセージの失敗の集約・場所。GoogleTest も MSTest も同じ形)。成功したら 0、解釈できない/python3 がなければ 1 (従来の表示に切り替える)
show_test_summary() {  # $1=test_error.log
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [ -f "$1" ] && command -v python3 >/dev/null 2>&1 || return 1
    mkdir -p "$DIR/.claude-logs" 2>/dev/null
    # 構造化された結果 (GoogleTest の XML・trx) があれば、それを使う。なければ、テキストのログを解釈する
    python3 -I "$here/summarize_test_log.py" "$1" --results-dir "$DIR/.claude-logs/test-results" --root "$DIR" \
        --json "$DIR/.claude-logs/test_summary.json"
}

# 成功時の警告の件数 (1 行だけ。警告がなければ何も出さない。失敗しても、結果には影響しない)
show_warnings_line() {
    local here w
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    w="$DIR/.claude-logs/warnings.log"
    [ -s "$w" ] && command -v python3 >/dev/null 2>&1 || return 0
    python3 -I "$here/summarize_build_log.py" "$w" --severity warning --root "$DIR" --oneline \
        --json "$DIR/.claude-logs/warnings_summary.json" 2>/dev/null || true
    return 0
}

# 成功時の要約の 1 行 (PASSED の次の行): build: SUCCESS / tests: 6 passed (DataLayer.Tests 1, LogicLayer.Tests 5)
# 構造化された結果 (trx / XML) がなければ、何も出さない。失敗しても、結果には影響しない。
show_passed_line() {
    local here line
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    command -v python3 >/dev/null 2>&1 || return 0
    line="$(python3 -I "$here/summarize_test_log.py" --passed-line --results-dir "$DIR/.claude-logs/test-results" --root "$DIR" 2>/dev/null)" || return 0
    [ -n "$line" ] && echo "build: SUCCESS / $line"
    return 0
}

first_line_is_env_error() {  # $1=file
    [ -f "$1" ] && head -n 1 "$1" | sed 's/^\xEF\xBB\xBF//' | grep -q '^\[ENVIRONMENT ERROR'
}

# 古い結果を必ず消してからフラグを置く (古いマーカーの誤読防止)
rm -f "$BUILD_RESULT" "$BUILD_ERR" "$TEST_RESULT" "$TEST_ERR"
rm -f "$DIR/.claude-logs/build_summary.json" "$DIR/.claude-logs/test_summary.json"   # 前回の要約 (JSON) も消す (今回の結果と取り違えない。ENV_ERROR / PASSED では更新されないため)
rm -rf "$DIR/.claude-logs/test-results"   # 前回の、構造化された結果 (XML / trx) も、古い結果の誤読を防ぐために消す
touch "$FLAG"

elapsed=0
picked_up=0
while [ ! -f "$TEST_RESULT" ]; do
    if [ "$picked_up" -eq 0 ]; then
        if [ ! -f "$FLAG" ]; then
            picked_up=1
        elif [ "$elapsed" -ge "$PICKUP_WAIT" ]; then
            rm -f "$FLAG"
            echo "WATCHER_NOT_RUNNING"
            echo "$(basename "$FLAG") was not picked up within ${PICKUP_WAIT}s. Ask the user to start run_watcher.cmd."
            case "$(basename "$FLAG")" in trigger_uitest.flag) echo "If the watcher is running, it may be an old version without UI test support: run ~/src/copy-host-tools.sh and restart the watcher (run_watcher.cmd)." ;; esac
            exit 3
        fi
    fi
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        echo "TIMEOUT"
        echo "test_result.txt did not appear within ${TIMEOUT}s."
        exit 5
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

sleep 0.3   # マーカー書き込み直後の読み取り競合を避ける
STATUS="$(tr -d '\r\n ' < "$TEST_RESULT")"

case "$STATUS" in
    PASSED)
        echo "PASSED"
        show_passed_line
        show_warnings_line
        exit 0
        ;;
    BUILD_FAILED)
        if first_line_is_env_error "$BUILD_ERR"; then
            echo "ENV_ERROR"
            show_log "$BUILD_ERR"
            exit 4
        fi
        echo "BUILD_FAILED"
        show_build_summary "$BUILD_ERR"
        exit 6
        ;;
    ENV_ERROR)
        echo "ENV_ERROR"
        show_log "$TEST_ERR"
        exit 4
        ;;
    TIMEOUT)
        echo "TEST_TIMEOUT"
        show_log "$TEST_ERR" 20
        exit 7
        ;;
    FAILED)
        echo "FAILED"
        if show_test_summary "$TEST_ERR"; then
            exit 1
        fi
        if [ -f "$TEST_ERR" ]; then
            # 失敗したテスト名の一覧を先頭に出す (詳細が長くても切り捨てられない)
            names=$(sed 's/^\xEF\xBB\xBF//; s/\r$//' "$TEST_ERR" \
                | grep -E '^\[  FAILED  \] [A-Za-z_][A-Za-z0-9_./]*' \
                | sed -E 's/^\[  FAILED  \] ([^ ,]+).*/\1/' | sort -u)
            if [ -n "$names" ]; then
                count=$(echo "$names" | wc -l)
                echo "Failed tests ($count):"
                echo "$names" | head -n 50 | sed 's/^/  /'
                [ "$count" -gt 50 ] && echo "  ... and $((count - 50)) more (see $TEST_ERR)"
                echo "--- details ---"
            fi
            show_log "$TEST_ERR"
        fi
        exit 1
        ;;
    *)
        echo "ENV_ERROR"
        echo "unexpected test_result.txt: '$STATUS'"
        exit 4
        ;;
esac
