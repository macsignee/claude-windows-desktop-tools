#!/usr/bin/env bash
# ui_guideline_check_test.sh - skills/ui-design-review/scripts/ui_guideline_check.py (UI デザインガイドラインの静的検査) を、
# 疑似プロジェクト (WPF / WinForms / MFC) で検証する。Windows も .NET も不要。
# あわせて、参照文書 (references/UI-Design-Guidelines.md) と、検査の規則 ID の対応、Skill の記述、配布を確かめる。
# Usage: tests/ui_guideline_check_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$ROOT/skills/ui-design-review"
CK="$SK/scripts/ui_guideline_check.py"
REF="$SK/references/UI-Design-Guidelines.md"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
T="${TMPDIR:-/tmp}/uigchk_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
chk() { python3 -I "$CK" "$@"; }

# 1 件の指摘を確かめる: expect <名前> <コード> <説明>   (info も見えるよう --all)
expect() {
    out="$(chk "$T/$1" --all)"; rc=$?
    ok "$3 ($2)" "$([ $rc = 0 ] && [ "$(has "$out" " $2 ")" = 1 ] && echo 1 || echo 0)"
}
absent() {
    out="$(chk "$T/$1" --all)"; rc=$?
    ok "$3 (no $2)" "$([ $rc = 0 ] && [ "$(has "$out" " $2 ")" = 0 ] && echo 1 || echo 0)"
}
clean() {
    out="$(chk "$T/$1")"; rc=$?
    ok "$2 (error 0 / warning 0)" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 / warning 0')" = 1 ] && echo 1 || echo 0)"
}

# ---------------------------------------------------------------- 疑似プロジェクトの作り方
# WPF: wpf <名前> [nomanifest]   (標準入力: Window の中身)
wpf() {
    local d="$T/$1"; mkdir -p "$d"
    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <OutputType>WinExe</OutputType>\n    <UseWPF>true</UseWPF>\n  </PropertyGroup>\n</Project>\n' > "$d/App.csproj"
    if [ "${2:-}" != nomanifest ]; then
        printf '<assembly><application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings><dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware></windowsSettings></application></assembly>\n' > "$d/app.manifest"
    fi
    {
        echo '<Window x:Class="X.MainWindow" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">'
        echo '<StackPanel>'; cat; echo '</StackPanel>'; echo '</Window>'
    } > "$d/MainWindow.xaml"
}
# WinForms: wf <名前> [nodpi]   (標準入力: InitializeComponent の中身)
wf() {
    local d="$T/$1"; mkdir -p "$d"
    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <OutputType>WinExe</OutputType>\n    <UseWindowsForms>true</UseWindowsForms>\n' > "$d/App.csproj"
    [ "${2:-}" = nodpi ] || printf '    <ApplicationHighDpiMode>SystemAware</ApplicationHighDpiMode>\n' >> "$d/App.csproj"
    printf '  </PropertyGroup>\n</Project>\n' >> "$d/App.csproj"
    { echo 'namespace X;'; echo 'partial class MainForm'; echo '{'; echo '    private void InitializeComponent()'; echo '    {'; echo '        SuspendLayout();'; cat
      echo '        ResumeLayout(false);'; echo '    }'; echo '}'; } > "$d/MainForm.Designer.cs"
}
# MFC: mfc <名前>   (標準入力: .rc の中身。環境変数 MFC_PCH / MFC_CHARSET / MFC_CT / MFC_NODPI)
PRAGMA_OK="#pragma comment(linker,\"/manifestdependency:\\\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\\\"\")"
mfc() {
    local d="$T/$1"; mkdir -p "$d"
    printf '<Project>\n  <PropertyGroup>\n    <ConfigurationType>%s</ConfigurationType>\n    <CharacterSet>%s</CharacterSet>\n    <UseOfMfc>Dynamic</UseOfMfc>\n  </PropertyGroup>\n</Project>\n' "${MFC_CT:-Application}" "${MFC_CHARSET:-Unicode}" > "$d/App.vcxproj"
    printf '#pragma once\n#include <afxwin.h>\n%s\n' "${MFC_PCH-$PRAGMA_OK}" > "$d/pch.h"
    [ -n "${MFC_NODPI:-}" ] || printf '<assembly><application><windowsSettings><dpiAware>true</dpiAware></windowsSettings></application></assembly>\n' > "$d/app.manifest"
    cat > "$d/App.rc"
}
RC_OK='IDD_MAIN DIALOGEX 0, 0, 240, 100
CAPTION "Main"
BEGIN
    DEFPUSHBUTTON   "&Save",IDOK,129,79,50,14
    PUSHBUTTON      "&Cancel",IDCANCEL,183,79,50,14
    LTEXT           "&Name:",IDC_STATIC,7,7,40,8
