#!/usr/bin/env python3
"""test_guard.py - 「Red を確認したあとの、テストの改変」を、基準との比較で検出する (読み取り専用。基準のコピーを書く以外は、何も変えない)。

Usage: test_guard.py snapshot <dir>
       test_guard.py check    <dir> [--json <out.json>] [--max-lines 40] [--all]

<dir> はソリューションのフォルダ。テストファイル (下の「対象」) を、`<dir>/.claude-logs/test_guard_base/` にコピーするのが snapshot。
check は、いまのテストファイルを、そのコピーと比べる。**Red を確認した直後に snapshot し、Green に向けた修正のあと (と、報告の前) に check する。**
ユーザーが改変を承認したら、snapshot をやり直す (基準の更新)。これは、鍵ではなく、検知器: 基準のコピーを書き換えられたら、すり抜ける。

対象 (テストファイル): 名前が Test / Tests で終わるフォルダ (MyAppTest/、MyApp.Tests/、MyApp.UITests/ など) の中の .cs .cpp .cc .cxx .h .hpp .csproj .vcxproj .runsettings .settings .props .targets、
  Test*.cpp / Test*.h / *Test.cs / *Tests.cs、どこにある *.runsettings。UiDialogs.cs / UiTestBase.cs (支援ファイル)、生成物、pch / stdafx は除く。
テストは、[TestMethod] (C#) と TEST / TEST_F / TEST_P / TYPED_TEST (C++) を単位に、名前で、基準と突き合わせる。コメントは、無視する。

検査 (コード / 重大度: error = 禁止事項の確実な違反、warning = 疑わしい、review = 正誤を機械では判定できない。ユーザーの確認に回す):
  TMG001 error   テストが消えた (ファイルごとの削除、[TestMethod] を外した場合を含む)
  TMG002 error   [Ignore] / Assert.Inconclusive / GTEST_SKIP / DISABLED_ が増えた。既存のテストに、[TestCategory] が足された
  TMG003 error   テストのアサーションが、ゼロになった
  TMG004 warning テストのアサーションの数が、減った (ヘルパーへの切り出しの場合もある)
  TMG005 error   アサーションを弱めた (AreEqual → AreNotEqual / IsNotNull、EXPECT_EQ → EXPECT_NE、IsTrue(true) など、常に成功する条件の追加)
  TMG006 warning 許容誤差を広げた (EXPECT_NEAR の 3 番目、Assert.AreEqual の delta)
  TMG007 warning [Timeout] の延長・削除、Thread.Sleep / Task.Delay / Sleep の追加、TimeSpan.From...() の待ち時間の延長
  TMG008 warning try/catch の追加 (失敗を飲み込む)、例外を期待するアサーション (ThrowsException / EXPECT_THROW / ExpectedException) の削除
  TMG009 error   テストプロジェクトのファイルで、Compile Remove / ExcludedFromBuild / TestCaseFilter / IsTestProject=false を足した
  TMG010 review  アサーションの行が、書き換わった (期待値・引数の変更。変更前後を並べる)
  TMG011 review  テスト以外の部分 (Fake、ヘルパー、[TestInitialize] / SetUp、フィクスチャ、設定) が変わった
  TMG090 info    追加されたテスト (件数。--all で表示)

終了コード: 0 = error なし / 1 = error あり / 2 = 引数が不正 / 3 = 基準がない・テストファイルがない。
"""
import argparse
import difflib
import hashlib
import json
import os
import re
import shutil
import sys
from collections import Counter
from datetime import datetime

SKIP_DIRS = {".git", ".vs", "bin", "obj", "packages", "node_modules", "TestResults", "ThirdParty", ".claude-logs",
             "x64", "x86", "Win32", "Debug", "Release", "vcpkg_installed", ".vcpkg", "poc"}
