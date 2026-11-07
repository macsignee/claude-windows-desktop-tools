#!/usr/bin/env bash
# mfc_wizard_layout_test.sh - /new-solution --type mfc / mfc-mdi / mfc-dialog の生成物が、Visual Studio のウィザードの構成
# (補助ファイル、PCH、res\、.vcxproj の設定、フィルター) に合っていることを、疑似フォルダで検証する (Windows 不要)。v2.60.0。
#
# Usage: tests/mfc_wizard_layout_test.sh
# 終了コード: 0 すべて OK / 1 失敗あり
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$REPO/skills/new-solution/scripts/new_solution.py"
MFC_CHK="$REPO/skills/mfc-check/scripts/mfc_check.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mfc_wizard_layout_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fail=0
ok() { echo "OK  $1"; }
ng() { echo "NG  $1"; fail=1; }

for t in mfc mfc-mdi mfc-dialog; do
    n="W_${t//-/_}"
    D="$WORK/$n"; mkdir -p "$D"
    if ! python3 "$NEW" "$D" --type "$t" --layers none --tests none >"$WORK/$n.out" 2>&1; then
        ng "$t: 作成に失敗した"; cat "$WORK/$n.out"; continue
    fi
    out=$(python3 - "$D" "$n" "$t" <<'PYX'
import os, re, struct, sys
root, n, t = sys.argv[1:4]
p = os.path.join(root, n)
errs = []
def need(cond, msg):
    if not cond:
        errs.append(msg)
def read(rel, enc='utf-8-sig'):
    return open(os.path.join(p, *rel.split('/')), encoding=enc).read()

# 補助ファイル
for f in ('framework.h', 'targetver.h', 'pch.h', 'pch.cpp', 'Resource.h', n + '.rc'):
    need(os.path.isfile(os.path.join(p, f)), '補助ファイルがない: ' + f)
fw, pch = read('framework.h'), read('pch.h')
need('Microsoft.Windows.Common-Controls' in fw, 'Common Controls の指令が framework.h にない')
need('#include "framework.h"' in pch and 'Common-Controls' not in pch, 'pch.h は framework.h を読むだけにする')
need('#include "targetver.h"' in fw, 'framework.h が targetver.h を読んでいない')
need('#include "pch.h"' in read('pch.cpp'), 'pch.cpp が pch.h を読んでいない')

# .cpp は、すべて、先頭で pch.h を読む (PCH を Use するため)
for f in sorted(os.listdir(p)):
    if f.endswith('.cpp'):
        first = [l for l in read(f).splitlines() if l.strip() and not l.lstrip().startswith('//')][0]
        need(first.strip() == '#include "pch.h"', f + ': 先頭の行が #include "pch.h" でない')

# .vcxproj
v = read(n + '.vcxproj')
need('<Keyword>MFCProj</Keyword>' in v and 'Win32Proj' not in v, 'Keyword が MFCProj でない')
need(v.count('<PrecompiledHeader>Use</PrecompiledHeader>') == 2, 'PCH が Use (Debug・Release) でない')
need(re.search(r'ClCompile Include="pch.cpp">\s*<PrecompiledHeader>Create</PrecompiledHeader>', v) is not None, 'pch.cpp が Create でない')
need(v.count('<PrecompiledHeaderFile>pch.h</PrecompiledHeaderFile>') == 2, 'PrecompiledHeaderFile がない')
need(v.count('<Midl>') == 2, 'Midl がない')
need(v.count('<Culture>0x0411</Culture>') == 2, 'ResourceCompile の Culture がない')
need(v.count('$(IntDir);%(AdditionalIncludeDirectories)') == 2, 'ResourceCompile の AdditionalIncludeDirectories がない')
need(v.count('<LinkIncremental>') == 2, 'LinkIncremental がない')
need(v.count('<EnableSegmentHeap>true</EnableSegmentHeap>') == 2, 'EnableSegmentHeap がない')
need('<WholeProgramOptimization>true</WholeProgramOptimization>' in v and v.count('<WholeProgramOptimization>') == 1, 'Release だけに WholeProgramOptimization')
need('ImportGroup Label="ExtensionTargets"' in v, 'ExtensionTargets がない')
# ウォッチャー・ガイドラインに必要な設定は、残す
need('<OutDir>$(SolutionDir)$(Platform)' in v, 'OutDir がない')
need('stdcpp20' in v, 'stdcpp20 がない')
need(v.count('<EnableDpiAwareness>true</EnableDpiAwareness>') == 2, 'EnableDpiAwareness がない')
need(v.count('<UseOfMfc>Dynamic</UseOfMfc>') == 2, 'UseOfMfc がない')

# res\
need(os.path.isfile(os.path.join(p, 'res', n + '.rc2')), 'res\\ に rc2 がない')
def ico_ok(rel):
    f = os.path.join(p, *rel.split('/'))
    if not os.path.isfile(f):
        errs.append('アイコンがない: ' + rel); return
    b = open(f, 'rb').read()
    ok_head = b[:6] == b'\x00\x00\x01\x00\x01\x00'
    size, off = struct.unpack('<II', b[14:22]) if len(b) >= 22 else (0, 0)
    need(ok_head and off + size == len(b), 'アイコンの形式が正しくない: ' + rel)
ico_ok('res/' + n + '.ico')
doc = os.path.join(p, 'res', n + 'Doc.ico')
if t == 'mfc-dialog':
    need(not os.path.exists(doc), 'ダイアログベースに文書のアイコンは要らない')
else:
    ico_ok('res/' + n + 'Doc.ico')

# フィルター
fl = read(n + '.vcxproj.filters')
need(len(re.findall(r'<Filter Include=', fl)) == 3, 'フィルターが 3 つでない (ソース / ヘッダー / リソース)')
need(re.search(r'<Image Include="res\\' + n + r'\.ico">\s*<Filter>リソース ファイル</Filter>', fl) is not None, 'ico が Image / リソース ファイルでない')
need(re.search(r'<None Include="res\\' + n + r'\.rc2">\s*<Filter>リソース ファイル</Filter>', fl) is not None, 'rc2 が None / リソース ファイルでない')
need(re.search(r'<ClCompile Include="pch.cpp">\s*<Filter>ソース ファイル</Filter>', fl) is not None, 'pch.cpp がソース ファイルの下にない')
need(re.search(r'<ClInclude Include="framework.h">\s*<Filter>ヘッダー ファイル</Filter>', fl) is not None, 'framework.h がヘッダー ファイルの下にない')

# .rc: アイコンと rc2。.rc と .rc2 は BOM なしで書くので、ASCII だけ
rc = open(os.path.join(p, n + '.rc'), 'rb').read()
rc2 = open(os.path.join(p, 'res', n + '.rc2'), 'rb').read()
need(b'IDR_MAINFRAME ICON "res\\\\' + n.encode() + b'.ico"' in rc, '.rc がアイコンを読んでいない')
need(b'#include "res\\' + n.encode() + b'.rc2"' in rc, '.rc が rc2 を読んでいない')
need(all(c < 0x80 for c in rc) and all(c < 0x80 for c in rc2), '.rc / .rc2 に ASCII 以外がある')
need(not rc.startswith(b'\xef\xbb\xbf') and not rc2.startswith(b'\xef\xbb\xbf'), '.rc / .rc2 は BOM なし')
if t != 'mfc-dialog':
    need(b'IDR_SAMPLETYPE ICON' in rc, '.rc が文書のアイコンを読んでいない')
    need(b'IDR_SAMPLETYPE' in open(os.path.join(p, 'Resource.h'), 'rb').read(), 'Resource.h に IDR_SAMPLETYPE がない')
need(b'IDR_MAINFRAME' in open(os.path.join(p, 'Resource.h'), 'rb').read(), 'Resource.h に IDR_MAINFRAME がない')
print('\n'.join(errs))
PYX
)
    if [ -z "$out" ]; then ok "$t: ウォッチャーが探す場所と DPI の設定を残したまま、ウィザードの構成 (補助ファイル、PCH、res、.vcxproj、フィルター) になっている"; else ng "$t: $out"; fi
    if python3 "$MFC_CHK" "$D" --all 2>&1 | grep -q 'error 0 / warning 0'; then ok "$t: mfc-check が error 0 / warning 0"; else ng "$t: mfc-check が指摘を出した"; fi
