#!/usr/bin/env python3
"""changed_lines.py - git の差分から、ブレークポイントを置く行 (追記・変更したコードの行) を選ぶ。

Usage: changed_lines.py <solution_dir> [--max N] [--names]
  既定: `<相対パス>:<行>` を 1 行ずつ出す (1 つの変更のかたまり (hunk) につき、コードの行を 1 つ。最大 N 件、既定 10)。
        ソースでないファイル、コードの行がない hunk (コメント・空行・波かっこだけ)、削除だけの hunk は、飛ばす。
        追跡されていない新規ファイルは、行を選ばず、`NEW_FILE: <相対パス>` を出す (どの行か決められない。Claude が --break で指定する)。
        N を超えたら、最後に `TRUNCATED: <件数>` を出す。
  --names: 変更・新規のファイルの相対パスだけを出す (VS で開き直す対象の選定用)。
終了コード: 0 = 成功 (0 件でもよい) / 2 = 引数の誤り / 3 = git のリポジトリではない・git がない
"""
import os
import re
import subprocess
import sys

SOURCE_EXT = {".cpp", ".cc", ".cxx", ".c", ".h", ".hpp", ".hxx", ".cs", ".vb"}
SKIP_PREFIX = ("//", "/*", "*", "*/", "#", "using ", "namespace ", "[")
DECL_RE = re.compile(r"^(public|private|protected|internal|static|sealed|abstract|partial|class|struct|enum|interface)\b[^=(;]*$")
USAGE = "usage: changed_lines.py <solution_dir> [--max N] [--names]"


def git(d, *args):
    try:
        r = subprocess.run(["git", "-c", "core.quotepath=false", "-C", d, *args],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
    except OSError:
        return None
    return r.stdout if r.returncode == 0 else None


def is_code(line):
    t = line.strip()
    if not t or t in ("else", "else {", "} else {", "try", "try {", "finally", "default:"):
        return False
    if re.fullmatch(r"[{};()\s]*", t):
        return False
    if t.startswith(SKIP_PREFIX):
        return False
    if re.fullmatch(r"(public|private|protected|case .*|default)\s*:", t):
        return False
    if DECL_RE.match(t):
        return False
    return True


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(USAGE, file=sys.stderr)
        return 2
    d = argv[0]
    mx, names = 10, False
    i = 1
    while i < len(argv):
        if argv[i] == "--max" and i + 1 < len(argv) and argv[i + 1].isdigit():
            mx = int(argv[i + 1])
            i += 2
        elif argv[i] == "--names":
            names = True
            i += 1
        else:
            print(USAGE, file=sys.stderr)
            return 2
    if not os.path.isdir(d):
        print("not a directory: " + d, file=sys.stderr)
        return 2
    if git(d, "rev-parse", "--is-inside-work-tree") is None:
        print("NOT_A_REPO")
        return 3
    # HEAD がまだない (最初のコミット前) ときは、差分を取れない。新規ファイルとして扱う
    has_head = git(d, "rev-parse", "--verify", "-q", "HEAD") is not None
    untracked = [p for p in (git(d, "ls-files", "-o", "--exclude-standard", "--", ".") or "").splitlines() if p]
    if names:
        files = (git(d, "diff", "--name-only", "--relative", "HEAD", "--", ".") or "").splitlines() if has_head else []
        for p in files + untracked:
            print(p)
        return 0
    results, total = [], 0
    if has_head:
        diff = git(d, "diff", "-U0", "--no-color", "--no-ext-diff", "--relative", "HEAD", "--", ".") or ""
        path, ln, chosen = None, 0, True
        for raw in diff.splitlines():
            if raw.startswith("+++ "):
                path = raw[4:]
                path = None if path == "/dev/null" else (path[2:] if path.startswith("b/") else path)
                if path and os.path.splitext(path)[1].lower() not in SOURCE_EXT:
                    path = None
            elif raw.startswith("@@"):
                m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", raw)
                ln = int(m.group(1)) if m else 0
                chosen = bool(m and m.group(2) == "0")   # 削除だけの hunk は、選ばない
            elif raw.startswith("+") and not raw.startswith("+++") and path:
                if not chosen and is_code(raw[1:]):
                    chosen = True
                    total += 1
                    if len(results) < mx:
                        results.append("%s:%d" % (path, ln))
                ln += 1
    for p in untracked:
        if os.path.splitext(p)[1].lower() in SOURCE_EXT:
            results.append("NEW_FILE: " + p)
    for r in results:
        print(r)
    if total > mx:
        print("TRUNCATED: %d" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
