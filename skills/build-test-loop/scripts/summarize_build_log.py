#!/usr/bin/env python3
"""summarize_build_log.py - build_error.log (MSBuild の errorsonly 出力) や warnings.log を、AI が読みやすい要約にする。

Usage: summarize_build_log.py <log> [--json <out.json>] [--max-lines 40]
                              [--severity error|warning] [--root <dir>] [--oneline]

やること (読み取り専用。元のログは変えない):
  - 同じ (コード, メッセージ) のエラーを 1 つにまとめ、件数と代表の場所 (最大 3 つ) を出す。
  - 最初に出たエラーの順に並べる (連鎖エラーの原因は、たいてい先頭側にある)。
  - コンパイル (C/D/MSB) とリンク (LNK) を区別して、見出しに件数を出す。
  - 解釈できない行は、最大 5 行だけ「その他」として残す (情報を落とさない)。
  - --json: 同じ内容を JSON でも書く (ログを再読しないで、後から参照できる)。
  - --severity warning: 警告 (`warning Cxxxx`) を、同じ形で要約する (既定は error)。解釈できない行は出さない。
  - --root <dir>: ログ中の Windows のフルパス (`C:` ドライブ形式) を、<dir> からの相対パス (`xxx/yyy.cpp`) にする
    (warnings.log はフルパスのまま。errors は、ウォッチャーが相対化済み)。<dir> の外のパスは、`/` 区切りのまま残す。
  - --oneline: 1 行だけ出す (`warnings: 12 (5 unique): C4244 x5, C4996 x3, ...`)。成功時の、件数の通知用。

BOM / CR / 行頭の "N>" は取り除く。標準出力は最大 --max-lines 行・1 行 400 文字。
解釈できる行 (--severity の種類) が 1 つもなければ、終了コード 3 で何も出さない (呼び出し側が、生のログに切り替える)。
"""
import argparse
import json
import os
import re
import sys
from collections import OrderedDict

DIAG = re.compile(
    r"^(?P<loc>.*?)\s*:\s*(?:fatal\s+)?(?P<sev>error|warning)\s+(?P<code>[A-Za-z]{1,8}\d{2,5})\s*:\s*(?P<msg>.*?)"
    r"(?:\s*\[(?P<proj>[^\]]+)\])?\s*$"
)
LINE_COL = re.compile(r"^(?P<file>.*?)\((?P<line>\d+)(?:,(?P<col>\d+))?\)$")
TRAILER = re.compile(r"^Build failed with exit code:")
MAX_LOCS = 3
MAX_OTHER = 5
MAX_WIDTH = 400


def to_rel(file, root):
    """Windows のフルパスを、root (WSL のパス) からの相対パスにする。root の外は、/ 区切りにするだけ。"""
    f = file.replace("\\", "/")
    if not root:
        return file
    m = re.match(r"^([A-Za-z]):/(.*)$", f)
    wsl = f"/mnt/{m.group(1).lower()}/{m.group(2)}" if m else f
    prefix = root.replace("\\", "/").rstrip("/") + "/"
    return wsl[len(prefix):] if wsl.lower().startswith(prefix.lower()) else f


def parse(text, severity="error", root=None):
    groups = OrderedDict()  # (code, msg) -> dict
    other = []
    total = 0
    for raw in text.splitlines():
        line = re.sub(r"^\s*\d+>", "", raw.replace("﻿", "").rstrip("\r")).strip()
        if not line or TRAILER.match(line):
            continue
        m = DIAG.match(line)
        if not m or m.group("sev") != severity:
            if severity == "error":
                other.append(line)
            continue
        total += 1
        code, msg = m.group("code"), m.group("msg").strip()
        loc = m.group("loc").strip()
        lc = LINE_COL.match(loc)
        file = to_rel(lc.group("file") if lc else loc, root)
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


def render(groups, other, total, max_lines, noun="errors"):
    files = set().union(*[g["files"] for g in groups.values()]) if groups else set()
    n_link = sum(g["count"] for g in groups.values() if kind(g["code"]) == "link")
    head = f"{total} {noun} ({len(groups)} unique) in {len(files)} files"
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
        out = out[: max_lines - 1] + [f"... ({hidden} more summary lines)"]
    return out


def oneline(groups, total, noun, top=3):
    parts = [f"{g['code']} x{g['count']}" for g in list(groups.values())[:top]]
    more = len(groups) - len(parts)
    return f"{noun}: {total} ({len(groups)} unique): " + ", ".join(parts) + (f", ... (+{more} more)" if more > 0 else "")


def to_json(groups, other, total, noun="errors"):
    return {
        noun: total,
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
    ap.add_argument("--severity", choices=["error", "warning"], default="error")
    ap.add_argument("--root")
    ap.add_argument("--oneline", action="store_true")
    a = ap.parse_args()
    noun = a.severity + "s"
    root = os.path.abspath(a.root) if a.root else None
    with open(a.log, encoding="utf-8-sig", errors="replace") as f:
        groups, other, total = parse(f.read(), a.severity, root)
    if not groups:
        return 3
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(to_json(groups, other, total, noun), f, ensure_ascii=False, indent=2)
    if a.oneline:
        sys.stdout.write(oneline(groups, total, noun) + "\n")
    else:
        sys.stdout.write("\n".join(render(groups, other, total, a.max_lines, noun)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
