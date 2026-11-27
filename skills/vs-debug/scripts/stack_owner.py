#!/usr/bin/env python3
"""stack_owner.py - vs_once.sh --inspect の STACK: の各フレームに、所有者の印と、要約を付ける (v2.107.0)。

Usage: python3 -I stack_owner.py [--solution-root <ソリューションのフォルダ (WSL のパス)>] <vs_output.txt>
  ウォッチャーが書いた出力を読み (BOM・CR は除く)、STACK: の行を書き換えて、標準出力へ出す。
  ホストが出す形:   STACK: #<n> <関数> [at <ファイル>:<行>] [[module=<モジュール>]]
  この出力の形:     STACK: #<n> [<所有者>] <関数> [at <ファイル>:<行>] [(<モジュール>)]
  最後の STACK: / STACK_TRUNCATED: の行の直後に、OWNER: と BOUNDARY: の行を足す。STACK: の行がなければ、そのまま。

所有者: ours (こちら) / ext (外のライブラリ) / sys (Windows・MFC・CRT・.NET) / unknown (判定できない)。
**ヒントであり、断定ではない** (こちらが誤った引数を渡して、外の中で落ちるときも、OWNER: は ext になる)。
判定は、ソースファイルのパスを先に見る (静的ライブラリは、exe に取り込まれて、モジュールが、こちらの exe になるため)。
ファイルがないとき (シンボルなし) だけ、モジュールで判定する。設計: docs/superpowers/specs/2026-11-26-vs-debug-stack-owner-design.md
"""
import os
import re
import sys

# システムのソースのパス (小文字・\ 区切りで比べる)
_SYS_PATH_RES = (
    re.compile(r"^[a-z]:\\windows\\"),
    re.compile(r"\\microsoft visual studio\\"),
    re.compile(r"\\windows kits\\"),
    re.compile(r"\\vc\\tools\\msvc\\"),
    re.compile(r"\\atlmfc\\"),
    re.compile(r"\\vctools\\"),
    re.compile(r"\\ucrt\\"),
    re.compile(r"\\minkernel\\"),
    re.compile(r"\\onecore\\"),
    re.compile(r"\\program files( \(x86\))?\\dotnet\\"),
    re.compile(r"\\microsoft\.net\\"),
)

# システムのモジュール名 (拡張子を除いた名前。小文字)
_SYS_MODULE_RE = re.compile(
    r"^(ntdll|kernel32|kernelbase|user32|gdi32|gdi32full|win32u|combase|rpcrt4|shell32|shcore|ole32|oleaut32|"
    r"comctl32|comdlg32|advapi32|sechost|msvcrt|ucrtbased?|vcruntime\d*(_\d+)?d?|msvcp\d*(_\d+)?d?|mfcm?\d+[a-z]*|"
    r"atl\d+d?|concrt\d*d?|"
    # .NET: 既知のフレームワークの名前だけ (System.Data.SQLite や Microsoft.Toolkit.* のような、第三者・追加のライブラリは、含めない)
    r"system(\.(private\.\w+|runtime(\.\w+)*|collections(\.\w+)*|linq(\.\w+)*|core|threading(\.\w+)*|io(\.\w+)*|"
    r"text(\.\w+)*|xaml|net(\.\w+)*|componentmodel(\.\w+)*|diagnostics(\.\w+)*|reflection(\.\w+)*|memory|"
    r"numerics(\.\w+)*|security(\.\w+)*|globalization(\.\w+)*|resources(\.\w+)*|buffers|console|windows(\.\w+)*|"
    r"drawing(\.\w+)*|configuration(\.\w+)*|xml(\.\w+)*|objectmodel|data(\.common|\.sqlclient|\.odbc|\.oledb|\.datasetextensions)?))?|"
    r"microsoft\.(csharp|visualbasic(\.\w+)*|win32(\.\w+)*|netcore(\.\w+)*|windows(\.\w+)*)|"
    r"presentation(core|framework|ui)\w*|presentationnative\w*|windowsbase|netstandard|mscorlib|"
    r"coreclr|clrjit|clr|hostfxr|hostpolicy)$"
)

