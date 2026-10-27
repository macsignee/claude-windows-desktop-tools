#!/usr/bin/env python3
"""winforms_check.py - WinForms の「コンパイルは通るが、実行時に壊れる / 規約に反する」部分を、静的に検査する (読み取り専用)。

Usage: winforms_check.py <dir> [--json <out.json>] [--max-lines 40] [--all]
                              [--logic <プロジェクト名>]... [--data <プロジェクト名>]...

<dir> 以下の .csproj を、プロジェクトとして検査する (.csproj がなければ、<dir> 全体を 1 つとして扱う)。
C# は、軽い字句解析 (コメントと文字列を除いて、正規表現と括弧の対応で見る) で検査する。完全な構文解析ではない。
**コンパイルエラーになるもの (イベントハンドラの不足、フィールドの重複など) は、対象外** (ビルドが教える)。

検査 (コード / 重大度: error = ほぼ確実な不具合、warning = 疑わしい):
  WFD001 error   Form のコンストラクターが、InitializeComponent() を呼んでいない (画面が空になる。例外も出ない)
  WFD002 error   Designer.cs に、同じ Name の文字列が、複数のコントロールにある (FindControl / UI Automation の AutomationId が、曖昧になる)
  WFD003 warning コントロールの Name の文字列が、変数名と違う (UI テストの AutomationId は Name。変数名とそろえる)
  WFD004 warning Designer.cs で生成したコントロールが、どの Controls.Add / AddRange にも入っていない (画面に出ない)
  WFD005 warning UI テストのプロジェクト (*.UITests) があるとき、操作するコントロールに Name がない (AutomationId が空になる)
  WFD006 warning InitializeComponent() を、Designer.cs 以外に書いている (デザイナーが、開けなくなる・書き換える)
  WFD007 warning InitializeComponent() の中に、制御構文 (if / for / while / switch / try) がある (デザイナーが、読めなくなる。宣言だけにする)
  WFD008 warning ListView の CheckBoxes = true (Designer.cs) と、View.Tile (並べて表示) を、同じコントロールに使っている (タイルは CheckBoxes と両立せず、NotSupportedException。
                 未処理だと、例外のダイアログで UI スレッドが止まり、UI テストが固まる)。タイルのときは、CheckBoxes = false にする
  WFT001 warning Application.DoEvents() を使っている (再入。処理を、async / await に分ける)
  WFT002 warning Form / UserControl のコードで、Thread.Sleep() を呼んでいる (UI が固まる)
  WFT003 error   Control.CheckForIllegalCrossThreadCalls = false (スレッドの誤りを、隠す。Invoke / BeginInvoke、または、async / await にする)
  WFL001 error   ロジック層・データ層が、WinForms に依存している (UseWindowsForms、-windows の TargetFramework、System.Windows.Forms / System.Drawing、MessageBox など)
  WFL002 warning Presenter (Presenters フォルダ、または名前が Presenter で終わる型) が、WinForms の型を使っている (MessageBox / Form / Control / Application など。テストしにくい)
  WFL003 error   プロジェクト参照の向きが、層 (アプリ → ロジック → データ) に反する
  WFL004 warning Form のコードで、Service / Repository などを new している (コンストラクターで受け取る。組み立ては、Program.cs)
  ASY001 warning .Result / .Wait() / GetAwaiter().GetResult() による、非同期処理の同期待機 (UI スレッドのデッドロック)
  ASY002 warning イベントハンドラ以外の async void
  EXC001 warning 空の catch (例外の握りつぶし)
  EXC002 warning catch した例外の `throw ex;` (スタックトレースが失われる。`throw;` にする)
  NAM001 warning bool に、Flag / Status / Check という曖昧な名前を付けている (IsXxx / HasXxx / CanXxx にする)

終了コード: 0 = error なし / 1 = error あり / 2 = 引数が不正 / 3 = 検査する対象がない (WinForms のプロジェクトも Designer.cs もない)。
"""
import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

