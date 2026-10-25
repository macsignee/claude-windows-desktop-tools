#!/usr/bin/env bash
# winforms_check_test.sh - winforms_check.py を、生成したソリューションと、わざと壊した複製で検証する。
# Windows も .NET も不要。
# Usage: tests/winforms_check_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
WC="$ROOT/skills/winforms-check/scripts/winforms_check.py"
T="${TMPDIR:-/tmp}/wfchk_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
chk() { python3 -I "$WC" "$1"; }

mkdir -p "$T/WfApp" "$T/NoLogic" "$T/AppOnly" "$T/Lib"
python3 "$NS" "$T/WfApp" --type winforms --layers data,logic --tests mstest --ui-tests flaui >/dev/null
python3 "$NS" "$T/NoLogic" --type winforms --layers data --tests mstest >/dev/null
python3 "$NS" "$T/AppOnly" --type winforms --layers none --tests none >/dev/null
python3 "$NS" "$T/Lib" --type csharp-dll --layers logic --tests mstest >/dev/null

# ---------------------------------------------------------------- 生成直後は、指摘が出ない
for d in WfApp NoLogic AppOnly; do
    out="$(chk "$T/$d")"; rc=$?
    ok "$d: generated solution is clean (rc=0, error 0 / warning 0)" "$([ $rc = 0 ] && [ "$(has "$out" 'error 0 / warning 0')" = 1 ] && echo 1 || echo 0)"
done
out="$(chk "$T/Lib")"; rc=$?
ok "csharp-dll (no WinForms): nothing to check (rc=3)" "$([ $rc = 3 ] && echo 1 || echo 0)"
chk "$T/nonexistent" >/dev/null 2>&1; ok "bad directory: rc=2" "$([ $? = 2 ] && echo 1 || echo 0)"

# 壊した複製を作って、検査する。mut <名前> <基にするフォルダ> <python の式 (s = ファイルの中身。path = ファイルのパス)>
# 使い方: mut NAME BASE REL 'python 文 (変数 s)' → $T/NAME を作る
mut() {
    rm -rf "$T/$1"; cp -r "$T/$2" "$T/$1"
    python3 - "$T/$1/$3" "$4" <<'PY'
import sys
p, code = sys.argv[1], sys.argv[2]
b = open(p, 'rb').read()
bom = b.startswith(b'\xef\xbb\xbf')
s = b.decode('utf-8-sig').replace('\r\n', '\n')
ns = {'s': s}
exec(code, ns)
s = ns['s'].replace('\n', '\r\n')
open(p, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + s.encode('utf-8'))
PY
}
# 1 件の指摘を確かめる: expect <名前> <コード> <rc> <説明>
expect() {
    out="$(chk "$T/$1")"; rc=$?
    ok "$4 ($2, rc=$3)" "$([ $rc = $3 ] && [ "$(has "$out" " $2 ")" = 1 ] && echo 1 || echo 0)"
}
DES="WfApp/Forms/MainForm.Designer.cs"; FRM="WfApp/Forms/MainForm.cs"

# ---------------------------------------------------------------- Designer / Form
mut m1 WfApp "$FRM" 's = s.replace("InitializeComponent();", "")'
expect m1 WFD001 1 "constructor does not call InitializeComponent"
mut m2 WfApp "$DES" 's = s.replace("NameTextBox.Name = \"NameTextBox\";", "NameTextBox.Name = \"ClearButton\";")'
expect m2 WFD002 1 "duplicate Name"
mut m3 WfApp "$DES" 's = s.replace("ClearButton.Name = \"ClearButton\";", "ClearButton.Name = \"clearBtn\";")'
expect m3 WFD003 0 "Name differs from the variable name"
mut m4 WfApp "$DES" 's = s.replace("MainTable.Controls.Add(ClearButton, 0, 2);", "")'
expect m4 WFD004 0 "control never added to Controls"
mut m5 WfApp "$DES" 's = s.replace("ClearButton.Name = \"ClearButton\";", "")'
expect m5 WFD005 0 "UI tests exist and the button has no Name"
mut m5b NoLogic "NoLogic/Forms/MainForm.Designer.cs" 's = s.replace("ClearButton.Name = \"ClearButton\";", "")'
out="$(chk "$T/m5b")"
ok "no UI test project: a missing Name is not WFD005" "$([ "$(has "$out" WFD005)" = 0 ] && echo 1 || echo 0)"
rm -rf "$T/m6"; cp -r "$T/WfApp" "$T/m6"
printf 'namespace WfApp.Forms;\n\npartial class Extra\n{\n    private void InitializeComponent()\n    {\n    }\n}\n' > "$T/m6/WfApp/Forms/Extra.cs"
expect m6 WFD006 1 "InitializeComponent outside Designer.cs"
mut m7 WfApp "$DES" 's = s.replace("        SuspendLayout();\n", "        SuspendLayout();\n        if (DesignMode) { }\n", 1)'
expect m7 WFD007 0 "control statement in InitializeComponent"

