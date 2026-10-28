#!/usr/bin/env bash
# uitest_once.sh - ホスト側ウォッチャーに「ビルド + UI テスト (FlaUI など) 実行」を1回させ、完了まで待って結果を返す。
#
# Usage: uitest_once.sh <solution_dir> [timeout_sec=900] [--visible | --separate | --invisible] [--slowmo <ms>] [--filter <式>] [--ui-timeout <秒>] [--hold <秒>] [--preview] [--present]
#   <solution_dir>: .sln/.slnx のあるフォルダ (ウォッチャーの TargetDir)
#   --visible:  この 1 回だけ、ユーザーのデスクトップで実行する (ウィンドウが見える。実行中、ユーザーは PC に触らない)。
#   --separate (別名 --invisible): この 1 回だけ、別のデスクトップで実行する (WPF でも。ウィンドウが画面に出ない。WPF のメニューは、開かない)。
#   --slowmo N: 操作の間に N ミリ秒の待ちを入れる (目で確かめるとき。例: 800)。
#   --filter 式: dotnet test の --filter の式で、UI テストを絞る (例: "FullyQualifiedName~LoginDialog")。UI を作りながら、いま書いたテストだけを、繰り返し実行するとき。
#                式に、引用符・改行は、使えない。絞った結果が 0 件のときは、テストが実行されない (式の誤りに、注意)。
#   --ui-timeout N: ウォッチャーが、UI テストのプロジェクト 1 つを、強制終了するまでの時間 (秒)。既定は、uitest.settings の timeout= → ウォッチャーの設定 (既定 600)。
#   待ち時間 (timeout_sec。指定がなければ): 600 (ビルド) + UI テストのプロジェクトの数 × (--ui-timeout、なければ 600) + --hold + 120。最低 900。
#   --hold N: テストが、最後の状態を、N 秒だけ、見せてから、終わる (目視確認。UiTestBase.HoldForViewing を呼ぶテストだけが、見せる。ユーザーが、アプリのウィンドウを閉じると、早く終わる)。
#             --visible と組み合わせて、**UI テストを、いつもは裏 (別のデスクトップ) で実行し、見たいときだけ、その画面を、ユーザーのデスクトップに出す**。
#   --preview [N]: --visible --hold N (既定 60 秒) の省略形。**--filter "TestCategory=Preview" など、画面を出すテストと組み合わせる。** N は、数字なら、続けて書く (--preview 120)。
#   --present: **UI テストを、デモ (プレゼン) として、ユーザーのデスクトップで、ゆっくり再生する。** --visible と、--slowmo 800 (指定がなければ) と、
#              操作する要素を赤い枠で囲む (UiTestBase の Find / OpenModal が描く) の、組み合わせ。**再生するのは、--filter で指定したテストだけ** (--filter が必須。
#              指定がなければ、全部を、ゆっくり再生してしまうので、BAD_ARGS)。--separate とは、同時に使えない。
#   UI テストは、ビルド → テスト (build_test_once.sh) の流れには、含まれない。UI の作成のループ (/ui-test-first) や、ユーザーが求めたときに、このスクリプトで実行する。
#   どちらも付けないとき (標準): ウォッチャーが決める。WPF のソリューションは、ユーザーのデスクトップ。それ以外は、別のデスクトップ。
#   (指定は、ウォッチャーを切り替えずに、trigger_uitest.flag の中身 (desktop= / slowmo=) として渡す。ウォッチャーが、新しい版である必要がある。)
#
# build_test_once.sh と同じ出力 (1行目と終了コード。PASSED のときの要約の行も同じ) の、UI テスト版。違いは次のとおり。
#   - フラグは trigger_uitest.flag。実行するのは、UI テストのプロジェクト (名前が UITests / UiTests で終わる、または FlaUI を参照)
#     だけ。通常のテスト (trigger_test.flag) からは、UI テストのプロジェクトは、除かれる。
#   - 既定の制限時間は 900 秒 (アプリの起動と操作を含むため)。ウォッチャー側の制限は、-UiTestTimeoutSec (既定 600、プロジェクトごと)。
#   - 実行中は、ユーザーが、マウスとキーボードに触らない (画面のロック・RDP の切断・最小化も避ける)。
#   - 失敗時のスクリーンショット (.claude-logs/ui-screenshots/*.png) があれば、最後に一覧を出す。Read ツールで、画像として読める。
#   - 操作の記録 (ui-trace.txt) があれば、テストごとの結果の行を出す (UI テストが、実際に動いたことの確認)。
#   - ユーザーのデスクトップで、目で確かめるには、--visible --slowmo 800 (ウォッチャーを、起動し直さなくてよい)。
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR=""
TIMEOUT=""
flag_content=""
positional=0
ui_timeout=""
hold=""
present=""
while [ $# -gt 0 ]; do
    case "$1" in
        --visible)  flag_content="${flag_content}desktop=visible"$'\n' ;;
        --separate|--invisible) flag_content="${flag_content}desktop=separate"$'\n' ;;
        --slowmo)
            shift
            case "${1:-}" in ''|*[!0-9]*) echo "BAD_ARGS: --slowmo needs a number (milliseconds): ${1:-}"; exit 2 ;; esac
            flag_content="${flag_content}slowmo=$1"$'\n' ;;
        --filter)
            shift
            case "${1:-}" in ''|*\"*|*$'\n'*|*$'\r'*|*'`'*|*\\) echo "BAD_ARGS: --filter needs a non-empty expression without quotes, backticks, newlines or a trailing backslash: ${1:-}"; exit 2 ;; esac
            flag_content="${flag_content}filter=$1"$'\n' ;;
        --hold)
            shift
            case "${1:-}" in ''|*[!0-9]*) echo "BAD_ARGS: --hold needs a number (seconds): ${1:-}"; exit 2 ;; esac
            hold="$1"
            flag_content="${flag_content}hold=$1"$'\n' ;;
        --preview)
            flag_content="${flag_content}desktop=visible"$'\n'
            case "${2:-}" in ''|*[!0-9]*) hold="${hold:-60}" ;; *) shift; hold="$1" ;; esac
            flag_content="${flag_content}hold=$hold"$'\n' ;;
        --present) present=1 ;;
        --ui-timeout)
            shift
            case "${1:-}" in ''|*[!0-9]*) echo "BAD_ARGS: --ui-timeout needs a number (seconds): ${1:-}"; exit 2 ;; esac
            ui_timeout="$1"
            flag_content="${flag_content}timeout=$1"$'\n' ;;
        *)
            positional=$((positional + 1))
            if [ "$positional" -eq 1 ]; then DIR="$1"; elif [ "$positional" -eq 2 ]; then TIMEOUT="$1"; fi ;;
    esac
    shift
