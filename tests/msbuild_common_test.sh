#!/usr/bin/env bash
# msbuild_common_test.sh - msbuild-common (Directory.Build.props / targets のたたき台) の静的検査 (v2.64.0)。
# MSBuild は WSL に無いので、XML の正しさ・版の一致・既存の props との同一性・参照の形だけを見る。実機のビルドは、別に確かめる。
# Usage: tests/msbuild_common_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
M="$ROOT/msbuild-common"
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }

FILES="$M/Common.props $M/Dotnet.props $M/Common.targets $M/templates/Directory.Build.props $M/templates/Directory.Build.targets"
ok "必要なファイルが、すべてある" "$(r=1; for f in $FILES $M/VERSION $M/README.md; do [ -f "$f" ] || r=0; done; echo $r)"
ok "XML として正しい (ルートが <Project>)" "$(python3 -I - $FILES <<'E'
import sys, xml.etree.ElementTree as ET
try:
    print(1 if all(ET.parse(f).getroot().tag == 'Project' for f in sys.argv[1:]) else 0)
except Exception:
    print(0)
E
)"
ok "UTF-8、LF、BOM なし" "$(r=1; for f in $FILES $M/VERSION $M/README.md; do grep -q $'\r' "$f" && r=0; [ "$(head -c3 "$f" | xxd -p)" = efbbbf ] && r=0; done; echo $r)"
ok "VERSION と Common.props の MsbuildCommonVersion が、同じ値" "$(v="$(tr -d '[:space:]' < "$M/VERSION")"; grep -q "<MsbuildCommonVersion>$v</MsbuildCommonVersion>" "$M/Common.props" && echo 1 || echo 0)"
ok "Dotnet.props の設定が、/new-solution が作る Directory.Build.props (add_project.py の DIRECTORY_BUILD_PROPS) と同じ (動きを変えない)" "$(python3 -I - "$ROOT" <<'E'
import sys, re, xml.etree.ElementTree as ET
root = sys.argv[1]
src = open(root + '/skills/csharp-test-first/scripts/add_project.py', encoding='utf-8').read()
m = re.search(r"DIRECTORY_BUILD_PROPS = '''(.*?)'''", src, re.S)
def props(xml):
    return {e.tag: (e.text or '').strip() for pg in ET.fromstring(xml).iter('PropertyGroup') for e in pg}
a = props(m.group(1))
b = props(open(root + '/msbuild-common/Dotnet.props', encoding='utf-8').read())
print(1 if a and a == b else 0)
E
)"
ok "Dotnet.props に TargetFramework を置かない (アプリと層で違う)" "$(! grep -q '<TargetFramework' "$M/Dotnet.props" && echo 1 || echo 0)"
ok "Common.props は、Dotnet.props を、.csproj のときだけ読む" "$(grep -q 'Dotnet.props" Condition="'"'"'$(MSBuildProjectExtension)'"'"' == '"'"'.csproj'"'"'"' "$M/Common.props" && echo 1 || echo 0)"
ok "ClaudeBuildInfo は、既定では何もしない (/p:ClaudeBuildInfo=true のときだけ)" "$(grep -q "Condition=\"'\$(ClaudeBuildInfo)' == 'true'\"" "$M/Common.targets" && grep -q 'AfterTargets="Build"' "$M/Common.targets" && echo 1 || echo 0)"
ok "薄いファイルは、親のファイルを読み (GetPathOfFileAbove)、そのあと build\\common\\ の共通ファイルを読む" "$(grep -q "GetPathOfFileAbove('Directory.Build.props'" "$M/templates/Directory.Build.props" && grep -q 'build\\common\\Common.props' "$M/templates/Directory.Build.props" && grep -q "GetPathOfFileAbove('Directory.Build.targets'" "$M/templates/Directory.Build.targets" && grep -q 'build\\common\\Common.targets' "$M/templates/Directory.Build.targets" && echo 1 || echo 0)"
ok "親のファイルが見つからないとき (空) は、Import しない (Condition)" "$(grep -q "'\$(_ParentBuildProps)' != ''" "$M/templates/Directory.Build.props" && grep -q "'\$(_ParentBuildTargets)' != ''" "$M/templates/Directory.Build.targets" && echo 1 || echo 0)"
ok "共通ファイルは、スキルのパスや CLAUDE.md に触れない (別のリポジトリへ、そのまま移せる)" "$(! grep -l -E '\.claude|CLAUDE\.md|skills/' $FILES >/dev/null 2>&1 && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
