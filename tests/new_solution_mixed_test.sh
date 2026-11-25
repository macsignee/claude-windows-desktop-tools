#!/usr/bin/env bash
# new_solution_mixed_test.sh - /new-solution は、言語が混ざるソリューション (.NET + C++ の層) を作らない。
# 混ざる指定は、エラー (rc=2) で止まり、「/add-project で、もう片方の層を足す」と案内する。
# 例外: C++ のメインに、.NET の UI テストを足す (--ui-tests flaui) は、混在だが、作れる (UT18・H7)。
# Windows も .NET も不要 (疑似フォルダ)。 Usage: tests/new_solution_mixed_test.sh
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
T="${TMPDIR:-/tmp}/nsmixed_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
stops() {  # stops <説明> <フォルダ名> <引数...> : rc=2 で止まり、/add-project を案内する
  local label="$1" n="$2"; shift 2
  mkdir -p "$T/$n"
  local out rc; out="$(python3 "$NS" "$T/$n" "$@" 2>&1)"; rc=$?
  ok "$label -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
  ok "$label -> /add-project を案内する" "$(has "$out" '/add-project')"
  local pre="${out%%/add-project*}"
  ok "$label -> 案内が、文の先頭にある (mstest / gtest に変える話より前)" "$([[ "$pre" != *--* ]] && echo 1 || echo 0)"
}

# 新規作成で、混ざる指定
stops "WPF に --tests gtest"            MixA --type wpf --layers logic --tests gtest
stops "WPF に --layer-kind"             MixB --type wpf --layers logic --tests none --layer-kind dll
stops "WinForms に --tests gtest"       MixC --type winforms --layers logic --tests gtest
stops "C++ (MFC) に --tests mstest"     MixD --type mfc-dialog --layers logic --tests mstest

# すでにあるソリューションへの、テストの後付けで、混ざる指定
mkdir -p "$T/MixE"; python3 "$NS" "$T/MixE" --type wpf --layers logic --tests none >/dev/null 2>&1
out="$(python3 "$NS" "$T/MixE" --tests gtest 2>&1)"; rc=$?
ok ".NET のソリューションに --tests gtest (後付け) -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
ok ".NET のソリューションに --tests gtest (後付け) -> /add-project を案内する" "$(has "$out" '/add-project')"
mkdir -p "$T/MixF"; python3 "$NS" "$T/MixF" --type mfc-dialog --layers none --tests none >/dev/null 2>&1
out="$(python3 "$NS" "$T/MixF" --tests mstest 2>&1)"; rc=$?
ok "C++ のソリューションに --tests mstest (後付け) -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
ok "C++ のソリューションに --tests mstest (後付け) -> /add-project を案内する" "$(has "$out" '/add-project')"

# 例外: C++ のメインに .NET の UI テスト (混在だが、作れる)
mkdir -p "$T/MixG"
python3 "$NS" "$T/MixG" --type mfc-dialog --layers none --tests none --ui-tests flaui --dry-run >/dev/null 2>&1; rc=$?
ok "C++ のメイン + --ui-tests flaui は、止まらない (rc=0)" "$([ $rc = 0 ] && echo 1 || echo 0)"

# 文書: 正式な手順が、明記されている
has_f() { grep -qF -- "$2" "$1" && echo 1 || echo 0; }
ok "README: 混在は /add-project が正式な手順" "$(has_f "$ROOT/README.md" '混在のソリューションは、`/add-project` で作る')"
ok "USAGE: 混在は /add-project が正式な手順" "$(has_f "$ROOT/docs/USAGE.md" '混在のソリューションは、`/add-project` で作る')"
ok "add-project SKILL: 混在の節 (C++ と C# の間の参照は扱わない)" "$(has_f "$ROOT/skills/add-project/SKILL.md" '混在のソリューション')"

