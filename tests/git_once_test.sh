#!/usr/bin/env bash
# git_once_test.sh - git-remote (v2.102.0): Windows の git.exe による push / fetch を、ウォッチャーに依頼する Skill を、疑似ウォッチャーと静的な検査で確かめる。
# Windows の git・認証がなくても、フラグの中身・引数の検査 (強制 push などを、置く前に断る)・結果の分岐・文書の整合を、確認できる。
# Usage: tests/git_once_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/git-remote/scripts/git_once.sh"
SKILL="$ROOT/skills/git-remote/SKILL.md"
PS1="$ROOT/host-tools/lib/git-remote.ps1"
MAIN="$ROOT/host-tools/watch_and_build.ps1"
RULE="$ROOT/rules/git-wsl.md"
T="${TMPDIR:-/tmp}/gitonce_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
BOM=$'\xEF\xBB\xBF'; CR=$'\r'

ok "git_once.sh exists and its syntax is valid" "$([ -f "$SCRIPT" ] && bash -n "$SCRIPT" 2>/dev/null && echo 1 || echo 0)"
ok "git_once.sh is executable" "$([ -x "$SCRIPT" ] && echo 1 || echo 0)"
[ -f "$SCRIPT" ] || { echo "PASS=$pass FAIL=$fail (git_once.sh がない: 以降は、実行できない)"; exit 1; }

# ---------------------------------------------------------------- 引数の検査 (フラグを、置く前に断る)
D="$T/sln"; mkdir -p "$D"
bad() { OUT="$(bash "$SCRIPT" "$D" "$@" 2>&1)"; RC=$?; }
bad --bogus;                    ok "BAD_ARGS: unknown option -> rc=2" "$([ $RC = 2 ] && [ "$(head -1 <<<"$OUT")" = "BAD_ARGS: unknown option: --bogus" ] && echo 1 || echo 0)"
bad --push --force;             ok "BAD_ARGS: --force is refused (no force push, ever)" "$([ $RC = 2 ] && [ "$(has "$OUT" 'unknown option: --force')" = 1 ] && echo 1 || echo 0)"
bad --push --force-with-lease;  ok "BAD_ARGS: --force-with-lease is refused" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --push --delete;            ok "BAD_ARGS: --delete is refused" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --push --tags;              ok "BAD_ARGS: --tags is refused (only the current branch is pushed)" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --push --remote;            ok "BAD_ARGS: --remote needs a name" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --push --remote -x;         ok "BAD_ARGS: a remote name starting with - is refused" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --push --remote 'a b';      ok "BAD_ARGS: a remote name with a space is refused" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --push --remote 'a;b';      ok "BAD_ARGS: a remote name with ; is refused" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --push --remote 'https://x/y.git'; ok "BAD_ARGS: a URL as the remote is refused (only a configured remote name)" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --fetch 'a:b';              ok "BAD_ARGS: --fetch with a refspec-like value is refused" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --set-upstream;             ok "BAD_ARGS: --set-upstream without --push" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --allow-main;               ok "BAD_ARGS: --allow-main without --push" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --status --push;            ok "BAD_ARGS: --status cannot be combined with other modes" "$([ $RC = 2 ] && echo 1 || echo 0)"
OUT="$(bash "$SCRIPT" "$T/none" --status 2>&1)"; RC=$?
ok "BAD_ARGS: the solution dir must exist" "$([ $RC = 2 ] && echo 1 || echo 0)"
bad --timeout abc --status;     ok "BAD_ARGS: --timeout must be a number" "$([ $RC = 2 ] && echo 1 || echo 0)"
ok "a refused call leaves no flag behind" "$([ ! -e "$D/trigger_git.flag" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 疑似ウォッチャー
fake_watcher() {
    local handler="$1"
    while true; do
        if [ -f "$D/trigger_git.flag" ]; then
            cp "$D/trigger_git.flag" "$D/flag.full"; grep -v "^# run=" "$D/trigger_git.flag" > "$D/flag.copy"
            rm -f "$D/trigger_git.flag"
            sleep 1
            "$handler"
        fi
        sleep 0.3
    done
}
write_id() { mkdir -p "$D/.claude-logs"; printf 'run=%s\r\nwatcher=fake\r\nkind=git\r\n' "$(sed -n 's/^# run=//p' "$D/flag.full")" > "$D/.claude-logs/run_id.txt"; }
h_ok()    { { printf '%sBRANCH: feat-x%s\nUPSTREAM: origin/feat-x%s\nREMOTE: origin https://example.com/r.git%s\nAHEAD: 1%s\nBEHIND: 0%s\nPUSHED: origin feat-x%s\n' "$BOM" "$CR" "$CR" "$CR" "$CR" "$CR" "$CR"; } > "$D/git_output.txt"; write_id; printf OK > "$D/git_result.txt"; }
h_auth()  { { printf '%sAUTH_REQUIRED: sign in once from Visual Studio (Git > Push), then retry.%s\n' "$BOM" "$CR"; } > "$D/git_error.log"; write_id; printf AUTH_REQUIRED > "$D/git_result.txt"; }
h_rej()   { { printf '%sREJECTED: the remote has commits you do not have (non-fast-forward).%s\n' "$BOM" "$CR"; } > "$D/git_error.log"; write_id; printf REJECTED > "$D/git_result.txt"; }
h_fail()  { { printf '%sFAILED: detached HEAD%s\n' "$BOM" "$CR"; } > "$D/git_error.log"; write_id; printf FAILED > "$D/git_result.txt"; }
h_env()   { { printf '%s[ENVIRONMENT ERROR - not a source code problem]%s\ngit.exe was not found.%s\n' "$BOM" "$CR" "$CR"; } > "$D/git_error.log"; write_id; printf FAILED > "$D/git_result.txt"; }
h_weird() { write_id; printf WEIRD > "$D/git_result.txt"; }
h_never() { :; }
run_case() {
    local handler="$1"; shift
    fake_watcher "$handler" & local W=$!
    OUT="$(bash "$SCRIPT" "$D" "$@")"; RC=$?
    kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
    rm -f "$D"/git_* "$D"/trigger_* 2>/dev/null
}

