#!/usr/bin/env bash
# install.sh - msbuild-common を、Windows から見えるフォルダへ、コピーする (バイトを変えない)。
#
# claude-windows-desktop-tools の host-tools (install.sh が /mnt/c/tools/claude-watcher/ へコピーする) と、同じ運用。
# コピー先は、git のリポジトリにしない (clone しない)。直すときは、この clone (~/src/msbuild-common) を直して、コミット・push し、
# このスクリプトで、配り直す。コピー先を、直接、編集しない。
#
# Usage: bash install.sh [--dest DIR] [--dry-run]     (実行権に頼らず、bash で実行する。host-tools の install.sh と同じ)
#
#   --dest DIR   コピー先 (既定: /mnt/c/tools/msbuild-common。Windows では C:\tools\msbuild-common = C:\Tools\msbuild-common。
#                Windows 側の環境変数 MSBUILD_COMMON_DIR が、この場所を指す)
#   --dry-run    何もコピーせず、変わるファイルだけを表示する
#
# 注意:
#   - コピーするのは、実行に必要な 8 ファイルだけ (README.md・LICENSE.md・install.sh・.git は、コピーしない)。
#   - コピー後に、cmp で、コピー先が同一であることを確認する。
#   - コピー先にだけある古いファイルは、消さない。必要なら手で削除する。
#   - コピー先に .git があれば、警告する (Windows 側に、clone を置かない運用のため)。
#
# 終了コード: 0 成功 / 1 コピー後の確認に失敗 / 2 引数・必要なファイルの問題 (何もコピーしない)
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/mnt/c/tools/msbuild-common"
DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dest) DEST="${2:?--dest に DIR が必要}"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n "2,19p" "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "不明なオプション: $1 (--help を参照)"; exit 2 ;;
    esac
done

FILES="Common.props Dotnet.props Common.targets VERSION templates/Directory.Build.props templates/Directory.Build.targets templates/reference/Directory.Build.props templates/reference/Directory.Build.targets"
missing=""
for f in $FILES; do [ -f "$REPO/$f" ] || missing="$missing $f"; done
[ -z "$missing" ] || { echo "ERROR: 必要なファイルがない:$missing" >&2; exit 2; }

ver="$(tr -d '[:space:]' < "$REPO/VERSION")"
old=""; [ -f "$DEST/VERSION" ] && old="$(tr -d '[:space:]' < "$DEST/VERSION")"
echo "== msbuild-common $ver -> $DEST (いまの版: ${old:-なし})"
if [ -d "$DEST/.git" ]; then
    echo "!!  $DEST に .git がある。この運用では、コピー先を git のリポジトリにしない (.git を消すか、別のフォルダにすること)。コピーは続ける"
fi
changed=0
for f in $FILES; do
    if [ ! -f "$DEST/$f" ]; then
        echo "   + $f"; changed=$((changed+1))
    elif ! cmp -s "$REPO/$f" "$DEST/$f"; then
        echo "   ~ $f"; changed=$((changed+1))
    fi
done
if [ "$changed" = 0 ]; then
    echo "   変更なし (すでに、同じ内容)"
    exit 0
fi
if [ "$DRY" = 1 ]; then
    echo "   (dry-run: 何もコピーしていない)"
    exit 0
fi
fail=0
for f in $FILES; do
    mkdir -p "$DEST/$(dirname "$f")" || { echo "NG  フォルダを作れない: $DEST/$(dirname "$f")"; exit 2; }
    cp "$REPO/$f" "$DEST/$f" || { echo "NG  コピーできない: $DEST/$f"; fail=1; continue; }
    cmp -s "$REPO/$f" "$DEST/$f" || { echo "NG  内容が一致しない: $DEST/$f"; fail=1; }
done
[ "$fail" = 0 ] || exit 1
echo "   OK  $changed ファイルをコピーした (版 ${old:-なし} -> $ver)"
w="$(wslpath -w "$DEST" 2>/dev/null)"
[ -n "$w" ] && echo "   Windows 側のパス: $w (環境変数 MSBUILD_COMMON_DIR は、これを指す)"
echo "次: 利用側 (claude-windows-desktop-tools) で、bash tools/sync-msbuild-common.sh <この clone> を実行して、同梱コピーに取り込む"
exit 0
