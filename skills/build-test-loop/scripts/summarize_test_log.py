#!/usr/bin/env python3
"""summarize_test_log.py - テストの失敗を、AI が読みやすい要約にする (GoogleTest / MSTest 共通)。

Usage: summarize_test_log.py <test_error.log> [--results-dir <dir>] [--root <dir>]
                             [--json <out.json>] [--max-lines 40]

入力は 2 通り (読み取り専用。元のファイルは変えない):
  1. 構造化された結果 (優先): --results-dir に置かれた、テストランナーの機械可読な出力。
       *.xml  GoogleTest の --gtest_output=xml
       *.trx  dotnet test --logger trx (MSTest など、VSTest 系のフレームワーク)
     どちらも、同じ共通の形式 (TestResult) に変換してから、集約する。フレームワークが違っても、出力の形は同じ。
  2. テキスト (従来): test_error.log の GoogleTest の失敗行。構造化された結果がないとき、または解釈できないときの代替。

やること:
  - 失敗したテストごとに、場所 (file(line)) とメッセージを取り出す。
  - **同じメッセージの失敗を 1 つにまとめる** (同じ原因の不具合は、1 つ直すと複数が通ることが多い)。
    まとめた組ごとに、件数・テスト名 (最大 5)・場所 (最大 3) を出す。出現順 (最初に失敗した順)。
  - 見出しに、失敗数とスイートごとの件数。構造化された結果があれば、実行数・成功数・スキップ数も。
  - 解釈できない行 (クラッシュの報告など) は、最大 8 行を「other」として残す (情報を落とさない)。
  - --json: 全テスト名を含む同じ内容を JSON でも書く (標準出力は、名前を省略するため)。
    JSON は、共通の形式 (schema 2。docs/DESIGN.md 4.24)。従来のキー (failed / groups / tests / other) も残している。
  - --root <dir>: 結果中の Windows のフルパスを、<dir> からの相対パス (`xxx/yyy.cpp`) にする。

BOM / CR は取り除く。標準出力は最大 --max-lines 行・1 行 400 文字。
失敗したテストが 1 つも解釈できなければ、終了コード 3 で何も出さない (呼び出し側が、従来の表示に切り替える)。
"""
import argparse
import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import OrderedDict

# ---------- 共通の形式 ----------
# TestResult: {"name": "Suite.Case", "source": "LogicLayerTest.exe", "framework": "gtest"|"mstest",
#              "outcome": "passed"|"failed"|"skipped", "ms": int|None,
#              "failures": [(location|None, message)]}
SCHEMA = 2

EXE = re.compile(r"^=== (?P<exe>.+?)(?::.*)? ===$")
FAILED_TIMED = re.compile(r"^\[\s+FAILED\s+\]\s+(?P<name>[^\s,]+)(?:,.*)?\s*\((?P<ms>\d+) ms\)\s*$")
FAILED_LISTED = re.compile(r"^\[\s+FAILED\s+\]\s+(?P<name>[^\s,]+)\s*$")
FAILED_COUNT = re.compile(r"^\[\s+FAILED\s+\]\s+\d+ tests?, listed below")
NOISE = re.compile(r"^\[(?:={10}|\s+PASSED\s+|\s+SKIPPED\s+|-{10})\]|^\s*\d+ FAILED TESTS?\s*$|^Tests failed$")
# MSVC: "path(49): error: ..."  /  Linux: "path:49: Failure"
LOC = re.compile(r"^(?P<file>.+?)(?:\((?P<l1>\d+)\)|:(?P<l2>\d+)): (?:error: |Failure\b:?\s*)(?P<msg>.*)$")
# テキストのログ中の、クラッシュ・タイムアウトなどの報告 (構造化された結果があっても、情報として残す)
SPECIAL = re.compile(r"^\(no gtest failure lines|^Hung test|^\(no test results|^=== .+: TIMEOUT")
MAX_NAMES = 5
MAX_LOCS = 3
MAX_OTHER = 8
MAX_MSG = 240
MAX_WIDTH = 400


def clean(raw):
    return raw.replace("﻿", "").rstrip("\r").rstrip()


def to_rel(file, root):
    """Windows のフルパスを、root (WSL のパス) からの相対パスにする。root の外は、/ 区切りにするだけ。"""
    if not file:
        return file
    f = file.replace("\\", "/")
    if not root:
        return f
    m = re.match(r"^([A-Za-z]):/(.*)$", f)
    wsl = f"/mnt/{m.group(1).lower()}/{m.group(2)}" if m else f
    prefix = root.replace("\\", "/").rstrip("/") + "/"
    return wsl[len(prefix):] if wsl.lower().startswith(prefix.lower()) else f


# ---------- 構造化された結果 (1): GoogleTest XML ----------
def _ms(seconds):
    try:
        return int(round(float(seconds) * 1000))
    except (TypeError, ValueError):
        return None


