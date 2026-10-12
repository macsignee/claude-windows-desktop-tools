#!/usr/bin/env bash
# install.sh - このリポジトリの成果物を、配布先へコピーする (バイトを変えない)。
#
#   skills/*      -> ~/.claude/skills/            (WSL の Claude Code が読むユーザー Skill)
#   host-tools/*  -> /mnt/c/tools/cpp-watcher/    (Windows 側で動かす 3 ファイル + README)
#
# Usage: install/install.sh [--skills-dir DIR] [--host-dir DIR] [--skills-only | --host-only] [--dry-run]
#
#   --skills-dir DIR  Skill のコピー先 (既定: $HOME/.claude/skills)
#   --host-dir DIR    ホスト側ツールのコピー先 (既定: /mnt/c/tools/cpp-watcher)
#   --skills-only     Skill だけをコピーする
#   --host-only       ホスト側ツールだけをコピーする
#   --dry-run         何もコピーせず、行う内容だけを表示する
#
# 注意:
#   - コピー前に tools/check-formats.sh で形式 (文字コード・改行・BOM) を検証し、違反があれば中止する。
#   - コピー後に、cmp でコピー先が同一であることを確認する。
#   - 配布先のファイルは、上書きされる。配布先を直接編集せず、このリポジトリを直して配り直す。
#   - 配布先にだけある古いファイル (リネーム前のもの) は、消さない。必要なら手で削除する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
HOST_DIR="/mnt/c/tools/cpp-watcher"
DO_SKILLS=1
DO_HOST=1
DRY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --skills-dir) SKILLS_DIR="${2:?--skills-dir に DIR が必要}"; shift 2 ;;
        --host-dir)   HOST_DIR="${2:?--host-dir に DIR が必要}"; shift 2 ;;
        --skills-only) DO_HOST=0; shift ;;
        --host-only)   DO_SKILLS=0; shift ;;
        --dry-run)     DRY=1; shift ;;
        -h|--help)     sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "不明なオプション: $1 (--help を参照)"; exit 2 ;;
    esac
done

echo "== リポジトリ : $REPO"
echo "   バージョン : $(cat "$REPO/VERSION" 2>/dev/null || echo unknown)"

echo "== 形式の検証"
bash "$REPO/tools/check-formats.sh" "$REPO" || { echo "形式の違反があるため、中止します。"; exit 1; }

fail=0

copy_tree() { # $1=コピー元ディレクトリ $2=コピー先ディレクトリ
    local src="$1" dst="$2"
    if [ "$DRY" -eq 1 ]; then
        echo "   [dry-run] $src -> $dst"
        return 0
    fi
    mkdir -p "$dst" || { echo "NG  フォルダを作れない: $dst"; fail=1; return 1; }
    # 先頭が "." のファイルやフォルダは、コピーしない (.claude など)
    (cd "$src" && find . -type f -not -path '*/.*' -print0) | while IFS= read -r -d '' f; do
        mkdir -p "$dst/$(dirname "$f")"
        cp "$src/$f" "$dst/$f"
    done
    # 同一性の確認 (バイト単位)
    (cd "$src" && find . -type f -not -path '*/.*' -print0) | while IFS= read -r -d '' f; do
        cmp -s "$src/$f" "$dst/$f" || { echo "NG  内容が一致しない: $dst/$f"; exit 1; }
    done || fail=1
    [ "$fail" -eq 0 ] && echo "   OK  $dst"
}

if [ "$DO_SKILLS" -eq 1 ]; then
    echo "== Skill -> $SKILLS_DIR"
    for d in "$REPO"/skills/*/; do
        copy_tree "${d%/}" "$SKILLS_DIR/$(basename "$d")"
    done
fi

if [ "$DO_HOST" -eq 1 ]; then
    echo "== ホスト側ツール -> $HOST_DIR"
    copy_tree "$REPO/host-tools" "$HOST_DIR"
    if command -v wslpath >/dev/null 2>&1 && [ "$DRY" -eq 0 ]; then
        echo "   Windows 側のパス: $(wslpath -w "$HOST_DIR" 2>/dev/null)"
    fi
fi

if [ "$fail" -ne 0 ]; then
    echo "失敗があります。上のメッセージを確認してください。"
    exit 1
fi
[ "$DRY" -eq 1 ] && echo "(dry-run: 何も変更していません)"
echo "完了。Skill を読み込ませるには、Claude Code のセッションを新しく起動してください。"
exit 0
