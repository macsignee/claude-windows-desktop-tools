#!/usr/bin/env bash
# new_solution_common_test.sh - /new-solution が、薄い Directory.Build.props / .targets と build\common\ (msbuild-common) を作ることの検証 (v2.65.0)。
# Windows も .NET も不要 (疑似フォルダ)。実機のビルドは、別に確かめる (TEST-PLAN 2-40)。
# Usage: tests/new_solution_common_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
M="$ROOT/msbuild-common"
V="$ROOT/skills/new-solution/msbuild-common"
T="${TMPDIR:-/tmp}/nscommon_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
same() { cmp -s "$1" "$2"; }

ok "配布用のコピー (skills/new-solution/msbuild-common) が、正本 (msbuild-common) と同じ (違うときは、cp で同期する)" "$(r=1
for f in Common.props Dotnet.props Common.targets VERSION templates/Directory.Build.props templates/Directory.Build.targets; do same "$M/$f" "$V/$f" || r=0; done; echo $r)"

n=0
for spec in "wpf|--layers logic --tests mstest --tfm net10.0" "winforms|--layers logic --tests mstest --tfm net10.0" "csharp-dll|--layers none --tests mstest --tfm net10.0" \
            "mfc|--layers logic --tests gtest" "mfc-dialog|--layers logic --tests gtest" "win32|--layers logic --tests gtest" "console|--layers logic --tests gtest" "dll|--layers none --tests gtest" "lib|--layers logic --tests gtest" "mfc-mdi|--layers logic --tests gtest"; do
    type="${spec%%|*}"; args="${spec#*|}"; n=$((n+1))
    D="$T/S$n"
    python3 "$NS" "$D" --type "$type" $args >"$T/out$n.txt" 2>&1; rc=$?
    ok "$type: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
    ok "$type: 薄い Directory.Build.props / .targets が、正本のテンプレートと同じ" "$(same "$D/Directory.Build.props" "$M/templates/Directory.Build.props" && same "$D/Directory.Build.targets" "$M/templates/Directory.Build.targets" && echo 1 || echo 0)"
    ok "$type: build/common/ の 4 ファイルが、正本と同じ" "$(r=1; for f in Common.props Dotnet.props Common.targets VERSION; do same "$M/$f" "$D/build/common/$f" || r=0; done; echo $r)"
    ok "$type: 承認の案 (出力) に、作るファイルが出る" "$(grep -qF '+ build/common/Common.props' "$T/out$n.txt" && grep -qF '+ Directory.Build.props' "$T/out$n.txt" && echo 1 || echo 0)"
    ok "$type: CLAUDE.md に、build\\common\\ はコピーで、手で編集しない、と書く" "$(grep -qF '## MSBuild の共通設定' "$D/CLAUDE.md" && grep -qF 'build\common\' "$D/CLAUDE.md" && echo 1 || echo 0)"
    case "$type" in
        wpf|winforms|csharp-dll) ok "$type: CLAUDE.md に、Dotnet.props の説明がある" "$(grep -qF 'Dotnet.props' "$D/CLAUDE.md" && echo 1 || echo 0)"
            ok "$type: 元の Directory.Build.props (Nullable を直接書くもの) は、もう作らない" "$(! grep -q '<Nullable>' "$D/Directory.Build.props" && echo 1 || echo 0)" ;;
        *) ok "$type: C++ の CLAUDE.md に、.NET の設定の説明は、ない" "$(! grep -qF 'Dotnet.props' "$D/CLAUDE.md" && echo 1 || echo 0)" ;;
    esac
done

# dry-run は、何も書かない
D="$T/dry"; python3 "$NS" "$D" --type wpf --layers logic --tests mstest --tfm net10.0 --dry-run >"$T/dry.txt" 2>&1
ok "dry-run: 案には出るが、何も書かない" "$(grep -qF '+ build/common/VERSION' "$T/dry.txt" && [ ! -e "$D" ] && echo 1 || echo 0)"

# すでに Directory.Build.props があるフォルダ: 上書きしない
D="$T/exist"; mkdir -p "$D"; printf '<Project><!-- mine --></Project>\n' > "$D/Directory.Build.props"
python3 "$NS" "$D" --type console --layers logic --tests gtest >"$T/exist.txt" 2>&1; rc=$?
ok "既存の Directory.Build.props: rc=0、上書きしない、NOTE を出す。.targets と build/common/ は作る" "$([ $rc = 0 ] && grep -q 'mine' "$D/Directory.Build.props" && grep -qF 'NOTE: すでに Directory.Build.props があるので' "$T/exist.txt" && same "$D/Directory.Build.targets" "$M/templates/Directory.Build.targets" && [ -f "$D/build/common/VERSION" ] && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
