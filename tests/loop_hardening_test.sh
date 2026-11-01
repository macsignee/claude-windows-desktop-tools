#!/usr/bin/env bash
# loop_hardening_test.sh - 自動修正ループの堅牢化 (v2.20.0) を、疑似ウォッチャーで検証する (Windows 不要)。
#   - 実行 ID の照合 (古い実行が、あとから書いたマーカーを、今回の結果と取り違えない)
#   - ウォッチャーが処理中 (watcher_busy.txt) のときは、WATCHER_NOT_RUNNING と誤報しない / TIMEOUT で、回収されていないフラグを取り下げる
#   - uitest_once.sh は、テストまで届かなかった実行 (WATCHER_NOT_RUNNING / TIMEOUT など) では、前回の画像と trace を表示しない
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/skills/auto-build/scripts/build_once.sh"
BTEST="$ROOT/skills/build-test-loop/scripts/build_test_once.sh"
UITEST="$ROOT/skills/build-test-loop/scripts/uitest_once.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1"; fi; }
mkdir -p "$T/.claude-logs"

runid_of() { sed 's/\r$//' "$1" | grep -m1 '^run=' | sed 's/^run=//'; }

# --- 疑似ウォッチャー (build): フラグを回収し、run_id.txt を書いてから、マーカーを書く
fake_build() {  # $1=結果 (SUCCESS / FAILED)  $2=遅延 (秒)
    while true; do
        if [ -f "$T/trigger_build.flag" ]; then
            id="$(runid_of "$T/trigger_build.flag")"; rm -f "$T/trigger_build.flag"
            sleep "${2:-0.5}"
            printf 'run=%s\r\n' "$id" > "$T/.claude-logs/run_id.txt"
            printf '%s' "$1" > "$T/build_result.txt"
            [ "$1" = FAILED ] && printf 'error C2065: x\n\nBuild failed with exit code: 1\n' > "$T/build_error.log"
        fi
        sleep 0.2
    done
}

# 1. 実行 ID が、フラグの 1 行目に書かれ、一致する結果を受け取る
fake_build SUCCESS 0.5 & W=$!
out="$(bash "$BUILD" "$T" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "build_once: a result with the matching run id is accepted (SUCCESS, rc=0)" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = SUCCESS ] && echo 1 || echo 0)"
rm -f "$T/build_result.txt" "$T/.claude-logs/run_id.txt"

# 2. 古い実行 (別の ID) が、先に書いたマーカーは、無視し、今回の ID のマーカーを待つ
stale_then_real() {
    while true; do
        if [ -f "$T/trigger_build.flag" ]; then
            id="$(runid_of "$T/trigger_build.flag")"; rm -f "$T/trigger_build.flag"
            printf 'run=OLD-RUN\r\n' > "$T/.claude-logs/run_id.txt"; printf SUCCESS > "$T/build_result.txt"   # 前の実行が、あとから、書いた、古い結果
            sleep 3
            printf 'run=%s\r\n' "$id" > "$T/.claude-logs/run_id.txt"; printf FAILED > "$T/build_result.txt"; printf 'error C2065: x\n\nBuild failed with exit code: 1\n' > "$T/build_error.log"
        fi
        sleep 0.2
    done
}
stale_then_real & W=$!
out="$(bash "$BUILD" "$T" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "build_once: a stale marker written by an older run (other run id) is NOT taken as this run's result" "$([ $rc = 1 ] && [ "$(echo "$out" | head -n 1)" = FAILED ] && echo 1 || echo 0)"
rm -f "$T/build_result.txt" "$T/build_error.log" "$T/.claude-logs/run_id.txt"

# 3. 古いウォッチャー (run_id.txt を書かない): マーカーだけで、従来どおり
legacy() { while true; do if [ -f "$T/trigger_build.flag" ]; then rm -f "$T/trigger_build.flag"; sleep 0.5; printf SUCCESS > "$T/build_result.txt"; fi; sleep 0.2; done; }
legacy & W=$!
out="$(bash "$BUILD" "$T" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "build_once: an old watcher (no run_id.txt) still works (marker only)" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = SUCCESS ] && echo 1 || echo 0)"
rm -f "$T/build_result.txt"