# ソリューションの直下にある、外のコードの置き場 (add-package の vcpkg・ThirdParty・NuGet など)。この下のソースは、ours にしない
_VENDOR_DIRS = ("vcpkg_installed", "packages", "thirdparty", "third_party", "3rdparty", "deps", "extern", "submodules", "external", "vendor")

_FRAME_RE = re.compile(r"^STACK: #(\d+) (.*)$")
_MODULE_RE = re.compile(r" \[module=(.*)\]$")
_FILE_RE = re.compile(r" at ((?:[A-Za-z]:[\\/]|\\\\|/).*?):(\d+)$")


def _norm(path):
    return path.replace("/", "\\").lower()


def _is_sys_path(p):
    return any(r.search(p) for r in _SYS_PATH_RES)


def _under(p, directory):
    return directory is not None and p.startswith(directory.rstrip("\\") + "\\")


def _own_or_vendor(p, directory):
    """ソリューションの下のパス: 直下が外のコードの置き場 (vcpkg_installed・ThirdParty・packages など) なら ext、そうでなければ ours。"""
    rel = p[len(directory.rstrip("\\")) + 1:]
    return "ext" if rel.split("\\", 1)[0] in _VENDOR_DIRS else "ours"


def _module_name(module):
    base = module.replace("/", "\\").rsplit("\\", 1)[-1].lower()
    for ext in (".dll", ".exe"):
        if base.endswith(ext):
            return base[: -len(ext)]
    return base


def classify(file, module, solution_dir):
    """フレームの所有者を返す: "ours" / "ext" / "sys" / "unknown"。ソースのパスを先に見て、なければモジュールで判定する。"""
    sd = _norm(solution_dir) if solution_dir else None
    if file:
        p = _norm(file)
        if _under(p, sd):
            return _own_or_vendor(p, sd)
        if _is_sys_path(p):
            return "sys"
        # .NET のフレームワークは、Source Link などで、/_/src/... のような、見慣れないパスになる。モジュールが、システムと言うなら、sys
        # (静的ライブラリは、モジュールが、こちらの exe なので、ここには当たらない)
        if module and _SYS_MODULE_RE.match(_module_name(module)):
            return "sys"
        return "ext" if sd is not None else "unknown"
    if module:
        if _SYS_MODULE_RE.match(_module_name(module)):
            return "sys"
        m = _norm(module)
        if "\\" in m:
            if _under(m, sd):
                # ソースがない (シンボルなし) とき、こちらの出力フォルダの DLL は、配布された外の DLL を、コピーしたものかもしれない。
                # 「こちら」と言えるのは、こちらのソースが見えるときだけ。外のコードの置き場 (vcpkg_installed など) の下だけ ext
                return "ext" if _own_or_vendor(m, sd) == "ext" else "unknown"
            if _is_sys_path(m):
                return "sys"
            return "ext" if sd is not None else "unknown"
        return "unknown"
    return "unknown"


# ---- ネイティブ C++ のフレーム (STACK: にファイルがない) の判定 (v2.107.2) ----
_SKIP_DIRS = {"bin", "obj", "x64", "win32", "arm64", "debug", "release", ".git", ".vs", "ipch", "testresults", ".vscode", ".venv",
              "vcpkg_installed", "packages", "thirdparty", "third_party", "3rdparty", "deps", "extern", "submodules",
              "external", "vendor", "node_modules", ".claude-logs", ".superpowers"}
_SRC_EXTS = (".cpp", ".cc", ".cxx", ".c", ".h", ".hpp", ".inl", ".cs")
_PROJ_EXTS = (".vcxproj", ".csproj", ".vbproj")
_MAX_FILES = 5000
_MAX_BYTES = 2 * 1024 * 1024


def _walk(root, exts):
    """root の下のファイル (外のコードの置き場と、ビルドの出力は、除く)。"""
    count = 0
    for cur, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d.lower() not in _SKIP_DIRS]
        for f in files:
            if f.lower().endswith(exts):
                count += 1
                if count > _MAX_FILES:
                    return
                yield os.path.join(cur, f)