# ---------------------------------------------------------------- スレッド・UI
mut m8 WfApp "$FRM" 's = s.replace("    public event EventHandler? NameChanged;", "    private void Busy() { Application.DoEvents(); }\n\n    public event EventHandler? NameChanged;")'
expect m8 WFT001 0 "Application.DoEvents"
mut m9 WfApp "$FRM" 's = s.replace("    public event EventHandler? NameChanged;", "    private void Busy() { Thread.Sleep(1000); }\n\n    public event EventHandler? NameChanged;")'
expect m9 WFT002 0 "Thread.Sleep in a Form"
mut m10 WfApp "WfApp/Program.cs" 's = s.replace("        ApplicationConfiguration.Initialize();", "        Control.CheckForIllegalCrossThreadCalls = false;\n        ApplicationConfiguration.Initialize();")'
expect m10 WFT003 1 "CheckForIllegalCrossThreadCalls = false"
mut m11 WfApp "$FRM" 's = s.replace("    public event EventHandler? NameChanged;", "    private void Make() { var s = new CustomerService(); }\n\n    public event EventHandler? NameChanged;")'
expect m11 WFL004 0 "new Service in a Form"

# ---------------------------------------------------------------- 層
mut m12 WfApp "LogicLayer/MainPresenter.cs" 's = s.replace("        Refresh();\n    }\n\n    private void OnNameChanged", "        MessageBox.Show(\"x\");\n        Refresh();\n    }\n\n    private void OnNameChanged", 1)'
expect m12 WFL001 1 "WinForms type (MessageBox) in the logic layer"
mut m13 WfApp "LogicLayer/LogicLayer.csproj" 's = s.replace("<TargetFramework>net8.0</TargetFramework>", "<TargetFramework>net8.0-windows</TargetFramework>\n    <UseWindowsForms>true</UseWindowsForms>")'
expect m13 WFL001 1 "logic layer csproj depends on WinForms"
mut m14 WfApp "LogicLayer/LogicLayer.csproj" 's = s.replace("</Project>", "  <ItemGroup>\n    <ProjectReference Include=\"..\\WfApp\\WfApp.csproj\" />\n  </ItemGroup>\n</Project>")'
expect m14 WFL003 1 "logic layer references the app"
mut m15 NoLogic "NoLogic/Presenters/MainPresenter.cs" 's = s.replace("        Refresh();\n    }\n\n    private void OnNameChanged", "        MessageBox.Show(\"x\");\n        Refresh();\n    }\n\n    private void OnNameChanged", 1)'
expect m15 WFL002 0 "MessageBox in the Presenter inside the app"

# ---------------------------------------------------------------- 共通の規則
mut m16 AppOnly "AppOnly/Forms/MainForm.cs" 's = s.replace("    public event EventHandler? NameChanged;", """    private bool flag;

    private async void Load() { await Task.Delay(1); }

    private void Wait() { Task.Delay(1).Wait(); }

    private void Swallow()
    {
        try { Wait(); } catch { }
        try { Wait(); } catch (Exception ex) { throw ex; }
    }

    public event EventHandler? NameChanged;""")'
out="$(chk "$T/m16")"
ok "common rules: ASY001 / ASY002 / EXC001 / EXC002 / NAM001 are reported" "$([ "$(has "$out" ' ASY001 ')$(has "$out" ' ASY002 ')$(has "$out" ' EXC001 ')$(has "$out" ' EXC002 ')$(has "$out" ' NAM001 ')" = 11111 ] && echo 1 || echo 0)"
mut m17 AppOnly "AppOnly/Forms/MainForm.cs" 's = s.replace("    public event EventHandler? NameChanged;", "    private async void Button_Click(object? sender, EventArgs e) { await Task.Delay(1); }\n\n    public event EventHandler? NameChanged;")'
out="$(chk "$T/m17")"
ok "async void event handler (sender, EventArgs) is not ASY002" "$([ "$(has "$out" ASY002)" = 0 ] && echo 1 || echo 0)"
ok "test projects are not checked by the common rules" "$(cp -r "$T/WfApp" "$T/m18" && printf 'namespace X;\nclass T { void M() { try { } catch { } } }\n' > "$T/m18/LogicLayer.Tests/Extra.cs" && [ "$(has "$(chk "$T/m18")" EXC001)" = 0 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- 出力
out="$(python3 -I "$WC" "$T/m1" --json "$T/out.json")"
ok "--json writes counts and findings" "$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d['counts']['error']>=1 and d['findings'] else 1)" "$T/out.json" && echo 1 || echo 0)"
ok "the finding shows file(line) relative to the solution folder" "$([ "$(has "$out" 'WfApp/Forms/MainForm.cs(')" = 1 ] && echo 1 || echo 0)"
ok "the tool is read-only (a checked folder is unchanged)" "$(a="$(find "$T/WfApp" -type f -exec md5sum {} + | sort | md5sum)"; chk "$T/WfApp" >/dev/null; b="$(find "$T/WfApp" -type f -exec md5sum {} + | sort | md5sum)"; [ "$a" = "$b" ] && echo 1 || echo 0)"

echo "PASS: $pass / FAIL: $fail"
[ "$fail" = 0 ]
