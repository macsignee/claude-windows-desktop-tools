#!/usr/bin/env bash
# summarize_test_log_test.sh - summarize_test_log.py の集約・場所・上限・フォールバックを検証する。
# Usage: tests/summarize_test_log_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/build-test-loop/scripts/summarize_test_log.py"
T="${TMPDIR:-/tmp}/stl_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }

BOM=$'\xEF\xBB\xBF'; CR=$'\r'
{
    printf '%s=== X.exe: exit code 1 ===%s\n' "$BOM" "$CR"
    printf 'App/TestGeo.cpp(49): error: Expected equality of these values:%s\n  25.0%s\n  Which is: 28%s\n' "$CR" "$CR" "$CR"
    printf '[  FAILED  ] TestPointD.DistX (0 ms)%s\n' "$CR"
    printf 'App/TestGeo.cpp(60): error: Expected equality of these values:%s\n  25.0%s\n  Which is: 28%s\n' "$CR" "$CR" "$CR"
    printf '[  FAILED  ] TestPointD.DistY (0 ms)%s\n' "$CR"
    printf 'App/TestLine.cpp(10): error: Value of: ok%s\n  Actual: false%s\nExpected: true%s\n' "$CR" "$CR" "$CR"
    printf '[  FAILED  ] TestLineD.Foo/0, where GetParam() = 1 (1 ms)%s\n' "$CR"
    printf '[==========] 5 tests ran.%s\n[  FAILED  ] 3 tests, listed below:%s\n' "$CR" "$CR"
    printf '[  FAILED  ] TestPointD.DistX%s\n[  FAILED  ] TestPointD.DistY%s\n[  FAILED  ] TestLineD.Foo/0, where GetParam() = 1%s\n' "$CR" "$CR" "$CR"
    printf '%s\n 3 FAILED TESTS%s\n%s\nTests failed%s\n' "$CR" "$CR" "$CR" "$CR"
} > "$T/t.log"

