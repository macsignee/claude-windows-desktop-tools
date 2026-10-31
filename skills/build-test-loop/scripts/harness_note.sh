#!/usr/bin/env bash
# harness_note.sh - 結果の自己記述 (どの実行の結果か) と、Skill とウォッチャーの版の不一致を、出力の末尾に出す。
#
# Usage: harness_note.sh <solution_dir>
# 読むもの: <solution_dir>/.claude-logs/run_id.txt (ウォッチャーが、結果のマーカーを書く直前に書く。1 行目は run=<実行 ID>。
#   v2.29.0 以降は、watcher= / kind= / input= / finished= の行が続く。古いウォッチャーは、1 行目だけ) と、
#   このスクリプトの 1 つ上のフォルダの VERSION (install.sh が、配布のときに置く。Skill の版)。
# 出力 (終了コードは、常に 0。ビルドとテストの結果には、影響しない。不一致は、警告 (NOTE) だけで、実行を止めない):
#   RESULT_INFO: kind=test input=<フォルダ名> finished=<時刻> watcher=<版>        (結果に、自己記述があるとき)
#   NOTE: 版の不一致: Skill=<版> / ウォッチャー=<版> (...)                          (両方の版が分かり、違うとき)
#   NOTE: ウォッチャーが古い (版の表示なし。v2.29.0 より前) (...)                  (run_id.txt に watcher= がないとき)
#   NOTE: ウォッチャーの版が分からない (...) / NOTE: Skill の版が分からない (...)   (どちらかが unknown / VERSION なし)
# 何も出さない場合: run_id.txt がない (結果が出なかった・さらに古いウォッチャー) / フォルダがない。
DIR="${1:-}"
[ -n "$DIR" ] && [ -f "$DIR/.claude-logs/run_id.txt" ] || exit 0
F="$DIR/.claude-logs/run_id.txt"

field() { # $1=キー。BOM と CR を除いて、最初の一致の値を返す
    sed 's/^\xEF\xBB\xBF//; s/\r$//' "$F" | sed -n "s/^$1=//p" | head -n 1
}

skill_ver=""
vf="$(dirname "${BASH_SOURCE[0]}")/../VERSION"
[ -f "$vf" ] && skill_ver="$(tr -d '\r\n' < "$vf" | head -c 32)"
watcher_ver="$(field watcher)"
kind="$(field kind)"; input="$(field input)"; finished="$(field finished)"

if [ -n "$watcher_ver" ]; then
    echo "RESULT_INFO: kind=${kind:-?} input=$(basename "${input//\\//}") finished=${finished:-?} watcher=$watcher_ver"
fi

fix="install.sh で Skill とホスト側を、最新に揃え、ウォッチャーを再起動する"
if [ -z "$watcher_ver" ]; then
    echo "NOTE: ウォッチャーが古い (版の表示なし。v2.29.0 より前)。$fix"
elif [ "$watcher_ver" = "unknown" ]; then
    echo "NOTE: ウォッチャーの版が分からない (配布先に VERSION がない)。$fix"
elif [ -z "$skill_ver" ]; then
    echo "NOTE: Skill の版が分からない (VERSION がない)。ウォッチャー=$watcher_ver。$fix"
elif [ "$skill_ver" != "$watcher_ver" ]; then
    echo "NOTE: 版の不一致: Skill=$skill_ver / ウォッチャー=$watcher_ver。$fix"
fi
exit 0
