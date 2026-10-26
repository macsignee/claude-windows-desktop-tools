#!/usr/bin/env bash
# wpf_menu_note_test.sh - wpf_menu_note.sh (WPF のメニューがあるときだけ、ユーザーのデスクトップのウォッチャーを使う旨を、知らせる) を検証する。Windows 不要。
# Usage: tests/wpf_menu_note_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTE="$ROOT/skills/build-test-loop/scripts/wpf_menu_note.sh"
T="${TMPDIR:-/tmp}/wpfnote_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }

wpf_proj() {  # $1=folder $2=xaml の中身
    mkdir -p "$1/App/Views"
    printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><UseWPF>true</UseWPF></PropertyGroup></Project>\n' > "$1/App/App.csproj"
    printf '%s\n' "$2" > "$1/App/Views/MainWindow.xaml"
}

# 1. WPF + <Menu>: 知らせる (NOTE が 2 行。終了コード 0)
D="$T/a"; wpf_proj "$D" '<Window><DockPanel><Menu><MenuItem Header="File" /></Menu></DockPanel></Window>'
out="$(bash "$NOTE" "$D")"; rc=$?
ok "menu: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "menu: 2 NOTE lines mention run_watcher_visible.cmd and the file" "$([ "$(echo "$out" | grep -c '^NOTE:')" = 2 ] && echo "$out" | grep -q 'run_watcher_visible.cmd' && echo "$out" | grep -q 'MainWindow.xaml' && echo 1 || echo 0)"

# 2. WPF + MenuItem だけ / ContextMenu でも知らせる
D="$T/b"; wpf_proj "$D" '<Window><Button><Button.ContextMenu><ContextMenu><MenuItem Header="x"/></ContextMenu></Button.ContextMenu></Button></Window>'
ok "context menu: noted" "$(bash "$NOTE" "$D" | grep -q '^NOTE:' && echo 1 || echo 0)"

# 3. WPF + メニューなし: 何も出さない
D="$T/c"; wpf_proj "$D" '<Window><StackPanel><Button Content="MenuButton" /><TextBlock Text="Menu" /></StackPanel></Window>'
ok "no menu: silent" "$([ -z "$(bash "$NOTE" "$D")" ] && echo 1 || echo 0)"

# 4. WPF でない (UseWPF なし) プロジェクトの XAML は、対象外 (WinForms / MFC の、メニューは、別のデスクトップで開く)
D="$T/d"; mkdir -p "$D/App"; printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><UseWindowsForms>true</UseWindowsForms></PropertyGroup></Project>\n' > "$D/App/App.csproj"
printf '<Menu />\n' > "$D/App/X.xaml"
ok "not WPF: silent" "$([ -z "$(bash "$NOTE" "$D")" ] && echo 1 || echo 0)"

# 5. bin / obj の XAML は、無視する
D="$T/e"; wpf_proj "$D" '<Window />'; mkdir -p "$D/App/obj/Debug"; printf '<Menu />\n' > "$D/App/obj/Debug/Generated.xaml"
ok "obj xaml ignored: silent" "$([ -z "$(bash "$NOTE" "$D")" ] && echo 1 || echo 0)"

# 6. 直近の UI テストが、ユーザーのデスクトップ (desktop: Default) で動いていたら、知らせない。別のデスクトップなら、知らせる
D="$T/f"; wpf_proj "$D" '<Window><Menu /></Window>'; mkdir -p "$D/.claude-logs/ui-screenshots"
printf '12:00:00.000 === A: start (desktop: Default, slowmo: 800 ms)\n' > "$D/.claude-logs/ui-screenshots/ui-trace.txt"
ok "visible watcher trace: silent" "$([ -z "$(bash "$NOTE" "$D")" ] && echo 1 || echo 0)"
printf '12:00:00.000 === A: start (desktop: Default, slowmo: 0 ms)\n12:01:00.000 === B: start (desktop: ClaudeUiTest123, slowmo: 0 ms)\n' > "$D/.claude-logs/ui-screenshots/ui-trace.txt"
ok "latest run on a separate desktop: noted" "$(bash "$NOTE" "$D" | grep -q '^NOTE:' && echo 1 || echo 0)"

# 7. 引数なし / 存在しないフォルダ: 何も出さず、rc=0
ok "bad args: silent, rc=0" "$(out="$(bash "$NOTE" "$T/none")"; [ $? = 0 ] && [ -z "$out" ] && [ -z "$(bash "$NOTE")" ] && echo 1 || echo 0)"

# 8. build_once.sh / build_test_once.sh の終了時に、呼ばれる (疑似ウォッチャー。1 行目と終了コードは、変わらない)
D="$T/g"; wpf_proj "$D" '<Window><Menu /></Window>'
( while true; do
    if [ -f "$D/trigger_build.flag" ]; then rm -f "$D/trigger_build.flag"; printf SUCCESS > "$D/build_result.txt"; fi
    if [ -f "$D/trigger_test.flag" ]; then rm -f "$D/trigger_test.flag"; printf SUCCESS > "$D/build_result.txt"; printf PASSED > "$D/test_result.txt"; fi
    sleep 0.2
  done ) & W=$!
out="$(bash "$ROOT/skills/auto-build/scripts/build_once.sh" "$D" 20)"; rc=$?
ok "build_once: first line SUCCESS, rc=0, NOTE printed" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = SUCCESS ] && echo "$out" | grep -q '^NOTE:' && echo 1 || echo 0)"
out="$(bash "$ROOT/skills/build-test-loop/scripts/build_test_once.sh" "$D" 20)"; rc=$?
kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
ok "build_test_once: first line PASSED, rc=0, NOTE printed" "$([ $rc = 0 ] && [ "$(echo "$out" | head -n 1)" = PASSED ] && echo "$out" | grep -q '^NOTE:' && echo 1 || echo 0)"

echo "PASS: $pass FAIL: $fail"
[ "$fail" = 0 ]
