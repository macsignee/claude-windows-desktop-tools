#!/usr/bin/env python3
"""wpf_check.py - WPF の「コンパイルは通るが、実行時に壊れる」部分を、静的に検査する (読み取り専用)。

Usage: wpf_check.py <dir> [--json <out.json>] [--max-lines 40] [--all]
                          [--logic <プロジェクト名>]... [--data <プロジェクト名>]... [--viewmodel <プロジェクト名>]...

<dir> 以下の .csproj を、プロジェクトとして検査する (.csproj がなければ、<dir> 全体を 1 つとして扱う)。
XAML は、XML として読む。C# は、軽い字句解析で、型・プロパティ・コンストラクターを取り出す (完全な構文解析ではない)。
**コンパイルエラーになるもの (イベントハンドラの不足、x:Name の重複など) は、対象外** (ビルドが教える)。

検査 (コード / 重大度: error = ほぼ確実な不具合、warning = 疑わしい、info = 参考):
  BND001 error   {Binding} のパスが、DataContext の型にない (黙って何も表示されない)。メソッド・フィールド・非 public の場合は、その旨を添える
  BND002 error   public フィールドにバインドしている (WPF は、プロパティしかバインドできない)
  BND003 error   読み取り専用のプロパティに、TwoWay でバインドしている (実行時に例外)。既定が TwoWay の項目 (TextBox.Text など) も、setter なしなら error (実機で、起動時の例外を確認)。setter が public でない場合は warning
  BND004 warning ViewModel が INotifyPropertyChanged を実装していない (値を変えても、画面が更新されない)
  BND900 info    DataContext の型を、解決できない / 基底クラスが外部で、検査できない
  CMD001 warning Command に、ICommand でない型のプロパティをバインドしている
  RES001 error   StaticResource のキーが、どこにも定義されていない (起動時に、XamlParseException)。外部の辞書があって、確実でないときは warning
  RES002 error   StaticResource が、同じ辞書の、後ろで定義されたキーを参照している (読み込み時に、定義済みのキーだけを解決するため、起動時に例外。実機で確認)
  RES003 error   同じ辞書に、同じ x:Key が複数ある (読み込み時に例外)
  RES004 warning DynamicResource のキーが、どこにも定義されていない (黙って、既定値になる)
  RES005 error   MergedDictionaries の Source が、プロジェクト内に見つからない (読み込み時に例外)
  CNV001 error   Converter に、IValueConverter / IMultiValueConverter を実装していないクラスを指定している
  UI001  error   code-behind のコンストラクターが、InitializeComponent() を呼んでいない (画面が空になる)
  APP001 error   App.xaml の StartupUri の XAML が、プロジェクト内に見つからない (起動時に例外)
  LAY001 error   ロジック層・データ層が、WPF に依存している (UseWPF、System.Windows 名前空間、MessageBox など)
  LAY002 warning ViewModel が、View の型を使っている (MessageBox / Application.Current / Window など。テストしにくい)
  LAY003 error   プロジェクト参照の方向が、層 (View → ViewModel → ロジック → データ) に反する。
                 Presentation / Application / Domain / Infrastructure の名前のプロジェクトは、標準の依存
                 (Presentation → Application → Domain、Infrastructure → Application / Domain。Domain は何も参照しない) で検査する
  DI001  warning ViewModel 内で、Service / Repository などを new している (コンストラクターインジェクションにする)
  ASY001 warning .Result / .Wait() / GetAwaiter().GetResult() による、非同期処理の同期待機 (UI スレッドのデッドロック)
  ASY002 warning イベントハンドラ以外の async void
  EXC001 warning 空の catch (例外の握りつぶし)
  EXC002 warning catch した例外の `throw ex;` (スタックトレースが失われる。`throw;` にする)
  NAM001 warning bool に、Flag / Status / Check という曖昧な名前を付けている (IsXxx / HasXxx / CanXxx にする)
  UI002  warning UI テストのプロジェクト (*.UITests) があるとき、操作できるコントロール (Button / TextBox など) に AutomationId (または x:Name) がない
  UI003  warning UserControl が、自分自身を DataContext に設定している (親から継承される DataContext を壊す)
  XAML001 info   XAML を、XML として解析できなかった (そのファイルの検査を省略)

終了コード: 0 = error なし / 1 = error あり / 2 = 引数が不正 / 3 = 検査する対象がない。
"""
import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import OrderedDict, defaultdict
from xml.parsers import expat

SKIP_DIRS = {".git", ".vs", "bin", "obj", "packages", "node_modules", "TestResults", "ThirdParty", ".claude-logs"}
SEV_ORDER = {"error": 0, "warning": 1, "info": 2}
X_NS = "http://schemas.microsoft.com/winfx/2006/xaml"
D_NS = "http://schemas.microsoft.com/expression/blend/2008"
PRES_NS = "http://schemas.microsoft.com/winfx/2006/xaml/presentation"

# 基底クラスが、プロジェクトの外にあっても、「検査してよい」(INotifyPropertyChanged を実装し、バインド対象のプロパティを足さない) もの
CLOSED_EXTERNAL_BASES = {"ObservableObject", "ObservableValidator", "ObservableRecipient", "BindableBase", "ReactiveObject",
                         "NotificationObject", "Object", "object"}
INPC_BASES = {"ObservableObject", "ObservableValidator", "ObservableRecipient", "BindableBase", "ReactiveObject",
              "NotificationObject", "INotifyPropertyChanged"}
# 基底が、これらなら、依存関係プロパティなどを持つので、「メンバーを、列挙できない」(検査しない)
DP_BASES = {"DependencyObject", "FrameworkElement", "Control", "UserControl", "Window", "Page", "ContentControl",
            "Freezable", "Visual", "UIElement", "Panel", "ItemsControl", "ViewModelBase"}
# 既定のバインディングの方向が TwoWay の、(要素名, プロパティ名)
TWOWAY_DEFAULT = {("TextBox", "Text"), ("CheckBox", "IsChecked"), ("RadioButton", "IsChecked"), ("ToggleButton", "IsChecked"),
                  ("Slider", "Value"), ("ComboBox", "SelectedItem"), ("ComboBox", "SelectedValue"), ("ComboBox", "SelectedIndex"),
                  ("ComboBox", "Text"), ("ListBox", "SelectedItem"), ("ListBox", "SelectedValue"), ("ListBox", "SelectedIndex"),
                  ("ListView", "SelectedItem"), ("DataGrid", "SelectedItem"), ("DatePicker", "SelectedDate"),
                  ("Calendar", "SelectedDate"), ("TabControl", "SelectedIndex"), ("TabControl", "SelectedItem"),
                  ("ScrollBar", "Value"), ("ProgressBar", "Value"), ("PasswordBox", "Password")}
NON_COMMAND_TYPES = {"string", "int", "long", "bool", "double", "float", "decimal", "object", "DateTime", "Guid", "char"}
MODIFIERS = {"public", "private", "protected", "internal", "static", "virtual", "override", "abstract", "readonly", "new",
             "partial", "async", "sealed", "unsafe", "extern", "required", "const", "volatile", "file", "ref"}
WPF_USING = re.compile(r"\busing\s+System\.Windows(?:\.(?:Controls|Media|Data|Documents|Shapes|Markup|Threading|Interop|Navigation|Ink))?\s*;")
WPF_USAGE = re.compile(r"\bMessageBox\.Show\b|\bApplication\.Current\b|\bnew\s+\w*(?:Window|Dialog)\s*\("
                       r"|\bOpenFileDialog\b|\bSaveFileDialog\b|\bClipboard\.|\.ShowDialog\s*\(|\bWindow\.Show\b")
