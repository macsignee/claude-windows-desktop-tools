#!/usr/bin/env bash
# add_common_test.sh - /add-project の common (add_common.py。薄い Directory.Build.props / .targets と build\common\ の後付け) の検証 (v2.66.0)。
# Windows も .NET も不要 (疑似フォルダ)。実機のビルドは、別に確かめる (TEST-PLAN 2-41)。
# Usage: tests/add_common_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C.UTF-8
unset MSBUILD_COMMON_DIR   # 既定 (配布用のコピー = コピー型) を確かめる。参照型は、下で、指定する
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
AC="$ROOT/skills/add-project/scripts/add_common.py"
SS="$ROOT/skills/add-project/scripts/solution_state.py"
M="$ROOT/skills/new-solution/msbuild-common"   # 取り込んだ msbuild-common (正本は macsignee/msbuild-common)
T="${TMPDIR:-/tmp}/addcommon_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
same() { cmp -s "$1" "$2"; }
# 新規作成 → 共通ファイルだけを、取り除いて、「以前の」状態にする
mkold() { # $1=フォルダ $2...=new_solution.py の引数
    local d="$1"; shift
    python3 "$NS" "$d" "$@" >/dev/null 2>&1 || return 1
    rm -f "$d/Directory.Build.targets"
    rm -rf "$d/build"
}
OLD_PROPS_PY='import sys; sys.path.insert(0, sys.argv[1] + "/skills/csharp-test-first/scripts"); import add_project as AP; sys.stdout.buffer.write(b"\xef\xbb\xbf" + AP.DIRECTORY_BUILD_PROPS.replace("\n", "\r\n").encode())'

# ---------------------------------------------------------------- .NET: 以前の /new-solution が作った Directory.Build.props
D="$T/W"; mkold "$D" --type wpf --layers logic --tests mstest --tfm net10.0
python3 -c "$OLD_PROPS_PY" "$ROOT" > "$D/Directory.Build.props"
sed -i '/MSBuild の共通設定/,$d' "$D/CLAUDE.md"
out="$(python3 "$AC" "$D" --dry-run 2>&1)"; rc=$?
ok "以前の形: dry-run は rc=0、何も書かない" "$([ $rc = 0 ] && [ ! -e "$D/build" ] && [ ! -e "$D/Directory.Build.targets" ] && grep -q 'Nullable' "$D/Directory.Build.props" && echo 1 || echo 0)"
ok "以前の形: 案に、薄い版への書き換え (~)、足すファイル (+)、CLAUDE.md の節 (+) が出る" "$(grep -q '~ Directory.Build.props' <<<"$out" && grep -q '+ Directory.Build.targets' <<<"$out" && grep -q '+ build/common/Dotnet.props' <<<"$out" && grep -q '+ CLAUDE.md' <<<"$out" && echo 1 || echo 0)"
out="$(python3 "$AC" "$D" 2>&1)"; rc=$?
ok "以前の形: 実行は rc=0" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "以前の形: 薄い 2 ファイルと build/common/ の 4 ファイルが、正本と同じ" "$(r=1; same "$D/Directory.Build.props" "$M/templates/Directory.Build.props" || r=0; same "$D/Directory.Build.targets" "$M/templates/Directory.Build.targets" || r=0; for f in Common.props Dotnet.props Common.targets VERSION; do same "$M/$f" "$D/build/common/$f" || r=0; done; echo $r)"
ok "以前の形: CLAUDE.md に、節が足され (Dotnet.props の説明つき)、元の内容は、残る" "$(grep -qF '## MSBuild の共通設定' "$D/CLAUDE.md" && grep -qF 'Dotnet.props' "$D/CLAUDE.md" && grep -q '^# ' "$D/CLAUDE.md" && echo 1 || echo 0)"
python3 "$AC" "$D" >/dev/null 2>&1; rc=$?
ok "2 回目は、rc=3 (すべて最新。何も書かない)" "$([ $rc = 3 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 手で書いた Directory.Build.props は、書き換えない
D="$T/Mine"; mkold "$D" --type wpf --layers logic --tests mstest --tfm net10.0
printf '<Project><PropertyGroup><Foo>1</Foo></PropertyGroup></Project>\n' > "$D/Directory.Build.props"
cp "$D/Directory.Build.props" "$T/mine.bak"
out="$(python3 "$AC" "$D" 2>&1)"; rc=$?
ok "手で書いた Directory.Build.props: rc=2、何も書かない (.targets も build/ も作らない)、Import の行を示す" "$([ $rc = 2 ] && same "$D/Directory.Build.props" "$T/mine.bak" && [ ! -e "$D/build" ] && [ ! -e "$D/Directory.Build.targets" ] && grep -qF 'build\common\Common.props' <<<"$out" && echo 1 || echo 0)"
# 手で、Import を足したもの: そのまま (=)
printf '<Project><Import Project="$(MSBuildThisFileDirectory)build\\common\\Common.props" /></Project>\n' > "$D/Directory.Build.props"
out="$(python3 "$AC" "$D" --dry-run 2>&1)"; rc=$?
ok "手で Import を足したもの: そのまま (=)、止まらない" "$([ $rc = 0 ] && grep -q '= Directory.Build.props: すでに、build' <<<"$out" && echo 1 || echo 0)"

