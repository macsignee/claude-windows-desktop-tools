#!/usr/bin/env bash
# wpf_menu_note.sh - WPF のプロジェクトの XAML に、メニュー (Menu / MenuItem / ContextMenu) があるときだけ、
# 「メニューの開閉を含む UI テストは、ユーザーのデスクトップ (run_watcher_visible.cmd) で、実行する」ことを、知らせる (NOTE の 2 行)。
#
# Usage: wpf_menu_note.sh <solution_dir>
# 何も出さない場合: WPF のプロジェクトがない / XAML にメニューがない / 直近の UI テストが、ユーザーのデスクトップ (desktop: Default) で動いた。
# 出力だけを行い、終了コードは、常に 0 (ビルドとテストの結果に、影響しない)。build_once.sh / build_test_once.sh が、終了時に呼ぶ。
#
# 理由 (実機で確認、2026-10-26): WPF のメニューのポップアップは、別のデスクトップ (ウォッチャーの既定) では、作られず、UIA のツリーに出ない
# (Expand() も、状態が Collapsed のまま)。ユーザーのデスクトップでは、Expand() で開く。WinForms / MFC のメニューは、別のデスクトップでも開く。
DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || exit 0

# 直近の UI テストが、ユーザーのデスクトップで動いていたら、知らせない (すでに、目で確かめるモード)
trace="$DIR/.claude-logs/ui-screenshots/ui-trace.txt"
if [ -f "$trace" ]; then
    last="$(grep -a 'start (desktop:' "$trace" 2>/dev/null | tail -n 1)"
    case "$last" in *"desktop: Default"*) exit 0 ;; esac
fi

found=""
count=0
while IFS= read -r proj; do
    pdir="$(dirname "$proj")"
    while IFS= read -r xaml; do
        if grep -q -E '<(Menu|MenuItem|ContextMenu)([[:space:]/>]|$)' "$xaml" 2>/dev/null; then
            count=$((count + 1))
            [ "$count" -le 3 ] && found="$found ${xaml#"$DIR"/}"
        fi
    done < <(find "$pdir" \( -name bin -o -name obj \) -prune -o -type f -name '*.xaml' -print 2>/dev/null)
done < <(find "$DIR" \( -name bin -o -name obj -o -name .git -o -name .claude-logs -o -name node_modules \) -prune -o -type f -name '*.csproj' -print 2>/dev/null \
         | while IFS= read -r p; do grep -q -i -E '<UseWPF>[[:space:]]*true' "$p" 2>/dev/null && printf '%s\n' "$p"; done)

if [ "$count" -gt 0 ]; then
    echo "NOTE: WPF の XAML に、メニューがある (${count} ファイル:${found}$([ "$count" -gt 3 ] && echo ' ...'))。"
    echo "NOTE: メニューの開閉を含む UI テストは、ウォッチャーを run_watcher_visible.cmd (ユーザーのデスクトップ) で起動して、実行すること。別のデスクトップ (既定) では、WPF のメニューのポップアップが開かない。別のデスクトップでは、ボタン・単体テストで確かめる。"
fi
exit 0