done

# MDI: メインフレームは OnCreateClient を上書きして、Window メニューを推測させない (既定の実装は、IDR_MAINFRAME のメニューが
# File だけだと、起動時に winmdi.cpp の ASSERT で止まる。v2.60.1。実機で見つかった)
M="$WORK/W_mfc_mdi/W_mfc_mdi"
if grep -q 'OnCreateClient' "$M/MainFrame.h" && grep -q 'CreateClient(lpcs, nullptr)' "$M/MainFrame.cpp"; then
    ok "mfc-mdi: MainFrame が OnCreateClient を上書きし、Window メニューを推測しない"
else
    ng "mfc-mdi: MainFrame が OnCreateClient を上書きしていない (起動時に ASSERT で止まる)"
fi
if grep -q 'DECLARE_MESSAGE_MAP' "$M/SampleApp.h" && grep -q 'ON_COMMAND(ID_FILE_NEW, &CWinApp::OnFileNew)' "$M/SampleApp.cpp" && grep -q 'ID_FILE_NEW' "$M/W_mfc_mdi.rc"; then
    ok "mfc-mdi: メニューの File→New (ID_FILE_NEW) を、アプリが割り当てている (CWinApp は割り当てない。なければ、New が押せない)"
else
    ng "mfc-mdi: ID_FILE_NEW の割り当てがない (子ウィンドウのメニューの New が、押せなくなる)"