def _read(path):
    try:
        if os.path.getsize(path) > _MAX_BYTES:
            return ""
        with open(path, "rb") as fh:
            return fh.read().decode("utf-8", errors="replace")
    except OSError:
        return ""


def project_outputs(root):
    """ソリューションのプロジェクトの出力名 (拡張子なし・小文字): プロジェクトのファイル名と、<TargetName> / <AssemblyName>。"""
    names = set()
    for path in _walk(root, _PROJ_EXTS):
        names.add(os.path.splitext(os.path.basename(path))[0].lower())
        text = _read(path)
        for m in re.finditer(r"<(?:TargetName|AssemblyName)>([^<$]+)</(?:TargetName|AssemblyName)>", text):
            names.add(m.group(1).strip().lower())
    return names


def _strip_comments(text):
    """コメントを空白にする (行の数は、変えない)。"""
    blank = lambda m: re.sub(r"[^\n]", " ", m.group(0))
    return re.sub(r"//[^\n]*", blank, re.sub(r"/\*.*?\*/", blank, text, flags=re.S))


def defined_in_sources(root, name, cache=None):
    """クラス名::関数名 の**定義**が、こちらのソースにあるか。行頭から (戻り値の型は、あってもよい) 名前、(引数)、const などの修飾、そして { か : (コンストラクターの初期化子)。
    呼び出し (`Lib::Fn(1);`、`return Lib::Fn(x);`)、宣言 (末尾が ;)、コメント、マップの &クラス::関数 は、数えない。"""
    if cache is None:
        cache = {}
    if "texts" not in cache:
        cache["texts"] = [_strip_comments(_read(p)) for p in _walk(root, _SRC_EXTS)]
    pat = re.compile(r"^[ \t]*(?:template\s*<[^>]*>\s*)?(?:[A-Za-z_][\w:<>,*&~ \t]*?[ \t*&]+)?" + re.escape(name)
                     + r"[ \t]*\([^;{}]*\)[ \t\r\n]*(?:(?:const|noexcept|override|final|volatile)[ \t\r\n]*)*[{:]", re.M)
    return any(pat.search(t) for t in cache["texts"])


def classify_native(func, module, solution_dir, solution_root, cache=None):
    """ファイルがないフレーム (ネイティブ C++) の判定。こちらのプロジェクトの出力のモジュールで、関数が、こちらのソースに定義されているときだけ ours。それ以外は unknown。"""
    if not solution_root or not module or not solution_dir:
        return "unknown"
    if cache is None:
        cache = {}
    if "outputs" not in cache:
        cache["outputs"] = project_outputs(solution_root)
    if _module_name(module) not in cache["outputs"]:
        return "unknown"
    m = _norm(module)
    if "\\" not in m or not _under(m, _norm(solution_dir)):   # 名前だけのモジュールは、こちらの出力と、確かめられない
        return "unknown"
    if "::" not in func:
        return "unknown"
    return "ours" if defined_in_sources(solution_root, func, cache) else "unknown"


def parse_frame(line):
    """STACK: #n ... の行を {n, func, file, line, module} にする。フレームの行でなければ None (STACK_TRUNCATED: も None)。"""
    m = _FRAME_RE.match(line)
    if not m:
        return None
    rest = m.group(2)
    module = ""
    mm = _MODULE_RE.search(rest)
    if mm:
        module = mm.group(1)
        rest = rest[: mm.start()]
    file = ""
    fline = ""
    fm = _FILE_RE.search(rest)
    if fm:
        file, fline = fm.group(1), fm.group(2)
        rest = rest[: fm.start()]
    return {"n": int(m.group(1)), "func": rest, "file": file, "line": fline, "module": module}


def _solution_dir(lines):
    for l in lines:
        if l.startswith("SOLUTION: "):
            path = l[len("SOLUTION: "):].strip()
            if "\\" in path or "/" in path:
                p = path.replace("/", "\\")
                return p.rsplit("\\", 1)[0]
            return None
    return None


