#!/usr/bin/env bash
# vs_once.sh - ホスト側ウォッチャーに、Windows の Visual Studio を操作させ (開く・前面・ブレークポイント・デバッグ実行)、完了まで待って結果を返す。
#
# Usage: vs_once.sh <solution_dir> [--timeout 秒] <モード>...
#   <solution_dir>: .sln / .slnx のあるフォルダ (ウォッチャーの TargetDir)
#   モード (何も指定しない = 開く / 前面に出す):
#     --status         状態だけ (SOLUTION / OPEN / INSTANCES / DEBUG_MODE / DIRTY)。VS を起動しない。他のモードとは併用できない
#     --reload         git で変更・追加したファイルのうち、VS で開いていて、未保存の編集がないものを、開き直す
#     --changes        git の差分 (追記・変更したコードの行。hunk ごとに 1 つ、最大 10) にブレークポイントを置く (先に、このツールが置いたものを消す)
#     --break <相対パス>:<行>   ブレークポイントを、1 つ置く (複数回指定できる)。--changes と併用できる
#     --clear          このツールが置いたブレークポイントを消す
#     --inspect        (v2.99.0) ブレークで止まっているときの状態: 呼び出し履歴 (STACK:)・ローカル変数 (LOCALS:)・例外 (EXCEPTION:)。読み取りだけ
#     --output [行数]  (v2.99.0) VS の出力ウィンドウの「デバッグ」ペイン (Debug.WriteLine / Trace / OutputDebugString / TRACE) の、最後の行数 (既定 200。1〜500)。
#                      全文は <solution_dir>/vs_debug_output.txt に残り、この標準出力には、最後の 60 行だけを出す。読み取りだけ (ペインを消さない)
#                      --inspect / --output だけを指定したとき (動作のモードと併用しないとき) は、--status と同じに、VS を起動せず、前面にも出さない
#     --step over|into|out [歩数]  (v2.101.0) ステップ実行 (F10 / F11 / Shift+F11)。歩数は 1〜30 (既定 1)。1 歩ごとに `STEP n: ファイル:行  ソースの行` と、変わった変数 (`CHANGED:`) を返す。
#                      1 回の実行の合計は 30 歩まで (複数回の指定の合計)。ブレークで止まっているときだけ。VS を起動せず、前面にも出さない
#     --continue       (v2.101.0) 続行 (F5)。次のブレークポイントか、終了まで (最大 20 秒待つ)
#     --pause          (v2.101.0) 走っているアプリを止める (ブレークにする)
#     --eval "<式>"    (v2.101.0) 式の値を返す (ウォッチ)。読み取りだけ: 代入・++・--・; を断る。200 文字まで、1 回の実行で 10 個まで。止まっているときだけ
#                      実行系 (--step / --continue / --pause / --eval) は、指定した順に実行する。--debug と併用すると、デバッグを始めたあとに実行する。デバッグの停止 (Shift+F5) は、ユーザーの操作 (操作を持たない)
#     --debug          デバッグ実行を始める (ユーザーが「デバッグを実行して」と言ったときだけ)。ブレークポイントを置くだけでは、実行しない
#     --frame <N>      (v2.107.0。--inspect か --eval と併用。--debug / --status / --step / --continue / --pause とは併用しない) N 番目のスタック フレームを選んで、LOCALS: と --eval を読む (0 = 先頭。読んだら、元のフレームに戻る)。STACK: の各フレームには、所有者の印 ([ours] [ext] [sys] [unknown]) と、OWNER: / BOUNDARY: の要約が付く (stack_owner.py。ヒントであり、断定ではない)
#     --no-wait        (--debug と併用) アプリが起動したら、ブレークポイントに着くのを待たずに返す (結果は DEBUG_MODE: run)。UI テストのアタッチ (uitest_once.sh --attach) で、きっかけの操作を撃つ前に使う
#   --timeout: 完了マーカーを待つ秒数 (既定 240。VS の起動とソリューションの読み込みを含む)
#
# 標準出力の1行目と終了コード:
#   OK                   rc=0  成功 (2 行目以降に、事実: DIRTY: / DEBUG_MODE: / BREAK_SET: など)
#   FAILED               rc=1  失敗 (理由。複数の VS・すでにデバッグ中・ファイルがない、など)
#   ENV_ERROR            rc=4  環境エラー (VS が見つからない・開かない)
#   WATCHER_NOT_RUNNING  rc=3  フラグが回収されない = ウォッチャー未起動
#   TIMEOUT              rc=5  完了マーカー (vs_result.txt。この実行のもの) が出ない。ウォッチャーは続けているかもしれない: 報告して止まる
#   BAD_ARGS             rc=2  引数の形が不正
set -u