SKIP_DIRS = {".git", ".vs", "bin", "obj", "packages", "node_modules", "TestResults", "ThirdParty", ".claude-logs"}
SEV_ORDER = {"error": 0, "warning": 1}
SYNC_WAIT = re.compile(r"(?:\)|\bTask\w*|\bawait\w*)\.Result\b|\.Wait\s*\(\s*\)|\.GetAwaiter\s*\(\s*\)\s*\.GetResult\s*\(\s*\)")
ASYNC_VOID = re.compile(r"\basync\s+void\s+(\w+)\s*\(([^)]*)\)")
EMPTY_CATCH = re.compile(r"\bcatch\s*(?:\([^)]*\))?\s*\{\s*\}")
CATCH_VAR = re.compile(r"\bcatch\s*\(\s*[\w.<>?]+\s+(\w+)\s*\)\s*\{")
VAGUE_BOOL = {"flag", "status", "check"}
BOOL_DECL = re.compile(r"\bbool\s+(\w+)\s*(?:[;=,){]|\{)")
WF_USING = re.compile(r"\busing\s+System\.(?:Windows\.Forms|Drawing)(?:\.[\w.]+)?\s*;")
# ImplicitUsings で、using がなくても、書ける型 (Presenter が使っていないか)
WF_USAGE = re.compile(r"\bMessageBox\b|\bApplication\.(?:Run|Exit|DoEvents|OpenForms|EnableVisualStyles)\b|\bnew\s+\w*Form\s*\("
                      r"|\b(?:Open|Save)FileDialog\b|\bFolderBrowserDialog\b|\bClipboard\.|\.ShowDialog\s*\(|\bControl\b|\bForm\b|\bUserControl\b")
NEW_SERVICE = re.compile(r"\bnew\s+[A-Z]\w*(?:Service|Repository|Client|Provider|Gateway)\s*[({]")
# Designer.cs で、Controls に入れないと、画面に出ない型 (確実に Control のもの。Timer / ToolTip / ImageList などは、含めない)
CONTROL_TYPES = {"Button", "TextBox", "Label", "CheckBox", "RadioButton", "ComboBox", "ListBox", "CheckedListBox", "Panel", "GroupBox",
                 "TableLayoutPanel", "FlowLayoutPanel", "DataGridView", "PictureBox", "NumericUpDown", "DateTimePicker", "ListView",
                 "TreeView", "TabControl", "ProgressBar", "RichTextBox", "MaskedTextBox", "SplitContainer", "LinkLabel", "TrackBar",
                 "MonthCalendar", "WebBrowser", "PropertyGrid", "StatusStrip", "MenuStrip", "ToolStrip", "TabPage"}
# UI テストで操作するコントロール (Name = AutomationId が要る)
INTERACTIVE_TYPES = {"Button", "TextBox", "ComboBox", "CheckBox", "RadioButton", "ListBox", "CheckedListBox", "DataGridView",
                     "NumericUpDown", "DateTimePicker", "ListView", "TreeView", "TabControl", "TrackBar", "RichTextBox", "MaskedTextBox", "LinkLabel"}


# ------------------------------------------------------------------ 読み込み (wpf-check と同じ。Skill は別々に配布されるので、複製している)
def read_text(path):
    b = open(path, "rb").read()
    if b[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return b.decode("utf-16", errors="replace")
    if b[:3] == b"\xef\xbb\xbf":
        return b[3:].decode("utf-8", errors="replace")
    try:
        return b.decode("utf-8")
    except UnicodeDecodeError:
        return b.decode("cp932", errors="replace")


def lineno(t, pos):
    return t.count("\n", 0, pos) + 1


def strip_cs(t):
    """C# のコメントと、文字列・文字の中身を、空白にする (改行と長さは残す。位置と行番号を保つ)。verbatim / 補間 / raw 文字列に対応。"""
    out, i, n = [], 0, len(t)
    while i < n:
        c, two = t[i], t[i:i + 2]
        if two == "//":
            j = t.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif two == "/*":
            j = t.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in t[i:j])); i = j
        elif t.startswith('"""', i):
            j = t.find('"""', i + 3)
            j = n if j < 0 else j + 3
            out.append('""' + "".join(ch if ch == "\n" else " " for ch in t[i + 2:j - 2]) + '""'); i = j
        elif c == '"':
            verbatim = i > 0 and t[i - 1] == "@" or (i > 1 and t[i - 2:i] in ("$@", "@$"))
            j = i + 1
            while j < n:
                if verbatim:
                    if t[j] == '"':
                        if t[j + 1:j + 2] == '"':
                            j += 2; continue
                        break
                    j += 1
                else:
                    if t[j] == "\\":
                        j += 2; continue
                    if t[j] in '"\n':
                        break
                    j += 1
            j = min(j + 1, n)
            out.append('"' + "".join(ch if ch == "\n" else " " for ch in t[i + 1:j - 1]) + '"'); i = j
        elif c == "'" and not (i > 0 and (t[i - 1].isalnum() or t[i - 1] == "_")):
            j = i + 1
            while j < n and t[j] != "'" and t[j] != "\n":
                j += 2 if t[j] == "\\" else 1
            j = min(j + 1, n)
            out.append("'" + " " * max(0, j - i - 2) + "'"); i = j
        else:
            out.append(c); i += 1
    return "".join(out)


