#!/usr/bin/env bash
# vs_once_test.sh - vs-debug (v2.90.0) を、疑似ウォッチャー (ファイルを書くだけの偽物) と、静的な検査で確かめる。
# Windows の Visual Studio がなくても、フラグの中身・結果の分岐・差分からの行の選び方・文書の整合を、確認できる。
# Usage: tests/vs_once_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/vs-debug/scripts/vs_once.sh"
CL="$ROOT/skills/vs-debug/scripts/changed_lines.py"
SKILL="$ROOT/skills/vs-debug/SKILL.md"
PS1="$ROOT/host-tools/lib/vs-ide.ps1"
T="${TMPDIR:-/tmp}/vsonce_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
BOM=$'\xEF\xBB\xBF'; CR=$'\r'

bash -n "$SCRIPT" && ok "syntax: vs_once.sh" 1
python3 -I -c "import ast;ast.parse(open('$CL',encoding='utf-8').read())" && ok "syntax: changed_lines.py" 1

# ---------------------------------------------------------------- changed_lines.py (git の差分 -> ブレークポイントの行)
G="$T/repo"; mkdir -p "$G"
git_() { git -c user.name=t -c user.email=t@example.com -c core.autocrlf=false -C "$G" "$@"; }
git_ init -q
printf 'int a()\n{\n    return 1;\n}\nint b()\n{\n    return 2;\n}\n' > "$G/a.cpp"
printf 'a\nb\n' > "$G/notes.txt"
git_ add -A >/dev/null; git_ commit -qm init
printf 'int a()\n{\n    int x = 1;\n    return x;\n}\nint b()\n{\n    // changed\n    return 3;\n}\n' > "$G/a.cpp"
printf 'a\nb\nc\n' > "$G/notes.txt"
printf 'int g() { return 3; }\n' > "$G/new.cpp"
out="$(python3 -I "$CL" "$G")"; rc=$?
ok "changed_lines: rc=0" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "changed_lines: the first hunk -> a.cpp:3 (int x = 1;)" "$(grep -qx 'a.cpp:3' <<<"$out" && echo 1 || echo 0)"
ok "changed_lines: a second hunk gets its own line, skipping its comment (a.cpp:9, return 3;)" "$(grep -qx 'a.cpp:9' <<<"$out" && echo 1 || echo 0)"
ok "changed_lines: non-source files (notes.txt) are skipped" "$(grep -q 'notes' <<<"$out" && echo 0 || echo 1)"
ok "changed_lines: a new untracked source file is reported as NEW_FILE, with no line" "$(grep -qx 'NEW_FILE: new.cpp' <<<"$out" && ! grep -q '^new.cpp:' <<<"$out" && echo 1 || echo 0)"
names="$(python3 -I "$CL" "$G" --names)"
ok "changed_lines --names: changed + new files (a.cpp, notes.txt, new.cpp)" "$([ "$(sort <<<"$names" | tr '\n' ' ')" = "a.cpp new.cpp notes.txt " ] && echo 1 || echo 0)"
out="$(python3 -I "$CL" "$G" --max 1)"
ok "changed_lines --max 1: one line + TRUNCATED" "$([ "$(grep -c '^a.cpp:' <<<"$out")" = 1 ] && grep -q '^TRUNCATED: ' <<<"$out" && echo 1 || echo 0)"
# 削除だけ・コメントだけ・波かっこだけの変更は、選ばない
git_ add -A >/dev/null; git_ commit -qm second
printf '// only a comment\n' >> "$G/a.cpp"
printf '{\n}\n' >> "$G/new.cpp"
out="$(python3 -I "$CL" "$G")"
ok "changed_lines: comment-only / brace-only additions give no breakpoint" "$([ -z "$out" ] && echo 1 || echo 0)"
python3 -I "$CL" "$T" >"$T/o.txt" 2>&1; rc=$?
ok "changed_lines: not a git repository -> NOT_A_REPO rc=3" "$([ $rc = 3 ] && grep -qx NOT_A_REPO "$T/o.txt" && echo 1 || echo 0)"
python3 -I "$CL" >/dev/null 2>&1; rc=$?
ok "changed_lines: no args -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- vs_once.sh: 引数の検査 (フラグを、置く前に断る)
D="$T/sln"; mkdir -p "$D"
bad() { OUT="$(bash "$SCRIPT" "$D" "$@" 2>&1)"; RC=$?; }
bad --bogus;                        ok "BAD_ARGS: unknown option -> rc=2" "$([ $RC = 2 ] && [ "$(head -1 <<<"$OUT")" = "BAD_ARGS: unknown option: --bogus" ] && echo 1 || echo 0)"
bad --break "../x.cpp:3";           ok "BAD_ARGS: .. in --break path" "$([ $RC = 2 ] && [ "$(has "$OUT" 'without ..')" = 1 ] && echo 1 || echo 0)"
bad --break "/etc/passwd:3";        ok "BAD_ARGS: absolute path in --break" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --break 'C:\x\a.cpp:3';         ok "BAD_ARGS: drive letter in --break" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --break "src/a.cpp";            ok "BAD_ARGS: --break without a line number" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --status --debug;               ok "BAD_ARGS: --status cannot be combined" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --no-wait;                      ok "BAD_ARGS: --no-wait needs --debug" "$([ $RC = 2 ] && [ "$(has "$OUT" 'needs --debug')" = 1 ] && echo 1 || echo 0)"
bad --status --debug --no-wait;     ok "BAD_ARGS: --status cannot be combined with --debug --no-wait" "$([ $RC = 2 ] && echo 1 || echo 0)"
for fa in "--frame" "--frame abc --inspect" "--frame -1 --inspect" "--frame 100 --inspect" "--frame 18446744073709551616 --inspect" "--frame 100000000000000000000 --inspect" "--frame 2" "--frame 1 --inspect --step over" "--frame 1 --inspect --continue" "--frame 1 --inspect --pause" "--frame 1 --inspect --debug" "--frame 1 --status"; do
    rm -f "$D/trigger_vs.flag"
    # shellcheck disable=SC2086
    bad $fa; ok "BAD_ARGS: $fa (no flag is written)" "$([ $RC = 2 ] && [ ! -e "$D/trigger_vs.flag" ] && echo 1 || echo 0)"