# 4. ウォッチャーが処理中 (watcher_busy.txt): フラグが回収されなくても、WATCHER_NOT_RUNNING とは、言わない。TIMEOUT で、フラグを取り下げる
printf 'build run=other\r\nstarted=now\r\n' > "$T/.claude-logs/watcher_busy.txt"
out="$(CLAUDE_PICKUP_WAIT=2 bash "$BUILD" "$T" 5)"; rc=$?
ok "build_once: watcher busy -> no WATCHER_NOT_RUNNING; TIMEOUT (rc=5) says not to start another run" "$([ $rc = 5 ] && [ "$(echo "$out" | head -n 1)" = TIMEOUT ] && echo "$out" | grep -q 'Do NOT start another run' && echo 1 || echo 0)"
ok "build_once: the unpicked flag is withdrawn on TIMEOUT" "$([ ! -f "$T/trigger_build.flag" ] && echo 1 || echo 0)"
rm -f "$T/.claude-logs/watcher_busy.txt"

# 5. 処理中でも、起動してもいない: WATCHER_NOT_RUNNING (rc=3)。メッセージに、フォルダの確認も
out="$(CLAUDE_PICKUP_WAIT=2 bash "$BUILD" "$T" 30)"; rc=$?
ok "build_once: not busy and not picked up -> WATCHER_NOT_RUNNING (rc=3), mentions checking the target folder" "$([ $rc = 3 ] && [ "$(echo "$out" | head -n 1)" = WATCHER_NOT_RUNNING ] && echo "$out" | grep -q 'targets this folder' && echo 1 || echo 0)"
ok "build_once: the flag is removed after WATCHER_NOT_RUNNING" "$([ ! -f "$T/trigger_build.flag" ] && echo 1 || echo 0)"

# 6. build_test_once.sh でも、同じ (古い実行のマーカーを、無視)
stale_test() {
    while true; do
        if [ -f "$T/trigger_test.flag" ]; then
            id="$(runid_of "$T/trigger_test.flag")"; rm -f "$T/trigger_test.flag"
            printf 'run=OLD-RUN\r\n' > "$T/.claude-logs/run_id.txt"; printf SUCCESS > "$T/build_result.txt"; printf PASSED > "$T/test_result.txt"
            sleep 3
            printf 'run=%s\r\n' "$id" > "$T/.claude-logs/run_id.txt"; printf SUCCESS > "$T/build_result.txt"; printf FAILED > "$T/test_result.txt"
            printf '[  FAILED  ] Suite.Case\n' > "$T/test_error.log"
        fi
        sleep 0.2
    done
}
stale_test & W=$!
out="$(bash "$BTEST" "$T" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "build_test_once: a stale PASSED from an older run is NOT taken; the real FAILED is reported (rc=1)" "$([ $rc = 1 ] && [ "$(echo "$out" | head -n 1)" = FAILED ] && echo 1 || echo 0)"
rm -f "$T/build_result.txt" "$T/test_result.txt" "$T/test_error.log" "$T/.claude-logs/run_id.txt"

# 7. フラグの 1 行目は run=... で、UI の指定は、その次の行
cap() { while true; do if [ -f "$T/trigger_uitest.flag" ]; then cp "$T/trigger_uitest.flag" "$T/flag_copy.txt"; rm -f "$T/trigger_uitest.flag"; printf SUCCESS > "$T/build_result.txt"; printf PASSED > "$T/test_result.txt"; fi; sleep 0.2; done; }
cap & W=$!
bash "$UITEST" "$T" 30 --visible --filter "Name~X" >/dev/null
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "uitest flag: line 1 is run=<id>, the UI settings follow" "$([ "$(sed 's/\r$//' "$T/flag_copy.txt" | head -n 1 | grep -c '^run=')" = 1 ] && grep -qx 'desktop=visible' "$T/flag_copy.txt" && grep -qx 'filter=Name~X' "$T/flag_copy.txt" && echo 1 || echo 0)"
rm -f "$T/build_result.txt" "$T/test_result.txt"

