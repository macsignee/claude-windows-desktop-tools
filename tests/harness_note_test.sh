#!/usr/bin/env bash
# harness_note_test.sh - 結果の自己記述と、Skill・ウォッチャーの版の不一致の検出 (v2.29.0) を検証する (Windows 不要)。
#   - install.sh が、Skill と、ホスト側の配布先に、VERSION を置く
#   - harness_note.sh: RESULT_INFO と、NOTE (古いウォッチャー / 版の不一致 / 版が不明)。警告だけで、終了コードは 0
#   - 配布した Skill の build_once.sh を、疑似ウォッチャーで動かして、末尾に出る (1 行目と終了コードは、変わらない)
#   - watch_and_build.ps1: 版の読み込み、run_id.txt の自己記述、起動バナー (静的)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1"; fi; }
b() { [ "$1" = 0 ] && echo 1 || echo 0; }

# --- 配布 (一時フォルダへ)
bash "$ROOT/install/install.sh" --skills-dir "$T/skills" --host-dir "$T/host" --rules-dir "$T/rules" --templates-dir "$T/tpl" --scripts-dir "$T/scripts" >"$T/inst.log" 2>&1
ok "install: succeeds" "$(b $?)"
V="$(tr -d '\r\n' < "$ROOT/VERSION")"
ok "install: the repo VERSION is placed in every skill ($(ls -d "$ROOT"/skills/*/ | wc -l) skills)" "$(for d in "$ROOT"/skills/*/; do [ "$(cat "$T/skills/$(basename "$d")/VERSION" 2>/dev/null)" = "$V" ] || exit 1; done; echo 1)"
ok "install: the repo VERSION is placed in the host-side folder" "$([ "$(cat "$T/host/VERSION" 2>/dev/null)" = "$V" ] && echo 1 || echo 0)"
ok "install: the repo itself has no skills/*/VERSION (made only on distribution)" "$(ls "$ROOT"/skills/*/VERSION >/dev/null 2>&1 && echo 0 || echo 1)"
bash "$ROOT/install/install.sh" --dry-run --skills-dir "$T/dry/skills" --host-dir "$T/dry/host" --rules-dir "$T/dry/r" --templates-dir "$T/dry/t" >/dev/null 2>&1
ok "install --dry-run: writes nothing" "$([ ! -e "$T/dry" ] && echo 1 || echo 0)"

# --- harness_note.sh (配布した版)
HN="$T/skills/build-test-loop/scripts/harness_note.sh"
S="$T/sln"; mkdir -p "$S/.claude-logs"
note() { bash "$HN" "$S"; }
rid() { printf "$1" > "$S/.claude-logs/run_id.txt"; }

rm -f "$S/.claude-logs/run_id.txt"
ok "no run_id.txt: silent, rc=0" "$([ -z "$(note)" ] && echo 1 || echo 0)"
bash "$HN" "$T/nonexistent" >/dev/null 2>&1; ok "no such folder: rc=0" "$(b $?)"
bash "$HN" >/dev/null 2>&1; ok "no argument: rc=0" "$(b $?)"

rid 'run=1-2-3\r\n'
out="$(note)"
ok "old watcher (run= only): NOTE, no RESULT_INFO" "$(grep -q '^NOTE: ウォッチャーが古い' <<<"$out" && ! grep -q RESULT_INFO <<<"$out" && echo 1 || echo 0)"

rid "run=1-2-3\r\nwatcher=$V\r\nkind=test\r\ninput=C:\\\\work\\\\My Sln\r\nfinished=2026-10-31 13:00:00\r\n"
out="$(note)"
ok "same versions: RESULT_INFO only (CRLF, backslash path -> folder name)" "$([ "$out" = "RESULT_INFO: kind=test input=My Sln finished=2026-10-31 13:00:00 watcher=$V" ] && echo 1 || echo 0)"

rid "run=1-2-3\r\nwatcher=0.0.1\r\nkind=build\r\ninput=/x/y\r\nfinished=2026-10-31 13:00:00\r\n"
out="$(note)"
ok "mismatch: NOTE with both versions" "$(grep -q "^NOTE: 版の不一致: Skill=$V / ウォッチャー=0.0.1" <<<"$out" && grep -q '^RESULT_INFO: kind=build input=y' <<<"$out" && echo 1 || echo 0)"
ok "mismatch: the NOTE says what to do (install.sh, restart)" "$(grep -q 'install.sh' <<<"$out" && grep -q '再起動' <<<"$out" && echo 1 || echo 0)"

rid "run=1-2-3\r\nwatcher=unknown\r\nkind=build\r\ninput=/x/y\r\nfinished=t\r\n"
ok "watcher version unknown: NOTE" "$(note | grep -q '^NOTE: ウォッチャーの版が分からない' && echo 1 || echo 0)"

rid "\xEF\xBB\xBFrun=1-2-3\r\nwatcher=$V\r\nkind=build\r\ninput=/x/y\r\nfinished=t\r\n"
ok "BOM on the first line: handled" "$(note | grep -q "watcher=$V" && echo 1 || echo 0)"