def parse_gtest_xml(path, root=None):
    """GoogleTest の XML → [TestResult]。<failure message="file:line&#10;メッセージ"> の形。"""
    tree = ET.parse(path)
    source = os.path.splitext(os.path.basename(path))[0]
    out = []
    for case in tree.getroot().iter("testcase"):
        cls = case.get("classname") or ""
        name = f"{cls}.{case.get('name')}" if cls else (case.get("name") or "?")
        failures = []
        for fl in case.findall("failure"):
            text = (fl.text or "").strip() or (fl.get("message") or "")
            lines = [clean(x) for x in text.splitlines() if x.strip()]
            loc = None
            if lines:
                m = re.match(r"^(?P<file>.+?):(?P<line>\d+)$", lines[0])
                if m:  # 先頭行が、"file:line" (GoogleTest の XML の形式)
                    loc = f"{to_rel(m.group('file'), root)}({m.group('line')})"
                    lines = lines[1:]
            failures.append((loc, " | ".join(s.strip() for s in lines) or "(no message)"))
        if failures:
            outcome = "failed"
        elif case.get("result") == "skipped" or case.get("status") == "notrun" or case.find("skipped") is not None:
            outcome = "skipped"
        else:
            outcome = "passed"
        out.append({"name": name, "source": source, "framework": "gtest", "outcome": outcome,
                    "ms": _ms(case.get("time")), "failures": failures})
    return out


# ---------- 構造化された結果 (2): trx (MSTest など) ----------
TRX_LOC = [
    re.compile(r"^.*\s(?:in|場所)\s+(?P<file>.+?):(?:line|行)\s+(?P<line>\d+)\s*$"),
]


def _local(tag):
    return tag.rsplit("}", 1)[-1]


def _dur_ms(d):
    m = re.match(r"^(\d+):(\d+):(\d+(?:\.\d+)?)$", d or "")
    return int(round((int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))) * 1000)) if m else None


def parse_trx(path, root=None):
    """trx (VSTest の結果) → [TestResult]。名前は、クラス名 + メソッド名。場所は、スタックトレースの、最初の、ファイルつきの行。"""
    tree = ET.parse(path)
    source = os.path.splitext(os.path.basename(path))[0]
    defs = {}  # testId -> フルネーム
    for el in tree.getroot().iter():
        if _local(el.tag) == "UnitTest":
            tid = el.get("id")
            method = next((c for c in el.iter() if _local(c.tag) == "TestMethod"), None)
            if tid and method is not None and method.get("className"):
                defs[tid] = method.get("className").split(",")[0].strip() + "." + (method.get("name") or el.get("name"))
    out = []
    for el in tree.getroot().iter():
        if _local(el.tag) != "UnitTestResult":
            continue
        test_name = el.get("testName") or ""
        name = defs.get(el.get("testId")) or test_name or "?"
        method = name.rsplit(".", 1)[-1]
        if test_name.startswith(method) and len(test_name) > len(method):
            name += test_name[len(method):]  # データ行つきのテスト: "Method (1,2)" の、括弧の部分を残す
        oc = (el.get("outcome") or "").lower()
        failures = []
        if oc in ("failed", "timeout", "aborted", "error"):
            outcome = "failed"
            msg, stack = "", ""
            for c in el.iter():
                t = _local(c.tag)
                if t == "Message" and not msg:
                    msg = (c.text or "").strip()
                elif t == "StackTrace" and not stack:
                    stack = (c.text or "").strip()
            loc = None
            for ln in stack.splitlines():
                m = TRX_LOC[0].search(ln.rstrip("\r"))
                if m:
                    loc = f"{to_rel(m.group('file'), root)}({m.group('line')})"
                    break
            parts = [clean(x).strip() for x in msg.splitlines() if x.strip()]
            failures.append((loc, " | ".join(parts) or f"({oc})"))
        elif oc in ("passed", "passedbutrunagain"):
            outcome = "passed"
        else:  # NotExecuted / Inconclusive / Pending など
            outcome = "skipped"
        out.append({"name": name, "source": source, "framework": "mstest", "outcome": outcome,
                    "ms": _dur_ms(el.get("duration")), "failures": failures})
    return out


def trx_run_errors(path):
    """trx の、実行全体のエラー (テストホストのクラッシュなど)。テストの失敗とは別に、other に残す。"""
    msgs = []
    try:
        for el in ET.parse(path).getroot().iter():
            if _local(el.tag) == "RunInfo" and (el.get("outcome") or "").lower() in ("error", "failed"):
                t = next((c.text for c in el.iter() if _local(c.tag) == "Text" and c.text), None)
                if t:
                    msgs.append("run error: " + " | ".join(x.strip() for x in t.splitlines() if x.strip()))
    except ET.ParseError:
        pass
    return msgs


