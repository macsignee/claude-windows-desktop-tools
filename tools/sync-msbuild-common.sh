#!/usr/bin/env bash
# sync-msbuild-common.sh - 外の正本 (macsignee/msbuild-common の clone) から、skills/new-solution/msbuild-common/ (配布用のコピー) に、取り込む (v2.68.0)。
#
# Usage: tools/sync-msbuild-common.sh <msbuild-common の clone のフォルダ> [--dry-run]
#
#   正本の、必要な 8 ファイルだけを、コピーする (README.md などは、取り込まない)。何を変えたかを、一覧にする。
#   コミットは、しない。取り込んだあとは、tests/ を実行して、CHANGELOG.md に、取り込んだ版を書くこと。
#   `install.sh --skills-only` で、配布する。配布用のコピーは、環境変数 MSBUILD_COMMON_DIR も、CLAUDE.md の
#   「- MSBuild 共通:」の行もないときに、/new-solution と /add-project common が使う (コピー型)。
#
# 終了コード: 0 成功 (変更なしも 0) / 2 引数・正本の問題 (何もコピーしない)
set -u
SRC="${1:-}"
DRY=0
[ "${2:-}" = "--dry-run" ] && DRY=1
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="$REPO/skills/new-solution/msbuild-common"
FILES="Common.props Dotnet.props Common.targets VERSION templates/Directory.Build.props templates/Directory.Build.targets templates/reference/Directory.Build.props templates/reference/Directory.Build.targets"

[ -n "$SRC" ] || { echo "ERROR: 正本のフォルダ (macsignee/msbuild-common の clone) を指定すること" >&2; echo "Usage: $0 <フォルダ> [--dry-run]" >&2; exit 2; }
[ -d "$SRC" ] || { echo "ERROR: フォルダがない: $SRC" >&2; exit 2; }
missing=""
for f in $FILES; do [ -f "$SRC/$f" ] || missing="$missing $f"; done
[ -z "$missing" ] || { echo "ERROR: 正本に、必要なファイルがない:$missing" >&2; exit 2; }

old="$(tr -d '[:space:]' < "$DST/VERSION" 2>/dev/null)"
new="$(tr -d '[:space:]' < "$SRC/VERSION")"
echo "取り込み先 : $DST (いまの版: ${old:-なし})"
echo "正本       : $SRC (版: $new)"
changed=0
for f in $FILES; do
    if [ ! -f "$DST/$f" ]; then
        echo "  + $f"; changed=$((changed+1))
    elif ! cmp -s "$SRC/$f" "$DST/$f"; then
        echo "  ~ $f"; changed=$((changed+1))
    fi
done
if [ "$changed" = 0 ]; then
    echo "変更なし (すでに、同じ内容)"
    exit 0
fi
if [ "$DRY" = 1 ]; then
    echo "(dry-run: 何もコピーしていない)"
    exit 0
fi
for f in $FILES; do
    mkdir -p "$(dirname "$DST/$f")"
    cp "$SRC/$f" "$DST/$f"
done
echo "完了。$changed ファイルを取り込んだ (版 ${old:-なし} → $new)"
echo "次: tests/ を実行する → CHANGELOG.md に、取り込んだ版を書く → install.sh --skills-only で配布する"
