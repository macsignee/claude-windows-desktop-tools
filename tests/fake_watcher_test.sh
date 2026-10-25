#!/usr/bin/env bash
# fake_watcher_test.sh - build_test_once.sh を、疑似ウォッチャー (ファイルを書くだけの偽物) で検証する。
#
# Windows 側のウォッチャーや VS がなくても、WSL/Linux だけで、結果の分岐 (1行目と終了コード) を確認できる。
# Usage: tests/fake_watcher_test.sh        (各ケースの出力の後に rc=... が出る。期待値は、見出しの expect を参照)
export LC_ALL=C
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills/build-test-loop/scripts/build_test_once.sh"
T="${TMPDIR:-/tmp}/bt_$$"
FX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures"
rm -rf "$T"; mkdir -p "$T"
BOM=$'\xEF\xBB\xBF'
CR=$'\r'

# 疑似ウォッチャー: フラグを回収し、1秒後に $1 の関数でファイルを書く
fake_watcher() {
    local handler="$1"
    while true; do
        if [ -f "$T/trigger_test.flag" ]; then
            rm -f "$T/trigger_test.flag"
            sleep 1
            "$handler"
        fi
        sleep 0.3
    done
}

h_passed()  { printf SUCCESS > "$T/build_result.txt"; printf PASSED > "$T/test_result.txt"; }
h_passedwarn() {   # 成功でも警告があれば、PASSED の次の行に 1 行だけ件数が出るか
    mkdir -p "$T/.claude-logs"
    {
        printf 'C:\\w\\a.cpp(1,1): warning C4244: conv [C:\\w\\a.vcxproj]%s\n' "$CR"
        printf 'C:\\w\\b.cpp(2,1): warning C4244: conv [C:\\w\\a.vcxproj]%s\n' "$CR"
    } > "$T/.claude-logs/warnings.log"
    printf SUCCESS > "$T/build_result.txt"; printf PASSED > "$T/test_result.txt"
}
h_passedstruct() {   # 構造化された結果 (trx) があれば、PASSED の次の行に、build: SUCCESS / tests: ... の要約が出るか
    mkdir -p "$T/.claude-logs/test-results"
    printf '%s' '<?xml version="1.0" encoding="utf-8"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results><UnitTestResult testId="t1" testName="A" duration="00:00:00.001" outcome="Passed"/><UnitTestResult testId="t2" testName="B" duration="00:00:00.001" outcome="Passed"/></Results><TestDefinitions><UnitTest name="A" id="t1"><TestMethod className="N.C, X.Tests" name="A"/></UnitTest><UnitTest name="B" id="t2"><TestMethod className="N.C, X.Tests" name="B"/></UnitTest></TestDefinitions></TestRun>' > "$T/.claude-logs/test-results/X.Tests.trx"
    printf SUCCESS > "$T/build_result.txt"; printf PASSED > "$T/test_result.txt"
}
h_failed()  {
    printf SUCCESS > "$T/build_result.txt"
    {
        printf '%s=== X.exe: exit code 1 ===%s\n' "$BOM" "$CR"
        printf 'DoubleBufferSampleTest/TestGeometry.cpp(49): error: Expected equality%s\n' "$CR"
        printf '  25.0%s\n  Which is: 28%s\n' "$CR" "$CR"
        printf '[  FAILED  ] TestPointD.GetDistance_X (0 ms)%s\n' "$CR"
        printf '[  FAILED  ] TestLineD.Foo (1 ms)%s\n%s\nTests failed%s\n' "$CR" "$CR" "$CR"
    } > "$T/test_error.log"
    printf FAILED > "$T/test_result.txt"
}
h_buildfail() {
    { printf '%sa.cpp(1,1): error C2143: x%s\n%s\nBuild failed with exit code: 1%s\n' "$BOM" "$CR" "$CR" "$CR"; } > "$T/build_error.log"
    printf FAILED > "$T/build_result.txt"; printf BUILD_FAILED > "$T/test_result.txt"
}
h_buildenv() {
    { printf '%s[ENVIRONMENT ERROR - not a source code problem]%s\nERROR: x%s\n' "$BOM" "$CR" "$CR"; } > "$T/build_error.log"
    printf FAILED > "$T/build_result.txt"; printf BUILD_FAILED > "$T/test_result.txt"
}
h_testtimeout() {
    printf SUCCESS > "$T/build_result.txt"
    { printf '=== X.exe: TIMEOUT after 5s (killed) ===%s\n' "$CR"; } > "$T/test_error.log"
    printf TIMEOUT > "$T/test_result.txt"
}
h_testenv() {
    { printf '%s[ENVIRONMENT ERROR - not a source code problem]%s\nERROR: no test exe%s\n' "$BOM" "$CR" "$CR"; } > "$T/test_error.log"
    printf ENV_ERROR > "$T/test_result.txt"
}
h_manyfail() {   # 失敗が多く詳細が60行を超えても、失敗一覧が先頭に出るか
    printf SUCCESS > "$T/build_result.txt"
    {
        for i in $(seq 1 80); do
            printf 'DoubleBufferSampleTest/T.cpp(%d): error: Expected equality%s\n  1\n  Which is: 2%s\n' "$i" "$CR" "$CR"
            printf '[  FAILED  ] Suite.Case%d (0 ms)%s\n' "$i" "$CR"
        done
        printf '[  FAILED  ] 80 tests, listed below:%s\n' "$CR"
        for i in $(seq 1 80); do printf '[  FAILED  ] Suite.Case%d%s\n' "$i" "$CR"; done
    } > "$T/test_error.log"
    printf FAILED > "$T/test_result.txt"
}
h_failed_structured() {   # GoogleTest の XML と trx (MSTest) の両方がある失敗: 共通の形式で要約されるか
    printf SUCCESS > "$T/build_result.txt"
    mkdir -p "$T/.claude-logs/test-results"
    cp "$FX/LogicLayerTest.xml" "$FX/WpfApp.Tests.trx" "$T/.claude-logs/test-results/"
    { printf '=== LogicLayerTest.exe ===\n[  FAILED  ] TestPointD.DistX (0 ms)\n=== WpfApp.Tests (dotnet test) ===\nFAILED x\n\nTests failed\n'; } > "$T/test_error.log"
    printf FAILED > "$T/test_result.txt"
}
h_failed_stale_results() {   # 前回の結果 (XML) が残っていても、今回の実行の前に、消されているか
    printf SUCCESS > "$T/build_result.txt"
    { printf '=== X.exe: exit code 1 ===\nA.cpp(1): error: Expected equality\n[  FAILED  ] S.OnlyThis (0 ms)\n\nTests failed\n'; } > "$T/test_error.log"
    printf FAILED > "$T/test_result.txt"
}
h_never()   { :; }            # フラグは回収するがマーカーを書かない
h_stale()   { sleep 2; h_passed; }   # 古い結果が残っていても、消されるか