VIEW_USING = re.compile(r"\busing\s+[\w.]*\.Views(?:\.[\w.]+)?\s*;")
NEW_SERVICE = re.compile(r"\bnew\s+[A-Z]\w*(?:Service|Repository|Client|Provider|Gateway)\s*[({]")
SYNC_WAIT = re.compile(r"(?:\)|\bTask\w*|\bawait\w*)\.Result\b|\.Wait\s*\(\s*\)|\.GetAwaiter\s*\(\s*\)\s*\.GetResult\s*\(\s*\)")
ASYNC_VOID = re.compile(r"\basync\s+void\s+(\w+)\s*\(([^)]*)\)")
EMPTY_CATCH = re.compile(r"\bcatch\s*(?:\([^)]*\))?\s*\{\s*\}")
CATCH_VAR = re.compile(r"\bcatch\s*\(\s*[\w.<>?]+\s+(\w+)\s*\)\s*\{")
VAGUE_BOOL = {"flag", "status", "check"}
STD_ALLOWED = {"domain": set(), "application": {"domain"}, "infrastructure": {"application", "domain"},
               "presentation": {"application", "domain", "infrastructure"}}


# ------------------------------------------------------------------ 共通
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
    """C# のコメントと、文字列・文字の中身を、空白にする (改行は残す。行番号を保つ)。verbatim / 補間 / raw 文字列に対応。"""
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


def split_top(s, sep=","):
    out, depth, cur = [], 0, []
    for ch in s:
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        if ch == sep and depth == 0:
            out.append("".join(cur).strip()); cur = []
        else:
            cur.append(ch)
    last = "".join(cur).strip()
    if last:
        out.append(last)
    return out


def simple_type(s):
    """型の文字列 → 単純名 (ジェネリクス・null 許容・名前空間・配列を除く)。"""
    s = re.sub(r"<.*>", "", s or "")
    s = s.replace("?", "").replace("[]", "").strip()
    return s.split(".")[-1].strip()


# ------------------------------------------------------------------ C# の解析
class CsType:
    def __init__(self, full, name, ns, kind, proj, path, line):
        self.full, self.name, self.ns, self.kind, self.proj = full, name, ns, kind, proj
        self.partial = False
        self.bases = []
        self.places = [(path, line)]
        self.props, self.fields, self.methods, self.events = {}, {}, {}, set()
        self.ctors = []          # コンストラクターの本体のテキスト
        self.attrs = set()
        self.rec_params = []

    def merge(self, o):
        self.partial = self.partial or o.partial
        self.bases += [b for b in o.bases if b not in self.bases]
        self.places += o.places
        self.props.update(o.props); self.fields.update(o.fields); self.methods.update(o.methods)
        self.events |= o.events
        self.ctors += o.ctors
        self.attrs |= o.attrs
        self.rec_params += o.rec_params


TYPE_HEAD = re.compile(r"^(?:(?:public|internal|private|protected|static|sealed|abstract|partial|unsafe|readonly|ref|file|new)\s+)*"
                       r"(?P<kind>class|struct|interface|record(?:\s+(?:class|struct))?|enum)\s+(?P<name>[A-Za-z_]\w*)")


def strip_attrs(h):
    """先頭の [Attr] を取り除く。戻り値: (残り, 属性名の集合)"""
    attrs = set()
    h = h.strip()
    while h.startswith("["):
        e = match_pair(h, 0, "[", "]")
        for a in split_top(h[1:e]):
            m = re.match(r"(?:\w+\s*:\s*)?([\w.]+)", a)
            if m:
                nm = m.group(1).split(".")[-1]
                attrs.add(nm[:-len("Attribute")] if nm.endswith("Attribute") and len(nm) > 9 else nm)
        h = h[e + 1:].lstrip()
    return h, attrs


def scan_segments(code, s, e):
    """code[s:e] の、深さ 0 の宣言を (ヘッダー, 開始位置, 終端, 本体の開始, 本体の終了) で返す。終端: '{' / ';' / '=>'。"""
    out, i, buf = [], s, s

    def to_semicolon(j):
        while j < e:
            c = code[j]
            if c in "([{":
                j = match_pair(code, j, c, {"(": ")", "[": "]", "{": "}"}[c]) + 1
                continue
            if c == ";":
                return j
            j += 1
        return e

    while i < e:
        c = code[i]
        if c in "([":
            i = match_pair(code, i, c, ")" if c == "(" else "]") + 1
        elif c == ";":
            out.append((code[buf:i], buf, ";", i, i)); i += 1; buf = i
        elif c == "=" and code[i + 1:i + 2] == ">":
            j = to_semicolon(i + 2)
            out.append((code[buf:i], buf, "=>", i + 2, j)); i = j + 1; buf = i
        elif c == "=" and code[i + 1:i + 2] == "=":
            i += 2
        elif c == "=":
            j = to_semicolon(i + 1)
            out.append((code[buf:i], buf, ";", i, j)); i = j + 1; buf = i
        elif c == "{":
            end = match_pair(code, i, "{", "}")
            out.append((code[buf:i], buf, "{", i + 1, end))
            i = end + 1
            k = i
            while k < e and code[k] in " \t\r\n":
                k += 1
            if code[k:k + 1] == "=" and code[k + 1:k + 2] != ">":
                i = to_semicolon(k) + 1      # プロパティの初期化子: { get; } = new();
            buf = i
        else:
            i += 1
    return out


def member_name_from_field(fname):
    n = re.sub(r"^(?:m_|_)+", "", fname)
    return n[:1].upper() + n[1:] if n else fname


def add_member(t, h, attrs, term, code, bs, be, path, hs):
    mods_removed = h
    mods = set()
    while True:
        m = re.match(r"([a-z]+)\s+", mods_removed)
        if m and m.group(1) in MODIFIERS:
            mods.add(m.group(1)); mods_removed = mods_removed[m.end():]
        else:
            break
    public = "public" in mods
    line = lineno(code, hs)
    if mods_removed.startswith("event "):
        t.events.add(re.split(r"\s+", mods_removed.rstrip())[-1].strip())
        return
    if "(" in mods_removed.split("=")[0] and not mods_removed.lstrip().startswith("this"):
        m = re.search(r"([A-Za-z_@]\w*)\s*(?:<[^()]*>)?\s*\(", mods_removed)
        if not m:
            return
        name = m.group(1)
        ret = mods_removed[:m.start()].strip()
        if name == t.name and not ret:
            t.ctors.append(code[bs:be] if term in ("{", "=>") else "")
            return
        t.methods[name] = {"attrs": attrs, "ret": ret, "async": "async" in mods or ret.startswith("Task") or ret.startswith("ValueTask"),
                           "public": public, "static": "static" in mods, "line": line}
        return
    if term == "{" or term == "=>":
        m = re.match(r"(?P<type>.+?)\s+(?P<name>[A-Za-z_@]\w*)\s*$", mods_removed, re.S)
        if not m:
            return
        body = code[bs:be] if term == "{" else ""
        has_get = term == "=>" or bool(re.search(r"\bget\b", body))
        setm = re.search(r"((?:\b(?:private|protected|internal)(?:\s+protected)?\s+)?)\b(set|init)\b", body) if term == "{" else None
        setter = "none"
        if setm:
            if setm.group(2) == "init":
                setter = "init"
            else:
                setter = "restricted" if setm.group(1).strip() else "public"
        t.props[m.group("name").lstrip("@")] = {"type": m.group("type").strip(), "setter": setter, "get": has_get, "public": public,
                                                  "static": "static" in mods, "attrs": attrs, "line": line}
        return
    # フィールド (int a, b; も)
    m = re.match(r"(?P<type>.+?)\s+(?P<names>[A-Za-z_@]\w*(?:\s*,\s*[A-Za-z_@]\w*)*)\s*$", mods_removed, re.S)
    if not m:
        return
    for nm in [x.strip().lstrip("@") for x in m.group("names").split(",")]:
        t.fields[nm] = {"type": m.group("type").strip(), "public": public, "static": "static" in mods or "const" in mods,
                        "attrs": attrs, "line": line}


