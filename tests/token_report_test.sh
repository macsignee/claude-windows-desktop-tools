#!/bin/bash
# tools/token_report.py (セッションのログの Token 集計) のテスト。小さな疑似のログで行う。
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TR="$ROOT/tools/token_report.py"
T="${TMPDIR:-/tmp}/token_report_test.$$"; mkdir -p "$T"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { printf '%s\n' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }

python3 -I - "$T/s.jsonl" <<'PY'
import json, sys
rows = []
def asst(mid, ui, cc, cr, out, content):
    # 1 つのメッセージが、content ごとに複数の行へ分かれる (id と usage は同じ)。重複を除くこと
    u = {'input_tokens': ui, 'cache_creation_input_tokens': cc, 'cache_read_input_tokens': cr, 'output_tokens': out}
    for c in content:
        rows.append({'type': 'assistant', 'message': {'id': mid, 'role': 'assistant', 'content': [c], 'usage': u}})
def tool(i, name): return {'type': 'tool_use', 'id': i, 'name': name, 'input': {}}
def result(i, text, as_str=False):
    c = text if as_str else [{'type': 'text', 'text': text}]
    rows.append({'type': 'user', 'message': {'role': 'user', 'content': [{'type': 'tool_result', 'tool_use_id': i, 'content': c}]}})
rows.append({'type': 'user', 'message': {'role': 'user', 'content': 'はじめ'}})
asst('m1', 2, 30000, 0, 5, [{'type': 'thinking', 'thinking': 'x'}, tool('t1', 'Bash')])
result('t1', 'a' * 120)
asst('m2', 3, 500, 30000, 7, [tool('t2', 'Read')])
result('t2', 'b' * 300)
skill = 'Base directory for this skill: /h/.claude/skills/csharp-test-first\n\n' + 'c' * 130
rows.append({'type': 'user', 'message': {'role': 'user', 'content': [{'type': 'text', 'text': skill}]}})
rows.append({'type': 'attachment', 'attachment': {'type': 'nested_memory', 'path': '/h/.claude/rules/csharp-common.md',
             'content': {'path': '/h/.claude/rules/csharp-common.md', 'type': 'User', 'content': 'd' * 400}}})
asst('m3', 4, 100, 30500, 9, [tool('t3', 'Bash')])
result('t3', 'e' * 50, as_str=True)
rows.append({'type': 'attachment', 'attachment': {'type': 'date', 'date': '2026-11-25'}})
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    f.write('{broken json\n')                      # 壊れた行は、読み飛ばす
    for r in rows: f.write(json.dumps(r, ensure_ascii=False) + '\n')
pass
PY
SKILL_LEN="$(python3 -I -c "print(len('Base directory for this skill: /h/.claude/skills/csharp-test-first\n\n' + 'c'*130))")"

OUT="$(python3 -I "$TR" "$T/s.jsonl" 2>&1)"; RC=$?
ok "正常終了 (rc=$RC)" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "ターン数は 3 (同じ id の行を、重複して数えない)" "$(has "$OUT" 'TURNS: 3')"
ok "合計: input 9 / cache_creation 30600 / cache_read 60500 / output 21" "$(has "$OUT" 'TOTAL: input=9 cache_creation=30600 cache_read=60500 output=21')"
ok "文脈の大きさ: 最初 30002 / 最後 30604 / 最大 30604" "$(has "$OUT" 'CONTEXT: first=30002 last=30604 max=30604')"
ok "Skill の読み込み: 名前・文字数・その時点の文脈" "$(has "$OUT" "SKILL: csharp-test-first chars=$SKILL_LEN context=30503")"
ok "規約の読み込み: nested_memory の文字数" "$(has "$OUT" 'MEMORY: /h/.claude/rules/csharp-common.md chars=400')"
ok "ツールの結果: Bash は 2 回・170 文字 (文字列の content も数える)" "$(has "$OUT" 'TOOL: Bash calls=2 chars=170')"
ok "ツールの結果: Read は 1 回・300 文字" "$(has "$OUT" 'TOOL: Read calls=1 chars=300')"
ok "--timeline なしでは、ターンごとの行を出さない" "$([ "$(has "$OUT" 'T1 ')" = 0 ] && echo 1 || echo 0)"

TL="$(python3 -I "$TR" --timeline "$T/s.jsonl" 2>&1)"
ok "timeline: 1 ターン目" "$(has "$TL" 'T1 context=30002 delta=+30002 tools=Bash')"
ok "timeline: 2 ターン目の増減" "$(has "$TL" 'T2 context=30503 delta=+501 tools=Read')"
ok "timeline: 3 ターン目" "$(has "$TL" 'T3 context=30604 delta=+101 tools=Bash')"

# フォルダを渡すと、いちばん新しい .jsonl を読む
mkdir "$T/d"; cp "$T/s.jsonl" "$T/d/new.jsonl"
OUT2="$(python3 -I "$TR" "$T/d" 2>&1)"
ok "フォルダを渡すと、最新の .jsonl を読む" "$(has "$OUT2" 'TURNS: 3')"

# 失敗の扱い (空のパス・存在しないパスで、例外を出さず、分かる文で終わる)
E1="$(python3 -I "$TR" "" 2>&1)"; R1=$?
ok "空のパスは、終了コード 2 と案内 (Traceback なし)" "$([ "$R1" = 2 ] && [ "$(has "$E1" Traceback)" = 0 ] && [ "$(has "$E1" 'ERROR')" = 1 ] && echo 1 || echo 0)"
E2="$(python3 -I "$TR" "$T/none.jsonl" 2>&1)"; R2=$?
ok "存在しないパスは、終了コード 2" "$([ "$R2" = 2 ] && [ "$(has "$E2" Traceback)" = 0 ] && echo 1 || echo 0)"
mkdir "$T/empty"; E3="$(python3 -I "$TR" "$T/empty" 2>&1)"; R3=$?
ok ".jsonl のないフォルダは、終了コード 2" "$([ "$R3" = 2 ] && [ "$(has "$E3" Traceback)" = 0 ] && echo 1 || echo 0)"
: > "$T/blank.jsonl"; E4="$(python3 -I "$TR" "$T/blank.jsonl" 2>&1)"; R4=$?
ok "assistant の行がないログは、TURNS: 0 で正常終了" "$([ "$R4" = 0 ] && [ "$(has "$E4" 'TURNS: 0')" = 1 ] && echo 1 || echo 0)"

echo "token_report_test: pass=$pass fail=$fail"
[ "$fail" = 0 ]