TEST_EXTS = {".cs", ".cpp", ".cc", ".cxx", ".h", ".hpp", ".csproj", ".vcxproj", ".runsettings", ".settings", ".props", ".targets"}
CODE_EXTS = {".cs", ".cpp", ".cc", ".cxx", ".h", ".hpp"}
SUPPORT_FILES = {"UiDialogs.cs", "UiTestBase.cs", "pch.h", "pch.cpp", "stdafx.h", "stdafx.cpp", "framework.h", "targetver.h"}
SUPPORT_SUFFIX = (".g.cs", ".g.i.cs", ".designer.cs", "AssemblyInfo.cs", ".AssemblyAttributes.cs")
BASE_REL = os.path.join(".claude-logs", "test_guard_base")
SEV_ORDER = {"error": 0, "warning": 1, "review": 2, "info": 3}


# ---------------------------------------------------------------- 読み込み
def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def decode(b):
    if b.startswith(b"\xef\xbb\xbf"):
        return b[3:].decode("utf-8", "replace")
    if b.startswith((b"\xff\xfe", b"\xfe\xff")):
        return b.decode("utf-16", "replace")
    try:
        return b.decode("utf-8")
    except UnicodeDecodeError:
        try:
            return b.decode("cp932")
        except UnicodeDecodeError:
            return b.decode("latin-1")


def is_test_dir_name(name):
    return name.lower() in ("test", "tests") or bool(re.search(r"Tests?$", name))


def is_test_file(rel):
    parts = rel.replace("\\", "/").split("/")
    name = parts[-1]
    if name in SUPPORT_FILES or name.endswith(SUPPORT_SUFFIX):
        return False
    ext = os.path.splitext(name)[1].lower()
    if ext not in TEST_EXTS:
        return False
    if ext == ".runsettings":
        return True
    if any(is_test_dir_name(p) for p in parts[:-1]):
        return True
    return bool(re.match(r"Test.*\.(cpp|h)$", name) or re.search(r"Tests?\.cs$", name))


def find_test_files(root):
    out = {}
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
        for f in files:
            full = os.path.join(d, f)
            rel = os.path.relpath(full, root).replace("\\", "/")
            if is_test_file(rel):
                out[rel] = full
    return out


# ---------------------------------------------------------------- 字句 (コメントの除去、文字列のスキップ、波括弧の対応)
_CHAR = re.compile(r"'(?:\\[^'\n]{1,8}|[^'\\\n])'")
_RAW_CPP = re.compile(r'"([^()\\ \n]{0,16})\(')


def skip_literal(s, i):
    """i から文字列・文字リテラルが始まるなら、その直後の位置を返す。始まらなければ None。"""
    c = s[i]
    if c == "'":
        m = _CHAR.match(s, i)
        return m.end() if m else None
    if c != '"':
        return None
    n = len(s)
    if s.startswith('"""', i):
        j = s.find('"""', i + 3)
        return n if j < 0 else j + 3
    if i > 0 and s[i - 1] == "R":
        m = _RAW_CPP.match(s, i)
        if m:
            j = s.find(")" + m.group(1) + '"', m.end())
            return n if j < 0 else j + len(m.group(1)) + 2
    verbatim = (i > 0 and s[i - 1] == "@") or s[max(0, i - 2):i] in ("@$", "$@")
    j = i + 1
    while j < n:
        ch = s[j]
        if verbatim:
            if ch == '"':
                if j + 1 < n and s[j + 1] == '"':
                    j += 2
                    continue
                return j + 1
        else:
            if ch == "\\":
                j += 2
                continue
            if ch == '"':
                return j + 1
            if ch == "\n":
                return j
        j += 1
    return n


def strip_comments(s):
    """コメントを空白にする (改行は残す)。文字列の中の // は、コメントではない。"""
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c in "\"'":
            e = skip_literal(s, i)
            if e is not None:
                out.append(s[i:e])
                i = e
                continue
        if c == "/" and i + 1 < n and s[i + 1] == "/":
            j = s.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "*":
            j = s.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", s[i:j]))
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