def parse_scope(code, s, e, ns, outer, path, proj, types, cur_type=None):
    for header, hs, term, bs, be in scan_segments(code, s, e):
        h, attrs = strip_attrs(header)
        h = re.sub(r"\s+", " ", h).strip()
        if not h:
            continue
        mns = re.match(r"namespace\s+([\w.]+)\s*$", h)
        if mns:
            if term == "{":
                parse_scope(code, bs, be, (ns + "." if ns else "") + mns.group(1), outer, path, proj, types)
            else:
                ns = mns.group(1)
            continue
        mt = TYPE_HEAD.match(h)
        if mt and term in ("{", ";"):
            kind = mt.group("kind").split()[0]
            name = mt.group("name")
            full = ".".join([x for x in [ns] + outer + [name] if x])
            t = CsType(full, name, ns, kind, proj, path, lineno(code, hs + max(0, header.find(name))))
            t.partial = bool(re.match(r"(?:\w+\s+)*partial\b", h))
            t.attrs = attrs
            rest = h[mt.end():]
            rest = re.sub(r"^\s*<.*?>(?=\s*[(:{]|$)", "", rest) if rest.lstrip().startswith("<") else rest
            if kind == "record" or "(" in rest.split(":")[0]:
                pm = re.match(r"\s*\(", rest)
                if pm:
                    pe = match_pair(rest, rest.index("("), "(", ")")
                    if kind == "record":
                        for prm in split_top(rest[rest.index("(") + 1:pe]):
                            pm2 = re.match(r"(?:\[[^\]]*\]\s*)*(?P<type>.+?)\s+(?P<name>[A-Za-z_]\w*)\s*(?:=.*)?$", prm, re.S)
                            if pm2:
                                t.rec_params.append(pm2.group("name"))
                                t.props[pm2.group("name")] = {"type": pm2.group("type"), "setter": "init", "get": True, "public": True,
                                                              "static": False, "attrs": set(), "line": t.places[0][1]}
                    rest = rest[pe + 1:]
            rest = re.split(r"\bwhere\b", rest)[0]
            if ":" in rest:
                t.bases = [simple_type(b) for b in split_top(rest.split(":", 1)[1])]
            if kind != "enum" and term == "{":
                parse_scope(code, bs, be, ns, outer + [name], path, proj, types, t)
            types.append(t)
            continue
        if cur_type is not None:
            add_member(cur_type, h, attrs, term, code, bs, be, path, hs)


def parse_cs(code, path, proj):
    types = []
    parse_scope(code, 0, len(code), "", [], path, proj, types)
    return types


# ------------------------------------------------------------------ XAML の解析
class Node:
    __slots__ = ("uri", "local", "attrs", "line", "offset", "parent", "children", "nsmap", "text")

    def __init__(self, uri, local, attrs, line, offset, parent, nsmap):
        self.uri, self.local, self.attrs, self.line, self.offset = uri, local, attrs, line, offset
        self.parent, self.children, self.nsmap, self.text = parent, [], nsmap, ""

    def ancestors(self):
        n = self
        while n:
            yield n
            n = n.parent

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()

    def child_prop(self, prop):
        want = f"{self.local}.{prop}"
        return next((c for c in self.children if c.local == want), None)


def parse_xaml(raw):
    """XAML のバイト列 → ルートの Node。解析できなければ None。"""
    p = expat.ParserCreate(namespace_separator=" ")
    p.ordered_attributes = True
    stack, pend, root = [], [], []

    def start(name, attrs):
        uri, local = name.rsplit(" ", 1) if " " in name else ("", name)
        d = OrderedDict()
        for k, v in zip(attrs[0::2], attrs[1::2]):
            au, al = k.rsplit(" ", 1) if " " in k else ("", k)
            key = "x:" + al if au == X_NS else "d:" + al if au == D_NS else al if not au else k
            d[key] = v
        nsmap = dict(stack[-1].nsmap) if stack else {}
        for pre, u in pend:
            nsmap[pre or ""] = u
        pend.clear()
        node = Node(uri, local, d, p.CurrentLineNumber, p.CurrentByteIndex, stack[-1] if stack else None, nsmap)
        if stack:
            stack[-1].children.append(node)
        else:
            root.append(node)
        stack.append(node)

    p.StartNamespaceDeclHandler = lambda pre, u: pend.append((pre, u))
    p.StartElementHandler = start
    p.EndElementHandler = lambda name: stack.pop()
    p.CharacterDataHandler = lambda data: stack and setattr(stack[-1], "text", stack[-1].text + data)
    try:
        p.Parse(raw, True)
    except expat.ExpatError:
        return None
    return root[0] if root else None


def attr_line(doc, node, key):
    """要素の開始タグの中で、属性が書かれている行。見つからなければ、要素の行。"""
    raw = doc.raw
    start = node.offset
    i, q = start, None
    while i < len(raw):
        ch = raw[i:i + 1]
        if q:
            if ch == q:
                q = None
        elif ch in (b'"', b"'"):
            q = ch
        elif ch == b">":
            break
        i += 1
    tag = raw[start:i]
    name = key.split(":")[-1].split(" ")[-1]
    m = re.search(rb"[\s<]" + re.escape(name.encode()) + rb"\s*=", tag)
    return node.line + (tag[:m.start()].count(b"\n") if m else 0)


class Doc:
    def __init__(self, path, rel, proj, raw):
        self.path, self.rel, self.proj, self.raw = path, rel, proj, raw
        self.root = parse_xaml(raw)
        self.cls = self.root.attrs.get("x:Class") if self.root else None


def clr_ns(uri):
    m = re.match(r"clr-namespace:([^;]+)", uri or "")
    return m.group(1).strip() if m else None


# ------------------------------------------------------------------ プロジェクト
class Project:
    def __init__(self, name, path, root, csproj=None):
        self.name, self.dir, self.root, self.csproj = name, path, root, csproj
        self.use_wpf = self.use_wf = False
        self.output = ""
        self.tfm = ""
        self.assembly = name
        self.refs = []
        self.cs, self.docs = [], []
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
            if tag == "UseWPF":
                p.use_wpf = txt.lower() == "true"
            elif tag == "UseWindowsForms":
                p.use_wf = txt.lower() == "true"
            elif tag == "OutputType":
                p.output = txt
            elif tag in ("TargetFramework", "TargetFrameworks"):
                p.tfm = txt
            elif tag == "AssemblyName" and txt:
                p.assembly = txt
            elif tag == "ProjectReference":
                p.refs.append(os.path.splitext(os.path.basename(el.get("Include", "").replace("\\", "/")))[0])
    except ET.ParseError:
        pass
    return p