# ---------------------------------------------------------------- build/common/ の版
D="$T/Ver"; mkold "$D" --type wpf --layers logic --tests mstest --tfm net10.0
mkdir -p "$D/build/common"; for f in Common.props Dotnet.props Common.targets; do cp "$M/$f" "$D/build/common/$f"; done
printf '0.0.9\n' > "$D/build/common/VERSION"
python3 -c "$OLD_PROPS_PY" "$ROOT" > "$D/Directory.Build.props"
out="$(python3 "$AC" "$D" 2>&1)"; rc=$?
ok "古い版 (0.0.9): 差し替える (~)。VERSION が、新しい版になる" "$([ $rc = 0 ] && grep -q '~ build/common/VERSION' <<<"$out" && same "$D/build/common/VERSION" "$M/VERSION" && echo 1 || echo 0)"
printf '99.0.0\n' > "$D/build/common/VERSION"
out="$(python3 "$AC" "$D" 2>&1)"; rc=$?
ok "配る版より新しい (99.0.0): rc=2 で、止まる" "$([ $rc = 2 ] && grep -q 'より新しい' <<<"$out" && [ "$(tr -d '\r\n' < "$D/build/common/VERSION")" = 99.0.0 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- C++
D="$T/Cpp"; mkold "$D" --type console --layers logic --tests gtest
sed -i '/MSBuild の共通設定/,$d' "$D/CLAUDE.md"
python3 "$AC" "$D" >/dev/null 2>&1; rc=$?
ok "C++: rc=0。薄いファイルと build/common/ が、正本と同じ" "$([ $rc = 0 ] && same "$D/Directory.Build.props" "$M/templates/Directory.Build.props" && same "$D/build/common/Common.targets" "$M/Common.targets" && echo 1 || echo 0)"
ok "C++: CLAUDE.md の節に、Dotnet.props の説明は、ない" "$(grep -qF '## MSBuild の共通設定' "$D/CLAUDE.md" && ! grep -qF 'Dotnet.props' "$D/CLAUDE.md" && echo 1 || echo 0)"

# ---------------------------------------------------------------- CLAUDE.md がない
D="$T/NoCl"; mkold "$D" --type console --layers logic --tests gtest
rm -f "$D/CLAUDE.md"
python3 "$AC" "$D" >/dev/null 2>&1
ok "CLAUDE.md がなければ、作らない" "$([ ! -e "$D/CLAUDE.md" ] && [ -f "$D/build/common/VERSION" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- solution_state の ADDABLE
D="$T/St"; mkold "$D" --type wpf --layers logic --tests mstest --tfm net10.0
ok "solution_state: 共通ファイルがないと、ADDABLE に common が出る" "$(python3 "$SS" "$D" | grep -q '^ADDABLE: common | ' && echo 1 || echo 0)"
python3 "$AC" "$D" >/dev/null 2>&1
ok "solution_state: 足したあとは、ADDABLE に common が出ない" "$(python3 "$SS" "$D" | grep -q '^ADDABLE: common | ' && echo 0 || echo 1)"
D="$T/St2"; python3 "$NS" "$D" --type wpf --layers logic --tests mstest --tfm net10.0 >/dev/null 2>&1
ok "solution_state: /new-solution が作ったばかりのものには、common が出ない" "$(python3 "$SS" "$D" | grep -q '^ADDABLE: common | ' && echo 0 || echo 1)"