fi
if ! grep -q 'OnCreateClient' "$WORK/W_mfc/W_mfc/MainFrame.h"; then ok "mfc (SDI): OnCreateClient は上書きしない"; else ng "mfc (SDI): OnCreateClient を上書きしている"; fi

# 層・テスト付きでも、メインの構成は同じ (層の .vcxproj は、v2.60.0 では変えない)
D="$WORK/W_layers"; mkdir -p "$D"
if python3 "$NEW" "$D" --type mfc --layers logic,data --tests gtest --gtest vcpkg >"$WORK/layers.out" 2>&1; then
    if grep -q '<Keyword>MFCProj</Keyword>' "$D/W_layers/W_layers.vcxproj" && [ -f "$D/W_layers/pch.cpp" ]; then ok "層・テスト付き: メインはウィザードの構成"; else ng "層・テスト付き: メインがウィザードの構成でない"; fi
    if grep -q '<Keyword>Win32Proj</Keyword>' "$D/LogicLayer/LogicLayer.vcxproj" && grep -q '<Keyword>Win32Proj</Keyword>' "$D/LogicLayerTest/LogicLayerTest.vcxproj"; then ok "層・テスト付き: 層とテストの .vcxproj は、変えていない (Win32Proj)"; else ng "層・テスト付き: 層かテストの .vcxproj が変わった"; fi
    if python3 "$MFC_CHK" "$D" --all 2>&1 | grep -q 'error 0 / warning 0'; then ok "層・テスト付き: mfc-check が error 0 / warning 0"; else ng "層・テスト付き: mfc-check が指摘を出した"; fi
else
    ng "層・テスト付き: 作成に失敗した"; tail -3 "$WORK/layers.out"
fi

echo
if [ "$fail" -eq 0 ]; then echo "すべて OK"; else echo "失敗あり"; fi
exit "$fail"