END'

# ---------------------------------------------------------------- 引数と、対象がない場合
chk "$T/nonexistent" >/dev/null 2>&1; ok "bad directory: rc=2" "$([ $? = 2 ] && echo 1 || echo 0)"
mkdir -p "$T/empty"; echo "x" > "$T/empty/readme.txt"
chk "$T/empty" >/dev/null 2>&1; ok "nothing to check: rc=3" "$([ $? = 3 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- WPF
wpf w0 <<'X'
<Label x:Name="NameLabel" Content="{DynamicResource NameText}" Target="{Binding ElementName=NameBox}" />
<TextBox x:Name="NameBox" AutomationProperties.LabeledBy="{Binding ElementName=NameLabel}" />
<ComboBox AutomationProperties.Name="{DynamicResource KindText}" />
<Button Content="{DynamicResource SaveText}" IsDefault="True" />
<Button Content="{DynamicResource CancelText}" IsCancel="True" />
<Button AutomationProperties.Name="{DynamicResource CloseText}" ToolTip="{DynamicResource CloseText}"><Image Source="x.png" /></Button>
<ListBox><ListBox.ItemTemplate><DataTemplate><TextBox Text="{Binding V}" /></DataTemplate></ListBox.ItemTemplate></ListBox>
X
clean w0 "WPF: a compliant window (strings from resources) is clean"
mkdir -p "$T/w0rd"; cp -r "$T/w0/." "$T/w0rd/"; printf '<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Style TargetType="TextBox" /></ResourceDictionary>\n' > "$T/w0rd/Styles.xaml"
clean w0rd "WPF: ResourceDictionary files are ignored; controls inside a DataTemplate are not flagged"

