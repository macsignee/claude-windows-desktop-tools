#!/usr/bin/env bash
# git_once.sh - ホスト側ウォッチャーに、Windows の git.exe で、リモートの操作 (状態・fetch・push) をさせ、完了まで待って結果を返す。
# 認証は、Windows の Git Credential Manager (Visual Studio の Git と同じ保管先)。GitHub 以外のリモートでも、VS と同じ認証で通る。
#
# Usage: git_once.sh <solution_dir> [--timeout 秒] [<モード>...]
#   <solution_dir>: リポジトリ (またはその中) のフォルダ (ウォッチャーの TargetDir)
#   モード (何も指定しない = --status):
#     --status                状態だけ (BRANCH / UPSTREAM / REMOTE / AHEAD / BEHIND / push される予定のコミット)。読み取りだけ。他のモードとは併用できない
#     --fetch [<リモート名>]  fetch (リモート名を省略すると、すべてのリモート)。作業フォルダを変えない
#     --push                  現在のブランチを push する (ユーザーが「push して」と頼んだときだけ)。作業フォルダ・インデックスを変えない
#       --remote <名前>       push 先のリモート名 (省略: 上流のリモート、なければ origin)。設定済みのリモート名だけ (URL は不可)
#       --set-upstream        上流を設定する (初めての push)
#       --allow-main          現在のブランチが main / master でも push する (ユーザーが、そう言ったときだけ)
#   --fetch と --push は併用できる (fetch → push の順)。最後に、必ず状態 (status) を返す。
#   持たない操作: 強制 push (--force / --force-with-lease)・ブランチやタグの削除・--tags・--mirror・pull・merge・rebase。引数として、断る。
#   --timeout: 完了マーカーを待つ秒数 (既定 180)
#
# 標準出力の1行目と終了コード:
#   OK                   rc=0  成功 (2 行目以降に、事実)
#   FAILED               rc=1  失敗 (理由。HEAD が切り離されている・リモートがない、など)
#   BAD_ARGS             rc=2  引数の形が不正
#   WATCHER_NOT_RUNNING  rc=3  フラグが回収されない = ウォッチャー未起動 (または、古い版)
#   ENV_ERROR            rc=4  環境エラー (git.exe が見つからない)
#   TIMEOUT              rc=5  完了マーカーが出ない。ウォッチャーは続けているかもしれない: 報告して止まる
#   AUTH_REQUIRED        rc=6  認証が要る。ユーザーが、VS (Git > プッシュ) で、1 回サインインする
#   REJECTED             rc=7  リモートに拒否された (non-fast-forward・保護されたブランチ、など)
set -u

PICKUP_WAIT="${CLAUDE_PICKUP_WAIT:-15}"
MAX_OUT=80
bad() { echo "BAD_ARGS: $*"; exit 2; }

DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || bad "solution dir not found: $DIR"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 大文字小文字を、実際のフォルダ名に直す (package_once.sh・vs_once.sh と同じ理由: /mnt は、大文字小文字を区別しないが、サンドボックスの書き込み許可は、区別する)
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
TIMEOUT=180
STATUS=0; FETCH=0; FETCH_REMOTE=""; PUSH=0; PUSH_REMOTE=""; SETUP=0; ALLOWMAIN=0
name_ok() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
while [ $# -gt 0 ]; do
    case "$1" in
        --timeout) [[ "${2:-}" =~ ^[0-9]+$ ]] || bad "--timeout needs a number of seconds"; TIMEOUT="$2"; shift 2 ;;
        --status) STATUS=1; shift ;;
        --fetch)
            FETCH=1; shift
            if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
                name_ok "$1" || bad "--fetch takes a configured remote name only (letters, digits, . _ -): $1"
                FETCH_REMOTE="$1"; shift
            fi ;;
        --push) PUSH=1; shift ;;
        --remote)
            [ $# -ge 2 ] || bad "--remote needs a remote name"
            name_ok "$2" || bad "--remote takes a configured remote name only (letters, digits, . _ -; no URL): $2"
            PUSH_REMOTE="$2"; shift 2 ;;
        --set-upstream) SETUP=1; shift ;;
        --allow-main) ALLOWMAIN=1; shift ;;
        *) bad "unknown option: $1" ;;
    esac
done
[ "$SETUP" -eq 1 ] && [ "$PUSH" -eq 0 ] && bad "--set-upstream is only for --push"
[ "$ALLOWMAIN" -eq 1 ] && [ "$PUSH" -eq 0 ] && bad "--allow-main is only for --push"
[ -n "$PUSH_REMOTE" ] && [ "$PUSH" -eq 0 ] && bad "--remote is only for --push"
[ "$STATUS" -eq 1 ] && [ $((FETCH + PUSH)) -gt 0 ] && bad "--status cannot be combined with --fetch / --push (the status is always returned at the end)"

OPS=()
if [ "$FETCH" -eq 1 ]; then OPS+=("fetch${FETCH_REMOTE:+ $FETCH_REMOTE}"); fi
if [ "$PUSH" -eq 1 ]; then
    l="push"
    [ -n "$PUSH_REMOTE" ] && l="$l remote=$PUSH_REMOTE"
    [ "$SETUP" -eq 1 ] && l="$l set-upstream"
    [ "$ALLOWMAIN" -eq 1 ] && l="$l allow-main"
    OPS+=("$l")
fi
OPS+=("status")

FLAG="$DIR/trigger_git.flag"
RESULT="$DIR/git_result.txt"
ERRLOG="$DIR/git_error.log"
OUTFILE="$DIR/git_output.txt"

show() {
    [ -f "$1" ] || return 0
    local total
    total=$(wc -l < "$1")
    sed 's/^\xEF\xBB\xBF//; s/\r$//' "$1" | cut -c1-400 | head -n "$MAX_OUT"
    [ "$total" -gt "$MAX_OUT" ] && echo "... ($total lines total; see $1)"
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

rm -f "$RESULT" "$ERRLOG" "$OUTFILE" "$RUN_ID_FILE"
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
            echo "trigger_git.flag was not picked up within ${PICKUP_WAIT}s, and the watcher does not look busy. Ask the user to start run_watcher.cmd (or check that it targets this folder: $DIR). The watcher must be the version that supports trigger_git.flag (HOST_VERSION 2.102.0 or later; redistribute with install.sh and restart it)."
            exit 3
        fi
    fi
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        [ -f "$FLAG" ] && rm -f "$FLAG"
        echo "TIMEOUT"
        echo "git_result.txt (for this run) did not appear within ${TIMEOUT}s. git may be waiting on the network or on a sign-in. Do NOT start another run; report to the user and stop."
        exit 5
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

sleep 0.3
VALUE="$(tr -d '\r\n ' < "$RESULT")"
case "$VALUE" in
    OK)
        echo "OK"; show "$OUTFILE"; exit 0 ;;
    AUTH_REQUIRED)
        echo "AUTH_REQUIRED"; show "$ERRLOG"; exit 6 ;;
    REJECTED)
        echo "REJECTED"; show "$ERRLOG"; exit 7 ;;
    FAILED)
        if [ -f "$ERRLOG" ] && head -n 1 "$ERRLOG" | sed 's/^\xEF\xBB\xBF//' | grep -q '^\[ENVIRONMENT ERROR'; then
            echo "ENV_ERROR"; show "$ERRLOG"; exit 4
        fi
        echo "FAILED"; show "$ERRLOG"; exit 1 ;;
    *)
        echo "ENV_ERROR"
        echo "unexpected git_result.txt: '$VALUE'"
        exit 4 ;;
esac