def match_pair(t, i, openc, closec):
    depth = 0
    for k in range(i, len(t)):
        if t[k] == openc:
            depth += 1
        elif t[k] == closec:
            depth -= 1
            if depth == 0:
                return k
    return len(t) - 1


class Project:
    def __init__(self, name, path, root, csproj=None):
        self.name, self.dir, self.root, self.csproj = name, path, root, csproj
        self.use_wf = self.use_wpf = False
        self.output = ""
        self.tfm = ""
        self.refs = []
        self.cs = []          # (path, raw, code, is_designer)
        self.findings = []
        self.checked = False

    def rel(self, p):
        return os.path.relpath(p, self.root).replace(os.sep, "/")

    def add(self, code, sev, msg, path=None, line=None):
        f = {"code": code, "severity": sev, "message": msg, "project": self.name, "file": path, "line": line}
        if f not in self.findings:
            self.findings.append(f)


def collect_files(d):
    out = []
    for cur, ds, fs in os.walk(d):
        ds[:] = [x for x in ds if x not in SKIP_DIRS and not x.startswith(".")]
        for f in fs:
            out.append(os.path.join(cur, f))
    return out


def load_project(csproj, root):
    p = Project(os.path.splitext(os.path.basename(csproj))[0], os.path.dirname(csproj), root, csproj)
    try:
        for el in ET.parse(csproj).getroot().iter():
            tag, txt = el.tag.split("}")[-1], (el.text or "").strip()
            if tag == "UseWindowsForms":
                p.use_wf = txt.lower() == "true"
            elif tag == "UseWPF":
                p.use_wpf = txt.lower() == "true"
            elif tag == "OutputType":
                p.output = txt
            elif tag in ("TargetFramework", "TargetFrameworks"):
                p.tfm = txt
            elif tag == "ProjectReference":
                p.refs.append(os.path.splitext(os.path.basename(el.get("Include", "").replace("\\", "/")))[0])
    except ET.ParseError:
        pass
    return p


# ------------------------------------------------------------------ 層の判定
RANK = {"data": 0, "logic": 1, "ui": 2}


def layer_of(pr, names):
    n = pr.name
    if re.search(r"Tests?$", n):
        return "test"
    if n in names["logic"]:
        return "logic"
    if n in names["data"]:
        return "data"
    if pr.use_wf and pr.output.lower() in ("winexe", "exe"):
        return "ui"
    if re.search(r"logic|domain|core|presenters?", n, re.I):
        return "logic"
    if re.search(r"data", n, re.I):
        return "data"
    if pr.use_wf:
        return "ui"
    return None


def is_designer(path):
    return path.lower().endswith(".designer.cs")


# ------------------------------------------------------------------ Designer.cs
def init_body(code, start=0):
    """code の中の InitializeComponent() の本体 (開始, 終了) を返す。なければ None。"""
    m = re.compile(r"\bvoid\s+InitializeComponent\s*\(\s*\)\s*\{").search(code, start)
    if not m:
        return None
    b = m.end() - 1
    return m, b, match_pair(code, b, "{", "}")


