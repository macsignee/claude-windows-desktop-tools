#!/usr/bin/env python3
"""ui_guideline_check.py - UI デザインガイドライン (references/UI-Design-Guidelines.md) のうち、静的に判定できる規則を検査する。

WPF (XAML)、WinForms (*.Designer.cs)、MFC (.rc / .vcxproj) の、ソースを読むだけ。実行も、Windows も、要らない。
読み取り専用 (ファイルは、変えない)。

Usage: ui_guideline_check.py PROJECT_DIR [--all] [--json FILE] [--fail-on-warning]
終了コード: 0 = 完了 (指摘があっても 0。--fail-on-warning のときは、warning があれば 1)
            2 = 引数が不正 / 3 = 検査する対象 (XAML / Designer.cs / .rc / .vcxproj / .csproj) がない

指摘は、ガイドラインの規則の、**ヒューリスティック (推測) による検出**。必須の規則に対するものは warning、推奨は info。
例外: UIG-CTL101 は、必須の規則だが、違反かを静的に判定できず、人の確認を促すだけなので、info。
通ったことは、規則を満たすことを意味しない (見た目・操作・表示は、人が確認する)。
"""
import argparse
import io
import json
import os
import re
import sys
import xml.sax

GUIDELINE_VERSION = "2.10"

SKIP_DIRS = {
    "bin", "obj", ".git", ".vs", ".claude", ".claude-logs", "node_modules", "packages",
    "TestResults", "Debug", "Release", "x64", "x86", "ipch", "poc",
}

# code: (規則 ID, 重大度, 一行の説明)。重大度: 必須の規則への指摘は warning、推奨は info (例外: UIG-CTL101)
RULES = {
    "UIG-KEY006": ("UI-KEY-006", "warning", "アクセスキーが、同じ画面で重複している"),
    "UIG-CTL091": ("UI-CTL-091", "warning", "破壊的な操作のボタンが、既定のボタンになっている"),
    "UIG-LAY007": ("UI-LAY-007", "info", "既定のボタンが、1 つの画面に複数ある"),
    "UIG-CTL003": ("UI-CTL-003", "warning", "アイコンだけのボタンに、アクセシブル名がない"),
    "UIG-CTL003T": ("UI-CTL-003", "warning", "アイコンだけのボタンに、ツールチップがない"),
    "UIG-ACC001": ("UI-ACC-001", "warning", "入力コントロールに、アクセシブル名がない"),
    "UIG-LAY005": ("UI-LAY-005", "warning", "コントロールを、座標 (Canvas) で配置している"),
    "UIG-TYP001": ("UI-TYP-001", "warning", "独自のフォントを指定している"),
    "UIG-LOC001": ("UI-LOC-001", "warning", "表示文字列が、XAML に直書きされている"),
    "UIG-DPI001": ("UI-DPI-001", "warning", "AutoScaleMode が None (DPI に追従しない)"),
    "UIG-DPI002": ("UI-DPI-002", "warning", "DPI 認識モードの宣言が見つからない"),
    "UIG-CTL100": ("UI-CTL-100", "warning", "MFC: Common Controls 6.0 以降のマニフェストの記述が見つからない"),
    "UIG-CTL100V": ("UI-CTL-100", "warning", "MFC: Common Controls のバージョンが 6.0 未満、または、記述が衝突している"),
    "UIG-CTL100U": ("UI-CTL-100", "warning", "MFC: Unicode 文字セットでビルドされていない"),
    "UIG-CTL101": ("UI-CTL-101", "info", "MFC の DLL に、ダイアログがある (ユーザー DLL のマニフェストは、静的に確認できない)"),
}

DESTRUCTIVE = re.compile(r"削除|消去|破棄|初期化|上書|リセット|Delete|Remove|Discard|Overwrite|Erase|Format\b|Reset\b", re.I)
ICON_FONT = re.compile(r"^(Segoe (MDL2|Fluent)|Marlett|Webdings|Wingdings)", re.I)
SAFE_FONT = re.compile(r"^(Segoe UI|Yu Gothic|Meiryo|MS UI Gothic|Consolas|Cascadia|Courier New|Lucida Console)", re.I)
DPI_EVIDENCE = re.compile(r"dpiaware|SetProcessDpiAwareness|SetProcessDPIAware|ApplicationHighDpiMode|HighDpiMode|PerMonitor", re.I)