wpf w1 <<'X'
<Button Content="_Save" /><Button Content="_Search" />
X
expect w1 UIG-KEY006 "WPF: duplicate access key"
wpf w2 <<'X'
<Button Content="_Delete" IsDefault="True" /><Button Content="_Cancel" IsCancel="True" />
X
expect w2 UIG-CTL091 "WPF: destructive button is the default button"
wpf w2b <<'X'
<Button Content="_Delete" /><Button Content="_Cancel" IsDefault="True" />
X
absent w2b UIG-CTL091 "WPF: the safe button is the default (not flagged)"
wpf w3 <<'X'
<Button Content="_Yes" IsDefault="True" /><Button Content="_No" IsDefault="True" />
X
expect w3 UIG-LAY007 "WPF: two default buttons (info)"
out="$(chk "$T/w3")"; ok "WPF: info is hidden without --all" "$([ "$(has "$out" UIG-LAY007)" = 0 ] && [ "$(has "$out" '--all')" = 1 ] && echo 1 || echo 0)"
wpf w4 <<'X'
<Button ToolTip="Close"><Image Source="x.png" /></Button>
X
expect w4 UIG-CTL003 "WPF: icon-only button without AutomationProperties.Name"
absent w4 UIG-CTL003T "WPF: ... but it has a ToolTip"
wpf w5 <<'X'
<Button AutomationProperties.Name="Close"><Path Data="M0,0" /></Button>
X
expect w5 UIG-CTL003T "WPF: icon-only button without ToolTip"
out="$(chk "$T/w5")"; ok "UIG-CTL003T is a warning (shown without --all; UI-CTL-003 is mandatory)" "$([ "$(has "$out" ' UIG-CTL003T ')" = 1 ] && echo 1 || echo 0)"
wpf w6 <<'X'
<TextBlock Text="Name" /><TextBox x:Name="NameBox" />
X
expect w6 UIG-ACC001 "WPF: TextBox with only a TextBlock next to it has no accessible name"
wpf w6b <<'X'
<Label Content="Name:" Target="{Binding ElementName=NameBox}" /><TextBox x:Name="NameBox" />
X
expect w6b UIG-ACC001 "WPF: Label Target alone gives no accessible name (Narrator, TP4)"
wpf w7 <<'X'
<Canvas><TextBox Canvas.Left="10" Canvas.Top="20" AutomationProperties.Name="N" /></Canvas>
X
expect w7 UIG-LAY005 "WPF: controls positioned on a Canvas"
wpf w7b <<'X'
<Canvas><Ellipse Canvas.Left="10" Canvas.Top="20" Width="5" Height="5" /></Canvas>
X
absent w7b UIG-LAY005 "WPF: shapes on a Canvas are not flagged"
wpf w8 <<'X'
<TextBlock FontFamily="Comic Sans MS" Text="x" /><TextBlock FontFamily="Segoe UI" Text="y" /><TextBlock FontFamily="Segoe MDL2 Assets" Text="z" />
X
expect w8 UIG-TYP001 "WPF: custom font family"
out="$(chk "$T/w8")"; ok "UIG-TYP001 is a warning (shown without --all; UI-TYP-001 is mandatory)" "$([ "$(has "$out" ' UIG-TYP001 ')" = 1 ] && echo 1 || echo 0)"
out="$(chk "$T/w8" --all)"; ok "WPF: Segoe UI and icon fonts are not flagged (1 finding)" "$([ "$(grep -c ' UIG-TYP001 ' <<<"$out")" = 1 ] && echo 1 || echo 0)"
wpf w9 <<'X'
<Button Content="Save" /><TextBlock Text="Hello" /><TextBlock Text="{Binding Greeting}" />
X
expect w9 UIG-LOC001 "WPF: hard-coded display strings are counted (one finding)"
out="$(chk "$T/w9")"; ok "UIG-LOC001 is a warning (shown without --all; UI-LOC-001 is mandatory)" "$([ "$(has "$out" ' UIG-LOC001 ')" = 1 ] && echo 1 || echo 0)"
wpf w10 nomanifest <<'X'
<Button Content="Save" />
X
expect w10 UIG-DPI002 "WPF: no DPI awareness declaration"
cp -r "$T/w10" "$T/w10b"; sed -i 's#</PropertyGroup>#  <ApplicationHighDpiMode>SystemAware</ApplicationHighDpiMode>\n  </PropertyGroup>#' "$T/w10b/App.csproj"
absent w10b UIG-DPI002 "WPF: ApplicationHighDpiMode in the csproj counts as a declaration"

# ---------------------------------------------------------------- WinForms
wf f0 <<'X'
        SaveButton = new Button();
        SearchButton = new Button();
        SaveButton.Text = "&Save";
        SearchButton.Text = "Sea&rch";
        AcceptButton = SaveButton;
        AutoScaleMode = AutoScaleMode.Font;
X
clean f0 "WinForms: a compliant form is clean"
wf f1 <<'X'
        SaveButton = new Button();
        SearchButton = new Button();
        SaveButton.Text = "&Save";
        SearchButton.Text = "&Search";
        AutoScaleMode = AutoScaleMode.Font;
X
expect f1 UIG-KEY006 "WinForms: duplicate access key"
wf f2 <<'X'
        DeleteButton = new Button();
        DeleteButton.Text = "削除";
        AcceptButton = DeleteButton;
        AutoScaleMode = AutoScaleMode.Font;
