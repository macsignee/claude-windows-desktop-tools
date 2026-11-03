#!/usr/bin/env bash
# new_solutions_test.sh - new_solutions.py (作業フォルダの下に、候補ごとのソリューションを、宣言ファイルから作る) を、疑似フォルダで検証する。
#
# Windows も .NET も git も不要。new_solution.py が、実際に、ファイルを生成する (WPF / WinForms / MFC / コンソール)。
# 検査: 一括の作成、不正な宣言では「何も作らない」、既存の候補に触らない、CLAUDE.md の節 (自動生成。改行コードを保つ)、
#       仕様書の取り込みと同期 (未編集は更新、編集済みは衝突、上書きしない)、対象の決め方 (resolve)。
# Usage: tests/new_solutions_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/new-solution/scripts/new_solutions.py"
T="${TMPDIR:-/tmp}/nss_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
hasnt() { grep -qF -- "$2" <<<"$1" && echo 0 || echo 1; }
isf() { [ -f "$1" ] && echo 1 || echo 0; }
isd() { [ -d "$1" ] && echo 1 || echo 0; }
eq() { [ "$1" = "$2" ] && echo 1 || echo 0; }

n=0
mkwork() {   # 作業フォルダ (docs の仕様書と、メモ付き) を作って、$W に入れる
    n=$((n+1)); W="$T/w$n/ToDo"; mkdir -p "$W/docs/specs" "$W/docs/ideas"
    cat > "$W/docs/ideas/todo.md" <<'EOF'
# todo メモ
EOF
    cat > "$W/docs/specs/todo.md" <<'EOF'
# ToDo 管理

- 元: docs/ideas/todo.md

## 具体例
| 入力 | 期待 |
|---|---|
| 追加 "A" | 一覧に A |

## 境界値と異常系
| ケース | 振る舞い |
|---|---|
| 空文字 | 追加しない |
EOF
}
GOOD='| 名前 | 種類 | 層 | テスト | UIテスト |
|---|---|---|---|---|
| TodoWpf | wpf | data,logic,viewmodel | mstest | none |
| TodoWin | winforms | data,logic | mstest | none |
| TodoMfc | mfc-dialog | logic | gtest | none |
| TodoPlain | console | none | none | none |'
mani() {    # mani <表> [<共通の行>]
    { echo "# 比較用ソリューション"; echo "- 仕様書: docs/specs/todo.md"; echo "- 名前空間: todo"; [ -n "${2:-}" ] && echo "$2"; echo; echo "$1"; } > "$W/solutions.md"
}
run() { out=$(python3 "$S" "$@" 2>&1); rc=$?; }
nothing_created() {   # 候補のフォルダが、1 つもない
    local c=0; for d in "$W"/*/; do case "$d" in */docs/) ;; *) c=$((c+1));; esac; done; [ "$c" = 0 ] && echo 1 || echo 0
}

# ---------------------------------------------------------------- dry-run
mkwork; mani "$GOOD"
run create "$W" --dry-run
ok "dry-run: rc=0" "$(eq $rc 0)"
ok "dry-run: 4 件が、新しく作る予定" "$(has "$out" "新しく作る 4 件")"
ok "dry-run: 何も作らない" "$(nothing_created)"
ok "dry-run: 仕様書の取り込みの予定が出る" "$(has "$out" "docs/specs/todo.md (仕様書の取り込み)")"

# ---------------------------------------------------------------- 作成
run create "$W"
ok "create: rc=0" "$(eq $rc 0)"
for c in TodoWpf TodoWin TodoMfc TodoPlain; do
    ok "$c: .slnx がある" "$(isf "$W/$c/$c.slnx")"
    ok "$c: 仕様書のコピー" "$(isf "$W/$c/docs/specs/todo.md")"
    ok "$c: 取り込みの記録 (.spec-sync.json)" "$(isf "$W/$c/docs/specs/.spec-sync.json")"
    ok "$c: CLAUDE.md に、比較の候補の節" "$(has "$(cat "$W/$c/CLAUDE.md")" "## 比較の候補")"
