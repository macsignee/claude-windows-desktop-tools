#!/usr/bin/env bash
# usage_guide_test.sh - 利用ガイド (docs/USAGE.md) が、Skill の一覧と、README の導線と、ずれていないことを検証する (v2.56.1)。
# Usage: tests/usage_guide_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
G="$ROOT/docs/USAGE.md"
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }

ok "USAGE.md がある" "$([ -f "$G" ] && echo 1 || echo 0)"
missing=""
for d in "$ROOT"/skills/*/; do n="$(basename "$d")"; grep -qF -- "$n" "$G" || missing="$missing $n"; done
ok "USAGE.md が、すべての Skill の名前に触れている (抜け:${missing:- なし})" "$([ -z "$missing" ] && echo 1 || echo 0)"
ok "スラッシュ専用の Skill (disable-model-invocation) が、USAGE.md の「新しい Skill ...」の表に、載っている" "$(r=1; for d in "$ROOT"/skills/*/; do if grep -q '^disable-model-invocation: true$' "$d/SKILL.md"; then grep -qF -- "/$(basename "$d")" "$G" || r=0; fi; done; echo $r)"
ok "USAGE.md: 判断フロー (Q1・Q2)、承認と差し戻し、困ったとき の 3 つの節がある" "$(r=1; for k in '## 1. どのコマンドを打つか' '### Q1.' '### Q2.' '## 2. 承認と差し戻しの言い方' '## 3. 困ったとき'; do grep -qF -- "$k" "$G" || r=0; done; echo $r)"
ok "USAGE.md: 承認は、はっきりした肯定の返事だけ。ほかの質問への答えは、承認でない (v2.55.1 の SKILL と同じ)" "$(grep -q 'はっきりした肯定の返事' "$G" && grep -q 'ほかの質問への答え' "$G" && grep -q '承認として扱われない' "$G" && echo 1 || echo 0)"
ok "USAGE.md: 確認の依頼に、「進めてよい」を混ぜない" "$(grep -q '確認の依頼に、「進めてよい」を混ぜない' "$G" && echo 1 || echo 0)"
ok "USAGE.md: ウォッチャーの細かい症状は、host-tools/README.md の「トラブルシューティング」へ (リンク先が、実在)" "$(grep -q 'host-tools/README.md' "$G" && grep -q '^## 7. トラブルシューティング' "$ROOT/host-tools/README.md" && echo 1 || echo 0)"
ok "README.md が、USAGE.md へ案内している (冒頭と、文書の一覧)" "$([ "$(grep -c 'docs/USAGE.md' "$ROOT/README.md")" -ge 2 ] && echo 1 || echo 0)"
ok "USAGE.md のリンク (../README.md、DESIGN.md、host-tools/README.md) の先が、実在する" "$([ -f "$ROOT/README.md" ] && [ -f "$ROOT/docs/DESIGN.md" ] && [ -f "$ROOT/host-tools/README.md" ] && echo 1 || echo 0)"
ok "USAGE.md: UTF-8、LF、BOM なし" "$(! grep -q $'\r' "$G" && [ "$(head -c3 "$G" | xxd -p)" != efbbbf ] && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
