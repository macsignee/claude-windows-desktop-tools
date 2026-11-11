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
bad --timeout abc;                  ok "BAD_ARGS: bad --timeout" "$([ $RC = 2 ] && echo 1 || echo 0)"
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
run_case h_ok --break src/a.cpp:12
ok "no --debug: the flag has no debug line (placing breakpoints never runs the app)" "$(grep -q '^debug' "$D/flag.copy" && echo 0 || echo 1)"
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
printf OK > "$D/vs_result.txt"; printf 'old output\n' > "$D/vs_output.txt"
fake_watcher h_ok & W=$!
OUT="$(bash "$SCRIPT" "$D")"; RC=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null; rm -f "$D"/vs_* "$D"/trigger_*
ok "stale result removed before the wait (old output not shown)" "$([ $RC = 0 ] && [ "$(has "$OUT" 'old output')" = 0 ] && echo 1 || echo 0)"

echo "=== WATCHER_NOT_RUNNING (expect rc=3 after ~15s)"
out="$(bash "$SCRIPT" "$D" --timeout 30 --status)"; rc=$?
ok "WATCHER_NOT_RUNNING: rc=3, the flag is withdrawn" "$([ $rc = 3 ] && [ "$(head -1 <<<"$out")" = WATCHER_NOT_RUNNING ] && [ ! -f "$D/trigger_vs.flag" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 静的な検査 (ホスト側・文書)
ok "vs-ide.ps1: UTF-8 BOM (Windows PowerShell 5.1 が日本語を読む)" "$([ "$(head -c 3 "$PS1")" = "$BOM" ] && echo 1 || echo 0)"
ok "vs-ide.ps1: every operation the WSL side can send is handled (open status reload clear break debug)" "$(for op in open status reload clear break debug; do grep -q "'$op'" "$PS1" || echo bad; done | grep -q bad && echo 0 || echo 1)"
ok "vs-ide.ps1: finds VS by the Running Object Table and the solution path (not the first VS)" "$(grep -q 'GetRunningObjectTable' "$PS1" && grep -q 'Solution.FullName' "$PS1" && grep -q 'MULTIPLE_INSTANCES' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: breakpoints are tagged, and clear deletes only the tagged ones" "$(grep -q 'claude-vs-debug' "$PS1" && grep -q '\$b.Tag' "$PS1" && grep -q '\.Delete()' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: debug starts only from design mode (DTE.Debugger.Go)" "$(grep -q "Debugger.Go" "$PS1" && grep -q "mode -ne 'design'" "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: the path is validated (no .., stays under the solution folder)" "$(grep -q 'StartsWith(\$SolutionDir' "$PS1" && grep -q '\\\.\\\.' "$PS1" && echo 1 || echo 0)"
ok "vs-ide.ps1: the VS version is not hard-coded (no 'VisualStudio.DTE.17.0')" "$(grep -q 'VisualStudio.DTE.17' "$PS1" && echo 0 || echo 1)"
ok "watch_and_build.ps1: loads vs-ide and handles trigger_vs.flag" "$(grep -q '"vs-ide"' "$ROOT/host-tools/watch_and_build.ps1" && grep -q 'VsTriggerFile' "$ROOT/host-tools/watch_and_build.ps1" && grep -q 'Invoke-VsFlag' "$ROOT/host-tools/watch_and_build.ps1" && echo 1 || echo 0)"
HV="$(tr -d '\r\n' < "$ROOT/host-tools/HOST_VERSION")"
ok "HOST_VERSION is 2.90.0 or later (the watcher change must be redistributed)" "$([ "$(printf '%s\n%s\n' 2.90.0 "$HV" | sort -V | head -n 1)" = 2.90.0 ] && echo 1 || echo 0)"
ok "host-tools/README.md: documents trigger_vs.flag, vs_result.txt, and the operations" "$(grep -q 'trigger_vs.flag' "$ROOT/host-tools/README.md" && grep -q 'vs_result.txt' "$ROOT/host-tools/README.md" && grep -q 'MULTIPLE_INSTANCES' "$ROOT/host-tools/README.md" && echo 1 || echo 0)"
ok "SKILL.md: frontmatter name + triggers (デバッグを実行して / ブレークポイント)" "$(sed -n 1,4p "$SKILL" | grep -q '^name: vs-debug' && sed -n 1,4p "$SKILL" | grep -q 'デバッグを実行して' && sed -n 1,4p "$SKILL" | grep -q 'ブレークポイントを置いて' && echo 1 || echo 0)"
ok "SKILL.md: debug runs only when the user asks; breakpoints alone never run the app" "$(grep -q 'ユーザーが、実行を求めたときだけ' "$SKILL" && grep -q 'ブレークポイントを置くだけでは、実行しない' "$SKILL" && echo 1 || echo 0)"
ok "SKILL.md: conflict rules (pre-edit --status, DIRTY -> do not edit and ask, no edit while debugging, INSTANCES)" "$(grep -q -- '--status' "$SKILL" && grep -q 'DIRTY:' "$SKILL" && grep -q '編集しない' "$SKILL" && grep -q 'INSTANCES: 2' "$SKILL" && grep -q 'デバッグ中は、ビルド・テスト・ソースの編集をしない' "$SKILL" && echo 1 || echo 0)"
ok "SKILL.md: breakpoints are placed last; only the tool's own breakpoints are cleared" "$(grep -q '最後に置く' "$SKILL" && grep -q 'このツールが置いた' "$SKILL" && echo 1 || echo 0)"
ok "SKILL.md uses <Skill群> with the path note (skill_paths_test)" "$(grep -q 'パスの書き方' "$SKILL" && echo 1 || echo 0)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
