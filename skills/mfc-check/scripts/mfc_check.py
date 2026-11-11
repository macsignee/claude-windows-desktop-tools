#!/usr/bin/env python3
"""mfc_check.py - MFC の「コンパイルは通るが、実行時に壊れる」部分を、静的に検査する (読み取り専用)。

Usage: mfc_check.py <dir> [--json <out.json>] [--max-lines 40] [--all]
                          [--logic <プロジェクト名>]... [--data <プロジェクト名>]...

<dir> 以下の .vcxproj を、プロジェクトとして検査する (.vcxproj がなければ、<dir> 全体を 1 つとして扱う)。
.rc は UTF-16 / UTF-8 (BOM) / CP932 のどれでも読める。

検査 (コード / 重大度: error = ほぼ確実な不具合、warning = 疑わしい、info = 参考):
  RES001 error   未定義の ID (コード・.rc で使っているが、resource.h にも、標準 ID にもない)。リソース定義の名前だけの場合は、warning (名前付きリソース)
  RES002 error   コマンド ID の値の重複 (別の名前が、同じ値。メッセージが、別の項目に届く)
  RES003 error   同じダイアログ内の、コントロール ID の値の重複
  RES004 error   同じ種類のリソースで、別の名前が、同じ値
  RES005 info    resource.h にあるが、どこでも使われていない ID
  MAP001 error   メッセージマップのハンドラが、クラスに宣言されていない
  MAP002 error   ハンドラが、宣言されているが、定義がない
  MAP003 error   BEGIN_MESSAGE_MAP があるが、クラスに DECLARE_MESSAGE_MAP がない
  MAP004 error   DECLARE_MESSAGE_MAP があるが、BEGIN_MESSAGE_MAP がない
  MAP005 warning afx_msg のハンドラが、メッセージマップに登録されていない (呼ばれない)
  MAP006 warning ハンドラの引数の数が、マクロの想定と違う
  MAP007 warning 同じメッセージマップに、同じ ID の ON_COMMAND が重複
  MAP008 info    ハンドラに afx_msg が付いていない
  UI001  warning ON_COMMAND の ID が、.rc のメニュー・アクセラレータ・ツールバーにない (コードから送る場合を除く)
  UI002  warning コントロール通知の ID が、.rc のダイアログにない (コードで作る場合を除く)
  UI003  warning DDX / DDV のコントロール ID が、.rc のダイアログにない
  UI004  warning UI テストのプロジェクト (*.UITests) があるとき、ダイアログの操作できるコントロール (ボタン・エディット・コンボなど) の ID が IDC_STATIC (-1) のまま、または、同じダイアログで、ID が重複している (UI テストの AutomationId = コントロール ID なので、ID で探せない)
  DLG001 error   DDX / DDV のコントロール ID が、そのクラスのダイアログ (IDD) にない
  DLG002 error   ダイアログクラスの IDD が、.rc に DIALOG として存在しない (DoModal が失敗する)
  DLG003 error   DDX_Control のメンバーの型が、ダイアログのコントロールの種類と違う
  DLG004 warning ダイアログのボタンに、ハンドラがない (押しても何も起きない)
  DLG005 warning ダイアログに、既定ボタン (DEFPUSHBUTTON) が複数ある
  DLG006 warning OnInitDialog が、基底クラスの OnInitDialog を呼んでいない
  DLG007 warning DoDataExchange が、基底クラスの DoDataExchange を呼んでいない
  DLG008 info    同じダイアログに、同じニーモニック (&X) が重複
  DLG009 info    AFX_DIALOG_LAYOUT が、存在しないダイアログのもの (VS が残した、不要な定義)
  DLG010 warning 同じメンバーを、複数の DDX_Control に渡している (2 回目以降は、MFC が何もしない)
  NSP001 warning CObject 派生のクラス (CDialog / CView / CDocument / CFrameWnd などを含む) が、名前空間の中にある (v2.89.0)
  DEC001 warning CObject 派生のクラスに、DECLARE_DYNAMIC / DECLARE_DYNCREATE / DECLARE_SERIAL がない (CWinApp / CWinThread 派生は除く)
  LAY001 error   ライブラリ (DLL / lib) で、GUI のクラスを使っている
  LAY002 warning ライブラリで、GUI のヘッダーを include している (pch / framework は info)
  LIB001 error   MFC の静的ライブラリ (StaticLibrary + UseOfMfc) を参照する exe / DLL / 静的ライブラリの UseOfMfc が、違う (v2.87.0)
  LAY003 error   プロジェクト参照の方向が、層 (UI → ロジック → データ) に反する

終了コード: 0 = error なし / 1 = error あり / 2 = 引数が不正 / 3 = 検査する対象がない。
"""
import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import OrderedDict, defaultdict

SKIP_DIRS = {".git", ".vs", "x64", "x86", "Win32", "ARM64", "Debug", "Release", "obj", "packages",
             "ThirdParty", "icu4c", "node_modules"}
CODE_EXT = (".cpp", ".cc", ".cxx", ".h", ".hpp", ".hh", ".inl")
SEV_ORDER = {"error": 0, "warning": 1, "info": 2}

ID_TOKEN = re.compile(r"\b(?:ID[A-Z]{0,2}_[A-Z0-9_]+|IDOK|IDCANCEL|IDYES|IDNO|IDABORT|IDRETRY|IDIGNORE|IDCLOSE|IDHELP"
                      r"|IDTRYAGAIN|IDCONTINUE|IDTIMEOUT)\b")
STD_PREFIXES = ("AFX_", "ID_FILE_", "ID_EDIT_", "ID_VIEW_", "ID_WINDOW_", "ID_APP_", "ID_HELP", "ID_INDICATOR_",
                "ID_OLE_", "ID_NEXT_PANE", "ID_PREV_PANE", "ID_CONTEXT_HELP", "ID_DEFAULT_HELP", "ID_SEPARATOR",
                "ID_RECORD_", "IDW_", "IDC_SIZE", "IDS_AFX", "IDP_OLE", "IDP_FAILED", "IDR_AFX")
STD_NAMES = {"IDOK", "IDCANCEL", "IDYES", "IDNO", "IDABORT", "IDRETRY", "IDIGNORE", "IDCLOSE", "IDHELP", "IDTRYAGAIN",
             "IDCONTINUE", "IDTIMEOUT", "IDC_STATIC", "IDC_ARROW", "IDC_IBEAM", "IDC_WAIT", "IDC_CROSS",
             "IDC_UPARROW", "IDC_HAND", "IDC_NO", "IDC_HELP", "IDC_APPSTARTING", "IDC_SIZEALL", "IDI_APPLICATION",
             "IDI_ASTERISK", "IDI_ERROR", "IDI_EXCLAMATION", "IDI_HAND", "IDI_INFORMATION", "IDI_QUESTION",
             "IDI_WARNING", "IDI_WINLOGO", "IDI_SHIELD", "ID_SEPARATOR"}

# ON_WM_xxx の、既知のハンドラ名と引数の数 (未知のマクロは、名前の一致だけを見る)
WM_TABLE = {
    "CREATE": ("OnCreate", 1), "DESTROY": ("OnDestroy", 0), "SIZE": ("OnSize", 3), "PAINT": ("OnPaint", 0),
    "CLOSE": ("OnClose", 0), "TIMER": ("OnTimer", 1), "ERASEBKGND": ("OnEraseBkgnd", 1),
    "LBUTTONDOWN": ("OnLButtonDown", 2), "LBUTTONUP": ("OnLButtonUp", 2), "LBUTTONDBLCLK": ("OnLButtonDblClk", 2),
    "RBUTTONDOWN": ("OnRButtonDown", 2), "RBUTTONUP": ("OnRButtonUp", 2), "MOUSEMOVE": ("OnMouseMove", 2),
    "MOUSEWHEEL": ("OnMouseWheel", 3), "KEYDOWN": ("OnKeyDown", 3), "KEYUP": ("OnKeyUp", 3), "CHAR": ("OnChar", 3),
    "SETFOCUS": ("OnSetFocus", 1), "KILLFOCUS": ("OnKillFocus", 1), "CONTEXTMENU": ("OnContextMenu", 2),
    "DROPFILES": ("OnDropFiles", 1), "HSCROLL": ("OnHScroll", 3), "VSCROLL": ("OnVScroll", 3),
    "SYSCOMMAND": ("OnSysCommand", 2), "QUERYDRAGICON": ("OnQueryDragIcon", 0),
    "GETMINMAXINFO": ("OnGetMinMaxInfo", 1), "ACTIVATE": ("OnActivate", 3), "SHOWWINDOW": ("OnShowWindow", 2),
    "CTLCOLOR": ("OnCtlColor", 3), "SETCURSOR": ("OnSetCursor", 3), "SIZING": ("OnSizing", 2), "MOVE": ("OnMove", 2),
}
# 明示ハンドラのマクロの、引数の数 (引数の数が、固定のもの)
PARAM_COUNT = {"ON_COMMAND": 0, "ON_COMMAND_EX": 1, "ON_COMMAND_RANGE": 1, "ON_UPDATE_COMMAND_UI": 1,
               "ON_UPDATE_COMMAND_UI_RANGE": 1, "ON_CONTROL": 0, "ON_CONTROL_RANGE": 1, "ON_NOTIFY": 2,
               "ON_NOTIFY_RANGE": 3, "ON_MESSAGE": 2, "ON_REGISTERED_MESSAGE": 2}
