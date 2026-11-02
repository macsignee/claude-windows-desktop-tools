#!/usr/bin/env bash
# rules_split_test.sh - C# の規約の 3 分割 (csharp-common.md / wpf-csharp.md / winforms-csharp.md。v2.35.0) を検証する。
# 文字列とバイト数による構造の確認 (Windows 不要)。読み込みの条件 (paths) が、実際に効くかは、実機で確かめる (TEST-PLAN 2-16)。
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
C="$ROOT/rules/csharp-common.md"; W="$ROOT/rules/wpf-csharp.md"; F="$ROOT/rules/winforms-csharp.md"
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
fm() { awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$1"; }
chap() { grep -o '^## [0-9]*\.' "$1" | tr -d '#. ' | tr '\n' ' '; }

ok "3 files exist" "$([ -f "$C" ] && [ -f "$W" ] && [ -f "$F" ] && echo 1 || echo 0)"
ok "common: paths is **/*.cs only" "$([ "$(fm "$C" | grep -c '^  - ')" = 1 ] && fm "$C" | grep -q '"\*\*/\*\.cs"' && echo 1 || echo 0)"
ok "wpf: paths does not match every .cs / .csproj (xaml, ViewModels, Views, *ViewModel* only)" "$(! fm "$W" | grep -q '"\*\*/\*\.cs"' && ! fm "$W" | grep -q 'csproj' && fm "$W" | grep -q '\*\*/\*\.xaml"' && fm "$W" | grep -q 'ViewModels' && fm "$W" | grep -q 'Views' && echo 1 || echo 0)"
ok "winforms: paths does not match every .cs / .csproj (Designer.cs, Forms, Presenters, *Presenter*, I*View only)" "$(! fm "$F" | grep -q '"\*\*/\*\.cs"' && ! fm "$F" | grep -q 'csproj' && fm "$F" | grep -q 'Designer\.cs' && fm "$F" | grep -q 'Forms' && fm "$F" | grep -q 'Presenters' && fm "$F" | grep -q 'Presenter\*' && echo 1 || echo 0)"
ok "common has the shared C# chapters 5 10 11 12 13 15 16 17, and no others" "$([ "$(chap "$C")" = '5 10 11 12 13 15 16 17 ' ] && echo 1 || echo 0)"
ok "wpf keeps the WPF-specific chapters and has none of the shared ones (numbers are unchanged)" "$([ "$(chap "$W")" = '1 2 3 4 6 7 8 9 14 18 19 ' ] && echo 1 || echo 0)"
ok "winforms: refers to csharp-common.md, no longer says to apply wpf-csharp.md chapters" "$(grep -q 'csharp-common.md' "$F" && ! grep -q '`wpf-csharp.md` の「' "$F" && ! grep -q 'wpf-csharp.md`) の \*\*C# の部分' "$F" && echo 1 || echo 0)"
ok "wpf points to csharp-common.md for the moved chapters" "$(grep -q 'csharp-common.md` に移した' "$W" && echo 1 || echo 0)"
ok "no other file still tells to read the shared chapters from wpf-csharp.md (new-solution, csharp-test-first, README)" "$(! grep -rq 'wpf-csharp.md` の C# の部分' "$ROOT/skills" "$ROOT/README.md" && echo 1 || echo 0)"

# 読み込みの大きさの上限 (バイト数。再び膨らまないように)。WinForms のファイルを読む = common + winforms、WPF = common + wpf
bytes() { wc -c < "$1" | tr -d ' '; }
bc=$(bytes "$C"); bw=$(bytes "$W"); bf=$(bytes "$F")
ok "WinForms: common + winforms <= 40000 bytes (was 62524 before the split; ${bc}+${bf})" "$([ $((bc+bf)) -le 40000 ] && echo 1 || echo 0)"
ok "WPF: common + wpf <= 44000 bytes (was 62524 before the split; ${bc}+${bw})" "$([ $((bc+bw)) -le 44000 ] && echo 1 || echo 0)"
ok "a plain .cs read (common only) <= 15000 bytes (${bc})" "$([ "$bc" -le 15000 ] && echo 1 || echo 0)"

# 配布: install.sh --rules-only が、3 つとも対象にする
out="$(bash "$ROOT/install/install.sh" --rules-only --dry-run --rules-dir "${TMPDIR:-/tmp}/rs_$$" 2>&1)"
ok "install.sh --rules-only --dry-run lists the 3 rule files" "$(echo "$out" | grep -q 'csharp-common.md' && echo "$out" | grep -q 'wpf-csharp.md' && echo "$out" | grep -q 'winforms-csharp.md' && echo 1 || echo 0)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