findings = []
stats = {"xaml": 0, "designer": 0, "rc": 0, "dotnet_projects": 0, "mfc_projects": 0}


def add(code, path, line, message, hint=""):
    rule, sev, _ = RULES[code]
    findings.append({"code": code, "rule": rule, "severity": sev, "file": path, "line": line,
                     "message": message, "hint": hint})


def read_text(path):
    b = open(path, "rb").read()
    if b.startswith((b"\xff\xfe", b"\xfe\xff")):
        return b.decode("utf-16", errors="replace")
    try:
        return b.decode("utf-8-sig")
    except UnicodeDecodeError:
        return b.decode("cp932", errors="replace")


def walk_files(root):
    for d, dirs, files in os.walk(root):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS and not x.startswith("."))
        for f in sorted(files):
            yield os.path.join(d, f)


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


def amp_key(label):
    s = label.replace("&&", "")
    m = re.search(r"&(\S)", s)
    return m.group(1).lower() if m else None


def underscore_key(label):
    s = label.replace("__", "")
    m = re.search(r"_([A-Za-z0-9])", s)
    return m.group(1).lower() if m else None


# --------------------------------------------------------------------------- XAML
class Node:
    __slots__ = ("tag", "attrs", "line", "children", "parent", "text")

    def __init__(self, tag, attrs, line, parent):
        self.tag, self.attrs, self.line, self.parent = tag, attrs, line, parent
        self.children, self.text = [], ""


class Builder(xml.sax.ContentHandler):
    def __init__(self):
        super().__init__()
        self.root, self.stack, self.loc = None, [], None

    def setDocumentLocator(self, loc):
        self.loc = loc

    def startElement(self, name, attrs):
        parent = self.stack[-1] if self.stack else None
        n = Node(name, dict(attrs.items()), self.loc.getLineNumber() if self.loc else 0, parent)
        if parent:
            parent.children.append(n)
        else:
            self.root = n
        self.stack.append(n)

    def endElement(self, name):
        self.stack.pop()

    def characters(self, content):
        if self.stack:
            self.stack[-1].text += content


def parse_xaml(path):
    b = open(path, "rb").read()
    h = Builder()
    try:
        xml.sax.parse(io.BytesIO(b), h)
    except Exception:
        return None
    return h.root


def local(tag):
    return tag.split(":")[-1]


def walk(n):
    yield n
    for c in n.children:
        yield from walk(c)


TEMPLATE_TAGS = {"DataTemplate", "ControlTemplate", "HierarchicalDataTemplate", "ItemsPanelTemplate", "Style", "ResourceDictionary"}


def in_template(n):
    p = n.parent
    while p:
        lt = local(p.tag)
        if lt in TEMPLATE_TAGS or lt.endswith(".Resources") or lt.endswith(".Triggers"):
            return True
        p = p.parent
    return False


def name_of(n):
    return n.attrs.get("x:Name") or n.attrs.get("Name") or ""


def has_text(n):
    for d in walk(n):
        if local(d.tag).endswith(".ToolTip"):
            continue
        for k in ("Content", "Text", "Header"):
            v = d.attrs.get(k)
            if v and v.strip():
                return True
        if d.text.strip():
            return True
    return False


def content_elements(n):
    out = []
    for d in walk(n):
        if d is n:
            continue
        lt = local(d.tag)
        if "." in lt or lt in ("Setter", "Style", "Trigger"):
            continue
        out.append(d)
    return out


def has_tooltip(n):
    if "ToolTip" in n.attrs or "ToolTipService.ToolTip" in n.attrs:
        return True
    return any(local(c.tag).endswith(".ToolTip") for c in n.children)