# ------------------------------------------------------------------ 検査の本体
class World:
    def __init__(self, projects):
        self.projects = projects
        self.types = OrderedDict()      # full -> CsType
        self.by_simple = defaultdict(list)
        self.docs = [d for p in projects for d in p.docs]
        self.code_keys = set()          # コードから追加されるリソースのキー
        self.dict_cache = {}
        self.stats = {"xaml": 0, "bindings": 0, "resources": 0}

    # ---- 型
    def add_types(self, ts):
        for t in ts:
            if t.full in self.types:
                self.types[t.full].merge(t)
            else:
                self.types[t.full] = t
        self.by_simple.clear()
        for t in self.types.values():
            self.by_simple[t.name].append(t)

    def resolve(self, name, ns_hint=None):
        if not name:
            return None
        if ns_hint and f"{ns_hint}.{name}" in self.types:
            return self.types[f"{ns_hint}.{name}"]
        c = self.by_simple.get(simple_type(name), [])
        return c[0] if len(c) == 1 else None

    def chain(self, t, seen=None):
        """型と、プロジェクト内の基底クラスの列。戻り値: (型のリスト, 外部の基底名のリスト)"""
        seen = seen or set()
        out, ext = [], []
        if t.full in seen:
            return out, ext
        seen.add(t.full)
        out.append(t)
        for b in t.bases:
            if re.match(r"I[A-Z]", b):          # インターフェース (命名規約)
                bt = self.resolve(b)
                if bt and bt.kind == "interface":
                    o2, e2 = self.chain(bt, seen)
                    out += o2; ext += e2
                continue
            bt = self.resolve(b)
            if bt is None:
                ext.append(b)
            else:
                o2, e2 = self.chain(bt, seen)
                out += o2; ext += e2
        return out, ext

    def closed(self, t):
        _, ext = self.chain(t)
        return all(b in CLOSED_EXTERNAL_BASES for b in ext), ext

    def has_inpc(self, t):
        ts, ext = self.chain(t)
        if any(e in INPC_BASES for e in ext):
            return True
        for x in ts:
            if "INotifyPropertyChanged" in x.bases or "PropertyChanged" in x.events or "INotifyPropertyChanged" in x.attrs:
                return True
        return any(e in DP_BASES for e in ext)

    def members(self, t):
        """型 (と基底) の、バインドできるメンバーの表: 名前 -> dict(kind, ...)"""
        out = {}
        ts, _ = self.chain(t)
        for x in reversed(ts):
            for n, m in x.methods.items():
                out[n] = {"kind": "method", **m}
            for n, f in x.fields.items():
                out[n] = {"kind": "field", **f}
                if "ObservableProperty" in f["attrs"]:
                    out[member_name_from_field(n)] = {"kind": "prop", "type": f["type"], "setter": "public", "get": True,
                                                       "public": True, "static": False, "line": f["line"], "generated": True}
            for n, m in x.props.items():
                out[n] = {"kind": "prop", **m}
            for n, m in x.methods.items():
                if "RelayCommand" in m["attrs"]:
                    base = re.sub(r"Async$", "", n)
                    out[base + "Command"] = {"kind": "prop", "type": "IRelayCommand", "setter": "none", "get": True,
                                              "public": True, "static": False, "line": m["line"], "generated": True}
        return out

    # ---- XAML の型
    def node_type(self, node):
        ns = clr_ns(node.uri)
        return self.resolve(node.local, ns) if ns else None

    def type_ref(self, text, nsmap):
        """'local:Foo' / '{x:Type local:Foo}' / 'Foo' → CsType"""
        s = (text or "").strip()
        m = re.match(r"\{\s*x:Type\s+(.+?)\s*\}$", s)
        if m:
            s = m.group(1)
        m = re.match(r"\{\s*d:DesignInstance\s+(?:Type\s*=\s*)?([\w:.]+)", s)
        if m:
            s = m.group(1)
        if ":" in s:
            pre, nm = s.split(":", 1)
            ns = clr_ns(nsmap.get(pre))
            return self.resolve(nm, ns)
        return self.resolve(s, clr_ns(nsmap.get("")))


# ---- リソース辞書
class DictInfo:
    def __init__(self):
        self.entries = []        # (key or None, node)
        self.merged = []         # (source, node)
        self.open = False
        self.container = None


def dict_info(container):
    info = DictInfo()
    info.container = container
    d = container
    if container.local.endswith(".Resources") or container.local.endswith(".MergedDictionaries"):
        rd = [c for c in container.children if c.local == "ResourceDictionary"]
        if len(rd) == 1 and container.local.endswith(".Resources"):
            d = rd[0]
            if d.attrs.get("Source"):
                info.merged.append((d.attrs["Source"], d))
    for ch in d.children:
        if ch.local == "ResourceDictionary.MergedDictionaries":
            for m in ch.children:
                if m.attrs.get("Source"):
                    info.merged.append((m.attrs["Source"], m))
                else:
                    sub = dict_info(m)
                    info.entries += sub.entries
                    info.merged += sub.merged
                    info.open = info.open or sub.open
        elif "." in ch.local:
            info.open = True                      # ThemeDictionaries など
        else:
            key = ch.attrs.get("x:Key") or ch.attrs.get("x:Name")
            if key and key.startswith("{"):
                key = None
            info.entries.append((key, ch))
    return info


def resolve_source(world, src, doc):
    """Source の文字列 → ('doc', Doc) / ('missing', パス) / ('external', None)"""
    s = src.strip()
    asm = None
    m = re.match(r"(?:pack://application:,,,)?/?([^/;]+);component/(.+)$", s, re.I)
    if m:
        asm, rel = m.group(1), m.group(2)
    else:
        m = re.match(r"pack://application:,,,/(.+)$", s, re.I)
        if m:
            rel = m.group(1)
        elif re.match(r"^[a-z]+://", s, re.I):
            return "external", None
        elif s.startswith("/"):
            rel = s[1:]
        else:
            rel = None
    if asm is not None:
        proj = next((p for p in world.projects if p.assembly.lower() == asm.lower() or p.name.lower() == asm.lower()), None)
        if proj is None:
            return "external", None
        target = os.path.normpath(os.path.join(proj.dir, rel))
    elif rel is not None:
        target = os.path.normpath(os.path.join(doc.proj.dir, rel))
    else:
        target = os.path.normpath(os.path.join(os.path.dirname(doc.path), s))
    for d in world.docs:
        if os.path.normcase(os.path.normpath(d.path)) == os.path.normcase(target):
            return "doc", d
    return "missing", target


def doc_dict(world, doc):
    if doc.path not in world.dict_cache:
        world.dict_cache[doc.path] = dict_info(doc.root) if doc.root is not None and doc.root.local == "ResourceDictionary" else None
    return world.dict_cache[doc.path]


def has_key(world, info, key, doc, state, seen=None):
    """辞書 (と、結合した辞書) に、キーがあるか。外部・未解決の辞書があれば state['open'] = True。"""
    seen = seen if seen is not None else set()
    if any(k == key for k, _ in info.entries):
        return True
    if info.open:
        state["open"] = True
    for src, node in info.merged:
        kind, tgt = resolve_source(world, src, doc)
        if kind == "doc":
            if tgt.path in seen:
                continue
            seen.add(tgt.path)
            sub = doc_dict(world, tgt)
            if sub and has_key(world, sub, key, tgt, state, seen):
                return True
        else:
            state["open"] = True
    return False


def app_dict(world):
    for d in world.docs:
        if d.root is not None and d.root.local == "Application":
            res = d.root.child_prop("Resources")
            if res is not None:
                return dict_info(res), d
    return None, None


def all_keys(world):
    if getattr(world, "_all_keys", None) is not None:
        return world._all_keys
    keys, opened = set(world.code_keys), False
    for d in world.docs:
        if d.root is None:
            continue
        for n in d.root.walk():
            if n.local.endswith(".Resources") or (n is d.root and n.local == "ResourceDictionary"):
                info = dict_info(n)
                keys |= {k for k, _ in info.entries if k}
                opened = opened or info.open
                for src, _ in info.merged:
                    if resolve_source(world, src, d)[0] != "doc":
                        opened = True
    world._all_keys = (keys, opened)
    return world._all_keys


