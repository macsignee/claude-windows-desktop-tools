#!/usr/bin/env python3
"""convert_to_utf8_bom.py - Shift-JIS (CP932) のソースを、UTF-8 (BOM 付き) / CRLF に変換する (LF のファイルは CRLF にそろえる)。

Usage: python3 -I convert_to_utf8_bom.py [--apply] <file>...

既定は、検証だけ (ファイルを書かない)。--apply で、その場で書き換える。
変換前に、CP932 として読めること、変換後に、CP932 へ戻すと元のバイト列と (改行を除いて) 一致すること
(= 文字化け・欠落がないこと) を確かめる。確認できないファイルは、書き換えない。
すでに BOM 付きの UTF-8 のファイルは、何もしない。末尾に改行がなければ、足す。
**BOM なしの UTF-8 (非 ASCII を含む) に見えるファイルは、変換しない (NG)。** UTF-8 の日本語は、CP932 としても、たまたま読めることが
多く (往復の確認も通ってしまう)、そのまま変換すると、文字化けした内容を、UTF-8 として書き込むため。読めないファイルや、存在しないファイルは、
NG とし、ほかのファイルは、続けて処理する。終了コード: 0 = すべて OK (またはスキップ) / 1 = NG のファイルがある。
"""
import sys

BOM = b"\xef\xbb\xbf"


def looks_like_utf8(raw):
    """UTF-8 として読めて、非 ASCII の文字を含むか (BOM なしの UTF-8 の疑い)。ASCII だけのファイルは、対象外 (変換してよい)。"""
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return any(ord(c) > 127 for c in text)


def convert(raw):
    text = raw.decode("cp932")
    if "\r" in text.replace("\r\n", ""):
        raise ValueError("lone CR found")
    lf = text.replace("\r\n", "\n")
    if not lf.endswith("\n"):
        lf += "\n"
    out = BOM + lf.replace("\n", "\r\n").encode("utf-8")
    # 往復の確認 (改行は LF にそろえて比べる。末尾の改行の追加だけは、差として許す)
    want = raw.replace(b"\r\n", b"\n")
    back = out[len(BOM):].decode("utf-8").replace("\r\n", "\n").encode("cp932")
    if back != want and back != want + b"\n":
        raise ValueError("round trip mismatch")
    return out


def main(argv):
    apply = "--apply" in argv
    files = [a for a in argv if a != "--apply"]
    bad = 0
    for p in files:
        try:
            raw = open(p, "rb").read()
        except OSError as e:
            print(f"NG   {p}: {e.strerror or e}")
            bad += 1
            continue
        if raw.startswith(BOM):
            print(f"skip (already UTF-8 BOM): {p}")
            continue
        if looks_like_utf8(raw):
            print(f"NG   {p}: UTF-8 (BOM なし) に見える。Shift-JIS ではないので、変換しない (BOM を付けるだけなら、別の方法で)")
            bad += 1
            continue
        try:
            out = convert(raw)
        except (UnicodeDecodeError, ValueError) as e:
            print(f"NG   {p}: {e}")
            bad += 1
            continue
        print(f"{'WROTE' if apply else 'OK  '} {p}  ({len(raw)} -> {len(out)} bytes)")
        if apply:
            open(p, "wb").write(out)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
