#!/usr/bin/env python3
"""summarize_build_log.py - build_error.log (MSBuild の errorsonly 出力) を、AI が読みやすい要約にする。

Usage: summarize_build_log.py <build_error.log> [--json <out.json>] [--max-lines 40]

やること (読み取り専用。元のログは変えない):
  - 同じ (コード, メッセージ) のエラーを 1 つにまとめ、件数と代表の場所 (最大 3 つ) を出す。
  - 最初に出たエラーの順に並べる (連鎖エラーの原因は、たいてい先頭側にある)。
  - コンパイル (C/D/MSB) とリンク (LNK) を区別して、見出しに件数を出す。
  - 解釈できない行は、最大 5 行だけ「その他」として残す (情報を落とさない)。
  - --json: 同じ内容を JSON でも書く (ログを再読しないで、後から参照できる)。

BOM / CR / 行頭の "N>" は取り除く。標準出力は最大 --max-lines 行・1 行 400 文字。
解釈できるエラー行が 1 つもなければ、終了コード 3 で何も出さない (呼び出し側が、生のログに切り替える)。
"""
import argparse
import json
import re
import sys
from collections import OrderedDict

DIAG = re.compile(
    r"^(?P<loc>.*?)\s*:\s*(?:fatal\s+)?(?P<sev>error|warning)\s+(?P<code>[A-Za-z]{1,4}\d{2,5})\s*:\s*(?P<msg>.*?)"
    r"(?:\s*\[(?P<proj>[^\]]+)\])?\s*$"
)
LINE_COL = re.compile(r"^(?P<file>.*?)\((?P<line>\d+)(?:,(?P<col>\d+))?\)$")
TRAILER = re.compile(r"^Build failed with exit code:")
MAX_LOCS = 3
MAX_OTHER = 5
MAX_WIDTH = 400


def parse(text):
    groups = OrderedDict()  # (code, msg) -> dict
    other = []
    total = 0
    for raw in text.splitlines():
        line = re.sub(r"^\s*\d+>", "", raw.replace("﻿", "").rstrip("\r")).strip()
        if not line or TRAILER.match(line):
            continue
        m = DIAG.match(line)
        if not m or m.group("sev") != "error":
            other.append(line)
            continue
        total += 1
        code, msg = m.group("code"), m.group("msg").strip()
        loc = m.group("loc").strip()
        lc = LINE_COL.match(loc)
        file = lc.group("file") if lc else loc
        pos = f"{file}({lc.group('line')}" + (f",{lc.group('col')})" if lc and lc.group("col") else ")") if lc else file
        proj = m.group("proj")
        proj = re.split(r"[\\/]", proj)[-1] if proj else None
        g = groups.setdefault((code, msg), {"code": code, "message": msg, "count": 0,
                                            "locations": [], "files": set(), "projects": set()})
        g["count"] += 1
        g["files"].add(file)
        if proj:
            g["projects"].add(proj)
        if pos not in g["locations"]:
            g["locations"].append(pos)
    return groups, other, total


def kind(code):
    return "link" if code.startswith("LNK") else "compile"


def render(groups, other, total, max_lines):
    files = set().union(*[g["files"] for g in groups.values()]) if groups else set()
    n_link = sum(g["count"] for g in groups.values() if kind(g["code"]) == "link")
    head = f"{total} errors ({len(groups)} unique) in {len(files)} files"
    if n_link:
        head += f"; compile {total - n_link} / link {n_link}"
    out = [head]
    for i, g in enumerate(groups.values(), 1):
        times = f"  x{g['count']}" if g["count"] > 1 else ""
        out.append(f"[{i}] {g['code']} {g['message']}{times}")
        locs = g["locations"][:MAX_LOCS]
        more = len(g["locations"]) - len(locs)
        out.append("    " + "  ".join(locs) + (f"  (+{more} more)" if more > 0 else ""))
    if other:
        out.append("other:")
        out.extend("    " + o for o in other[:MAX_OTHER])
        if len(other) > MAX_OTHER:
            out.append(f"    (+{len(other) - MAX_OTHER} more lines)")
    out = [s[:MAX_WIDTH] for s in out]
    if len(out) > max_lines:
        hidden = len(out) - (max_lines - 1)
        out = out[: max_lines - 1] + [f"... ({hidden} more summary lines; see build_error.log)"]
    return out


def to_json(groups, other, total):
    return {
        "errors": total,
        "unique": len(groups),
        "groups": [
            {"code": g["code"], "kind": kind(g["code"]), "message": g["message"], "count": g["count"],
             "locations": g["locations"], "projects": sorted(g["projects"])}
            for g in groups.values()
        ],
        "other": other,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--json")
    ap.add_argument("--max-lines", type=int, default=40)
    a = ap.parse_args()
    with open(a.log, encoding="utf-8-sig", errors="replace") as f:
        groups, other, total = parse(f.read())
    if not groups:
        return 3
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(to_json(groups, other, total), f, ensure_ascii=False, indent=2)
    sys.stdout.write("\n".join(render(groups, other, total, a.max_lines)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