NOTIFY_PREFIX = re.compile(r"^ON_(?:BN|EN|CBN|LBN|STN)_")
GUI_CLASSES = re.compile(r"\b(?:CWnd|CDialog|CDialogEx|CView|CFormView|CScrollView|CDocument|CFrameWnd|CMDIFrameWnd|"
                         r"CMDIChildWnd|CButton|CEdit|CListCtrl|CTreeCtrl|CComboBox|CListBox|CStatic|CPropertySheet|"
                         r"CPropertyPage|CToolBar|CStatusBar|AfxGetMainWnd|AfxMessageBox)\b")
GUI_HEADERS = re.compile(r"#\s*include\s*[<\"](?:afxwin|afxext|afxdlgs|afxcmn|afxcontrolbars|afxdisp|afxdtctl|afxpriv|"
                         r"afxole|afxodlgs)\.h[>\"]")
PCH_NAMES = {"framework.h", "pch.h", "stdafx.h"}
DIALOG_BASES = {"CDialog", "CDialogEx", "CPropertyPage", "CMFCPropertyPage", "CFormView", "CDHtmlDialog"}
NO_INITDIALOG = {"CFormView"}       # CFormView は OnInitDialog ではなく OnInitialUpdate
# MFC 標準のコントロールクラス -> .rc 上の種類 (DDX_Control の型の検査に使う。自作の派生クラスは、判定しない)
MFC_CTRL_CATEGORY = {"CEdit": "edit", "CButton": "button", "CStatic": "static", "CComboBox": "combobox",
                     "CListBox": "listbox", "CListCtrl": "syslistview32", "CTreeCtrl": "systreeview32",
                     "CProgressCtrl": "msctls_progress32", "CSliderCtrl": "msctls_trackbar32",
                     "CSpinButtonCtrl": "msctls_updown32", "CTabCtrl": "systabcontrol32", "CRichEditCtrl": "richedit",
                     "CDateTimeCtrl": "sysdatetimepick32", "CMonthCalCtrl": "sysmonthcal32", "CScrollBar": "scrollbar",
                     "CIPAddressCtrl": "sysipaddress32"}
KEYWORD_CATEGORY = {"EDITTEXT": "edit", "COMBOBOX": "combobox", "LISTBOX": "listbox", "SCROLLBAR": "scrollbar",
                    "PUSHBUTTON": "button", "DEFPUSHBUTTON": "button", "GROUPBOX": "button", "CHECKBOX": "button",
                    "RADIOBUTTON": "button", "AUTOCHECKBOX": "button", "AUTORADIOBUTTON": "button",
                    "AUTO3STATE": "button", "STATE3": "button", "LTEXT": "static", "CTEXT": "static",
                    "RTEXT": "static", "ICON": "static"}
STD_BUTTON_IDS = {"IDOK", "IDCANCEL", "IDHELP", "IDABORT", "IDRETRY", "IDIGNORE", "IDYES", "IDNO", "IDCLOSE",
                  "IDTRYAGAIN", "IDCONTINUE"}


# ------------------------------------------------------------------ 読み込み
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


def strip_code(t, blank_strings=True):
    """コメント (と、既定では文字列の中身) を空白にする。改行は残す (行番号を保つ)。"""
    out, i, n = [], 0, len(t)
    while i < n:
        c = t[i]
        two = t[i:i + 2]
        if two == "//":
            j = t.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif two == "/*":
            j = t.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in t[i:j])); i = j
        elif c == '"' or (c == "'" and not (i > 0 and (t[i - 1].isalnum() or t[i - 1] == "_"))):
            q, j = c, i + 1
            while j < n and t[j] != q and t[j] != "\n":
                j += 2 if t[j] == "\\" else 1
            j = min(j + 1, n)
            seg = t[i:j]
            out.append(q + "".join(" " for _ in seg[1:-1]) + q if blank_strings and len(seg) >= 2 else seg); i = j
        else:
            out.append(c); i += 1
    return "".join(out)


def lineno(t, pos):
    return t.count("\n", 0, pos) + 1


def split_args(s):
    args, depth, cur, in_q = [], 0, [], False
    for ch in s:
        if ch == '"':
            in_q = not in_q
        if not in_q and ch in "([{":
            depth += 1
        elif not in_q and ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0 and not in_q:
            args.append("".join(cur).strip()); cur = []
        else:
            cur.append(ch)
    last = "".join(cur).strip()
    if last or args:
        args.append(last)
    return args