run_case() {  # $1=名前 $2=ハンドラ $3=timeout
    echo "=== $1"
    fake_watcher "$2" & local W=$!
    bash "$SCRIPT" "$T" "${3:-20}"
    echo "rc=$?"
    kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
    rm -rf "$T"/*.txt "$T"/*.log "$T"/*.flag "$T"/.claude-logs
}

bash -n "$SCRIPT" && echo "syntax-ok"
run_case "PASSED (expect rc=0)"                 h_passed
run_case "PASSED with structured results (expect rc=0, 2nd line: build: SUCCESS / tests: 2 passed (X.Tests 2))" h_passedstruct
run_case "PASSED with warnings (expect rc=0, 2nd line: warnings: 2 (1 unique): C4244 x2)" h_passedwarn
run_case "FAILED (expect rc=1, names first)"    h_failed
run_case "BUILD_FAILED (expect rc=6)"           h_buildfail
run_case "BUILD env -> ENV_ERROR (expect rc=4)" h_buildenv
run_case "TEST_TIMEOUT (expect rc=7)"           h_testtimeout
run_case "ENV_ERROR (expect rc=4)"              h_testenv
run_case "many failures (expect rc=1, 80 same-message failures grouped as x80, names/locations capped)" h_manyfail

echo "=== stale marker removed before wait (expect rc=0 after ~2s, not instant)"
printf PASSED > "$T/test_result.txt"; printf SUCCESS > "$T/build_result.txt"
fake_watcher h_stale & W=$!
start=$(date +%s); bash "$SCRIPT" "$T" 20; echo "rc=$? elapsed=$(( $(date +%s) - start ))s"
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
rm -f "$T"/*.txt "$T"/*.log "$T"/*.flag

echo "=== WATCHER_NOT_RUNNING (expect rc=3 after ~15s)"
bash "$SCRIPT" "$T" 30; echo "rc=$?"
rm -f "$T"/*.flag

run_case "TIMEOUT: flag picked up, no marker (expect rc=5)" h_never 4

echo "=== BAD_ARGS (expect rc=2)"
bash "$SCRIPT" "$T/nonexistent" 5; echo "rc=$?"


# ---------- 構造化された結果 (GoogleTest XML + trx) の経路 ----------
asserts=0; assert_fail=0
expect() { asserts=$((asserts+1)); if ! grep -qF -- "$2" <<<"$1"; then assert_fail=$((assert_fail+1)); echo "FAIL: $3 (missing: $2)"; fi; }

echo "=== FAILED with gtest XML + trx (expect rc=1, one common summary for both frameworks)"
fake_watcher h_failed_structured & W=$!
out="$(bash "$SCRIPT" "$T" 20)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
echo "$out"; echo "rc=$rc"
expect "$out" "FAILED" "first line is FAILED"
expect "$out" "6 failed tests in 4 suites" "summary covers both frameworks"
expect "$out" "[ran 10: passed 2 / failed 6 / skipped 2]" "ran/passed/failed/skipped"
expect "$out" "WpfApp.Tests.CalcTests.AddsTwoNumbers" "MSTest failure listed"
expect "$out" "TestGeo.cpp(49)" "GoogleTest location shown (relative-path conversion is covered by summarize_test_log_test.sh)"
[ "$rc" = 1 ] || { assert_fail=$((assert_fail+1)); echo "FAIL: rc=$rc (expected 1)"; }
[ -f "$T/.claude-logs/test_summary.json" ] || { assert_fail=$((assert_fail+1)); echo "FAIL: test_summary.json not written"; }
rm -rf "$T"/*.txt "$T"/*.log "$T"/*.flag "$T"/.claude-logs

echo "=== stale test-results removed before the run (expect the text log to be used, not old XML)"
mkdir -p "$T/.claude-logs/test-results"; cp "$FX/WpfApp.Tests.trx" "$T/.claude-logs/test-results/"
fake_watcher h_failed_stale_results & W=$!
out="$(bash "$SCRIPT" "$T" 20)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
echo "$out"; echo "rc=$rc"
expect "$out" "S.OnlyThis" "text log used"
if grep -qF "WpfApp.Tests" <<<"$out"; then assert_fail=$((assert_fail+1)); echo "FAIL: stale trx leaked into the summary"; fi
rm -rf "$T"/*.txt "$T"/*.log "$T"/*.flag "$T"/.claude-logs

echo "structured-path asserts: $asserts checked, $assert_fail failed"

rm -rf "$T"
echo "ALL DONE"
[ "$assert_fail" = 0 ]