def load_structured(results_dir, root=None):
    """results_dir の *.xml / *.trx を、すべて読む。戻り値: ([TestResult], [other 行])。読めないファイルは、other に残す。"""
    results, other = [], []
    if not results_dir or not os.path.isdir(results_dir):
        return results, other
    for p in sorted(glob.glob(os.path.join(results_dir, "*.xml")) + glob.glob(os.path.join(results_dir, "*.trx"))):
        try:
            if p.endswith(".trx"):
                results += parse_trx(p, root)
                other += trx_run_errors(p)
            else:
                results += parse_gtest_xml(p, root)
        except (ET.ParseError, OSError) as e:
            other.append(f"(could not read {os.path.basename(p)}: {e})")
    return results, other


# ---------- テキスト (従来): GoogleTest の失敗行 ----------
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


def parse_text(text):
    tests = OrderedDict()  # name -> TestResult
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
            t = tests.setdefault(name, {"name": name, "source": exe, "framework": "gtest", "outcome": "failed",
                                        "ms": int(m.group("ms")), "failures": []})
            t["failures"] = split_failures(pending)
            pending = []
            continue
        if FAILED_COUNT.match(line):
            continue
        m = FAILED_LISTED.match(line)
        if m:  # "listed below" の再掲。初出なら、詳細なしで登録
            tests.setdefault(m.group("name"), {"name": m.group("name"), "source": exe, "framework": "gtest",
                                               "outcome": "failed", "ms": None, "failures": []})
            continue
        if NOISE.match(line):
            continue
        if line.startswith("(no gtest failure lines") or line.startswith("Hung test"):
            other.append(line)
            continue
        pending.append(line)
    other.extend(pending)  # 最後の FAILED 行に続かなかった行 (クラッシュ時の出力など)
    return list(tests.values()), other


def special_lines(text):
    """構造化された結果を使うとき、テキストのログから、クラッシュ・タイムアウトの報告だけを、other に残す。"""
    out = []
    for raw in text.splitlines():
        line = clean(raw)
        if SPECIAL.match(line):
            out.append(line)
    return out


# ---------- 集約と出力 ----------
def group(failed):
    groups = OrderedDict()
    for t in failed:
        msg = " || ".join(m for _, m in t["failures"]) or "(no failure details in log)"
        g = groups.setdefault(msg, {"message": msg, "tests": [], "locations": []})
        g["tests"].append(t["name"])
        for loc, _ in t["failures"]:
            if loc and loc not in g["locations"]:
                g["locations"].append(loc)
    return list(groups.values())


def totals(results):
    c = {"total": len(results), "passed": 0, "failed": 0, "skipped": 0}
    for r in results:
        c[r["outcome"]] += 1
    return c


def render(failed, counts, groups, other, max_lines):
    suites = OrderedDict()
    for t in failed:
        s = t["name"].rsplit(".", 1)[0] if t["framework"] == "mstest" else t["name"].split(".")[0]
        suites[s] = suites.get(s, 0) + 1
    top = list(suites.items())[:5]
    head = f"{len(failed)} failed tests in {len(suites)} suites: " + ", ".join(f"{s} {c}" for s, c in top)
    if len(suites) > len(top):
        head += f", ... (+{len(suites) - len(top)} suites)"
    if counts:
        head += f"  [ran {counts['total']}: passed {counts['passed']} / failed {counts['failed']} / skipped {counts['skipped']}]"
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


def to_json(results, failed, groups, other, structured):
    sources = OrderedDict()
    for r in results:
        s = sources.setdefault(r["source"], {"source": r["source"], "framework": r["framework"],
                                             "total": 0, "passed": 0, "failed": 0, "skipped": 0})
        s["total"] += 1
        s[r["outcome"]] += 1
    return {
        "schema": SCHEMA,
        "structured": structured,
        "totals": totals(results) if structured else None,
        "sources": list(sources.values()),
        "failed": len(failed),
        "groups": [{"message": g["message"], "count": len(g["tests"]), "tests": g["tests"],
                    "locations": g["locations"]} for g in groups],
        "tests": [{"name": t["name"], "source": t["source"], "framework": t["framework"], "exe": t["source"],
                   "ms": t["ms"], "failures": [{"location": l, "message": m} for l, m in t["failures"]]}
                  for t in failed],
        "other": other,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--results-dir")
    ap.add_argument("--root")
    ap.add_argument("--json")
    ap.add_argument("--max-lines", type=int, default=40)
    a = ap.parse_args()
    root = os.path.abspath(a.root) if a.root else None
    try:
        with open(a.log, encoding="utf-8-sig", errors="replace") as f:
            text = f.read()
    except OSError:
        text = ""

    results, other = load_structured(a.results_dir, root)
    structured = bool(results)
    if structured:
        failed = [r for r in results if r["outcome"] == "failed"]
        other = other + special_lines(text)
    else:
        failed, other = parse_text(text)
        results = failed
    if not failed:
        return 3
    groups = group(failed)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(to_json(results, failed, groups, other, structured), f, ensure_ascii=False, indent=2)
    counts = totals(results) if structured else None
    sys.stdout.write("\n".join(render(failed, counts, groups, other, a.max_lines)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
