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
ok "trigger_test.flag was not used" "$([ ! -e "$T/trigger_test.flag" ] && echo 1 || echo 0)"

# 2. trigger_test.flag だけを回収する watcher (UI テスト非対応の古い版) → WATCHER_NOT_RUNNING (フラグ名が、通常のテストと違う)
rm -rf "$T/.claude-logs" "$T/build_result.txt" "$T/test_result.txt"
fake_watcher trigger_test.flag & W=$!
out="$(bash "$SCRIPT" "$T" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "an old watcher that only handles trigger_test.flag -> WATCHER_NOT_RUNNING (rc=3)" "$([ $rc = 3 ] && [ "$(echo "$out" | head -n 1)" = WATCHER_NOT_RUNNING ] && echo 1 || echo 0)"
rm -f "$T/trigger_uitest.flag"

# 3. 引数不正
out="$(bash "$SCRIPT" /no/such/dir)"; rc=$?
ok "BAD_ARGS for a missing folder (rc=2)" "$([ $rc = 2 ] && echo "$out" | head -n 1 | grep -q BAD_ARGS && echo 1 || echo 0)"

rm -rf "$T"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