out="$(python3 -I "$S" "$T/t.log" --json "$T/o.json")"; rc=$?
ok "rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "header: 3 failed, 2 suites with counts" "$(has "$out" '3 failed tests in 2 suites: TestPointD 2, TestLineD 1')"
ok "same message grouped (x2)" "$(has "$out" '[1] x2  Expected equality of these values: | 25.0 | Which is: 28')"
ok "grouped tests listed" "$(has "$out" 'tests: TestPointD.DistX, TestPointD.DistY')"
ok "both locations listed" "$(has "$out" 'App/TestGeo.cpp(49)  App/TestGeo.cpp(60)')"
ok "different message is a separate group" "$(has "$out" '[2]  Value of: ok | Actual: false | Expected: true')"
ok "parameterized name (', where GetParam()') parsed" "$(has "$out" 'tests: TestLineD.Foo/0')"
ok "listed-below re-list not double counted" "$([ "$(grep -c 'DistX' <<<"$out")" = 1 ] && echo 1 || echo 0)"
ok "gtest summary lines not in output" "$([ "$(grep -c '==========\|FAILED TESTS\|Tests failed' <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "BOM stripped" "$([ "$(grep -c "$BOM" <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "json written (all names) and valid" "$(python3 -c "import json,sys; d=json.load(open('$T/o.json')); sys.exit(0 if d['failed']==3 and len(d['tests'])==3 and d['groups'][0]['count']==2 else 1)" && echo 1 || echo 0)"

# Linux 形式 (file:line: Failure)
printf 'a_test.cc:12: Failure\nExpected equality\n[  FAILED  ] S.T (0 ms)\n' > "$T/l.log"
ok "linux 'file:line: Failure' form" "$(has "$(python3 -I "$S" "$T/l.log")" 'at: a_test.cc(12)')"

# 上限: 異なる失敗 100 件でも max-lines に収まる。全名は JSON に残る
for i in $(seq 1 100); do printf 'a.cpp(%d): error: m%d\n[  FAILED  ] S.C%d (0 ms)\n' "$i" "$i" "$i"; done > "$T/big.log"
n="$(python3 -I "$S" "$T/big.log" --json "$T/big.json" | wc -l)"
ok "output capped at 40 lines (got $n)" "$([ "$n" -le 40 ] && echo 1 || echo 0)"
ok "json keeps all 100 names" "$(python3 -c "import json,sys; sys.exit(0 if len(json.load(open('$T/big.json'))['tests'])==100 else 1)" && echo 1 || echo 0)"

# クラッシュ (失敗テスト名なし) は rc=3 で何も出さない (従来の表示へ)
printf '=== X.exe: exit code -1 ===\n(no gtest failure lines: process crashed or exited abnormally, exit code -1)\nTests failed\n' > "$T/c.log"
out="$(python3 -I "$S" "$T/c.log")"; rc=$?
ok "crash (no test names) -> rc=3, no output" $([ $rc = 3 ] && [ -z "$out" ] && echo 1 || echo 0)


# ---------- 構造化された結果 (GoogleTest XML + trx) ----------
FX="$ROOT/tests/fixtures"
mkdir -p "$T/res"; cp "$FX/LogicLayerTest.xml" "$FX/WpfApp.Tests.trx" "$T/res/"
: > "$T/empty.log"
out="$(python3 -I "$S" "$T/empty.log" --results-dir "$T/res" --root /mnt/c/w --json "$T/s.json")"; rc=$?
ok "structured: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "structured: header has totals from both frameworks" "$(has "$out" '6 failed tests in 4 suites')"
ok "structured: ran/passed/failed/skipped counts" "$(has "$out" '[ran 10: passed 2 / failed 6 / skipped 2]')"
ok "gtest xml: same message grouped (x2)" "$(has "$out" '[1] x2  Expected equality of these values: | 25.0 | Which is: 28')"
ok "gtest xml: windows path made relative (--root)" "$(has "$out" 'at: LogicLayerTest/TestGeo.cpp(49)  LogicLayerTest/TestGeo.cpp(60)')"
ok "gtest xml: parameterized name (classname Inst/TestLineD)" "$(has "$out" 'tests: Inst/TestLineD.Foo/0')"
ok "gtest xml: skipped test is not a failure" "$([ "$(grep -c 'Later' <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "trx: same message grouped across tests (x2)" "$(has "$out" '[3] x2  Assert.AreEqual failed. Expected:<3>. Actual:<4>.')"
ok "trx: full name = class + method" "$(has "$out" 'tests: WpfApp.Tests.CalcTests.AddsTwoNumbers, WpfApp.Tests.CalcTests.SubtractsTwoNumbers')"
ok "trx: location from the first stack frame with a file" "$(has "$out" 'at: WpfApp.Tests/CalcTests.cs(21)  WpfApp.Tests/CalcTests.cs(30)')"
ok "trx: data-row suffix kept in the name" "$(has "$out" 'WpfApp.Tests.ViewModelTests.IsEven (2,True)')"
ok "trx: NotExecuted is skipped, not failed" "$([ "$(grep -c 'Ignored' <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "json schema 2: structured, totals, per-source counts" "$(python3 -c "
import json,sys
d=json.load(open('$T/s.json'))
ok = (d['schema']==2 and d['structured'] is True and d['totals']=={'total':10,'passed':2,'failed':6,'skipped':2}
      and {s['framework'] for s in d['sources']}=={'gtest','mstest'}
      and d['failed']==6 and len(d['tests'])==6 and d['groups'][0]['count']==2)
sys.exit(0 if ok else 1)" && echo 1 || echo 0)"
ok "json keeps legacy keys (failed/groups/tests/other)" "$(python3 -c "
import json,sys
d=json.load(open('$T/s.json')); sys.exit(0 if all(k in d for k in ('failed','groups','tests','other')) else 1)" && echo 1 || echo 0)"

# 全部成功の結果だけがあるとき: 失敗なし → rc=3 (呼び出し側は、従来の表示へ)
mkdir -p "$T/res_ok"
python3 - "$T/res_ok" <<'PY'
import sys
open(sys.argv[1] + "/A.xml", "w").write('<?xml version="1.0"?><testsuites><testsuite name="S"><testcase name="T" classname="S" status="run" time="0"/></testsuite></testsuites>')
PY
python3 -I "$S" "$T/empty.log" --results-dir "$T/res_ok" >/dev/null; rc=$?
ok "structured: no failures -> rc=3" $([ $rc = 3 ] && echo 1 || echo 0)

# 壊れた XML は、other に残し、読めたほうは使う
mkdir -p "$T/res_bad"; cp "$FX/WpfApp.Tests.trx" "$T/res_bad/"; printf '<testsuites><broken' > "$T/res_bad/Broken.xml"
out="$(python3 -I "$S" "$T/empty.log" --results-dir "$T/res_bad")"
ok "broken xml: reported under other, valid trx still used" "$([ "$(has "$out" '3 failed tests')" = 1 ] && [ "$(has "$out" 'could not read Broken.xml')" = 1 ] && echo 1 || echo 0)"

# 構造化された結果と一緒に、テキストのログのクラッシュ報告も残す
printf '=== CrashTest.exe: exit code -1073741819 ===\n(no gtest failure lines: process crashed or exited abnormally, exit code -1073741819)\nTests failed\n' > "$T/crash.log"
out="$(python3 -I "$S" "$T/crash.log" --results-dir "$T/res")"
ok "structured + text log: crash report kept under other" "$([ "$(has "$out" 'other:')" = 1 ] && [ "$(has "$out" 'process crashed or exited abnormally')" = 1 ] && [ "$(grep -c '=== CrashTest.exe: exit code' <<<"$out")" = 0 ] && echo 1 || echo 0)"

# 結果ディレクトリがない / 空 → テキストの解釈に戻る (従来どおり)
out="$(python3 -I "$S" "$T/t.log" --results-dir "$T/nonexistent")"
ok "no results dir -> falls back to the text log" "$(has "$out" '3 failed tests in 2 suites: TestPointD 2, TestLineD 1')"

# MSTest の、日本語 OS のスタックトレース (場所 ...:行 N)
mkdir -p "$T/res_ja"
python3 - "$T/res_ja" <<'PY'
import sys
trx = """<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results>
<UnitTestResult testId="t1" testName="M" duration="00:00:00.001" outcome="Failed"><Output><ErrorInfo><Message>x</Message>
<StackTrace>   場所 N.C.M() 場所 C:\\w\\P.Tests\\C.cs:行 7</StackTrace></ErrorInfo></Output></UnitTestResult></Results>
<TestDefinitions><UnitTest name="M" id="t1"><TestMethod className="N.C, P.Tests" name="M"/></UnitTest></TestDefinitions></TestRun>"""
open(sys.argv[1] + "/P.Tests.trx", "w", encoding="utf-8").write(trx)
PY
out="$(python3 -I "$S" "$T/empty.log" --results-dir "$T/res_ja" --root /mnt/c/w)"
ok "trx: Japanese stack trace location (場所 ...:行 N)" "$(has "$out" 'at: P.Tests/C.cs(7)')"

# ---------------------------------------------------------------- --passed-line (成功時の 1 行。build_test_once.sh が、PASSED の次の行に出す)
mkdir -p "$T/pl_two" "$T/pl_skip" "$T/pl_empty"
python3 - "$T" <<'PY'
import sys
def trx(path, results):
    rs = "".join(f'<UnitTestResult testId="t{i}" testName="{n}" duration="00:00:00.001" outcome="{o}"/>' for i, (n, o) in enumerate(results))
    ds = "".join(f'<UnitTest name="{n}" id="t{i}"><TestMethod className="N.C, {path.rsplit("/", 1)[1][:-4]}" name="{n}"/></UnitTest>' for i, (n, o) in enumerate(results))
    open(path, "w", encoding="utf-8").write('<?xml version="1.0" encoding="utf-8"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results>' + rs + '</Results><TestDefinitions>' + ds + '</TestDefinitions></TestRun>')
t = sys.argv[1]
trx(t + "/pl_two/DataLayer.Tests.trx", [("A", "Passed")])
trx(t + "/pl_two/LogicLayer.Tests.trx", [("B", "Passed"), ("C", "Passed"), ("D", "Passed"), ("E", "Passed"), ("F", "Passed")])
trx(t + "/pl_skip/P.Tests.trx", [("A", "Passed"), ("B", "NotExecuted")])
PY
out="$(python3 -I "$S" --passed-line --results-dir "$T/pl_two" --root /mnt/c/w)"; rc=$?
ok "passed-line: two MSTest projects -> one line with per-project counts (rc=0)" "$([ $rc = 0 ] && [ "$out" = "tests: 6 passed (DataLayer.Tests 1, LogicLayer.Tests 5)" ] && echo 1 || echo 0)"
ok "passed-line: it is exactly one line" "$([ "$(wc -l <<<"$out")" = 1 ] && echo 1 || echo 0)"
out="$(python3 -I "$S" --passed-line --results-dir "$T/pl_skip")"
ok "passed-line: skipped tests are counted (tests: 1 passed, 1 skipped (P.Tests 2))" "$([ "$out" = "tests: 1 passed, 1 skipped (P.Tests 2)" ] && echo 1 || echo 0)"
cp "$FX/LogicLayerTest.xml" "$T/pl_skip/"
out="$(python3 -I "$S" --passed-line --results-dir "$T/pl_skip")"
ok "passed-line: GoogleTest XML and trx together are both listed (a failing fixture also shows its failed count)" "$(grep -qF 'P.Tests 2' <<<"$out" && grep -qF 'LogicLayerTest 5' <<<"$out" && grep -qF '3 failed' <<<"$out" && echo 1 || echo 0)"
python3 -I "$S" --passed-line --results-dir "$T/pl_empty" >/dev/null; rc=$?
ok "passed-line: no structured results -> rc=3 and no output" "$([ $rc = 3 ] && [ -z "$(python3 -I "$S" --passed-line --results-dir "$T/pl_empty")" ] && echo 1 || echo 0)"
python3 -I "$S" --passed-line --results-dir "$T/nonexistent" >/dev/null; rc=$?
ok "passed-line: missing results dir -> rc=3" "$([ $rc = 3 ] && echo 1 || echo 0)"
python3 -I "$S" --passed-line >/dev/null; rc=$?
ok "passed-line: no --results-dir -> rc=3" "$([ $rc = 3 ] && echo 1 || echo 0)"
python3 -I "$S" >/dev/null 2>&1; rc=$?
ok "without a log and without --passed-line: usage error (rc=2)" "$([ $rc = 2 ] && echo 1 || echo 0)"
mkdir -p "$T/pl_many"
for n in 1 2 3 4 5 6 7 8; do cp "$T/pl_skip/P.Tests.trx" "$T/pl_many/S$n.Tests.trx"; done
out="$(python3 -I "$S" --passed-line --results-dir "$T/pl_many")"
ok "passed-line: more than 6 sources are capped with '... +2 more'" "$(has "$out" '... +2 more')"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
