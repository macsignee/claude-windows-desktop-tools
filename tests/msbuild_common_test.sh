#!/usr/bin/env bash
# msbuild_common_test.sh - 取り込んだ msbuild-common (skills/new-solution/msbuild-common/。正本は macsignee/msbuild-common) の静的検査 (v2.64.0。v2.68.0 で、別リポジトリへ分離)。
# MSBuild は WSL に無いので、XML の正しさ・版の一致・既存の props との同一性・参照の形だけを見る。実機のビルドは、別に確かめる。
# Usage: tests/msbuild_common_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
M="$ROOT/skills/new-solution/msbuild-common"   # 外の正本 (macsignee/msbuild-common) の、取り込んだ版のコピー
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }

FILES="$M/Common.props $M/Dotnet.props $M/Common.targets $M/templates/Directory.Build.props $M/templates/Directory.Build.targets $M/templates/reference/Directory.Build.props $M/templates/reference/Directory.Build.targets"
ok "必要なファイルが、すべてある" "$(r=1; for f in $FILES $M/VERSION; do [ -f "$f" ] || r=0; done; echo $r)"
ok "XML として正しい (ルートが <Project>)" "$(python3 -I - $FILES <<'E'
import sys, xml.etree.ElementTree as ET
try:
    print(1 if all(ET.parse(f).getroot().tag == 'Project' for f in sys.argv[1:]) else 0)
except Exception:
    print(0)
E
)"
ok "UTF-8、LF、BOM なし" "$(r=1; for f in $FILES $M/VERSION; do grep -q $'\r' "$f" && r=0; [ "$(head -c3 "$f" | xxd -p)" = efbbbf ] && r=0; done; echo $r)"
ok "VERSION と Common.props の MsbuildCommonVersion が、同じ値" "$(v="$(tr -d '[:space:]' < "$M/VERSION")"; grep -q "<MsbuildCommonVersion>$v</MsbuildCommonVersion>" "$M/Common.props" && echo 1 || echo 0)"
ok "Dotnet.props の設定が、/new-solution が作る Directory.Build.props (add_project.py の DIRECTORY_BUILD_PROPS) と同じ (動きを変えない)" "$(python3 -I - "$ROOT" <<'E'
import sys, re, xml.etree.ElementTree as ET
root = sys.argv[1]
src = open(root + '/skills/csharp-test-first/scripts/add_project.py', encoding='utf-8').read()
m = re.search(r"DIRECTORY_BUILD_PROPS = '''(.*?)'''", src, re.S)
def props(xml):
    return {e.tag: (e.text or '').strip() for pg in ET.fromstring(xml).iter('PropertyGroup') for e in pg}