def has_acc_name(n):
    return "AutomationProperties.Name" in n.attrs or "AutomationProperties.LabeledBy" in n.attrs


BUTTON_TAGS = {"Button", "ToggleButton", "RepeatButton"}
INPUT_TAGS = {"TextBox", "PasswordBox", "ComboBox", "DatePicker"}
CANVAS_CHILD_TAGS = {"Button", "TextBox", "ComboBox", "CheckBox", "RadioButton", "Label", "TextBlock",
                     "ListBox", "DatePicker", "PasswordBox", "Slider", "ToggleButton"}


def label_targets(root):
    names = set()
    for n in walk(root):
        if local(n.tag) == "Label" and "Target" in n.attrs:
            t = n.attrs["Target"]
            for m in re.finditer(r"ElementName\s*=\s*(\w+)|x:Reference\s+(?:Name\s*=\s*)?(\w+)", t):
                names.add(m.group(1) or m.group(2))
    return names


def check_xaml(path, rel, loc):
    root = parse_xaml(path)
    if root is None or local(root.tag) in ("ResourceDictionary", "Application"):
        return
    stats["xaml"] += 1
    targets = label_targets(root)

    # アクセスキーの重複 (UI-KEY-006)。メニューは、メニューごとに、別の範囲
    scopes = {}
    for n in walk(root):
        if in_template(n):
            continue
        for attr in ("Content", "Header"):
            v = n.attrs.get(attr)
            if not v or v.startswith("{"):
                continue
            k = underscore_key(v)
            if k is None:
                continue
            p, scope = n.parent, "window"
            while p:
                if local(p.tag) in ("Menu", "ContextMenu", "MenuItem"):
                    scope = id(p)
                    break
                p = p.parent
            scopes.setdefault((scope, k), []).append(n)
    for (_, k), nodes in scopes.items():
        if len(nodes) > 1:
            add("UIG-KEY006", rel, nodes[1].line,
                "アクセスキー _%s が、この画面で %d 回使われている (行 %s)" % (k.upper(), len(nodes), ", ".join(str(x.line) for x in nodes)),
                "別の文字にする (UI-KEY-006)")

    defaults = []
    for n in walk(root):
        if in_template(n):
            continue
        lt = local(n.tag)
        if lt in BUTTON_TAGS and n.attrs.get("IsDefault", "").lower() == "true":
            defaults.append(n)
            label = " ".join([n.attrs.get("Content", ""), name_of(n), n.attrs.get("Command", ""),
                              n.attrs.get("AutomationProperties.AutomationId", "")])
            if DESTRUCTIVE.search(label):
                add("UIG-CTL091", rel, n.line, "破壊的な操作と思われるボタン (%s) が、IsDefault になっている" % (n.attrs.get("Content") or name_of(n)),
                    "既定のボタンを、安全な側 (キャンセルなど) にする。確認ダイアログも同様 (UI-CTL-091)")
        if lt in BUTTON_TAGS and not has_text(n) and content_elements(n):
            if not has_acc_name(n):
                add("UIG-CTL003", rel, n.line, "アイコンだけのボタン (%s) に、AutomationProperties.Name がない" % (name_of(n) or lt),
                    "AutomationProperties.Name を付ける (UI-CTL-003)")
            if not has_tooltip(n):
                add("UIG-CTL003T", rel, n.line, "アイコンだけのボタン (%s) に、ToolTip がない" % (name_of(n) or lt),
                    "ToolTip を付ける (UI-CTL-003)")
        if lt in INPUT_TAGS and not has_acc_name(n) and name_of(n) not in targets:
            add("UIG-ACC001", rel, n.line, "%s (%s) に、アクセシブル名がない" % (lt, name_of(n) or "x:Name なし"),
                "AutomationProperties.Name / LabeledBy を付けるか、Label の Target で結ぶ。TextBlock は、名前にならない (UI-ACC-001)")
        if lt == "Canvas":
            pos = [c for c in n.children if local(c.tag) in CANVAS_CHILD_TAGS
                   and any(k in c.attrs for k in ("Canvas.Left", "Canvas.Top", "Canvas.Right", "Canvas.Bottom"))]
            if pos:
                add("UIG-LAY005", rel, n.line, "Canvas で、%d 個のコントロールを、座標で配置している" % len(pos),
                    "Grid / StackPanel / DockPanel にする (UI-LAY-005)")
        for k in ("FontFamily",):
            v = n.attrs.get(k)
            if v and not v.startswith("{"):
                first = v.split(",")[0].strip()
                if not SAFE_FONT.match(first) and not ICON_FONT.match(first):
                    add("UIG-TYP001", rel, n.line, "FontFamily=\"%s\" を指定している" % v, "Windows 標準の UI フォントに従う (UI-TYP-001)")
        if lt == "Setter" and n.attrs.get("Property") == "FontFamily":
            v = n.attrs.get("Value", "")
            if v and not v.startswith("{"):
                first = v.split(",")[0].strip()
                if not SAFE_FONT.match(first) and not ICON_FONT.match(first):
                    add("UIG-TYP001", rel, n.line, "Setter で FontFamily=\"%s\" を指定している" % v, "Windows 標準の UI フォントに従う (UI-TYP-001)")
    if len(defaults) > 1:
        add("UIG-LAY007", rel, defaults[1].line, "IsDefault のボタンが %d 個ある" % len(defaults), "既定のボタンは、1 つにする (UI-LAY-007)")

    # 表示文字列の直書き (UI-LOC-001): 件数だけを、集計する
    for n in walk(root):
        lt = local(n.tag)
        keys = ["Content", "Header", "Title", "ToolTip"] + (["Text"] if lt in ("TextBlock", "Run") else [])
        for k in keys:
            v = n.attrs.get(k)
            if v and not v.startswith("{") and re.search(r"[A-Za-z぀-ヿ一-鿿]", v):
                loc["count"] += 1
                if loc["first"] is None:
                    loc["first"] = (rel, n.line)


