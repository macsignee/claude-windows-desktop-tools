#!/usr/bin/env bash
# git_wsl_rule_test.sh - rules/git-wsl.md (v2.88.0): Visual Studio と WSL の両方で Git を操作するときの規約と、CLAUDE.md の案内の検証 (Windows 不要)。
# Usage: tests/git_wsl_rule_test.sh      終了コード: 0 すべて OK / 1 失敗あり
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R="$ROOT/rules/git-wsl.md"
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
has() { grep -q -F -e "$2" "$1" && echo 1 || echo 0; }
all1() { case "$1" in *0*) echo 0 ;; *) echo 1 ;; esac; }

ok "git-wsl.md exists with paths (.gitattributes / .sln / .slnx only; not every file)" "$([ -f "$R" ] && head -n 1 "$R" | grep -q '^---$' && grep -q '\*\*/.gitattributes' "$R" && grep -q '\*\*/\*.slnx' "$R" && ! grep -q '"\*\*/\*"' "$R" && echo 1 || echo 0)"
ok "git-wsl.md: UTF-8 without BOM, LF" "$([ "$(head -c3 "$R" | od -An -tx1 | tr -d ' \n')" != "efbbbf" ] && ! grep -q $'\r' "$R" && echo 1 || echo 0)"
ok "git-wsl.md: .gitattributes decides (text=auto eol=crlf); repo LF / working tree CRLF; add with --add-gitattributes" "$(all1 "$(has "$R" '* text=auto eol=crlf')$(has "$R" 'リポジトリの中は LF、作業フォルダは CRLF')$(has "$R" '--add-gitattributes')")"
ok "git-wsl.md: WSL git settings (autocrlf false, fileMode false, user.name / user.email, safe.directory)" "$(all1 "$(has "$R" 'core.autocrlf false')$(has "$R" 'core.fileMode false')$(has "$R" 'user.name')$(has "$R" 'safe.directory')")"
ok "git-wsl.md: check before commit (status, diff --stat, ls-files --eol, --ignore-cr-at-eol), do not normalize in bulk" "$(all1 "$(has "$R" 'git status --short')$(has "$R" 'git ls-files --eol')$(has "$R" '--ignore-cr-at-eol')$(has "$R" '--renormalize')")"
ok "git-wsl.md: do not run git while VS does (index.lock), reload in VS, commit only when asked, push by the user" "$(all1 "$(has "$R" 'index.lock')$(has "$R" 'すべて再読み込み')$(has "$R" 'ユーザーが頼んだときだけ')")"
ok "new_solution.py: every CLAUDE.md template points to git-wsl.md (4 templates)" "$([ "$(grep -c 'rules/git-wsl.md' "$ROOT/skills/new-solution/scripts/new_solution.py")" = 4 ] && echo 1 || echo 0)"
ok "a generated CLAUDE.md mentions git-wsl.md" "$(d=$(mktemp -d); python3 "$ROOT/skills/new-solution/scripts/new_solution.py" "$d/app" --type console --layers none --tests none >/dev/null 2>&1; r=$(grep -c 'git-wsl.md' "$d/app/CLAUDE.md" 2>/dev/null); rm -rf "$d"; [ "${r:-0}" -ge 1 ] && echo 1 || echo 0)"
ok "USAGE.md has the section for operating Git from both Visual Studio and WSL" "$(has "$ROOT/docs/USAGE.md" 'Visual Studio と WSL の、両方で、Git を操作するとき')"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
