#!/usr/bin/env python3
"""fix_cpp_encoding.py - 日本語を含む、BOM なしの UTF-8 の C++ ソースを、UTF-8 BOM 付きにする (v2.82.0)。

Usage: python3 -I fix_cpp_encoding.py <ソリューションのフォルダ> [--check]

なぜ: MSVC は、BOM なしのファイルを、ANSI (CP932) として読む。日本語を含む、BOM なしの UTF-8 の .cpp / .h は、
      文字化けして、C2447 などのビルドエラーになる。`/new-solution` や `/cpp-test-first` の途中で、新しく作った
      ファイルが、BOM なし・LF になりやすい (実機で、2 回、ビルドが止まった)。
対象: 拡張子が .cpp .cxx .c .h .hpp .hxx .inl .rc で、(1) BOM がない (2) UTF-8 として読める (3) 非 ASCII を含む。
      ASCII だけのファイルは、そのまま (BOM は、要らない)。C# (.cs) は、BOM なしでも読めるので、対象外。
直すこと: BOM を足す。改行が LF だけのファイルは、CRLF にそろえる (CRLF が 1 つでもあれば、改行は変えない)。
行わないこと: プロジェクトに `/utf-8` (または `/source-charset:utf-8`) があれば、何もしない (BOM なしで、正しく読める)。
      bin / obj / x64 / Debug / Release / vcpkg_installed / .git / .claude-logs / node_modules の下は、見ない。
--check: 直さず、対象のファイルを、一覧するだけ (終了コード 1 = 対象あり)。
出力 (標準エラー): 直したファイルの数と、先頭のいくつか。終了コード: 0 = 何も直さなかった・直した / 1 = --check で対象あり。
"""
import os
import sys

BOM = b"\xef\xbb\xbf"
EXTS = {".cpp", ".cxx", ".c", ".h", ".hpp", ".hxx", ".inl", ".rc"}
SKIP_DIRS = {"bin", "obj", "x64", "debug", "release", "vcpkg_installed", ".git", ".claude-logs", "node_modules", ".vs"}
PROJECT_EXTS = {".vcxproj", ".props", ".targets"}


def has_utf8_flag(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d.lower() not in SKIP_DIRS]
        for f in filenames:
            if os.path.splitext(f)[1].lower() in PROJECT_EXTS:
                try:
                    text = open(os.path.join(dirpath, f), encoding="utf-8-sig", errors="replace").read().lower()
                except OSError:
                    continue
                if "/utf-8" in text or "/source-charset:utf-8" in text:
                    return True
    return False


def candidates(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d.lower() not in SKIP_DIRS]
        for f in filenames:
            if os.path.splitext(f)[1].lower() not in EXTS:
                continue
            path = os.path.join(dirpath, f)
            try:
                raw = open(path, "rb").read()
            except OSError:
                continue
            if raw.startswith(BOM):
                continue
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                continue   # CP932 などは、convert_to_utf8_bom.py の領分 (ここでは、触らない)
            if any(ord(c) > 127 for c in text):
                yield path, raw


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    check = "--check" in argv
    if len(args) != 1 or not os.path.isdir(args[0]):
        print("Usage: fix_cpp_encoding.py <ソリューションのフォルダ> [--check]", file=sys.stderr)
        return 2
    root = args[0]
    if has_utf8_flag(root):
        return 0
    targets = list(candidates(root))
    if check:
        for path, _ in targets:
            print(path)
        return 1 if targets else 0
    fixed = []
    for path, raw in targets:
        body = raw
        if b"\r\n" not in body:
            body = body.replace(b"\n", b"\r\n")
        try:
            with open(path, "wb") as fh:
                fh.write(BOM + body)
        except OSError as ex:
            print(f"ENCODING_FIX: 書けない: {path} ({ex})", file=sys.stderr)
            continue
        fixed.append(path)
    if fixed:
        shown = ", ".join(os.path.relpath(p, root) for p in fixed[:5])
        more = f" ほか {len(fixed) - 5} 件" if len(fixed) > 5 else ""
        print(f"ENCODING_FIX: 日本語を含む BOM なしの C++ ソース {len(fixed)} 件を、BOM 付き (改行は CRLF) にした: {shown}{more}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
