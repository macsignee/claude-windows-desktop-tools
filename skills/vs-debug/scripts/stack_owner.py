#!/usr/bin/env python3
"""stack_owner.py - vs_once.sh --inspect の STACK: の各フレームに、所有者の印と、要約を付ける (v2.107.0)。

Usage: python3 -I stack_owner.py <vs_output.txt>
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
_VENDOR_DIRS = ("vcpkg_installed", "packages", "thirdparty", "third_party", "external", "vendor")

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


def transform(lines):
    """出力の全行を受け取り、STACK: の行を書き換え、最後の STACK: / STACK_TRUNCATED: の直後に OWNER: と BOUNDARY: を足して返す。"""
    sd = _solution_dir(lines)
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
        owner = classify(f["file"], f["module"], sd)
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
    if len(argv) != 2:
        sys.stderr.write("usage: stack_owner.py <vs_output.txt>\n")
        return 2
    path = argv[1]
    if not os.path.isfile(path):
        return 0
    with open(path, "rb") as fh:
        data = fh.read().decode("utf-8", errors="replace")
    if data.startswith("\ufeff"):
        data = data[1:]
    lines = [l.rstrip("\r") for l in data.split("\n")]
    if lines and lines[-1] == "":
        lines.pop()
    sys.stdout.write("\n".join(transform(lines)) + ("\n" if lines else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
