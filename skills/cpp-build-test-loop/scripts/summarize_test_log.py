#!/usr/bin/env python3
"""summarize_test_log.py - test_error.log (GoogleTest の失敗行) を、AI が読みやすい要約にする。

Usage: summarize_test_log.py <test_error.log> [--json <out.json>] [--max-lines 40]

やること (読み取り専用。元のログは変えない):
  - 失敗したテストごとに、失敗の場所 (file(line)) とメッセージ (Expected / Which is ...) を取り出す。
  - **同じメッセージの失敗を 1 つにまとめる** (同じ原因の不具合は、1 つ直すと複数が通ることが多い)。
    まとめた組ごとに、件数・テスト名 (最大 5)・場所 (最大 3) を出す。出現順 (最初に失敗した順)。
  - 見出しに、失敗数とスイートごとの件数。
  - 解釈できない行 (クラッシュの報告など) は、最大 8 行を「other」として残す (情報を落とさない)。
  - --json: 全テスト名を含む同じ内容を JSON でも書く (標準出力は、名前を省略するため)。

BOM / CR は取り除く。標準出力は最大 --max-lines 行・1 行 400 文字。
失敗したテストが 1 つも解釈できなければ、終了コード 3 で何も出さない (呼び出し側が、従来の表示に切り替える)。
"""
import argparse
import json
import re
import sys
from collections import OrderedDict

EXE = re.compile(r"^=== (?P<exe>.+?)(?::.*)? ===$")
FAILED_TIMED = re.compile(r"^\[\s+FAILED\s+\]\s+(?P<name>[^\s,]+)(?:,.*)?\s*\((?P<ms>\d+) ms\)\s*$")
FAILED_LISTED = re.compile(r"^\[\s+FAILED\s+\]\s+(?P<name>[^\s,]+)\s*$")
FAILED_COUNT = re.compile(r"^\[\s+FAILED\s+\]\s+\d+ tests?, listed below")
NOISE = re.compile(r"^\[(?:={10}|\s+PASSED\s+|\s+SKIPPED\s+|-{10})\]|^\s*\d+ FAILED TESTS?\s*$|^Tests failed$")
# MSVC: "path(49): error: ..."  /  Linux: "path:49: Failure"
LOC = re.compile(r"^(?P<file>.+?)(?:\((?P<l1>\d+)\)|:(?P<l2>\d+)): (?:error: |Failure\b:?\s*)(?P<msg>.*)$")
MAX_NAMES = 5
MAX_LOCS = 3
MAX_OTHER = 8
MAX_MSG = 240
MAX_WIDTH = 400


def clean(raw):
    return raw.replace("﻿", "").rstrip("\r").rstrip()


def split_failures(lines):
    """pending 行 → [(場所 or None, メッセージ)]。"""
    out = []
    for ln in lines:
        m = LOC.match(ln)
        if m:
            out.append([f"{m.group('file')}({m.group('l1') or m.group('l2')})", [m.group("msg").strip()]])
        elif out:
            out[-1][1].append(ln.strip())
        else:
            out.append([None, [ln.strip()]])
    return [(loc, " | ".join(p for p in parts if p)) for loc, parts in out]


def parse(text):
    tests = OrderedDict()  # name -> dict
    other = []
    pending = []
    exe = None
    for raw in text.splitlines():
        line = clean(raw)
        if not line.strip():
            continue
        m = EXE.match(line)
        if m:
            exe = m.group("exe")
            pending = []
            continue
        m = FAILED_TIMED.match(line)
        if m:
            name = m.group("name")
            t = tests.setdefault(name, {"name": name, "exe": exe, "ms": int(m.group("ms")), "failures": []})
            t["failures"] = split_failures(pending)
            pending = []
            continue
        if FAILED_COUNT.match(line):
            continue
        m = FAILED_LISTED.match(line)
        if m:  # "listed below" の再掲。初出なら、詳細なしで登録
            tests.setdefault(m.group("name"), {"name": m.group("name"), "exe": exe, "ms": None, "failures": []})
            continue
        if NOISE.match(line):
            continue
        if line.startswith("(no gtest failure lines") or line.startswith("Hung test"):
            other.append(line)
            continue
        pending.append(line)
    other.extend(pending)  # 最後の FAILED 行に続かなかった行 (クラッシュ時の出力など)
    return tests, other


def group(tests):
    groups = OrderedDict()
    for t in tests.values():
        msg = " || ".join(m for _, m in t["failures"]) or "(no failure details in log)"
        g = groups.setdefault(msg, {"message": msg, "tests": [], "locations": []})
        g["tests"].append(t["name"])
        for loc, _ in t["failures"]:
            if loc and loc not in g["locations"]:
                g["locations"].append(loc)
    return list(groups.values())


def render(tests, groups, other, max_lines):
    suites = OrderedDict()
    for n in tests:
        suites[n.split(".")[0]] = suites.get(n.split(".")[0], 0) + 1
    top = list(suites.items())[:5]
    head = f"{len(tests)} failed tests in {len(suites)} suites: " + ", ".join(f"{s} {c}" for s, c in top)
    if len(suites) > len(top):
        head += f", ... (+{len(suites) - len(top)} suites)"
    out = [head]
    for i, g in enumerate(groups, 1):
        n = len(g["tests"])
        msg = g["message"] if len(g["message"]) <= MAX_MSG else g["message"][: MAX_MSG - 3] + "..."
        out.append(f"[{i}]{f' x{n}' if n > 1 else ''}  {msg}")
        names = g["tests"][:MAX_NAMES]
        more = n - len(names)
        out.append("    tests: " + ", ".join(names) + (f"  (+{more} more)" if more > 0 else ""))
        if g["locations"]:
            locs = g["locations"][:MAX_LOCS]
            more = len(g["locations"]) - len(locs)
            out.append("    at: " + "  ".join(locs) + (f"  (+{more} more)" if more > 0 else ""))
    if other:
        out.append("other:")
        out.extend("    " + o for o in other[:MAX_OTHER])
        if len(other) > MAX_OTHER:
            out.append(f"    (+{len(other) - MAX_OTHER} more lines)")
    out = [s[:MAX_WIDTH] for s in out]
    if len(out) > max_lines:
        hidden = len(out) - (max_lines - 1)
        out = out[: max_lines - 1] + [f"... ({hidden} more summary lines; see test_error.log)"]
    return out


def to_json(tests, groups, other):
    return {
        "failed": len(tests),
        "groups": [{"message": g["message"], "count": len(g["tests"]), "tests": g["tests"],
                    "locations": g["locations"]} for g in groups],
        "tests": [{"name": t["name"], "exe": t["exe"], "ms": t["ms"],
                   "failures": [{"location": l, "message": m} for l, m in t["failures"]]} for t in tests.values()],
        "other": other,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--json")
    ap.add_argument("--max-lines", type=int, default=40)
    a = ap.parse_args()
    with open(a.log, encoding="utf-8-sig", errors="replace") as f:
        tests, other = parse(f.read())
    if not tests:
        return 3
    groups = group(tests)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(to_json(tests, groups, other), f, ensure_ascii=False, indent=2)
    sys.stdout.write("\n".join(render(tests, groups, other, a.max_lines)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
