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
PICKUP_WAIT="${CLAUDE_PICKUP_WAIT:-15}"   # フラグが回収されるまでの許容秒数 (ウォッチャーは1秒周期。テスト用に、環境変数 CLAUDE_PICKUP_WAIT で変えられる)

if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
    echo "BAD_ARGS: project dir not found: $DIR"
    exit 2
fi
# 数値でない制限時間だと、待機ループの比較が毎回エラーになり、永久に待ち続けてしまう
case "$TIMEOUT" in
    ''|*[!0-9]*) echo "BAD_ARGS: timeout must be a positive integer (seconds): $TIMEOUT"; exit 2 ;;
esac

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
# 日本語を含む、BOM なしの C++ ソースを、BOM 付きにそろえる (MSVC が ANSI として読んで、ビルドが止まるのを避ける。v2.82.0)
python3 -I "$(dirname "${BASH_SOURCE[0]}")/../../build-test-loop/scripts/fix_cpp_encoding.py" "$DIR" || true

# 終了時 (どの結果のときも): WPF の XAML にメニューがあれば、ユーザーのデスクトップのウォッチャーを使う旨を、知らせる (1 行目と終了コードは、変えない)
# 終了時 (どの結果のときも): 結果の自己記述 (RESULT_INFO) と、Skill・ウォッチャーの版の不一致 (NOTE。警告だけ) を、出力の末尾に出す (1 行目と終了コードは、変えない)
hnote="$(dirname "${BASH_SOURCE[0]}")/../../build-test-loop/scripts/harness_note.sh"
note="$(dirname "${BASH_SOURCE[0]}")/../../build-test-loop/scripts/wpf_menu_note.sh"
trap '[ -f "$note" ] && bash "$note" "$DIR"; [ -f "$hnote" ] && bash "$hnote" "$DIR"' EXIT

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


# 実行 ID (v2.20.0): この実行のフラグに、実行 ID (run=...) を書く。ウォッチャーは、結果のマーカーを書く直前に、同じ ID を .claude-logs/run_id.txt に書く。
# 前の実行 (TIMEOUT で、あきらめたが、ウォッチャーは、まだ続けていた実行) が、あとで書いた、古いマーカーを、今回の結果と取り違えないための照合。
# run_id.txt がない = 古いウォッチャー (この機能より前) → 照合なし (従来どおり)。
RUN_ID="$(date +%s)-$$-$RANDOM"
RUN_ID_FILE="$DIR/.claude-logs/run_id.txt"
BUSY_FILE="$DIR/.claude-logs/watcher_busy.txt"   # ウォッチャーが、処理中の間だけ、ある (処理の開始時に作り、終了時に消す)

result_ready() {  # $1=マーカーのファイル。マーカーがあり、かつ、実行 ID が、この実行のものか (古いウォッチャーなら、マーカーだけ)
    [ -f "$1" ] || return 1
    [ -f "$RUN_ID_FILE" ] || return 0
    [ "$(sed 's/^\xEF\xBB\xBF//; s/\r$//' "$RUN_ID_FILE" | head -n 1)" = "run=$RUN_ID" ]
}

watcher_busy() {  # ウォッチャーが、別の処理 (ビルド・テスト・パッケージ操作など) の最中か (60 分以内に、始まったもの)
    [ -f "$BUSY_FILE" ] && [ -n "$(find "$BUSY_FILE" -mmin -60 2>/dev/null)" ]
}

# 古い結果を必ず消してからフラグを置く (古いマーカーの誤読防止)
rm -f "$RESULT" "$ERRLOG" "$RUN_ID_FILE"
rm -f "$DIR/.claude-logs/build_summary.json"   # 前回の要約 (JSON) も消す (SUCCESS / ENV_ERROR では更新されないため、古い結果が残る)
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
printf 'run=%s\n' "$RUN_ID" > "$FLAG"
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
            echo "trigger_build.flag was not picked up within ${PICKUP_WAIT}s, and the watcher does not look busy. Ask the user to start run_watcher.cmd (or check that it targets this folder: $DIR)."
            exit 3
        fi
    fi
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        # 回収されていないフラグは、取り下げる (あとで、思いがけず、実行されない)。回収されていれば、ウォッチャーは、続けている
        if [ -f "$FLAG" ]; then rm -f "$FLAG"; fi
        echo "TIMEOUT"
        echo "build_result.txt (for this run) did not appear within ${TIMEOUT}s. The watcher may still be working (busy file: $(watcher_busy && echo present || echo absent)). Do NOT start another run until the watcher is idle: report and stop."
        exit 5
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

sleep 0.3   # マーカー書き込み直後の読み取り競合を避ける
STATUS="$(tr -d '\r\n ' < "$RESULT")"

if [ "$STATUS" = "SUCCESS" ]; then
    echo "SUCCESS"
    show_warnings_line
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