done
ok "WPF: メモのコピー (元:)" "$(isf "$W/TodoWpf/docs/ideas/todo.md")"
ok "WPF: テストケースの種" "$(isf "$W/TodoWpf/docs/specs/todo.cases.md")"
ok "C++ (gtest): LogicLayerTest がある" "$(isd "$W/TodoMfc/LogicLayerTest")"
ok "候補どうしは、独立 (WPF のフォルダに、WinForms のファイルがない)" "$(eq "$(ls "$W/TodoWpf" | grep -c MainForm)" 0)"
sec=$(cat "$W/TodoWin/CLAUDE.md")
ok "節: 自分の候補に『この候補』" "$(has "$sec" '`TodoWin` (winforms、この候補)')"
ok "節: 他の候補の名前と種類" "$([ "$(has "$sec" '`TodoWpf` (wpf)')" = 1 ] && [ "$(has "$sec" '`TodoMfc` (mfc-dialog)')" = 1 ] && echo 1 || echo 0)"
ok "節: 仕様書の正本と、同期の案内" "$([ "$(has "$sec" '../docs/specs/todo.md')" = 1 ] && [ "$(has "$sec" 'sync-spec')" = 1 ] && echo 1 || echo 0)"
ok "節: 他の候補を、読まない・書かない" "$(has "$sec" "他の候補のフォルダは、読まない・書かない")"
ok "次の手順: 候補ごとのウォッチャー" "$(has "$out" 'run_watcher.cmd')"
ok "次の手順: 候補が 2 つ以上のとき、run_watchers.cmd (まとめて起動) を案内する" "$(has "$out" 'run_watchers.cmd "')"
ok "次の手順: GoogleTest の仕上げは、gtest の候補だけ" "$([ "$(has "$out" 'GTEST_VCPKG: no-baseline')" = 1 ] && [ "$(echo "$out" | grep -c 'GTEST_VCPKG: no-baseline')" = 1 ] && echo 1 || echo 0)"
ok "既存の CLAUDE.md の内容 (# CLAUDE.md の見出し) が、残っている" "$(has "$sec" "# CLAUDE.md (TodoWin)")"

