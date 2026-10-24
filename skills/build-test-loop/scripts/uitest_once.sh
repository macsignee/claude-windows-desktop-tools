#!/usr/bin/env bash
# uitest_once.sh - ホスト側ウォッチャーに「ビルド + UI テスト (FlaUI など) 実行」を1回させ、完了まで待って結果を返す。
#
# Usage: uitest_once.sh <solution_dir> [timeout_sec=900]
#   <solution_dir>: .sln/.slnx のあるフォルダ (ウォッチャーの TargetDir)
#
# build_test_once.sh と同じ出力 (1行目と終了コード) の、UI テスト版。違いは次のとおり。
#   - フラグは trigger_uitest.flag。実行するのは、UI テストのプロジェクト (名前が UITests / UiTests で終わる、または FlaUI を参照)
#     だけ。通常のテスト (trigger_test.flag) からは、UI テストのプロジェクトは、除かれる。
#   - 既定の制限時間は 900 秒 (アプリの起動と操作を含むため)。ウォッチャー側の制限は、-UiTestTimeoutSec (既定 600、プロジェクトごと)。
#   - 実行中は、ユーザーが、マウスとキーボードに触らない (画面のロック・RDP の切断・最小化も避ける)。
#   - 失敗時のスクリーンショット (.claude-logs/ui-screenshots/*.png) があれば、最後に一覧を出す。Read ツールで、画像として読める。
#   - 操作の記録 (ui-trace.txt) があれば、テストごとの結果の行を出す (UI テストが、実際に動いたことの確認)。
#   - ユーザーのデスクトップで、目で確かめるには、ウォッチャーを run_watcher_visible.cmd で起動する (操作の間に待ちが入る)。
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="${1:-}"
TIMEOUT="${2:-900}"

out="$(BUILD_TEST_FLAG=trigger_uitest.flag bash "$here/build_test_once.sh" "$DIR" "$TIMEOUT")"
rc=$?
printf '%s\n' "$out"

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