# ---------------------------------------------------------------- 参照型 (外の正本)
D="$T/Ref"; mkold "$D" --type wpf --layers logic --tests mstest --tfm net10.0
python3 -c "$OLD_PROPS_PY" "$ROOT" > "$D/Directory.Build.props"
out="$(MSBUILD_COMMON_DIR="$M" python3 "$AC" "$D" 2>&1)"; rc=$?
ok "参照型 (環境変数): rc=0。参照型の薄いファイルだけ。build/ は作らない" "$([ $rc = 0 ] && same "$D/Directory.Build.props" "$M/templates/reference/Directory.Build.props" && same "$D/Directory.Build.targets" "$M/templates/reference/Directory.Build.targets" && [ ! -e "$D/build" ] && grep -qF '決めた元: 環境変数 MSBUILD_COMMON_DIR' <<<"$out" && grep -qF 'NOTE: 参照型。' <<<"$out" && echo 1 || echo 0)"
ok "参照型: CLAUDE.md に、正本の行と、節が足される (一度だけ)" "$(grep -qF -- "- MSBuild 共通: $M" "$D/CLAUDE.md" && [ "$(grep -cF '## MSBuild の共通設定' "$D/CLAUDE.md")" = 1 ] && echo 1 || echo 0)"
python3 "$AC" "$D" >/dev/null 2>&1; rc=$?
ok "参照型の 2 回目 (環境変数なし。CLAUDE.md の行で正本が決まる): rc=3 (最新。何も書かない)" "$([ $rc = 3 ] && echo 1 || echo 0)"
out="$(MSBUILD_COMMON_DIR="$T/nonexist" python3 "$AC" "$D" --dry-run 2>&1)"; rc=$?
ok "CLAUDE.md の行が、環境変数より優先される (環境変数が、存在しないフォルダでも、止まらない)" "$([ $rc = 3 ] && grep -qF '決めた元: CLAUDE.md' <<<"$out" && echo 1 || echo 0)"

# コピー型 → 参照型 の切り替え / auto は、すでにある型を保つ
D="$T/Sw"; mkold "$D" --type console --layers logic --tests gtest
python3 "$AC" "$D" >/dev/null 2>&1
out="$(MSBUILD_COMMON_DIR="$M" python3 "$AC" "$D" --dry-run 2>&1)"; rc=$?
ok "auto: すでにコピー型なら、環境変数があっても、コピー型のまま (最新で rc=3)" "$([ $rc = 3 ] && echo 1 || echo 0)"
out="$(MSBUILD_COMMON_DIR="$M" python3 "$AC" "$D" --common reference 2>&1)"; rc=$?
ok "--common reference: コピー型の薄いファイルを、参照型に書き換える (~)。build/common/ は、残して、触らない" "$([ $rc = 0 ] && grep -q '~ Directory.Build.props' <<<"$out" && same "$D/Directory.Build.props" "$M/templates/reference/Directory.Build.props" && [ -f "$D/build/common/VERSION" ] && grep -q 'build/common/: 参照型では使わない' <<<"$out" && grep -qF -- "- MSBuild 共通: $M" "$D/CLAUDE.md" && [ "$(grep -cF '## MSBuild の共通設定' "$D/CLAUDE.md")" = 1 ] && echo 1 || echo 0)"
out="$(python3 "$AC" "$D" --common copy 2>&1)"; rc=$?
ok "--common copy: 参照型を、コピー型に戻す。CLAUDE.md の節も戻る (正本の行は、なくなる)" "$([ $rc = 0 ] && same "$D/Directory.Build.props" "$M/templates/Directory.Build.props" && ! grep -qF -- '- MSBuild 共通:' "$D/CLAUDE.md" && [ "$(grep -cF '## MSBuild の共通設定' "$D/CLAUDE.md")" = 1 ] && echo 1 || echo 0)"

# 参照型を、場所なしで頼む / --common-dir
D="$T/RefNone"; mkold "$D" --type console --layers logic --tests gtest; rm -f "$D/Directory.Build.props"
out="$(python3 "$AC" "$D" --common reference 2>&1)"; rc=$?
ok "--common reference: 場所がなければ、rc=2 で、何も書かない" "$([ $rc = 2 ] && [ ! -e "$D/Directory.Build.props" ] && grep -qF 'MSBUILD_COMMON_DIR' <<<"$out" && echo 1 || echo 0)"
python3 "$AC" "$D" --common-dir "$M" >/dev/null 2>&1
ok "--common-dir: 参照型になる" "$(same "$D/Directory.Build.props" "$M/templates/reference/Directory.Build.props" && echo 1 || echo 0)"
# 手で書いた参照型 (印がある): そのまま
D="$T/RefMine"; mkold "$D" --type console --layers logic --tests gtest
printf '<Project><PropertyGroup><X>$(MSBUILD_COMMON_DIR)</X></PropertyGroup></Project>\n' > "$D/Directory.Build.props"
out="$(MSBUILD_COMMON_DIR="$M" python3 "$AC" "$D" --dry-run 2>&1)"; rc=$?
ok "手で書いた参照 (環境変数 MSBUILD_COMMON_DIR を使うもの): そのまま (=)、止まらない" "$([ $rc = 0 ] && grep -q '= Directory.Build.props: すでに、外の正本を参照している' <<<"$out" && echo 1 || echo 0)"

# ---------------------------------------------------------------- 引数
python3 "$AC" "$T/nonexist" >/dev/null 2>&1; rc=$?
ok "フォルダがなければ rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
mkdir -p "$T/Empty"; python3 "$AC" "$T/Empty" >/dev/null 2>&1; rc=$?
ok "ソリューションがなければ rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
