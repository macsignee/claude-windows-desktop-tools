#!/usr/bin/env bash
# package_once_test.sh - package_once.sh を、疑似ウォッチャー (ファイルを書くだけの偽物) で検証する。
# Windows 側のウォッチャーや dotnet / vcpkg がなくても、操作の検証と結果の分岐 (1 行目と終了コード) を確認できる。
# Usage: tests/package_once_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/add-package/scripts/package_once.sh"
T="${TMPDIR:-/tmp}/pkgonce_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
BOM=$'\xEF\xBB\xBF'; CR=$'\r'

# 疑似ウォッチャー: フラグを回収 (内容を flag.copy に残す) し、1 秒後に $1 の関数でファイルを書く
fake_watcher() {
    local handler="$1"
    while true; do
        if [ -f "$T/trigger_package.flag" ]; then
            cp "$T/trigger_package.flag" "$T/flag.full"; grep -v "^# run=" "$T/trigger_package.flag" > "$T/flag.copy"
            rm -f "$T/trigger_package.flag"
            sleep 1
            "$handler"
        fi
        sleep 0.3
    done
}
h_ok()    { { printf '%s## nuget versions Newtonsoft.Json%s\nNewtonsoft.Json: 100 versions%s\nstable (newest last): 13.0.1, 13.0.2, 13.0.3%s\n' "$BOM" "$CR" "$CR" "$CR"; } > "$T/package_output.txt"; printf OK > "$T/package_result.txt"; }
h_fail()  { { printf '%s## nuget add App/App.csproj Nope.Pkg%s\n' "$BOM" "$CR"; } > "$T/package_output.txt"; { printf '%serror: Unable to find package Nope.Pkg. No packages exist with this id in source(s): nuget.org%s\n' "$BOM" "$CR"; } > "$T/package_error.log"; printf FAILED > "$T/package_result.txt"; }
h_env()   { { printf '%s[ENVIRONMENT ERROR - not a source code problem]%s\nERROR: vcpkg.exe was not found.%s\n' "$BOM" "$CR" "$CR"; } > "$T/package_error.log"; printf FAILED > "$T/package_result.txt"; }
h_many()  { for i in $(seq 1 200); do echo "line $i"; done > "$T/package_output.txt"; printf OK > "$T/package_result.txt"; }
h_never() { :; }
h_weird() { printf WEIRD > "$T/package_result.txt"; }
h_stale() { sleep 2; h_ok; }

run_case() {  # $1=ハンドラ、残りは package_once.sh の引数 (solution_dir を除く)
    local handler="$1"; shift
    fake_watcher "$handler" & local W=$!
    OUT="$(bash "$SCRIPT" "$T" "$@")"; RC=$?
    kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
    rm -f "$T"/package_* "$T"/trigger_* 2>/dev/null
}

bash -n "$SCRIPT" && ok "syntax" 1

# ---------------------------------------------------------------- 結果の分岐
run_case h_ok "nuget versions Newtonsoft.Json"
ok "OK: rc=0, first line OK, output shown without BOM / CR" "$([ $RC = 0 ] && [ "$(head -1 <<<"$OUT")" = OK ] && [ "$(has "$OUT" 'stable (newest last): 13.0.1, 13.0.2, 13.0.3')" = 1 ] && ! grep -q "$BOM\|$CR" <<<"$OUT" && echo 1 || echo 0)"
ok "OK: the flag holds exactly the operation line" "$([ "$(cat "$T/flag.copy")" = "nuget versions Newtonsoft.Json" ] && echo 1 || echo 0)"

run_case h_ok "nuget search json" "vcpkg search fmt" "fetch nlohmann/json v3.11.3 json single_include"
ok "several operations: one line each, in order" "$([ "$(cat "$T/flag.copy")" = "$(printf 'nuget search json\nvcpkg search fmt\nfetch nlohmann/json v3.11.3 json single_include')" ] && echo 1 || echo 0)"

run_case h_fail "nuget add App/App.csproj Nope.Pkg"
ok "FAILED (source problem): rc=1, error text shown" "$([ $RC = 1 ] && [ "$(head -1 <<<"$OUT")" = FAILED ] && [ "$(has "$OUT" 'Unable to find package Nope.Pkg')" = 1 ] && echo 1 || echo 0)"

run_case h_env "vcpkg install"
ok "ENV_ERROR: rc=4 (not a source problem)" "$([ $RC = 4 ] && [ "$(head -1 <<<"$OUT")" = ENV_ERROR ] && [ "$(has "$OUT" 'vcpkg.exe was not found')" = 1 ] && echo 1 || echo 0)"

run_case h_many "vcpkg search x"
ok "long output is capped (80 lines + a note)" "$([ "$(wc -l <<<"$OUT")" -le 83 ] && [ "$(has "$OUT" '200 lines total')" = 1 ] && echo 1 || echo 0)"

run_case h_weird "vcpkg install"
ok "unexpected marker -> ENV_ERROR rc=4" "$([ $RC = 4 ] && [ "$(has "$OUT" "unexpected package_result.txt: 'WEIRD'")" = 1 ] && echo 1 || echo 0)"

run_case h_never --timeout 4 "vcpkg install"
ok "TIMEOUT: flag picked up but no marker -> rc=5" "$([ $RC = 5 ] && [ "$(head -1 <<<"$OUT")" = TIMEOUT ] && echo 1 || echo 0)"

