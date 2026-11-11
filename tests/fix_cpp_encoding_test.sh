#!/usr/bin/env bash
# fix_cpp_encoding_test.sh - skills/build-test-loop/scripts/fix_cpp_encoding.py (BOM なしの日本語の C++ ソースを、BOM 付きにそろえる) の検証 (Windows 不要)。
# Usage: tests/fix_cpp_encoding_test.sh      終了コード: 0 すべて OK / 1 失敗あり
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/skills/build-test-loop/scripts/fix_cpp_encoding.py"
W="$(mktemp -d "${TMPDIR:-/tmp}/fixenc.XXXXXX")"; trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
bom() { [ "$(head -c3 "$1" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ] && echo 1 || echo 0; }
crlf() { grep -q $'\r' "$1" && echo 1 || echo 0; }

mkdir -p "$W/a/Proj" "$W/a/Proj/bin" "$W/a/Proj/x64/Debug"
printf '// 日本語のコメント\nint main() { return 0; }\n' > "$W/a/Proj/Jp.cpp"            # BOM なし・LF・日本語
printf 'int ascii_only();\n' > "$W/a/Proj/Ascii.h"                                       # ASCII だけ
printf '\xef\xbb\xbf// 日本語\r\nint x;\r\n' > "$W/a/Proj/HasBom.cpp"                    # すでに BOM 付き
printf '// 日本語\nclass A {};\n' > "$W/a/Proj/Skip.cs"                                   # C# は対象外
printf '// 日本語\nint b;\n' > "$W/a/Proj/bin/InBin.cpp"                                 # bin の下は見ない
printf '// 日本語\nint c;\n' > "$W/a/Proj/x64/Debug/InX64.cpp"                           # x64 の下は見ない
printf '// 日本語\r\nint m;\nint n;\n' > "$W/a/Proj/Mixed.cpp"                           # CRLF が 1 つでもあれば、改行は変えない
printf '\x82\xa0\x82\xa2\n' > "$W/a/Proj/Sjis.cpp"                                       # CP932 (UTF-8 として読めない) は、触らない
cp "$W/a/Proj/Sjis.cpp" "$W/sjis.orig"; cp "$W/a/Proj/Ascii.h" "$W/ascii.orig"; cp "$W/a/Proj/Skip.cs" "$W/skip.orig"
cp "$W/a/Proj/bin/InBin.cpp" "$W/inbin.orig"; cp "$W/a/Proj/HasBom.cpp" "$W/hasbom.orig"

out="$(python3 -I "$FIX" "$W/a" --check)"; rc=$?
ok "--check lists the BOM-less Japanese C++ files and returns 1 (no file is written)" "$([ "$rc" = 1 ] && echo "$out" | grep -q 'Jp.cpp' && echo "$out" | grep -q 'Mixed.cpp' && [ "$(bom "$W/a/Proj/Jp.cpp")" = 0 ] && echo 1 || echo 0)"
ok "--check does not list ASCII-only, BOM files, C#, bin/x64, or CP932 files" "$(echo "$out" | grep -q 'Ascii.h\|HasBom\|Skip.cs\|InBin\|InX64\|Sjis' && echo 0 || echo 1)"

err="$(python3 -I "$FIX" "$W/a" 2>&1 >/dev/null)"; rc=$?
ok "run: exit 0 and a one-line ENCODING_FIX notice on stderr (2 files)" "$([ "$rc" = 0 ] && echo "$err" | grep -q 'ENCODING_FIX: .* 2 件' && echo 1 || echo 0)"
ok "Jp.cpp: BOM added, LF converted to CRLF, content kept" "$([ "$(bom "$W/a/Proj/Jp.cpp")" = 1 ] && [ "$(crlf "$W/a/Proj/Jp.cpp")" = 1 ] && grep -q '日本語のコメント' "$W/a/Proj/Jp.cpp" && echo 1 || echo 0)"
ok "Mixed.cpp: BOM added, line endings unchanged (a lone LF stays)" "$([ "$(bom "$W/a/Proj/Mixed.cpp")" = 1 ] && [ "$(tail -c 7 "$W/a/Proj/Mixed.cpp" | od -An -c | tr -d ' ' | tr -d '\n')" = "int n;\n" ] || [ "$(grep -c $'\r' "$W/a/Proj/Mixed.cpp")" = 1 ] && echo 1 || echo 0)"
ok "ASCII-only, already-BOM, C#, bin, CP932 files are untouched" "$(cmp -s "$W/a/Proj/Ascii.h" "$W/ascii.orig" && cmp -s "$W/a/Proj/HasBom.cpp" "$W/hasbom.orig" && cmp -s "$W/a/Proj/Skip.cs" "$W/skip.orig" && cmp -s "$W/a/Proj/bin/InBin.cpp" "$W/inbin.orig" && cmp -s "$W/a/Proj/Sjis.cpp" "$W/sjis.orig" && echo 1 || echo 0)"
err2="$(python3 -I "$FIX" "$W/a" 2>&1)"
ok "second run changes nothing and prints nothing (idempotent)" "$([ -z "$err2" ] && echo 1 || echo 0)"

mkdir -p "$W/b"; printf '<Project><ItemDefinitionGroup><ClCompile><AdditionalOptions>/utf-8 %%(AdditionalOptions)</AdditionalOptions></ClCompile></ItemDefinitionGroup></Project>\n' > "$W/b/P.vcxproj"
printf '// 日本語\nint d;\n' > "$W/b/Jp.cpp"
python3 -I "$FIX" "$W/b" >/dev/null 2>&1
ok "a project with /utf-8: nothing is changed" "$([ "$(bom "$W/b/Jp.cpp")" = 0 ] && echo 1 || echo 0)"
python3 -I "$FIX" "$W/nonexistent" >/dev/null 2>&1; ok "bad folder: exit 2" "$([ $? = 2 ] && echo 1 || echo 0)"

ok "build_test_once.sh and build_once.sh call fix_cpp_encoding.py (uitest_once.sh goes through build_test_once.sh)" "$(grep -q 'fix_cpp_encoding.py' "$ROOT/skills/build-test-loop/scripts/build_test_once.sh" && grep -q 'fix_cpp_encoding.py' "$ROOT/skills/auto-build/scripts/build_once.sh" && echo 1 || echo 0)"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