# 8. uitest_once.sh: テストまで届かなかった実行では、前回の画像と trace を、表示しない
mkdir -p "$T/.claude-logs/ui-screenshots"; printf PNG > "$T/.claude-logs/ui-screenshots/Old-window.png"
printf '12:00:00.000 === Old_Test: start (desktop: Default, slowmo: 0 ms)\n12:00:01.000 === Old_Test: Passed\n' > "$T/.claude-logs/ui-screenshots/ui-trace.txt"
out="$(CLAUDE_PICKUP_WAIT=2 bash "$UITEST" "$T" 30)"; rc=$?
ok "uitest_once: WATCHER_NOT_RUNNING (rc=3) does not list the previous screenshots / 'Passed' lines" "$([ $rc = 3 ] && ! echo "$out" | grep -q 'Old-window.png' && ! echo "$out" | grep -q 'Old_Test: Passed' && echo 1 || echo 0)"
fake_ui() { while true; do if [ -f "$T/trigger_uitest.flag" ]; then id="$(runid_of "$T/trigger_uitest.flag")"; rm -f "$T/trigger_uitest.flag"; printf 'run=%s\r\n' "$id" > "$T/.claude-logs/run_id.txt"; printf SUCCESS > "$T/build_result.txt"; printf PASSED > "$T/test_result.txt"; fi; sleep 0.2; done; }
fake_ui & W=$!
out="$(bash "$UITEST" "$T" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "uitest_once: after a real PASSED, the screenshots and trace lines are listed" "$([ $rc = 0 ] && echo "$out" | grep -q 'Old-window.png' && echo "$out" | grep -q 'Old_Test: Passed' && echo 1 || echo 0)"

# 9. 待ち時間の既定: ビルド 600 + UI テストのプロジェクトの数 × 制限時間 + hold + 120 (最低 900)
for f in x y; do mkdir -p "$T/App$f.UITests"; : > "$T/App$f.UITests/App$f.UITests.csproj"; done
out="$(CLAUDE_PICKUP_WAIT=1 bash -x "$UITEST" "$T" --ui-timeout 700 --hold 60 2>&1 | grep -m1 'build_test_once.sh' )"
ok "uitest_once: the default wait = 600 + 2 projects x 700 + hold 60 + 120 = 2180 s" "$(echo "$out" | grep -q ' 2180$' && echo 1 || echo 0)"

# 10. パスの大文字小文字: WSL の /mnt/c は、大文字小文字を区別しないが、保持する。サンドボックスの書き込み許可は、文字列として、区別して比較する。
#     引数のパスを、実際の大文字小文字に直す (resolve_true_case)。Linux (区別する) のファイルシステムでも、find -iname で、実際の名前に直ることを確かめる
mkdir -p "$T/RealCase/MySolution/Sub"
eval "$(sed -n '/^resolve_true_case() {/,/^}/p' "$BUILD")"
got="$(resolve_true_case "$T/realcase/MYSOLUTION/sub")"
ok "resolve_true_case: a wrongly-cased path is turned into the real one" "$([ "$got" = "$T/RealCase/MySolution/Sub" ] && echo 1 || echo 0)"
got="$(resolve_true_case "$T/RealCase/MySolution/Sub")"
ok "resolve_true_case: a correctly-cased path is unchanged" "$([ "$got" = "$T/RealCase/MySolution/Sub" ] && echo 1 || echo 0)"
got="$(resolve_true_case "$T/RealCase/NoSuch/Dir")"
ok "resolve_true_case: a part that does not exist is kept as given (no crash)" "$([ "$got" = "$T/RealCase/NoSuch/Dir" ] && echo 1 || echo 0)"
got="$(resolve_true_case "relative/Path")"
ok "resolve_true_case: a relative path is returned unchanged" "$([ "$got" = "relative/Path" ] && echo 1 || echo 0)"
for f in "$BUILD" "$BTEST" "$ROOT/skills/add-package/scripts/package_once.sh" "$ROOT/skills/new-solution/scripts/gtest_once.sh"; do
    ok "$(basename "$f"): resolves the dir to its real case before writing flags / results" "$(grep -q '^DIR="$(resolve_true_case "$DIR")"' "$f" && echo 1 || echo 0)"