def check_designer(pr, path, raw, code, ui_tests):
    found = init_body(code)
    if not found:
        return
    _m, b, e = found
    rel = pr.rel(path)
    body_raw, body = raw[b:e], code[b:e]
    base = lineno(code, b) - 1

    def line_of(off):
        return base + body.count("\n", 0, off) + 1

    creations = {}   # 変数名 -> (型, 行)
    for m in re.finditer(r"(?<![\w.])(?:this\.)?(\w+)\s*=\s*new\s+([\w.]+)\s*(?:\(|\{)", body):
        creations[m.group(1)] = (m.group(2).split(".")[-1], line_of(m.start()))
    names = []       # (prefix または None, Name の文字列, 行)
    for m in re.finditer(r"(?:(?<![\w.])(?:this\.)?(\w+)\.)?(?<!\w)Name\s*=\s*\"([^\"\n]*)\"", body_raw):
        prefix = m.group(1)
        names.append((None if prefix in (None, "this") else prefix, m.group(2), line_of(m.start())))

    seen = {}
    for prefix, nm, ln in names:
        if nm in seen:
            pr.add("WFD002", "error", f"Name \"{nm}\" が、複数のコントロールにある ({seen[nm]} 行目と {ln} 行目。FindControl / AutomationId が、曖昧になる)", rel, ln)
        else:
            seen[nm] = ln
        if prefix and prefix in creations and prefix != nm:
            pr.add("WFD003", "warning", f"{prefix}.Name が \"{nm}\" (変数名と違う。UI テストの AutomationId は Name。そろえる)", rel, ln)

    added = set()
    for m in re.finditer(r"\.(?:Add|AddRange)\s*\(", body):
        i = m.end() - 1
        added.update(re.findall(r"[A-Za-z_]\w*", body[i:match_pair(body, i, "(", ")")]))
    named = {p for p, _n, _l in names if p}
    for var, (typ, ln) in creations.items():
        if typ in CONTROL_TYPES and var not in added:
            pr.add("WFD004", "warning", f"{var} ({typ}) が、どの Controls.Add / AddRange にも入っていない (画面に出ない)", rel, ln)
        if ui_tests and typ in INTERACTIVE_TYPES and var not in named:
            pr.add("WFD005", "warning", f"{var} ({typ}) に Name がない (UI テストの AutomationId が、空になる。{var}.Name = \"{var}\";)", rel, ln)

    m = re.search(r"\b(if|for|foreach|while|switch|try)\b\s*[({]", body)
    if m:
        pr.add("WFD007", "warning", f"InitializeComponent() の中に、{m.group(1)} がある (デザイナーが読めなくなる。宣言 (代入と Add) だけにする。処理は、コンストラクターに書く)", rel, line_of(m.start()))


def check_listview_tile(pr):
    """WFD008: Designer.cs で CheckBoxes = true の ListView を、View.Tile にしている (実機で確認: NotSupportedException。例外のダイアログで、UI が止まる)。
    Designer.cs 以外で、そのコントロールの CheckBoxes に、true 以外 (= false など、切り替える処理) を代入していれば、対応済みとみなす。"""
    for path, _raw, code, des in pr.cs:
        if not des:
            continue
        for m in re.finditer(r"(?<![\w.])(?:this\.)?(\w+)\.CheckBoxes\s*=\s*true\b", code):
            var = m.group(1)
            uses_tile = [p2 for p2, _r2, c2, _d2 in pr.cs if re.search(r"\bView\.Tile\b", c2) and re.search(r"\b" + re.escape(var) + r"\b", c2)]
            handled = any(re.search(r"\b" + re.escape(var) + r"\.CheckBoxes\s*=\s*(?!true\b)", c2) for p2, _r2, c2, d2 in pr.cs if not d2)
            if uses_tile and not handled:
                pr.add("WFD008", "warning", f"{var} (ListView) は、CheckBoxes = true で、View.Tile も使っている ({pr.rel(uses_tile[0])})。タイルは、CheckBoxes と両立しない (NotSupportedException)。タイルのときは、{var}.CheckBoxes = false にする", pr.rel(path), lineno(code, m.start()))


def check_forms(pr, ui_files):
    """InitializeComponent を持つクラスの、コンストラクターが、呼んでいるか (WFD001)。Designer.cs 以外の InitializeComponent (WFD006)。"""
    for path, raw, code, des in pr.cs:
        for m in re.finditer(r"\bvoid\s+InitializeComponent\s*\(\s*\)\s*\{", code):
            cls = re.findall(r"\bclass\s+(\w+)", code[:m.start()])
            if not des:
                pr.add("WFD006", "warning", "InitializeComponent() を、Designer.cs 以外に書いている (デザイナーが、開けなくなる・書き換える。*.Designer.cs に置く)", pr.rel(path), lineno(code, m.start()))
            if not cls:
                continue
            c = cls[-1]
            ctors = []
            for p2, _r2, code2, _d2 in pr.cs:
                for mm in re.finditer(r"\b(?:public|internal|protected|private)\s+" + re.escape(c) + r"\s*\(([^)]*)\)\s*(?::\s*(this|base)\s*\([^)]*\))?\s*\{", code2):
                    ctors.append((p2, code2, mm))
            if not ctors:
                pr.add("WFD001", "error", f"{c} に、コンストラクターがない (InitializeComponent() が呼ばれず、画面が空になる)", pr.rel(path), lineno(code, m.start()))
            for p2, code2, mm in ctors:
                if mm.group(2) == "this":
                    continue   # 別のコンストラクターに任せている
                end = match_pair(code2, mm.end() - 1, "{", "}")
                if not re.search(r"\bInitializeComponent\s*\(", code2[mm.end():end]):
                    pr.add("WFD001", "error", f"{c} のコンストラクターが、InitializeComponent() を呼んでいない (画面が空になる。例外も出ない)", pr.rel(p2), lineno(code2, mm.start()))


