#!/usr/bin/env bash
# package_once.sh - ホスト側ウォッチャーに、パッケージの操作 (NuGet / vcpkg / ソースの取得) を 1 回させ、完了まで待って結果を返す。
#
# Usage: package_once.sh <solution_dir> [--timeout 秒] <操作>...
#        package_once.sh <solution_dir> [--timeout 秒] --file <操作の一覧ファイル>
#   <solution_dir>: .sln / .slnx のあるフォルダ (ウォッチャーの TargetDir)
#   <操作>: 1 引数に 1 操作 (引用符で囲む)。許可する形:
#       nuget search <語>
#       nuget versions <ID>
#       nuget add <プロジェクト> <ID> [<バージョン>]
#       nuget remove <プロジェクト> <ID>
#       vcpkg search <語>
#       vcpkg baseline
#       vcpkg install
#       fetch <owner/repo> <タグ> <名前> [<サブフォルダ>]
#   --file: 1 行 1 操作のファイル (空行と # 行は無視。ThirdParty.manifest など)。--file と <操作> は、併用できる (先に <操作>)。
#   --timeout: 完了マーカーを待つ秒数 (既定 300)。vcpkg install は、長いので、1800 など。
#
# 引数は、ホスト側のコマンドに渡るので、ここでも、決まった形だけを許可する (ウォッチャーも、同じ規則で検証する)。
#
# 標準出力の1行目と終了コード:
#   OK                   rc=0  成功 (2 行目以降に、各操作の出力)
#   FAILED               rc=1  失敗 (原因。ソース側の問題: パッケージ名の誤りなど)
#   ENV_ERROR            rc=4  環境エラー (ネットワーク・vcpkg / dotnet がない。ソースの問題ではない)
#   WATCHER_NOT_RUNNING  rc=3  フラグが回収されない = ウォッチャー未起動
#   TIMEOUT              rc=5  完了マーカー (package_result.txt。この実行のもの) が出ない。ウォッチャーは、続けているかもしれない: 報告して止まる
#                              (フラグは、実行 ID の照合で、前の実行の古い結果を、今回の結果と取り違えない)
#   BAD_ARGS             rc=2  引数・操作の形が不正
set -u

MAX_OUT=80   # 出力の最大行数 (トークン節約)
PICKUP_WAIT="${CLAUDE_PICKUP_WAIT:-15}"

bad() { echo "BAD_ARGS: $*"; exit 2; }

DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || bad "solution dir not found: $DIR"
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

shift
TIMEOUT=300
OPS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --timeout) TIMEOUT="${2:-}"; shift 2 || bad "--timeout needs a value" ;;
        --file)
            f="${2:-}"; shift 2 || bad "--file needs a path"
            [ -f "$f" ] || bad "file not found: $f"
            while IFS= read -r line || [ -n "$line" ]; do
                line="$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
                case "$line" in ''|'#'*) continue ;; esac
                OPS+=("$line")
            done < "$f"
            ;;
        *) OPS+=("$1"); shift ;;
    esac
done
case "$TIMEOUT" in ''|*[!0-9]*) bad "timeout must be a positive integer (seconds): $TIMEOUT" ;; esac
[ "${#OPS[@]}" -gt 0 ] || bad "no operation given"

# ---- 操作の形の検証 (ウォッチャーと同じ規則) ----
RE_ID='^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'
RE_VER='^[0-9][0-9A-Za-z.+-]{0,63}$'
RE_TERM='^[A-Za-z0-9][A-Za-z0-9._+-]{0,59}$'
RE_REPO='^[A-Za-z0-9][A-Za-z0-9._-]{0,99}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'
RE_TAG='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
RE_NAME='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
RE_PROJ='^[A-Za-z0-9._/\\-]+\.(csproj|vbproj|fsproj)$'
RE_SEG='^[A-Za-z0-9._-]+$'