done

# ---- 文書 (Skill) の整合: 止めどき・TIMEOUT・禁止リスト・Green の条件・UI のループ
BTL="$ROOT/skills/build-test-loop/SKILL.md"; AB="$ROOT/skills/auto-build/SKILL.md"; WTF="$ROOT/skills/csharp-test-first/SKILL.md"; CTF="$ROOT/skills/cpp-test-first/SKILL.md"; UTF="$ROOT/skills/ui-test-first/SKILL.md"; AF="$ROOT/skills/add-feature/SKILL.md"
for f in "$AB" "$BTL"; do
    ok "$(basename "$(dirname "$f")"): TIMEOUT (rc 5) means stop and report, no retry (the old 'retry once' is gone); BAD_ARGS row exists" "$(grep -q '再試行しない' "$f" && ! grep -q '1回だけ再試行可' "$f" && grep -q '`BAD_ARGS`' "$f" && grep -q '`TIMEOUT` | 5 |' "$f" && echo 1 || echo 0)"
done
ok "build-test-loop: one 'stop rules' section (count = total runs, 5 max; TEST_TIMEOUT twice -> stop; hard-coding / test-only branches / removing tests from the project / editing helpers are forbidden; test-file edits only mechanical)" "$(grep -q '^## 止めどき' "$BTL" && grep -q '合計' "$BTL" && grep -q 'ハードコード' "$BTL" && grep -q '#ifdef' "$BTL" && grep -q 'から外す' "$BTL" && grep -q '機械的な追従' "$BTL" && grep -q '2 回続いたら' "$BTL" && echo 1 || echo 0)"
ok "auto-build: points to the stop rules; FAILED is explained as a build failure; test-file edits need confirmation except mechanical ones" "$(grep -q '止めどき' "$AB" && grep -q 'ビルド失敗' "$AB" && grep -q '機械的な追従' "$AB" && echo 1 || echo 0)"
ok "add-feature: points to the stop rules (per task 5 runs, 15 in total)" "$(grep -q '止めどき' "$AF" && grep -q '15 回' "$AF" && echo 1 || echo 0)"
for f in "$WTF" "$CTF"; do
    ok "$(basename "$(dirname "$f")"): baseline run before Red; new tests must appear in the results (count + grep) before Green is complete; no stub when fixing a bug in existing code" "$(grep -q '4.0 ベースライン' "$f" && grep -q 'Green の完了条件' "$f" && grep -q 'test-results' "$f" && grep -q 'スタブを置かない' "$f" && grep -q 'test_summary.json' "$f" && echo 1 || echo 0)"
done
ok "ui-test-first: Preview_<screen> naming + the regression run excludes Preview; --separate is the loop default (menu tests are separate); TEST_TIMEOUT: read ui-trace, 1 extension, stop on 2; user consent for visible; UiDialogsExtra for project-specific helpers" "$(grep -q 'Preview_<画面>' "$UTF" && grep -q 'TestCategory!=Preview' "$UTF" && grep -q -- '--separate' "$UTF" && grep -q 'MenuUiTests' "$UTF" && grep -q '最後の 10 行' "$UTF" && grep -q '2 回続いたら' "$UTF" && grep -q '了承' "$UTF" && grep -q 'UiDialogsExtra.cs' "$UTF" && ! grep -q '<画面>_Preview' "$UTF" && echo 1 || echo 0)"

# ---- GTEST_* 環境変数の除去
WP="$ROOT/host-tools/watch_and_build.ps1"
ok "watcher: GTEST_* environment variables are removed at startup (a leftover GTEST_FILTER made every test run 0 tests), with a notice" "$(grep -q "Name -like 'GTEST_\*'" "$WP" && grep -q 'RemovedGtestEnv' "$WP" && grep -q 'removed from the watcher process' "$WP" && echo 1 || echo 0)"

