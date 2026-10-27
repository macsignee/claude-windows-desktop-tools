#!/usr/bin/env bash
# host_tools_static_test.sh - ホスト側 (watch_and_build.ps1 / run_watcher.cmd) の、構造の静的な確認。
# PowerShell も Windows も使えないので、実行はできない。**書き換えで壊しやすい点** (ソリューションの遅延検出) だけを、文字列で確かめる。
# 実機での確認は、TEST-PLAN の H 系。
# Usage: tests/host_tools_static_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PS="$ROOT/host-tools/watch_and_build.ps1"
CMD="$ROOT/host-tools/run_watcher.cmd"
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
ps() { tr -d '\r' < "$PS" | sed '1s/^\xef\xbb\xbf//'; }
cnt() { ps | grep -c -- "$1"; }

ok "ps1: UTF-8 BOM + CRLF" "$([ "$(head -c3 "$PS" | xxd -p)" = efbbbf ] && [ "$(grep -vc $'\r$' "$PS")" = 0 ] && echo 1 || echo 0)"
ok "ps1: -SolutionPath is optional (no Mandatory on it)" "$(ps | awk '/^param\(/,/\[string\]\$Platform/' | grep -B1 '\[string\]\$SolutionPath' | grep -q Mandatory && echo 0 || echo 1)"
ok "ps1: TargetDir is still mandatory" "$(ps | awk '/^param\(/,/\[string\]\$SolutionPath/' | grep -B1 '\[string\]\$TargetDir' | grep -q 'Mandatory=\$true' && echo 1 || echo 0)"
ok "ps1: an explicit -SolutionPath that does not exist is still an error (exit 2)" "$(ps | awk '/SolutionExplicit\) \{/,/^}/' | grep -q 'exit 2' && echo 1 || echo 0)"
ok "ps1: Find-SolutionFile prefers .slnx, then .sln, with an exact extension check" "$(ps | awk '/^function Find-SolutionFile/,/^}/' | grep -q '".slnx", ".sln"' && ps | awk '/^function Find-SolutionFile/,/^}/' | grep -q 'Extension -ieq' && echo 1 || echo 0)"
ok "ps1: Update-SolutionState is defined, called at startup, and in the gtest / package / build triggers (4 calls)" "$([ "$(cnt '^function Update-SolutionState')" = 1 ] && [ "$(cnt '^ *Update-SolutionState')" = 4 ] && echo 1 || echo 0)"
ok "ps1: Update-SolutionState assigns script-scope variables (SolutionPath / SolutionDir / ProjectPaths / HasCpp / HasDotnet / Platform / BuildFeatures / SolutionKind)" "$(b="$(ps | awk '/^function Update-SolutionState/,/^}/')"; for v in SolutionPath SolutionDir ProjectPaths HasCpp HasDotnet Platform BuildFeatures SolutionKind; do grep -qE "\\\$script:$v +=" <<<"$b" || exit 1; done; echo 1)"
ok "ps1: the old one-shot startup assignments are gone (no top-level \$HasCpp / \$BuildFeatures = ...)" "$(! ps | grep -q '^\$HasCpp \|^\$BuildFeatures = \|^\$SolutionKind = \|^\$SolutionDir = ' && echo 1 || echo 0)"
ok "ps1: the build trigger returns an environment error (exit code 2) when there is no solution, without running the build script" "$(ps | grep -q 'if (-not \$SolutionPath) {' && ps | grep -q 'ERROR: no .sln / .slnx found in' && ps | awk '/if \(-not \$SolutionPath\) \{/,/\$exitCode = 2/' | grep -q 'exitCode = 2' && echo 1 || echo 0)"
ok "ps1: Invoke-BuildScript is only reached when a solution exists" "$(ps | awk '/if \(-not \$SolutionPath\) \{/{f=1} f&&/Invoke-BuildScript/{print "after"; exit}' | grep -q after && echo 1 || echo 0)"
ok "ps1: the banner copes with a missing solution" "$(ps | grep -q "no .sln / .slnx in ' + \$TargetDir" && echo 1 || echo 0)"
ok "ps1: brackets are balanced (outside the known baseline: { } -1, ( ) +1 from strings and comments)" "$(python3 - "$PS" <<'PY'
import re,sys
t=open(sys.argv[1],'rb').read().decode('utf-8-sig')
t=re.sub(r"@'.*?'@","",t,flags=re.S)
c={k:t.count(k) for k in '{}()[]'}
print(1 if (c['{']-c['}'],c['(']-c[')'],c['[']-c[']'])==(-1,1,0) else 0)
PY
)"