valid_op() {  # $1=操作の 1 行。不正なら、理由を標準出力に出して 1
    local op="$1" t
    # shellcheck disable=SC2206
    t=($op)
    local n=${#t[@]}
    [ "$n" -ge 1 ] || { echo "empty operation"; return 1; }
    case "${t[0]}" in
        fetch)
            { [ "$n" -eq 4 ] || [ "$n" -eq 5 ]; } || { echo "usage: fetch <owner/repo> <tag> <name> [<subfolder>]"; return 1; }
            [[ "${t[1]}" =~ $RE_REPO ]] || { echo "invalid repo: ${t[1]}"; return 1; }
            [[ "${t[2]}" =~ $RE_TAG ]] || { echo "invalid tag: ${t[2]}"; return 1; }
            [[ "${t[3]}" =~ $RE_NAME ]] || { echo "invalid name: ${t[3]}"; return 1; }
            if [ "$n" -eq 5 ]; then
                local seg
                IFS='/' read -ra segs <<< "${t[4]//\\//}"
                for seg in "${segs[@]}"; do
                    [[ "$seg" =~ $RE_SEG ]] && [ "$seg" != "." ] && [ "$seg" != ".." ] || { echo "invalid subfolder: ${t[4]}"; return 1; }
                done
            fi
            ;;
        nuget)
            case "${t[1]:-}" in
                search)   [ "$n" -eq 3 ] && [[ "${t[2]}" =~ $RE_TERM ]] || { echo "usage: nuget search <term>"; return 1; } ;;
                versions) [ "$n" -eq 3 ] && [[ "${t[2]}" =~ $RE_ID ]] || { echo "usage: nuget versions <id>"; return 1; } ;;
                add|remove)
                    if [ "${t[1]}" = add ]; then { [ "$n" -eq 4 ] || [ "$n" -eq 5 ]; } || { echo "usage: nuget add <project> <id> [<version>]"; return 1; }
                    else [ "$n" -eq 4 ] || { echo "usage: nuget remove <project> <id>"; return 1; }; fi
                    [[ "${t[2]}" =~ $RE_PROJ ]] || { echo "invalid project (a .csproj / .vbproj / .fsproj path under the solution folder): ${t[2]}"; return 1; }
                    case "/${t[2]//\\//}/" in */../*) echo "invalid project path: ${t[2]}"; return 1 ;; esac
                    [[ "${t[3]}" =~ $RE_ID ]] || { echo "invalid package id: ${t[3]}"; return 1; }
                    if [ "$n" -eq 5 ]; then [[ "${t[4]}" =~ $RE_VER ]] || { echo "invalid version: ${t[4]}"; return 1; }; fi
                    ;;
                *) echo "unknown nuget operation: $op (search / versions / add / remove)"; return 1 ;;
            esac
            ;;
        vcpkg)
            case "${t[1]:-}" in
                search)   [ "$n" -eq 3 ] && [[ "${t[2]}" =~ $RE_TERM ]] || { echo "usage: vcpkg search <term>"; return 1; } ;;
                baseline|install) [ "$n" -eq 2 ] || { echo "usage: vcpkg ${t[1]}"; return 1; } ;;
                *) echo "unknown vcpkg operation: $op (search / baseline / install)"; return 1 ;;
            esac
            ;;
        *) echo "unknown operation: $op (nuget ... / vcpkg ... / fetch ...)"; return 1 ;;
    esac
    return 0
}

for op in "${OPS[@]}"; do
    why="$(valid_op "$op")" || bad "$why"
done

FLAG="$DIR/trigger_package.flag"
RESULT="$DIR/package_result.txt"
ERRLOG="$DIR/package_error.log"
OUTFILE="$DIR/package_output.txt"

show() {  # $1=ファイル: BOM / CR を除き、1 行 400 文字、最大 MAX_OUT 行
    [ -f "$1" ] || return 0
    local total
    total=$(wc -l < "$1")
    sed 's/^\xEF\xBB\xBF//; s/\r$//' "$1" | cut -c1-400 | head -n "$MAX_OUT"
    [ "$total" -gt "$MAX_OUT" ] && echo "... ($total lines total; see $1)"
    return 0
}


# 実行 ID (v2.20.1 / build_once.sh と同じ仕組み): フラグに、実行 ID をコメント行 (# run=...) で書く (古いウォッチャーが、操作やタグと取り違えない形)。
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
rm -f "$RESULT" "$ERRLOG" "$OUTFILE" "$RUN_ID_FILE"
{ printf '# run=%s\n' "$RUN_ID"; printf '%s\n' "${OPS[@]}"; } > "$FLAG"

elapsed=0
picked_up=0
while ! result_ready "$RESULT"; do
    if [ "$picked_up" -eq 0 ]; then
        if [ ! -f "$FLAG" ]; then
            picked_up=1
        elif [ "$elapsed" -ge "$PICKUP_WAIT" ] && ! watcher_busy; then
            rm -f "$FLAG"
            echo "WATCHER_NOT_RUNNING"
            echo "trigger_package.flag was not picked up within ${PICKUP_WAIT}s, and the watcher does not look busy. Ask the user to start run_watcher.cmd (or check that it targets this folder: $DIR)."
            exit 3
        fi
    fi
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        # 回収されていないフラグは、取り下げる (あとで、思いがけず、実行されない)。回収されていれば、ウォッチャーは、続けている
        if [ -f "$FLAG" ]; then rm -f "$FLAG"; fi
        echo "TIMEOUT"
        echo "package_result.txt (for this run) did not appear within ${TIMEOUT}s. The watcher may still be working (busy file: $(watcher_busy && echo present || echo absent)). Do NOT start another run until the watcher is idle: report and stop. (The user may allow a rerun with a longer --timeout; finished ports are cached.)"
        exit 5
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

sleep 0.3   # マーカー書き込み直後の読み取り競合を避ける
STATUS="$(tr -d '\r\n ' < "$RESULT")"

case "$STATUS" in
    OK)
        echo "OK"
        show "$OUTFILE"
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
        echo "unexpected package_result.txt: '$STATUS'"
        exit 4
        ;;
esac
