#!/usr/bin/env bash
# gtest_once.sh - ホスト側ウォッチャーに、GoogleTest のソースを 1 回取得させ、完了まで待って結果を返す。
#
# Usage: gtest_once.sh <project_dir> [tag] [timeout_sec=180]
#   tag  取得する GoogleTest のタグ (例: v1.17.0 / release-1.12.1)。省略時は、ウォッチャーの既定 (-GtestTag)
#
# ウォッチャーが、<project_dir>\ThirdParty\googletest\ (include, src, LICENSE, VERSION.txt) に置く。
# Windows 側が GitHub に届く必要がある。同じタグが、すでに置かれていれば、何もせずに OK。
#
# 標準出力 (1行目) と終了コード:
#   OK                   rc=0  取得済み (または、すでに同じタグがある)
#   FAILED               rc=1  取得失敗 (2行目以降に gtest_error.log。環境の問題。ソースの問題ではない)
#   WATCHER_NOT_RUNNING  rc=3  フラグが回収されない = ウォッチャー未起動
#   TIMEOUT              rc=5  完了マーカーが出ない
#   (引数/フォルダ不正)   rc=2
set -u

DIR="${1:-}"
TAG="${2:-}"
TIMEOUT="${3:-180}"
PICKUP_WAIT=15   # フラグが回収されるまでの許容秒数 (ウォッチャーは1秒周期)

if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
    echo "BAD_ARGS: project dir not found: $DIR"
    exit 2
fi
# 数値でない制限時間だと、待機ループの比較が毎回エラーになり、永久に待ち続けてしまう
case "$TIMEOUT" in
    ''|*[!0-9]*) echo "BAD_ARGS: timeout must be a positive integer (seconds): $TIMEOUT"; exit 2 ;;
esac
# タグは、ウォッチャー側でコマンドの引数や URL に渡る。決まった形だけを許可する
if [ -n "$TAG" ] && ! printf '%s' "$TAG" | grep -Eq '^(v|release-)[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    echo "BAD_ARGS: invalid tag: $TAG (allowed: v1.17.0 / release-1.12.1)"
    exit 2
fi

FLAG="$DIR/trigger_gtest.flag"
RESULT="$DIR/gtest_result.txt"
ERRLOG="$DIR/gtest_error.log"

show_log() {
    [ -f "$ERRLOG" ] || return 0
    local total
    total=$(wc -l < "$ERRLOG")
    sed 's/^\xEF\xBB\xBF//; s/\r$//' "$ERRLOG" | cut -c1-400 | head -n 30
    [ "$total" -gt 30 ] && echo "... ($total lines total; see $ERRLOG)"
    return 0
}

# 古い結果を必ず消してからフラグを置く (古いマーカーの誤読防止)
rm -f "$RESULT" "$ERRLOG"
if [ -n "$TAG" ]; then printf '%s\n' "$TAG" > "$FLAG"; else : > "$FLAG"; fi

elapsed=0
picked_up=0
while [ ! -f "$RESULT" ]; do
    if [ "$picked_up" -eq 0 ]; then
        if [ ! -f "$FLAG" ]; then
            picked_up=1
        elif [ "$elapsed" -ge "$PICKUP_WAIT" ]; then
            rm -f "$FLAG"
            echo "WATCHER_NOT_RUNNING"
            echo "trigger_gtest.flag was not picked up within ${PICKUP_WAIT}s. Ask the user to start run_watcher.cmd."
            exit 3
        fi
    fi
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        echo "TIMEOUT"
        echo "gtest_result.txt did not appear within ${TIMEOUT}s."
        exit 5
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

sleep 0.3   # マーカー書き込み直後の読み取り競合を避ける
STATUS="$(tr -d '\r\n ' < "$RESULT")"

if [ "$STATUS" = "OK" ]; then
    echo "OK"
    exit 0
fi

echo "FAILED"
show_log
exit 1
