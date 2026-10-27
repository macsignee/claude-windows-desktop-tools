#!/usr/bin/env bash
# wpf_menu_note.sh - WPF のプロジェクトの XAML に、メニュー (Menu / MenuItem / ContextMenu) があるときだけ、
# UI テストを、どのデスクトップで実行するか (UI テストのプロジェクトの uitest.settings) を、知らせる (NOTE の 1〜2 行)。
#
# Usage: wpf_menu_note.sh <solution_dir>
# 何も出さない場合: WPF のプロジェクトがない / XAML にメニューがない / 直近の UI テストが、ユーザーのデスクトップ (desktop: Default) で動いた。
# uitest.settings に desktop=visible がない → 「desktop=visible を書く」(1 行)。ある → 「ユーザーのデスクトップで実行される。触らない」(1 行)。
# あるのに、直近の UI テストが、別のデスクトップで動いた記録 (ui-trace.txt) があるときは、2 行目で、原因 (ウォッチャーが古い / --separate の指定) と、対処を知らせる。
# 出力だけを行い、終了コードは、常に 0 (ビルドとテストの結果に、影響しない)。build_once.sh / build_test_once.sh が、終了時に呼ぶ。
#
# 理由 (実機で確認、2026-10-26): WPF のメニューのポップアップは、別のデスクトップでは、作られず、UIA のツリーに出ない
# (Expand() も、状態が Collapsed のまま)。ユーザーのデスクトップでは、Expand() で開く。WinForms / MFC のメニューは、別のデスクトップでも開く。
# どのデスクトップで実行するかの既定は、フレームワークごとの違いも含め、UI テストのプロジェクトの uitest.settings が持つ (add_ui_tests.py が、WPF には visible を書く)。
DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || exit 0

# 直近の UI テストが、ユーザーのデスクトップで動いていたら、知らせない (すでに、目で確かめるモード)
trace="$DIR/.claude-logs/ui-screenshots/ui-trace.txt"
last=""
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
    visible_files="$(find "$DIR" \( -name bin -o -name obj -o -name .git -o -name .claude-logs -o -name node_modules \) -prune -o -type f -name uitest.settings -print 2>/dev/null \
        | while IFS= read -r f; do sed 's/#.*$//' "$f" | grep -q -i -E '^[[:space:]]*desktop[[:space:]]*=[[:space:]]*(visible|default)[[:space:]]*$' && printf '%s\n' "$f"; done)"
    if [ -z "$visible_files" ]; then
        echo "NOTE: WPF の XAML に、メニューがある (${count} ファイル:${found}$([ "$count" -gt 3 ] && echo ' ...'))。WPF のメニューは、別のデスクトップでは、開かない。UI テストのプロジェクトの uitest.settings に、desktop=visible を書くこと (ユーザーのデスクトップで実行される。実行中は、PC に触らないよう、ユーザーに伝える)。1 回だけなら、uitest_once.sh --visible。"
    else
        echo "NOTE: WPF の XAML に、メニューがある (${count} ファイル:${found}$([ "$count" -gt 3 ] && echo ' ...'))。UI テストは、uitest.settings (desktop=visible) に従い、ユーザーのデスクトップで実行される。実行中は、PC に触らないよう、ユーザーに伝えること。"
        if [ -n "$last" ]; then
            echo "NOTE: 直近の UI テストは、別のデスクトップで動いた。ウォッチャーが古い (~/src/copy-host-tools.sh で再配置して、ウォッチャーを再起動) か、--separate / --invisible を指定した。メニューを含むテストは、uitest_once.sh --visible で実行する。"
        fi
    fi
fi
exit 0