STATIC_RES = re.compile(r"\{\s*StaticResource\s+(?:ResourceKey\s*=\s*)?([^\s{}=,]+)\s*\}")
DYNAMIC_RES = re.compile(r"\{\s*DynamicResource\s+(?:ResourceKey\s*=\s*)?([^\s{}=,]+)\s*\}")


def resource_refs(node, pattern, elem_name):
    """ノードの属性とテキストにある、リソース参照。戻り値: [(key, 属性名)]"""
    out = []
    for k, v in node.attrs.items():
        for m in pattern.finditer(v):
            out.append((m.group(1), k))
    if node.local == elem_name and node.attrs.get("ResourceKey"):
        out.append((node.attrs["ResourceKey"], "ResourceKey"))
    return out


def lookup_static(world, node, doc, key):
    """StaticResource のキーを、ノードから、祖先の Resources → アプリの辞書の順に探す。戻り値: (found, forward, open, entry_node)"""
    state = {"open": False}
    cur = node
    chain = list(node.ancestors())
    for a in chain:
        res = a if (a.local == "ResourceDictionary" and a.parent is None) else a.child_prop("Resources")
        if res is None:
            continue
        info = dict_info(res)
        d_node = res
        if res.local.endswith(".Resources"):
            rd = [c for c in res.children if c.local == "ResourceDictionary"]
            d_node = rd[0] if len(rd) == 1 else res
        entry = next((x for x in chain if x.parent is d_node), None)
        idx = next((i for i, (_, nd) in enumerate(info.entries) if nd is entry), None) if entry is not None else None
        keys_before = [k for k, _ in info.entries[:idx]] if idx is not None else [k for k, _ in info.entries]
        keys_after = [k for k, _ in info.entries[idx:]] if idx is not None else []
        if key in keys_before:
            return True, False, state["open"], None
        if idx is not None and key in keys_after and not has_key(world, DictInfoMerged(info), key, doc, state):
            return True, True, state["open"], None
        if has_key(world, DictInfoMerged(info), key, doc, state):
            return True, False, state["open"], None
        if info.open:
            state["open"] = True
    ap, adoc = app_dict(world)
    if ap and has_key(world, ap, key, adoc, state):
        return True, False, state["open"], None
    if ap is None:
        state["open"] = state["open"] or False
    return False, False, state["open"], None


class DictInfoMerged:
    """辞書の、結合した辞書だけを見るための、見かけ上の DictInfo (entries は含めない)。"""
    def __init__(self, info):
        self.entries, self.merged, self.open = [], info.merged, info.open


def find_entry(world, node, doc, key):
    """キーで、リソースの要素 (エントリ) を探す (コンバーターの型の確認用)。見つからなければ None。"""
    for a in node.ancestors():
        res = a if (a.local == "ResourceDictionary" and a.parent is None) else a.child_prop("Resources")
        if res is None:
            continue
        info = dict_info(res)
        for k, nd in info.entries:
            if k == key:
                return nd
        for src, _ in info.merged:
            kind, tgt = resolve_source(world, src, doc)
            if kind == "doc":
                sub = doc_dict(world, tgt)
                for k, nd in (sub.entries if sub else []):
                    if k == key:
                        return nd
    ap, _ = app_dict(world)
    if ap:
        for k, nd in ap.entries:
            if k == key:
                return nd
    return None


def check_resources(world, pr, doc):
    root = doc.root
    for n in root.walk():
        # RES003: 同じ辞書の重複 / RES005: Source
        if n.local.endswith(".Resources") or (n is root and n.local == "ResourceDictionary"):
            info = dict_info(n)
            seen = {}
            for k, nd in info.entries:
                if k:
                    if k in seen:
                        pr.add("RES003", "error", f"同じ辞書に、x:Key=\"{k}\" が複数ある (読み込み時に例外)", doc.rel, attr_line(doc, nd, "x:Key"))
                    seen[k] = nd
            for src, nd in info.merged:
                kind, tgt = resolve_source(world, src, doc)
                if kind == "missing":
                    pr.add("RES005", "error", f"MergedDictionaries の Source が、プロジェクト内にない: {src}", doc.rel, attr_line(doc, nd, "Source"))
        if n.local == "Application" and n.attrs.get("StartupUri"):
            kind, tgt = resolve_source(world, n.attrs["StartupUri"] if n.attrs["StartupUri"].startswith(("/", "pack:")) else "./" + n.attrs["StartupUri"], doc)
            if kind == "missing":
                pr.add("APP001", "error", f"StartupUri の XAML が、プロジェクト内にない: {n.attrs['StartupUri']}", doc.rel, attr_line(doc, n, "StartupUri"))
        # StaticResource
        for key, attr in resource_refs(n, STATIC_RES, "StaticResource"):
            world.stats["resources"] += 1
            found, forward, opened, _ = lookup_static(world, n, doc, key)
            if key in world.code_keys:
                continue
            line = attr_line(doc, n, attr)
            if forward:
                pr.add("RES002", "error", f"StaticResource \"{key}\" が、同じ辞書の後ろで定義されている (StaticResource は、読み込み時に、定義済みのキーだけを解決する。起動時に例外。順序を直すか、DynamicResource にする)", doc.rel, line)
            elif not found:
                is_lib = pr.output.lower() == "library"
                if doc.root.local == "ResourceDictionary":
                    other, _ = all_keys(world)
                    if key in other:
                        continue            # 別の辞書で、定義済み (呼び出し側が、先に結合する前提)
                if opened or is_lib:
                    why = "外部の辞書があるため、確実ではない" if opened else "ライブラリ: アプリ側の辞書で、解決される可能性がある"
                    pr.add("RES001", "warning", f"StaticResource \"{key}\" の定義が見つからない ({why})", doc.rel, line)
                else:
                    pr.add("RES001", "error", f"StaticResource \"{key}\" が、どこにも定義されていない (起動時に XamlParseException)", doc.rel, line)
        # DynamicResource
        for key, attr in resource_refs(n, DYNAMIC_RES, "DynamicResource"):
            keys, opened = all_keys(world)
            if key not in keys and not opened and not key.startswith("{"):
                pr.add("RES004", "warning", f"DynamicResource \"{key}\" が、どこにも定義されていない (黙って、既定値になる)", doc.rel, attr_line(doc, n, attr))
        # CNV001
        for k, v in n.attrs.items():
            m = re.search(r"Converter\s*=\s*\{\s*StaticResource\s+([^\s{}=,]+)\s*\}", v)
            if m:
                ent = find_entry(world, n, doc, m.group(1))
                t = world.node_type(ent) if ent is not None else None
                if t is not None:
                    ts, ext = world.chain(t)
                    names = {b for x in ts for b in x.bases}
                    if all(e in CLOSED_EXTERNAL_BASES for e in ext) and not ({"IValueConverter", "IMultiValueConverter"} & names):
                        pr.add("CNV001", "error", f"Converter \"{m.group(1)}\" のクラス {t.name} が、IValueConverter / IMultiValueConverter を実装していない", doc.rel, attr_line(doc, n, k))


# ---- バインディング
def parse_binding(text):
    """'{Binding Path, Mode=TwoWay}' → (path, {opt: val}) / None"""
    m = re.match(r"^\{\s*Binding\b(.*)\}\s*$", text.strip(), re.S)
    if not m:
        return None
    body = m.group(1).strip()
    path, opts = None, {}
    for part in split_top(body):
        if "=" in part and not part.startswith("{"):
            k, v = part.split("=", 1)
            opts[k.strip()] = v.strip()
        elif path is None and part:
            path = part
    if path is None:
        path = opts.get("Path")
    return path, opts