# ------------------------------------------------------------------ スレッド・UI
def check_ui_code(pr):
    for path, raw, code, des in pr.cs:
        rel = pr.rel(path)
        for m in re.finditer(r"\bApplication\.DoEvents\s*\(", code):
            pr.add("WFT001", "warning", "Application.DoEvents() を使っている (再入で、状態が壊れる。処理を async / await に分ける)", rel, lineno(code, m.start()))
        for m in re.finditer(r"\bCheckForIllegalCrossThreadCalls\s*=\s*false\b", code):
            pr.add("WFT003", "error", "CheckForIllegalCrossThreadCalls = false (スレッドの誤りを隠す。Invoke / BeginInvoke、または async / await にする)", rel, lineno(code, m.start()))
        if not des and re.search(r":\s*(?:[\w.]+\s*,\s*)*(?:Form|UserControl)\b", code):
            for m in re.finditer(r"\bThread\.Sleep\s*\(", code):
                pr.add("WFT002", "warning", "Form / UserControl のコードで、Thread.Sleep() を呼んでいる (UI が固まる。await Task.Delay にする)", rel, lineno(code, m.start()))
            m = NEW_SERVICE.search(code)
            if m:
                pr.add("WFL004", "warning", f"Form のコードで、{m.group(0).strip()} を生成している (コンストラクターで、インターフェースを受け取る。組み立ては、Program.cs)", rel, lineno(code, m.start()))


# ------------------------------------------------------------------ 共通の規則 (非同期・例外・名前)
def check_code_rules(pr):
    for path, raw, code, des in pr.cs:
        rel = pr.rel(path)
        for m in list(SYNC_WAIT.finditer(code))[:5]:
            pr.add("ASY001", "warning", f"非同期処理を同期的に待っている: {m.group(0).strip()} (UI スレッドのデッドロックの恐れ。await にする)", rel, lineno(code, m.start()))
        for m in ASYNC_VOID.finditer(code):
            if "EventArgs" not in m.group(2) and "sender" not in m.group(2):
                pr.add("ASY002", "warning", f"async void {m.group(1)}: イベントハンドラ以外の async void (Task を返す)", rel, lineno(code, m.start()))
        for m in EMPTY_CATCH.finditer(code):
            pr.add("EXC001", "warning", "空の catch (例外の握りつぶし。ログを書くか、再スローする)", rel, lineno(code, m.start()))
        for m in CATCH_VAR.finditer(code):
            end = match_pair(code, m.end() - 1, "{", "}")
            if re.search(r"\bthrow\s+" + re.escape(m.group(1)) + r"\s*;", code[m.end():end]):
                pr.add("EXC002", "warning", f"throw {m.group(1)}; はスタックトレースを失う (throw; にする)", rel, lineno(code, m.start()))
        if des:
            continue
        for m in BOOL_DECL.finditer(code):
            if m.group(1).lstrip("_").lower() in VAGUE_BOOL:
                pr.add("NAM001", "warning", f"bool の名前 \"{m.group(1)}\" が曖昧 (IsXxx / HasXxx / CanXxx のように、状態や判定と分かる名前にする)", rel, lineno(code, m.start()))


# ------------------------------------------------------------------ 層
def is_presenter_file(pr, path, code):
    parts = path.replace("\\", "/").split("/")
    return "Presenters" in parts or re.search(r"\bclass\s+\w+Presenter\b", code) is not None