# ---- package_once.sh / gtest_once.sh の実行 ID の照合 (v2.20.1)
PKG="$ROOT/skills/add-package/scripts/package_once.sh"
GT="$ROOT/skills/new-solution/scripts/gtest_once.sh"
rid() { sed 's/\r$//' "$1" | grep -m1 -E '^#? *run=' | sed -E 's/^#? *run=//'; }   # フラグの、実行 ID (run=... または # run=...)

# package: 一致する ID のマーカーを受け取る。フラグには、# run=<ID> のコメント行があり、操作の行は、そのまま
fake_pkg() {  # $1=結果  $2=ID を書くか (id / stale / none)
    while true; do
        if [ -f "$T/trigger_package.flag" ]; then
            id="$(rid "$T/trigger_package.flag")"; cp "$T/trigger_package.flag" "$T/pkg_flag.copy"; rm -f "$T/trigger_package.flag"
            case "$2" in
                stale) printf 'run=OLD-RUN\r\n' > "$T/.claude-logs/run_id.txt"; printf OK > "$T/package_result.txt"; sleep 3 ;;
            esac
            printf 'hello\n' > "$T/package_output.txt"
            [ "$2" != none ] && printf 'run=%s\r\n' "$id" > "$T/.claude-logs/run_id.txt"
            [ "$1" = FAILED ] && { printf 'ERROR: no such package\n' > "$T/package_error.log"; }
            printf '%s' "$1" > "$T/package_result.txt"
        fi
        sleep 0.2
    done
}
fake_pkg OK id & W=$!
out="$(bash "$PKG" "$T" "vcpkg search fmt")"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "package_once: a result with the matching run id is accepted (OK, rc=0); the flag has a '# run=' comment line before the operation" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = OK ] && [ "$(head -n 1 "$T/pkg_flag.copy" | cut -c1-6)" = "# run=" ] && [ "$(sed -n 2p "$T/pkg_flag.copy")" = "vcpkg search fmt" ] && echo 1 || echo 0)"
rm -f "$T/package_result.txt" "$T/package_output.txt" "$T/.claude-logs/run_id.txt"

fake_pkg FAILED stale & W=$!
out="$(bash "$PKG" "$T" "vcpkg search fmt")"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "package_once: a stale OK written by an older run (other run id) is NOT taken; the real FAILED is reported (rc=1)" "$([ $rc = 1 ] && [ "$(echo "$out" | head -n 1)" = FAILED ] && echo 1 || echo 0)"
rm -f "$T/package_result.txt" "$T/package_output.txt" "$T/package_error.log" "$T/.claude-logs/run_id.txt"

fake_pkg OK none & W=$!
out="$(bash "$PKG" "$T" "vcpkg search fmt")"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "package_once: an old watcher (no run_id.txt) still works (marker only)" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = OK ] && echo 1 || echo 0)"
rm -f "$T/package_result.txt" "$T/package_output.txt" "$T/.claude-logs/run_id.txt"

printf 'package run=other\r\nstarted=now\r\n' > "$T/.claude-logs/watcher_busy.txt"
out="$(CLAUDE_PICKUP_WAIT=2 bash "$PKG" "$T" --timeout 5 "vcpkg search fmt")"; rc=$?
ok "package_once: watcher busy -> no WATCHER_NOT_RUNNING; TIMEOUT (rc=5) says not to start another run; the unpicked flag is withdrawn" "$([ $rc = 5 ] && [ "$(echo "$out" | head -n 1)" = TIMEOUT ] && echo "$out" | grep -q 'Do NOT start another run' && [ ! -f "$T/trigger_package.flag" ] && echo 1 || echo 0)"
rm -f "$T/.claude-logs/watcher_busy.txt"
out="$(CLAUDE_PICKUP_WAIT=2 bash "$PKG" "$T" "vcpkg search fmt")"; rc=$?
ok "package_once: not busy and not picked up -> WATCHER_NOT_RUNNING (rc=3), the flag is removed" "$([ $rc = 3 ] && [ "$(echo "$out" | head -n 1)" = WATCHER_NOT_RUNNING ] && [ ! -f "$T/trigger_package.flag" ] && echo 1 || echo 0)"