def match_brace(s, i):
    """s[i] == '{' に対応する '}' の位置の、次を返す (見つからなければ len(s))。"""
    depth, n = 0, len(s)
    while i < n:
        c = s[i]
        if c in "\"'":
            e = skip_literal(s, i)
            if e is not None:
                i = e
                continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def split_args(s, i):
    """s[i] の直後 ('(' の次) から、トップレベルのカンマで区切った引数を返す。"""
    args, cur, depth, n = [], [], 0, len(s)
    while i < n:
        c = s[i]
        if c in "\"'":
            e = skip_literal(s, i)
            if e is not None:
                cur.append(s[i:e])
                i = e
                continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                args.append("".join(cur).strip())
                return args
            depth -= 1
        elif c == "," and depth == 0:
            args.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    return args


# ---------------------------------------------------------------- テストの抽出
CS_TEST = re.compile(r"\[\s*(?:TestMethod|DataTestMethod)\b")
CPP_TEST = re.compile(r"\b(TEST|TEST_F|TEST_P|TYPED_TEST)\s*\(\s*(\w+)\s*,\s*(\w+)\s*\)\s*\{")
ASSERT_CS = re.compile(r"\b((?:Assert|StringAssert|CollectionAssert)\.\w+)\s*[<(]")
ASSERT_CPP = re.compile(r"\b((?:ASSERT|EXPECT)_\w+)\s*\(")
NOT_ASSERTS = {"Assert.Inconclusive", "Assert.Fail"}
TRIVIAL = re.compile(r"Assert\.IsTrue\(\s*true\s*[,)]|Assert\.IsFalse\(\s*false\s*[,)]|(?:EXPECT|ASSERT)_TRUE\(\s*true\s*\)|"
                     r"(?:EXPECT|ASSERT)_FALSE\(\s*false\s*\)|Assert\.AreEqual\(\s*(\w+)\s*,\s*\1\s*[,)]|(?:EXPECT|ASSERT)_EQ\(\s*(\w+)\s*,\s*\2\s*\)")
SLEEP = re.compile(r"\b(?:Thread\.Sleep|Task\.Delay|Sleep|SleepEx|this_thread::sleep_for)\s*\(")
FROM_TIME = re.compile(r"TimeSpan\.From(Seconds|Milliseconds|Minutes)\(\s*(\d+(?:\.\d+)?)")
EXPECT_THROW = re.compile(r"\b(?:Assert\.Throws\w*|(?:EXPECT|ASSERT)_(?:THROW|ANY_THROW|NO_THROW|DEATH))\b")
NEAR = re.compile(r"\b(?:(?:EXPECT|ASSERT)_NEAR|Assert\.AreEqual)\s*\(")
FILE_COUNTS = [("Ignore", re.compile(r"\[\s*Ignore\b")), ("Assert.Inconclusive", re.compile(r"\bAssert\.Inconclusive\b")),
               ("GTEST_SKIP", re.compile(r"\bGTEST_SKIP\b")), ("DISABLED_", re.compile(r"\bDISABLED_\w*"))]


def is_strong(k):
    return (("Equal" in k and "Not" not in k) or k.endswith(("_EQ", "_STREQ", "_NEAR", "_STRCASEEQ")) or
            ("Same" in k and "Not" not in k))


def is_weak(k):
    return "NotEqual" in k or "NotSame" in k or k.endswith("_NE") or k == "Assert.IsNotNull"


def assertions(body):
    kinds = Counter()
    for m in ASSERT_CS.finditer(body):
        if m.group(1) not in NOT_ASSERTS:
            kinds[m.group(1)] += 1
    for m in ASSERT_CPP.finditer(body):
        kinds[m.group(1)] += 1
    return kinds


def tolerances(body):
    out = []
    for m in NEAR.finditer(body):
        a = split_args(body, m.end())
        if len(a) >= 3:
            t = a[2].split(":")[-1].strip().rstrip("fFdDmM")
            try:
                out.append(float(t))
            except ValueError:
                pass
    return out


