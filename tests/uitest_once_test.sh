#!/usr/bin/env bash
# uitest_once_test.sh - uitest_once.sh を、疑似ウォッチャーで検証する (Windows 不要)。
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/build-test-loop/scripts/uitest_once.sh"
T="$(mktemp -d)"
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1"; fi; }

# 疑似ウォッチャー: $1 のフラグを回収し、1 秒後に、結果 (と、スクリーンショット) を書く
fake_watcher() {
    local flag="$1"
    while true; do
        if [ -f "$T/$flag" ]; then
            rm -f "$T/$flag"
            sleep 1
            mkdir -p "$T/.claude-logs/ui-screenshots"
            printf 'PNG' > "$T/.claude-logs/ui-screenshots/Login_Fails-window.png"
            printf '12:00:00.000 === Login_Fails: start (desktop: Default, slowmo: 800 ms)\n12:00:01.000 find: NameTextBox\n12:00:02.000 === Login_Fails: Failed\n12:00:03.000 === Other_Test: Passed\n' > "$T/.claude-logs/ui-screenshots/ui-trace.txt"
            printf SUCCESS > "$T/build_result.txt"; printf PASSED > "$T/test_result.txt"
        fi
        sleep 0.3
    done
}

# 1. trigger_uitest.flag を回収する watcher → PASSED と、スクリーンショットの一覧
fake_watcher trigger_uitest.flag & W=$!
out="$(bash "$SCRIPT" "$T" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "PASSED (rc=0), first line is PASSED" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = PASSED ] && echo 1 || echo 0)"
ok "screenshots are listed (relative path)" "$(echo "$out" | grep -q '^\.claude-logs/ui-screenshots/Login_Fails-window.png$' && echo 1 || echo 0)"
ok "ui-trace: path and per-test outcome lines are printed" "$(echo "$out" | grep -q '^ui-trace (4 lines' && echo "$out" | grep -q '^=== Login_Fails: Failed$' && echo "$out" | grep -q '^=== Other_Test: Passed$' && echo 1 || echo 0)"
ok "trigger_test.flag was not used" "$([ ! -e "$T/trigger_test.flag" ] && echo 1 || echo 0)"

# 2. trigger_test.flag だけを回収する watcher (UI テスト非対応の古い版) → WATCHER_NOT_RUNNING (フラグ名が、通常のテストと違う)
rm -rf "$T/.claude-logs" "$T/build_result.txt" "$T/test_result.txt"
fake_watcher trigger_test.flag & W=$!
out="$(bash "$SCRIPT" "$T" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "an old watcher that only handles trigger_test.flag -> WATCHER_NOT_RUNNING (rc=3)" "$([ $rc = 3 ] && [ "$(echo "$out" | head -n 1)" = WATCHER_NOT_RUNNING ] && echo 1 || echo 0)"
ok "the message names trigger_uitest.flag and tells to update the watcher" "$(echo "$out" | grep -q "^trigger_uitest.flag was not picked up" && echo "$out" | grep -q "old version" && echo 1 || echo 0)"
rm -f "$T/trigger_uitest.flag"

# 2b. 1 回ごとの指定 (--visible / --separate / --slowmo) は、フラグの中身になる。指定がなければ、中身は空 (ウォッチャーが、決める)
capture_watcher() {
    while true; do
        if [ -f "$T/trigger_uitest.flag" ]; then
            cp "$T/trigger_uitest.flag" "$T/captured.txt"; rm -f "$T/trigger_uitest.flag"
            printf SUCCESS > "$T/build_result.txt"; printf PASSED > "$T/test_result.txt"
        fi
        sleep 0.2
    done
}
rm -rf "$T/.claude-logs" "$T/build_result.txt" "$T/test_result.txt"
capture_watcher & W=$!
bash "$SCRIPT" "$T" 30 --visible --slowmo 800 >/dev/null
ok "--visible --slowmo 800: the flag carries desktop=visible and slowmo=800" "$([ "$(grep -c . "$T/captured.txt")" = 2 ] && grep -qx 'desktop=visible' "$T/captured.txt" && grep -qx 'slowmo=800' "$T/captured.txt" && echo 1 || echo 0)"
bash "$SCRIPT" "$T" --separate 30 >/dev/null
ok "--separate (options may come before the timeout): desktop=separate only" "$([ "$(cat "$T/captured.txt")" = 'desktop=separate' ] && echo 1 || echo 0)"
bash "$SCRIPT" "$T" --invisible 30 >/dev/null
ok "--invisible is an alias of --separate: desktop=separate" "$([ "$(cat "$T/captured.txt")" = 'desktop=separate' ] && echo 1 || echo 0)"
bash "$SCRIPT" "$T" 30 >/dev/null
ok "no option: the flag is empty (the watcher decides: WPF -> your desktop, else separate)" "$([ ! -s "$T/captured.txt" ] && echo 1 || echo 0)"
bash "$SCRIPT" "$T" 30 --filter "FullyQualifiedName~LoginDialog&TestCategory=ui" --ui-timeout 1800 >/dev/null
ok "--filter and --ui-timeout: the flag carries filter=... and timeout=1800 (one per line)" "$([ "$(grep -c . "$T/captured.txt")" = 2 ] && grep -qx 'filter=FullyQualifiedName~LoginDialog&TestCategory=ui' "$T/captured.txt" && grep -qx 'timeout=1800' "$T/captured.txt" && echo 1 || echo 0)"
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
out="$(bash "$SCRIPT" "$T" --filter 'A"B')"; rc=$?
ok "--filter with a quote -> BAD_ARGS (rc=2)" "$([ $rc = 2 ] && echo "$out" | head -n 1 | grep -q BAD_ARGS && echo 1 || echo 0)"
out="$(bash "$SCRIPT" "$T" --ui-timeout abc)"; rc=$?
ok "--ui-timeout with a non-number -> BAD_ARGS (rc=2)" "$([ $rc = 2 ] && echo "$out" | head -n 1 | grep -q BAD_ARGS && echo 1 || echo 0)"
out="$(bash "$SCRIPT" "$T" --visible --separate)"; rc=$?
ok "--visible with --separate -> BAD_ARGS (rc=2)" "$([ $rc = 2 ] && echo "$out" | head -n 1 | grep -q BAD_ARGS && echo 1 || echo 0)"
out="$(bash "$SCRIPT" "$T" --slowmo abc)"; rc=$?
ok "--slowmo with a non-number -> BAD_ARGS (rc=2)" "$([ $rc = 2 ] && echo "$out" | head -n 1 | grep -q BAD_ARGS && echo 1 || echo 0)"

# 3. 引数不正
out="$(bash "$SCRIPT" /no/such/dir)"; rc=$?
ok "BAD_ARGS for a missing folder (rc=2)" "$([ $rc = 2 ] && echo "$out" | head -n 1 | grep -q BAD_ARGS && echo 1 || echo 0)"

rm -rf "$T"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