# gtest: フラグの 1 行目は、タグのまま (古いウォッチャーが、1 行目だけを読んでも、動く)。2 行目が、# run=<ID>
fake_gt() {  # $1=ID を書くか (id / stale / none)
    while true; do
        if [ -f "$T/trigger_gtest.flag" ]; then
            id="$(rid "$T/trigger_gtest.flag")"; cp "$T/trigger_gtest.flag" "$T/gt_flag.copy"; rm -f "$T/trigger_gtest.flag"
            case "$1" in
                stale) printf 'run=OLD-RUN\r\n' > "$T/.claude-logs/run_id.txt"; printf OK > "$T/gtest_result.txt"; sleep 3 ;;
            esac
            [ "$1" != none ] && printf 'run=%s\r\n' "$id" > "$T/.claude-logs/run_id.txt"
            if [ "$1" = stale ]; then printf 'ERROR: git clone failed\n' > "$T/gtest_error.log"; printf FAILED > "$T/gtest_result.txt"; else printf OK > "$T/gtest_result.txt"; fi
        fi
        sleep 0.2
    done
}
fake_gt id & W=$!
out="$(bash "$GT" "$T" v1.17.0 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "gtest_once: matching run id accepted (OK, rc=0); flag line 1 = the tag, line 2 = '# run=<ID>'" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = OK ] && [ "$(sed -n 1p "$T/gt_flag.copy")" = v1.17.0 ] && [ "$(sed -n 2p "$T/gt_flag.copy" | cut -c1-6)" = "# run=" ] && echo 1 || echo 0)"
rm -f "$T/gtest_result.txt" "$T/.claude-logs/run_id.txt"
fake_gt id & W=$!
out="$(bash "$GT" "$T" "" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "gtest_once: no tag -> flag line 1 is empty (an old watcher reads the default tag), line 2 is the run id" "$([ $rc = 0 ] && [ -z "$(sed -n 1p "$T/gt_flag.copy" | tr -d '\r')" ] && [ "$(sed -n 2p "$T/gt_flag.copy" | cut -c1-6)" = "# run=" ] && echo 1 || echo 0)"
rm -f "$T/gtest_result.txt" "$T/.claude-logs/run_id.txt"
fake_gt stale & W=$!
out="$(bash "$GT" "$T" "" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "gtest_once: a stale OK written by an older run is NOT taken; the real FAILED is reported (rc=1)" "$([ $rc = 1 ] && [ "$(echo "$out" | head -n 1)" = FAILED ] && echo 1 || echo 0)"
rm -f "$T/gtest_result.txt" "$T/gtest_error.log" "$T/.claude-logs/run_id.txt"
fake_gt none & W=$!
out="$(bash "$GT" "$T" "" 30)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "gtest_once: an old watcher (no run_id.txt) still works (marker only)" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = OK ] && echo 1 || echo 0)"
rm -f "$T/gtest_result.txt" "$T/.claude-logs/run_id.txt"
printf 'gtest fetch run=other\r\nstarted=now\r\n' > "$T/.claude-logs/watcher_busy.txt"
out="$(CLAUDE_PICKUP_WAIT=2 bash "$GT" "$T" "" 5)"; rc=$?
ok "gtest_once: watcher busy -> TIMEOUT (rc=5), not WATCHER_NOT_RUNNING; the unpicked flag is withdrawn" "$([ $rc = 5 ] && [ "$(echo "$out" | head -n 1)" = TIMEOUT ] && [ ! -f "$T/trigger_gtest.flag" ] && echo 1 || echo 0)"
rm -f "$T/.claude-logs/watcher_busy.txt"