MAX_OUT=150   # 30 歩のトレース (1 歩 = 2〜4 行) が、切れないように
PICKUP_WAIT="${CLAUDE_PICKUP_WAIT:-15}"
bad() { echo "BAD_ARGS: $*"; exit 2; }

DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || bad "solution dir not found: $DIR"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 大文字小文字を、実際のフォルダ名に直す (package_once.sh と同じ理由: /mnt は、大文字小文字を区別しないが、サンドボックスの書き込み許可は、区別する)
resolve_true_case() {
    local input="$1" resolved="" component parent names chosen
    case "$input" in /*) ;; *) printf '%s\n' "$input"; return 0 ;; esac
    local IFS=/
    local -a parts
    read -ra parts <<< "$input"
    for component in "${parts[@]}"; do
        [ -z "$component" ] && continue
        parent="${resolved:-/}"
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
align_to_launch_case() {
    local d="$1" p="$PWD"
    if [ "${d,,}" = "${p,,}" ]; then printf '%s\n' "$p"
    elif [[ "${d,,}" == "${p,,}/"* ]]; then printf '%s\n' "$p/${d:$((${#p}+1))}"
    else printf '%s\n' "$d"; fi
}
DIR="$(align_to_launch_case "$DIR")"

hnote="$SELF_DIR/../../build-test-loop/scripts/harness_note.sh"
trap '[ -f "$hnote" ] && bash "$hnote" "$DIR"' EXIT

shift
TIMEOUT=240
STATUS_ONLY=0; RELOAD=0; CHANGES=0; CLEAR=0; DEBUG=0; NOWAIT=0; FRAME=""; INSPECT=0; OUTPUT=0; OUTPUT_N=200
RUNOPS=(); STEPS_TOTAL=0; EVALS=0   # 実行系の操作 (step / continue / pause / eval)。指定した順
BREAKS=()
RE_PATH='^[^[:cntrl:]"<>|*?:]+$'
while [ $# -gt 0 ]; do
    case "$1" in
        --timeout) TIMEOUT="${2:-}"; shift 2 || bad "--timeout needs a value" ;;
        --status) STATUS_ONLY=1; shift ;;
        --reload) RELOAD=1; shift ;;
        --changes) CHANGES=1; shift ;;
        --clear) CLEAR=1; shift ;;
        --debug) DEBUG=1; shift ;;
        --no-wait) NOWAIT=1; shift ;;
        --inspect) INSPECT=1; shift ;;
        --frame)
            v="${2:-}"; shift 2 || bad "--frame needs a frame number (0 to 99)"
            [[ "$v" =~ ^[0-9]+$ ]] || bad "--frame needs a frame number (0 to 99): $v"
            FRAME=$((10#$v))
            [ "$FRAME" -le 99 ] || bad "--frame needs a frame number from 0 to 99: $v"
            ;;
        --continue) RUNOPS+=("continue"); shift ;;
        --pause) RUNOPS+=("pause"); shift ;;
        --step)
            kind="${2:-}"
            case "$kind" in over|into|out) ;; *) bad "--step needs over / into / out: ${kind:-(none)}" ;; esac
            shift 2
            n=1
            if [[ "${1:-}" =~ ^[0-9]+$ ]]; then n=$((10#$1)); shift; fi
            { [ "$n" -ge 1 ] && [ "$n" -le 30 ]; } || bad "--step needs a number of steps from 1 to 30: $n"
            STEPS_TOTAL=$((STEPS_TOTAL + n))
            [ "$STEPS_TOTAL" -le 30 ] || bad "the steps of one run must add up to 30 or less (stepping is limited to 30 steps per request): $STEPS_TOTAL"
            RUNOPS+=("step $kind $n")
            ;;
        --eval)
            e="${2:-}"; shift 2 || bad "--eval needs an expression"
            [ -n "$e" ] || bad "--eval needs an expression"
            [ "${#e}" -le 200 ] || bad "--eval: the expression must be 200 characters or less"
            case "$e" in *$'\n'*|*';'*) bad "--eval: one expression only (no newline, no ';')" ;; esac
            t="${e//==/  }"; t="${t//!=/  }"; t="${t//<=/  }"; t="${t//>=/  }"
            case "$e" in *'<<='*|*'>>='*) bad "--eval is read-only: an assignment is not allowed: $e" ;; esac
            case "$t" in *=*) bad "--eval is read-only: an assignment is not allowed: $e" ;; esac
            case "$e" in *'++'*|*'--'*) bad "--eval is read-only: ++ / -- are not allowed: $e" ;; esac
            EVALS=$((EVALS + 1))
            [ "$EVALS" -le 10 ] || bad "--eval: up to 10 expressions per run"
            RUNOPS+=("eval $e")
            ;;
        --output)
            OUTPUT=1
            if [[ "${2:-}" =~ ^[0-9]+$ ]]; then OUTPUT_N=$((10#$2)); shift 2; else shift; fi
            { [ "$OUTPUT_N" -ge 1 ] && [ "$OUTPUT_N" -le 500 ]; } || bad "--output needs a number of lines from 1 to 500: $OUTPUT_N"
            ;;
        --break)
            b="${2:-}"; shift 2 || bad "--break needs <path>:<line>"
            [[ "$b" =~ ^(.+):([0-9]{1,6})$ ]] || bad "--break needs <relative path>:<line>: $b"
            p="${BASH_REMATCH[1]}"
            [[ "$p" =~ $RE_PATH ]] || bad "invalid path: $p"
            case "/${p//\\//}/" in */../*) bad "path must be relative, without ..: $p" ;; esac
            case "$p" in /*|[A-Za-z]:*) bad "path must be relative to the solution folder: $p" ;; esac
            BREAKS+=("$b")
            ;;
        *) bad "unknown option: $1" ;;
    esac
done
[ "$NOWAIT" -eq 0 ] || [ "$DEBUG" -eq 1 ] || bad "--no-wait needs --debug"
if [ -n "$FRAME" ]; then
    # フレームの選択は、止まっているときの読み取り (--inspect / --eval) だけ。実行系とは、併用しない (実行すると、先頭のフレームに戻る)
    { [ "$INSPECT" -eq 1 ] || [ "$EVALS" -gt 0 ]; } || bad "--frame needs --inspect or --eval"
    { [ "$DEBUG" -eq 0 ] && [ "$STATUS_ONLY" -eq 0 ]; } || bad "--frame cannot be combined with --debug or --status"
    for r in "${RUNOPS[@]+"${RUNOPS[@]}"}"; do
        case "$r" in eval\ *) ;; *) bad "--frame cannot be combined with --step / --continue / --pause" ;; esac
    done
fi
case "$TIMEOUT" in ''|*[!0-9]*) bad "timeout must be a positive integer (seconds): $TIMEOUT" ;; esac
if [ "$STATUS_ONLY" -eq 1 ] && [ $((RELOAD + CHANGES + CLEAR + DEBUG + INSPECT + OUTPUT + ${#BREAKS[@]} + ${#RUNOPS[@]})) -gt 0 ]; then
    bad "--status cannot be combined with other modes"
fi

# ---- フラグの内容 (ウォッチャーが、1 行 1 操作で、上から実行する) ----
OPS=()
ACTION=$((RELOAD + CHANGES + CLEAR + DEBUG + ${#BREAKS[@]}))
if [ "$STATUS_ONLY" -eq 1 ]; then
    OPS+=("status")
elif [ "$ACTION" -eq 0 ] && [ $((INSPECT + OUTPUT + ${#RUNOPS[@]})) -gt 0 ]; then
    # 読み取り・実行系だけ (--status と同じ): VS を起動せず、前面にも出さない
    [ -z "$FRAME" ] || OPS+=("frame $FRAME")
    for r in "${RUNOPS[@]+"${RUNOPS[@]}"}"; do OPS+=("$r"); done
    [ "$INSPECT" -eq 1 ] && OPS+=("inspect")
    [ "$OUTPUT" -eq 1 ] && OPS+=("output $OUTPUT_N")
    OPS+=("status")
else
    OPS+=("open")
    if [ "$RELOAD" -eq 1 ]; then
        while IFS= read -r f; do
            [ -n "$f" ] && OPS+=("reload $f")
        done < <(python3 "$SELF_DIR/changed_lines.py" "$DIR" --names 2>/dev/null | head -n 40)
    fi
    if [ "$CHANGES" -eq 1 ] || [ "$CLEAR" -eq 1 ]; then OPS+=("clear"); fi
    if [ "$CHANGES" -eq 1 ]; then
        cl="$(python3 "$SELF_DIR/changed_lines.py" "$DIR" 2>&1)"; rc=$?
        [ "$rc" -eq 3 ] && bad "the solution folder is not a git repository (use --break <path>:<line> instead): $DIR"
        [ "$rc" -eq 0 ] || bad "changed_lines.py failed: $cl"
        CHANGE_NOTES="$(grep -E '^(NEW_FILE|TRUNCATED):' <<<"$cl")"
        while IFS= read -r l; do
            [[ "$l" =~ ^[^:\ ]([^:]*):[0-9]+$ ]] && OPS+=("break $l")
        done <<< "$cl"
    fi
    for b in "${BREAKS[@]+"${BREAKS[@]}"}"; do OPS+=("break $b"); done
    if [ "$DEBUG" -eq 1 ]; then if [ "$NOWAIT" -eq 1 ]; then OPS+=("debug nowait"); else OPS+=("debug"); fi; fi
    [ -z "$FRAME" ] || OPS+=("frame $FRAME")
    for r in "${RUNOPS[@]+"${RUNOPS[@]}"}"; do OPS+=("$r"); done
    [ "$INSPECT" -eq 1 ] && OPS+=("inspect")
    [ "$OUTPUT" -eq 1 ] && OPS+=("output $OUTPUT_N")
    OPS+=("status")
fi
CHANGE_NOTES="${CHANGE_NOTES:-}"

FLAG="$DIR/trigger_vs.flag"
RESULT="$DIR/vs_result.txt"
ERRLOG="$DIR/vs_error.log"
OUTFILE="$DIR/vs_output.txt"
CAPFILE="$DIR/vs_debug_output.txt"   # --output の全文 (ウォッチャーが書く)
MAX_CAP=60

show() {
    [ -f "$1" ] || return 0
    local total content=""
    if [ "$1" = "$OUTFILE" ] && grep -aq 'STACK: #' "$1"; then
        # STACK: の各フレームに、所有者の印 (ours / ext / sys / unknown) と、OWNER: / BOUNDARY: の要約を付ける (v2.107.0)。
        # python3 がない・スクリプトが失敗したときは、印なしの、元の出力を出す (EXCEPTION: / LOCALS: / STOPPED: を、失わない)
        content="$(python3 -I "$SELF_DIR/stack_owner.py" "$1" 2>/dev/null)" || content=""
    fi
    [ -n "$content" ] || content="$(sed 's/^\xEF\xBB\xBF//; s/\r$//' "$1")"
    [ -n "$content" ] || return 0
    total=$(printf '%s\n' "$content" | wc -l)
    printf '%s\n' "$content" | cut -c1-400 | head -n "$MAX_OUT"
    [ "$total" -gt "$MAX_OUT" ] && echo "... ($total lines total; see $1)"
    return 0
}

# --output の取り込み: 最後の MAX_CAP 行だけを出す (全文は、ファイルを読む)
show_capture() {
    [ -f "$CAPFILE" ] || return 0
    local total shown
    total=$(wc -l < "$CAPFILE")
    shown=$total; [ "$shown" -gt "$MAX_CAP" ] && shown=$MAX_CAP
    echo "=== VS debug output (last $shown of $total captured lines; full: $CAPFILE) ==="
    sed 's/^\xEF\xBB\xBF//; s/\r$//' "$CAPFILE" | cut -c1-400 | tail -n "$MAX_CAP"
    return 0
}

RUN_ID="$(date +%s)-$$-$RANDOM"
RUN_ID_FILE="$DIR/.claude-logs/run_id.txt"
BUSY_FILE="$DIR/.claude-logs/watcher_busy.txt"
result_ready() {
    [ -f "$1" ] || return 1
    [ -f "$RUN_ID_FILE" ] || return 0
    [ "$(sed 's/^\xEF\xBB\xBF//; s/\r$//' "$RUN_ID_FILE" | head -n 1)" = "run=$RUN_ID" ]
}
watcher_busy() { [ -f "$BUSY_FILE" ] && [ -n "$(find "$BUSY_FILE" -mmin -60 2>/dev/null)" ]; }

rm -f "$RESULT" "$ERRLOG" "$OUTFILE" "$CAPFILE" "$RUN_ID_FILE"
{ printf '# run=%s\n' "$RUN_ID"; printf '%s\n' "${OPS[@]}"; } > "$FLAG"
if [ ! -f "$FLAG" ]; then
    echo "ENV_ERROR"
    echo "Could not write $(basename "$FLAG"): $FLAG (nothing was started). Check the write permission of this folder (sandbox) and the letter case of the folder Claude Code was started in."
    exit 4
fi

elapsed=0; picked_up=0
while ! result_ready "$RESULT"; do
    if [ "$picked_up" -eq 0 ]; then
        if [ ! -f "$FLAG" ]; then
            picked_up=1
        elif [ "$elapsed" -ge "$PICKUP_WAIT" ] && ! watcher_busy; then
            rm -f "$FLAG"
            echo "WATCHER_NOT_RUNNING"
            echo "trigger_vs.flag was not picked up within ${PICKUP_WAIT}s, and the watcher does not look busy. Ask the user to start run_watcher.cmd (or check that it targets this folder: $DIR). The watcher must be the version that supports trigger_vs.flag (HOST_VERSION 2.90.0 or later; redistribute with install.sh and restart it)."
            exit 3
        fi
    fi
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        [ -f "$FLAG" ] && rm -f "$FLAG"
        echo "TIMEOUT"
        echo "vs_result.txt (for this run) did not appear within ${TIMEOUT}s. Visual Studio may still be starting or may be showing a dialog. Do NOT start another run; report to the user and stop."
        exit 5
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

sleep 0.3
STATUS="$(tr -d '\r\n ' < "$RESULT")"
notes() { [ -n "$CHANGE_NOTES" ] && printf '%s\n' "$CHANGE_NOTES"; return 0; }

case "$STATUS" in
    OK)
        echo "OK"
        show "$OUTFILE"
        show_capture
        notes
        exit 0
        ;;
    FAILED)
        if [ -f "$ERRLOG" ] && head -n 1 "$ERRLOG" | sed 's/^\xEF\xBB\xBF//' | grep -q '^\[ENVIRONMENT ERROR'; then
            echo "ENV_ERROR"
            show "$ERRLOG"
            exit 4
        fi
        echo "FAILED"
        show "$ERRLOG"
        exit 1
        ;;
    *)
        echo "ENV_ERROR"
        echo "unexpected vs_result.txt: '$STATUS'"
        exit 4
        ;;
esac
