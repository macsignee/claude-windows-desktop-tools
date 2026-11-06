#!/usr/bin/env bash
# convert_utf8_bom_test.sh - scripts/convert_to_utf8_bom.py (Shift-JIS -> UTF-8 BOM / CRLF) の検証 (Windows 不要)。
# 既定は検証だけ / --apply で書く / 往復の確認 / BOM 付きはスキップ / BOM なしの UTF-8 は変換しない (v2.41.0) / 存在しないファイルは NG で、続ける。
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/scripts/convert_to_utf8_bom.py"
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
D="${TMPDIR:-/tmp}/cvt_$$"; mkdir -p "$D"
py() { python3 -I "$S" "$@"; }

# 入力の作成
python3 -I - "$D" <<'PY'
import sys
d=sys.argv[1]
open(d+'/sjis_crlf.cpp','wb').write('// 日本語のコメント\r\nint x;\r\n'.encode('cp932'))
open(d+'/sjis_lf.cpp','wb').write('// 日本語のコメント\nint y;\n'.encode('cp932'))
open(d+'/sjis_nonl.cpp','wb').write('// 末尾に改行なし'.encode('cp932'))
open(d+'/ascii.cpp','wb').write(b'int a;\r\n')
open(d+'/bom.cpp','wb').write(b'\xef\xbb\xbf'+'// すでに BOM 付き\r\n'.encode('utf-8'))
open(d+'/lone_cr.cpp','wb').write('// 単独の CR\rint z;\r\n'.encode('cp932'))
# BOM なしの UTF-8 (CP932 としても、たまたま読めるもの)。修正の前は、文字化けして、受理された
for i,s in enumerate(["// 画像を読み込む\n","// 計算結果を表示\n","// ダイアログを閉じる\n","// 描画する\n","// リストに追加\n","// 削除する\n"]):
    open(d+f'/utf8_nobom_{i}.cpp','wb').write(s.encode('utf-8'))
PY

# 1. 既定は、検証だけ (書かない)
cp "$D/sjis_crlf.cpp" "$D/sjis_crlf.orig"
out="$(py "$D/sjis_crlf.cpp" 2>&1)"; rc=$?
ok "default is verify only: prints OK, exit 0, the file is not changed" "$([ $rc = 0 ] && echo "$out" | grep -q '^OK ' && cmp -s "$D/sjis_crlf.cpp" "$D/sjis_crlf.orig" && echo 1 || echo 0)"
# 2. --apply で、UTF-8 (BOM) + CRLF に変換
py --apply "$D/sjis_crlf.cpp" "$D/sjis_lf.cpp" "$D/sjis_nonl.cpp" >/dev/null 2>&1; rc=$?
res="$(python3 -I - "$D" <<'PY'
import sys
d=sys.argv[1]
BOM=b'\xef\xbb\xbf'
def chk(n,want):
    b=open(d+'/'+n,'rb').read()
    return b.startswith(BOM) and b[3:].decode('utf-8')==want and b'\n' not in b[3:].replace(b'\r\n',b'')