# ウォッチャー (ps1): gtest / package のフラグから、実行 ID を読み、マーカーの直前に run_id.txt を書く。# run= の行は、操作でもタグでもない
WP="$ROOT/host-tools/watch_and_build.ps1"
ok "watcher: Get-RunIdFromFlag accepts the comment form '# run=<ID>'; the gtest / package blocks read it; both marker writers call Write-RunId first" "$(grep -q "match '(?m)^#?\\\\s\*run=" "$WP" && grep -q 'CurrentRunId = Get-RunIdFromFlag \$GtestTriggerFile' "$WP" && grep -q 'CurrentRunId = Get-RunIdFromFlag \$PackageTriggerFile' "$WP" && awk '/^function Write-GtestMarker/{f=1} f&&/Write-RunId/{print "1"; exit} f&&/^}/{exit}' "$WP" | grep -q 1 && awk '/^function Write-PackageMarker/{f=1} f&&/Write-RunId/{print "1"; exit} f&&/^}/{exit}' "$WP" | grep -q 1 && echo 1 || echo 0)"
ok "watcher: a gtest flag whose first line is the comment (no tag) falls back to the default tag" "$(grep -q "gtestTagLine -match '\^\\\\s\*#'" "$WP" && echo 1 || echo 0)"

# --- フラグを書けなかったとき (v2.24.2): 待たずに、ENV_ERROR (rc=4) と理由を出す。何も始まっていない
for spec in "auto-build/scripts/build_once.sh|trigger_build.flag|" "build-test-loop/scripts/build_test_once.sh|trigger_test.flag|" "new-solution/scripts/gtest_once.sh|trigger_gtest.flag|" "add-package/scripts/package_once.sh|trigger_package.flag|nuget search foo"; do
    IFS='|' read -r sc fl arg <<<"$spec"
    D="$T/ff_$(basename "$sc" .sh)"; mkdir -p "$D/trigger_dummy"; mkdir "$D/$fl"   # フラグと同じ名前のフォルダ → 書けない
    start=$(date +%s)
    if [ -n "$arg" ]; then out="$(cd "$D" && bash "$ROOT/skills/$sc" "$D" "$arg" 2>/dev/null)"; rc=$?; else out="$(cd "$D" && bash "$ROOT/skills/$sc" "$D" 2>/dev/null)"; rc=$?; fi
    el=$(( $(date +%s) - start ))
    ok "$(basename "$sc"): flag cannot be written -> ENV_ERROR rc=4, immediately (${el}s)" "$([ "$rc" = 4 ] && [ "$el" -lt 5 ] && [ "$(echo "$out" | head -n1)" = ENV_ERROR ] && echo 1 || echo 0)"
    ok "$(basename "$sc"): says that nothing was started / run again from the start" "$(grep -q 'nothing was started' <<<"$out" && grep -q 'from the start' <<<"$out" && echo 1 || echo 0)"
done

# --- 起動したフォルダの綴りに合わせる (v2.24.4): 起動が小文字 (todo)、実際が ToDo のとき、フラグを、起動した綴りで書く
# (Linux は大文字小文字を区別するので、関数だけを取り出して、文字列として確かめる。実機の確認は、TEST-PLAN の NS10)
for sc in auto-build/scripts/build_once.sh build-test-loop/scripts/build_test_once.sh new-solution/scripts/gtest_once.sh add-package/scripts/package_once.sh; do
    fn="$(sed -n '/^align_to_launch_case()/,/^}/p' "$ROOT/skills/$sc")"
    r="$(bash -c 'PWD=/mnt/c/Workspace/todo; '"$fn"'; a() { align_to_launch_case "$1"; }; echo "$(a /mnt/c/Workspace/ToDo)|$(a /mnt/c/Workspace/ToDo/sub/X)|$(a /mnt/c/Workspace/ToDoX)|$(a /mnt/c/Workspace/Other)"')"
    ok "$(basename "$sc"): paths in the launch folder use the launch spelling; others are untouched ($r)" "$([ "$r" = "/mnt/c/Workspace/todo|/mnt/c/Workspace/todo/sub/X|/mnt/c/Workspace/ToDoX|/mnt/c/Workspace/Other" ] && echo 1 || echo 0)"
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