run_case h_ok
ok "default (no mode): flag = status only (read-only)" "$([ "$(cat "$D/flag.copy")" = "status" ] && echo 1 || echo 0)"
ok "OK: rc=0, first line OK, facts shown without BOM / CR" "$([ $RC = 0 ] && [ "$(head -1 <<<"$OUT")" = OK ] && [ "$(has "$OUT" 'BRANCH: feat-x')" = 1 ] && ! grep -q "$BOM\|$CR" <<<"$OUT" && echo 1 || echo 0)"
run_case h_ok --status
ok "--status: flag = status" "$([ "$(cat "$D/flag.copy")" = "status" ] && echo 1 || echo 0)"
run_case h_ok --fetch
ok "--fetch: fetch (all remotes), then status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'fetch\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --fetch origin
ok "--fetch origin: fetch origin, then status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'fetch origin\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --push
ok "--push: push (the current branch), then status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'push\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --push --remote upstream2 --set-upstream
ok "--push --remote X --set-upstream: the options are on the push line" "$([ "$(cat "$D/flag.copy")" = "$(printf 'push remote=upstream2 set-upstream\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --push --allow-main
ok "--push --allow-main: allow-main is on the push line (only when the user said main is OK)" "$([ "$(cat "$D/flag.copy")" = "$(printf 'push allow-main\nstatus')" ] && echo 1 || echo 0)"
run_case h_ok --fetch --push
ok "--fetch + --push: fetch first, then push, then status" "$([ "$(cat "$D/flag.copy")" = "$(printf 'fetch\npush\nstatus')" ] && echo 1 || echo 0)"
ok "the flag never contains force / delete / refspec / URL" "$(! grep -qiE 'force|delete|tags|:|://' "$D/flag.copy" 2>/dev/null && echo 1 || echo 0)"
run_case h_ok --push
ok "the flag has the run id comment on the first line" "$(head -1 "$D/flag.full" | grep -qE '^# run=[0-9]+-[0-9]+-[0-9]+$' && echo 1 || echo 0)"

run_case h_auth --push
ok "AUTH_REQUIRED: rc=6, first line AUTH_REQUIRED, the guidance is shown" "$([ $RC = 6 ] && [ "$(head -1 <<<"$OUT")" = AUTH_REQUIRED ] && [ "$(has "$OUT" 'sign in once')" = 1 ] && echo 1 || echo 0)"
run_case h_rej --push
ok "REJECTED: rc=7, first line REJECTED" "$([ $RC = 7 ] && [ "$(head -1 <<<"$OUT")" = REJECTED ] && [ "$(has "$OUT" 'non-fast-forward')" = 1 ] && echo 1 || echo 0)"
run_case h_fail --push
ok "FAILED: rc=1, first line FAILED" "$([ $RC = 1 ] && [ "$(head -1 <<<"$OUT")" = FAILED ] && [ "$(has "$OUT" 'detached HEAD')" = 1 ] && echo 1 || echo 0)"
run_case h_env --push
ok "ENV_ERROR: rc=4 (git.exe not found)" "$([ $RC = 4 ] && [ "$(head -1 <<<"$OUT")" = ENV_ERROR ] && echo 1 || echo 0)"
run_case h_weird --status
ok "an unknown marker value -> ENV_ERROR rc=4" "$([ $RC = 4 ] && [ "$(head -1 <<<"$OUT")" = ENV_ERROR ] && echo 1 || echo 0)"

# 未起動・時間切れ
OUT="$(CLAUDE_PICKUP_WAIT=1 bash "$SCRIPT" "$D" --status 2>&1)"; RC=$?
ok "WATCHER_NOT_RUNNING: rc=3 when the flag is not picked up (and the flag is removed)" "$([ $RC = 3 ] && [ "$(head -1 <<<"$OUT")" = WATCHER_NOT_RUNNING ] && [ ! -e "$D/trigger_git.flag" ] && echo 1 || echo 0)"
mkdir -p "$D/.claude-logs"; printf 'busy\r\n' > "$D/.claude-logs/watcher_busy.txt"
OUT="$(CLAUDE_PICKUP_WAIT=1 bash "$SCRIPT" "$D" --timeout 3 --status 2>&1)"; RC=$?
ok "TIMEOUT: rc=5 when the watcher is busy and no result appears; the guidance says not to start another run" "$([ $RC = 5 ] && [ "$(head -1 <<<"$OUT")" = TIMEOUT ] && [ "$(has "$OUT" 'Do NOT start another run')" = 1 ] && echo 1 || echo 0)"
rm -rf "$D/.claude-logs" "$D"/trigger_* "$D"/git_*

# ---------------------------------------------------------------- 古い結果の取り違え (run id の照合)
fake_old() { while true; do if [ -f "$D/trigger_git.flag" ]; then rm -f "$D/trigger_git.flag"; sleep 1; mkdir -p "$D/.claude-logs"; printf 'run=OLD\r\n' > "$D/.claude-logs/run_id.txt"; printf OK > "$D/git_result.txt"; fi; sleep 0.3; done; }
fake_old & W=$!
OUT="$(CLAUDE_PICKUP_WAIT=1 bash "$SCRIPT" "$D" --timeout 4 --status 2>&1)"; RC=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "a result with another run id is not taken as this run's result (TIMEOUT, not OK)" "$([ $RC = 5 ] && echo 1 || echo 0)"
rm -rf "$D/.claude-logs" "$D"/trigger_* "$D"/git_*

# ---------------------------------------------------------------- ホスト側 (静的)
ok "host: lib/git-remote.ps1 exists, UTF-8 BOM + CRLF" "$([ -f "$PS1" ] && [ "$(head -c3 "$PS1" | xxd -p)" = efbbbf ] && [ "$(grep -vc $'\r$' "$PS1")" = 0 ] && echo 1 || echo 0)"
P="$(tr -d '\r' < "$PS1" 2>/dev/null | sed 's/^\xEF\xBB\xBF//')"
M="$(tr -d '\r' < "$MAIN" | sed 's/^\xEF\xBB\xBF//')"
ok "host: the main script loads git-remote and handles trigger_git.flag (result git_result.txt, output git_output.txt, error git_error.log)" "$([ "$(has "$M" '"git-remote"')" = 1 ] && [ "$(has "$M" 'trigger_git.flag')" = 1 ] && [ "$(has "$M" 'git_result.txt')" = 1 ] && [ "$(has "$M" 'git_output.txt')" = 1 ] && [ "$(has "$M" 'git_error.log')" = 1 ] && [ "$(has "$M" 'Invoke-GitFlag')" = 1 ] && echo 1 || echo 0)"
ok "host: the git flag is handled as its own kind (kind=git, busy mark, run id)" "$([ "$(has "$M" 'CurrentKind = "git"')" = 1 ] && [ "$(has "$M" 'Set-WatcherBusy "git')" = 1 ] && echo 1 || echo 0)"
ok "host: only status / fetch / push are operations; anything else is refused" "$([ "$(has "$P" 'Invoke-GitOps')" = 1 ] && [ "$(has "$P" "'status'")" = 1 ] && [ "$(has "$P" "'fetch'")" = 1 ] && [ "$(has "$P" "'push'")" = 1 ] && [ "$(has "$P" 'unknown operation')" = 1 ] && echo 1 || echo 0)"
ok "host: no force / delete / mirror / tags are ever passed to git (they appear only in the refusal list)" "$(! grep -vE '^\s*#|REFUSED|refuse' <<<"$P" | grep -qE -- '--force|--delete|--mirror|--tags|--prune-tags|\+refs|\+HEAD' && echo 1 || echo 0)"
ok "host: git never waits on a prompt (GIT_TERMINAL_PROMPT=0, GCM_INTERACTIVE=never) and is killed after a time limit" "$([ "$(has "$P" 'GIT_TERMINAL_PROMPT')" = 1 ] && [ "$(has "$P" 'GCM_INTERACTIVE')" = 1 ] && [ "$(has "$P" 'WaitForExit')" = 1 ] && [ "$(has "$P" 'Kill')" = 1 ] && echo 1 || echo 0)"
ok "host: protected branches (main / master) are refused unless allow-main" "$([ "$(has "$P" 'allow-main')" = 1 ] && [ "$(has "$P" 'main')" = 1 ] && [ "$(has "$P" 'master')" = 1 ] && echo 1 || echo 0)"
ok "host: a detached HEAD is refused; the branch name is checked against a safe pattern" "$([ "$(has "$P" 'detached HEAD')" = 1 ] && grep -qE "\^\[A-Za-z0-9" <<<"$P" && echo 1 || echo 0)"
ok "host: the outcome is classified (AUTH_REQUIRED / REJECTED / FAILED) from git's output" "$([ "$(has "$P" 'AUTH_REQUIRED')" = 1 ] && [ "$(has "$P" 'REJECTED')" = 1 ] && [ "$(has "$P" 'non-fast-forward')" = 1 ] && [ "$(has "$P" 'Authentication failed')" = 1 ] && echo 1 || echo 0)"
ok "host: credentials in a remote URL are masked before they are shown" "$([ "$(has "$P" 'REMOTE:')" = 1 ] && grep -qE '\*\*\*|://\$' <<<"$P" && echo 1 || echo 0)"
ok "host: git.exe is looked up on PATH, then in the usual install folders" "$([ "$(has "$P" 'git.exe')" = 1 ] && [ "$(has "$P" 'Program Files')" = 1 ] && echo 1 || echo 0)"
ok "host: the upstream is set with git branch --set-upstream-to (push has no -u: push -u failed silently on a real machine, GR4)" "$([ "$(has "$P" '--set-upstream-to=')" = 1 ] && ! grep -qE '\$pushArgs \+= "-u"|"push", "-u"' <<<"$P" && echo 1 || echo 0)"
ok "host: when .git/config is locked (the sandbox mounts /dev/null on config.lock while git_once.sh runs), the upstream is set after the result is returned (UPSTREAM_PENDING / Complete-GitUpstream)" "$([ "$(has "$P" 'UPSTREAM_PENDING')" = 1 ] && [ "$(has "$P" 'function Complete-GitUpstream')" = 1 ] && [ "$(has "$P" 'GitDeferredUpstream')" = 1 ] && tr -d '\r' < "$MAIN" >/dev/null && awk '/Write-GitMarker "OK"/{f=1} f&&/Complete-GitUpstream/{print "y"; exit}' <<<"$P" | grep -q y && echo 1 || echo 0)"
ok "host: without an upstream, the same-name remote branch (origin/<branch>) is used for AHEAD / BEHIND, and a push to it is allowed without --set-upstream" "$([ "$(has "$P" 'function Get-GitSameNameRef')" = 1 ] && [ "$(has "$P" 'is not set; the branch')" = 1 -o "$(has "$P" 'not set; the branch')" = 1 ] && [ "$(has "$P" 'does not exist on')" = 1 ] && echo 1 || echo 0)"
ok "host: HOST_VERSION is 2.102.0 or later" "$([ "$(printf '%s\n%s\n' 2.102.0 "$(tr -d '\r\n' < "$ROOT/host-tools/HOST_VERSION")" | sort -V | head -n 1)" = "2.102.0" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- Skill・規約・文書
ok "SKILL.md exists, name: git-remote, and the description says push / fetch" "$([ -f "$SKILL" ] && head -5 "$SKILL" | grep -q '^name: git-remote$' && head -5 "$SKILL" | grep -q 'push' && echo 1 || echo 0)"
S="$(cat "$SKILL" 2>/dev/null)"
ok "SKILL.md: push only when the user asks; never force; main only on the user's explicit word" "$([ "$(has "$S" '頼んだときだけ')" = 1 ] && [ "$(has "$S" '強制')" = 1 ] && [ "$(has "$S" '--allow-main')" = 1 ] && echo 1 || echo 0)"
ok "SKILL.md: AUTH_REQUIRED means the user signs in from Visual Studio once; Claude does not look for or create credentials" "$([ "$(has "$S" 'AUTH_REQUIRED')" = 1 ] && [ "$(has "$S" '認証情報')" = 1 ] && echo 1 || echo 0)"
ok "SKILL.md: pull / merge are not offered (the user decides), and the reason push is safe next to the WSL git is written" "$([ "$(has "$S" 'pull')" = 1 ] && [ "$(has "$S" 'インデックス')" = 1 ] && echo 1 || echo 0)"
ok "SKILL.md stays small (under 12000 bytes)" "$([ "$(wc -c < "$SKILL" 2>/dev/null || echo 99999)" -lt 12000 ] && echo 1 || echo 0)"
R="$(cat "$RULE")"
ok "rules/git-wsl.md: push / fetch go through the git-remote Skill (no longer 'the user (VS) only'), pull / merge stay with the user" "$([ "$(has "$R" 'git-remote')" = 1 ] && [ "$(has "$R" 'git_once.sh')" = 1 ] && ! grep -qF 'プッシュ・取得・PR・マージは、ユーザー (VS)' "$RULE" && echo 1 || echo 0)"
ok "rules/git-wsl.md: warns about the sandbox's empty files (.bashrc / .gitconfig / .mcp.json / .vscode / .claude ...) getting into a commit: stage by name, tell the user before 'commit all' in VS, delete-commit + .git/info/exclude" "$([ "$(has "$R" 'サンドボックス')" = 1 ] && [ "$(has "$R" '.mcp.json')" = 1 ] && [ "$(has "$R" 'すべてコミット')" = 1 ] && [ "$(has "$R" '.git/info/exclude')" = 1 ] && [ "$(has "$R" '名前を指定して')" = 1 ] && echo 1 || echo 0)"
ok "SKILL.md: the --status before a push may be skipped when the user named the branch / remote, but not for a first push, main / master, several remotes, or when unsure; the push result still reports BRANCH / TO_PUSH" "$([ "$(has "$S" '省いてよい')" = 1 ] && [ "$(has "$S" '初めての push')" = 1 ] && [ "$(has "$S" 'リモートが複数')" = 1 ] && [ "$(has "$S" 'TO_PUSH')" = 1 ] && echo 1 || echo 0)"
ok "CHANGELOG.md records 2.102.4 (the rule note and the skipped pre-status)" "$(grep -q '2.102.4' "$ROOT/CHANGELOG.md" && echo 1 || echo 0)"
ok "CHANGELOG.md records the feature" "$(grep -q '2.102.0' "$ROOT/CHANGELOG.md" && grep -q 'git-remote' "$ROOT/CHANGELOG.md" && echo 1 || echo 0)"
ok "TEST-PLAN.md has the real-machine checks (2-64)" "$(grep -q '^### 2-64' "$ROOT/docs/TEST-PLAN.md" && echo 1 || echo 0)"
ok "DESIGN.md has the decision (4.97)" "$(grep -q '^### 4.97' "$ROOT/docs/DESIGN.md" && echo 1 || echo 0)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