done
bad --timeout abc;                  ok "BAD_ARGS: bad --timeout" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --output 0;                     ok "BAD_ARGS: --output 0 (1..500 lines)" "$([ $RC = 2 ] && [ "$(has "$OUT" '1 to 500')" = 1 ] && echo 1 || echo 0)"
bad --output 501;                   ok "BAD_ARGS: --output 501 (1..500 lines)" "$([ $RC = 2 ] && [ "$(has "$OUT" '1 to 500')" = 1 ] && echo 1 || echo 0)"
bad --output abc;                   ok "BAD_ARGS: --output abc (not a number: abc is an unknown option)" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --status --output;              ok "BAD_ARGS: --status cannot be combined with --output" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --status --inspect;             ok "BAD_ARGS: --status cannot be combined with --inspect" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --step;                         ok "BAD_ARGS: --step needs over / into / out" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --step sideways;                ok "BAD_ARGS: --step sideways (not over / into / out)" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --step over 0;                  ok "BAD_ARGS: --step over 0 (1..30 steps)" "$([ $RC = 2 ] && [ "$(has "$OUT" '1 to 30')" = 1 ] && echo 1 || echo 0)"
bad --step over 31;                 ok "BAD_ARGS: --step over 31 (1..30 steps)" "$([ $RC = 2 ] && [ "$(has "$OUT" '1 to 30')" = 1 ] && echo 1 || echo 0)"
bad --step over 20 --step into 11;  ok "BAD_ARGS: the steps of one run add up to more than 30" "$([ $RC = 2 ] && [ "$(has "$OUT" '30')" = 1 ] && echo 1 || echo 0)"
bad --status --step over;           ok "BAD_ARGS: --status cannot be combined with --step" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --eval "";                      ok "BAD_ARGS: --eval needs an expression" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --eval "x = 5";                 ok "BAD_ARGS: --eval rejects an assignment (read-only)" "$([ $RC = 2 ] && [ "$(has "$OUT" 'read-only')" = 1 ] && echo 1 || echo 0)"
bad --eval "x += 1";                ok "BAD_ARGS: --eval rejects a compound assignment" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --eval "i++";                   ok "BAD_ARGS: --eval rejects ++" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --eval "--i";                   ok "BAD_ARGS: --eval rejects --" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --eval "a; b";                  ok "BAD_ARGS: --eval rejects a semicolon (one expression only)" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --eval "$(printf 'x%.0s' $(seq 1 201))"; ok "BAD_ARGS: --eval rejects an expression longer than 200 characters" "$([ $RC = 2 ] && echo 1 || echo 0)"
OUT="$(bash "$SCRIPT" "$T/none" 2>&1)"; RC=$?
ok "BAD_ARGS: missing solution dir" "$([ $RC = 2 ] && echo 1 || echo 0)"
ok "BAD_ARGS: no flag is written" "$([ ! -f "$D/trigger_vs.flag" ] && echo 1 || echo 0)"
OUT="$(bash "$SCRIPT" "$T" --changes 2>&1)"; RC=$?   # $T は git のリポジトリではない
ok "--changes in a folder that is not a git repository -> BAD_ARGS (use --break)" "$([ $RC = 2 ] && [ "$(has "$OUT" 'not a git repository')" = 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- vs_once.sh: 疑似ウォッチャー
fake_watcher() {
    local handler="$1"
    while true; do
        if [ -f "$D/trigger_vs.flag" ]; then
            cp "$D/trigger_vs.flag" "$D/flag.full"; grep -v "^# run=" "$D/trigger_vs.flag" > "$D/flag.copy"
            rm -f "$D/trigger_vs.flag"
            sleep 1
            "$handler"
        fi
        sleep 0.3
    done
}
write_id() { mkdir -p "$D/.claude-logs"; printf 'run=%s\r\nwatcher=fake\r\n' "$(sed -n 's/^# run=//p' "$D/flag.full")" > "$D/.claude-logs/run_id.txt"; }
h_ok()    { { printf '%sSOLUTION: x%s\nOPEN: yes%s\nINSTANCES: 1%s\nDEBUG_MODE: design%s\nDIRTY: C:\\p\\a.cpp%s\nDIRTY_COUNT: 1%s\n' "$BOM" "$CR" "$CR" "$CR" "$CR" "$CR" "$CR"; } > "$D/vs_output.txt"; write_id; printf OK > "$D/vs_result.txt"; }
h_fail()  { { printf '%sMULTIPLE_INSTANCES: 2 Visual Studio windows have this solution open.%s\n' "$BOM" "$CR"; } > "$D/vs_error.log"; write_id; printf FAILED > "$D/vs_result.txt"; }
h_env()   { { printf '%s[ENVIRONMENT ERROR - not a source code problem]%s\nVisual Studio (devenv.exe) was not found (vswhere.exe).%s\n' "$BOM" "$CR" "$CR"; } > "$D/vs_error.log"; write_id; printf FAILED > "$D/vs_result.txt"; }
h_cap()   { { printf '%sSOLUTION: x%s\nDEBUG_MODE: break%s\nSTOPPED: Foo::Bar at C:\\p\\a.cpp:12%s\nOUTPUT: file=vs_debug_output.txt lines=100 total=100%s\nDIRTY_COUNT: 0%s\n' "$BOM" "$CR" "$CR" "$CR" "$CR" "$CR"; } > "$D/vs_output.txt"; for i in $(seq 1 100); do printf 'debug line %s%s\n' "$i" "$CR"; done > "$D/vs_debug_output.txt"; write_id; printf OK > "$D/vs_result.txt"; }
h_steps() { { printf '%sSTEP 1: C:\\p\\a.cpp:10  int x = f(a);%s\nCHANGED: a = 1 -> 2%s\n' "$BOM" "$CR" "$CR"; for i in $(seq 2 60); do printf 'STEP %s: C:\\p\\a.cpp:%s  line %s%s\nCHANGED: n = %s -> %s%s\n' "$i" "$((9+i))" "$i" "$CR" "$((i-1))" "$i" "$CR"; done; printf 'STEP_DONE: 60/60%s\nDEBUG_MODE: break%s\n' "$CR" "$CR"; } > "$D/vs_output.txt"; write_id; printf OK > "$D/vs_result.txt"; }
h_stack() { { printf '%sSTACK: #0 Lib::Run at z:\\nightly\\LibA\\a.cpp:9 [module=LibA.dll]%s\nSTACK: #1 App::Go at C:\\p\\a.cpp:12 [module=App.exe]%s\nSOLUTION: C:\\p\\App.slnx%s\nDEBUG_MODE: break%s\n' "$BOM" "$CR" "$CR" "$CR" "$CR"; } > "$D/vs_output.txt"; write_id; printf OK > "$D/vs_result.txt"; }
h_native() { { printf '%sSTACK: #0 Lib::Run [module=C:\\p\\x64\\Debug\\LibA.dll]%s\nSTACK: #1 Dlg::Go [module=C:\\p\\x64\\Debug\\App.exe]%s\nSOLUTION: C:\\p\\App.slnx%s\nDEBUG_MODE: break%s\nSTOPPED: Lib::Run at z:\\nightly\\LibA\\a.cpp:9%s\n' "$BOM" "$CR" "$CR" "$CR" "$CR" "$CR"; } > "$D/vs_output.txt"; write_id; printf OK > "$D/vs_result.txt"; }
h_native_exc() { { printf '%sSTACK: #0 ExtDll_Sum [module=C:\\p\\x64\\Debug\\ExtDll.dll]%s\nSOLUTION: C:\\p\\App.slnx%s\nDEBUG_MODE: break%s\nLAST_OUTPUT: Exception thrown at 0x00007FFB1ACD16D2 (ExtDll.dll) in App.exe: 0xC0000005: Access violation reading location 0x0000000000000000.%s\n' "$BOM" "$CR" "$CR" "$CR" "$CR"; } > "$D/vs_output.txt"; write_id; printf OK > "$D/vs_result.txt"; }
h_never() { :; }
h_weird() { write_id; printf WEIRD > "$D/vs_result.txt"; }
run_case() {
    local handler="$1"; shift
    fake_watcher "$handler" & local W=$!
    OUT="$(bash "$SCRIPT" "$D" "$@")"; RC=$?
    kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
    rm -f "$D"/vs_* "$D"/trigger_* 2>/dev/null
}

