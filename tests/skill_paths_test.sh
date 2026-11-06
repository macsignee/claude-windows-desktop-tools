#!/usr/bin/env bash
# skill_paths_test.sh - Skill が、配布先のパスを固定せず、「Skill のフォルダ」を基準にしていることを検証する (v2.58.0)。
# ホームの ~/.claude/skills でも、プロジェクトの .claude/skills でも、同じに動く (コピー先は、install.sh の --skills-dir で変えられる)。
# Usage: tests/skill_paths_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="${TMPDIR:-/tmp}/skp_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }

# 1. 固定のパス (~/.claude/skills/<Skill 名>) が、Skill・規約・ひな形・道具の文書とスクリプトに残っていない
left="$(grep -rIn '~/\.claude/skills/[a-z]' "$ROOT/skills" "$ROOT/rules" "$ROOT/templates" "$ROOT/scripts" 2>/dev/null | head -5)"
ok "~/.claude/skills/<Skill 名> の固定のパスが、skills / rules / templates / scripts に残っていない${left:+ (残り: $left)}" "$([ -z "$left" ] && echo 1 || echo 0)"
left="$(grep -rIn '~/\.claude/\(rules\|templates\|scripts\)/' "$ROOT/skills" "$ROOT/rules" "$ROOT/templates" 2>/dev/null | head -5)"
ok "~/.claude/rules・templates・scripts の固定のパスも、残っていない (.claude/... と書く)${left:+ (残り: $left)}" "$([ -z "$left" ] && echo 1 || echo 0)"

# 2. <Skill群> を使う SKILL.md は、冒頭で、意味を書いている
miss=""
for f in "$ROOT"/skills/*/SKILL.md; do
    if grep -q '<Skill群>' "$f" && ! grep -q 'パスの書き方' "$f"; then miss="$miss $(basename "$(dirname "$f")")"; fi
done
ok "<Skill群> を使う SKILL.md は、冒頭に「パスの書き方」を書いている (抜け:${miss:- なし})" "$([ -z "$miss" ] && echo 1 || echo 0)"

# 3. <Skill群>/<Skill 名>/<パス> が、リポジトリの skills/ に実在する (プレースホルダ < > と * を含むものは除く)
bad=""
while IFS= read -r ref; do
    rel="${ref#<Skill群>/}"
    case "$rel" in *"<"*|*"*"*|*"{"*|*"$"*) continue ;; esac
    rel="${rel%%[\"\`\ ,)]*}"
    [ -e "$ROOT/skills/$rel" ] || bad="$bad $rel"
done < <(grep -rIoh '<Skill群>/[A-Za-z0-9_./-]*' "$ROOT/skills" | sort -u)
ok "<Skill群>/... の参照先が、すべて skills/ に実在する (実在しない:${bad:- なし})" "$([ -z "$bad" ] && echo 1 || echo 0)"

# 4. プロジェクトの .claude/skills に配布しても、同じ参照が解決する (配布先を、一時フォルダにする)
P="$T/proj/.claude/skills"
bash "$ROOT/install/install.sh" --skills-only --skills-dir "$P" --host-dir "$T/h" --rules-dir "$T/r" --templates-dir "$T/t" --scripts-dir "$T/s" >/dev/null 2>&1
ok "install.sh --skills-dir <プロジェクト>/.claude/skills で、全 Skill が配られる" "$([ "$(ls "$P" | wc -l)" = "$(ls "$ROOT/skills" | wc -l)" ] && echo 1 || echo 0)"
bad=""
while IFS= read -r ref; do
    rel="${ref#<Skill群>/}"
    case "$rel" in *"<"*|*"*"*|*"{"*|*"$"*) continue ;; esac
    rel="${rel%%[\"\`\ ,)]*}"
    [ -e "$P/$rel" ] || bad="$bad $rel"
done < <(grep -rIoh '<Skill群>/[A-Za-z0-9_./-]*' "$P" | sort -u)
ok "配布先 (プロジェクトの .claude/skills) でも、<Skill群>/... の参照先が、すべて解決する (解決しない:${bad:- なし})" "$([ -z "$bad" ] && echo 1 || echo 0)"
ok "配布先の SKILL.md に、ホームの固定のパスがない" "$(! grep -rIq '~/\.claude/skills/[a-z]' "$P" && echo 1 || echo 0)"

# 5. スクリプトが、自分の場所から、Skill 群を求める (solution_state.py の例のコマンド、test_guard_note.sh の全文のコマンド)
D="$T/Sol"; mkdir -p "$D"
python3 "$ROOT/skills/new-solution/scripts/new_solution.py" "$D" --type console --layers logic,data --tests none >/dev/null 2>&1
out="$(python3 "$P/add-project/scripts/solution_state.py" "$D" 2>&1)"
ok "solution_state.py の ADDABLE の例のコマンドは、実行した場所 (配布先の .claude/skills) のスクリプトを指す" "$(grep -q "python3 $P/cpp-test-first/scripts/add_layer.py" <<<"$out" && ! grep -q '~/.claude' <<<"$out" && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
