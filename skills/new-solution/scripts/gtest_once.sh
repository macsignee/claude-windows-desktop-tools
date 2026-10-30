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
#   ENV_ERROR            rc=4  フラグを書けなかった (起動したフォルダの大文字小文字が、実際と違う、など。何も始まっていない)
#   WATCHER_NOT_RUNNING  rc=3  フラグが回収されない = ウォッチャー未起動
#   TIMEOUT              rc=5  完了マーカー (この実行のもの) が出ない。ウォッチャーは、続けているかもしれない: 報告して止まる
#   (引数/フォルダ不正)   rc=2
set -u

DIR="${1:-}"
TAG="${2:-}"
TIMEOUT="${3:-180}"
PICKUP_WAIT="${CLAUDE_PICKUP_WAIT:-15}"   # フラグが回収されるまでの許容秒数 (ウォッチャーは1秒周期)

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

# WSL の /mnt など、大文字小文字を区別しない (が、保持する) ファイルシステムでは、$DIR の大文字小文字が
# 実際のフォルダ名と違っていても [ -d "$DIR" ] は通る。だが、サンドボックスの書き込み許可は、パスの文字列を
# 大文字小文字を区別して比較するため、違ったままだと rm やフラグの書き込みが "Read-only file system" で
# 失敗し、前回の結果を、今回の結果と取り違えることがある (実機で確認)。ここで、実際の大文字小文字に直す。
resolve_true_case() {
    local input="$1" resolved="" component parent names chosen
    case "$input" in
        /*) ;;
        *) printf '%s\n' "$input"; return 0 ;;
    esac
    local IFS=/
    local -a parts
    read -ra parts <<< "$input"
    for component in "${parts[@]}"; do
        [ -z "$component" ] && continue
        parent="${resolved:-/}"
        # [ -e ... ] は、このマウント上では大文字小文字を区別せず「ある」になってしまうため使えない。
        # 親ディレクトリを列挙して、実際の (大文字小文字が正しい) 名前を探す。
        names="$(find "$parent" -maxdepth 1 -iname "$component" -printf '%f\n' 2>/dev/null)"
        chosen=""
        while IFS= read -r n; do
            [ -z "$n" ] && continue
            if [ "$n" = "$component" ]; then chosen="$n"; break; fi
            [ -z "$chosen" ] && chosen="$n"
        done <<< "$names"
        [ -z "$chosen" ] && chosen="$component"
        if [ "$parent" = "/" ]; then resolved="/$chosen"; else resolved="$parent/$chosen"; fi
    done
    printf '%s\n' "${resolved:-/}"
}
DIR="$(resolve_true_case "$DIR")"
# ただし、起動したフォルダ ($PWD) の中なら、起動したときの綴りに合わせる。サンドボックスが書き込みを許すのは、起動したときの綴り
# だけなので、実際の大文字小文字に直すと、かえって書き込めなくなる (Windows 側は、大文字小文字を区別しないので、どちらでも同じ)
align_to_launch_case() {
    local d="$1" p="$PWD"
    if [ "${d,,}" = "${p,,}" ]; then
        printf '%s\n' "$p"
    elif [[ "${d,,}" == "${p,,}/"* ]]; then
        printf '%s\n' "$p/${d:$((${#p}+1))}"
    else
        printf '%s\n' "$d"
    fi
}
DIR="$(align_to_launch_case "$DIR")"

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


# 実行 ID (v2.20.1 / build_once.sh と同じ仕組み): フラグの 2 行目に、実行 ID をコメント行 (# run=...) で書く (1 行目は、タグのまま。古いウォッチャーは、1 行目だけを読む)。
# ウォッチャーは、結果のマーカーを書く直前に、同じ ID を .claude-logs/run_id.txt に書く。前の実行 (TIMEOUT であきらめたが、ウォッチャーは続けていた)
# が、あとで書いた、古いマーカーを、今回の結果と取り違えないための照合。run_id.txt がない = 古いウォッチャー → 照合なし (従来どおり)。
RUN_ID="$(date +%s)-$$-$RANDOM"
RUN_ID_FILE="$DIR/.claude-logs/run_id.txt"
BUSY_FILE="$DIR/.claude-logs/watcher_busy.txt"   # ウォッチャーが、処理中の間だけ、ある

result_ready() {  # $1=マーカーのファイル。マーカーがあり、かつ、実行 ID が、この実行のものか (古いウォッチャーなら、マーカーだけ)
    [ -f "$1" ] || return 1
    [ -f "$RUN_ID_FILE" ] || return 0
    [ "$(sed 's/^\xEF\xBB\xBF//; s/\r$//' "$RUN_ID_FILE" | head -n 1)" = "run=$RUN_ID" ]
}

watcher_busy() {  # ウォッチャーが、別の処理の最中か (60 分以内に、始まったもの)
    [ -f "$BUSY_FILE" ] && [ -n "$(find "$BUSY_FILE" -mmin -60 2>/dev/null)" ]
}

# 古い結果を必ず消してからフラグを置く (古いマーカーの誤読防止)
rm -f "$RESULT" "$ERRLOG" "$RUN_ID_FILE"
# フラグを書けなかったとき (例: 起動したフォルダの大文字小文字が、実際と違い、サンドボックスが書き込みを許さない): 結果を待たずに、理由を出して終わる
check_flag_written() {
    [ -f "$FLAG" ] && return 0
    local want="$PWD" real
    real="$(resolve_true_case "$PWD")"
    echo "ENV_ERROR"
    echo "Could not write $(basename "$FLAG"): $FLAG (nothing was started; the watcher was not asked to do anything)."
    if [ "$want" != "$real" ]; then
        echo "The folder Claude Code was started in differs in letter case from the real folder name (started: $want, real: $real). Ask the user to restart Claude Code in the real name, then run this again from the start."
    else
        echo "Check the write permission of this folder (sandbox), then run this again from the start."
    fi
    exit 4
}
printf '%s\n# run=%s\n' "$TAG" "$RUN_ID" > "$FLAG"
check_flag_written

elapsed=0
picked_up=0
while ! result_ready "$RESULT"; do
    if [ "$picked_up" -eq 0 ]; then
        if [ ! -f "$FLAG" ]; then
            picked_up=1
        elif [ "$elapsed" -ge "$PICKUP_WAIT" ] && ! watcher_busy; then
            rm -f "$FLAG"
            echo "WATCHER_NOT_RUNNING"
            echo "trigger_gtest.flag was not picked up within ${PICKUP_WAIT}s, and the watcher does not look busy. Ask the user to start run_watcher.cmd (or check that it targets this folder: $DIR)."
            exit 3
        fi
    fi
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        # 回収されていないフラグは、取り下げる。回収されていれば、ウォッチャーは、続けている
        if [ -f "$FLAG" ]; then rm -f "$FLAG"; fi
        echo "TIMEOUT"
        echo "gtest_result.txt (for this run) did not appear within ${TIMEOUT}s. The watcher may still be working (busy file: $(watcher_busy && echo present || echo absent)). Do NOT start another run until the watcher is idle: report and stop."
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