def wait_ms(body):
    mult = {"Milliseconds": 1, "Seconds": 1000, "Minutes": 60000}
    return sum(float(m.group(2)) * mult[m.group(1)] for m in FROM_TIME.finditer(body))


def extract_tests(code):
    """code (コメントを除いたもの) から、[(キー, 先頭, 末尾, ヘッダー, 本体)] を返す。"""
    found = []
    for m in CS_TEST.finditer(code):
        b = max(code.rfind("}", 0, m.start()), code.rfind(";", 0, m.start()), code.rfind("{", 0, m.start())) + 1
        j, depth, n, body_start, expr = m.end(), 1, len(code), -1, False   # m.end() は、属性の `]` の手前 (`[` が開いたまま)
        while j < n:
            c = code[j]
            if c in "\"'":
                e = skip_literal(code, j)
                if e is not None:
                    j = e
                    continue
            if c in "([":
                depth += 1
            elif c in ")]":
                depth -= 1
            elif depth == 0 and c == "{":
                body_start = j
                break
            elif depth == 0 and c == "=" and code.startswith("=>", j):
                expr = True
                body_start = j
                break
            elif depth == 0 and c == ";":
                break
            j += 1
        if body_start < 0:
            continue
        if expr:
            e = code.find(";", body_start)
            end = n if e < 0 else e + 1
        else:
            end = match_brace(code, body_start)
        header = code[b:body_start]
        stripped = header
        for _ in range(6):
            stripped = re.sub(r"\[[^\[\]]*\]", " ", stripped)
        nm = re.search(r"(\w+)\s*(?:<[^<>]*>)?\s*\(", stripped)
        if not nm:
            continue
        classes = re.findall(r"\b(?:class|struct)\s+(\w+)", code[:m.start()])
        key = (classes[-1] + "." if classes else "") + nm.group(1)
        found.append((key, b, end, header, code[body_start:end]))
    for m in CPP_TEST.finditer(code):
        end = match_brace(code, m.end() - 1)
        found.append((m.group(2) + "." + m.group(3), m.start(), end, "", code[m.end() - 1:end]))
    found.sort(key=lambda t: t[1])
    seen, out = Counter(), []
    for key, b, e, h, body in found:
        seen[key] += 1
        out.append((key if seen[key] == 1 else "%s#%d" % (key, seen[key]), b, e, h, body))
    return out


def analyze(text, ext):
    """-> (tests: {key: info}, residual 行のリスト, ファイル単位の数)"""
    if ext not in CODE_EXTS:
        return {}, None, {}
    code = strip_comments(text.replace("\r\n", "\n").replace("\r", "\n"))
    tests, blank = {}, list(code)
    for key, b, e, header, body in extract_tests(code):
        kinds = assertions(body)
        lines = [re.sub(r"\s+", " ", ln).strip() for ln in body.split("\n")]
        tests[key] = {
            "kinds": kinds, "n_assert": sum(kinds.values()),
            "trivial": len(TRIVIAL.findall(body)),
            "assert_lines": [ln for ln in lines if ASSERT_CS.search(ln) or ASSERT_CPP.search(ln)],
            "sleep": len(SLEEP.findall(body)), "wait_ms": wait_ms(body),
            "catch": len(re.findall(r"\bcatch\b", body)),
            "throws": len(EXPECT_THROW.findall(body)) + len(re.findall(r"\bExpectedException\b", header)),
            "tol": tolerances(body),
            "timeout": (lambda t: int(t.group(1)) if t else None)(re.search(r"\[\s*Timeout\(\s*(\d+)", header)),
            "cats": set(re.findall(r"TestCategory\(\s*\"([^\"]*)\"", header)),
        }
        for k in range(b, min(e, len(blank))):
            if blank[k] != "\n":
                blank[k] = " "
    residual = [re.sub(r"\s+", " ", ln).strip() for ln in "".join(blank).split("\n")]
    residual = [ln for ln in residual if ln]
    fcounts = {name: len(rx.findall(code)) for name, rx in FILE_COUNTS}
    return tests, residual, fcounts