X
expect f2 UIG-CTL091 "WinForms: destructive button is the AcceptButton"
wf f3 <<'X'
        AutoScaleMode = AutoScaleMode.None;
X
expect f3 UIG-DPI001 "WinForms: AutoScaleMode.None"
wf f4 <<'X'
        IconButton = new Button();
        IconButton.Image = Properties.Resources.Close;
        IconButton.Text = "";
        AutoScaleMode = AutoScaleMode.Font;
X
expect f4 UIG-CTL003 "WinForms: icon-only button without AccessibleName"
wf f4b <<'X'
        IconButton = new Button();
        IconButton.Image = Properties.Resources.Close;
        IconButton.AccessibleName = "Close";
        AutoScaleMode = AutoScaleMode.Font;
X
absent f4b UIG-CTL003 "WinForms: ... with AccessibleName is not flagged"
wf f5 nodpi <<'X'
        AutoScaleMode = AutoScaleMode.Font;
X
expect f5 UIG-DPI002 "WinForms: no DPI mode declaration"
wf f6 <<'X'
        FileItem = new ToolStripMenuItem();
        EditItem = new ToolStripMenuItem();
        FileItem.Text = "&File";
        EditItem.Text = "&Find";
        AutoScaleMode = AutoScaleMode.Font;
X
absent f6 UIG-KEY006 "WinForms: menu items are not checked for duplicate keys (separate scopes)"

# ---------------------------------------------------------------- MFC
mfc m0 <<<"$RC_OK"
clean m0 "MFC: a compliant project is clean"
MFC_PCH="" mfc m1 <<<"$RC_OK"
expect m1 UIG-CTL100 "MFC: no Common Controls manifest"
MFC_PCH="${PRAGMA_OK//6.0.0.0/5.82.0.0}" mfc m2 <<<"$RC_OK"
expect m2 UIG-CTL100V "MFC: Common Controls version below 6.0"
MFC_PCH="$PRAGMA_OK"$'\n'"${PRAGMA_OK//6.0.0.0/5.0.0.0}" mfc m2b <<<"$RC_OK"
expect m2b UIG-CTL100V "MFC: conflicting Common Controls versions"
MFC_CHARSET=MultiByte mfc m3 <<<"$RC_OK"
expect m3 UIG-CTL100U "MFC: MultiByte character set"
MFC_NODPI=1 mfc m4 <<<"$RC_OK"
expect m4 UIG-DPI002 "MFC: no DPI awareness declaration"
mfc m5 <<'X'
IDD_MAIN DIALOGEX 0, 0, 240, 100
BEGIN
    DEFPUSHBUTTON   "&Save",IDOK,129,79,50,14
    PUSHBUTTON      "S&earch",IDC_SEARCH,183,79,50,14
    PUSHBUTTON      "&Cancel",IDCANCEL,183,59,50,14
END
X
absent m5 UIG-KEY006 "MFC: different access keys (S / E / C) in a dialog are not flagged"
mfc m5b <<'X'
IDD_MAIN DIALOGEX 0, 0, 240, 100
BEGIN
    DEFPUSHBUTTON   "&Save",IDOK,129,79,50,14
    PUSHBUTTON      "&Search",IDC_SEARCH,183,79,50,14
END
X
expect m5b UIG-KEY006 "MFC: duplicate access key in a dialog"
mfc m6 <<'X'
IDD_MAIN DIALOGEX 0, 0, 240, 100
BEGIN
    DEFPUSHBUTTON   "削除",IDOK,129,79,50,14
    PUSHBUTTON      "キャンセル",IDCANCEL,183,79,50,14
END
X
expect m6 UIG-CTL091 "MFC: destructive DEFPUSHBUTTON"
mfc m7 <<'X'
IDD_MAIN DIALOGEX 0, 0, 240, 100
BEGIN
    DEFPUSHBUTTON   "OK",IDOK,129,79,50,14
    DEFPUSHBUTTON   "Apply",IDAPPLY,183,79,50,14