# --------------------------------------------------------------------------- WinForms (Designer.cs)
MENU_TYPE = re.compile(r"ToolStrip|MenuItem|MenuStrip|ContextMenu", re.I)


def check_designer(path, rel):
    text = read_text(path)
    if "InitializeComponent" not in text or "System.Windows.Forms" not in text and "SuspendLayout" not in text:
        return
    stats["designer"] += 1
    types, texts, images, accnames = {}, {}, {}, set()
    accept, accept_line = None, 0
    for i, line in enumerate(text.split("\n"), 1):
        m = re.search(r"^\s*(?:this\.)?(\w+)\s*=\s*new\s+(?:System\.Windows\.Forms\.)?(\w+)\s*\(", line)
        if m:
            types[m.group(1)] = m.group(2)
        m = re.search(r"^\s*(?:this\.)?(\w+)\.Text\s*=\s*\"((?:[^\"\\]|\\.)*)\"\s*;", line)
        if m:
            texts[m.group(1)] = (m.group(2), i)
        m = re.search(r"^\s*(?:this\.)?(\w+)\.(?:Image|ImageIndex|ImageKey|BackgroundImage)\s*=", line)
        if m:
            images.setdefault(m.group(1), i)
        m = re.search(r"^\s*(?:this\.)?(\w+)\.(?:AccessibleName|ToolTipText)\s*=", line)
        if m:
            accnames.add(m.group(1))
        m = re.search(r"AcceptButton\s*=\s*(?:this\.)?(\w+)", line)
        if m:
            accept, accept_line = m.group(1), i
        m = re.search(r"AutoScaleMode\s*=\s*(?:System\.Windows\.Forms\.)?AutoScaleMode\.(\w+)", line)
        if m and m.group(1) == "None":
            add("UIG-DPI001", rel, i, "AutoScaleMode が None になっている", "AutoScaleMode.Dpi または Font にする (UI-DPI-001)")
    seen = {}
    for var, (s, ln) in texts.items():
        if MENU_TYPE.search(types.get(var, "")):
            continue
        k = amp_key(s.replace("\\\"", "\""))
        if k:
            seen.setdefault(k, []).append((var, ln))
    for k, items in seen.items():
        if len(items) > 1:
            add("UIG-KEY006", rel, items[1][1], "アクセスキー &%s が、%d 個のコントロールで使われている (%s)" % (k.upper(), len(items), ", ".join(v for v, _ in items)),
                "別の文字にする (UI-KEY-006)")
    if accept and accept in texts and DESTRUCTIVE.search(texts[accept][0] + " " + accept):
        add("UIG-CTL091", rel, accept_line, "破壊的な操作と思われるボタン (%s) が、AcceptButton になっている" % accept,
            "AcceptButton を、安全な側にする (UI-CTL-091)")
    for var, ln in images.items():
        if types.get(var) in ("Button", "ToolStripButton") and not texts.get(var, ("", 0))[0].strip() and var not in accnames:
            add("UIG-CTL003", rel, ln, "アイコンだけのボタン (%s) に、AccessibleName がない" % var, "AccessibleName を付ける (UI-CTL-003)")