def check_layering(projects, names):
    by = {p.name: p for p in projects}
    for pr in projects:
        L = layer_of(pr, names)
        if L != "test":
            check_code_rules(pr)
        if L in ("logic", "data") and (pr.use_wf or pr.use_wpf or "-windows" in pr.tfm):
            pr.add("WFL001", "error", f"{L} 層の {pr.name} が、Windows / WinForms に依存している (UseWindowsForms / TargetFramework {pr.tfm or '?'}。net8.0 などの、Windows 非依存にする)", pr.rel(pr.csproj) if pr.csproj else None)
        if L in RANK:
            for ref in pr.refs:
                q = by.get(ref)
                Q = layer_of(q, names) if q else None
                if q and Q in RANK and RANK[L] < RANK[Q]:
                    pr.add("WFL003", "error", f"{pr.name} ({L}) が {q.name} ({Q}) を参照している (アプリ → ロジック → データの向きに反する)", pr.rel(pr.csproj) if pr.csproj else None)
        for path, raw, code, des in pr.cs:
            if L in ("logic", "data"):
                m = WF_USING.search(code) or WF_USAGE.search(code)
                if m:
                    pr.add("WFL001", "error", f"{L} 層で、WinForms の型を使っている: {m.group(0).strip()}", pr.rel(path), lineno(code, m.start()))
            elif L == "ui" and not des and is_presenter_file(pr, path, code):
                m = WF_USING.search(code) or WF_USAGE.search(code)
                if m:
                    pr.add("WFL002", "warning", f"Presenter が、WinForms の型を使っている: {m.group(0).strip()} (テストしにくい。IDialogService などに分ける)", pr.rel(path), lineno(code, m.start()))


def run(root, names):
    root = os.path.abspath(root)
    files = collect_files(root)
    csprojs = sorted(p for p in files if p.lower().endswith(".csproj"))
    projects = [load_project(c, root) for c in csprojs] or [Project(os.path.basename(root), root, root)]
    nested = {pr.dir for pr in projects}
    for pr in projects:
        for path in collect_files(pr.dir):
            if any(os.path.dirname(path).startswith(d + os.sep) for d in nested if d != pr.dir and d.startswith(pr.dir + os.sep)):
                continue
            low = path.lower()
            if low.endswith(".cs") and not low.endswith((".g.cs", ".g.i.cs")):
                raw = read_text(path)
                pr.cs.append((path, raw, strip_cs(raw), is_designer(path)))
    ui_tests = any(re.search(r"UITests?$", pr.name, re.I) for pr in projects)   # UI テストのプロジェクトがあるか (WFD005 の条件)
    for pr in projects:
        pr.checked = pr.use_wf or any(d and "InitializeComponent" in c for _p, _r, c, d in pr.cs)
        for path, raw, code, des in pr.cs:
            if des:
                check_designer(pr, path, raw, code, ui_tests)
        check_forms(pr, None)
        check_listview_tile(pr)
        if pr.use_wf or pr.checked:
            check_ui_code(pr)
    check_layering(projects, names)
    return projects


def summarize(projects, max_lines):
    findings = [f for pr in projects for f in pr.findings]
    findings.sort(key=lambda f: (SEV_ORDER[f["severity"]], f["project"], f["code"], f["file"] or "", f["line"] or 0))
    n = {s: sum(1 for f in findings if f["severity"] == s) for s in SEV_ORDER}
    checked = [pr.name for pr in projects if pr.checked]
    out = [f"winforms-check: error {n['error']} / warning {n['warning']} ({len(checked)} projects: {', '.join(checked[:6])}{'...' if len(checked) > 6 else ''})"]
    for i, f in enumerate(findings, 1):
        out.append(f"[{i}] {f['severity']:7s} {f['code']} {f['message']}")
        if f["file"]:
            out.append(f"      {f['file']}" + (f"({f['line']})" if f["line"] else ""))
    out = [s[:400] for s in out]
    if len(out) > max_lines:
        out = out[:max_lines - 1] + [f"... ({len(findings)} findings in total; see --json)"]
    return out, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--json")
    ap.add_argument("--max-lines", type=int, default=40)
    ap.add_argument("--all", action="store_true", help="(wpf-check と、引数をそろえるため。info は、ない)")
    ap.add_argument("--logic", action="append", default=[])
    ap.add_argument("--data", action="append", default=[])
    a = ap.parse_args()
    if not os.path.isdir(a.dir):
        print(f"BAD_ARGS: not a directory: {a.dir}")
        return 2
    projects = run(a.dir, {"logic": set(a.logic), "data": set(a.data)})
    if not any(pr.checked for pr in projects):
        print("winforms-check: nothing to check (no WinForms project / Designer.cs found)")
        return 3
    out, n = summarize(projects, a.max_lines)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump({"counts": n, "findings": [fi for pr in projects for fi in pr.findings]}, f, ensure_ascii=False, indent=2)
    sys.stdout.write("\n".join(out) + "\n")
    return 1 if n["error"] else 0


if __name__ == "__main__":
    sys.exit(main())