# ---------------------------------------------------------------- snapshot / check
def sha1(b):
    return hashlib.sha1(b).hexdigest()


def cmd_snapshot(root):
    files = find_test_files(root)
    if not files:
        print("test_guard: テストファイルが見つからない (対象の規則は、このスクリプトの先頭を参照)")
        return 3
    base = os.path.join(root, BASE_REL)
    if os.path.isdir(base):
        shutil.rmtree(base, ignore_errors=True)
    manifest = {"created": datetime.now().isoformat(timespec="seconds"), "files": {}}
    for rel, full in sorted(files.items()):
        b = read_bytes(full)
        dst = os.path.join(base, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(b)
        manifest["files"][rel] = sha1(b)
    with open(os.path.join(base, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("test_guard: 基準を作った (テストファイル %d 件) -> %s" % (len(files), BASE_REL))
    return 0


def add(findings, code, sev, file, test, msg, detail=None):
    findings.append({"code": code, "severity": sev, "file": file, "test": test, "message": msg, "detail": detail or []})


CONFIG_RISK = re.compile(r"Compile\s+Remove\s*=|ExcludedFromBuild\s*>\s*true|TestCaseFilter|<IsTestProject>\s*false|<Filter>", re.I)


def compare(base_root, root, manifest):
    base_files = manifest["files"]
    cur_files = find_test_files(root)
    findings, changed = [], []
    base_tests, cur_tests = {}, {}      # key -> (file, info)
    base_res, cur_res, base_cnt, cur_cnt = {}, {}, {}, {}
    base_text = {}
    for rel in base_files:
        p = os.path.join(base_root, rel)
        text = decode(read_bytes(p)) if os.path.exists(p) else ""
        base_text[rel] = text
        t, r, c = analyze(text, os.path.splitext(rel)[1].lower())
        for k, v in t.items():
            base_tests[k] = (rel, v)
        base_res[rel], base_cnt[rel] = r, c
    cur_text = {}
    for rel, full in cur_files.items():
        b = read_bytes(full)
        cur_text[rel] = decode(b)
        t, r, c = analyze(cur_text[rel], os.path.splitext(rel)[1].lower())
        for k, v in t.items():
            cur_tests[k] = (rel, v)
        cur_res[rel], cur_cnt[rel] = r, c
        if rel not in base_files:
            changed.append("A " + rel)
        elif sha1(b) != base_files[rel]:
            changed.append("M " + rel)
    for rel in base_files:
        if rel not in cur_files:
            changed.append("D " + rel)

    # --- ファイル単位
    disabled_now = set()
    for rel in cur_files:
        if rel in base_files and cur_cnt.get(rel):
            for name in FILE_COUNTS:
                d = cur_cnt[rel].get(name[0], 0) - base_cnt[rel].get(name[0], 0)
                if d > 0:
                    rx = dict(FILE_COUNTS)[name[0]]
                    old = set(ln.strip() for ln in base_text[rel].splitlines() if rx.search(ln))
                    new = [ln.strip() for ln in cur_text[rel].splitlines() if rx.search(ln) and ln.strip() not in old]
                    add(findings, "TMG002", "error", rel, None, "`%s` が %d 件増えた" % (name[0], d), new[:3])
    for rel in cur_files:
        if rel in base_files and rel.lower().endswith((".csproj", ".vcxproj", ".runsettings", ".props", ".targets", ".settings")):
            old = base_text[rel].replace("\r\n", "\n").splitlines()
            risky = [ln.strip() for ln in cur_text[rel].replace("\r\n", "\n").splitlines()
                     if CONFIG_RISK.search(ln) and ln not in old]
            if risky:
                add(findings, "TMG009", "error", rel, None, "テストを実行から外す設定が増えた", risky[:3])
            elif cur_text[rel].replace("\r\n", "\n") != base_text[rel].replace("\r\n", "\n"):
                add(findings, "TMG011", "review", rel, None, "プロジェクト・設定ファイルが変わった",
                    [("-" if l[0] == "-" else "+") + l[1:].strip() for l in difflib.unified_diff(old, cur_text[rel].replace("\r\n", "\n").splitlines(), lineterm="", n=0)
                     if l[0] in "+-" and not l.startswith(("+++", "---"))][:6])
    # --- テスト単位
    for k, (rel, b) in sorted(base_tests.items()):
        if k not in cur_tests:
            alt = [c for c in cur_tests if c.endswith("DISABLED_" + k.split(".")[-1]) and c.split(".")[0] == k.split(".")[0]]
            if alt:
                add(findings, "TMG002", "error", rel, k, "テストが DISABLED_ になった (`%s`)" % alt[0])
            else:
                add(findings, "TMG001", "error", rel, k, "テストが消えた" + ("" if rel in cur_files else " (ファイルごと削除)"))
            continue
        crel, c = cur_tests[k]
        where = crel
        if b["n_assert"] > 0 and c["n_assert"] == 0:
            add(findings, "TMG003", "error", where, k, "アサーションが %d → 0 になった" % b["n_assert"])
        elif c["n_assert"] < b["n_assert"]:
            add(findings, "TMG004", "warning", where, k, "アサーションが %d → %d に減った" % (b["n_assert"], c["n_assert"]))
        strong_d = sum(v for q, v in c["kinds"].items() if is_strong(q)) - sum(v for q, v in b["kinds"].items() if is_strong(q))
        weak_d = sum(v for q, v in c["kinds"].items() if is_weak(q)) - sum(v for q, v in b["kinds"].items() if is_weak(q))
        if strong_d < 0 and weak_d > 0:
            add(findings, "TMG005", "error", where, k, "等価の検査が減り、弱い検査 (NotEqual / IsNotNull など) が増えた")
        if c["trivial"] > b["trivial"]:
            add(findings, "TMG005", "error", where, k, "常に成功するアサーション (IsTrue(true) など) が増えた")
        bt, ct = b["tol"], c["tol"]
        if (len(bt) == len(ct) and any(y > x * 1.0000001 for x, y in zip(bt, ct))) or \
           (len(bt) != len(ct) and ct and bt and max(ct) > max(bt) * 1.0000001):
            add(findings, "TMG006", "warning", where, k, "許容誤差が広がった (%s → %s)" % (bt, ct))
        if b["timeout"] is not None and (c["timeout"] is None or c["timeout"] > b["timeout"]):
            add(findings, "TMG007", "warning", where, k, "[Timeout] が延びた・外れた (%s → %s)" % (b["timeout"], c["timeout"]))
        if c["sleep"] > b["sleep"]:
            add(findings, "TMG007", "warning", where, k, "Sleep / Delay が増えた (%d → %d)" % (b["sleep"], c["sleep"]))
        if c["wait_ms"] > b["wait_ms"] + 1e-9:
            add(findings, "TMG007", "warning", where, k, "待ち時間 (TimeSpan.From...) が延びた (%g → %g ms)" % (b["wait_ms"], c["wait_ms"]))
        if c["catch"] > b["catch"]:
            add(findings, "TMG008", "warning", where, k, "catch が増えた (失敗を飲み込む疑い)")
        if c["throws"] < b["throws"]:
            add(findings, "TMG008", "warning", where, k, "例外を期待するアサーションが減った (%d → %d)" % (b["throws"], c["throws"]))
        newcats = c["cats"] - b["cats"]
        if newcats:
            add(findings, "TMG002", "error", where, k, "[TestCategory] が足された (%s)。実行から外れる恐れ" % ", ".join(sorted(newcats)))
        ro, rn = Counter(b["assert_lines"]), Counter(c["assert_lines"])
        gone, new = list((ro - rn).elements()), list((rn - ro).elements())
        if gone and new:
            add(findings, "TMG010", "review", where, k, "アサーションの行が書き換わった (%d 行)" % len(gone),
                ["- " + x for x in gone[:3]] + ["+ " + x for x in new[:3]])
    for rel in cur_files:
        if rel in base_files and base_res.get(rel) is not None and cur_res.get(rel) is not None and base_res[rel] != cur_res[rel]:
            d = [l for l in difflib.unified_diff(base_res[rel], cur_res[rel], lineterm="", n=0) if l[0] in "+-" and not l.startswith(("+++", "---"))]
            add(findings, "TMG011", "review", rel, None, "テスト以外の部分 (Fake / ヘルパー / Setup / フィクスチャなど) が変わった", d[:6])
    added = [k for k in cur_tests if k not in base_tests]
    if added:
        add(findings, "TMG090", "info", "", None, "追加されたテスト %d 件 (名前を変えたテストは、「消えた」と「追加」に分かれる)" % len(added), added[:5])
    return findings, changed


def cmd_check(root, json_out, max_lines, show_all):
    base_root = os.path.join(root, BASE_REL)
    mf = os.path.join(base_root, "manifest.json")
    if not os.path.isfile(mf):
        print("test_guard: 基準がない。先に `test_guard.py snapshot <dir>` を実行する (Red を確認した直後)")
        return 3
    with open(mf, encoding="utf-8") as f:
        manifest = json.load(f)
    findings, changed = compare(base_root, root, manifest)
    findings.sort(key=lambda x: (SEV_ORDER[x["severity"]], x["file"], x["test"] or ""))
    cnt = Counter(x["severity"] for x in findings)
    lines = ["test_guard: error %d / warning %d / review %d (基準 %s、変更されたテストファイル %d 件)" %
             (cnt["error"], cnt["warning"], cnt["review"], manifest.get("created", "?"), len(changed))]
    if changed:
        lines.append("変更されたテストファイル (**報告の先頭に書く**): " + " / ".join(changed[:12]) + (" ..." if len(changed) > 12 else ""))
    for x in findings:
        if x["severity"] == "info" and not show_all:
            continue
        lines.append("%s %-7s %s%s: %s" % (x["code"], x["severity"], x["file"], ("::" + x["test"]) if x["test"] else "", x["message"]))
        lines.extend("    " + d for d in x["detail"])
    if cnt["error"]:
        lines.append("→ error は、ユーザーの明示的な許可なしに、してはいけない変更 (build-test-loop の「止めどき」5)。元に戻すか、止まって確認する。承認されたら、snapshot をやり直す")
    elif cnt["warning"] or cnt["review"]:
        lines.append("→ warning / review は、正当な変更かもしれない。理由を、ユーザーに報告する")
    if len(lines) > max_lines:
        lines = lines[:max_lines] + ["... (%d 行を省略。--max-lines で増やせる)" % (len(lines) - max_lines)]
    print("\n".join(lines))
    if json_out:
        with open(json_out, "w", encoding="utf-8") as f:
            json.dump({"changed": changed, "findings": findings}, f, ensure_ascii=False, indent=1)
    return 1 if cnt["error"] else 0


def main(argv):
    ap = argparse.ArgumentParser(description="テストの改変を検出する")
    ap.add_argument("mode", choices=["snapshot", "check"])
    ap.add_argument("dir")
    ap.add_argument("--json")
    ap.add_argument("--max-lines", type=int, default=40)
    ap.add_argument("--all", action="store_true")
    try:
        a = ap.parse_args(argv)
    except SystemExit:
        return 2
    if not os.path.isdir(a.dir):
        print("test_guard: フォルダがない: %s" % a.dir)
        return 2
    root = os.path.abspath(a.dir)
    return cmd_snapshot(root) if a.mode == "snapshot" else cmd_check(root, a.json, a.max_lines, a.all)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