a = props(m.group(1))
b = props(open(root + '/skills/new-solution/msbuild-common/Dotnet.props', encoding='utf-8').read())
print(1 if a and a == b else 0)
E
)"
ok "Dotnet.props に TargetFramework を置かない (アプリと層で違う)" "$(! grep -q '<TargetFramework' "$M/Dotnet.props" && echo 1 || echo 0)"
ok "Common.props は、Dotnet.props を、.csproj のときだけ読む" "$(grep -q 'Dotnet.props" Condition="'"'"'$(MSBuildProjectExtension)'"'"' == '"'"'.csproj'"'"'"' "$M/Common.props" && echo 1 || echo 0)"
ok "ClaudeBuildInfo は、既定では何もしない (/p:ClaudeBuildInfo=true のときだけ)" "$(grep -q "Condition=\"'\$(ClaudeBuildInfo)' == 'true'\"" "$M/Common.targets" && grep -q 'AfterTargets="Build"' "$M/Common.targets" && echo 1 || echo 0)"
ok "薄いファイルは、親のファイルを読み (GetPathOfFileAbove)、そのあと build\\common\\ の共通ファイルを読む" "$(grep -q "GetPathOfFileAbove('Directory.Build.props'" "$M/templates/Directory.Build.props" && grep -q 'build\\common\\Common.props' "$M/templates/Directory.Build.props" && grep -q "GetPathOfFileAbove('Directory.Build.targets'" "$M/templates/Directory.Build.targets" && grep -q 'build\\common\\Common.targets' "$M/templates/Directory.Build.targets" && echo 1 || echo 0)"
ok "親のファイルが見つからないとき (空) は、Import しない (Condition)" "$(grep -q "'\$(_ParentBuildProps)' != ''" "$M/templates/Directory.Build.props" && grep -q "'\$(_ParentBuildTargets)' != ''" "$M/templates/Directory.Build.targets" && echo 1 || echo 0)"
ok "共通ファイルは、スキルのパスや CLAUDE.md に触れない (別のリポジトリへ、そのまま移せる)" "$(! grep -l -E '\.claude|CLAUDE\.md|skills/' $FILES >/dev/null 2>&1 && echo 1 || echo 0)"
ok "ClaudeBuildInfo の出力先は、\$(IntDir) が空のとき (SDK 形式の .csproj) \$(IntermediateOutputPath) にする" "$(grep -q "_ClaudeBuildInfoDir Condition=\"'\$(_ClaudeBuildInfoDir)' == ''\">\$(IntermediateOutputPath)" "$M/Common.targets" && echo 1 || echo 0)"
ok "参照型の薄いファイルは、環境変数 MSBUILD_COMMON_DIR を読み、未設定なら、印のついたパスで、Import が失敗する (黙って飛ばさない)。親のファイルも読む" "$(r=1; for f in props targets; do t="$M/templates/reference/Directory.Build.$f"; grep -q '\$(MSBUILD_COMMON_DIR)' "$t" || r=0; grep -q '__MSBUILD_COMMON_DIR_NOT_SET__' "$t" || r=0; grep -q 'GetPathOfFileAbove' "$t" || r=0; done; grep -q 'Import Project="\$(MsbuildCommonDir)\\Common.props" />' "$M/templates/reference/Directory.Build.props" || r=0; grep -q 'Import Project="\$(MsbuildCommonDir)\\Common.targets" />' "$M/templates/reference/Directory.Build.targets" || r=0; ! grep -q 'Import Project="[^"]*" Condition="[^"]*MsbuildCommonDir' "$M/templates/reference/Directory.Build.props" || r=0; echo $r)"

# ---------------------------------------------------------------- ClaudeCheckProject (v0.2.0。mfc-check / wpf-check / winforms-check の、プロジェクト設定だけで判定できる検査)
ok "Common.props: ClaudeCheck の既定は warning (off / warning / error)" "$(grep -q "<ClaudeCheck Condition=\"'\$(ClaudeCheck)' == ''\">warning</ClaudeCheck>" "$M/Common.props" && echo 1 || echo 0)"
ok "ClaudeCheckProject は、BeforeTargets=PrepareForBuild (コンパイルより前。Build の前だと、コンパイル・リンクの後になる) で、ClaudeCheck が off のときは何もしない" "$(grep -q '<Target Name="ClaudeCheckProject" BeforeTargets="PrepareForBuild" Condition="'"'"'\$(ClaudeCheck)'"'"' == '"'"'warning'"'"' Or '"'"'\$(ClaudeCheck)'"'"' == '"'"'error'"'"'"' "$M/Common.targets" && echo 1 || echo 0)"
ok "Warning / Error タスクは、Target の中だけにある (Target の外に置くと、MSBuild が読み込めない)" "$(python3 -I - "$M/Common.targets" <<'E'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
bad = [e.tag for ch in root if ch.tag != 'Target' for e in ch.iter() if e.tag in ('Warning', 'Error')]
inside = [e.tag for t in root.iter('Target') for e in t.iter() if e.tag in ('Warning', 'Error')]
print(1 if not bad and inside else 0)
E
)"
ok "検査のコード (LAY001 LAY003 DLL001 DLL002 DLL003) が、各 check と同じ意味で、揃っている" "$(r=1; for c in LAY001 LAY003 DLL001 DLL002 DLL003; do grep -q "Code=\"$c\"" "$M/Common.targets" || r=0; done
    for c in LAY001 LAY003; do grep -q "\"$c\"" "$ROOT/skills/wpf-check/scripts/wpf_check.py" || r=0; done
    for c in DLL001 DLL002 DLL003 LAY003; do grep -q "\"$c\"" "$ROOT/skills/mfc-check/scripts/mfc_check.py" || r=0; done
    for c in WFL001 WFL003; do grep -q "\"$c\"" "$ROOT/skills/winforms-check/scripts/winforms_check.py" || r=0; done; echo $r)"