mkdir -p "$T/lone/scripts"; cp "$HN" "$T/lone/scripts/harness_note.sh"
rid "run=1-2-3\r\nwatcher=$V\r\nkind=build\r\ninput=/x/y\r\nfinished=t\r\n"
ok "no Skill VERSION: NOTE" "$(bash "$T/lone/scripts/harness_note.sh" "$S" | grep -q '^NOTE: Skill の版が分からない' && echo 1 || echo 0)"

# --- 配布した Skill の build_once.sh を、疑似ウォッチャー (新しい形の run_id.txt) で動かす
E="$T/e2e"; mkdir -p "$E/.claude-logs"
runid_of() { sed 's/\r$//' "$1" | grep -m1 '^run=' | sed 's/^run=//'; }
fake() {  # $1=watcher の版の行 (空なら、古い形)
    while true; do
        if [ -f "$E/trigger_build.flag" ]; then
            id="$(runid_of "$E/trigger_build.flag")"; rm -f "$E/trigger_build.flag"; sleep 0.3
            if [ -n "$1" ]; then printf 'run=%s\r\nwatcher=%s\r\nkind=build\r\ninput=%s\r\nfinished=2026-10-31 13:00:00\r\n' "$id" "$1" "$E" > "$E/.claude-logs/run_id.txt"
            else printf 'run=%s\r\n' "$id" > "$E/.claude-logs/run_id.txt"; fi
            printf SUCCESS > "$E/build_result.txt"
        fi
        sleep 0.2
    done
}
BUILD="$T/skills/auto-build/scripts/build_once.sh"
fake "$V" & W=$!; out="$(bash "$BUILD" "$E" 30)"; rc=$?; kill $W 2>/dev/null; wait $W 2>/dev/null
ok "build_once (same version): SUCCESS, rc=0, first line unchanged, RESULT_INFO at the end, no NOTE" "$([ $rc = 0 ] && [ "$(head -n 1 <<<"$out")" = SUCCESS ] && grep -q '^RESULT_INFO: kind=build input=e2e ' <<<"$out" && ! grep -q '^NOTE: ' <<<"$out" && echo 1 || echo 0)"
rm -f "$E/build_result.txt" "$E/.claude-logs/run_id.txt"
fake "0.0.1" & W=$!; out="$(bash "$BUILD" "$E" 30)"; rc=$?; kill $W 2>/dev/null; wait $W 2>/dev/null
ok "build_once (version mismatch): still SUCCESS, rc=0 (the NOTE never blocks), NOTE shown" "$([ $rc = 0 ] && [ "$(head -n 1 <<<"$out")" = SUCCESS ] && grep -q '^NOTE: 版の不一致' <<<"$out" && echo 1 || echo 0)"
rm -f "$E/build_result.txt" "$E/.claude-logs/run_id.txt"
fake "" & W=$!; out="$(bash "$BUILD" "$E" 30)"; rc=$?; kill $W 2>/dev/null; wait $W 2>/dev/null
ok "build_once (old watcher): still SUCCESS, rc=0, NOTE about the old watcher" "$([ $rc = 0 ] && [ "$(head -n 1 <<<"$out")" = SUCCESS ] && grep -q '^NOTE: ウォッチャーが古い' <<<"$out" && echo 1 || echo 0)"

# --- watch_and_build.ps1 (静的)
# 本体 + lib\*.ps1 を 1 つにつなげて検査する (機能ごとに、lib に分かれているため)
P="$T/watch_all.ps1"; cat "$ROOT/host-tools/watch_and_build.ps1" "$ROOT"/host-tools/lib/*.ps1 > "$P"
ok "ps1: reads VERSION next to the script into WatcherVersion (unknown when missing)" "$(grep -q 'script:WatcherVersion = "unknown"' "$P" && grep -q 'Join-Path $verDir "VERSION"' "$P" && echo 1 || echo 0)"
ok "ps1: run_id.txt keeps run= on the first line, then watcher= / kind= / input= / finished=" "$(grep -q 'run=$($script:CurrentRunId)`r`nwatcher=$($script:WatcherVersion)`r`nkind=$($script:CurrentKind)`r`ninput=$TargetDir`r`nfinished=' "$P" && echo 1 || echo 0)"
ok "ps1: CurrentKind is set for gtest / package / build-test-uitest" "$(grep -q 'CurrentKind = "gtest"' "$P" && grep -q 'CurrentKind = "package"' "$P" && grep -q 'CurrentKind = $(if ($runUiTests) { "uitest" } elseif ($runTests) { "test" } else { "build" })' "$P" && echo 1 || echo 0)"
ok "ps1: the start banner shows the version" "$(grep -q 'Write-Host " Version      : $($script:WatcherVersion)' "$P" && echo 1 || echo 0)"
ok "ps1: still UTF-8 with BOM and CRLF" "$([ "$(head -c 3 "$P" | od -An -tx1 | tr -d ' ')" = efbbbf ] && ! grep -qP '(?<!\r)$' "$P" && echo 1 || echo 0)"

# --- 実行権限: Skill の .sh は、すべて実行できる (bash なしで呼ばれても、Permission denied にならない。package_once.sh だけ、以前から、なかった)
ok "every skills/*/scripts/*.sh is executable" "$(for f in "$ROOT"/skills/*/scripts/*.sh; do [ -x "$f" ] || { echo "not executable: $f" >&2; exit 1; }; done; echo 1)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
