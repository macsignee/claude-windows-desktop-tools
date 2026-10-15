#!/usr/bin/env bash
# build_once.sh - ホスト側ウォッチャーに1回ビルドさせ、完了まで待って結果を返す。
#
# Usage: build_once.sh <project_dir> [timeout_sec=180]
#
# 標準出力 (1行目) と終了コード:
#   SUCCESS              rc=0  ビルド成功
#   FAILED               rc=1  ビルド失敗 (2行目以降に build_error.log を出力)
#   ENV_ERROR            rc=4  環境エラー (ソースの問題ではない。2行目以降にログ)
#   WATCHER_NOT_RUNNING  rc=3  フラグが消えない = ウォッチャー未起動
#   TIMEOUT              rc=5  完了マーカーが出ない
#   (引数/フォルダ不正)   rc=2
set -u

DIR="${1:-}"
TIMEOUT="${2:-180}"
PICKUP_WAIT=15   # フラグが回収されるまでの許容秒数 (ウォッチャーは1秒周期)

if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
    echo "BAD_ARGS: project dir not found: $DIR"
    exit 2
fi
# 数値でない制限時間だと、待機ループの比較が毎回エラーになり、永久に待ち続けてしまう
case "$TIMEOUT" in
    ''|*[!0-9]*) echo "BAD_ARGS: timeout must be a positive integer (seconds): $TIMEOUT"; exit 2 ;;
esac

FLAG="$DIR/trigger_build.flag"
RESULT="$DIR/build_result.txt"
ERRLOG="$DIR/build_error.log"

# エラーログ表示: BOM/CR除去、1行400文字・最大40行に制限 (トークン節約。全文は build_error.log / .claude-logs)
show_log() {
    [ -f "$ERRLOG" ] || return 0
    local total
    total=$(wc -l < "$ERRLOG")
    sed 's/^\xEF\xBB\xBF//; s/\r$//' "$ERRLOG" | cut -c1-400 | head -n 40
    [ "$total" -gt 40 ] && echo "... ($total lines total; see $ERRLOG)"
    return 0
}

# コンパイル/リンクエラーの要約 (同じエラーの集約・件数・代表の場所)。解釈できない/python3 がなければ生ログ (show_log)
show_summary() {
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$ERRLOG" ] && command -v python3 >/dev/null 2>&1; then
        mkdir -p "$DIR/.claude-logs" 2>/dev/null
        python3 -I "$here/summarize_build_log.py" "$ERRLOG" --json "$DIR/.claude-logs/build_summary.json" && return 0
    fi
    show_log
}

# 古い結果を必ず消してからフラグを置く (古いマーカーの誤読防止)
rm -f "$RESULT" "$ERRLOG"
touch "$FLAG"

elapsed=0
picked_up=0
while [ ! -f "$RESULT" ]; do
    if [ "$picked_up" -eq 0 ]; then
        if [ ! -f "$FLAG" ]; then
            picked_up=1
        elif [ "$elapsed" -ge "$PICKUP_WAIT" ]; then
            rm -f "$FLAG"
            echo "WATCHER_NOT_RUNNING"
            echo "trigger_build.flag was not picked up within ${PICKUP_WAIT}s. Ask the user to start run_watcher.cmd."
            exit 3
        fi
    fi
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        echo "TIMEOUT"
        echo "build_result.txt did not appear within ${TIMEOUT}s."
        exit 5
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

sleep 0.3   # マーカー書き込み直後の読み取り競合を避ける
STATUS="$(tr -d '\r\n ' < "$RESULT")"

if [ "$STATUS" = "SUCCESS" ]; then
    echo "SUCCESS"
    exit 0
fi

if [ -f "$ERRLOG" ] && head -n 1 "$ERRLOG" | sed 's/^\xEF\xBB\xBF//' | grep -q '^\[ENVIRONMENT ERROR'; then
    echo "ENV_ERROR"
    show_log
    exit 4
fi

echo "FAILED"
show_summary
exit 1