END
X
expect m7 UIG-LAY007 "MFC: two DEFPUSHBUTTONs in a dialog (info)"
MFC_CT=DynamicLibrary mfc m8 <<<"$RC_OK"
expect m8 UIG-CTL101 "MFC: a DLL with a dialog (info: check the manifest resource ID 2 by hand)"
out="$(chk "$T/m8")"; ok "UIG-CTL101 stays info (the only exception to the severity policy: a reminder, not a detected violation)" "$([ "$(has "$out" ' UIG-CTL101 ')" = 0 ] && echo 1 || echo 0)"
# 2 つのダイアログで、同じアクセスキーを使っても、重複ではない
mfc m9 <<'X'
IDD_A DIALOGEX 0, 0, 240, 100
BEGIN
    PUSHBUTTON      "&Save",IDOK,129,79,50,14
END
IDD_B DIALOGEX 0, 0, 240, 100
BEGIN
    PUSHBUTTON      "&Save",IDOK,129,79,50,14
END
X
absent m9 UIG-KEY006 "MFC: the same access key in different dialogs is not a duplicate"

# ---------------------------------------------------------------- 出力・終了コード・読み取り専用
out="$(chk "$T/w2" --json "$T/out.json")"
ok "--json writes counts, stats and findings (with rule IDs)" "$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d['counts']['warning']>=1 and d['findings'][0]['rule'].startswith('UI-') and d['guideline_version'] else 1)" "$T/out.json" && echo 1 || echo 0)"
ok "the finding shows file(line) relative to the project folder" "$([ "$(has "$out" 'MainWindow.xaml(')" = 1 ] && echo 1 || echo 0)"
chk "$T/w2" --fail-on-warning >/dev/null; ok "--fail-on-warning: rc=1 when there is a warning" "$([ $? = 1 ] && echo 1 || echo 0)"
chk "$T/w0" --fail-on-warning >/dev/null; ok "--fail-on-warning: rc=0 when clean" "$([ $? = 0 ] && echo 1 || echo 0)"
a="$(find "$T/w2" "$T/m1" -type f -exec md5sum {} + | sort | md5sum)"; chk "$T/w2" --all >/dev/null; chk "$T/m1" --all >/dev/null; b="$(find "$T/w2" "$T/m1" -type f -exec md5sum {} + | sort | md5sum)"
ok "the tool is read-only (checked folders are unchanged)" "$([ "$a" = "$b" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 生成したソリューションは、ガイドラインの検査を通る (v2.27.0 で、テンプレートを対応させた)
mkdir -p "$T/gen_wpf" "$T/gen_wf" "$T/gen_mfc" "$T/gen_mdi" "$T/gen_sdi"
python3 "$NS" "$T/gen_wpf" --type wpf --layers none --tests none >/dev/null 2>&1
python3 "$NS" "$T/gen_wf" --type winforms --layers none --tests none >/dev/null 2>&1
python3 "$NS" "$T/gen_mfc" --type mfc-dialog --layers none --tests none >/dev/null 2>&1
python3 "$NS" "$T/gen_mdi" --type mfc-mdi --layers none --tests none >/dev/null 2>&1
python3 "$NS" "$T/gen_sdi" --type mfc --layers none --tests none >/dev/null 2>&1
for d in gen_wpf gen_wf gen_mfc gen_mdi gen_sdi; do
    out="$(chk "$T/$d" --all)"; rc=$?
    ok "$d: runs on a generated solution (rc=0, 'error 0')" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 /')" = 1 ] && echo 1 || echo 0)"