def match_brace(t, open_pos):
    depth = 0
    for i in range(open_pos, len(t)):
        if t[i] == "{":
            depth += 1
        elif t[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(t) - 1


def is_standard(name):
    return name in STD_NAMES or name.startswith(STD_PREFIXES)


# ------------------------------------------------------------------ プロジェクト
class Project:
    def __init__(self, name, path, root):
        self.name, self.dir, self.root = name, path, root
        self.kind = None            # Application / DynamicLibrary / StaticLibrary / None
        self.mfc = set()
        self.cfg = {}               # 構成 ("Debug|x64") -> {"mfc": UseOfMfc, "defs": PreprocessorDefinitions の集合}
        self.refs = []
        self.files = []             # (相対パス, 生のテキスト)
        self.findings = []

    def rel(self, p):
        return os.path.relpath(p, self.root).replace(os.sep, "/")

    def add(self, code, sev, msg, path=None, line=None):
        self.findings.append({"code": code, "severity": sev, "message": msg, "project": self.name,
                              "file": path, "line": line})


def collect_files(d):
    out = []
    for cur, ds, fs in os.walk(d):
        ds[:] = [x for x in ds if x not in SKIP_DIRS and not x.startswith(".")]
        for f in fs:
            out.append(os.path.join(cur, f))
    return out


CFG_KEY = re.compile(r"==\s*'([^']+)'")


def cfg_of(p, el):
    m = CFG_KEY.search(el.get("Condition", ""))
    return p.cfg.setdefault(m.group(1) if m else "", {"mfc": None, "defs": set()})


def load_project(vcx, root):
    p = Project(os.path.splitext(os.path.basename(vcx))[0], os.path.dirname(vcx), root)
    try:
        for el in ET.parse(vcx).getroot().iter():
            tag = el.tag.split("}")[-1]
            if tag == "ConfigurationType" and el.text and not p.kind:
                p.kind = el.text.strip()
            elif tag == "UseOfMfc" and el.text:
                p.mfc.add(el.text.strip())
            elif tag == "PropertyGroup" and el.get("Label") == "Configuration":
                for ch in el:
                    if ch.tag.split("}")[-1] == "UseOfMfc" and ch.text:
                        cfg_of(p, el)["mfc"] = ch.text.strip()
            elif tag == "ItemDefinitionGroup":
                for ch in el.iter():
                    if ch.tag.split("}")[-1] == "PreprocessorDefinitions" and ch.text:
                        cfg_of(p, el)["defs"] |= {d.strip() for d in ch.text.split(";") if d.strip() and not d.startswith("%")}
            elif tag == "ProjectReference":
                inc = el.get("Include", "")
                p.refs.append(os.path.splitext(os.path.basename(inc.replace("\\", "/")))[0])
    except ET.ParseError:
        pass
    return p


# ------------------------------------------------------------------ .rc
BLOCK_TYPES = ("DIALOGEX", "DIALOG", "MENUEX", "MENU", "ACCELERATORS", "TOOLBAR", "STRINGTABLE", "VERSIONINFO",
               "DESIGNINFO", "AFX_DIALOG_LAYOUT", "RCDATA")
SINGLE_TYPES = ("ICON", "BITMAP", "CURSOR", "HTML")
RC_HEAD = re.compile(r"^\s*(?:(\w+)\s+)?(%s)\b" % "|".join(BLOCK_TYPES + SINGLE_TYPES))
TEXT_FIRST = {"CONTROL", "LTEXT", "CTEXT", "RTEXT", "PUSHBUTTON", "DEFPUSHBUTTON", "GROUPBOX", "CHECKBOX",
              "RADIOBUTTON", "AUTOCHECKBOX", "AUTORADIOBUTTON", "AUTO3STATE", "STATE3", "ICON"}
ID_FIRST = {"EDITTEXT", "COMBOBOX", "LISTBOX", "SCROLLBAR", "BEDIT", "HEDIT", "IEDIT"}


def parse_rc(text):
    """-> dict(defs, dialogs, menu_ids, accel_ids, toolbar_ids, string_ids, ids, defines)"""
    lines = strip_code(text, blank_strings=False).split("\n")
    hits, skip = [], set()          # ID の出現 (名前, 行) と、使用に数えない行 (VS のメタデータ)
    r = {"defs": [], "dialogs": OrderedDict(), "dlgctrls": OrderedDict(), "layouts": {}, "_skip": skip, "menu": {}, "accel": {}, "toolbar": {}, "strings": {}, "ids": {},
         "defines": set()}
    for no, ln in enumerate(lines, 1):
        for m in ID_TOKEN.finditer(re.sub(r'"(?:[^"]|"")*"', '""', ln)):
            hits.append((m.group(0), no))
        d = re.match(r"^\s*#\s*define\s+(\w+)", ln)
        if d:
            r["defines"].add(d.group(1))
    i = 0
    while i < len(lines):
        m = RC_HEAD.match(lines[i])
        if not m or lines[i].lstrip().startswith("#"):
            i += 1
            continue
        name, typ = m.group(1), m.group(2)
        if typ in SINGLE_TYPES:
            if name:
                r["defs"].append((name, typ, i + 1))
            i += 1
            continue
        # BEGIN を探して、対応する END まで
        j = i
        while j < len(lines) and not re.search(r"\bBEGIN\b|\{", re.sub(r'"[^"]*"', '""', lines[j])):
            j += 1
        depth, k, body = 0, j, []
        while k < len(lines):
            s = re.sub(r'"(?:[^"]|"")*"', '""', lines[k])
            depth += len(re.findall(r"\bBEGIN\b|\{", s)) - len(re.findall(r"\bEND\b|\}", s))
            body.append((k + 1, lines[k]))
            if depth <= 0 and k >= j:
                break
            k += 1
        if name and typ != "STRINGTABLE":
            r["defs"].append((name, typ, i + 1))
        parse_block(r, name, typ, body, i + 1)
        i = k + 1
    for nm, no in hits:
        if no not in skip:
            r["ids"].setdefault(nm, no)
    del r["_skip"]
    return r


def parse_block(r, name, typ, body, head_line=0):
    if typ in ("DIALOGEX", "DIALOG"):
        ctrls, rich, buf, start = [], [], "", 0
        for no, ln in body[1:-1]:
            if not buf:
                start = no
            buf += " " + ln.strip()
            if buf.rstrip().endswith(","):
                continue
            km = re.match(r"^\s*([A-Z0-9]+)\s+(.*)$", buf)
            buf = ""
            if not km or (km.group(1) not in TEXT_FIRST and km.group(1) not in ID_FIRST):
                continue
            args = split_args(km.group(2))
            idx = 1 if km.group(1) in TEXT_FIRST else 0
            if len(args) > idx and (ID_TOKEN.fullmatch(args[idx]) or re.fullmatch(r"-?\d+", args[idx])):
                ctrls.append((args[idx], start))
                kw = km.group(1)
                cls = args[2].strip('"').lower() if kw == "CONTROL" and len(args) > 2 else None
                rich.append({"id": args[idx], "line": start, "kw": kw, "cls": cls,
                             "text": args[0].strip('"') if kw in TEXT_FIRST and args else "",
                             "style": args[3] if kw == "CONTROL" and len(args) > 3 else ""})
        r["dialogs"][name] = ctrls
        r["dlgctrls"][name] = rich
    elif typ in ("MENU", "MENUEX"):
        for no, ln in body:
            mm = re.search(r'MENUITEM\s+(?:"(?:[^"]|"")*"|\w+)\s*,\s*(\w+)', ln)
            if mm:
                r["menu"].setdefault(mm.group(1), no)
    elif typ == "ACCELERATORS":
        for no, ln in body[1:-1]:
            mm = re.match(r'^\s*("(?:[^"]|\\")*"|[A-Za-z0-9_]+)\s*,\s*([A-Za-z0-9_]+)\s*,', ln)
            if mm:
                r["accel"].setdefault(mm.group(2), no)
    elif typ == "TOOLBAR":
        for no, ln in body:
            mm = re.match(r"^\s*BUTTON\s+(\w+)", ln)
            if mm:
                r["toolbar"].setdefault(mm.group(1), no)
    elif typ == "AFX_DIALOG_LAYOUT":
        r["layouts"][name] = head_line
        r["_skip"].add(head_line)           # 見出し行の ID は、使用ではない
    elif typ == "DESIGNINFO":
        r["_skip"].update(no for no, _ in body)   # VS のデザイナのメタデータ
    elif typ == "STRINGTABLE":
        for no, ln in body[1:-1]:
            mm = re.match(r'^\s*(\w+)\s+"', ln)
            if mm:
                r["strings"].setdefault(mm.group(1), no)


# ------------------------------------------------------------------ ソース
CLASS_RE = re.compile(r"\b(?:class|struct)\s+([A-Za-z_][\w\s]*?)\s*(:[^;{]*)?\{")


def find_classes(code, path):
    out = []
    for m in CLASS_RE.finditer(code):
        before = code[max(0, m.start() - 6):m.start()]
        if re.search(r"\benum\s*$", before):
            continue
        words = [w for w in m.group(1).split() if w != "final"]
        if not words:
            continue
        o = m.end() - 1
        c = match_brace(code, o)
        out.append({"name": words[-1], "file": path, "line": lineno(code, m.start()), "body": code[o:c + 1],
                    "bases": m.group(2) or "", "span": (o, c)})
    for a in out:                   # own: 入れ子のクラスの本体を空白にした、そのクラス自身の本体
        chars = list(a["body"])
        for b in out:
            if b is not a and a["span"][0] < b["span"][0] and b["span"][1] < a["span"][1]:
                for k in range(b["span"][0] - a["span"][0], b["span"][1] - a["span"][0] + 1):
                    if chars[k] != "\n":
                        chars[k] = " "
        a["own"] = "".join(chars)
    return out


def parse_maps(code, path):
    out = []
    for m in re.finditer(r"BEGIN_MESSAGE_MAP\s*\(\s*([\w:]+)\s*,\s*([\w:]+)\s*\)(.*?)END_MESSAGE_MAP\s*\(\s*\)", code, re.S):
        entries = []
        for e in re.finditer(r"\b(ON_[A-Z0-9_]+)\s*\(([^()]*)\)", m.group(3)):
            entries.append({"macro": e.group(1), "args": split_args(e.group(2)),
                            "line": lineno(code, m.start(3) + e.start())})
        out.append({"cls": m.group(1).split("::")[-1], "base": m.group(2), "file": path, "line": lineno(code, m.start()),
                    "entries": entries, "start": m.start(), "end": m.end()})
    return out


def param_count(params):
    ps = [p for p in split_args(params) if p.strip()]
    if len(ps) == 1 and ps[0].strip() == "void":
        return 0, 0
    return sum(1 for p in ps if "=" not in p), len(ps)


def handler_of(entry, cls):
    """-> (handler 名 or None, 修飾クラス or None, 期待する引数の数 or None, 暗黙か)"""
    mac = entry["macro"]
    if mac.startswith("ON_WM_"):
        suffix = mac[len("ON_WM_"):]
        if suffix == "CTLCOLOR_REFLECT":
            return "CtlColor", None, 2, True
        if suffix.endswith("_REFLECT"):
            suffix = suffix[:-len("_REFLECT")]
        if suffix in WM_TABLE:
            return WM_TABLE[suffix][0], None, WM_TABLE[suffix][1], True
        return "On" + suffix, None, None, True
    if not entry["args"]:
        return None, None, None, False
    h = entry["args"][-1].lstrip("&").strip()
    qual = None
    if "::" in h:
        qual, h = [x.strip() for x in h.rsplit("::", 1)]
        qual = qual.split("::")[-1].strip()
    if not re.fullmatch(r"\w+", h):
        return None, None, None, False
    exp = PARAM_COUNT.get(mac)
    if exp is None and NOTIFY_PREFIX.match(mac):
        exp = 0
    return h, qual, exp, False


def check_resources(p, resh, rcs, codes, rcinfo):
    defines = {}
    if resh:
        t = strip_code(read_text(resh))
        for m in re.finditer(r"^\s*#\s*define\s+(\w+)\s+(-?(?:0[xX][0-9a-fA-F]+|\d+))\b", t, re.M):
            defines.setdefault(m.group(1), (int(m.group(2), 0), lineno(t, m.start())))
    rel_h = p.rel(resh) if resh else None
    # コード中で、自前に定義された名前 (#define / enum / constexpr) は、定義済みとして扱う
    local_defs = set()
    for path, code in codes:
        local_defs.update(re.findall(r"#\s*define\s+(ID\w*)", code))
        local_defs.update(re.findall(r"\b(ID\w+)\s*=[^=]", code))
    for rc in rcinfo.values():
        local_defs.update(rc["defines"])
    used = OrderedDict()   # 名前 -> (ファイル, 行)
    for path, code in codes:
        if resh and os.path.samefile(path, resh):
            continue
        for m in ID_TOKEN.finditer(code):
            used.setdefault(m.group(0), (p.rel(path), lineno(code, m.start())))
    for rcpath, rc in rcinfo.items():
        for name, no in rc["ids"].items():
            used.setdefault(name, (p.rel(rcpath), no))
    # RES001
    rc_def_names = {n for rc in rcinfo.values() for n, _, _ in rc["defs"]}
    for name, (f, no) in used.items():
        if name not in defines and name not in local_defs and not is_standard(name):
            if name in rc_def_names and not any(name in rc[k] for rc in rcinfo.values()
                                               for k in ("menu", "accel", "toolbar")):
                # リソース定義の名前が、未定義: RC は、名前付きリソースとして、受け付ける (数値 ID では、参照できない)
                p.add("RES001", "warning", f"名前付きリソース: {name} (resource.h に数値がない。数値 ID では参照できない)", f, no)
            else:
                p.add("RES001", "error", f"未定義の ID: {name} (resource.h にない)", f, no)
    # RES005
    for name, (val, no) in defines.items():
        if name not in used and not name.startswith(("_APS_", "IDC_STATIC")) and rel_h:
            p.add("RES005", "info", f"どこでも使われていない ID: {name}", rel_h, no)
    # コマンド ID の値の重複 (使われているもの同士)
    cmd_users = set()
    for rc in rcinfo.values():
        cmd_users.update(rc["menu"], rc["accel"], rc["toolbar"])
    for mp in p.maps:
        for e in mp["entries"]:
            if e["macro"] in ("ON_COMMAND", "ON_COMMAND_EX", "ON_UPDATE_COMMAND_UI") and e["args"]:
                cmd_users.add(e["args"][0])
    by_val = defaultdict(list)
    for name in cmd_users:
        if name in defines and re.match(r"^ID[M]?_", name):
            by_val[defines[name][0]].append(name)
    for val, names in by_val.items():
        if len(names) > 1:
            p.add("RES002", "error", "コマンド ID の値が重複: " + " と ".join(f"{n}={val}" for n in sorted(names)),
                  rel_h, min(defines[n][1] for n in names))
    # RES003: 同じダイアログ内
    for rcpath, rc in rcinfo.items():
        for dlg, ctrls in rc["dialogs"].items():
            seen = defaultdict(list)
            for idn, no in ctrls:
                v = defines[idn][0] if idn in defines else (int(idn) if re.fullmatch(r"-?\d+", idn) else None)
                if v is None or v == -1 or idn in STD_NAMES:
                    continue
                seen[v].append((idn, no))
            for v, items in seen.items():
                if len(items) > 1:
                    p.add("RES003", "error", f"ダイアログ {dlg} のコントロール ID の値が重複: "
                          + " と ".join(f"{n}={v}" for n, _ in items), p.rel(rcpath), items[0][1])
    # RES004: 同じ種類で、別の名前が同じ値
    for rcpath, rc in rcinfo.items():
        by_type = defaultdict(lambda: defaultdict(set))
        for name, typ, no in rc["defs"]:
            if name in defines:
                by_type[typ.replace("DIALOGEX", "DIALOG").replace("MENUEX", "MENU")][defines[name][0]].add(name)
        for typ, vals in by_type.items():
            for v, names in vals.items():
                if len(names) > 1:
                    p.add("RES004", "error", f"{typ} の ID の値が重複: " + " と ".join(f"{n}={v}" for n in sorted(names)),
                          p.rel(rcpath))
    return defines


def build_classes(codes):
    classes = defaultdict(list)
    for path, code in codes:
        for c in find_classes(code, path):
            classes[c["name"]].append(c)
    return classes


def decl_pattern(fn):
    return (r"([^;{}]*?)\b(%s)\s*\(([^;{]*?)\)\s*((?:const|noexcept|override|final|volatile|&|\s)*)"
            r"(?:=\s*(?:0|default|delete)\s*)?(;|\{)" % re.escape(fn))


def find_member(cls_name, fn, classes, implicit, seen=None):
    """cls_name 自身、次に、プロジェクト内の基底クラスから、fn の宣言を探す。-> (宣言したクラス, 宣言の match or None)"""
    seen = seen if seen is not None else set()
    if cls_name in seen or cls_name not in classes:
        return None, None
    seen.add(cls_name)
    c = classes[cls_name][0]
    flags = re.I if implicit else 0
    if re.search(r"\b%s\s*\(" % re.escape(fn), c["own"], flags):
        return c, re.search(decl_pattern(fn), c["own"], flags)
    for b in re.findall(r"\b\w+\b", c["bases"]):
        r = find_member(b, fn, classes, implicit, seen)
        if r[0] is not None:
            return r
    return None, None


def check_maps(p, codes, rcinfo, classes, ddx_handled):
    all_code = [c for _, c in codes]
    has_template_map = any("BEGIN_TEMPLATE_MESSAGE_MAP" in c for c in all_code)
    map_cls = {mp["cls"] for mp in p.maps}
    dialog_ids = {idn for rc in rcinfo.values() for ctrls in rc["dialogs"].values() for idn, _ in ctrls}
    rc_cmds = set()
    for rc in rcinfo.values():
        rc_cmds.update(rc["menu"], rc["accel"], rc["toolbar"])
    map_ranges = [(mp["file"], mp["start"], mp["end"]) for mp in p.maps]
    code_by_path = dict(codes)

    def used_outside_maps(name):
        for path, code in codes:
            if os.path.basename(path).lower() == "resource.h":
                continue            # ID の定義そのものは、使用ではない
            for m in re.finditer(r"\b%s\b" % re.escape(name), code):
                if any(f == path and s <= m.start() < e for f, s, e in map_ranges):
                    continue
                return True
        return False

    all_referenced = set()           # どこかのマップが参照するハンドラ名 (継承先のマップも含む)
    for mp in p.maps:
        for e in mp["entries"]:
            hh = handler_of(e, mp["cls"])[0]
            if hh:
                all_referenced.add(hh.lower())

    for mp in p.maps:
        cls = mp["cls"]
        cdecl = classes.get(cls, [None])[0]
        rel = p.rel(mp["file"])
        if cdecl is not None and not re.search(r"\bDECLARE_MESSAGE_MAP\s*\(", cdecl["own"]):
            p.add("MAP003", "error", f"{cls}: BEGIN_MESSAGE_MAP があるが、クラスに DECLARE_MESSAGE_MAP がない",
                  rel, mp["line"])
        seen_cmd = {}
        for e in mp["entries"]:
            mac = e["macro"]
            if mac in ("ON_COMMAND", "ON_UPDATE_COMMAND_UI") and e["args"]:
                key = (mac, e["args"][0])
                if key in seen_cmd:
                    p.add("MAP007", "warning", f"{cls}: {mac}({e['args'][0]}) が重複 (後のものは、呼ばれない)", rel, e["line"])
                seen_cmd[key] = e["line"]
            h, qual, exp, implicit = handler_of(e, cls)
            if h is None:
                continue
            # UI との対応
            if mac in ("ON_COMMAND", "ON_UPDATE_COMMAND_UI") and e["args"]:
                idn = e["args"][0]
                if idn.startswith("ID_") and not is_standard(idn) and idn not in rc_cmds and rcinfo \
                        and not used_outside_maps(idn):
                    p.add("UI001", "warning", f"{mac}({idn}): .rc のメニュー・アクセラレータ・ツールバーに、この ID がない",
                          rel, e["line"])
            if NOTIFY_PREFIX.match(mac) and e["args"]:
                idn = e["args"][0]
                if ID_TOKEN.fullmatch(idn) and not is_standard(idn) and idn not in dialog_ids and rcinfo \
                        and not used_outside_maps(idn):
                    p.add("UI002", "warning", f"{mac}({idn}): .rc のダイアログに、このコントロール ID がない", rel, e["line"])
            if qual is not None and qual != cls:
                continue            # 基底クラスのハンドラ (例: &CWinApp::OnFileNew)
            if cdecl is None:
                continue
            owner, decl = find_member(cls, h, classes, implicit)
            if owner is None:
                # ON_WM_xxx は、MFC の基底 (CWnd など) が、既定のハンドラを持つ。宣言がなくても、合法
                if not implicit:
                    p.add("MAP001", "error", f"{cls}::{h}: メッセージマップにあるが、クラス (とプロジェクト内の基底クラス) に"
                          f"宣言されていない ({mac})", rel, e["line"])
                continue
            real = decl.group(2) if decl else h
            oname = owner["name"]
            flags = re.I if implicit else 0
            no_body_needed = decl is not None and (decl.group(5) == "{" or re.search(r"=\s*(?:0|default|delete)\b", decl.group(0)))
            defined = no_body_needed or re.search(r"\b%s\s*::\s*%s\s*\(" % (re.escape(oname), re.escape(real)),
                                                  "\n".join(all_code), flags)
            if not defined:
                p.add("MAP002", "error", f"{oname}::{real}: 宣言されているが、定義が見つからない", rel, e["line"])
            if decl:
                if "afx_msg" not in decl.group(1):
                    p.add("MAP008", "info", f"{oname}::{real}: afx_msg が付いていない", p.rel(owner["file"]), owner["line"])
                if exp is not None:
                    lo, hi = param_count(decl.group(3))
                    if not (lo <= exp <= hi):
                        p.add("MAP006", "warning", f"{oname}::{real}: 引数の数が {lo if lo == hi else f'{lo}〜{hi}'} 個。"
                              f"{mac} の想定は {exp} 個", rel, e["line"])
        # MAP005: afx_msg の孤立 (どのマップからも、参照されない)
        if cdecl is not None:
            for m in re.finditer(r"afx_msg\b[^;{()]*?\b(\w+)\s*\([^;{]*?\)\s*(?:const|noexcept|override|final|\s)*;", cdecl["own"]):
                if m.group(1).lower() not in all_referenced:
                    p.add("MAP005", "warning", f"{cls}::{m.group(1)}: afx_msg で宣言されているが、メッセージマップに登録されていない",
                          p.rel(cdecl["file"]), cdecl["line"] + cdecl["own"].count("\n", 0, m.start()))
    # MAP004
    if not has_template_map:
        for name, lst in classes.items():
            c = lst[0]
            if re.search(r"\bDECLARE_MESSAGE_MAP\s*\(", c["own"]) and name not in map_cls:
                p.add("MAP004", "error", f"{name}: DECLARE_MESSAGE_MAP があるが、BEGIN_MESSAGE_MAP がない (リンクエラーになる)",
                      p.rel(c["file"]), c["line"])
    # UI003: DDX / DDV
    for path, code in codes:
        for m in re.finditer(r"\bDD[XV]_\w+\s*\(\s*\w+\s*,\s*(ID\w+)", code):
            idn = m.group(1)
            if (path, lineno(code, m.start())) in ddx_handled:
                continue            # DLG001 で、そのクラスのダイアログに対して、検査済み
            if rcinfo and idn not in dialog_ids and not is_standard(idn):
                p.add("UI003", "warning", f"DDX/DDV のコントロール ID {idn} が、.rc のダイアログにない", p.rel(path), lineno(code, m.start()))


def dialog_kind(name, classes, seen=None):
    seen = seen if seen is not None else set()
    if name in seen or name not in classes:
        return None
    seen.add(name)
    for b in re.findall(r"\b\w+\b", classes[name][0]["bases"]):
        if b in DIALOG_BASES:
            return b
        r = dialog_kind(b, classes, seen)
        if r:
            return r
    return None


def func_bodies(codes, cls, fn):
    """-> [(path, code, 本体の開始位置, 本体)]  (Class::fn(...) { ... } の定義)"""
    out = []
    pat = re.compile(r"\b%s\s*::\s*%s\s*\([^)]*\)\s*(?:const\s*)?\{" % (re.escape(cls), re.escape(fn)))
    for path, code in codes:
        for m in pat.finditer(code):
            o = m.end() - 1
            out.append((path, code, o, code[o:match_brace(code, o) + 1]))
    return out


def ctrl_category(c):
    if c["kw"] == "CONTROL":
        k = (c["cls"] or "")
        return "richedit" if k.startswith("richedit") else k
    return KEYWORD_CATEGORY.get(c["kw"])


def is_push_button(c):
    if c["kw"] in ("PUSHBUTTON", "DEFPUSHBUTTON"):
        return True
    return c["kw"] == "CONTROL" and c["cls"] == "button" and bool(re.search(r"BS_(DEF)?PUSHBUTTON", c["style"]))


def check_dialogs(p, codes, rcinfo, classes, used_outside_maps):
    """ダイアログに関する検査。-> DDX 呼び出しのうち、検査済みの (path, 行) の集合"""
    handled = set()
    if not rcinfo:
        return handled
    all_code = "\n".join(c for _, c in codes)
    dlg_defs = {}        # ダイアログ名 -> 行
    other_defs = {}
    for rc in rcinfo.values():
        for name, typ, no in rc["defs"]:
            (dlg_defs if typ in ("DIALOG", "DIALOGEX") else other_defs).setdefault(name, typ)
    dlg_ctrls = {}
    for rcpath, rc in rcinfo.items():
        for name, rich in rc["dlgctrls"].items():
            dlg_ctrls[name] = (rcpath, rich)
    maps = defaultdict(list)
    for mp in p.maps:
        maps[mp["cls"]].append(mp)
    # ダイアログごとの、静的な検査 (クラスに関係しない)
    for name, (rcpath, rich) in dlg_ctrls.items():
        rel = p.rel(rcpath)
        defaults = [c for c in rich if c["kw"] == "DEFPUSHBUTTON"
                    or (c["kw"] == "CONTROL" and c["cls"] == "button" and "BS_DEFPUSHBUTTON" in c["style"])]
        if len(defaults) > 1:
            p.add("DLG005", "warning", f"ダイアログ {name} に、既定ボタンが {len(defaults)} 個ある: "
                  + ", ".join(c["id"] for c in defaults), rel, defaults[1]["line"])
        mn = defaultdict(list)
        for c in rich:
            if category_has_mnemonic(c):
                m = re.search(r"(?<!&)&([A-Za-z0-9])", c["text"])
                if m:
                    mn[m.group(1).lower()].append(c)
        for k, cs in mn.items():
            if len(cs) > 1:
                p.add("DLG008", "info", f"ダイアログ {name} で、ニーモニック &{k.upper()} が重複: "
                      + ", ".join(c["id"] for c in cs), rel, cs[1]["line"])
    for rcpath, rc in rcinfo.items():
        for name, no in rc["layouts"].items():
            if name not in dlg_defs:
                p.add("DLG009", "info", f"AFX_DIALOG_LAYOUT {name} に対応するダイアログがない (VS が残した、不要な定義)",
                      p.rel(rcpath), no)
    # クラスごとの検査
    for cname, lst in classes.items():
        c = lst[0]
        kind = dialog_kind(cname, classes)
        if kind is None:
            continue
        rel = p.rel(c["file"])
        idd = None
        m = re.search(r"\benum\s*\{\s*IDD\s*=\s*(\w+)", c["own"])
        if m:
            idd = m.group(1)
        else:
            for mm in re.finditer(r"\b%s\s*::\s*%s\s*\([^)]*\)\s*:\s*([^{;]*)\{" % (re.escape(cname), re.escape(cname)), all_code):
                m2 = re.search(r"\b\w+\s*\(\s*(IDD_\w+)\b", mm.group(1))
                if m2:
                    idd = m2.group(1)
                    break
        if idd and not is_standard(idd):
            if idd not in dlg_defs:
                what = f"{other_defs[idd]} として定義されている (DIALOG ではない)" if idd in other_defs else ".rc にない"
                p.add("DLG002", "error", f"{cname}: ダイアログ ID {idd} が {what} (DoModal / Create が失敗する)", rel, c["line"])
                idd_ctrls = None
            else:
                idd_ctrls = dlg_ctrls.get(idd, (None, []))[1]
        else:
            idd_ctrls = None
        # DoDataExchange
        for path, code, o, body in func_bodies(codes, cname, "DoDataExchange"):
            if not re.search(r"\b\w+\s*::\s*DoDataExchange\s*\(", body):
                p.add("DLG007", "warning", f"{cname}::DoDataExchange が、基底クラスの DoDataExchange を呼んでいない",
                      p.rel(path), lineno(code, o))
            binds = {}          # DDX_Control のメンバー -> [(ID, 開始, 終了, 行)]
            for dm in re.finditer(r"\b(DD[XV]_\w+)\s*\(\s*\w+\s*,\s*(ID\w+)\s*(?:,\s*([\w.\[\]>\-]+))?", body):
                line = lineno(code, o + dm.start())
                handled.add((path, line))
                macro, cid, member = dm.group(1), dm.group(2), dm.group(3)
                if macro == "DDX_Control" and member:
                    binds.setdefault(member, []).append((cid, dm.start(), dm.end(), line))
                if idd_ctrls is None or is_standard(cid):
                    if idd_ctrls is None and idd is None:
                        handled.discard((path, line))      # ダイアログが分からない: UI003 に任せる
                    continue
                ctrl = next((x for x in idd_ctrls if x["id"] == cid), None)
                if ctrl is None:
                    p.add("DLG001", "error", f"{cname}: {macro} の ID {cid} が、ダイアログ {idd} にない", p.rel(path), line)
                elif macro == "DDX_Control" and member:
                    mt = re.search(r"\b([A-Za-z_]\w*)\s+%s\s*(?:\[[^\]]*\])?\s*;" % re.escape(member), c["own"])
                    mtype = mt.group(1) if mt else None
                    want, have = ctrl_category(ctrl), MFC_CTRL_CATEGORY.get(mtype)
                    if want and have and want != have:
                        p.add("DLG003", "error", f"{cname}: DDX_Control({cid}, {member}) の型 {mtype} が、ダイアログ {idd} の"
                              f"コントロール ({ctrl['kw']}{' ' + ctrl['cls'] if ctrl['cls'] else ''}) と合わない", p.rel(path), line)
            # DLG010: MFC の DDX_Control は、メンバーが接続済みなら、コントロールを探さない。
            # 同じメンバーを別の ID に渡すと、2 回目以降は、何も起きない (コピー&ペーストの誤りに多い)
            for member, lst in binds.items():
                for (id1, s1, e1, _), (id2, s2, e2, line2) in zip(lst, lst[1:]):
                    if re.search(r"\b(?:else|case|default)\b", body[e1:s2]):
                        continue            # 分岐ごとに、別の ID を渡す書き方は、正当
                    p.add("DLG010", "warning", f"{cname}: DDX_Control のメンバー {member} が、{id1} と {id2} の両方に渡されている "
                          "(2 回目以降は、MFC が、接続済みのメンバーを探さないので、何も起きない)", p.rel(path), line2)
        # OnInitDialog (CFormView を除く)
        if kind not in NO_INITDIALOG:
            for path, code, o, body in func_bodies(codes, cname, "OnInitDialog"):
                if not re.search(r"\b\w+\s*::\s*OnInitDialog\s*\(", body):
                    p.add("DLG006", "warning", f"{cname}::OnInitDialog が、基底クラスの OnInitDialog を呼んでいない "
                          "(コントロールの初期化と DDX が行われない)", p.rel(path), lineno(code, o))
        # ボタンのハンドラ
        if idd_ctrls:
            ents = [e for mp in maps.get(cname, []) for e in mp["entries"]]
            if any(e["macro"].endswith("_RANGE") for e in ents):
                continue
            mapped = {a for e in ents for a in e["args"]}
            for ctrl in idd_ctrls:
                cid = ctrl["id"]
                if not is_push_button(ctrl) or cid in STD_BUTTON_IDS or cid in mapped or not ID_TOKEN.fullmatch(cid):
                    continue
                if used_outside_maps(cid):
                    continue
                p.add("DLG004", "warning", f"{cname}: ダイアログ {idd} のボタン {cid} に、ハンドラがない (押しても何も起きない)",
                      p.rel(dlg_ctrls[idd][0]), ctrl["line"])
    return handled


def category_has_mnemonic(c):
    return ctrl_category(c) in ("button", "static") and c["kw"] != "ICON"


def make_used_outside_maps(p, codes):
    ranges = [(mp["file"], mp["start"], mp["end"]) for mp in p.maps]

    def used(name):
        for path, code in codes:
            if os.path.basename(path).lower() == "resource.h":
                continue            # ID の定義そのものは、使用ではない
            for m in re.finditer(r"\b%s\b" % re.escape(name), code):
                if any(f == path and s <= m.start() < e for f, s, e in ranges):
                    continue
                return True
        return False
    return used


# UI テスト (FlaUI) で操作するコントロールの種類 (.rc の CONTROL のクラス)。静的テキスト・グループボックス・アイコンは、含めない
UI_OPERABLE_KW = {"PUSHBUTTON", "DEFPUSHBUTTON", "EDITTEXT", "COMBOBOX", "LISTBOX", "CHECKBOX", "AUTOCHECKBOX",
                  "RADIOBUTTON", "AUTORADIOBUTTON", "AUTO3STATE", "STATE3", "SCROLLBAR"}
UI_OPERABLE_CLASSES = {"button", "edit", "combobox", "listbox", "scrollbar", "syslistview32", "systreeview32",
                       "systabcontrol32", "msctls_trackbar32", "msctls_updown32", "sysdatetimepick32", "sysmonthcal32",
                       "sysipaddress32"}


def has_ui_tests(root):
    """ソリューションに、UI テストのプロジェクト (名前が UITests / UiTests で終わる .csproj) があるか。"""
    for f in collect_files(root):
        b = os.path.basename(f)
        if b.lower().endswith(".csproj") and re.search(r"(UI|Ui)Tests\.csproj$", b):
            return True
    return False


def is_ui_operable(c):
    if c["kw"] in UI_OPERABLE_KW:
        return True
    if c["kw"] != "CONTROL":
        return False
    k = c["cls"] or ""
    if k == "button" and "BS_GROUPBOX" in c["style"]:
        return False
    return k in UI_OPERABLE_CLASSES or k.startswith("richedit")


def check_ui_ids(p, rcinfo):
    """UI004: UI テストで操作するコントロールの ID が、IDC_STATIC (-1) のまま / 重複している。"""
    for rcpath, rc in rcinfo.items():
        rel = p.rel(rcpath)
        for dlg, rich in rc["dlgctrls"].items():
            seen = {}
            for c in rich:
                if not is_ui_operable(c):
                    continue
                cid = c["id"]
                if cid in ("IDC_STATIC", "-1"):
                    label = c["kw"] + ((' "' + c["text"] + '"') if c["text"] else "")
                    p.add("UI004", "warning", "ダイアログ " + dlg + " の操作できるコントロール (" + label + ") の ID が " + cid + " のまま "
                          "(UI テストの AutomationId = コントロール ID なので、ID で探せない。固有の ID (IDC_xxx) を付ける)", rel, c["line"])
                elif cid in seen:
                    p.add("UI004", "warning", f"ダイアログ {dlg} のコントロール ID {cid} が重複している (UI テストで、どちらを指すか決まらない)", rel, c["line"])
                else:
                    seen[cid] = c["line"]


UI_WORDS = ("ui", "view", "views", "dialog", "dialogs")   # 名前に、この語を含む DLL は、画面を持つ層 (UI DLL) として扱う


def is_ui_name(name):
    if "viewmodel" in name.lower():   # ViewModel は 'View' を含むが、画面の層ではない (solution_state.py と同じ規則)
        return False
    return any(t.lower() in UI_WORDS for t in re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+", name))


def check_layering(projects, logic_names, data_names, ui_names=()):
    by_name = {pr.name: pr for pr in projects}

    def layer(pr):
        n = pr.name
        if re.search(r"Tests?$", n):
            return "test"
        if pr.kind == "Application":
            return "main"
        if pr.kind in ("DynamicLibrary", "StaticLibrary") and (n in ui_names or (n not in logic_names and n not in data_names and is_ui_name(n))):
            return "ui"
        if n in logic_names or (n not in data_names and re.search(r"logic", n, re.I)):
            return "logic"
        if n in data_names or re.search(r"data", n, re.I):
            return "data"
        return "lib" if pr.kind in ("DynamicLibrary", "StaticLibrary") else None
    for pr in projects:
        L = layer(pr)
        if L == "test" or L is None:
            continue
        for ref in pr.refs:
            q = by_name.get(ref)
            if q is None:
                continue
            Q = layer(q)
            bad = (L == "data" and Q in ("logic", "main", "ui")) or (L == "logic" and Q in ("main", "ui")) \
                or (L in ("lib", "logic", "data", "ui") and Q == "main")
            if bad:
                pr.add("LAY003", "error", f"{pr.name} ({L}) が {q.name} ({Q}) を参照している (UI → ロジック → データの向きに反する)",
                       pr.name + ".vcxproj")
        if pr.kind in ("DynamicLibrary", "StaticLibrary") and L != "ui":    # 画面を持つ層 (UI DLL) は、GUI を使ってよい
            for path, raw in pr.files:
                if not path.lower().endswith(CODE_EXT):
                    continue
                code = strip_code(raw)
                for m in GUI_CLASSES.finditer(code):
                    pr.add("LAY001", "error", f"ライブラリ {pr.name} で GUI のクラス/関数 {m.group(0)} を使っている",
                           pr.rel(path), lineno(code, m.start()))
                    break
                hdr_src = strip_code(raw, blank_strings=False)
                for m in GUI_HEADERS.finditer(hdr_src):
                    sev = "info" if os.path.basename(path).lower() in PCH_NAMES or mfc_dll_kind(pr) or is_mfc_static_lib(pr) else "warning"
                    pr.add("LAY002", sev, f"ライブラリ {pr.name} で GUI のヘッダーを include: {m.group(0).split()[-1]}",
                           pr.rel(path), lineno(hdr_src, m.start()))
                    break


# ------------------------------------------------------------------ MFC の DLL の設定 (DLL001〜DLL008)
def mfc_values(pr):
    return [c["mfc"] or "false" for c in pr.cfg.values()] or ["false"]


def has_def(pr, name):
    return any(name in c["defs"] for c in pr.cfg.values())


def is_mfc_static_lib(pr):
    """MFC の静的ライブラリ (StaticLibrary + UseOfMfc)。MFC の型 (CString / CObject) を使うため、afxwin.h などの include は、info にとどめる。"""
    return pr.kind == "StaticLibrary" and any(v in ("Dynamic", "Static") for v in mfc_values(pr))


def mfc_dll_kind(pr):
    """'ext' (MFC 拡張 DLL: _AFXEXT) / 'std' (MFC 標準 DLL: _USRDLL + MFC) / None。DLL でないとき、MFC を使わないときは None"""
    if pr.kind != "DynamicLibrary" or not any(v in ("Dynamic", "Static") for v in mfc_values(pr)):
        return None
    if has_def(pr, "_AFXEXT"):
        return "ext"
    return "std" if has_def(pr, "_USRDLL") else None


def project_codes(pr):
    return [(path, strip_code(raw)) for path, raw in pr.files if path.lower().endswith(CODE_EXT)]


def check_export_manage_state(pr, codes):
    """DLL007: 標準 DLL (共有 MFC) の、公開の関数が、先頭で AFX_MANAGE_STATE を呼んでいるか。"""
    macros = {m.group(1) for _, c in codes for m in re.finditer(r"#\s*define\s+(\w+)\s+__declspec\s*\(\s*dllexport\s*\)", c)}
    heads = "|".join(sorted(macros) + [r"__declspec\s*\(\s*dllexport\s*\)"])
    decl = re.compile(r"\b(?:%s)(?!\s*(?:class|struct)\b)\s+([^;{}()=]*?)\b([A-Za-z_]\w*)\s*\(" % heads)
    names = {m.group(2) for _, c in codes for m in decl.finditer(c) if not re.search(r"\b(?:class|struct|enum)\b", m.group(1))}
    for name in sorted(names):
        d = re.compile(r"\b%s\s*\([^;{}]*?\)\s*(?:const\s*)?(?:noexcept\s*)?\{" % re.escape(name))
        for path, c in codes:
            if not path.lower().endswith((".cpp", ".cc", ".cxx")):
                continue
            for m in d.finditer(c):
                body = c[m.end():match_brace(c, m.end() - 1)]
                if not re.match(r"\s*AFX_MANAGE_STATE\b", body):
                    pr.add("DLL007", "warning", f"標準 DLL (共有 MFC) の公開関数 {name} が、先頭で AFX_MANAGE_STATE を呼んでいない",
                           pr.rel(path), lineno(c, m.start()))


# CObject を、基底に持つ、MFC のクラス (一部。これらから派生すれば、CObject 派生)。CWinApp / CWinThread は、DEC001 の対象外 (ウィザードも、マクロを書かない)。
MFC_OBJECT_BASES = {
    "CObject", "CCmdTarget", "CWnd", "CDialog", "CDialogEx", "CFormView", "CView", "CScrollView", "CCtrlView", "CEditView",
    "CListView", "CTreeView", "CRichEditView", "CHtmlView", "CDocument", "COleDocument", "CFrameWnd", "CMDIFrameWnd",
    "CMDIChildWnd", "CMiniFrameWnd", "CPropertySheet", "CPropertyPage", "CDialogBar", "CControlBar", "CToolBar", "CStatusBar",
    "CReBar", "CButton", "CEdit", "CComboBox", "CListBox", "CListCtrl", "CTreeCtrl", "CTabCtrl", "CSliderCtrl", "CSpinButtonCtrl",
    "CProgressCtrl", "CStatic", "CScrollBar", "CSplitterWnd", "CHeaderCtrl", "CRichEditCtrl", "CToolTipCtrl", "CDateTimeCtrl",
    "CMonthCalCtrl", "CIPAddressCtrl", "CDocTemplate", "CSingleDocTemplate", "CMultiDocTemplate", "CException", "CFile", "CMemFile",
    "CGdiObject", "CBitmap", "CBrush", "CFont", "CPen", "CPalette", "CRgn", "CDC", "CMenu", "CImageList", "CMFCPropertyPage",
    "CDHtmlDialog", "CWinThread", "CWinApp",
}
MFC_NO_DECLARE_BASES = {"CWinApp", "CWinThread"}   # アプリケーション・スレッドのクラス (ウィザードは、DECLARE_DYNAMIC を、書かない)
DECLARE_RE = re.compile(r"\bDECLARE_(?:DYNAMIC|DYNCREATE|SERIAL)\s*\(")


def namespace_spans(code):
    """コードの中の、namespace { ... } の範囲の一覧 (開き括弧の位置, 閉じ括弧の位置)。"""
    out = []
    for m in re.finditer(r"\bnamespace\b[^;{=]*\{", code):
        o = m.end() - 1
        out.append((o, match_brace(code, o)))
    return out


def is_cobject_derived(name, classes, seen=None):
    """(CObject 派生か, CWinApp / CWinThread 派生か)。プロジェクトの中の基底クラスも、たどる。"""
    seen = seen if seen is not None else set()
    if name in seen or name not in classes:
        return False, False
    seen.add(name)
    obj = app = False
    for b in re.findall(r"\b\w+\b", classes[name][0]["bases"]):
        if b in ("public", "protected", "private", "virtual"):
            continue
        if b in MFC_OBJECT_BASES:
            obj = True
            app = app or b in MFC_NO_DECLARE_BASES
        else:
            o, a = is_cobject_derived(b, classes, seen)
            obj, app = obj or o, app or a
    return obj, app


def check_class_decls(pr, codes):
    """NSP001: CObject 派生のクラスは、名前空間に入れない (MFC のマクロは、クラス名を ## / # で扱うので、名前空間つきの名前を渡せない)。
    DEC001: CObject 派生のクラスには、DECLARE_DYNAMIC / DECLARE_DYNCREATE / DECLARE_SERIAL を書く (CWinApp / CWinThread 派生は除く)。"""
    classes = defaultdict(list)
    spans = {}
    for path, code in codes:
        spans[path] = namespace_spans(code)
        for c in find_classes(code, path):
            classes[c["name"]].append(c)
    found = 0
    for name, defs in classes.items():
        obj, app = is_cobject_derived(name, classes)
        if not obj:
            continue
        c = defs[0]
        if not c["bases"]:
            continue
        found += 1
        in_ns = any(o < c["span"][0] and c["span"][1] < e for o, e in spans.get(c["file"], []))
        if in_ns:
            pr.add("NSP001", "warning", f"{pr.name}: CObject 派生のクラス {name} が、名前空間の中にある (MFC のマクロ (RUNTIME_CLASS・IMPLEMENT_*) は、名前空間つきの名前を扱えない。名前空間に入れない)",
                   pr.rel(c["file"]), c["line"])
        if not app and not DECLARE_RE.search(c["own"]):
            pr.add("DEC001", "warning", f"{pr.name}: CObject 派生のクラス {name} に、DECLARE_DYNAMIC / DECLARE_DYNCREATE / DECLARE_SERIAL がない (実行時のクラス情報が、基底クラスのものになる)",
                   pr.rel(c["file"]), c["line"])
    return found


def check_mfc_dlls(projects):
    by_name = {pr.name: pr for pr in projects}
    for pr in projects:
        if re.search(r"Tests?$", pr.name):
            continue
        if pr.kind == "DynamicLibrary":
            ext, usr = has_def(pr, "_AFXEXT"), has_def(pr, "_USRDLL")
            file = pr.name + ".vcxproj"
            if any("_AFXEXT" in c["defs"] and "_USRDLL" in c["defs"] for c in pr.cfg.values()):
                pr.add("DLL001", "error", f"{pr.name}: _USRDLL と _AFXEXT が、同じ構成で、両方定義されている (標準 DLL と拡張 DLL の、どちらか 1 つにする)", file)
            if ext and any(v != "Dynamic" for v in mfc_values(pr)):
                pr.add("DLL002", "error", f"{pr.name}: MFC 拡張 DLL (_AFXEXT) だが、UseOfMfc が Dynamic でない (拡張 DLL は、共有 MFC が必須)", file)
            if not ext and not usr and any(v in ("Dynamic", "Static") for v in mfc_values(pr)):
                pr.add("DLL003", "warning", f"{pr.name}: UseOfMfc が有効だが、_USRDLL (標準 DLL) も _AFXEXT (拡張 DLL) も定義されていない", file)
            codes = project_codes(pr)
            joined = "\n".join(c for _, c in codes)
            if ext and not usr:
                if "AfxInitExtensionModule" not in joined:
                    pr.add("DLL005", "error", f"{pr.name}: MFC 拡張 DLL に、DllMain の AfxInitExtensionModule がない (リソースや CObject の動的生成が、実行時に壊れる)", file)
                if "CDynLinkLibrary" not in joined:
                    pr.add("DLL006", "warning", f"{pr.name}: MFC 拡張 DLL に、new CDynLinkLibrary がない (リソース チェーンに入らない)", file)
                if "AfxTermExtensionModule" not in joined:
                    pr.add("DLL006", "warning", f"{pr.name}: MFC 拡張 DLL に、AfxTermExtensionModule がない (DLL_PROCESS_DETACH の後始末)", file)
            if mfc_dll_kind(pr) == "std":
                if not re.search(r"\bclass\s+\w+\s*:\s*public\s+CWinApp\b", joined) and not re.search(r"\bCWinApp\b[^;{]*\{", joined):
                    pr.add("DLL004", "warning", f"{pr.name}: MFC 標準 DLL に、CWinApp 派生のクラス (と、グローバルの theApp) がない (MFC の初期化が行われない)", file)
                if "Dynamic" in mfc_values(pr):
                    check_export_manage_state(pr, codes)
        if pr.kind in ("Application", "DynamicLibrary", "StaticLibrary"):
            for ref in pr.refs:
                q = by_name.get(ref)
                # MFC の静的ライブラリ (StaticLibrary + UseOfMfc) を参照する側は、UseOfMfc が、同じ値 (Dynamic / Static) でなければならない
                # (違うと、MFC のランタイムが 2 つになったり、LNK2005 / LNK2038 になる)。MFC なしの exe / DLL も、同じ (UseOfMfc がない)。
                if q is not None and q.kind == "StaticLibrary":
                    qv = {v for v in mfc_values(q) if v in ("Dynamic", "Static")}
                    if qv and set(mfc_values(pr)) != qv:
                        pr.add("LIB001", "error", f"{pr.name}: MFC の静的ライブラリ {q.name} (UseOfMfc={'/'.join(sorted(qv))}) を参照しているが、"
                               f"UseOfMfc が違う ({'/'.join(sorted(set(mfc_values(pr))))})。参照する側を、同じ UseOfMfc にする (MFC のランタイムが 2 つになる、または LNK2005 / LNK2038)",
                               pr.name + ".vcxproj")
                if pr.kind == "StaticLibrary":
                    continue
                if q is not None and q.kind == "DynamicLibrary" and has_def(q, "_AFXEXT") and any(v != "Dynamic" for v in mfc_values(pr)):
                    pr.add("DLL008", "error", f"{pr.name}: MFC 拡張 DLL {q.name} を参照しているが、UseOfMfc が Dynamic でない (MFC のランタイムが 2 つになり、実行時に壊れる)",
                           pr.name + ".vcxproj")


# ------------------------------------------------------------------ 実行
def claude_layer_roles(root):
    """root/CLAUDE.md の「- 層:」の行の「役割:名前」(例 logic:ExtLayer) -> (ロジック, データ, 画面) の名前の一覧。
    名前に Logic / Data / Ui の語がない層の、役割を決める (--logic / --data / --ui と、同じ働き)。"""
    logic, data, ui = [], [], []
    try:
        text = open(os.path.join(root, "CLAUDE.md"), encoding="utf-8-sig").read()
    except OSError:
        return logic, data, ui
    m = re.search(r"^- 層:\s*(.+)$", text, re.M)
    for item in re.split(r"[,、]", m.group(1) if m else ""):
        em = re.match(r"\s*(data|logic|ui)\s*:\s*([\w.]+)", item)
        if em:
            {"logic": logic, "data": data, "ui": ui}[em.group(1)].append(em.group(2))
    return logic, data, ui


def run(root, logic_names, data_names, ui_names=()):
    root = os.path.abspath(root)
    cl, cd, cu = claude_layer_roles(root)
    logic_names, data_names, ui_names = [*logic_names, *cl], [*data_names, *cd], [*ui_names, *cu]
    vcxs = sorted(p for p in collect_files(root) if p.lower().endswith(".vcxproj"))
    projects = [load_project(v, root) for v in vcxs] or [Project(os.path.basename(root), root, root)]
    nested = {pr.dir for pr in projects}
    for pr in projects:
        for path in collect_files(pr.dir):
            if any(os.path.dirname(path).startswith(d + os.sep) for d in nested if d != pr.dir and d.startswith(pr.dir + os.sep)):
                continue            # 入れ子の、別プロジェクトのファイル
            if path.lower().endswith(CODE_EXT + (".rc", ".rc2")):
                pr.files.append((path, read_text(path)))
    for pr in projects:
        codes = [(f, strip_code(t)) for f, t in pr.files if f.lower().endswith(CODE_EXT)]
        rcs = [(f, t) for f, t in pr.files if f.lower().endswith(".rc")]
        resh = next((f for f, _ in pr.files if os.path.basename(f).lower() == "resource.h"), None)
        pr.maps = []
        for path, code in codes:
            pr.maps.extend(parse_maps(code, path))
        rcinfo = {f: parse_rc(t) for f, t in rcs}
        pr.checked = bool(rcs or pr.maps)
        if pr.checked:
            check_resources(pr, resh, rcs, codes, rcinfo)
            classes = build_classes(codes)
            handled = check_dialogs(pr, codes, rcinfo, classes, make_used_outside_maps(pr, codes))
            check_maps(pr, codes, rcinfo, classes, handled)
    for pr in projects:      # CObject 派生のクラスの宣言 (NSP001 / DEC001)。MFC を使うコードがあるプロジェクトだけ (テストの exe などは、対象になるクラスがない)
        codes = [(f, strip_code(t)) for f, t in pr.files if f.lower().endswith(CODE_EXT)]
        if codes and check_class_decls(pr, codes):
            pr.checked = True    # CObject 派生のクラスがある (リソースも、メッセージマップも、なくても、検査した)
    if has_ui_tests(root):   # UI テストのプロジェクトがあるときだけ (UI004)
        for pr in projects:
            if pr.checked:
                check_ui_ids(pr, {f: parse_rc(t) for f, t in pr.files if f.lower().endswith(".rc")})
    check_layering(projects, set(logic_names), set(data_names), set(ui_names))
    check_mfc_dlls(projects)
    return projects


def summarize(projects, include_info, max_lines):
    findings = [f for pr in projects for f in pr.findings if include_info or f["severity"] != "info"]
    findings.sort(key=lambda f: (SEV_ORDER[f["severity"]], f["project"], f["code"], f["file"] or "", f["line"] or 0))
    n = {s: sum(1 for f in findings if f["severity"] == s) for s in SEV_ORDER}
    checked = [pr.name for pr in projects if pr.checked or pr.kind in ("DynamicLibrary", "StaticLibrary")]
    out = [f"mfc-check: error {n['error']} / warning {n['warning']}" + (f" / info {n['info']}" if include_info else "")
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
    ap.add_argument("--ui", action="append", default=[])
    a = ap.parse_args()
    if not os.path.isdir(a.dir):
        print(f"BAD_ARGS: not a directory: {a.dir}")
        return 2
    projects = run(a.dir, a.logic, a.data, a.ui)
    if not any(pr.checked or pr.kind in ("DynamicLibrary", "StaticLibrary") for pr in projects):
        print("mfc-check: nothing to check (no .rc / message map / library project found)")
        return 3
    out, n, findings = summarize(projects, a.all, a.max_lines)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump({"counts": n, "findings": [fi for pr in projects for fi in pr.findings]}, f, ensure_ascii=False, indent=2)
    sys.stdout.write("\n".join(out) + "\n")
    return 1 if n["error"] else 0


if __name__ == "__main__":
    sys.exit(main())
