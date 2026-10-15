#!/usr/bin/env bash
# summarize_build_log_test.sh - summarize_build_log.py の集約・並び・上限・フォールバックを検証する。
# Usage: tests/summarize_build_log_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/cpp-auto-build/scripts/summarize_build_log.py"
T="${TMPDIR:-/tmp}/sbl_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }

BOM=$'\xEF\xBB\xBF'; CR=$'\r'
{
    printf '%s2>MyApp/Foo.cpp(49,5): error C2065: '"'"'cnt'"'"': undeclared identifier [C:\\w\\MyApp.vcxproj]%s\n' "$BOM" "$CR"
    printf 'MyApp/Foo.cpp(50,9): error C2065: '"'"'cnt'"'"': undeclared identifier [C:\\w\\MyApp.vcxproj]%s\n' "$CR"
    printf 'MyApp/Foo.cpp(50,9): error C2065: '"'"'cnt'"'"': undeclared identifier [C:\\w\\MyApp.vcxproj]%s\n' "$CR"
    printf 'MyApp/Bar.cpp(12,3): error C2065: '"'"'cnt'"'"': undeclared identifier [C:\\w\\MyApp.vcxproj]%s\n' "$CR"
    printf 'MyApp/Bar.cpp(20): error C2143: syntax error [C:\\w\\MyApp.vcxproj]%s\n' "$CR"
    printf 'Foo.obj : error LNK2019: unresolved external symbol f [C:\\w\\MyApp.vcxproj]%s\n' "$CR"
    printf 'MyApp.exe : fatal error LNK1120: 1 unresolved externals [C:\\w\\MyApp.vcxproj]%s\n' "$CR"
    printf 'weird line%s\n%s\nBuild failed with exit code: 1%s\n' "$CR" "$CR" "$CR"
} > "$T/e.log"

out="$(python3 -I "$S" "$T/e.log" --json "$T/o.json")"; rc=$?
ok "rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "header counts (7 errors, 4 unique, compile 5 / link 2)" "$(has "$out" '7 errors (4 unique) in 4 files; compile 5 / link 2')"
ok "same error grouped with count x4" "$(has "$out" "C2065 'cnt': undeclared identifier  x4")"
ok "duplicate location listed once" "$([ "$(grep -o 'Foo.cpp(50,9)' <<<"$out" | wc -l)" = 1 ] && echo 1 || echo 0)"
ok "first-seen order (C2065 before LNK2019)" "$([ "$(grep -n 'C2065' <<<"$out" | head -1 | cut -d: -f1)" -lt "$(grep -n 'LNK2019' <<<"$out" | cut -d: -f1)" ] && echo 1 || echo 0)"
ok "unparsed line kept under other:" "$(has "$out" '    weird line')"
ok "BOM / N> prefix stripped" "$([ "$(grep -c "$BOM\|2>" <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "json written and valid" "$(python3 -c "import json,sys; d=json.load(open('$T/o.json')); sys.exit(0 if d['errors']==7 and d['groups'][0]['count']==4 else 1)" && echo 1 || echo 0)"

# 上限: 異なるエラー 100 件でも max-lines に収まる
for i in $(seq 1 100); do printf 'a.cpp(%d,1): error C2065: '"'"'v%d'"'"': undeclared identifier\n' "$i" "$i"; done > "$T/big.log"
n="$(python3 -I "$S" "$T/big.log" | wc -l)"
ok "output capped at 40 lines (got $n)" "$([ "$n" -le 40 ] && echo 1 || echo 0)"

# 解釈できるエラーがなければ rc=3 で何も出さない (呼び出し側が生ログへ切り替える)
printf 'nothing parsable\n' > "$T/j.log"
out="$(python3 -I "$S" "$T/j.log")"; rc=$?
ok "unparsable -> rc=3, no output" $([ $rc = 3 ] && [ -z "$out" ] && echo 1 || echo 0)

# --- 警告 (--severity warning / --root / --oneline) ---
mkdir -p "$T/w/proj"
{
    printf '%sC:\\work\\proj\\MyApp\\Foo.cpp(12,5): warning C4244: conv [C:\\work\\proj\\MyApp\\MyApp.vcxproj]%s\n' "$BOM" "$CR"
    printf 'C:\\work\\proj\\MyApp\\Bar.cpp(7,1): warning C4244: conv [C:\\work\\proj\\MyApp\\MyApp.vcxproj]%s\n' "$CR"
    printf 'c:\\WORK\\proj\\MyApp\\Bar.cpp(9,3): warning C4996: unsafe [C:\\work\\proj\\MyApp\\MyApp.vcxproj]%s\n' "$CR"
    printf 'C:\\Program Files\\VS\\include\\x.h(1): warning C4005: redefined [C:\\work\\proj\\MyApp\\MyApp.vcxproj]%s\n' "$CR"
    printf 'Foo.cpp(1): error C2065: x [C:\\work\\proj\\MyApp\\MyApp.vcxproj]%s\n' "$CR"
} > "$T/w.log"
out="$(python3 -I "$S" "$T/w.log" --severity warning --root /mnt/c/work/proj --json "$T/w.json")"; rc=$?
ok "warnings: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "warnings: header (4 warnings, 3 unique; errors not counted)" "$(has "$out" '4 warnings (3 unique) in 3 files')"
ok "warnings: grouped x2" "$(has "$out" "C4244 conv  x2")"
ok "warnings: paths made relative (case-insensitive drive/dir)" "$(has "$out" 'MyApp/Foo.cpp(12,5)  MyApp/Bar.cpp(7,1)')"
ok "warnings: path outside root kept (/ separated)" "$(has "$out" 'C:/Program Files/VS/include/x.h(1)')"
ok "warnings: no 'other:' section for unparsed/error lines" "$([ "$(grep -c 'other:' <<<"$out")" = 0 ] && echo 1 || echo 0)"
ok "warnings: json key is 'warnings'" "$(python3 -c "import json,sys; d=json.load(open('$T/w.json')); sys.exit(0 if d['warnings']==4 and 'errors' not in d else 1)" && echo 1 || echo 0)"
one="$(python3 -I "$S" "$T/w.log" --severity warning --root /mnt/c/work/proj --oneline)"
ok "warnings: --oneline is one line with top codes" "$([ "$(wc -l <<<"$one")" = 1 ] && [ "$(has "$one" 'warnings: 4 (3 unique): C4244 x2, C4996 x1, C4005 x1')" = 1 ] && echo 1 || echo 0)"
printf 'Foo.cpp(1): error C2065: x\n' > "$T/nowarn.log"
out="$(python3 -I "$S" "$T/nowarn.log" --severity warning)"; rc=$?
ok "warnings: none -> rc=3, no output" $([ $rc = 3 ] && [ -z "$out" ] && echo 1 || echo 0)

# 2 つの Skill のコピーが同一であること
ok "skill copies identical" $(cmp -s "$S" "$ROOT/skills/cpp-build-test-loop/scripts/summarize_build_log.py" && echo 1 || echo 0)

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
