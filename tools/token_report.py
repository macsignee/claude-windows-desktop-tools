#!/usr/bin/env python3
"""token_report.py - Claude Code のセッションのログ (.jsonl) から、Token の使い方を集計する。

使い方:
    python3 -I tools/token_report.py [--timeline] <セッションの .jsonl | .jsonl のあるフォルダ>

  ログは ~/.claude/projects/<フォルダ名>/<セッション ID>.jsonl にある (フォルダ名は、作業フォルダの / を - にしたもの)。
  フォルダを渡すと、いちばん新しい .jsonl を読む。

出力 (1 行 1 項目。grep しやすい形):
    TURNS:    ターン数 (assistant のメッセージ。同じ message.id の行は、1 つと数える)
    TOTAL:    input / cache_creation / cache_read / output の合計
    CONTEXT:  1 ターンの文脈の大きさ (input + cache_read + cache_creation) の、最初・最後・最大
    SKILL:    Skill の読み込み (本文の文字数と、その時点の文脈の大きさ)
    MEMORY:   規約 (rules) の読み込み (nested_memory の文字数)
    TOOL:     ツールの結果の、回数と文字数 (ツール名ごと)
    --timeline: ターンごとの文脈と増減、使ったツール

終了コード: 0 正常 / 2 引数・ファイルの誤り
"""
import json
import os
import sys

SKILL_PREFIX = 'Base directory for this skill:'


def find_log(path):
    if not path:
        raise ValueError('ログのパスが空です。~/.claude/projects/<フォルダ名>/ の .jsonl か、そのフォルダを渡してください')
    if os.path.isdir(path):
        logs = [os.path.join(path, n) for n in os.listdir(path) if n.endswith('.jsonl')]
        if not logs:
            raise ValueError('.jsonl がありません: ' + path)
        return max(logs, key=os.path.getmtime)
    if not os.path.isfile(path):
        raise ValueError('ファイルがありません: ' + path)
    return path


def read_rows(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            try:
                row = json.loads(line)
            except ValueError:
                continue                      # 壊れた行は、読み飛ばす
            if isinstance(row, dict):
                yield row


def text_len(content):
    """tool_result の content (文字列、または text ブロックの配列) の文字数。画像は数えない。"""
    if isinstance(content, str):
        return len(content)
    if isinstance(content, list):
        return sum(len(b.get('text', '')) for b in content if isinstance(b, dict) and b.get('type') == 'text')
    return 0


def blocks_of(row):
    msg = row.get('message')
    content = msg.get('content') if isinstance(msg, dict) else None
    return content if isinstance(content, list) else []


def analyze(rows):
    turns = []                  # [{'id', 'context', 'tools': [名前...]}]
    by_id = {}
    totals = {'input': 0, 'cache_creation': 0, 'cache_read': 0, 'output': 0}
    tool_names = {}             # tool_use の id → 名前
    tools = {}                  # 名前 → [回数, 文字数]
    skills, memories = [], []

    for row in rows:
        kind = row.get('type')
        if kind == 'assistant':
            msg = row.get('message') or {}
            mid = msg.get('id')
            turn = by_id.get(mid) if mid else None
            if turn is None:
                u = msg.get('usage') or {}
                ui, cc, cr = (u.get('input_tokens') or 0), (u.get('cache_creation_input_tokens') or 0), (u.get('cache_read_input_tokens') or 0)
                totals['input'] += ui
                totals['cache_creation'] += cc
                totals['cache_read'] += cr
                totals['output'] += u.get('output_tokens') or 0
                turn = {'context': ui + cr + cc, 'tools': []}
                turns.append(turn)
                if mid:
                    by_id[mid] = turn
            for b in blocks_of(row):
                if isinstance(b, dict) and b.get('type') == 'tool_use':
                    tool_names[b.get('id')] = b.get('name', '?')
                    turn['tools'].append(b.get('name', '?'))
        elif kind == 'user':
            context_now = turns[-1]['context'] if turns else 0
            for b in blocks_of(row):
                if not isinstance(b, dict):
                    continue
                if b.get('type') == 'tool_result':
                    name = tool_names.get(b.get('tool_use_id'), '?')
                    entry = tools.setdefault(name, [0, 0])
                    entry[0] += 1
                    entry[1] += text_len(b.get('content'))
                elif b.get('type') == 'text' and b.get('text', '').startswith(SKILL_PREFIX):
                    text = b['text']
                    first = text.split('\n', 1)[0]
                    name = first[len(SKILL_PREFIX):].strip().replace('\\', '/').rstrip('/').rsplit('/', 1)[-1]
                    skills.append((name, len(text), context_now))
        elif kind == 'attachment':
            a = row.get('attachment') or {}
            if a.get('type') == 'nested_memory':
                inner = a.get('content')
                body = inner.get('content', '') if isinstance(inner, dict) else inner
                memories.append((a.get('path', '?'), len(body) if isinstance(body, str) else 0))

    return {'turns': turns, 'totals': totals, 'tools': tools, 'skills': skills, 'memories': memories}


def render(result, timeline):
    turns, t = result['turns'], result['totals']
    out = ['TURNS: %d' % len(turns),
           'TOTAL: input=%d cache_creation=%d cache_read=%d output=%d' % (t['input'], t['cache_creation'], t['cache_read'], t['output'])]
    if turns:
        ctx = [x['context'] for x in turns]
        out.append('CONTEXT: first=%d last=%d max=%d' % (ctx[0], ctx[-1], max(ctx)))
    for name, chars, context in result['skills']:
        out.append('SKILL: %s chars=%d context=%d' % (name, chars, context))
    for path, chars in result['memories']:
        out.append('MEMORY: %s chars=%d' % (path, chars))
    for name, (calls, chars) in sorted(result['tools'].items(), key=lambda kv: -kv[1][1]):
        out.append('TOOL: %s calls=%d chars=%d' % (name, calls, chars))
    if timeline:
        prev = 0
        for i, x in enumerate(turns, 1):
            out.append('T%d context=%d delta=%+d tools=%s' % (i, x['context'], x['context'] - prev, ','.join(x['tools']) or '-'))
            prev = x['context']
    return '\n'.join(out)


def main(argv):
    args = [a for a in argv if a != '--timeline']
    timeline = len(args) != len(argv)
    if len(args) != 1:
        print('ERROR: 使い方: token_report.py [--timeline] <セッションの .jsonl | フォルダ>', file=sys.stderr)
        return 2
    try:
        path = find_log(args[0])
    except ValueError as e:
        print('ERROR: ' + str(e), file=sys.stderr)
        return 2
    print(render(analyze(read_rows(path)), timeline))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