ok "cmd: CP932 + CRLF (no BOM)" "$([ "$(head -c3 "$CMD" | xxd -p)" != efbbbf ] && [ "$(grep -c $'\r$' "$CMD")" = "$(wc -l < "$CMD")" ] && echo 1 || echo 0)"
c="$(iconv -f CP932 -t UTF-8 "$CMD" | tr -d '\r')"
ok "cmd: starts even when no solution exists (the 'no .sln' error remains only when no ProjectDir argument was given)" "$(grep -q 'if not defined SLN_FILE if defined DEFAULT_DIR (' <<<"$c" && ! grep -q '^if not defined SLN_FILE (' <<<"$c" && echo 1 || echo 0)"
ok "cmd: passes -SolutionPath only when a solution was found (SLN_ARG)" "$(grep -q '^set "SLN_ARG="' <<<"$c" && grep -q '^if defined SLN_FILE set SLN_ARG=-SolutionPath "%SLN_FILE%"' <<<"$c" && grep -q -- '-TargetDir "%PROJECT_DIR%" %SLN_ARG% -Platform' <<<"$c" && ! grep -q -- '-SolutionPath "%SLN_FILE%" -Platform' <<<"$c" && echo 1 || echo 0)"
ok "cmd: the solution display does not use a parenthesized block (a file name with ')' must not break it)" "$(grep -q '^if defined SLN_FILE echo  Solution:' <<<"$c" && grep -q '^if not defined SLN_FILE echo  Solution:' <<<"$c" && echo 1 || echo 0)"

ok "ps1: -UiTestTimeoutSec defaults from WATCH_UI_TIMEOUT_SEC (600 when unset); an explicit argument wins" "$(ps | grep -qF '[int]$UiTestTimeoutSec = $(if ($env:WATCH_UI_TIMEOUT_SEC) { [int]$env:WATCH_UI_TIMEOUT_SEC } else { 600 })' && echo 1 || echo 0)"
ok "ps1: the UI test banner still shows the timeout" "$(ps | grep -qF 'timeout ${UiTestTimeoutSec}s' && echo 1 || echo 0)"

ok "ps1: -UiTestDesktop defaults to auto (WATCH_UI_DESKTOP overrides); visible is accepted as an alias of default" "$(ps | grep -qF '[ValidateSet("auto","default","visible","separate","invisible")]' && ps | grep -qF '} else { "auto" }' && ps | grep -qF 'if ($UiTestDesktop -eq "visible") { $UiTestDesktop = "default" }' && echo 1 || echo 0)"
ok "ps1: invisible is accepted as an alias of separate (parameter and the flag)" "$(ps | grep -qF 'if ($UiTestDesktop -eq "invisible") { $UiTestDesktop = "separate" }' && ps | grep -qF 'if ($w -eq "invisible") { $w = "separate" }' && echo 1 || echo 0)"
ok "ps1: the per-run settings are read from trigger_uitest.flag BEFORE the flag is removed" "$(ps | awk '/Get-Content -LiteralPath \$UiTestTriggerFile -Raw/{r=NR} /Remove-Item -LiteralPath \$TriggerFile/{d=NR} END{exit !(r && d && r<d)}' && echo 1 || echo 0)"
ok "ps1: the default desktop comes from the UI test project's uitest.settings (no WPF special case in the watcher); the flag's desktop= / slowmo= win" "$(ps | grep -qF 'Read-UiProjectSettings' && ps | grep -qF '"uitest.settings"' && ps | grep -qF 'ConvertFrom-UiSettingsText' && ps | grep -qF "desktop\\s*=" && ps | grep -qF "slowmo\\s*=" && ! ps | grep -qF 'Test-SolutionUsesWpf' && echo 1 || echo 0)"
ok "ps1: precedence = flag > watcher setting (-UiTestDesktop / WATCH_UI_DESKTOP) > uitest.settings > separate" "$(ps | awk '/if \(\$fl.Desktop\)/{a=NR} /elseif \(\$UiTestDesktop -in/{b=NR} /elseif \(\$proj.Desktop\)/{c=NR} /default \(no uitest.settings\)/{d=NR} END{exit !(a && b>a && c>b && d>=c)}' && echo 1 || echo 0)"
ok "ps1: Invoke-Tests and the software rendering use the resolved per-run desktop and slow-motion" "$(ps | grep -qF '$script:UiRun.Desktop -eq "separate"' && ps | grep -qF '$script:UiRun.SlowMoMs' && ! ps | grep -qF '($Ui -and $UiTestDesktop' && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