# ---------------------------------------------------------------- 再実行 (冪等)
h1=$(cat "$W"/Todo*/CLAUDE.md "$W"/Todo*/*.slnx | sha1sum)
run create "$W"
h2=$(cat "$W"/Todo*/CLAUDE.md "$W"/Todo*/*.slnx | sha1sum)
ok "再実行: rc=3 (新しく作るものがない)" "$(eq $rc 3)"
ok "再実行: 既存の候補は、何も変わらない" "$(eq "$h1" "$h2")"
ok "再実行: 『すでにある』と報告" "$(has "$out" "= TodoWpf (すでにある)")"

# ---------------------------------------------------------------- 行を足す
echo "$GOOD
| TodoLib | csharp-dll | logic | mstest | none |" > "$T/tbl"
mani "$(cat "$T/tbl")"
run create "$W"
ok "行の追加: rc=0。足した 1 件だけ作る" "$([ $rc = 0 ] && [ "$(has "$out" "+ TodoLib を作った")" = 1 ] && [ "$(has "$out" "+ TodoWpf")" = 0 ] && echo 1 || echo 0)"
ok "行の追加: TodoLib の .slnx" "$(isf "$W/TodoLib/TodoLib.slnx")"
ok "行の追加: 既存の候補の節に、TodoLib が入る" "$(has "$(cat "$W/TodoWin/CLAUDE.md")" '`TodoLib` (csharp-dll)')"
ok "行の追加: 節の更新を、報告する" "$(has "$out" "書いた・更新した")"

# ---------------------------------------------------------------- 不正な宣言: 何も作らない
bad() {   # bad <名前> <表> <期待する文言>
    mkwork; mani "$2"; run create "$W"
    ok "不正 ($1): rc=2" "$(eq $rc 2)"
    ok "不正 ($1): 文言「$3」" "$(has "$out" "$3")"
    ok "不正 ($1): 何も作らない" "$(nothing_created)"
}
bad "名前が重複" '| 名前 | 種類 | 層 | テスト |
|---|---|---|---|
| A1 | wpf | none | none |
| a1 | console | none | none |' "名前が重複している"
bad "名前が不正" '| 名前 | 種類 | 層 | テスト |
|---|---|---|---|
| 1Bad | wpf | none | none |
| a-b | console | none | none |' "名前が使えない"
bad "テストが未定" '| 名前 | 種類 | 層 | テスト |
|---|---|---|---|
| A1 | wpf | none | none |
| B1 | console | none | 未定 |' "テストが未定"
bad "テストが空欄" '| 名前 | 種類 | 層 | テスト |
|---|---|---|---|
| B1 | console | none |  |' "質問して、決める"
bad "種類が不正" '| 名前 | 種類 | 層 | テスト |
|---|---|---|---|
| B1 | java | none | none |' "種類が不正"
bad "必須の列がない" '| 名前 | 種類 | 層 |
|---|---|---|
| B1 | wpf | none |' "必須の列がない: テスト"
bad "知らない列" '| 名前 | 種類 | 層 | テスト | 色 |
|---|---|---|---|---|
| B1 | wpf | none | none | 赤 |' "知らない列がある: 色"
bad "テストの値が不正" '| 名前 | 種類 | 層 | テスト |
|---|---|---|---|
| B1 | wpf | none | junit |' "テストが不正"
bad "表がない" 'なにもない' "候補の表がない"

mkwork; mani "$GOOD" "- 仕様書: docs/specs/no_such.md"; sed -i '2d' "$W/solutions.md"; run create "$W"
ok "仕様書がない: rc=2 で、何も作らない" "$([ $rc = 2 ] && [ "$(has "$out" "仕様書がない")" = 1 ] && [ "$(nothing_created)" = 1 ] && echo 1 || echo 0)"

mkwork; rm -f "$W/solutions.md"; run create "$W"
ok "solutions.md がない: rc=3" "$(eq $rc 3)"

# new_solution.py の側で、不正になる組み合わせ (WinForms に viewmodel 層): 他の有効な候補も、作らない
mkwork; mani '| 名前 | 種類 | 層 | テスト |
|---|---|---|---|
| OkOne | console | none | none |
| BadWin | winforms | viewmodel | none |'
run create "$W"
ok "new_solution.py が拒否する組み合わせ: rc=2" "$(eq $rc 2)"
ok "new_solution.py が拒否: 候補名を示す" "$(has "$out" "BadWin")"
ok "new_solution.py が拒否: 有効な候補も、作らない" "$(nothing_created)"

# ---------------------------------------------------------------- 仕様書なしの宣言
mkwork; printf '%s\n%s\n' '| 名前 | 種類 | 層 | テスト |' '|---|---|---|---|' > "$W/solutions.md"; echo '| Solo | console | none | none |' >> "$W/solutions.md"
run create "$W"
ok "仕様書なし: 作れる" "$([ $rc = 0 ] && [ "$(isf "$W/Solo/Solo.slnx")" = 1 ] && echo 1 || echo 0)"
ok "仕様書なし: 取り込みの記録を作らない" "$(eq "$(isf "$W/Solo/docs/specs/.spec-sync.json")" 0)"
ok "仕様書なし: 節に『正本』の行がない" "$(hasnt "$(cat "$W/Solo/CLAUDE.md")" "仕様書の正本")"
run sync-spec "$W"
ok "仕様書なし: sync-spec は rc=2 (仕様書が決まっていない)" "$(eq $rc 2)"

# ---------------------------------------------------------------- 列の別名・追加の列・CRLF + BOM
mkwork; python3 - "$W" <<'PY'
import sys
w = sys.argv[1]
s = ("- 仕様書: `docs/specs/todo.md`\r\n\r\n| ソリューション名 | メインの種類 | 層 | テスト | UIテスト | 名前空間 | 備考 |\r\n|---|---|---|---|---|---|---|\r\n"
     "| `Alpha` | console | なし | none | - | alpha | 試作 |\r\n")
open(w + "/solutions.md", "wb").write(b"\xef\xbb\xbf" + s.encode("utf-8"))
PY
run create "$W"
ok "別名の列・バッククォート・CRLF + BOM・『なし』: 作れる" "$([ $rc = 0 ] && [ "$(isf "$W/Alpha/Alpha.slnx")" = 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- CLAUDE.md の改変: 改変した場所だけ。CRLF を保つ
mkwork; mani "$GOOD"; run create "$W" >/dev/null
python3 - "$W/TodoPlain/CLAUDE.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, "rb").read().decode("utf-8").replace("\r\n", "\n").replace("\n", "\r\n")
open(p, "wb").write(s.encode("utf-8"))
PY
echo "$GOOD
| TodoLib | csharp-dll | logic | mstest | none |" > "$T/tbl"; mani "$(cat "$T/tbl")"; run create "$W" >/dev/null
ok "CRLF の CLAUDE.md: 節の更新後も、LF だけの行が混ざらない" "$(python3 - "$W/TodoPlain/CLAUDE.md" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
print(1 if b.count(b"\n") == b.count(b"\r\n") and b"TodoLib" in b else 0)
PY
)"

# ---------------------------------------------------------------- sync-spec
mkwork; mani "$GOOD"; run create "$W" >/dev/null
run sync-spec "$W"
ok "sync (変更なし): rc=0 で、更新 0 件" "$([ $rc = 0 ] && [ "$(has "$out" "更新 0 件 / 衝突 0 件")" = 1 ] && echo 1 || echo 0)"

echo "- 追記 (正本で変更)" >> "$W/docs/specs/todo.md"
run sync-spec "$W" --dry-run
ok "sync dry-run: 更新の予定 (4 候補)、何も書かない" "$([ $rc = 0 ] && [ "$(echo "$out" | grep -c '~ ')" = 4 ] && [ "$(has "$(cat "$W/TodoWpf/docs/specs/todo.md")" "追記")" = 0 ] && echo 1 || echo 0)"
cases_before=$(cat "$W/TodoWpf/docs/specs/todo.cases.md")
run sync-spec "$W"
ok "sync: 未編集の候補は、正本に更新される (rc=0)" "$([ $rc = 0 ] && [ "$(has "$(cat "$W/TodoWpf/docs/specs/todo.md")" "追記")" = 1 ] && [ "$(has "$(cat "$W/TodoMfc/docs/specs/todo.md")" "追記")" = 1 ] && echo 1 || echo 0)"
ok "sync: テストケースの種 (cases.md) は、更新しない" "$(eq "$cases_before" "$(cat "$W/TodoWpf/docs/specs/todo.cases.md")")"
run sync-spec "$W"
ok "sync: 2 回目は、更新 0 件" "$(has "$out" "更新 0 件 / 衝突 0 件")"

# 候補側だけ編集 → そのまま (正本が変わっていない)
echo "- 候補 Wpf だけの追記" >> "$W/TodoWpf/docs/specs/todo.md"
run sync-spec "$W"
ok "sync: 候補側だけの編集は、そのまま (rc=0)" "$([ $rc = 0 ] && [ "$(has "$out" "候補側だけが変更されている")" = 1 ] && [ "$(has "$(cat "$W/TodoWpf/docs/specs/todo.md")" "Wpf だけ")" = 1 ] && echo 1 || echo 0)"

# 候補側も、正本も編集 → 衝突。上書きしない
echo "- 正本の 2 回目の追記" >> "$W/docs/specs/todo.md"
run sync-spec "$W"
ok "sync: 両方が変更 → 衝突 (rc=1)" "$([ $rc = 1 ] && [ "$(has "$out" "X TodoWpf: docs/specs/todo.md")" = 1 ] && echo 1 || echo 0)"
ok "sync: 衝突したコピーは、上書きしない" "$([ "$(has "$(cat "$W/TodoWpf/docs/specs/todo.md")" "Wpf だけ")" = 1 ] && [ "$(has "$(cat "$W/TodoWpf/docs/specs/todo.md")" "2 回目")" = 0 ] && echo 1 || echo 0)"
ok "sync: 衝突していない候補は、更新される" "$(has "$(cat "$W/TodoWin/docs/specs/todo.md")" "2 回目")"
ok "sync: 衝突の件数と、対処の案内" "$([ "$(has "$out" "衝突 1 件")" = 1 ] && [ "$(has "$out" "そのファイルを消して")" = 1 ] && echo 1 || echo 0)"

# 衝突の解消: 候補側のコピーを消す → 再コピー
rm "$W/TodoWpf/docs/specs/todo.md"
run sync-spec "$W"
ok "sync: コピーを消すと、再コピーされる (rc=0)" "$([ $rc = 0 ] && [ "$(has "$(cat "$W/TodoWpf/docs/specs/todo.md")" "2 回目")" = 1 ] && echo 1 || echo 0)"

# 記録がなく、正本と違う → 衝突
rm "$W/TodoWin/docs/specs/.spec-sync.json"; echo "手で変更" >> "$W/TodoWin/docs/specs/todo.md"
run sync-spec "$W"
ok "sync: 記録がなく、正本と違う → 衝突" "$([ $rc = 1 ] && [ "$(has "$out" "取り込みの記録がなく")" = 1 ] && echo 1 || echo 0)"

# 記録がなく、正本と同じ → 記録を作る
mkwork; mani "$GOOD"; run create "$W" >/dev/null; rm "$W/TodoPlain/docs/specs/.spec-sync.json"
run sync-spec "$W"
ok "sync: 記録がなく、正本と同じ → 記録を作り直す" "$([ $rc = 0 ] && [ "$(isf "$W/TodoPlain/docs/specs/.spec-sync.json")" = 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- resolve
mkwork; mani "$GOOD"; run create "$W" >/dev/null
run resolve "$W"
ok "resolve (候補が複数、名前なし): rc=2 と候補の一覧" "$([ $rc = 2 ] && [ "$(has "$out" "CANDIDATES: TodoWpf, TodoWin, TodoMfc, TodoPlain")" = 1 ] && echo 1 || echo 0)"
run resolve "$W" TodoWin
ok "resolve (名前): パスを返す" "$([ $rc = 0 ] && [ "$out" = "$W/TodoWin" ] && echo 1 || echo 0)"
run resolve "$W" todowin
ok "resolve: 名前の大文字小文字は、区別しない" "$([ $rc = 0 ] && [ "$out" = "$W/TodoWin" ] && echo 1 || echo 0)"
run resolve "$W" ToDo/TodoMfc
ok "resolve: ToDo/TodoMfc の形でも、最後の名前で選ぶ" "$([ $rc = 0 ] && [ "$out" = "$W/TodoMfc" ] && echo 1 || echo 0)"
run resolve "$W" NoSuch
ok "resolve: ない候補は rc=3 (作られている候補を示す)" "$([ $rc = 3 ] && [ "$(has "$out" "TodoWpf")" = 1 ] && echo 1 || echo 0)"
run resolve "$W/TodoWpf"
ok "resolve: カレントがソリューションなら、そのフォルダ (名前は要らない)" "$([ $rc = 0 ] && [ "$out" = "$W/TodoWpf" ] && echo 1 || echo 0)"
run resolve "$T"
ok "resolve: .sln も solutions.md もない → rc=3" "$(eq $rc 3)"
mkwork; printf '%s\n%s\n' '| 名前 | 種類 | 層 | テスト |' '|---|---|---|---|' > "$W/solutions.md"; echo '| One | console | none | none |' >> "$W/solutions.md"
run resolve "$W"
ok "resolve: 宣言はあるが、作られていない → rc=3" "$(eq $rc 3)"
run create "$W" >/dev/null; run resolve "$W"
ok "resolve: 候補が 1 つなら、名前なしで、それを返す" "$([ $rc = 0 ] && [ "$out" = "$W/One" ] && echo 1 || echo 0)"
mkwork; mani "$GOOD"; run create "$W" --dry-run >/dev/null; run resolve "$W"
ok "resolve: 作る前 (dry-run のあと) は、候補がない → rc=3" "$(eq $rc 3)"

# ---------------------------------------------------------------- Skill が、対象の決め方 (resolve) に、触れている
for sk in auto-build build-test-loop add-package cpp-test-first csharp-test-first ui-test-first add-feature; do
    ok "Skill $sk: 作業フォルダでの対象の決め方 (resolve)" "$(has "$(cat "$ROOT/skills/$sk/SKILL.md")" 'new_solutions.py resolve "$PWD"')"
done
ok "Skill add-feature: new_solution.py に \$PWD を渡さない (\$SLN)" "$(hasnt "$(cat "$ROOT/skills/add-feature/SKILL.md")" 'new_solution.py "$PWD"')"
NSK="$(cat "$ROOT/skills/new-solution/SKILL.md")"; NSS="$(cat "$ROOT/skills/new-solutions/SKILL.md")"
ok "Skill new-solution: 既定は 1 つのソリューション (質問なしで A)。作業フォルダの質問は、しない" "$([ "$(has "$NSK" "どちらのモードか")" = 0 ] && [ "$(has "$NSK" "## C. 作業フォルダ")" = 0 ] && [ "$(has "$NSK" "/new-solutions")" = 1 ] && echo 1 || echo 0)"
ok "Skill new-solutions: 作業フォルダ (disable-model-invocation、.slnx を作らない)" "$([ "$(has "$NSS" "name: new-solutions")" = 1 ] && [ "$(has "$NSS" "disable-model-invocation: true")" = 1 ] && [ "$(has "$NSS" ".slnx\` を作らない")" = 1 ] && echo 1 || echo 0)"
ok "Skill new-solutions / new-solution: 種類の質問は、2 段階 (選択肢は 4 つまで)" "$([ "$(has "$NSS" "種類の質問は、2 段階")" = 1 ] && [ "$(has "$NSK" "2 段階にする")" = 1 ] && echo 1 || echo 0)"
ok "Skill new-solutions: GoogleTest (vcpkg) の仕上げのコマンドを、自分の中に書く (/new-solution を読み込んでいなくても、分かる)" "$([ "$(has "$NSS" 'package_once.sh "$候補" --timeout 1800 "vcpkg baseline" "vcpkg install"')" = 1 ] && echo 1 || echo 0)"
ok "Skill new-solutions: DLL (dll / lib / csharp-dll) も選べる" "$([ "$(has "$NSS" '`dll` / `lib`')" = 1 ] && [ "$(has "$NSS" '`csharp-dll`')" = 1 ] && echo 1 || echo 0)"
mkwork; mani '| 名前 | 種類 | 層 | テスト |
|---|---|---|---|
| LibCpp | dll | none | gtest |
| LibCs | csharp-dll | none | mstest |
| LibSt | lib | logic | none |'; run create "$W"
ok "DLL の候補 (dll / csharp-dll / lib) を作れる: rc=0" "$(eq $rc 0)"
ok "create: run_watcher.cmd の場所を、出力に書く (配置先のパスは、固定で書かない)" "$([ "$(has "$out" "ホスト側ツール")" = 1 ] && [ "$(has "$out" "cpp-watcher")" = 0 ] && [ "$(has "$out" "claude-watcher")" = 0 ] && echo 1 || echo 0)"
ok "Skill new-solutions: 質問は、候補ごとにまとめる。選択肢は exe だけにしない、「その他」を出さない" "$([ "$(has "$NSS" "候補ごとに、まとめて聞く")" = 1 ] && [ "$(has "$NSS" "「その他」の選択肢は、出さない")" = 1 ] && echo 1 || echo 0)"
ok "DLL: LibCpp.slnx / LibCs.slnx / LibSt.slnx" "$([ "$(isf "$W/LibCpp/LibCpp.slnx")" = 1 ] && [ "$(isf "$W/LibCs/LibCs.slnx")" = 1 ] && [ "$(isf "$W/LibSt/LibSt.slnx")" = 1 ] && echo 1 || echo 0)"
ok "Skill update-from-ideas: 作業フォルダでは、構成案を出さない" "$(has "$(cat "$ROOT/skills/update-from-ideas/SKILL.md")" "構成案は、出さない")"

# ---------------------------------------------------------------- 補助
ok "Windows のパスへの変換 (/mnt/c/... → c:\\...)" "$(python3 -I - "$ROOT/skills/new-solution/scripts" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import new_solutions as N
a = N.to_windows_path('/mnt/c/workspace/macsignee/source/repos/ToDo/TodoWpf') == 'c:\\workspace\\macsignee\\source\\repos\\ToDo\\TodoWpf'
b = N.to_windows_path('/home/x/y') == '/home/x/y'
print(1 if a and b else 0)
PY
)"
run bogus "$W"
ok "不正なサブコマンド: rc=2" "$(eq $rc 2)"
run create "$T/no_such_dir"
ok "フォルダがない: rc=2" "$(eq $rc 2)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
