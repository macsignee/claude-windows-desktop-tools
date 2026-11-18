#!/usr/bin/env bash
# project_scope_test.sh - プロジェクト単位のビルド・テスト (--project <名前> / フラグの project=<名前>。v2.98.0) を、検証する。
#   - Skill 側 (build_once.sh / build_test_once.sh / uitest_once.sh): フラグに project= を書く、引数の検査、古いウォッチャーを知らせる NOTE。疑似ウォッチャーで、WSL だけで確かめる。
#   - ホスト側 (watch_and_build.ps1 / lib\*.ps1 / build-windows.cmd): PowerShell が WSL にないので、ソースを静的に確かめる (実機は、TEST-PLAN 2-58)。
# Usage: tests/project_scope_test.sh      (最後に PASS=... FAIL=...。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BO="$ROOT/skills/auto-build/scripts/build_once.sh"
BT="$ROOT/skills/build-test-loop/scripts/build_test_once.sh"
UT="$ROOT/skills/build-test-loop/scripts/uitest_once.sh"
HN="$ROOT/skills/build-test-loop/scripts/harness_note.sh"
HT="$ROOT/host-tools"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
yes_if() { "$@" >/dev/null 2>&1 && echo 1 || echo 0; }

# ---- 疑似ウォッチャー: フラグを回収して、中身を $T/seen_<フラグ名> に残し、結果を書く。run_id.txt の scope= は、$SCOPE_LINE が空でなければ書く (新しいウォッチャーの真似)
fake_watcher() {  # $1=フラグ名 $2=build|test
    local flag="$1" kind="$2"
    while true; do
        if [ -f "$T/$flag" ]; then
            cp "$T/$flag" "$T/seen_$flag"
            rid="$(sed -n 's/^run=//p' "$T/$flag" | head -n 1 | tr -d '\r')"
            rm -f "$T/$flag"
            sleep 1
            mkdir -p "$T/.claude-logs"
            { printf 'run=%s\r\nwatcher=2.98.0\r\nkind=%s\r\ninput=%s\r\n' "$rid" "$kind" "$T"; [ -z "${SCOPE_LINE:-}" ] || printf 'scope=%s\r\n' "$SCOPE_LINE"; printf 'finished=2026-11-18 10:00:00\r\n'; } > "$T/.claude-logs/run_id.txt"
            if [ "$kind" = build ]; then printf SUCCESS > "$T/build_result.txt"
            else printf SUCCESS > "$T/build_result.txt"; printf PASSED > "$T/test_result.txt"; fi
        fi
        sleep 0.3
    done
}
reset() { rm -rf "$T/.claude-logs" "$T"/*.txt "$T"/*.flag "$T"/seen_* 2>/dev/null; }

# ---- 1. build_test_once.sh --project: フラグに project= が書かれ、結果に scope= が付く (新しいウォッチャー)
reset; SCOPE_LINE="project=OrderLogic" fake_watcher trigger_test.flag test & W=$!
out="$(bash "$BT" "$T" 20 --project OrderLogic 2>&1)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "build_test_once --project: PASSED (rc=0)" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = PASSED ] && echo 1 || echo 0)"
ok "build_test_once --project: the flag has run= on line 1 and project=OrderLogic" "$([ "$(head -n 1 "$T/seen_trigger_test.flag" | cut -c1-4)" = "run=" ] && grep -qx 'project=OrderLogic' "$T/seen_trigger_test.flag" && echo 1 || echo 0)"
ok "build_test_once --project: RESULT_INFO shows scope=project=OrderLogic, and no NOTE (the watcher handled it)" "$(echo "$out" | grep -q 'RESULT_INFO:.*scope=project=OrderLogic' && ! echo "$out" | grep -q 'NOTE: --project' && echo 1 || echo 0)"

# ---- 2. --project=<名前> の形、引数の順序 (--project が先頭でも、dir と timeout が読める)
reset; SCOPE_LINE="project=Foo.Bar" fake_watcher trigger_test.flag test & W=$!
out="$(bash "$BT" --project=Foo.Bar "$T" 20 2>&1)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "build_test_once --project=Foo.Bar before the positional arguments works" "$([ $rc = 0 ] && grep -qx 'project=Foo.Bar' "$T/seen_trigger_test.flag" && echo 1 || echo 0)"

# ---- 3. --project を付けない: フラグに project= を書かない (これまでどおり、ソリューション全体)
reset; SCOPE_LINE="solution" fake_watcher trigger_test.flag test & W=$!
out="$(bash "$BT" "$T" 20 2>&1)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "build_test_once without --project: no project= line in the flag, no NOTE" "$([ $rc = 0 ] && ! grep -q '^project=' "$T/seen_trigger_test.flag" && ! echo "$out" | grep -q 'NOTE: --project' && echo 1 || echo 0)"

# ---- 4. 古いウォッチャー (scope= を書かない): NOTE で、全体を処理したことを知らせる
reset; SCOPE_LINE="" fake_watcher trigger_test.flag test & W=$!
out="$(bash "$BT" "$T" 20 --project OrderLogic 2>&1)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "old watcher (no scope= in run_id.txt): still PASSED, but a NOTE says the whole solution was processed" "$([ $rc = 0 ] && echo "$out" | grep -q 'NOTE: --project OrderLogic' && echo "$out" | grep -q 'HOST_VERSION 2.98.0' && echo 1 || echo 0)"

# ---- 5. build_once.sh --project
reset; SCOPE_LINE="project=OrderLogic" fake_watcher trigger_build.flag build & W=$!
out="$(bash "$BO" "$T" 20 --project OrderLogic 2>&1)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "build_once --project: SUCCESS (rc=0), the flag has project=OrderLogic" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = SUCCESS ] && grep -qx 'project=OrderLogic' "$T/seen_trigger_build.flag" && echo 1 || echo 0)"
reset; fake_watcher trigger_build.flag build & W=$!
out="$(bash "$BO" "$T" 20 2>&1)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "build_once without --project: the flag is only run=<ID>" "$([ $rc = 0 ] && [ "$(wc -l < "$T/seen_trigger_build.flag")" = 1 ] && echo 1 || echo 0)"

# ---- 6. uitest_once.sh --project: フラグに project= (UI テストのフラグ)。UI テストのプロジェクトは 1 つなので、待ち時間の計算は 1 つ分
reset; SCOPE_LINE="project=OrderLogic" fake_watcher trigger_uitest.flag test & W=$!
out="$(bash "$UT" "$T" 30 --project OrderLogic --separate 2>&1)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "uitest_once --project: PASSED, the flag has project=OrderLogic and desktop=separate" "$([ $rc = 0 ] && grep -qx 'project=OrderLogic' "$T/seen_trigger_uitest.flag" && grep -qx 'desktop=separate' "$T/seen_trigger_uitest.flag" && echo 1 || echo 0)"
ok "uitest_once --project: RESULT_INFO shows the scope" "$(echo "$out" | grep -q 'scope=project=OrderLogic' && echo 1 || echo 0)"

# ---- 7. 引数の検査: 名前がない・不正な文字 → BAD_ARGS (rc=2)。何も、ウォッチャーに頼まない
for bad in "--project" "--project=" "--project a/b" "--project a;b" "--project a\$b"; do
    reset
    # shellcheck disable=SC2086
    out="$(bash "$BT" "$T" 5 $bad 2>&1)"; rc=$?
    ok "build_test_once '$bad': BAD_ARGS (rc=2), no flag written" "$([ $rc = 2 ] && echo "$out" | head -n 1 | grep -q '^BAD_ARGS' && [ ! -f "$T/trigger_test.flag" ] && echo 1 || echo 0)"
done
reset; out="$(bash "$UT" "$T" 5 --project 2>&1)"; rc=$?
ok "uitest_once '--project' without a name: BAD_ARGS (rc=2)" "$([ $rc = 2 ] && echo "$out" | head -n 1 | grep -q '^BAD_ARGS' && echo 1 || echo 0)"
reset; out="$(bash "$UT" "$T" 5 --project 'a b' 2>&1)"; rc=$?
ok "uitest_once '--project a b': BAD_ARGS (rc=2)" "$([ $rc = 2 ] && echo "$out" | head -n 1 | grep -q '^BAD_ARGS' && echo 1 || echo 0)"

# ---- 8. harness_note.sh: HARNESS_EXPECT_SCOPE がなければ、何も言わない (これまでどおり)
mkdir -p "$T/h/.claude-logs"
printf 'run=1\r\nwatcher=2.98.0\r\nkind=test\r\ninput=C:\\x\r\nfinished=t\r\n' > "$T/h/.claude-logs/run_id.txt"
out="$(bash "$HN" "$T/h" 2>&1)"
ok "harness_note: no HARNESS_EXPECT_SCOPE -> no scope NOTE, and no scope= in RESULT_INFO when the result has none" "$(! echo "$out" | grep -q 'NOTE: --project' && ! echo "$out" | grep -q 'scope=' && echo 1 || echo 0)"

# ======================================================================== ホスト側 (静的)
PS="$HT/watch_and_build.ps1"; BLD="$HT/lib/build.ps1"; TST="$HT/lib/tests.ps1"; CMN="$HT/lib/common.ps1"; CMD="$HT/build-windows.cmd"
BOM3() { head -c3 "$1" | xxd -p; }
for f in "$PS" "$BLD" "$TST" "$CMN"; do
    ok "$(basename "$f"): still UTF-8 BOM + CRLF" "$([ "$(BOM3 "$f")" = efbbbf ] && [ "$(grep -vc $'\r$' "$f")" = 0 ] && echo 1 || echo 0)"
done
ok "build-windows.cmd: still CRLF, decodes as CP932" "$([ "$(grep -vc $'\r$' "$CMD")" = 0 ] && iconv -f CP932 -t UTF-8 "$CMD" >/dev/null 2>&1 && echo 1 || echo 0)"
b="$(tr -d '\r' < "$BLD")"; p="$(tr -d '\r' < "$PS")"; t="$(tr -d '\r' < "$TST")"; c="$(tr -d '\r' < "$CMN")"
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
ok "build.ps1: Get-FlagProjectName / Resolve-ProjectScope / Invoke-ScopedBuild exist" "$([ "$(has "$b" 'function Get-FlagProjectName')" = 1 ] && [ "$(has "$b" 'function Resolve-ProjectScope')" = 1 ] && [ "$(has "$b" 'function Invoke-ScopedBuild')" = 1 ] && echo 1 || echo 0)"
ok "build.ps1: the test project names are <name>Test / <name>Tests / <name>.Tests, and <name>.UITests for UI tests" "$([ "$(has "$b" '@("Test", "Tests", ".Tests")')" = 1 ] && [ "$(has "$b" '".UITests"')" = 1 ] && echo 1 || echo 0)"
ok "build.ps1: the project name is validated (letters, digits, _ . -)" "$(has "$b" "'^[A-Za-z0-9_.\\-]+\$'")"
ok "build.ps1: the scoped build builds Main first, then the test project, and stops at the first failure" "$([ "$(has "$b" 'if ($sc.Main) { $targets += $sc.Main }')" = 1 ] && [ "$(has "$b" '$targets += @($sc.Test)')" = 1 ] && [ "$(has "$b" 'if ($b.ExitCode -ne 0) { return')" = 1 ] && echo 1 || echo 0)"
ok "build.ps1: SolutionDir is passed to MSBuild through the environment (no quoting problem), and restored afterwards" "$([ "$(has "$b" "\$env:SolutionDir = \$SolutionDir.TrimEnd('\\') + '\\'")" = 1 ] && [ "$(has "$b" 'finally {')" = 1 ] && [ "$(has "$b" 'Remove-Item Env:\SolutionDir')" = 1 ] && echo 1 || echo 0)"
ok "build.ps1: Invoke-BuildScript takes an optional project target (the solution when omitted)" "$([ "$(has "$b" 'function Invoke-BuildScript([string]$Target = "")')" = 1 ] && [ "$(has "$b" "+ \$Target + '\" \"'")" = 1 ] && echo 1 || echo 0)"
ok "watch_and_build.ps1: reads project= from the flag before deleting it, then builds with Invoke-ScopedBuild when a scope is set" "$([ "$(has "$p" 'Get-FlagProjectName $scopeText')" = 1 ] && [ "$(has "$p" 'if ($script:Scope) { Invoke-ScopedBuild } else { Invoke-BuildScript }')" = 1 ] && [ "$p" != "" ] && echo 1 || echo 0)"
ok "watch_and_build.ps1: the project= flag is read BEFORE Remove-Item of the flag" "$(python3 - "$PS" <<'PYEOF' 2>/dev/null && echo 1 || echo 0
import sys
t = open(sys.argv[1], 'rb').read().decode('utf-8-sig').replace('\r\n', '\n')
i = t.index('Get-FlagProjectName $scopeText')
j = t.index('Remove-Item -LiteralPath $TriggerFile', i)
sys.exit(0 if i < j else 1)
PYEOF
)"
ok "watch_and_build.ps1: tests run against the scope's test projects only (ProjectPaths narrowed, then restored in finally), scope cleared at the end" "$([ "$(has "$p" '$script:ProjectPaths = @($script:Scope.Test); $script:ScopeActive = $true')" = 1 ] && [ "$(has "$p" 'finally { $script:ProjectPaths = $savedProjectPaths; $script:ScopeActive = $false }')" = 1 ] && [ "$(has "$p" '$script:Scope = $null
        Clear-WatcherBusy')" = 1 ] && echo 1 || echo 0)"
ok "watch_and_build.ps1: documents project= in the header and the banner" "$([ "$(has "$p" '[プロジェクト単位]')" = 1 ] && [ "$(has "$p" 'flag line project=<name>')" = 1 ] && echo 1 || echo 0)"
ok "watch_and_build.ps1: the message uses \${scopeName} (a variable followed by ':' would be read as a drive-qualified name)" "$([ "$(has "$p" '${scopeName}:')" = 1 ] && ! grep -q '\$scopeName:' <<<"$p" && echo 1 || echo 0)"
ok "tests.ps1: Find-TestExes keeps only the exes of the scope's test projects when a scope is active" "$([ "$(has "$t" 'if ($script:ScopeActive)')" = 1 ] && [ "$(has "$t" '$scopeExes -contains $_.Name')" = 1 ] && echo 1 || echo 0)"
ok "common.ps1: run_id.txt records scope= (project=<name> or solution)" "$([ "$(has "$c" 'scope=$(if ($script:Scope')" = 1 ] && [ "$(has "$c" "'solution'")" = 1 ] && echo 1 || echo 0)"
cmd="$(iconv -f CP932 -t UTF-8 "$CMD" | tr -d '\r')"
ok "build-windows.cmd: a lone .csproj / .vbproj / .fsproj gets Platform AnyCPU (Any CPU is the solution configuration name); a solution is unchanged" "$([ "$(has "$cmd" 'for %%E in (.csproj .vbproj .fsproj) do if /i "%TARGET_EXT%"=="%%E" set "MSPLATFORM=AnyCPU"')" = 1 ] && echo 1 || echo 0)"
ok "build-windows.cmd: a lone .NET project also gets AnyCPU when the watcher Platform is x64 (mixed solution), unless it declares <Platforms> (else bin\\x64\\Debug and dotnet test --no-build looks in bin\\Debug)" "$([ "$(has "$cmd" 'findstr /I /C:"<Platforms>" "%TARGET%" >nul 2>&1 || set "MSPLATFORM=AnyCPU"')" = 1 ] && echo 1 || echo 0)"
ok "the new mapping comes after TARGET_EXT is set and before MSBuild runs" "$(python3 - "$CMD" <<'PYEOF' 2>/dev/null && echo 1 || echo 0
import sys
t = open(sys.argv[1], 'rb').read().decode('cp932')
a = t.index('set "TARGET_EXT=%%~xI"'); b = t.index('set "MSPLATFORM=AnyCPU"'); c = t.index('MSBuild.exe "%TARGET%"')
sys.exit(0 if a < b < c else 1)
PYEOF
)"
ok "HOST_VERSION is 2.98.0 or later (the scope needs the new watcher; harness_note.sh tells when it is older)" "$([ "$(printf '%s\n%s\n' "$(tr -d '\r\n' < "$HT/HOST_VERSION")" 2.98.0 | sort -V | head -n 1)" = "2.98.0" ] && echo 1 || echo 0)"
ok "SKILL.md of auto-build / build-test-loop and references/ui-tests.md mention --project" "$(grep -q -- '--project' "$ROOT/skills/auto-build/SKILL.md" && grep -q -- '--project' "$ROOT/skills/build-test-loop/SKILL.md" && grep -q -- "--project" "$ROOT/skills/build-test-loop/references/ui-tests.md" && echo 1 || echo 0)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