done
# 待ち時間 (Skill 側) の既定: 900 秒。--ui-timeout が長いときは、それより、長くする (ウォッチャーが、先に、時間切れにしてくれるように)
# 待ち時間 (Skill 側) の既定: ビルド (最大 600 秒) + UI テストのプロジェクトの数 × 制限時間 (--ui-timeout、なければ 600 秒) + 見せる時間 (--hold) + 余裕 120 秒。最低 900 秒。
# (ウォッチャーが、先に、時間切れにして、結果を返すように、Skill 側の待ちを、それより長くする。短いと、TIMEOUT (rc 5) になり、古い結果の誤読につながる)
if [ -z "$TIMEOUT" ]; then
    n_ui="$(find "$DIR" \( -name bin -o -name obj -o -name .git -o -name .claude-logs -o -name node_modules \) -prune -o -type f \( -iname '*UITests.csproj' -o -iname '*UiTests.csproj' \) -print 2>/dev/null | wc -l | tr -d ' ')"
    [ "${n_ui:-0}" -ge 1 ] || n_ui=1
    TIMEOUT=$((600 + ${ui_timeout:-600} * n_ui + ${hold:-0} + 120))
    [ "$TIMEOUT" -ge 900 ] || TIMEOUT=900
fi
if [ -n "$present" ]; then
    case "$flag_content" in *filter=*) ;; *) echo "BAD_ARGS: --present plays only the tests you specify: add --filter \"<式>\" (e.g. --filter \"FullyQualifiedName~LoginDialog\")"; exit 2 ;; esac
    case "$flag_content" in *desktop=separate*) echo "BAD_ARGS: --present needs your desktop; it cannot be used with --separate"; exit 2 ;; esac
    case "$flag_content" in *desktop=visible*) ;; *) flag_content="${flag_content}desktop=visible"$'\n' ;; esac
    case "$flag_content" in *slowmo=*) ;; *) flag_content="${flag_content}slowmo=800"$'\n' ;; esac
    flag_content="${flag_content}present=1"$'\n'
fi
case "$flag_content" in *desktop=visible*desktop=separate*|*desktop=separate*desktop=visible*) echo "BAD_ARGS: --visible and --separate cannot be used together"; exit 2 ;; esac

out="$(BUILD_TEST_FLAG=trigger_uitest.flag BUILD_TEST_FLAG_CONTENT="${flag_content%$'\n'}" bash "$here/build_test_once.sh" "$DIR" "$TIMEOUT")"
rc=$?
printf '%s\n' "$out"

# スクリーンショットと trace は、この実行が、テストまで届いたとき (PASSED / FAILED / TEST_TIMEOUT = rc 0 / 1 / 7) だけ、出す。
# それ以外 (WATCHER_NOT_RUNNING / TIMEOUT / BAD_ARGS / ビルド失敗など) では、前回の画像と「Passed」が残っていて、今回の結果に見えるため、出さない。
if [ "$rc" != 0 ] && [ "$rc" != 1 ] && [ "$rc" != 7 ]; then exit "$rc"; fi

shots="$DIR/.claude-logs/ui-screenshots"
if [ -d "$shots" ]; then
    list="$(find "$shots" -maxdepth 1 -type f -iname '*.png' 2>/dev/null | sort | head -n 20)"
    if [ -n "$list" ]; then
        echo "screenshots (Read ツールで、画像として開ける):"
        printf '%s\n' "$list" | sed "s#^$DIR/##"
    fi
fi

# 操作の記録 (トレース): 動いたことの確認。テストごとの結果の行 (=== テスト名: Passed / Failed) と、記録の場所を出す
trace="$DIR/.claude-logs/ui-screenshots/ui-trace.txt"
if [ -f "$trace" ]; then
    n="$(wc -l < "$trace" | tr -d ' ')"
    echo "ui-trace (${n} lines; 操作の記録。動いたことの確認に使う): ${trace#$DIR/}"
    grep -a -E ' === .*: (Passed|Failed|Inconclusive|Timeout|Aborted|Error|NotExecuted|Unknown)' "$trace" | sed 's/^[0-9:.]* //' | head -n 20
fi
exit "$rc"
