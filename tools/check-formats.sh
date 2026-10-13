#!/usr/bin/env bash
# check-formats.sh - ファイルの文字コード・改行・BOM が、決められた形式か検証する。
#
# Usage: tools/check-formats.sh [root_dir]      (省略時は、このスクリプトの親フォルダ = リポジトリのルート)
# 終了コード: 0 すべて OK / 1 形式の違反あり
#
# 形式 (docs/DESIGN.md「ファイル形式」):
#   *.cmd  : CP932 (Shift_JIS)、CRLF、BOM なし
#   *.ps1  : UTF-8、BOM あり、CRLF
#   *.sh   : UTF-8、LF、BOM なし (bash -n で構文も確認)
#   *.md   : UTF-8、LF、BOM なし
#   *.py   : UTF-8、LF、BOM なし (python3 で構文も確認)
set -u

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
fail=0
checked=0

ng() { echo "NG  $1: $2"; fail=1; }

has_bom()  { [ "$(head -c3 "$1" | xxd -p)" = "efbbbf" ]; }
has_cr()   { grep -q $'\r' "$1"; }
all_crlf() { # 全行が CR で終わっているか (最終行に改行がない場合は、その行を除く)
    local bad
    bad=$(grep -c -v $'\r$' "$1")
    [ "$bad" -eq 0 ]
}

while IFS= read -r -d '' f; do
    rel="${f#$ROOT/}"
    case "$f" in
        *.cmd)
            checked=$((checked + 1))
            has_bom "$f"   && ng "$rel" "BOM がある (CP932 は BOM なし)"
            all_crlf "$f"  || ng "$rel" "CRLF でない行がある"
            iconv -f cp932 -t utf-8 "$f" >/dev/null 2>&1 || ng "$rel" "CP932 として読めない (UTF-8 などで保存し直された?)"
            ;;
        *.ps1)
            checked=$((checked + 1))
            has_bom "$f"   || ng "$rel" "BOM がない (Windows PowerShell 5.1 で日本語が化ける)"
            all_crlf "$f"  || ng "$rel" "CRLF でない行がある"
            iconv -f utf-8 -t utf-8 "$f" >/dev/null 2>&1 || ng "$rel" "UTF-8 として読めない"
            ;;
        *.sh)
            checked=$((checked + 1))
            has_bom "$f"   && ng "$rel" "BOM がある"
            has_cr "$f"    && ng "$rel" "CR (CRLF) が含まれる (bash で動かない)"
            iconv -f utf-8 -t utf-8 "$f" >/dev/null 2>&1 || ng "$rel" "UTF-8 として読めない"
            bash -n "$f" 2>/dev/null || ng "$rel" "bash の構文エラー"
            ;;
        *.py)
            checked=$((checked + 1))
            has_bom "$f"   && ng "$rel" "BOM がある"
            has_cr "$f"    && ng "$rel" "CR (CRLF) が含まれる"
            iconv -f utf-8 -t utf-8 "$f" >/dev/null 2>&1 || ng "$rel" "UTF-8 として読めない"
            python3 -c "import ast,sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" "$f" 2>/dev/null || ng "$rel" "python の構文エラー"
            ;;
        *.md)
            checked=$((checked + 1))
            has_bom "$f"   && ng "$rel" "BOM がある"
            has_cr "$f"    && ng "$rel" "CR (CRLF) が含まれる"
            iconv -f utf-8 -t utf-8 "$f" >/dev/null 2>&1 || ng "$rel" "UTF-8 として読めない"
            ;;
    esac
done < <(find "$ROOT" -type f \( -name '*.cmd' -o -name '*.ps1' -o -name '*.sh' -o -name '*.md' -o -name '*.py' \) \
            -not -path '*/.git/*' -print0 | sort -z)

if [ "$fail" -eq 0 ]; then
    echo "OK  形式の検証に成功 ($checked ファイル)"
fi
exit "$fail"