# --------------------------------------------------------------------------- MFC (.rc / .vcxproj)
CTRL_RE = re.compile(r'^\s*(DEFPUSHBUTTON|PUSHBUTTON|LTEXT|RTEXT|CTEXT|CONTROL|GROUPBOX|AUTOCHECKBOX|AUTORADIOBUTTON|CHECKBOX|RADIOBUTTON|AUTO3STATE|STATE3)\s+"((?:[^"]|"")*)"')
DLG_RE = re.compile(r"^\s*(\w+)\s+DIALOG(?:EX)?\b")


def check_rc(path, rel):
    text = read_text(path)
    dialogs = 0
    state, name, controls = 0, "", []
    for i, line in enumerate(text.split("\n"), 1):
        m = DLG_RE.match(line)
        if m and state == 0:
            state, name, controls = 1, m.group(1), []
            continue
        if state == 1 and line.strip() == "BEGIN":
            state = 2
            continue
        if state == 2 and line.strip() == "END":
            dialogs += 1
            seen, defs = {}, []
            for kind, s, ln in controls:
                k = amp_key(s.replace('""', '"'))
                if k:
                    seen.setdefault(k, []).append(ln)
                if kind == "DEFPUSHBUTTON":
                    defs.append((s, ln))
            for k, lns in seen.items():
                if len(lns) > 1:
                    add("UIG-KEY006", rel, lns[1], "ダイアログ %s: アクセスキー &%s が、%d 回使われている (行 %s)" % (name, k.upper(), len(lns), ", ".join(map(str, lns))),
                        "別の文字にする (UI-KEY-006)")
            for s, ln in defs:
                if DESTRUCTIVE.search(s):
                    add("UIG-CTL091", rel, ln, "ダイアログ %s: 破壊的な操作と思われるボタン (%s) が、DEFPUSHBUTTON になっている" % (name, s),
                        "既定のボタンを、安全な側にする (UI-CTL-091)")
            if len(defs) > 1:
                add("UIG-LAY007", rel, defs[1][1], "ダイアログ %s: DEFPUSHBUTTON が %d 個ある" % (name, len(defs)), "既定のボタンは、1 つにする (UI-LAY-007)")
            state = 0
            continue
        if state == 2:
            m = CTRL_RE.match(line)
            if m:
                controls.append((m.group(1), m.group(2), i))
    if dialogs:
        stats["rc"] += 1
    return dialogs


def version_tuple(v):
    return tuple(int(x) for x in v.split(".") if x.isdigit())


def project_files(proj_dir):
    for p in walk_files(proj_dir):
        yield p


def attr_region(t, pos):
    """pos を含む、XML のタグ (<...>)、または、1 行 (#pragma など) の文字列を返す。"""
    lt, gt = t.rfind("<", 0, pos), t.find(">", pos)
    if lt != -1 and gt != -1 and "<" not in t[pos:gt] and ">" not in t[lt:pos]:
        return t[lt:gt]
    a = t.rfind("\n", 0, pos) + 1
    b = t.find("\n", pos)
    return t[a: len(t) if b == -1 else b]