# 古い結果は、フラグを置く前に、消される
printf OK > "$T/package_result.txt"; printf 'old output\n' > "$T/package_output.txt"
fake_watcher h_stale & W=$!
start=$(date +%s); OUT="$(bash "$SCRIPT" "$T" "nuget versions Newtonsoft.Json")"; RC=$?; el=$(( $(date +%s) - start ))
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null; rm -f "$T"/package_* "$T"/trigger_*
ok "stale result removed before the wait (rc=0 after >= 2s, not instant; old output not shown)" "$([ $RC = 0 ] && [ "$el" -ge 2 ] && [ "$(has "$OUT" 'old output')" = 0 ] && echo 1 || echo 0)"

# --file (ThirdParty.manifest): コメントと空行は無視、CRLF も可
printf '# header\r\n\r\nfetch nlohmann/json v3.11.3 json single_include\r\nfetch fmtlib/fmt 11.0.2 fmt\r\n' > "$T/ThirdParty.manifest"
run_case h_ok --file "$T/ThirdParty.manifest"
ok "--file: operations replayed one per line (comments / blank lines / CR dropped)" "$([ $RC = 0 ] && [ "$(cat "$T/flag.copy")" = "$(printf 'fetch nlohmann/json v3.11.3 json single_include\nfetch fmtlib/fmt 11.0.2 fmt')" ] && echo 1 || echo 0)"
run_case h_ok "vcpkg search zlib" --file "$T/ThirdParty.manifest"
ok "operation arguments come before --file lines" "$([ "$(head -1 "$T/flag.copy")" = "vcpkg search zlib" ] && [ "$(wc -l < "$T/flag.copy")" = 3 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 引数の検証 (ウォッチャーを呼ぶ前に、拒否する)
bad() {  # $1=説明 残り=引数
    local why="$1"; shift
    local out rc
    out="$(bash "$SCRIPT" "$T" "$@")"; rc=$?
    ok "BAD_ARGS: $why" "$([ $rc = 2 ] && [ "$(head -1 <<<"$out" | cut -c1-8)" = BAD_ARGS ] && [ ! -f "$T/trigger_package.flag" ] && echo 1 || echo 0)"
}
bad "package id with ';' (command injection)" "nuget add App/App.csproj 'Foo;calc'"
bad "package id with '&'" "nuget versions Foo&calc"
bad "project outside the solution ('..')" "nuget add ../Evil/Evil.csproj Foo"
bad "project that is not a .csproj" "nuget add App/App.vcxproj Foo"
bad "project with a drive path" "nuget add C:/x/App.csproj Foo"
bad "version with a space" "nuget add App/App.csproj Foo '1.0 --source http://evil'"
bad "version starting with '-'" "nuget add App/App.csproj Foo --prerelease"
bad "unknown nuget verb" "nuget push App/App.csproj Foo"
bad "unknown tool" "choco install foo"
bad "vcpkg install with an argument" "vcpkg install --triplet evil"
bad "vcpkg search with a space" "vcpkg search 'a b'"
bad "fetch with a URL as the repo" "fetch https://evil.example/x v1 foo"
bad "fetch with '..' in the subfolder" "fetch a/b v1 foo ../x"
bad "fetch name with a slash" "fetch a/b v1 foo/bar"
bad "fetch tag starting with '-'" "fetch a/b -v1 foo"
bad "fetch with too few arguments" "fetch a/b v1"
bad "empty operation list" --timeout 5
bad "timeout that is not a number" --timeout abc "vcpkg install"
out="$(bash "$SCRIPT" "$T/nonexistent" "vcpkg install")"; rc=$?
ok "BAD_ARGS: solution dir missing -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
out="$(bash "$SCRIPT" "$T" --file "$T/none.txt")"; rc=$?
ok "BAD_ARGS: --file that does not exist -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
printf 'fetch a/b v1 foo\nvcpkg install --evil\n' > "$T/bad.manifest"
out="$(bash "$SCRIPT" "$T" --file "$T/bad.manifest")"; rc=$?
ok "BAD_ARGS: an invalid line inside --file is rejected as well" "$([ $rc = 2 ] && [ ! -f "$T/trigger_package.flag" ] && echo 1 || echo 0)"

# 正しい形は、通る (拒否しすぎない)
good() {
    run_case h_ok "$@"
    ok "accepted: $*" "$([ $RC = 0 ] && echo 1 || echo 0)"
}
good "nuget add src/App/App.csproj CommunityToolkit.Mvvm 8.4.0"
good "nuget add App\\App.csproj Serilog.Sinks.File 6.0.0-beta.1"
good "nuget remove App/App.csproj Newtonsoft.Json"
good "vcpkg baseline"
good "fetch fmtlib/fmt 11.0.2 fmt"
good "fetch nlohmann/json v3.11.3 json single_include"
good "fetch Neargye/magic_enum v0.9.7 magic_enum include/magic_enum"

echo "=== WATCHER_NOT_RUNNING (expect rc=3 after ~15s)"
out="$(bash "$SCRIPT" "$T" --timeout 30 "vcpkg search fmt")"; rc=$?
ok "WATCHER_NOT_RUNNING: rc=3, the flag is withdrawn" "$([ $rc = 3 ] && [ "$(head -1 <<<"$out")" = WATCHER_NOT_RUNNING ] && [ ! -f "$T/trigger_package.flag" ] && echo 1 || echo 0)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