ok=chk('sjis_crlf.cpp','// 日本語のコメント\r\nint x;\r\n') and chk('sjis_lf.cpp','// 日本語のコメント\r\nint y;\r\n') and chk('sjis_nonl.cpp','// 末尾に改行なし\r\n')
print(1 if ok else 0)
PY
)"
ok "--apply converts Shift-JIS to UTF-8 with BOM and CRLF (LF is turned into CRLF, a final newline is added)" "$([ $rc = 0 ] && [ "$res" = 1 ] && echo 1 || echo 0)"
# 3. 2 回目は、何もしない (BOM 付きは、スキップ)
before="$(cksum < "$D/sjis_crlf.cpp")"
out="$(py --apply "$D/sjis_crlf.cpp" "$D/bom.cpp" 2>&1)"; rc=$?
ok "an already converted file (UTF-8 BOM) is skipped, not changed, exit 0" "$([ $rc = 0 ] && [ "$(echo "$out" | grep -c '^skip')" = 2 ] && [ "$(cksum < "$D/sjis_crlf.cpp")" = "$before" ] && echo 1 || echo 0)"
# 4. ASCII だけのファイルは、変換してよい (BOM が付く)
py --apply "$D/ascii.cpp" >/dev/null 2>&1; rc=$?
ok "an ASCII-only file is converted (BOM added), exit 0" "$([ $rc = 0 ] && [ "$(head -c3 "$D/ascii.cpp" | xxd -p)" = efbbbf ] && echo 1 || echo 0)"
# 5. 単独の CR は、NG (書かない)
cp "$D/lone_cr.cpp" "$D/lone_cr.orig"
out="$(py --apply "$D/lone_cr.cpp" 2>&1)"; rc=$?
ok "a lone CR is NG, exit 1, the file is not changed" "$([ $rc = 1 ] && echo "$out" | grep -q '^NG ' && cmp -s "$D/lone_cr.cpp" "$D/lone_cr.orig" && echo 1 || echo 0)"
# 6. BOM なしの UTF-8 は、変換しない (6 件とも NG。--apply でも書かない)  [v2.41.0 の修正]
for i in 0 1 2 3 4 5; do cp "$D/utf8_nobom_$i.cpp" "$D/utf8_nobom_$i.orig"; done
out="$(py --apply "$D"/utf8_nobom_[0-5].cpp 2>&1)"; rc=$?
same=1; for i in 0 1 2 3 4 5; do cmp -s "$D/utf8_nobom_$i.cpp" "$D/utf8_nobom_$i.orig" || same=0; done
ok "UTF-8 without BOM (that CP932 happens to decode) is NG for all 6 samples, exit 1, nothing is written (mojibake is no longer produced silently)" "$([ $rc = 1 ] && [ "$(echo "$out" | grep -c '^NG ')" = 6 ] && [ $same = 1 ] && ! echo "$out" | grep -q 'WROTE' && echo 1 || echo 0)"
# 7. 存在しないファイルは、NG にして、ほかのファイルは、続けて処理する
python3 -I -c "open('$D/next.cpp','wb').write('// 次のファイル\n'.encode('cp932'))"
out="$(py --apply "$D/nofile.cpp" "$D/next.cpp" 2>&1)"; rc=$?
ok "a missing file is NG without a traceback, the next file is still converted, exit 1" "$([ $rc = 1 ] && echo "$out" | grep -q '^NG .*nofile.cpp' && ! echo "$out" | grep -q 'Traceback' && [ "$(head -c3 "$D/next.cpp" | xxd -p)" = efbbbf ] && echo 1 || echo 0)"
# 8. Shift-JIS として読めないバイト列は、NG (書かない)
printf '\x81' > "$D/broken.cpp"; cp "$D/broken.cpp" "$D/broken.orig"
out="$(py --apply "$D/broken.cpp" 2>&1)"; rc=$?
ok "bytes that are not valid CP932 are NG, the file is not changed" "$([ $rc = 1 ] && cmp -s "$D/broken.cpp" "$D/broken.orig" && echo 1 || echo 0)"
# 9. 配布: install.sh が、~/.claude/scripts/ に配る
T="$D/inst"; bash "$ROOT/install/install.sh" --rules-only --rules-dir "$T/r" --templates-dir "$T/t" --scripts-dir "$T/s" >/dev/null 2>&1
ok "install.sh --rules-only copies scripts/convert_to_utf8_bom.py (identical to the repo)" "$([ -f "$T/s/convert_to_utf8_bom.py" ] && cmp -s "$T/s/convert_to_utf8_bom.py" "$S" && echo 1 || echo 0)"
# 10. 規則が参照する場所と同じ名前 (.claude/scripts/convert_to_utf8_bom.py)
ok "cpp-common.md and csharp-common.md refer to .claude/scripts/convert_to_utf8_bom.py, which the repo now ships" "$(grep -q '.claude/scripts/convert_to_utf8_bom.py' "$ROOT/rules/cpp-common.md" && grep -q '.claude/scripts/convert_to_utf8_bom.py' "$ROOT/rules/csharp-common.md" && [ -f "$S" ] && echo 1 || echo 0)"

rm -rf "$D" 2>/dev/null
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