def check_mfc_project(vcx, root):
    proj_dir = os.path.dirname(vcx)
    rel = os.path.relpath(vcx, root)
    stats["mfc_projects"] += 1
    vtext = read_text(vcx)
    # Unicode 文字セット
    for m in re.finditer(r"<CharacterSet>(\w+)</CharacterSet>", vtext):
        if m.group(1) != "Unicode":
            add("UIG-CTL100U", rel, line_of(vtext, m.start()), "CharacterSet が %s になっている" % m.group(1),
                "Unicode 文字セットにする。Common Controls は Unicode のみ対応 (UI-CTL-100)")
            break
    # Common Controls のマニフェスト
    versions = []
    dpi = bool(DPI_EVIDENCE.search(vtext))
    has_dialog = False
    for p in project_files(proj_dir):
        ext = os.path.splitext(p)[1].lower()
        if ext not in (".h", ".hpp", ".cpp", ".rc", ".rc2", ".manifest", ".vcxproj", ".props"):
            continue
        t = read_text(p)
        if DPI_EVIDENCE.search(t):
            dpi = True
        if ext == ".rc" and re.search(r"\bDIALOG(EX)?\b", t):
            has_dialog = True
        for m in re.finditer(r"Microsoft\.Windows\.Common-Controls", t):
            vm = re.search(r"version\s*=\s*['\"]?([\d.]+)", attr_region(t, m.start()))
            if vm:
                versions.append((version_tuple(vm.group(1)), os.path.relpath(p, root), line_of(t, m.start())))
    for d in (root,):
        for fn in ("Directory.Build.props", "Directory.Build.targets"):
            fp = os.path.join(d, fn)
            if os.path.isfile(fp) and DPI_EVIDENCE.search(read_text(fp)):
                dpi = True
    if not versions:
        add("UIG-CTL100", rel, 1, "Common Controls (Microsoft.Windows.Common-Controls) のマニフェストの記述が、ソース・リソース・プロジェクトのどこにもない",
            "pch.h などに、`#pragma comment(linker, \"/manifestdependency:...\")` を書く。実行ファイルは、リソース ID 1 (UI-CTL-100)")
    else:
        distinct = sorted({v for v, _, _ in versions})
        if distinct[0] < (6,) or len(distinct) > 1:
            _, f, ln = versions[0]
            add("UIG-CTL100V", f, ln, "Common Controls の指定が、6.0 未満、または、異なる版が混在している (%s)" % ", ".join(".".join(map(str, v)) for v in distinct),
                "6.0.0.0 に、そろえる。内容が衝突すると、マニフェストが壊れて、起動しない (UI-CTL-100)")
    if not dpi:
        add("UIG-DPI002", rel, 1, "DPI 認識モードの宣言 (dpiAware など) が、プロジェクトの中に見つからない",
            "アプリケーションマニフェストなどで、DPI 認識モードを明示する (UI-DPI-002)")
    if has_dialog and re.search(r"<ConfigurationType>DynamicLibrary</ConfigurationType>", vtext):
        add("UIG-CTL101", rel, 1, "MFC の DLL に、ダイアログがある", "ユーザー DLL は、マニフェストをリソース ID 2 で組み込む。手作業で確認する (UI-CTL-101)")


# --------------------------------------------------------------------------- .NET (WPF / WinForms) の exe
def check_dotnet_project(csproj, root):
    t = read_text(csproj)
    if not re.search(r"<OutputType>\s*WinExe\s*</OutputType>", t, re.I):
        return
    if not re.search(r"<Use(WPF|WindowsForms)>\s*true\s*</Use(WPF|WindowsForms)>", t, re.I):
        return
    stats["dotnet_projects"] += 1
    proj_dir = os.path.dirname(csproj)
    dpi = bool(DPI_EVIDENCE.search(t))
    for p in project_files(proj_dir):
        ext = os.path.splitext(p)[1].lower()
        if ext in (".manifest", ".cs", ".props", ".config", ".csproj") and DPI_EVIDENCE.search(read_text(p)):
            dpi = True
            break
    if not dpi:
        for fn in ("Directory.Build.props", "Directory.Build.targets"):
            fp = os.path.join(root, fn)
            if os.path.isfile(fp) and DPI_EVIDENCE.search(read_text(fp)):
                dpi = True
    if not dpi:
        add("UIG-DPI002", os.path.relpath(csproj, root), 1, "DPI 認識モードの宣言 (app.manifest の dpiAware / ApplicationHighDpiMode など) が、見つからない",
            "アプリケーションマニフェストなどで、DPI 認識モードを明示する。DPI 非対応にしない (UI-DPI-002)")


