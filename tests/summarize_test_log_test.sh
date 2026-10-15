#!/usr/bin/env bash
# summarize_test_log_test.sh - summarize_test_log.py の集約・場所・上限・フォールバックを検証する。
# Usage: tests/summarize_test_log_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/cpp-build-test-loop/scripts/summarize_test_log.py"
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

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