done
out="$(chk "$T/gen_wpf")"
ok "generated WPF: only UIG-LOC001 remains (UI-DPI-002 / UI-ACC-001 are satisfied by the template; localization is a decision left to the user)" "$([ "$(has "$out" 'warning 1')" = 1 ] && [ "$(has "$out" ' UIG-LOC001 ')" = 1 ] && echo 1 || echo 0)"
for d in gen_wf gen_mfc gen_mdi gen_sdi; do
    out="$(chk "$T/$d")"
    ok "$d: no warning on a generated solution (DPI awareness, Common Controls manifest)" "$([ "$(has "$out" 'error 0 / warning 0')" = 1 ] && echo 1 || echo 0)"
done
ok "generated WPF: app.manifest declares DPI awareness and the csproj references it" "$(grep -q 'dpiAware' "$T/gen_wpf/gen_wpf/app.manifest" && grep -q '<ApplicationManifest>app.manifest</ApplicationManifest>' "$T/gen_wpf/gen_wpf/gen_wpf.csproj" && echo 1 || echo 0)"
ok "generated WPF: the name box gets its UIA name from LabeledBy (Label Target alone is silent in Narrator)" "$(f="$T/gen_wpf/gen_wpf/Views/MainWindow.xaml"; grep -q 'x:Name="NameLabel"' "$f" && grep -q 'AutomationProperties.LabeledBy="{Binding ElementName=NameLabel}"' "$f" && echo 1 || echo 0)"
ok "generated WinForms: ApplicationHighDpiMode is set in the csproj" "$(grep -q '<ApplicationHighDpiMode>SystemAware</ApplicationHighDpiMode>' "$T/gen_wf/gen_wf/gen_wf.csproj" && echo 1 || echo 0)"
for d in gen_mfc gen_mdi gen_sdi; do
    ok "$d: framework.h (included from pch.h) has the Common Controls directive" "$(grep -q 'Microsoft.Windows.Common-Controls' "$T/$d/$d/framework.h" && echo 1 || echo 0)"
    ok "$d: DPI awareness is declared in the vcxproj (Debug and Release: <Manifest><EnableDpiAwareness>true), not by SetProcessDPIAware()" "$([ "$(grep -c '<EnableDpiAwareness>true</EnableDpiAwareness>' "$T/$d/$d/$d.vcxproj")" = 2 ] && ! grep -q 'SetProcessDPIAware' "$T/$d/$d/SampleApp.cpp" && echo 1 || echo 0)"
done

# ---------------------------------------------------------------- 参照文書と、規則 ID の対応
ok "reference guideline exists, is v2.x, UTF-8 without BOM / CR" "$([ -f "$REF" ] && head -n 1 "$REF" | grep -q 'Windows Desktop UI Design Guidelines' && grep -q '^\*\*版:\*\*' "$REF" && [ "$(head -c3 "$REF" | xxd -p)" != efbbbf ] && ! grep -q $'\r' "$REF" && echo 1 || echo 0)"
bad=""
for id in $(grep -o '"UI-[A-Z]*-[0-9]*"' "$CK" | tr -d '"' | sort -u); do
    grep -q "^\*\*$id \[\(必須\|推奨\|任意\)\]" "$REF" || bad="$bad $id"
