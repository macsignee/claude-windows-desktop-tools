#!/usr/bin/env bash
# gtest_once_test.sh - skills/new-solution/scripts/gtest_once.sh を、疑似ウォッチャー (ファイルを書くだけの偽物) で検証する。
# Windows 側のウォッチャーがなくても、結果の分岐 (1行目と終了コード) を確認できる。
#
# Usage: tests/gtest_once_test.sh
# 終了コード: 0 すべて OK / 1 失敗あり
set -u
export LC_ALL=C

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills/new-solution/scripts/gtest_once.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/gtest_once_test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
BOM=$'\xEF\xBB\xBF'
CR=$'\r'
fail=0

ok() { echo "OK  $1"; }
ng() { echo "NG  $1"; fail=1; }

# 疑似ウォッチャー: フラグを回収 (1 行目を、$T/seen_tag に残す)、1 秒後に、ハンドラでファイルを書く
fake_watcher() {
    local handler="$1"
    while true; do
        if [ -f "$T/trigger_gtest.flag" ]; then
            head -n 1 "$T/trigger_gtest.flag" > "$T/seen_tag"
            rm -f "$T/trigger_gtest.flag"
            sleep 1
            "$handler"
        fi
        sleep 0.3
    done
}
h_ok()     { printf OK > "$T/gtest_result.txt"; }
h_failed() {
    { printf '%s[ENVIRONMENT ERROR - not a source code problem]%s\nERROR: could not get GoogleTest v1.17.0 from https://github.com/google/googletest%s\ngit clone failed (exit code 128).%s\n' "$BOM" "$CR" "$CR" "$CR"; } > "$T/gtest_error.log"
    printf FAILED > "$T/gtest_result.txt"
}
h_never()  { :; }

# $1=説明 $2=期待する 1 行目 $3=期待する rc $4=ハンドラ $5...=スクリプトの引数
run_case() {
    local desc="$1" want1="$2" wantrc="$3" handler="$4"; shift 4
    rm -f "$T"/*.txt "$T"/*.log "$T"/*.flag "$T/seen_tag"
    fake_watcher "$handler" & local W=$!
    local out rc
    out="$(bash "$SCRIPT" "$@" 2>&1)"; rc=$?
    kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
    local first; first="$(printf '%s\n' "$out" | head -n 1)"
    if [ "$first" = "$want1" ] && [ "$rc" -eq "$wantrc" ]; then ok "$desc"; else ng "$desc (1行目='$first' rc=$rc、期待 '$want1' / $wantrc)"; fi
    LAST_OUT="$out"
}

bash -n "$SCRIPT" && ok "構文" || ng "構文"

run_case "OK (rc=0)"                              OK 0 h_ok "$T" "" 20
run_case "タグを、フラグの 1 行目に書く"           OK 0 h_ok "$T" v1.17.0 20
[ "$(cat "$T/seen_tag" 2>/dev/null)" = "v1.17.0" ] && ok "  ウォッチャーが、タグを受け取った" || ng "  ウォッチャーが、タグを受け取った"
run_case "タグ省略: フラグは空"                    OK 0 h_ok "$T" "" 20
[ -z "$(cat "$T/seen_tag" 2>/dev/null)" ] && ok "  フラグの 1 行目が空" || ng "  フラグの 1 行目が空"
run_case "FAILED (rc=1) + ログ (BOM と CR を除去)"  FAILED 1 h_failed "$T" "" 20
printf '%s\n' "$LAST_OUT" | grep -q 'ENVIRONMENT ERROR' && ! printf '%s' "$LAST_OUT" | grep -q $'\r' && ok "  ログが出て、CR がない" || ng "  ログが出て、CR がない"
run_case "TIMEOUT (rc=5)"                         TIMEOUT 5 h_never "$T" "" 3
run_case "不正なタグ -> BAD_ARGS (rc=2)"           "BAD_ARGS: invalid tag: v1;rm -rf (allowed: v1.17.0 / release-1.12.1)" 2 h_ok "$T" "v1;rm -rf" 5
run_case "フォルダなし -> BAD_ARGS (rc=2)"          "BAD_ARGS: project dir not found: $T/nonexistent" 2 h_ok "$T/nonexistent" "" 5
run_case "timeout が数値でない -> BAD_ARGS (rc=2)" "BAD_ARGS: timeout must be a positive integer (seconds): abc" 2 h_ok "$T" "" abc

# 古い結果が、消されるか (前回の OK が残っていても、今回の FAILED を返す)
rm -f "$T"/*.txt "$T"/*.log "$T"/*.flag
printf OK > "$T/gtest_result.txt"
fake_watcher h_failed & W=$!
out="$(bash "$SCRIPT" "$T" "" 20 2>&1)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
[ "$(printf '%s\n' "$out" | head -n 1)" = "FAILED" ] && [ "$rc" -eq 1 ] && ok "古いマーカーが消される" || ng "古いマーカーが消される"

# ウォッチャーがない -> 約 15 秒で WATCHER_NOT_RUNNING (フラグも消す)
rm -f "$T"/*.txt "$T"/*.log "$T"/*.flag
out="$(bash "$SCRIPT" "$T" "" 60 2>&1)"; rc=$?
[ "$(printf '%s\n' "$out" | head -n 1)" = "WATCHER_NOT_RUNNING" ] && [ "$rc" -eq 3 ] && [ ! -f "$T/trigger_gtest.flag" ] && ok "WATCHER_NOT_RUNNING (rc=3)、フラグを片付ける" || ng "WATCHER_NOT_RUNNING (rc=3)"

echo
if [ "$fail" -eq 0 ]; then echo "すべて OK"; else echo "失敗あり"; fi
exit "$fail"
