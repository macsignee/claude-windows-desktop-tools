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
PICKUP_WAIT="${CLAUDE_PICKUP_WAIT:-15}"   # フラグが回収されるまでの許容秒数 (ウォッチャーは1秒周期。テスト用に、環境変数 CLAUDE_PICKUP_WAIT で変えられる)
MAX_DETAIL=60    # 詳細ログの最大行数 (トークン節約)

if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
    echo "BAD_ARGS: solution dir not found: $DIR"
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
python3 -I "$(dirname "${BASH_SOURCE[0]}")/fix_cpp_encoding.py" "$DIR" || true

# 終了時 (どの結果のときも): WPF の XAML にメニューがあれば、ユーザーのデスクトップのウォッチャーを使う旨を、知らせる (1 行目と終了コードは、変えない)
# 続けて、テストの改変の検査の結果 (TEST_GUARD: の行。基準があるときだけ) を、末尾に出す。UI テスト (uitest_once.sh) は、自分の出力の末尾で出す
# その前に、結果の自己記述と、Skill・ウォッチャーの版の不一致 (harness_note.sh。警告だけ)。UI テストでも、ここで出る (uitest_once.sh は、この出力を、そのまま出す)
trap 'bash "$(dirname "${BASH_SOURCE[0]}")/harness_note.sh" "$DIR"; bash "$(dirname "${BASH_SOURCE[0]}")/wpf_menu_note.sh" "$DIR"; [ -n "${BUILD_TEST_FLAG:-}" ] || bash "$(dirname "${BASH_SOURCE[0]}")/test_guard_note.sh" "$DIR"' EXIT

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
rm -f "$BUILD_RESULT" "$BUILD_ERR" "$TEST_RESULT" "$TEST_ERR" "$RUN_ID_FILE"
rm -f "$DIR/.claude-logs/build_summary.json" "$DIR/.claude-logs/test_summary.json"   # 前回の要約 (JSON) も消す (今回の結果と取り違えない。ENV_ERROR / PASSED では更新されないため)
rm -rf "$DIR/.claude-logs/test-results"   # 前回の、構造化された結果 (XML / trx) も、古い結果の誤読を防ぐために消す
# BUILD_TEST_FLAG_CONTENT があれば、フラグの中身にする (uitest_once.sh の --visible / --separate / --slowmo。ウォッチャーが、1 回ごとの指定として読む)
# 1 行目は、実行 ID (run=...。ウォッチャーが、結果と一緒に、返す)。
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
{ printf 'run=%s\n' "$RUN_ID"; if [ -n "${BUILD_TEST_FLAG_CONTENT:-}" ]; then printf '%s\n' "$BUILD_TEST_FLAG_CONTENT"; fi; } > "$FLAG"
check_flag_written

elapsed=0
picked_up=0
while ! result_ready "$TEST_RESULT"; do
    if [ "$picked_up" -eq 0 ]; then
        if [ ! -f "$FLAG" ]; then
            picked_up=1
        elif [ "$elapsed" -ge "$PICKUP_WAIT" ] && ! watcher_busy; then
            rm -f "$FLAG"
            echo "WATCHER_NOT_RUNNING"
            echo "$(basename "$FLAG") was not picked up within ${PICKUP_WAIT}s, and the watcher does not look busy. Ask the user to start run_watcher.cmd (or check that it targets this folder: $DIR)."
            case "$(basename "$FLAG")" in trigger_uitest.flag) echo "If the watcher is running, it may be an old version without UI test support: run ~/src/copy-host-tools.sh and restart the watcher (run_watcher.cmd)." ;; esac
            exit 3
        fi
    fi
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        # 回収されていないフラグは、取り下げる (あとで、思いがけず、実行されない)。回収されていれば、ウォッチャーは、続けている
        if [ -f "$FLAG" ]; then rm -f "$FLAG"; fi
        echo "TIMEOUT"
        echo "test_result.txt (for this run) did not appear within ${TIMEOUT}s. The watcher may still be working (busy file: $(watcher_busy && echo present || echo absent)). Do NOT start another run until the watcher is idle: report and stop."
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