run_case h_ok
ok "default: flag = open + status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'open\nstatus')" ] && echo 1 || echo 0)"
ok "OK: rc=0, first line OK, facts shown without BOM / CR" "$([ $RC = 0 ] && [ "$(head -1 <<<"$OUT")" = OK ] && [ "$(has "$OUT" 'DIRTY: C:\p\a.cpp')" = 1 ] && ! grep -q "$BOM\|$CR" <<<"$OUT" && echo 1 || echo 0)"
run_case h_ok --status
ok "--status: flag = status only (does not open VS)" "$([ "$(cat "$D/flag.copy")" = "status" ] && echo 1 || echo 0)"
run_case h_ok --break src/a.cpp:12 --break "dir with space/b.cpp:7"
ok "--break: open, break lines (the path may contain spaces), status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'open\nbreak src/a.cpp:12\nbreak dir with space/b.cpp:7\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --clear
ok "--clear: open, clear, status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'open\nclear\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --break src/a.cpp:12 --debug
ok "--debug comes after the breakpoints, before the final status; no debug without --debug" "$([ "$(cat "$D/flag.copy")" = "$(printf 'open\nbreak src/a.cpp:12\ndebug\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --break src/a.cpp:12 --debug --no-wait
ok "--debug --no-wait: the debug line carries nowait (the watcher returns without waiting for a break)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'open\nbreak src/a.cpp:12\ndebug nowait\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --frame 2 --inspect
ok "--frame 2 --inspect: frame comes before inspect (read-only run: no open)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'frame 2\ninspect\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --frame 3 --eval "x"
ok "--frame 3 --eval: frame comes before eval" "$([ "$(cat "$D/flag.copy")" = "$(printf 'frame 3\neval x\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --frame 007 --inspect
ok "--frame 007: leading zeros are read as decimal (7)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'frame 7\ninspect\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --frame 0000000000000000000000007 --inspect
ok "--frame with many leading zeros is still 7 (digit count is checked after the zeros are removed)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'frame 7\ninspect\nstatus')" ] && echo 1 || echo 0)"
run_case h_stack --inspect
ok "--inspect: STACK lines get the owner mark, the module moves to the end, OWNER and BOUNDARY follow; no BOM / CR" "$([ "$(has "$OUT" 'STACK: #0 [ext] Lib::Run at z:\nightly\LibA\a.cpp:9 (LibA.dll)')" = 1 ] && [ "$(has "$OUT" 'STACK: #1 [ours] App::Go at C:\p\a.cpp:12 (App.exe)')" = 1 ] && [ "$(has "$OUT" 'OWNER: top=ext (frame #0)')" = 1 ] && [ "$(has "$OUT" 'BOUNDARY: #1 ours -> ext #0')" = 1 ] && ! grep -q "$BOM\|$CR" <<<"$OUT" && echo 1 || echo 0)"
mkdir -p "$D/App"; printf '<Project/>\n' > "$D/App/App.vcxproj"; printf 'void Dlg::Go()\n{\n}\n' > "$D/App/Dlg.cpp"
run_case h_native --inspect
ok "native frames (no file in STACK): the STOPPED file makes #0 ext, and our solution folder (--solution-root) shows that Dlg::Go is defined in our sources -> ours, boundary found" "$([ "$(has "$OUT" 'STACK: #0 [ext] Lib::Run at z:\nightly\LibA\a.cpp:9')" = 1 ] && [ "$(has "$OUT" 'STACK: #1 [ours] Dlg::Go')" = 1 ] && [ "$(has "$OUT" 'BOUNDARY: #1 ours -> ext #0')" = 1 ] && echo 1 || echo 0)"
rm -rf "$D/App"
run_case h_native_exc --inspect
ok "native exception: the host's LAST_OUTPUT: line becomes EXCEPTION: (before STACK:), and LAST_OUTPUT: is not shown" "$([ "$(has "$OUT" 'EXCEPTION: (debug output; may be stale) Exception thrown at 0x00007FFB1ACD16D2')" = 1 ] && [ "$(has "$OUT" 'LAST_OUTPUT:')" = 0 ] && [ "$(has "$OUT" 'STACK: #0')" = 1 ] && echo 1 || echo 0)"
FB2="$T/fakebin2"; mkdir -p "$FB2"; printf '#!/bin/sh\nexit 1\n' > "$FB2/python3"; chmod +x "$FB2/python3"
OLDPATH2="$PATH"; PATH="$FB2:$PATH"
run_case h_native_exc --inspect
PATH="$OLDPATH2"
ok "stack_owner.py failing: the raw LAST_OUTPUT: line is not shown (it is not an exception verdict, and the skill does not document it), the rest is" "$([ "$(has "$OUT" 'LAST_OUTPUT:')" = 0 ] && [ "$(has "$OUT" 'STACK: #0 ExtDll_Sum')" = 1 ] && [ "$(head -1 <<<"$OUT")" = OK ] && echo 1 || echo 0)"
FB="$T/fakebin"; mkdir -p "$FB"; printf '#!/bin/sh\nexit 1\n' > "$FB/python3"; chmod +x "$FB/python3"
OLDPATH="$PATH"; PATH="$FB:$PATH"
run_case h_stack --inspect
PATH="$OLDPATH"
ok "stack_owner.py failing (no python3): the plain output is still shown (STACK / SOLUTION lines are not lost)" "$([ "$(has "$OUT" 'STACK: #0 Lib::Run')" = 1 ] && [ "$(has "$OUT" 'SOLUTION: C:\p\App.slnx')" = 1 ] && [ "$(head -1 <<<"$OUT")" = OK ] && echo 1 || echo 0)"
run_case h_ok --break src/a.cpp:12
ok "no --debug: the flag has no debug line (placing breakpoints never runs the app)" "$(grep -q '^debug' "$D/flag.copy" && echo 0 || echo 1)"
# --output / --inspect (v2.99.0): 読み取りだけのときは、VS を開かない (--status と同じ)。動作のモードと併用すると、open から始める
run_case h_ok --output
ok "--output alone: read-only (no open), default 200 lines, then status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'output 200\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --output 50
ok "--output 50: output 50 (read-only, no open)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'output 50\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --output 007
ok "--output 007: leading zeros are read as decimal (7)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'output 7\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --inspect
ok "--inspect alone: read-only (no open): inspect, status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'inspect\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --output 100 --inspect
ok "--inspect + --output: inspect first, then output, then status (no open)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'inspect\noutput 100\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --break src/a.cpp:12 --debug --inspect --output 80
ok "with --debug: open, break, debug, inspect, output, status (the capture is taken after the app stops or runs)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'open\nbreak src/a.cpp:12\ndebug\ninspect\noutput 80\nstatus')" ] && echo 1 || echo 0)"
run_case h_cap --output 100
ok "the capture file is shown after the facts: header (last 60 of 100), then the last lines, CR removed" "$([ "$(has "$OUT" '=== VS debug output (last 60 of 100 captured lines')" = 1 ] && [ "$(has "$OUT" 'debug line 100')" = 1 ] && [ "$(has "$OUT" 'debug line 41')" = 1 ] && [ "$(has "$OUT" 'debug line 40')" = 0 ] && ! grep -q "$CR" <<<"$OUT" && echo 1 || echo 0)"
ok "the facts (STOPPED: / OUTPUT:) are shown before the capture" "$([ "$(has "$OUT" 'STOPPED: Foo::Bar')" = 1 ] && [ "$(has "$OUT" 'OUTPUT: file=vs_debug_output.txt')" = 1 ] && echo 1 || echo 0)"
run_case h_ok
ok "no capture file -> no capture block (the default run is unchanged)" "$([ "$(has "$OUT" 'VS debug output')" = 0 ] && echo 1 || echo 0)"
# --step / --continue / --pause / --eval (v2.101.0): 読み取りだけのときは、VS を開かない。実行系の操作は、指定した順
run_case h_ok --step over
ok "--step over: step over 1, then status (read-only: no open)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'step over 1\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --step into 3
ok "--step into 3: step into 3 (no open)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'step into 3\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --step out
ok "--step out: step out 1" "$([ "$(cat "$D/flag.copy")" = "$(printf 'step out 1\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --continue
ok "--continue: continue (F5), then status (no open)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'continue\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --pause
ok "--pause: pause, then status (no open)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'pause\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --eval "i + 1"
ok "--eval: the expression is kept as one flag line (spaces included)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'eval i + 1\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --eval "a == b"
ok "--eval: a comparison (==) is not an assignment" "$([ "$(cat "$D/flag.copy")" = "$(printf 'eval a == b\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --eval "a <= b && c != d"
ok "--eval: <= and != are not assignments" "$([ "$(cat "$D/flag.copy")" = "$(printf 'eval a <= b && c != d\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --step over 2 --eval "i" --step into
ok "the run operations keep the order given on the command line" "$([ "$(cat "$D/flag.copy")" = "$(printf 'step over 2\neval i\nstep into 1\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --break src/a.cpp:3 --debug --step over 2 --inspect --output 50
ok "with --debug: open, break, debug, step, inspect, output, status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'open\nbreak src/a.cpp:3\ndebug\nstep over 2\ninspect\noutput 50\nstatus')" ] && echo 1 || echo 0)"
run_case h_steps --step over 30
ok "a 30-step trace (about 120 lines) is shown in full (no truncation of the trace)" "$([ "$(has "$OUT" 'STEP 60:')" = 1 ] && [ "$(has "$OUT" 'STEP_DONE: 60/60')" = 1 ] && [ "$(has "$OUT" 'lines total')" = 0 ] && echo 1 || echo 0)"
# --changes / --reload: ソリューションのフォルダが git のリポジトリのとき
D0="$D"
G2="$T/repo2"; mkdir -p "$G2"
git -c core.autocrlf=false -C "$G2" init -q
printf 'int main()\n{\n    return 0;\n}\n' > "$G2/a.cpp"
git -c user.name=t -c user.email=t@example.com -C "$G2" add -A >/dev/null; git -c user.name=t -c user.email=t@example.com -C "$G2" commit -qm i
printf 'int main()\n{\n    int x = 1;\n    return x;\n}\n' > "$G2/a.cpp"
printf 'int h() { return 1; }\n' > "$G2/n.cpp"
D="$G2"
run_case h_ok --changes --reload
ok "--changes --reload: open, reload (changed + new files), clear, break a.cpp:3, status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'open\nreload a.cpp\nreload n.cpp\nclear\nbreak a.cpp:3\nstatus')" ] && echo 1 || echo 0)"
ok "--changes: NEW_FILE is reported to Claude (a line cannot be chosen automatically)" "$([ "$(has "$OUT" 'NEW_FILE: n.cpp')" = 1 ] && echo 1 || echo 0)"
D="$D0"