# v2.105.3: 実機 (TEST-PLAN 2-70、MX1〜MX6) で見つけた点の修正
AL="$ROOT/skills/cpp-test-first/scripts/add_layer.py"
SS="$ROOT/skills/add-project/scripts/solution_state.py"
# (3) 混在: 言語が違う組には、SUGGEST_REF を出さない (C++ と C# の間は、参照を作らない)
mkdir -p "$T/MixH"; python3 "$NS" "$T/MixH" --type wpf --layers logic --tests mstest >/dev/null 2>&1
python3 "$AL" "$T/MixH" NativeLayer --kind dll --tests gtest >/dev/null 2>&1
out="$(python3 "$SS" "$T/MixH" 2>&1)"
ok "混在: KIND は mixed" "$(has "$out" 'KIND: mixed')"
ok "混在: 言語が違う組 (WPF -> C++ の層) に、SUGGEST_REF を出さない" "$([ "$(grep -c '^SUGGEST_REF' <<<"$out")" = 0 ] && echo 1 || echo 0)"
# (1) new-solution の SKILL: 言語が混ざる指定は、質問で直さず、止めて /add-project を案内する
NSK="$ROOT/skills/new-solution/SKILL.md"
ok "new-solution SKILL: 言語が混ざる指定は、質問で直さず、/add-project を案内して止める" "$(has_f "$NSK" '言語が混ざる指定は、質問で直さず')"
# (2) add-project の SKILL: 混在でも、層の表に 1 行 (種類は C++ DLL)
ASK="$ROOT/skills/add-project/SKILL.md"
ok "add-project SKILL: 混在でも、層の表に 1 行足す (表の下の箇条書きにしない)" "$(has_f "$ASK" '混在でも、層の表に 1 行')"
# (4) 「扱わない」の書き方: できない、ではない。ひな形・自動の参照・検査がないだけで、P/Invoke は、自分で書く
for f in "$ROOT/README.md" "$ROOT/docs/USAGE.md" "$ASK"; do
  ok "$(basename "$f"): P/Invoke は、自分で書く (禁止ではない)" "$(has_f "$f" 'P/Invoke は、自分で書く')"
done

# v2.105.4: 再確認 (2-70 の MX1) で、v2.105.3 の文言だけでは、Claude が質問に進んだ。手順の最初に、スクリプトに検査させる
l0="$(grep -n '^0\. \*\*まず、引数を、スクリプトに検査させる' "$NSK" | head -1 | cut -d: -f1)"
l1="$(grep -n '^1\. \*\*引数を読み、省略した項目を質問する' "$NSK" | head -1 | cut -d: -f1)"
ok "new-solution SKILL: 手順 0 (引数を、まず、--dry-run でスクリプトに検査させる) が、手順 1 (質問) より前にある" "$([ -n "$l0" ] && [ -n "$l1" ] && [ "$l0" -lt "$l1" ] && echo 1 || echo 0)"
ok "new-solution SKILL: 手順 0 は、終了コード 2 の文を、そのまま伝えて止まる (質問で直さない)" "$(sed -n "${l0:-1},$((${l0:-1}+4))p" "$NSK" | grep -q '終了コード 2' && sed -n "${l0:-1},$((${l0:-1}+4))p" "$NSK" | grep -q 'そのまま' && echo 1 || echo 0)"
ok "new-solution SKILL: 「矛盾する組み合わせは、どちらかを変えてもらう」は、言語が混ざる指定を含まない (手順 0 へ)" "$(grep -n '矛盾する組み合わせ' "$NSK" | grep -q '言語が混ざる' && echo 1 || echo 0)"

# v2.105.5: 再々確認 (MX1c) で、Claude は、手順 0 でスクリプトを実行したが、文頭の「WPF は mstest」を使って、選択肢を出した。案内を先頭にし、選択肢を出さない
ok "new-solution SKILL 手順 0: 「mstest に変えますか」のような選択肢も出さない" "$(sed -n "${l0:-1}p" "$NSK" | grep -q '選択肢' && echo 1 || echo 0)"
ok "new-solution SKILL 手順 0: 出力の最初の 1 文を、そのまま伝えて終わる" "$(sed -n "${l0:-1}p" "$NSK" | grep -q '最初の 1 文' && echo 1 || echo 0)"

echo "new_solution_mixed_test: pass=$pass fail=$fail"
[ "$fail" = 0 ]