# --------------------------------------------------------------------------- 実行
def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("project")
    ap.add_argument("--all", action="store_true", help="info (推奨の規則への指摘と、人の確認を促すもの) も表示する")
    ap.add_argument("--json", dest="json_out")
    ap.add_argument("--fail-on-warning", action="store_true")
    try:
        a = ap.parse_args(argv)
    except SystemExit:
        return 2
    root = os.path.abspath(a.project)
    if not os.path.isdir(root):
        print("ui-guideline-check: フォルダがない: %s" % a.project, file=sys.stderr)
        return 2

    loc = {"count": 0, "first": None}
    files = list(walk_files(root))
    for p in files:
        rel = os.path.relpath(p, root).replace(os.sep, "/")
        low = p.lower()
        if low.endswith(".xaml"):
            check_xaml(p, rel, loc)
        elif low.endswith(".designer.cs"):
            check_designer(p, rel)
        elif low.endswith(".rc"):
            check_rc(p, rel)
    for p in files:
        low = p.lower()
        if low.endswith(".vcxproj"):
            if re.search(r"<UseOfMfc>\s*(Dynamic|Static)\s*</UseOfMfc>", read_text(p)):
                check_mfc_project(p, root)
        elif low.endswith(".csproj"):
            check_dotnet_project(p, root)
    if loc["count"]:
        f, ln = loc["first"]
        add("UIG-LOC001", f, ln, "XAML に、表示文字列の直書きが、全部で %d 個ある (最初の 1 件の位置)" % loc["count"],
            "ローカライズが要る場合は、リソースにする (UI-LOC-001)")

    checked = sum(stats.values())
    if checked == 0:
        print("ui-guideline-check: 検査する対象 (XAML / *.Designer.cs / MFC の .rc・.vcxproj / WPF・WinForms の .csproj) がない")
        return 3

    for f in findings:
        f["file"] = f["file"].replace(os.sep, "/")
    counts = {"error": 0, "warning": sum(1 for f in findings if f["severity"] == "warning"),
              "info": sum(1 for f in findings if f["severity"] == "info")}
    shown = [f for f in findings if f["severity"] == "warning" or a.all]
    parts = ["XAML %d" % stats["xaml"], "Designer.cs %d" % stats["designer"], ".rc(ダイアログあり) %d" % stats["rc"],
             "MFC プロジェクト %d" % stats["mfc_projects"], ".NET の exe %d" % stats["dotnet_projects"]]
    print("ui-guideline-check (ガイドライン v%s): error 0 / warning %d (%s)" % (GUIDELINE_VERSION, counts["warning"], ", ".join(parts)))
    if counts["info"] and not a.all:
        print("  info %d 件は、--all で表示する" % counts["info"])
    for i, f in enumerate(shown, 1):
        print("[%d] %-7s %s (%s) %s" % (i, f["severity"], f["code"], f["rule"], f["message"]))
        print("      %s(%d)" % (f["file"], f["line"]))
        if f["hint"]:
            print("      → %s" % f["hint"])
    if a.json_out:
        with open(a.json_out, "w", encoding="utf-8") as fp:
            json.dump({"guideline_version": GUIDELINE_VERSION, "counts": counts, "stats": stats, "findings": findings}, fp, ensure_ascii=False, indent=2)
    if a.fail_on_warning and counts["warning"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