done
ok "every rule ID used by the checker is an active rule in the reference guideline${bad:+ (missing:$bad)}" "$([ -z "$bad" ] && echo 1 || echo 0)"
ver="$(grep -m1 '^\*\*版:\*\*' "$REF" | sed 's/[^0-9.]*\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/')"
ok "GUIDELINE_VERSION in the checker matches the reference guideline (v$ver)" "$([ "$(grep -m1 '^GUIDELINE_VERSION' "$CK" | sed 's/.*"\(.*\)".*/\1/')" = "$ver" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- Skill の記述
S="$SK/SKILL.md"
ok "SKILL.md: name ui-design-review, points to the reference, the checker and the checklist (Appendix F)" "$([ -f "$S" ] && head -n 6 "$S" | grep -q '^name: ui-design-review$' && grep -q 'references/UI-Design-Guidelines.md' "$S" && grep -q 'ui_guideline_check.py' "$S" && grep -q '付録 F' "$S" && echo 1 || echo 0)"
ok "SKILL.md: warns not to read the whole guideline and to find rules by ID" "$(grep -q 'grep -n' "$S" && grep -q '全文を読まない' "$S" && echo 1 || echo 0)"
ok "SKILL.md: states the heuristics limits and does not weaken screens to silence findings" "$(grep -q '誤検出と限界' "$S" && grep -q '指摘を消すために' "$S" && echo 1 || echo 0)"
ok "SKILL.md: the F.2 report template is inline (確認した項目 / 不適合 / 確認不能)" "$(grep -q '^確認した項目:' "$S" && grep -q '^不適合:' "$S" && grep -q '^確認不能:' "$S" && echo 1 || echo 0)"
ok "SKILL.md: states the severity policy and its only exception (UIG-CTL101)" "$(grep -q '重大度の方針' "$S" && grep -q '例外は `UIG-CTL101` だけ' "$S" && echo 1 || echo 0)"
ok "SKILL.md: WPF defaults to system DPI awareness (do not claim PerMonitorV2 by default)" "$(grep -q 'システム DPI 対応' "$S" && grep -q 'PerMonitorV2 相当」と書かない' "$S" && echo 1 || echo 0)"
ok "SKILL.md: cite rules after checking the text (no invented section numbers)" "$(grep -q '本文を `grep` で確かめてから書く' "$S" && echo 1 || echo 0)"
ok "ui-test-first: the plan table has a 守る規則 ID column and the Appendix E item numbers" "$(grep -q '列「守る規則 ID」' "$ROOT/skills/ui-test-first/SKILL.md" && grep -q '付録 E の項目のうち、この画面に該当するものの番号' "$ROOT/skills/ui-test-first/SKILL.md" && echo 1 || echo 0)"
ok "ui-test-first: the 守る規則 ID column is in both table definitions (部品 / 操作と期待), and Appendix E item 7 (有効 / 無効) is mapped" "$(grep -q '表の列は、「部品 / 種類 / 識別の名前 / 守る規則 ID」' "$ROOT/skills/ui-test-first/SKILL.md" && grep -q '表の列は、「# / 操作 / 期待 / 確認場所 / 守る規則 ID」' "$ROOT/skills/ui-test-first/SKILL.md" && grep -q '7 状態の条件' "$ROOT/skills/ui-test-first/SKILL.md" && echo 1 || echo 0)"
ok "ui-test-first: ask about every mandatory finding (no silent deferral)" "$(grep -q '一部だけ質問して、残りを黙って' "$ROOT/skills/ui-test-first/SKILL.md" && echo 1 || echo 0)"
ok "SKILL.md: the 適用した付録 field means a technology appendix (not Appendix F)" "$(grep -q '「適用した付録」' "$S" && grep -q '付録 F (チェックリスト) は、書かない' "$S" && echo 1 || echo 0)"
ok "SKILL.md: 「画面の確認」 only when the screen was actually operated (otherwise 実装の確認 / 確認不能)" "$(grep -q '「画面の確認」は、実際の画面を、起動して、操作・表示して、確かめたときだけ' "$S" && grep -q '「実装の確認」' "$S" && echo 1 || echo 0)"
ok "SKILL.md: following the OS (theme / text size) cannot be judged from color settings (UI-CLR-005); use 確認不能" "$(grep -q '色指定やスタイルの有無では判定できない' "$S" && grep -q 'UI-CLR-005' "$S" && echo 1 || echo 0)"
for f in skills/ui-test-first/SKILL.md skills/wpf-check/SKILL.md skills/winforms-check/SKILL.md skills/mfc-check/SKILL.md; do
    ok "$f: points to /ui-design-review" "$(grep -q 'ui-design-review' "$ROOT/$f" && echo 1 || echo 0)"
done
out="$(bash "$ROOT/install/install.sh" --skills-only --dry-run --skills-dir "$T/skills_dst" 2>&1)"
ok "install.sh --dry-run lists skills/ui-design-review" "$(echo "$out" | grep -q 'ui-design-review' && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
