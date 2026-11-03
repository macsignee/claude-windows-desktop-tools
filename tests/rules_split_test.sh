#!/usr/bin/env bash
# rules_split_test.sh - C# の規約の 3 分割 (csharp-common.md / wpf-csharp.md / winforms-csharp.md。v2.35.0) を検証する。
# 文字列とバイト数による構造の確認 (Windows 不要)。読み込みの条件 (paths) が、実際に効くかは、実機で確かめる (TEST-PLAN 2-16)。
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
C="$ROOT/rules/csharp-common.md"; W="$ROOT/rules/wpf-csharp.md"; F="$ROOT/rules/winforms-csharp.md"
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
fm() { awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$1"; }
chap() { grep -o '^## [0-9]*\.' "$1" | tr -d '#. ' | tr '\n' ' '; }

ok "3 files exist" "$([ -f "$C" ] && [ -f "$W" ] && [ -f "$F" ] && echo 1 || echo 0)"
ok "common: paths is **/*.cs only" "$([ "$(fm "$C" | grep -c '^  - ')" = 1 ] && fm "$C" | grep -q '"\*\*/\*\.cs"' && echo 1 || echo 0)"
ok "wpf: paths does not match every .cs / .csproj (xaml, ViewModels, Views, *ViewModel* only)" "$(! fm "$W" | grep -q '"\*\*/\*\.cs"' && ! fm "$W" | grep -q 'csproj' && fm "$W" | grep -q '\*\*/\*\.xaml"' && fm "$W" | grep -q 'ViewModels' && fm "$W" | grep -q 'Views' && echo 1 || echo 0)"
ok "winforms: paths does not match every .cs / .csproj (Designer.cs, Forms, Presenters, *Presenter*, I*View only)" "$(! fm "$F" | grep -q '"\*\*/\*\.cs"' && ! fm "$F" | grep -q 'csproj' && fm "$F" | grep -q 'Designer\.cs' && fm "$F" | grep -q 'Forms' && fm "$F" | grep -q 'Presenters' && fm "$F" | grep -q 'Presenter\*' && echo 1 || echo 0)"
ok "common has the shared C# chapters 5 10 11 12 13 15 16 17, and no others" "$([ "$(chap "$C")" = '5 10 11 12 13 15 16 17 ' ] && echo 1 || echo 0)"
ok "wpf keeps the WPF-specific chapters and has none of the shared ones (numbers are unchanged)" "$([ "$(chap "$W")" = '1 2 3 4 6 7 8 9 14 18 19 ' ] && echo 1 || echo 0)"
ok "winforms: refers to csharp-common.md, no longer says to apply wpf-csharp.md chapters" "$(grep -q 'csharp-common.md' "$F" && ! grep -q '`wpf-csharp.md` の「' "$F" && ! grep -q 'wpf-csharp.md`) の \*\*C# の部分' "$F" && echo 1 || echo 0)"
ok "wpf points to csharp-common.md for the moved chapters" "$(grep -q 'csharp-common.md` に移した' "$W" && echo 1 || echo 0)"
ok "no other file still tells to read the shared chapters from wpf-csharp.md (new-solution, csharp-test-first, README)" "$(! grep -rq 'wpf-csharp.md` の C# の部分' "$ROOT/skills" "$ROOT/README.md" && echo 1 || echo 0)"

# 読み込みの大きさの上限 (バイト数。再び膨らまないように)。WinForms のファイルを読む = common + winforms、WPF = common + wpf
bytes() { wc -c < "$1" | tr -d ' '; }
bc=$(bytes "$C"); bw=$(bytes "$W"); bf=$(bytes "$F")
ok "WinForms: common + winforms <= 40000 bytes (was 62524 before the split; ${bc}+${bf})" "$([ $((bc+bf)) -le 40000 ] && echo 1 || echo 0)"
ok "WPF: common + wpf <= 44000 bytes (was 62524 before the split; ${bc}+${bw})" "$([ $((bc+bw)) -le 44000 ] && echo 1 || echo 0)"
ok "a plain .cs read (common only) <= 15000 bytes (${bc})" "$([ "$bc" -le 15000 ] && echo 1 || echo 0)"

# 配布: install.sh --rules-only が、3 つとも対象にする
out="$(bash "$ROOT/install/install.sh" --rules-only --dry-run --rules-dir "${TMPDIR:-/tmp}/rs_$$" 2>&1)"
ok "install.sh --rules-only --dry-run lists the 3 rule files" "$(echo "$out" | grep -q 'csharp-common.md' && echo "$out" | grep -q 'wpf-csharp.md' && echo "$out" | grep -q 'winforms-csharp.md' && echo 1 || echo 0)"

# C++ / MFC の規則 (mfc-cpp.md) と、C++ のひな形 (templates/cpp/) も、リポジトリに入っている (v2.41.0)。
# 名前は、wpf-csharp.md / winforms-csharp.md の <技術>-<言語> に揃えた (旧名 cpp-mfc.md は、取り込む前に、リポジトリの外にあった)
CPP="$ROOT/rules/mfc-cpp.md"
ok "mfc-cpp.md is in the repo (named like wpf-csharp.md), the old cpp-mfc.md is not; paths are the C++ extensions only (not **/*.cs), UTF-8 without BOM, LF" "$([ -f "$CPP" ] && [ ! -e "$ROOT/rules/cpp-mfc.md" ] && head -n 1 "$CPP" | grep -q '^---$' && fm "$CPP" | grep -q '"\*\*/\*\.cpp"' && fm "$CPP" | grep -q '"\*\*/\*\.h"' && ! fm "$CPP" | grep -q '\.cs"' && [ "$(head -c3 "$CPP" | xxd -p)" = 2d2d2d ] && ! grep -q $'\r' "$CPP" && grep -q '^# C++ / MFC コーディング規約' "$CPP" && echo 1 || echo 0)"
ok "mfc-cpp.md: CView::m_pDocument is not called public (it is protected in afxwin.h)" "$(grep -q 'CView::m_pDocument` (`protected`。派生クラスから触れる)' "$CPP" && ! grep -q '`public` メンバー変数 (`CWnd::m_hWnd`、`CView::m_pDocument`' "$CPP" && echo 1 || echo 0)"
ok "mfc-cpp.md: iterating MFC collections with iterators is a recommendation (not required), mfciterators.h is only an example without the personal absolute path" "$(grep -q '使うことを、推奨する\*\* (必須ではない。使わなくてもよい)' "$CPP" && grep -q '\*\*一例:\*\* 自作の `mfciterators.h`' "$CPP" && grep -q '特定のファイルに、固定しない' "$CPP" && ! grep -q 'C:\\Workspace' "$CPP" && ! grep -q '実装例:\*\* 自作の' "$CPP" && echo 1 || echo 0)"
ok "wpf-csharp.md refers to mfc-cpp.md (not the old name) and the file exists in the repo" "$(grep -q 'mfc-cpp.md' "$W" && ! grep -q 'cpp-mfc.md' "$W" && [ -f "$CPP" ] && echo 1 || echo 0)"
CPPT="${TMPDIR:-/tmp}/rs_cpp_$$"; bash "$ROOT/install/install.sh" --rules-only --rules-dir "$CPPT" --templates-dir "$CPPT/t" --scripts-dir "$CPPT/s" >/dev/null 2>&1
ok "install.sh --rules-only copies mfc-cpp.md (identical to the repo)" "$([ -f "$CPPT/mfc-cpp.md" ] && cmp -s "$CPPT/mfc-cpp.md" "$CPP" && echo 1 || echo 0)"
ok "install.sh copies templates/cpp/ (.clang-format .clang-tidy .editorconfig)" "$([ -f "$CPPT/t/cpp/.clang-format" ] && [ -f "$CPPT/t/cpp/.clang-tidy" ] && [ -f "$CPPT/t/cpp/.editorconfig" ] && echo 1 || echo 0)"
rm -rf "$CPPT" 2>/dev/null
# 旧名 (cpp-mfc.md) が、配布先に残っているとき、警告が出る (二重に読み込まれるため)
CPPO="${TMPDIR:-/tmp}/rs_old_$$"; mkdir -p "$CPPO"; echo old > "$CPPO/cpp-mfc.md"
out="$(bash "$ROOT/install/install.sh" --rules-only --rules-dir "$CPPO" --templates-dir "$CPPO/t" --scripts-dir "$CPPO/s" 2>&1)"
ok "install.sh warns when the old cpp-mfc.md is left in the rules folder (it would be loaded twice)" "$(echo "$out" | grep -q '旧名の規則が残っています' && echo "$out" | grep -q 'mfc-cpp.md' && [ -f "$CPPO/cpp-mfc.md" ] && echo 1 || echo 0)"
rm -rf "$CPPO" 2>/dev/null

# templates/cpp/: mfc-cpp.md の規則 (Allman、スペース 4、include の順序を変えない、関数は 100 行まで、CRLF、charset を書かない) と食い違わない
TC="$ROOT/templates/cpp"
ok "templates/cpp matches mfc-cpp.md (Allman, indent 4, SortIncludes Never, function-size 100, CRLF for cpp/h/hpp, no charset line)" "$(grep -q 'BreakBeforeBraces: Allman' "$TC/.clang-format" && grep -q 'IndentWidth: 4' "$TC/.clang-format" && grep -q 'UseTab: Never' "$TC/.clang-format" && grep -q 'SortIncludes: Never' "$TC/.clang-format" && grep -q "LineThreshold" "$TC/.clang-tidy" && grep -q "value: '100'" "$TC/.clang-tidy" && grep -q 'readability-function-size' "$TC/.clang-tidy" && grep -q 'end_of_line = crlf' "$TC/.editorconfig" && grep -q 'indent_size = 4' "$TC/.editorconfig" && ! grep -q '^charset' "$TC/.editorconfig" && grep -q 'LineThreshold: 100' "$CPP" && echo 1 || echo 0)"

# 再発防止 (v2.41.0): install.sh を実際に実行する (ドライランでも --skills-only でもない) テストは、--scripts-dir を、必ず、渡す。
# 渡さないと、ホームの ~/.claude/scripts/ を、テストが、実際に上書きしてしまう (2026-11-03 に起きた。バックアップ .~1~ が残った)。
bad_install="$(grep -n 'install\.sh"\? ' "$ROOT"/tests/*.sh | grep -v 'dry-run' | grep -v -- '--skills-only' | grep -v -- '--scripts-dir' | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' | grep -v 'ok "' )"
ok "no test runs install.sh for real (not dry-run, not --skills-only) without --scripts-dir (it would overwrite the real ~/.claude/scripts)" "$([ -z "$bad_install" ] && echo 1 || { echo "$bad_install" >&2; echo 0; })"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