run_case h_fail
ok "FAILED: rc=1, the reason is shown" "$([ $RC = 1 ] && [ "$(head -1 <<<"$OUT")" = FAILED ] && [ "$(has "$OUT" 'MULTIPLE_INSTANCES: 2')" = 1 ] && echo 1 || echo 0)"
run_case h_env
ok "ENV_ERROR: rc=4" "$([ $RC = 4 ] && [ "$(head -1 <<<"$OUT")" = ENV_ERROR ] && [ "$(has "$OUT" 'devenv.exe')" = 1 ] && echo 1 || echo 0)"
run_case h_weird
ok "unexpected marker -> ENV_ERROR rc=4" "$([ $RC = 4 ] && [ "$(has "$OUT" "unexpected vs_result.txt: 'WEIRD'")" = 1 ] && echo 1 || echo 0)"
run_case h_never --timeout 4
ok "TIMEOUT: flag picked up but no marker -> rc=5" "$([ $RC = 5 ] && [ "$(head -1 <<<"$OUT")" = TIMEOUT ] && echo 1 || echo 0)"

# 古い結果は、フラグを置く前に消される
printf OK > "$D/vs_result.txt"; printf 'old output\n' > "$D/vs_output.txt"; printf 'old capture\n' > "$D/vs_debug_output.txt"
fake_watcher h_ok & W=$!
OUT="$(bash "$SCRIPT" "$D")"; RC=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null; rm -f "$D"/vs_* "$D"/trigger_*
ok "stale result removed before the wait (old output and the old capture are not shown)" "$([ $RC = 0 ] && [ "$(has "$OUT" 'old output')" = 0 ] && [ "$(has "$OUT" 'old capture')" = 0 ] && echo 1 || echo 0)"

