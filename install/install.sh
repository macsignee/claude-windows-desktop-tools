#!/usr/bin/env bash
# install.sh - このリポジトリの成果物を、配布先へコピーする (バイトを変えない)。
#
#   skills/*      -> ~/.claude/skills/            (WSL の Claude Code が読むユーザー Skill)
#   host-tools/*  -> /mnt/c/tools/claude-watcher/ (Windows 側で動かす 3 ファイル + lib\*.ps1 (ウォッチャーの機能ごとの関数) + README。C++ と .NET の両方に使う)
#   rules/*.md    -> ~/.claude/rules/              (ユーザー共通のコーディング規約。C++ / C# / XAML を扱うときに、自動で読み込まれる)
#   templates/*   -> ~/.claude/templates/          (.editorconfig などのひな形)
#   scripts/*     -> ~/.claude/scripts/            (規約が参照する道具。convert_to_utf8_bom.py = Shift-JIS から UTF-8 (BOM 付き) への変換)
#
# Usage: install/install.sh [--skills-dir DIR] [--host-dir DIR] [--rules-dir DIR] [--templates-dir DIR] [--scripts-dir DIR]
#                           [--skills-only | --host-only | --rules-only] [--dry-run]
#
#   --skills-dir DIR  Skill のコピー先 (既定: $HOME/.claude/skills)
#   --host-dir DIR    ホスト側ツールのコピー先 (既定: /mnt/c/tools/claude-watcher)
#   --rules-dir DIR   規約のコピー先 (既定: $HOME/.claude/rules)
#   --templates-dir DIR  ひな形のコピー先 (既定: $HOME/.claude/templates)
#   --scripts-dir DIR    規約が参照する道具のコピー先 (既定: $HOME/.claude/scripts)
#   --skills-only     Skill だけをコピーする
#   --host-only       ホスト側ツールだけをコピーする
#   --rules-only      規約・ひな形・道具 (scripts/) だけをコピーする (既存のファイルは、上書きせず、番号付きのバックアップ (~) を残す)
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
HOST_DIR="/mnt/c/tools/claude-watcher"
RULES_DIR="$HOME/.claude/rules"
TEMPLATES_DIR="$HOME/.claude/templates"
SCRIPTS_DIR="$HOME/.claude/scripts"
DO_SKILLS=1
DO_HOST=1
DO_RULES=1
DRY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --skills-dir) SKILLS_DIR="${2:?--skills-dir に DIR が必要}"; shift 2 ;;
        --host-dir)   HOST_DIR="${2:?--host-dir に DIR が必要}"; shift 2 ;;
        --rules-dir)  RULES_DIR="${2:?--rules-dir に DIR が必要}"; shift 2 ;;
        --templates-dir) TEMPLATES_DIR="${2:?--templates-dir に DIR が必要}"; shift 2 ;;
        --scripts-dir) SCRIPTS_DIR="${2:?--scripts-dir に DIR が必要}"; shift 2 ;;
        --skills-only) DO_HOST=0; DO_RULES=0; shift ;;
        --host-only)   DO_SKILLS=0; DO_RULES=0; shift ;;
        --rules-only)  DO_SKILLS=0; DO_HOST=0; shift ;;
        --dry-run)     DRY=1; shift ;;
        -h|--help)     sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# 配布先に、このリポジトリの版 (VERSION) を置く (v2.29.0)。Skill のスクリプト (*_once.sh) が、ウォッチャーの版 (host-tools の VERSION を、
# ウォッチャーが、結果の run_id.txt に書く) と照合し、不一致なら、警告 (NOTE) を出す。リポジトリには、置かない (配布のときだけ作る)。
write_version() { # $1=書き込み先のファイル
    [ "$DRY" -eq 1 ] && return 0
    local v
    v="$(tr -d '\r\n' < "$REPO/VERSION" 2>/dev/null)"
    [ -n "$v" ] || { echo "!!  VERSION が読めないため、版のファイルを置かない: $1"; return 0; }
    printf '%s\n' "$v" > "$1" || { echo "NG  版のファイルを書けない: $1"; fail=1; }
}

if [ "$DO_SKILLS" -eq 1 ]; then
    echo "== Skill -> $SKILLS_DIR"
    for d in "$REPO"/skills/*/; do
        copy_tree "${d%/}" "$SKILLS_DIR/$(basename "$d")"
        write_version "$SKILLS_DIR/$(basename "$d")/VERSION"
    done
fi

# 規約とひな形は、ユーザーが手で直していることがある。上書きせず、番号付きのバックアップ (~1~ など) を残す。
# (先頭が "." のファイル (.editorconfig) も、コピーする)
copy_file_backup() { # $1=コピー元ファイル $2=コピー先ファイル
    if [ "$DRY" -eq 1 ]; then
        echo "   [dry-run] $1 -> $2"
        return 0
    fi
    mkdir -p "$(dirname "$2")" || { echo "NG  フォルダを作れない: $(dirname "$2")"; fail=1; return 1; }
    if [ -f "$2" ] && cmp -s "$1" "$2"; then
        echo "   same $2"
        return 0
    fi
    cp --backup=numbered "$1" "$2" || { echo "NG  コピーできない: $2"; fail=1; return 1; }
    cmp -s "$1" "$2" || { echo "NG  内容が一致しない: $2"; fail=1; return 1; }
    echo "   OK  $2"
}

if [ "$DO_RULES" -eq 1 ]; then
    echo "== 規約 -> $RULES_DIR"
    for f in "$REPO"/rules/*.md; do
        [ -f "$f" ] && copy_file_backup "$f" "$RULES_DIR/$(basename "$f")"
    done
    echo "== ひな形 -> $TEMPLATES_DIR"
    while IFS= read -r -d '' f; do
        copy_file_backup "$REPO/templates/$f" "$TEMPLATES_DIR/$f"
    done < <(cd "$REPO/templates" && find . -type f -print0 | sed -z 's|^\./||')
    echo "== 道具 -> $SCRIPTS_DIR"
    while IFS= read -r -d '' f; do
        copy_file_backup "$REPO/scripts/$f" "$SCRIPTS_DIR/$f"
    done < <(cd "$REPO/scripts" && find . -type f -not -name '*.pyc' -not -path '*/__pycache__/*' -print0 | sed -z 's|^\./||')
fi

if [ "$DO_HOST" -eq 1 ]; then
    echo "== ホスト側ツール -> $HOST_DIR"
    copy_tree "$REPO/host-tools" "$HOST_DIR"
    write_version "$HOST_DIR/VERSION"
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