ok "層の役割の判定 (名前 → 役割) が、solution_state.py の role_of_name と同じ (MSBuild の式を、Python に写して比べる)" "$(python3 -I - "$M/Common.targets" "$ROOT/skills/add-project/scripts" <<'E'
import re, sys
sys.path.insert(0, sys.argv[2])
import solution_state as S
t = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r"Regex\]::Replace\('\$\(MSBuildProjectName\)', '([^']+)', ' \$0 '\)", t)
if not m:
    print(0); raise SystemExit
pat = m.group(1)
words_in_ref = re.search(r"Regex\]::Replace\('%\(Identity\)', '([^']+)', ' \$0 '\)", t)
if not words_in_ref or words_in_ref.group(1) != pat:
    print(0); raise SystemExit
def msb(name):
    words = ' ' + re.sub(pat, lambda x: ' ' + x.group(0) + ' ', name).lower()
    low = name.lower()
    if 'viewmodel' in low: return 'viewmodel'
    if any(f' {w} ' in words for w in ('ui', 'view', 'views', 'dialog', 'dialogs')): return 'ui'
    if 'logic' in low: return 'logic'
    if 'data' in low: return 'data'
    return 'other'
names = ['LogicLayer', 'DataLayer', 'ViewModels', 'MainViewModel', 'UiLayer', 'UIHost', 'ReportView', 'Views', 'Dialogs', 'OrderDialog',
         'Build', 'Guide', 'ExtLayer', 'Core', 'AppData', 'ViewModelLogic', 'Quiet', 'Ui', 'UserInterface', 'DataView', 'Database',
         'BusinessLogic', 'my.view', 'Report_UI', 'MFCApp', 'cmWin32', 'Drops']
print(1 if all(S.role_of_name(n) == msb(n) for n in names) else 0)
E
)"
ok "層の向きの違反は、solution_state.py の ref_issues と同じ組 (data→logic/viewmodel/ui、logic→viewmodel/ui、viewmodel→ui)" "$(python3 -I - "$M/Common.targets" "$ROOT/skills/add-project/scripts" <<'E'
import re, sys
sys.path.insert(0, sys.argv[2])
import solution_state as S
t = open(sys.argv[1], encoding='utf-8').read()
pairs = set()
for m in re.finditer(r"<_CcViolation Include=\"@\(_CcRef\)\" Condition=\"'\$\(_CcRole\)' == '(\w+)' And (.*?)\" />", t):
    me, rest = m.group(1), m.group(2)
    for r in re.findall(r"'%\(Role\)' == '(\w+)'", rest):
        pairs.add((me, r))
want = {(a, b) for a in ('main', 'ui', 'viewmodel', 'logic', 'data') for b in ('main', 'ui', 'viewmodel', 'logic', 'data')
        if S.RANK[a] > S.RANK[b] and b != 'main'}
print(1 if pairs == want else 0)
E
)"

ok "メタデータで繰り返す Warning / Error (%(_CcViolation.…)) は、違反があるときだけ実行する (空でも 1 回、空の値で、実行されるため。CK1 で見つかった誤り)" "$(python3 -I - "$M/Common.targets" <<'E'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
tasks = [e for e in root.iter() if e.tag in ('Warning', 'Error') and '%(_CcViolation.' in (e.get('Text') or '')]
print(1 if tasks and all("'%(_CcViolation.Identity)' != ''" in (e.get('Condition') or '') for e in tasks) else 0)
E
)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