echo "=== WATCHER_NOT_RUNNING (expect rc=3 after ~15s)"
out="$(bash "$SCRIPT" "$D" --timeout 30 --status)"; rc=$?
ok "WATCHER_NOT_RUNNING: rc=3, the flag is withdrawn" "$([ $rc = 3 ] && [ "$(head -1 <<<"$out")" = WATCHER_NOT_RUNNING ] && [ ! -f "$D/trigger_vs.flag" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 静的な検査 (ホスト側・文書)
ok "vs-ide.ps1: UTF-8 BOM (Windows PowerShell 5.1 が日本語を読む)" "$([ "$(head -c 3 "$PS1")" = "$BOM" ] && echo 1 || echo 0)"
ok "vs-ide.ps1: every operation the WSL side can send is handled (open status reload clear break debug)" "$(for op in open status reload clear break debug; do grep -q "'$op'" "$PS1" || echo bad; done | grep -q bad && echo 0 || echo 1)"
ok "vs-ide.ps1: finds VS by the Running Object Table and the solution path (not the first VS)" "$(grep -q 'GetRunningObjectTable' "$PS1" && grep -q 'Solution.FullName' "$PS1" && grep -q 'MULTIPLE_INSTANCES' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: breakpoints are tagged, and clear deletes only the tagged ones" "$(grep -q 'claude-vs-debug' "$PS1" && grep -q '\$b.Tag' "$PS1" && grep -q '\.Delete()' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: debug starts only from design mode (DTE.Debugger.Go)" "$(grep -q "Debugger.Go" "$PS1" && grep -q "mode -ne 'design'" "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: debug waits for the breakpoint hit (run -> break), and status reports STOPPED at break" "$(grep -q 'VsBreakWaitSec' "$PS1" && grep -q "while ((Get-VsModeName \$dte) -eq 'run'" "$PS1" && grep -q "if (\$mode -eq 'break') { \$lines += (Get-VsLocation" "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: dbgDebugMode mapping is 1=design 2=break 3=run (v2.90.2: it was swapped)" "$(grep -q '1 { "design" } 2 { "break" } 3 { "run" }' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: the path is validated (no .., stays under the solution folder)" "$(grep -q 'StartsWith(\$SolutionDir' "$PS1" && grep -q '\\\.\\\.' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: the VS version is not hard-coded (no 'VisualStudio.DTE.17.0')" "$(grep -q 'VisualStudio.DTE.17' "$PS1" && echo 0 || echo 1)"
ok "vs-ide.ps1: the inspect and output operations are handled (v2.99.0)" "$(grep -q "'inspect'" "$PS1" && grep -q "'output'" "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: output reads the Debug pane through Windows.Item(<Output window kind>).Object (not DTE2 ToolWindows, which PowerShell cannot see), by ENUMERATING the panes and matching the GUID (the name is localized; Item(<index>) fails)" "$(grep -q 'FC076020-078A-11D1-A7DF-00A0C9110051' "$PS1" && grep -q '34E76E81-EE4A-11D0-AE2E-00A0C90FFFC3' "$PS1" && grep -q 'ReadOutputPane' "$PS1" && grep -q 'IEnumerable' "$PS1" && grep -q 'OutputWindowPanes' "$PS1" && grep -q 'TextDocument' "$PS1" && ! grep -v -E '^ *(#|//)' "$PS1" | grep -q 'ToolWindows' && echo 1 || echo 0)"
ok "vs-ide.ps1: OUTPUT_UNAVAILABLE lists the panes that were found (name=guid), so a wrong GUID can be fixed from the real values" "$(grep -q 'OUTPUT_UNAVAILABLE' "$PS1" && grep -q 'Panes: ' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: debug waits while the mode is design OR unknown (right after Go the mode can be unknown), then for the breakpoint hit" "$(grep -q -- "-in @('design', 'unknown')" "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: after the breakpoint wait, debug waits a few more seconds while the mode is still unknown (a stop at an exception can read unknown for a moment; real machine 2026-11-19)" "$(grep -q 'VsUnknownWaitSec' "$PS1" && grep -q "(Get-VsModeName \$dte) -eq 'unknown'" "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: the EXCEPTION: line carries the exception type as well as the message" "$(grep -q 'EXCEPTION: ' "$PS1" && grep -q '\$ex.Type' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: the VS lookup for reload / clear / break / debug / inspect / output is retried a few times when 0 found (right after the app starts, VS can briefly not answer)" "$(grep -q 'VsTargetRetry' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: output is read-only on VS (never clears the pane) and bounded (lines and characters)" "$(! grep -q '\.Clear()' "$PS1" && grep -q 'VsOutputMaxLines' "$PS1" && grep -q 'VsOutputMaxChars' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: output says so when the Debug pane does not exist yet (OUTPUT_UNAVAILABLE), instead of failing" "$(grep -q 'OUTPUT_UNAVAILABLE' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: inspect reads the stack, the locals and the exception, only in break mode (INSPECT_SKIP otherwise)" "$(grep -q 'StackFrames' "$PS1" && grep -q 'Locals' "$PS1" && grep -q '\$exception' "$PS1" && grep -q 'INSPECT_SKIP' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: inspect / output need exactly one VS that has the solution open (never start VS)" "$(grep -q "{ \$_ -in @('reload', 'clear', 'break', 'debug', 'inspect', 'output', 'step', 'continue', 'pause', 'eval', 'frame') }" "$PS1" && echo 1 || echo 0)"
ok "watch_and_build.ps1: defines VsDebugOutputFile and removes the old capture with the other vs_ files" "$(grep -q 'VsDebugOutputFile' "$ROOT/host-tools/watch_and_build.ps1" && grep -q 'vs_debug_output.txt' "$ROOT/host-tools/watch_and_build.ps1" && echo 1 || echo 0)"
ok "watch_and_build.ps1: loads vs-ide and handles trigger_vs.flag" "$(grep -q '"vs-ide"' "$ROOT/host-tools/watch_and_build.ps1" && grep -q 'VsTriggerFile' "$ROOT/host-tools/watch_and_build.ps1" && grep -q 'Invoke-VsFlag' "$ROOT/host-tools/watch_and_build.ps1" && echo 1 || echo 0)"
HV="$(tr -d '\r\n' < "$ROOT/host-tools/HOST_VERSION")"
ok "HOST_VERSION is 2.99.0 or later (--output / --inspect need the new watcher)" "$([ "$(printf '%s\n%s\n' 2.99.0 "$HV" | sort -V | head -n 1)" = 2.99.0 ] && echo 1 || echo 0)"
ok "host-tools/README.md: documents trigger_vs.flag, vs_result.txt, and the operations" "$(grep -q 'trigger_vs.flag' "$ROOT/host-tools/README.md" && grep -q 'vs_result.txt' "$ROOT/host-tools/README.md" && grep -q 'MULTIPLE_INSTANCES' "$ROOT/host-tools/README.md" && echo 1 || echo 0)"
ok "SKILL.md: frontmatter name + triggers (デバッグを実行して / ブレークポイント)" "$(sed -n 1,4p "$SKILL" | grep -q '^name: vs-debug' && sed -n 1,4p "$SKILL" | grep -q 'デバッグを実行して' && sed -n 1,4p "$SKILL" | grep -q 'ブレークポイントを置いて' && echo 1 || echo 0)"
ok "SKILL.md: debug runs only when the user asks; breakpoints alone never run the app" "$(grep -q 'ユーザーが、実行を求めたときだけ' "$SKILL" && grep -q 'ブレークポイントを置くだけでは、実行しない' "$SKILL" && echo 1 || echo 0)"
ok "SKILL.md: conflict rules (pre-edit --status, DIRTY -> do not edit and ask, no edit while debugging, INSTANCES)" "$(grep -q -- '--status' "$SKILL" && grep -q 'DIRTY:' "$SKILL" && grep -q '編集しない' "$SKILL" && grep -q 'INSTANCES: 2' "$SKILL" && grep -q 'デバッグ中は、ビルド・テスト・ソースの編集をしない' "$SKILL" && echo 1 || echo 0)"
ok "SKILL.md: breakpoints are placed last; only the tool's own breakpoints are cleared" "$(grep -q '最後に置く' "$SKILL" && grep -q 'このツールが置いた' "$SKILL" && echo 1 || echo 0)"
ok "SKILL.md: documents --output and --inspect (read-only, no VS start, what they return, and the privacy note)" "$(grep -q -- '--output' "$SKILL" && grep -q -- '--inspect' "$SKILL" && grep -q 'vs_debug_output.txt' "$SKILL" && grep -q '個人情報' "$SKILL" && echo 1 || echo 0)"
ok "host-tools/README.md: documents the inspect and output operations and vs_debug_output.txt" "$(grep -q 'vs_debug_output.txt' "$ROOT/host-tools/README.md" && grep -q '`inspect`' "$ROOT/host-tools/README.md" && grep -q '`output' "$ROOT/host-tools/README.md" && echo 1 || echo 0)"
ok "new_solution.py: the generated .gitignore lists vs_debug_output.txt" "$(grep -q 'vs_debug_output.txt' "$ROOT/skills/new-solution/scripts/new_solution.py" && echo 1 || echo 0)"
ok "SKILL.md: states when the output can be read (running, stopped, and after the app ended until the next debug start; --inspect only while stopped)" "$(grep -q '終了したあと' "$SKILL" && grep -q '次のデバッグを始める前' "$SKILL" && grep -q '止まっているときだけ' "$SKILL" && echo 1 || echo 0)"
ok "vs-ide.ps1: the step / continue / pause / eval operations are handled (v2.101.0)" "$(for op in step continue pause eval; do grep -q "'$op'" "$PS1" || echo bad; done | grep -q bad && echo 0 || echo 1)"
ok "vs-ide.ps1: steps and Go / Break do not block (WaitForBreakOrEnd = false) and poll the mode with a timeout (a modal dialog must not freeze the watcher)" "$(grep -q 'StepOver($false)' "$PS1" && grep -q 'StepInto($false)' "$PS1" && grep -q 'StepOut($false)' "$PS1" && grep -q 'Break($false)' "$PS1" && grep -q 'STEP_TIMEOUT' "$PS1" && grep -q 'STEP_END' "$PS1" && grep -q 'VsStepWaitSec' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: a run is capped at 30 steps (VsStepMax), and step / continue / pause / eval need the right mode (break / run)" "$(grep -q 'VsStepMax' "$PS1" && grep -q 'not in break mode' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: eval is read-only: it rejects an assignment and ++ / -- again on the host (EVAL_REJECTED), and reads the value with GetExpression" "$(grep -q 'EVAL_REJECTED' "$PS1" && grep -q 'GetExpression' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: no stop operation (stopping is the user's: Shift+F5). No Debugger.Stop / TerminateAll / DetachAll / SetNextStatement / ExecuteStatement" "$(! grep -v -E '^ *(#|//)' "$PS1" | grep -q -E 'Debugger\.(Stop|TerminateAll|DetachAll|SetNextStatement|ExecuteStatement)' && echo 1 || echo 0)"
ok "vs-ide.ps1: each step reports STEP n: <file>:<line> <source line> and the CHANGED: locals" "$(grep -q 'STEP ' "$PS1" && grep -q 'CHANGED: ' "$PS1" && grep -q 'STEP_DONE' "$PS1" && echo 1 || echo 0)"
ok "HOST_VERSION is 2.101.0 or later (--step / --eval need the new watcher)" "$([ "$(printf '%s\n%s\n' 2.101.0 "$(tr -d '\r\n' < "$ROOT/host-tools/HOST_VERSION")" | sort -V | head -n 1)" = "2.101.0" ] && echo 1 || echo 0)"
ok "SKILL.md: the step-through bug hunt (user asks only, 30 steps, 3 visits to one place, read-only eval, no function calls without consent, no editing while debugging, stop is the user's)" "$(grep -q -- '--step' "$SKILL" && grep -q -- '--eval' "$SKILL" && grep -q -- '--continue' "$SKILL" && grep -q '30 歩' "$SKILL" && grep -q '3 回' "$SKILL" && grep -q '関数の呼び出し' "$SKILL" && grep -q 'ユーザーが、求めたとき' "$SKILL" && echo 1 || echo 0)"
ok "host-tools/README.md: documents the step / continue / pause / eval operations, and that there is no stop" "$(grep -q '`step ' "$ROOT/host-tools/README.md" && grep -q '`eval ' "$ROOT/host-tools/README.md" && grep -q '`continue`' "$ROOT/host-tools/README.md" && echo 1 || echo 0)"
ok "SKILL.md uses <Skill群> with the path note (skill_paths_test)" "$(grep -q 'パスの書き方' "$SKILL" && echo 1 || echo 0)"

# v2.104.1: ステップ実行の改善 (b)(c)(d)。PowerShell は WSL で動かせないので、形を静的に確かめる (実機は TEST-PLAN 2-67)
ok "vs-ide.ps1 (b): a value VS cannot read (IsValidValue false, e.g. an optimized-away variable) is shown short, not as VS's long message" "$(grep -q 'function Format-VsValue' "$PS1" && grep -q 'IsValidValue' "$PS1" && grep -q '(unavailable)' "$PS1" && grep -q 'Format-VsValue \$e' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1 (c): values are read in decimal (HexDisplayMode off while reading, then restored to what the user had)" "$(grep -q 'function Use-VsDecimal' "$PS1" && grep -q 'function Restore-VsHex' "$PS1" && grep -q 'HexDisplayMode' "$PS1" && [ "$(grep -c 'Use-VsDecimal \$dte' "$PS1")" -ge 3 ] && [ "$(grep -c 'Restore-VsHex \$dte' "$PS1")" -ge 3 ] && echo 1 || echo 0)"
ok "vs-ide.ps1 (d): STOPPED: takes the place from the stack frame (FileName / LineNumber) and retries a moment when it is not ready" "$(grep -q 'VsLocationWaitSec' "$PS1" && grep -q '\$frame.FileName' "$PS1" && grep -q '\$frame.LineNumber' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: still has the UTF-8 BOM after the edit" "$([ "$(head -c 3 "$PS1")" = "$BOM" ] && echo 1 || echo 0)"

# v2.105.1: 読めない変数 ((unavailable)) の型名が空 (`()`) になる点 (実機 2026-11-25、TEST-PLAN 2-67 の IM4 の観察)。型が空のときは、式から補い、それでも空なら、空の括弧を出さない
ok "vs-ide.ps1 (v2.105.1): the type of a local comes from Get-VsTypeName (falls back to GetExpression of the name when e.Type is empty), and no empty () is printed" "$(grep -q 'function Get-VsTypeName' "$PS1" && grep -q 'Get-VsTypeName \$dte \$e' "$PS1" && sed -n '/function Get-VsTypeName/,/^}/p' "$PS1" | grep -q 'GetExpression' && ! grep -q '(\$(\$e.Type))' "$PS1" && echo 1 || echo 0)"

# v2.104.2: --debug --inspect で、起動が遅く、20 秒で break に届かなかったとき、inspect の前に、追加で待つ ((a)。実機 2026-11-24 に再現)
ok "vs-ide.ps1 (a): inspect right after debug waits extra for break when the app is still running (VsInspectExtraWaitSec), only when debug was started in the same run" "$(grep -q 'VsInspectExtraWaitSec' "$PS1" && grep -q 'debugStarted' "$PS1" && [ "$(grep -c 'debugStarted' "$PS1")" -ge 3 ] && echo 1 || echo 0)"
ok "vs-ide.ps1 (a): the extra wait is bounded (a while loop with a deadline, not an endless wait)" "$(grep -A4 'VsInspectExtraWaitSec)' "$PS1" | grep -q 'Get-Date' && echo 1 || echo 0)"

ok "vs-ide.ps1 (a): the extra wait also waits through 'unknown' (the mode reads unknown for a moment just before break; 実機 2026-11-24 v2.104.2)" "$(grep -A4 'VsInspectExtraWaitSec)' "$PS1" | grep -q "in @('run', 'unknown')" && echo 1 || echo 0)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