def _summary(frames, truncated=False):
    """frames: [(n, owner)] (上から順)。OWNER: と BOUNDARY: の行を返す。truncated: STACK_TRUNCATED: があり、深いフレームは、見ていない。"""
    non_sys = [(n, o) for n, o in frames if o != "sys"]
    note = "all %d frames shown are sys; deeper frames were not checked" % len(frames)
    if non_sys:
        owner = "OWNER: top=%s (frame #%d)" % (non_sys[0][1], non_sys[0][0])
    elif truncated:
        owner = "OWNER: top=sys (frame #%d; %s)" % (frames[0][0] if frames else 0, note)
    else:
        owner = "OWNER: top=sys (frame #%d)" % (frames[0][0] if frames else 0)
    boundary = "BOUNDARY: none"
    if truncated:
        boundary = "BOUNDARY: none (in the %d frames shown; deeper frames were not checked)" % len(frames)
    found = False
    for (a_n, a_o), (b_n, b_o) in zip(non_sys, non_sys[1:]):
        if a_o == "ext" and b_o == "ours":
            boundary = "BOUNDARY: #%d ours -> ext #%d" % (b_n, a_n)
            found = True
            break
    if not found:
        seen_ext = False
        for idx, (n, o) in enumerate(non_sys):
            if o == "ext":
                seen_ext = True
            elif o == "unknown" and seen_ext and any(x[1] == "ours" for x in non_sys[idx + 1:]):
                boundary = "BOUNDARY: unknown (frame #%d has no symbols)" % n
                break
    return owner, boundary


def _stopped(lines):
    """STOPPED: <関数> at <ファイル>:<行> → {func, file, line} (なければ None)。"""
    for l in lines:
        if l.startswith("STOPPED: "):
            f = parse_frame("STACK: #0 " + l[len("STOPPED: "):])
            if f and f["file"]:
                return f
            return None
    return None


def _stopped_ok(f, stopped, sd, solution_root, cache):
    """STOPPED: のファイルを、このフレームに割り当ててよいか。ファイルがこちらのソリューションの中なら (ours になる)、フレームのモジュールが、
    こちらのプロジェクトの出力で、こちらの出力フォルダにあるときだけ (外の DLL の、同じ名前のフレームに、こちらのファイルを付けて、ours としない)。"""
    p = _norm(stopped["file"])
    if sd is None or not _under(p, _norm(sd)) or _own_or_vendor(p, _norm(sd)) == "ext":
        return True
    if not solution_root or not f["module"]:
        return False
    if "outputs" not in cache:
        cache["outputs"] = project_outputs(solution_root)
    m = _norm(f["module"])
    return _module_name(m) in cache["outputs"] and "\\" in m and _under(m, _norm(sd))


# ネイティブの例外 (SEH。アクセス違反など) は、`$exception` が使えない。VS は、止まったとき、デバッグ出力ペインに、例外の 1 行を書く
# (日本語: `0x… (ExtDll.dll) で例外がスローされました (App.exe 内): 0xC0000005: 場所 … の読み取り中にアクセス違反が発生しました`、英語: `Exception thrown at 0x… (ExtDll.dll) in App.exe: 0xC0000005: Access violation …`)。
# ホストは、その最後の行を `LAST_OUTPUT:` として出す。次の形のときだけ、`EXCEPTION:` にする (言語に依存しない):
#   **アドレス (0x + 8〜16 桁) が先にあり、そのあとに、例外のコード (0xC… / 0xE… / 0x8…) をコロンで挟んだ形**。アプリ自身のログ (`CreateFile failed: 0x80070005: …`) は、アドレスがなく、通らない。
# さらに、行が名前を挙げるモジュール (最初の `(X.dll)`) が、フレーム #0 のモジュールと違うときは、捨てる (処理済みの例外のあと、別の場所のブレークポイントで止まった場合の、古い行)。
# **ペインの 1 行からの推測なので、出所を明示する** (`EXCEPTION: (debug output; may be stale) …`)。
_EXC_LINE_RE = re.compile(r"0x[0-9A-Fa-f]{8,16}\b.*: 0x[CcEe8][0-9A-Fa-f]{7}: ")
_LINE_MODULE_RE = re.compile(r"\(([^()\s]+\.(?:dll|exe|sys|drv|ocx))\)", re.IGNORECASE)
_EXC_TAG = "EXCEPTION: (debug output; may be stale) "