def first_segments(path):
    """パス → セグメントの列。解釈できない・検査しない形なら None。"""
    if path is None or path in ("", ".", "/"):
        return None
    if re.search(r"[(){}$\\/]", path.lstrip(".")) or path.startswith("."):
        return None
    segs = []
    for s in path.split("."):
        nm = re.match(r"^([A-Za-z_]\w*)(\[.*\])?$", s.strip())
        if not nm:
            return None
        segs.append(nm.group(1))
    return segs


def runtime_context(world, doc, node, design):
    """ノードの DataContext の型。戻り値: ('type', CsType, 'runtime'|'design') / ('unknown',)"""
    chain = list(node.ancestors())
    for a in chain:
        dc = a.attrs.get("DataContext")
        if dc is not None:
            t = None
            m = re.match(r"\{\s*StaticResource\s+([^\s{}=,]+)\s*\}", dc)
            if m:
                ent = find_entry(world, a, doc, m.group(1))
                t = world.node_type(ent) if ent is not None else None
                return ("type", t, "runtime") if t else ("unknown",)
            if dc.strip().startswith("{Binding"):
                pb = parse_binding(dc)
                segs = first_segments(pb[0]) if pb else None
                parent_ctx = runtime_context(world, doc, a.parent, design) if a.parent is not None else ("unknown",)
                if segs and parent_ctx[0] == "type":
                    t = walk_path_type(world, parent_ctx[1], segs)
                    if t:
                        return ("type", t, parent_ctx[2])
                return ("unknown",)
            return ("unknown",)
        prop = a.child_prop("DataContext")
        if prop is not None:
            kids = [c for c in prop.children]
            t = world.node_type(kids[0]) if len(kids) == 1 else None
            return ("type", t, "runtime") if t else ("unknown",)
        if a.local in ("DataTemplate", "HierarchicalDataTemplate"):
            dt = a.attrs.get("DataType")
            t = world.type_ref(dt, a.nsmap) if dt else None
            return ("type", t, "runtime") if t else ("unknown",)
        if a.local in ("ControlTemplate", "ItemsPanelTemplate", "Style", "ContentPresenter"):
            return ("unknown",)
        dd = a.attrs.get("d:DataContext")
        if dd and "design" not in design:
            t = world.type_ref(dd, a.nsmap)
            if t:
                design["design"] = t
    root = chain[-1]
    t = code_behind_context(world, doc)
    if t is not None:
        return ("type", t, "runtime")
    if "design" in design:
        return ("type", design["design"], "design")
    return ("unknown",)


def code_behind_context(world, doc):
    """code-behind と、ウィンドウを作るコードから、ルートの DataContext の型を推定する。"""
    cls = world.types.get(doc.cls) if doc.cls else None
    if cls is None:
        return None
    for path, _ in cls.places:
        code = world.cs_code.get(path, "")
        for m in re.finditer(r"\bDataContext\s*=\s*([^;]+);", code):
            rhs = m.group(1).strip()
            if rhs == "this":
                return cls
            mn = re.match(r"new\s+([\w.]+)", rhs)
            if mn:
                return world.resolve(mn.group(1))
            mg = re.search(r"Get\w*Service<\s*([\w.]+)\s*>", rhs)
            if mg:
                return world.resolve(mg.group(1))
            mi = re.match(r"^(?:this\.)?([A-Za-z_]\w*)$", rhs)
            if mi:
                ident = mi.group(1)
                md = re.search(r"\b([A-Z][\w<>?.]*)\s+" + re.escape(ident) + r"\b\s*[,)=;]", code)
                if md:
                    return world.resolve(md.group(1))
    # ウィンドウを作る側: new MainWindow { DataContext = new MainViewModel() } / x.DataContext = new X()
    for code in world.cs_code.values():
        m = re.search(r"new\s+" + re.escape(cls.name) + r"\s*(?:\([^)]*\))?\s*\{[^}]*DataContext\s*=\s*new\s+([\w.]+)", code)
        if m:
            return world.resolve(m.group(1))
        for mv in re.finditer(r"(?:var|" + re.escape(cls.name) + r")\s+(\w+)\s*=\s*new\s+" + re.escape(cls.name) + r"\s*\(", code):
            m2 = re.search(r"\b" + re.escape(mv.group(1)) + r"\.DataContext\s*=\s*new\s+([\w.]+)", code)
            if m2:
                return world.resolve(m2.group(1))
    return None


def walk_path_type(world, t, segs):
    cur = t
    for s in segs:
        if cur is None:
            return None
        mem = world.members(cur).get(s)
        if not mem or mem["kind"] != "prop":
            return None
        cur = world.resolve(simple_type(mem["type"]))
    return cur


def near(name, names):
    low = {n.lower(): n for n in names}
    if name.lower() in low and low[name.lower()] != name:
        return low[name.lower()]
    best, bd = None, 3
    for n in names:
        if abs(len(n) - len(name)) >= 3:
            continue
        d = lev(name.lower(), n.lower())
        if d < bd:
            best, bd = n, d
    return best


def lev(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def check_bindings(world, pr, doc):
    root = doc.root
    inpc_missing = defaultdict(set)          # 型 -> プロパティ名
    unresolved = set()
    for n in root.walk():
        items = [(k, v) for k, v in n.attrs.items() if not k.startswith(("x:", "d:")) and "{Binding" in v.replace("{ Binding", "{Binding")]
        if n.local == "Binding" and n.attrs.get("Path"):
            items.append(("Path", "{Binding " + n.attrs["Path"] + "}"))
        for attr, val in items:
            pb = parse_binding(val.replace("{ Binding", "{Binding"))
            if pb is None:
                continue
            path, opts = pb
            if any(k in opts for k in ("Source", "ElementName", "RelativeSource")):
                continue
            segs = first_segments(path)
            if not segs:
                continue
            if any(a.local in ("ControlTemplate", "ItemsPanelTemplate", "Style") for a in n.ancestors()) and not any(
                    a.local in ("DataTemplate", "HierarchicalDataTemplate") for a in n.ancestors()):
                continue
            world.stats["bindings"] += 1
            node_for_ctx = n.parent if attr == "DataContext" and n.parent is not None else n
            ctx = runtime_context(world, doc, node_for_ctx, {})
            line = attr_line(doc, n, attr)
            if ctx[0] != "type":
                continue
            t, certainty = ctx[1], ctx[2]
            closed, ext = world.closed(t)
            sev_missing = "error" if certainty == "runtime" else "warning"
            cur = t
            for si, seg in enumerate(segs):
                closed, ext = world.closed(cur)
                mems = world.members(cur)
                m = mems.get(seg)
                if m is None:
                    if closed:
                        sug = near(seg, [k for k, v in mems.items() if v["kind"] == "prop"])
                        pr.add("BND001", sev_missing, f"{{Binding {path}}}: {cur.name} にプロパティ \"{seg}\" がない" + (f" (もしかして: {sug})" if sug else ""), doc.rel, line)
                    else:
                        unresolved.add((cur.name, tuple(ext)))
                    break
                if m["kind"] == "method":
                    pr.add("BND001", sev_missing, f"{{Binding {path}}}: \"{seg}\" は {cur.name} のメソッド (バインドできるのはプロパティ。Command には ICommand のプロパティが要る)", doc.rel, line)
                    break
                if m["kind"] == "field":
                    if m.get("public") and not m.get("static"):
                        pr.add("BND002", sev_missing, f"{{Binding {path}}}: \"{seg}\" は {cur.name} の public フィールド (WPF はプロパティしかバインドできない。{{ get; set; }} にする)", doc.rel, line)
                    else:
                        pr.add("BND001", sev_missing, f"{{Binding {path}}}: \"{seg}\" は {cur.name} の非 public フィールド (バインドできない)", doc.rel, line)
                    break
                if not m.get("public", True) or m.get("static"):
                    why = "public でない" if not m.get("public", True) else "static"
                    pr.add("BND001", sev_missing if not m.get("public", True) else "warning",
                           f"{{Binding {path}}}: \"{seg}\" は {cur.name} の{why}プロパティ (インスタンスの public プロパティしか、バインドされない)", doc.rel, line)
                    break
                last = si == len(segs) - 1
                if last:
                    mode = opts.get("Mode", "").strip()
                    explicit_two = mode in ("TwoWay", "OneWayToSource")
                    default_two = not mode and (n.local, attr) in TWOWAY_DEFAULT
                    readonly = m["setter"] in ("none", "restricted") and not m.get("generated")
                    if (explicit_two or default_two) and readonly:
                        sev = "error" if m["setter"] == "none" else "warning"
                        what = "読み取り専用" if m["setter"] == "none" else "setter が public でない"
                        pr.add("BND003", sev,
                               f"{{Binding {path}}}: \"{seg}\" は {cur.name} の{what}プロパティ ({'TwoWay' if explicit_two else attr + ' は既定で TwoWay'}。実行時に例外)", doc.rel, line)
                    if attr == "Command":
                        tn = simple_type(m["type"])
                        ct = world.resolve(tn)
                        if tn in NON_COMMAND_TYPES:
                            pr.add("CMD001", "warning", f"Command=\"{{Binding {path}}}\": \"{seg}\" の型 {tn} は、ICommand ではない", doc.rel, line)
                        elif ct is not None and world.closed(ct)[0]:
                            nm = {b for x in world.chain(ct)[0] for b in x.bases}
                            if "ICommand" not in nm and not tn.endswith("Command"):
                                pr.add("CMD001", "warning", f"Command=\"{{Binding {path}}}\": \"{seg}\" の型 {tn} は、ICommand を実装していない", doc.rel, line)
                    if mode != "OneTime" and m["setter"] == "public" and not m.get("static") and not world.has_inpc(cur) and closed:
                        inpc_missing[cur.full].add(seg)
                nt = world.resolve(simple_type(m["type"]))
                if nt is None and not last:
                    break
                cur = nt if nt is not None else cur
    for full, props in inpc_missing.items():
        t = world.types[full]
        pr.add("BND004", "warning", f"{t.name} が INotifyPropertyChanged を実装していない (バインドしている {', '.join(sorted(props)[:4])} を変えても、画面は更新されない)",
               pr.rel(t.places[0][0]), t.places[0][1])
    for name, ext in sorted(unresolved):
        pr.add("BND900", "info", f"{name} の基底クラス ({', '.join(ext) or '不明'}) が外部にあり、バインディングを検査できない", doc.rel, None)


def check_init_component(world, pr, doc):
    root = doc.root
    if root.local in ("Application",) or not doc.cls:
        return
    t = world.types.get(doc.cls)
    if t is None or t.kind != "class":
        return
    if not t.ctors:
        pr.add("UI001", "error", f"{t.name} に、コンストラクターがない (InitializeComponent() が呼ばれず、画面が空になる)", pr.rel(t.places[0][0]), t.places[0][1])
        return
    if not any(re.search(r"\bInitializeComponent\s*\(", body) for body in t.ctors):
        # this(...) で、別のコンストラクターに委譲する書き方があるので、どれか 1 つでも呼んでいれば、指摘しない
        pr.add("UI001", "error", f"{t.name} のコンストラクターが、InitializeComponent() を呼んでいない (画面が空になる)", pr.rel(t.places[0][0]), t.places[0][1])


# ---- 層
def layer_of(pr, names):
    n = pr.name
    if re.search(r"Tests?$", n):
        return "test"
    if n in names["logic"]:
        return "logic"
    if n in names["data"]:
        return "data"
    if n in names["vm"]:
        return "vm"
    if pr.use_wpf and pr.output.lower() in ("winexe", "exe"):
        return "ui"
    if re.search(r"viewmodels?$", n, re.I):
        return "vm"
    if re.search(r"logic|domain|core", n, re.I):
        return "logic"
    if re.search(r"data", n, re.I):
        return "data"
    if pr.use_wpf:
        return "ui"
    return None


RANK = {"data": 0, "logic": 1, "vm": 2, "ui": 3}


def std_layer(name):
    """標準の層の名前 (Domain / Application / Infrastructure / Presentation。末尾が一致) なら、小文字で返す。"""
    m = re.search(r"(?:^|\.)(Domain|Application|Infrastructure|Presentation)$", name)
    return m.group(1).lower() if m else None


def is_vm_file(world, L, path):
    return L == "vm" or re.search(r"ViewModel", os.path.basename(path)) or any(
        t.name.endswith("ViewModel") for t in world.types.values() if any(pl[0] == path for pl in t.places))


def check_vm_file(pr, path, code):
    """ViewModel のファイルが、View の型・ダイアログ・Service の生成を、使っていないか。"""
    m = WPF_USING.search(code) or WPF_USAGE.search(code) or VIEW_USING.search(code)
    if m:
        pr.add("LAY002", "warning", f"ViewModel が、View の型を使っている: {m.group(0).strip()} (テストしにくい。IDialogService などに分ける)", pr.rel(path), lineno(code, m.start()))
    m = NEW_SERVICE.search(code)
    if m:
        pr.add("DI001", "warning", f"ViewModel 内で、{m.group(0).strip()} を生成している (コンストラクターインジェクションで受け取る)", pr.rel(path), lineno(code, m.start()))


def check_code_rules(world, pr):
    """プロジェクトの全ファイルに共通の規則 (非同期・例外・名前)。テストプロジェクトでは、呼ばない。"""
    for path, raw, code in pr.cs:
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
    for t in world.types.values():
        if t.proj is not pr:
            continue
        for kind, table in (("プロパティ", t.props), ("フィールド", t.fields)):
            for n, m in table.items():
                if simple_type(m["type"]) in ("bool", "Boolean") and n.lstrip("_").lower() in VAGUE_BOOL:
                    pr.add("NAM001", "warning", f"bool の{kind}名 \"{n}\" が曖昧 (IsXxx / HasXxx / CanXxx のように、状態や判定と分かる名前にする)", pr.rel(t.places[0][0]), m.get("line"))


def check_std_layer(world, by, pr, S):
    """標準の層 (Presentation / Application / Domain / Infrastructure) の、依存と WPF への依存を検査する。"""
    for ref in pr.refs:
        q = by.get(ref)
        Q = std_layer(q.name) if q else None
        if Q and Q != S and Q not in STD_ALLOWED[S]:
            pr.add("LAY003", "error", f"{pr.name} ({S}) が {q.name} ({Q}) を参照している (標準の依存: Presentation → Application → Domain、Infrastructure → Application / Domain。Domain は、何も参照しない)",
                   pr.rel(pr.csproj) if pr.csproj else None)
    if S != "presentation" and (pr.use_wpf or pr.use_wf or "-windows" in pr.tfm):
        pr.add("LAY001", "error", f"{S} 層の {pr.name} が、WPF / Windows に依存している (UseWPF / UseWindowsForms / TargetFramework {pr.tfm or '?'}。Windows 非依存にする)",
               pr.rel(pr.csproj) if pr.csproj else None)
    for path, raw, code in pr.cs:
        if S != "presentation":
            m = WPF_USING.search(code) or WPF_USAGE.search(code)
            if m:
                pr.add("LAY001", "error", f"{S} 層で、WPF の型を使っている: {m.group(0).strip()}", pr.rel(path), lineno(code, m.start()))
        elif is_vm_file(world, "vm", path) and "ViewModel" in os.path.basename(path):
            check_vm_file(pr, path, code)


def check_layering(world, projects, names):
    by = {p.name: p for p in projects}
    for pr in projects:
        L = layer_of(pr, names)
        if L != "test":
            check_code_rules(world, pr)
        explicit = pr.name in names["logic"] or pr.name in names["data"] or pr.name in names["vm"]   # --logic / --data / --viewmodel は、名前による推定より優先する
        S = std_layer(pr.name) if L != "test" and not explicit else None
        if S:
            check_std_layer(world, by, pr, S)
            continue
        if L in (None, "test"):
            continue
        for ref in pr.refs:
            q = by.get(ref)
            Q = layer_of(q, names) if q else None
            if q and Q in RANK and L in RANK and RANK[L] < RANK[Q]:
                pr.add("LAY003", "error", f"{pr.name} ({L}) が {q.name} ({Q}) を参照している (View → ViewModel → ロジック → データの向きに反する)", pr.rel(pr.csproj) if pr.csproj else None)
        if L in ("logic", "data", "vm") and (pr.use_wpf or pr.use_wf or "-windows" in pr.tfm):   # ViewModel 層も WPF 非依存 (規約。WS13 の実機で、検査が漏れていた)
            pr.add("LAY001", "error", f"{'ViewModel' if L == 'vm' else L} 層の {pr.name} が、WPF / Windows に依存している (UseWPF / UseWindowsForms / TargetFramework {pr.tfm or '?'}。net8.0 などの、Windows 非依存にする)", pr.rel(pr.csproj) if pr.csproj else None)
        for path, raw, code in pr.cs:
            if L in ("logic", "data"):
                m = WPF_USING.search(code) or WPF_USAGE.search(code)
                if m:
                    pr.add("LAY001", "error", f"{L} 層で、WPF の型を使っている: {m.group(0).strip()}", pr.rel(path), lineno(code, m.start()))
            elif is_vm_file(world, L, path):
                check_vm_file(pr, path, code)


# UI テスト (FlaUI) で操作するコントロール。AutomationProperties.AutomationId か x:Name (= AutomationId になる) が要る。
UI_INTERACTIVE = {"Button", "ToggleButton", "RepeatButton", "TextBox", "PasswordBox", "ComboBox", "CheckBox", "RadioButton",
                  "ListBox", "ListView", "DataGrid", "Slider", "TreeView", "TabControl"}


def check_ui_automation_ids(world, pr, doc):
    """UI002: ソリューションに UI テストのプロジェクト (*.UITests) があるとき、操作できるコントロールに AutomationId がない。"""
    if not getattr(world, "ui_tests", False) or not pr.use_wpf:
        return
    for n in doc.root.walk():
        if n.local not in UI_INTERACTIVE:
            continue
        # テンプレート・スタイルの中は、繰り返し使われるので、対象外
        if any(a is not n and (a.local.endswith("Template") or a.local == "Style" or a.local.endswith(".Resources")) for a in n.ancestors()):
            continue
        if n.attrs.get("AutomationProperties.AutomationId") or n.attrs.get("x:Name") or n.attrs.get("Name"):
            continue
        pr.add("UI002", "warning", f"<{n.local}> に AutomationId がない (UI テストで探せない。AutomationProperties.AutomationId を付ける)", doc.rel, n.line)


def check_xaml_rules(world, pr, doc):
    """XAML の規則: UserControl が、自分自身を DataContext にしない。UI テストがあるとき、操作するコントロールに AutomationId がある。"""
    check_ui_automation_ids(world, pr, doc)
    root = doc.root
    if root.local != "UserControl":
        return
    for n in root.walk():
        dc = n.attrs.get("DataContext", "")
        if "RelativeSource" in dc and re.search(r"\bSelf\b", dc):
            pr.add("UI003", "warning", "UserControl が、自分自身を DataContext に設定している (親の View から継承される DataContext を壊す。依存関係プロパティで値を受け取る)",
                   doc.rel, attr_line(doc, n, "DataContext"))


# ------------------------------------------------------------------ 実行
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
            if low.endswith(".cs") and not low.endswith((".g.cs", ".g.i.cs", ".designer.cs")):
                raw = read_text(path)
                pr.cs.append((path, raw, strip_cs(raw)))
            elif low.endswith(".xaml"):
                pr.docs.append(Doc(path, pr.rel(path), pr, open(path, "rb").read()))
    world = World(projects)
    world.ui_tests = any(re.search(r"UITests?$", pr.name) or re.search(r"UiTests?$", pr.name) for pr in projects)   # UI テストのプロジェクトがあるか (UI002 の条件)
    world.cs_code = {}
    for pr in projects:
        for path, raw, code in pr.cs:
            world.cs_code[path] = code
            world.add_types(parse_cs(code, path, pr))
            for m in re.finditer(r"\bResources(?:\[\s*\"([^\"]*)\"\s*\]|\.Add\(\s*\"([^\"]*)\")", raw):
                world.code_keys.add(m.group(1) or m.group(2))
    for pr in projects:
        pr.checked = bool(pr.docs) or pr.use_wpf
        for doc in pr.docs:
            world.stats["xaml"] += 1
            if doc.root is None:
                pr.add("XAML001", "info", "XAML を XML として解析できなかった (このファイルの検査を省略)", doc.rel, None)
                continue
            check_resources(world, pr, doc)
            check_bindings(world, pr, doc)
            check_init_component(world, pr, doc)
            check_xaml_rules(world, pr, doc)
    check_layering(world, projects, names)
    return projects, world


def summarize(projects, include_info, max_lines):
    findings = [f for pr in projects for f in pr.findings if include_info or f["severity"] != "info"]
    findings.sort(key=lambda f: (SEV_ORDER[f["severity"]], f["project"], f["code"], f["file"] or "", f["line"] or 0))
    n = {s: sum(1 for f in findings if f["severity"] == s) for s in SEV_ORDER}
    checked = [pr.name for pr in projects if pr.checked]
    out = [f"wpf-check: error {n['error']} / warning {n['warning']}" + (f" / info {n['info']}" if include_info else "")
           + f" ({len(checked)} projects: {', '.join(checked[:6])}{'...' if len(checked) > 6 else ''})"]
    for i, f in enumerate(findings, 1):
        out.append(f"[{i}] {f['severity']:7s} {f['code']} {f['message']}")
        if f["file"]:
            out.append(f"      {f['file']}" + (f"({f['line']})" if f["line"] else ""))
    out = [s[:400] for s in out]
    if len(out) > max_lines:
        out = out[:max_lines - 1] + [f"... ({len(findings)} findings in total; see --json)"]
    return out, n, findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--json")
    ap.add_argument("--max-lines", type=int, default=40)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--logic", action="append", default=[])
    ap.add_argument("--data", action="append", default=[])
    ap.add_argument("--viewmodel", action="append", default=[])
    a = ap.parse_args()
    if not os.path.isdir(a.dir):
        print(f"BAD_ARGS: not a directory: {a.dir}")
        return 2
    projects, world = run(a.dir, {"logic": set(a.logic), "data": set(a.data), "vm": set(a.viewmodel)})
    if not any(pr.checked for pr in projects):
        print("wpf-check: nothing to check (no WPF project / .xaml found)")
        return 3
    out, n, findings = summarize(projects, a.all, a.max_lines)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump({"counts": n, "stats": world.stats, "findings": [fi for pr in projects for fi in pr.findings]},
                      f, ensure_ascii=False, indent=2)
    sys.stdout.write("\n".join(out) + "\n")
    return 1 if n["error"] else 0


if __name__ == "__main__":
    sys.exit(main())