def _fold_last_output(lines):
    """LAST_OUTPUT: の行を取り除き、例外の形で、モジュールが合い、EXCEPTION: がまだないときだけ、出所つきの EXCEPTION: を (最初の STACK: の前に) 足す。"""
    has_exc = any(l.startswith("EXCEPTION:") for l in lines)
    top_module = ""
    for l in lines:
        f = parse_frame(l)
        if f is not None:
            top_module = f["module"]
            break
    out = []
    exc = None
    for l in lines:
        if l.startswith("LAST_OUTPUT: "):
            text = l[len("LAST_OUTPUT: "):].strip()
            if not has_exc and exc is None and _EXC_LINE_RE.search(text):
                mm = _LINE_MODULE_RE.search(text)
                if not (mm and top_module and _module_base(mm.group(1)) != _module_base(top_module)):
                    exc = _EXC_TAG + text
            continue
        out.append(l)
    if exc:
        pos = next((i for i, l in enumerate(out) if l.startswith("STACK: #")), 0)
        out.insert(pos, exc)
    return out


def _module_base(module):
    return module.replace("/", "\\").rsplit("\\", 1)[-1].lower()


def transform(lines, solution_root=None):
    """出力の全行を受け取り、STACK: の行を書き換え、最後の STACK: / STACK_TRUNCATED: の直後に OWNER: と BOUNDARY: を足して返す。
    solution_root: ソリューションのフォルダ (WSL のパス)。ネイティブ C++ のフレームを、こちらのソースの定義と照合するために使う。"""
    lines = _fold_last_output(lines)
    sd = _solution_dir(lines)
    stopped = _stopped(lines)
    stopped_given = False
    cache = {}
    out = []
    frames = []
    last = -1
    truncated = False
    for l in lines:
        f = parse_frame(l)
        if f is None:
            out.append(l)
            if l.startswith("STACK_TRUNCATED:") and frames:
                last = len(out) - 1
                truncated = True
            continue
        # ネイティブ C++ のフレームには、ファイルが取れない。止まったフレームのファイルは、STOPPED: にある。
        # 同じ関数名で、ファイルを持たない最初のフレームに、割り当てる (PDB がなく、#0 にソースがないときは、#1 になる)
        if stopped and not stopped_given and not f["file"] and f["func"] == stopped["func"] and _stopped_ok(f, stopped, sd, solution_root, cache):
            f["file"], f["line"] = stopped["file"], stopped["line"]
            stopped_given = True
        owner = classify(f["file"], f["module"], sd)
        if owner == "unknown" and not f["file"]:
            owner = classify_native(f["func"], f["module"], sd, solution_root, cache)
        frames.append((f["n"], owner))
        text = "STACK: #%d [%s] %s" % (f["n"], owner, f["func"])
        if f["file"]:
            text += " at %s:%s" % (f["file"], f["line"])
        if f["module"]:
            text += " (%s)" % f["module"]
        out.append(text)
        last = len(out) - 1
    if not frames:
        return list(lines)
    owner_line, boundary_line = _summary(frames, truncated)
    out[last + 1:last + 1] = [owner_line, boundary_line]
    return out


def main(argv):
    args = argv[1:]
    solution_root = None
    if len(args) >= 2 and args[0] == "--solution-root":
        solution_root = args[1]
        args = args[2:]
    if len(args) != 1:
        sys.stderr.write("usage: stack_owner.py [--solution-root <folder>] <vs_output.txt>\n")
        return 2
    path = args[0]
    if not os.path.isfile(path):
        return 0
    with open(path, "rb") as fh:
        data = fh.read().decode("utf-8", errors="replace")
    if data.startswith("\ufeff"):
        data = data[1:]
    lines = [l.rstrip("\r") for l in data.split("\n")]
    if lines and lines[-1] == "":
        lines.pop()
    sys.stdout.write("\n".join(transform(lines, solution_root)) + ("\n" if lines else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
