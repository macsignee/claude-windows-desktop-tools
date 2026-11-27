#!/usr/bin/env bash
# stack_owner_test.sh - stack_owner.py (STACK: の各フレームの所有者の判定と、要約) の単体テスト (Windows 不要)。
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/vs-debug/scripts/stack_owner.py"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok() { if [ "$2" = 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }

if [ ! -f "$SCRIPT" ]; then echo "FAIL: stack_owner.py がない: $SCRIPT"; echo "PASS=0 FAIL=1"; exit 1; fi

# ---- Python の関数を直接呼ぶ (結果は「ok|FAIL 名前」の行)
python3 -I - "$ROOT/skills/vs-debug/scripts" > "$T/py.out" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import stack_owner as so

def check(name, cond):
    print(("ok " if cond else "FAIL ") + name)

SD = r"c:\ws\Sln"
VS = r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.4\atlmfc\src\mfc\wincore.cpp"

# --- classify: ソースのパス
check("classify: ours (case differs)", so.classify(r"C:\WS\Sln\UiLayer\a.cpp", "", SD) == "ours")
check("classify: ours (forward slashes)", so.classify("c:/ws/sln/x.cpp", "", SD) == "ours")
check("classify: ours (solution dir with a trailing backslash)", so.classify(r"c:\ws\sln\x.cpp", "", SD + "\\") == "ours")
check("classify: ext (mapped drive)", so.classify(r"z:\nightly\LibA\src\a.cpp", "", SD) == "ext")
check("classify: ext (UNC)", so.classify(r"\\srv\share\LibA\a.cpp", "", SD) == "ext")
check("classify: sys (MFC source under Visual Studio)", so.classify(VS, "", SD) == "sys")
check("classify: sys (vctools CRT source path of Microsoft's build machine)", so.classify(r"d:\a01\_work\1\s\src\vctools\crt\vcruntime\src\eh\x.cpp", "", SD) == "sys")
check("classify: sys (Windows folder)", so.classify(r"C:\Windows\x.c", "", SD) == "sys")
check("classify: static library: the source is external, the module is our exe -> ext (the file is looked at first)", so.classify(r"z:\nightly\LibA\src\a.cpp", r"C:\ws\Sln\x64\Debug\App.exe", SD) == "ext")
# --- classify: ソースがない
check("classify: no source, ntdll -> sys", so.classify("", "ntdll.dll", SD) == "sys")
check("classify: no source, MFC DLL name -> sys", so.classify("", "MFC140UD.dll", SD) == "sys")
check("classify: no source, .NET core lib -> sys", so.classify("", "System.Private.CoreLib.dll", SD) == "sys")
check("classify: no source, a DLL in our output folder -> unknown (it may be a delivered external DLL copied here; ours needs our source)", so.classify("", r"C:\ws\Sln\x64\Debug\UiLayer.dll", SD) == "unknown")
check("classify: no source, an external DLL copied into our output folder without its PDB -> unknown, never ours", so.classify("", r"C:\ws\Sln\x64\Debug\ExtDll.dll", SD) == "unknown")
check("classify: no source, a DLL under a vendor folder of the solution -> ext", so.classify("", r"C:\ws\Sln\vcpkg_installed\x64-windows\bin\foo.dll", SD) == "ext")
check("classify: no source, System32 DLL by path -> sys", so.classify("", r"C:\Windows\System32\foo.dll", SD) == "sys")
check("classify: no source, external DLL by path -> ext", so.classify("", r"z:\nightly\LibA\LibA.dll", SD) == "ext")
check("classify: no source, a bare module name that is not a system one -> unknown", so.classify("", "LibA.dll", SD) == "unknown")
check("classify: no file, no module -> unknown", so.classify("", "", SD) == "unknown")
# --- classify: SOLUTION がない
check("classify: no solution dir: a source that looks ours -> unknown", so.classify(r"C:\ws\Sln\a.cpp", "", None) == "unknown")
check("classify: no solution dir: a system source is still sys", so.classify(VS, "", None) == "sys")

# --- parse_frame
f = so.parse_frame(r"STACK: #3 Foo<int>::operator() at c:\ws\Sln\a.cpp:54 [module=App.exe]")
check("parse_frame: template + operator() + module", f == {"n": 3, "func": "Foo<int>::operator()", "file": r"c:\ws\Sln\a.cpp", "line": "54", "module": "App.exe"})
f = so.parse_frame(r"STACK: #1 handle at risk at c:\a.cpp:9")
check("parse_frame: ' at ' inside the function name", f is not None and f["func"] == "handle at risk" and f["file"] == r"c:\a.cpp" and f["line"] == "9" and f["module"] == "")
f = so.parse_frame("STACK: #5 [External Code]")
check("parse_frame: no file", f is not None and f["func"] == "[External Code]" and f["file"] == "" and f["n"] == 5)
f = so.parse_frame(r"STACK: #2 Run at \\srv\share\LibA\a.cpp:7 [module=C:\x y\LibA.dll]")
check("parse_frame: UNC file and a module path with a space", f is not None and f["file"] == r"\\srv\share\LibA\a.cpp" and f["module"] == r"C:\x y\LibA.dll")
check("parse_frame: STACK_TRUNCATED is not a frame", so.parse_frame("STACK_TRUNCATED: 27 more frames") is None)
check("parse_frame: other lines are not frames", so.parse_frame("LOCALS: a = 1") is None)

# --- transform
def frames(*specs):
    out = []
    for i, (func, file, mod) in enumerate(specs):
        s = f"STACK: #{i} {func}"
        if file: s += f" at {file}"
        if mod: s += f" [module={mod}]"
        out.append(s)
    return out

SOL = [r"SOLUTION: c:\ws\Sln\Sln.slnx", "DEBUG_MODE: break"]
EXT = ("Lib::Run", r"z:\nightly\LibA\a.cpp:9", "LibA.dll")
SYS = ("CWnd::WindowProc", VS + ":100", "mfc140ud.dll")
OURS = ("App::Go", r"c:\ws\Sln\a.cpp:12", "App.exe")

t = so.transform(["LOCALS: x = 1"] + frames(EXT, SYS, OURS) + SOL)
check("transform: STACK lines are tagged [ext] [sys] [ours] and the module goes to the end in parentheses",
      t[1] == r"STACK: #0 [ext] Lib::Run at z:\nightly\LibA\a.cpp:9 (LibA.dll)" and t[2].startswith("STACK: #1 [sys] CWnd::WindowProc") and t[3] == r"STACK: #2 [ours] App::Go at c:\ws\Sln\a.cpp:12 (App.exe)")
check("transform: OWNER and BOUNDARY come right after the last STACK line", t[4] == "OWNER: top=ext (frame #0)" and t[5] == r"BOUNDARY: #2 ours -> ext #0" and t[6] == r"SOLUTION: c:\ws\Sln\Sln.slnx" and t[0] == "LOCALS: x = 1")
t = so.transform(frames(OURS) + SOL)
check("transform: only our frame -> top=ours, no boundary", "OWNER: top=ours (frame #0)" in t and "BOUNDARY: none" in t)
t = so.transform(frames(SYS, SYS, OURS) + SOL)
check("transform: sys frames on top are skipped -> top=ours (frame #2), no boundary", "OWNER: top=ours (frame #2)" in t and "BOUNDARY: none" in t)
t = so.transform(frames(SYS, SYS) + SOL)
check("transform: all sys -> top=sys", "OWNER: top=sys (frame #0)" in t)
t = so.transform(frames(EXT, ("Mystery", "", "Lib2.dll"), OURS) + SOL)
check("transform: an unknown frame between -> the boundary is not asserted", "BOUNDARY: unknown (frame #1 has no symbols)" in t)
t = so.transform(frames(EXT, SYS, OURS) + ["STACK_TRUNCATED: 27 more frames"] + SOL)
i = t.index("STACK_TRUNCATED: 27 more frames")
check("transform: with STACK_TRUNCATED the summary follows that line (shown frames only)", t[i + 1].startswith("OWNER:") and t[i + 2].startswith("BOUNDARY:"))
src = ["DIRTY: C:\\p\\a.cpp", "DIRTY_COUNT: 1"]
check("transform: no STACK lines -> unchanged", so.transform(src) == src)
t = so.transform(frames(OURS))   # SOLUTION の行がない
check("transform: no SOLUTION line -> our-looking frame is unknown", t[0].startswith("STACK: #0 [unknown]") and "OWNER: top=unknown (frame #0)" in t)
t = so.transform(frames(OURS, EXT) + SOL)
check("transform: our frame is on top and calls nothing external -> boundary none (an external frame below is the caller)", "BOUNDARY: none" in t)

# --- review fixes (v2.107.0): vendor folders, framework frames with mapped paths, narrower module names, truncated summary, path edge cases
check("classify: vcpkg_installed under the solution is external code -> ext", so.classify(r"C:\ws\Sln\vcpkg_installed\x64-windows\include\nlohmann\json.hpp", "", SD) == "ext")
check("classify: ThirdParty under the solution -> ext", so.classify(r"c:\ws\sln\ThirdParty\LibB\b.cpp", "", SD) == "ext")
check("classify: packages / third_party / external / vendor under the solution -> ext", all(so.classify("c:\\ws\\sln\\%s\\x.cpp" % d, "", SD) == "ext" for d in ("packages", "third_party", "external", "vendor")))
check("classify: a folder named like a vendor folder deeper in our project is still ours", so.classify(r"c:\ws\sln\UiLayer\external_api.cpp", "", SD) == "ours" and so.classify(r"c:\ws\sln\UiLayer\packages_view.cpp", "", SD) == "ours")
check("classify: Sln2 is not under Sln", so.classify(r"C:\ws\Sln2\a.cpp", "", SD) == "ext")
check("classify: solution dir given with forward slashes and other case", so.classify(r"C:\WS\SLN\a.cpp", "", "c:/ws/sln") == "ours")
check("classify: .NET framework frame with a Source Link path -> sys (the module says so)", so.classify("/_/src/libraries/System.Private.CoreLib/src/System/ThrowHelper.cs", "System.Private.CoreLib.dll", SD) == "sys")
check("classify: WPF framework frame with a mapped path -> sys", so.classify("/_/src/Microsoft.DotNet.Wpf/src/PresentationFramework/x.cs", "PresentationFramework.dll", SD) == "sys")
check("classify: an external source with an external module stays ext", so.classify(r"z:\nightly\LibA\a.cpp", "LibA.dll", SD) == "ext")
for name in ("MfcHelper.dll", "MfcCommon.dll", "PresentationLogic.dll", "System.Data.SQLite.dll", "Microsoft.Toolkit.Mvvm.dll"):
    check("classify: %s is not a system module -> unknown (bare name)" % name, so.classify("", name, SD) == "unknown")
for name in ("mfc140ud.dll", "MFC140U.dll", "mfcm140ud.dll", "PresentationFramework.dll", "PresentationCore.dll", "System.Linq.dll", "System.Private.CoreLib.dll", "System.Data.Common.dll", "Microsoft.CSharp.dll", "WindowsBase.dll", "msvcp140d.dll", "VCRUNTIME140D.dll", "ucrtbased.dll"):
    check("classify: %s -> sys" % name, so.classify("", name, SD) == "sys")
t = so.transform(frames(EXT, SYS, OURS) + ["STACK_TRUNCATED: 27 more frames"] + SOL)
i = t.index("STACK_TRUNCATED: 27 more frames")
check("transform: BOUNDARY found in the shown frames is reported normally even if truncated", t[i + 2].startswith("BOUNDARY: #2 ours -> ext #0"))
t = so.transform(frames(OURS) + ["STACK_TRUNCATED: 27 more frames"] + SOL)
i = t.index("STACK_TRUNCATED: 27 more frames")
check("transform: no boundary in the shown frames but truncated -> says deeper frames were not checked", t[i + 2].startswith("BOUNDARY: none") and "frames shown" in t[i + 2])
t = so.transform(frames(SYS, SYS) + ["STACK_TRUNCATED: 5 more frames"] + SOL)
i = t.index("STACK_TRUNCATED: 5 more frames")
check("transform: all shown frames are sys but truncated -> OWNER says so", "frames shown" in t[i + 1])
t = so.transform(frames(OURS) + SOL)
check("transform: not truncated -> plain BOUNDARY: none", "BOUNDARY: none" in t)

# --- v2.107.2: ネイティブ C++ (STACK: にファイルがない) の判定: STOPPED のファイルの割り当て、プロジェクトの出力と定義の照合
import os, tempfile
root = tempfile.mkdtemp()
def w(rel, text):
    path = os.path.join(root, *rel.split("/")); os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)
w("App/App.vcxproj", "<Project><PropertyGroup><ProjectName>App</ProjectName></PropertyGroup></Project>")
w("Lib/Renamed.vcxproj", "<Project><PropertyGroup><TargetName>RealName</TargetName></PropertyGroup></Project>")
w("App/SampleDlg.cpp", "void SampleDlg::OnCallExtDll()\n{\n  ExtDll_Sum(p, n);\n}\nBEGIN_MESSAGE_MAP(SampleDlg, CDialog)\n ON_BN_CLICKED(1, &SampleDlg::OnMapOnly)\nEND_MESSAGE_MAP()\n")
w("vcpkg_installed/x64/include/vendor.cpp", "void Vendor::Thing()\n{\n}\n")
w("x64/Debug/App/junk.cpp", "void Junk::Fn()\n{\n}\n")
WSD = r"C:\ws\Sln"
def nf(func, mod): return so.classify_native(func, mod, WSD, root)
check("project_outputs: stems of the vcxproj files, and TargetName", so.project_outputs(root) == {"app", "renamed", "realname"})
check("native: our exe + a method defined in our sources -> ours", nf("SampleDlg::OnCallExtDll", r"C:\ws\Sln\x64\Debug\App.exe") == "ours")
check("native: our exe + a method only referenced in the message map (no definition with a paren) -> unknown", nf("SampleDlg::OnMapOnly", r"C:\ws\Sln\x64\Debug\App.exe") == "unknown")
check("native: our exe + a function without a class (static library function) -> unknown", nf("ExtStatic_Sum", r"C:\ws\Sln\x64\Debug\App.exe") == "unknown")
check("native: our exe + a qualified name that no source of ours defines (static library class) -> unknown", nf("ExtStatic::Helper", r"C:\ws\Sln\x64\Debug\App.exe") == "unknown")
check("native: a copied external DLL in our output folder -> unknown even if the name looks defined", nf("SampleDlg::OnCallExtDll", r"C:\ws\Sln\x64\Debug\ExtDll.dll") == "unknown")
check("native: a name defined only under a vendor folder or a build folder does not count", nf("Vendor::Thing", r"C:\ws\Sln\x64\Debug\App.exe") == "unknown" and nf("Junk::Fn", r"C:\ws\Sln\x64\Debug\App.exe") == "unknown")
check("native: TargetName override: RealName.dll is ours when defined", (w("Lib/Real.cpp", "int Real::Calc()\n{\n return 1;\n}\n") or True) and nf("Real::Calc", r"C:\ws\Sln\x64\Debug\RealName.dll") == "ours")
check("native: without a solution root nothing is claimed as ours", so.classify_native("SampleDlg::OnCallExtDll", r"C:\ws\Sln\x64\Debug\App.exe", WSD, None) == "unknown")

OW1 = ["STACK: #0 ExtDll_Sum [module=C:\\ws\\Sln\\x64\\Debug\\ExtDll.dll]",
       "STACK: #1 SampleDlg::OnCallExtDll [module=C:\\ws\\Sln\\x64\\Debug\\App.exe]",
       "STACK: #2 _AfxDispatchCmdMsg [module=C:\\Windows\\System32\\mfc140ud.dll]",
       r"SOLUTION: C:\ws\Sln\App.slnx", r"STOPPED: ExtDll_Sum at C:\ws\ExtDll\ExtDll\ExtDllSum.cpp:8"]
t = so.transform(OW1, root)
check("OW1 on a native stack: #0 gets the STOPPED file -> ext, #1 is defined in our sources -> ours, OWNER top=ext, boundary found",
      t[0].startswith("STACK: #0 [ext] ExtDll_Sum at C:\\ws\\ExtDll\\ExtDll\\ExtDllSum.cpp:8") and t[1].startswith("STACK: #1 [ours] SampleDlg::OnCallExtDll") and "OWNER: top=ext (frame #0)" in t and "BOUNDARY: #1 ours -> ext #0" in t)
OW3 = ["STACK: #0 ExtStatic_Sum [module=C:\\ws\\Sln\\x64\\Debug\\App.exe]",
       "STACK: #1 SampleDlg::OnCallExtDll [module=C:\\ws\\Sln\\x64\\Debug\\App.exe]",
       r"SOLUTION: C:\ws\Sln\App.slnx", r"STOPPED: ExtStatic_Sum at C:\ws\ExtStatic\ExtStatic\ExtStaticSum.cpp:8"]
t = so.transform(OW3, root)
check("OW3 static library: #0 -> ext by the STOPPED file although the module is our exe", t[0].startswith("STACK: #0 [ext]") and "OWNER: top=ext (frame #0)" in t and "BOUNDARY: #1 ours -> ext #0" in t)
OW4 = ["STACK: #0 00007ffb949116d2 [module=C:\\ws\\Sln\\x64\\Debug\\ExtDll.dll]",
       "STACK: #1 SampleDlg::OnCallExtDll [module=C:\\ws\\Sln\\x64\\Debug\\App.exe]",
       r"SOLUTION: C:\ws\Sln\App.slnx", r"STOPPED: SampleDlg::OnCallExtDll at C:\ws\Sln\App\SampleDlg.cpp:75"]
t = so.transform(OW4, root)
check("OW4 no PDB: the STOPPED file goes to #1 (matched by function name, not by index) -> ours; #0 stays unknown, never ours", t[0].startswith("STACK: #0 [unknown]") and t[1].startswith("STACK: #1 [ours]") and "OWNER: top=unknown (frame #0)" in t)
OW5 = ["STACK: #0 SampleDlg::OnInitDialog [module=C:\\ws\\Sln\\x64\\Debug\\App.exe]", "STACK: #1 AfxDlgProc [module=C:\\Windows\\System32\\mfc140ud.dll]",
       r"SOLUTION: C:\ws\Sln\App.slnx", r"STOPPED: SampleDlg::OnInitDialog at C:\ws\Sln\App\SampleDlg.cpp:30"]
t = so.transform(OW5, root)
check("OW5: our code at the breakpoint -> ours, OWNER top=ours", t[0].startswith("STACK: #0 [ours] SampleDlg::OnInitDialog at C:\\ws\\Sln\\App\\SampleDlg.cpp:30") and "OWNER: top=ours (frame #0)" in t)
t = so.transform(["STACK: #0 Bar at C:\\ws\\Sln\\b.cpp:2 [module=App.exe]", "STACK: #1 Bar [module=C:\\Windows\\System32\\x.dll]", "STOPPED: Bar at C:\\q\\z.cpp:9", "SOLUTION: C:\\ws\\Sln\\App.slnx"], root)
check("STOPPED mapping: a frame that already has a file keeps it; the next frame with the same name gets the STOPPED file", t[0].startswith("STACK: #0 [ours] Bar at C:\\ws\\Sln\\b.cpp:2") and "C:\\q\\z.cpp:9" in t[1])

# --- v2.107.2 のレビューの指摘: 定義と呼び出しの区別 (C1)、STOPPED の割り当てにモジュールの一致 (I1)、外のコードの置き場の名前 (I2)、裸のモジュール名 (M3)、STOPPED の端 (M4)
root2 = tempfile.mkdtemp()
def w2(rel, text):
    path = os.path.join(root2, *rel.split("/")); os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)
w2("App/App.vcxproj", "<Project/>")
w2("App/Dlg.cpp", "\n".join([
  "#include <x>",
  "void Dlg::Go()",
  "{",
  "  ExtStatic::Helper(1);",
  "  int r = ExtStatic::Calc(2);",
  "  return Lib::Helper(r);",
  "  if (ok) Lib::Run(3);",
  "}",
  "// calls Lib::Hidden() {",
  "/* Lib::Block() { */",
  "friend int Lib::Friend(int);",
  "int Dlg::Size() const",
  "{",
  "  return 0;",
  "}",
  "Dlg::Dlg(int x) : m_x(x)",
  "{",
  "}",
  "int Dlg::Wide(",
  "  int a,",
  "  int b)",
  "{",
  "  return a + b;",
  "}",
  "Dlg::~Dlg()",
  "{",
  "}",
  "bool Dlg::operator==(const Dlg& o) const",
  "{",
  "  return true;",
  "}",
  ""]))
w2("3rdparty/Zlib/Zlib.vcxproj", "<Project/>")
w2("3rdparty/Zlib/z.cpp", "int Zlib::Inflate()\n{\n  return 1;\n}\n")
def nf2(func, mod, sd=WSD, rt=root2): return so.classify_native(func, mod, sd, rt)
APPEXE = r"C:\ws\Sln\x64\Debug\App.exe"
check("C1: a CALL of a library function in our sources is not a definition (ExtStatic::Helper(1);) -> unknown", nf2("ExtStatic::Helper", APPEXE) == "unknown")
check("C1: a call whose result is used (int r = ExtStatic::Calc(2);) -> unknown", nf2("ExtStatic::Calc", APPEXE) == "unknown")
check("C1: return Lib::Helper(r); and if (ok) Lib::Run(3); are calls -> unknown", nf2("Lib::Helper", APPEXE) == "unknown" and nf2("Lib::Run", APPEXE) == "unknown")
check("C1: names in comments and a friend declaration are not definitions -> unknown", nf2("Lib::Hidden", APPEXE) == "unknown" and nf2("Lib::Block", APPEXE) == "unknown" and nf2("Lib::Friend", APPEXE) == "unknown")
check("C1: a real definition is ours", nf2("Dlg::Go", APPEXE) == "ours")
check("C1: const method, constructor with initialiser, multi-line parameters, destructor, operator== are definitions -> ours",
      all(nf2(n, APPEXE) == "ours" for n in ("Dlg::Size", "Dlg::Dlg", "Dlg::Wide", "Dlg::~Dlg", "Dlg::operator==")))
check("I2: a vendored project under 3rdparty does not make a copied DLL ours", nf2("Zlib::Inflate", r"C:\ws\Sln\x64\Debug\Zlib.dll") == "unknown")
check("I2: a source under 3rdparty / deps / extern / submodules is external code -> ext", all(so.classify("c:\\ws\\sln\\%s\\x.cpp" % d, "", SD) == "ext" for d in ("3rdparty", "deps", "extern", "submodules")))
check("M3: a bare module name is never claimed as ours", nf2("Dlg::Go", "App.exe") == "unknown")
check("M3: without a solution dir nothing is ours", nf2("Dlg::Go", APPEXE, None) == "unknown")

# I1: STOPPED のファイルを、別のモジュールのフレームに割り当てない
I1 = ["STACK: #0 Process [module=C:\\ws\\Sln\\x64\\Debug\\ExtDll.dll]", "STACK: #1 Process [module=C:\\ws\\Sln\\x64\\Debug\\App.exe]",
      r"SOLUTION: C:\ws\Sln\App.slnx", r"STOPPED: Process at C:\ws\Sln\App\p.cpp:3"]
t = so.transform(I1, root2)
check("I1: our source file is not given to a same-named frame of an external DLL; it goes to the frame of our exe -> #0 unknown, #1 ours, never top=ours for the external frame",
      t[0].startswith("STACK: #0 [unknown] Process (") and t[1].startswith("STACK: #1 [ours] Process at C:\\ws\\Sln\\App\\p.cpp:3") and "OWNER: top=unknown (frame #0)" in t)
t = so.transform(I1, None)
check("I1: without a solution root, an in-solution STOPPED file is not assigned at all (cannot check the module) -> unknown", t[0].startswith("STACK: #0 [unknown]") and t[1].startswith("STACK: #1 [unknown]"))
# M4
t = so.transform(["STACK: #0 Foo [module=C:\\ws\\Sln\\x64\\Debug\\ExtDll.dll]", r"SOLUTION: C:\ws\Sln\App.slnx", "STOPPED: (location unknown)"], root2)
check("M4: STOPPED: (location unknown) assigns nothing", t[0].startswith("STACK: #0 [unknown] Foo (") and " at " not in t[0])
t = so.transform([r"STOPPED: Far at C:\ws\Sln\App\far.cpp:1", "STACK: #0 Near [module=C:\\Windows\\System32\\ntdll.dll]", r"SOLUTION: C:\ws\Sln\App.slnx"], root2)
check("M4: STOPPED before the STACK lines works; no frame has the stopped name -> nothing is assigned (the stop is outside the shown frames)", t[1].startswith("STACK: #0 [sys] Near") and " at " not in t[1])

# --- v2.107.3: ネイティブの例外 (SEH) の EXCEPTION:。ホストが出す LAST_OUTPUT: (デバッグ出力ペインの最後の行) を、例外の形のときだけ EXCEPTION: にする
FR = ["STACK: #0 ExtDll_Sum [module=C:\\ws\\Sln\\x64\\Debug\\ExtDll.dll]", r"SOLUTION: C:\ws\Sln\App.slnx"]
JA = "LAST_OUTPUT: 0x00007FFB1ACD16D2 (ExtDll.dll) で例外がスローされました (App.exe 内): 0xC0000005: 場所 0x0000000000000000 の読み取り中にアクセス違反が発生しました"
t = so.transform([JA] + FR, None)
check("EXCEPTION: made from the Japanese VS line, placed before the STACK lines; LAST_OUTPUT: is gone", t[0].startswith("EXCEPTION: 0x00007FFB1ACD16D2 (ExtDll.dll) で例外がスローされました") and "0xC0000005" in t[0] and t[1].startswith("STACK: #0") and not any(x.startswith("LAST_OUTPUT:") for x in t))
EN = "LAST_OUTPUT: Exception thrown at 0x00007FFB1ACD16D2 (ExtDll.dll) in App.exe: 0xC0000005: Access violation reading location 0x0000000000000000."
t = so.transform([EN] + FR, None)
check("EXCEPTION: made from the English VS line", t[0].startswith("EXCEPTION: Exception thrown at 0x00007FFB1ACD16D2") and not any(x.startswith("LAST_OUTPUT:") for x in t))
t = so.transform(["LAST_OUTPUT: Unhandled exception at 0x00007FF6A1B2C3D4 in App.exe: 0xC0000005: Access violation writing location 0x0000000000000010."] + FR, None)
check("EXCEPTION: made from an unhandled-exception line", t[0].startswith("EXCEPTION: Unhandled exception at"))
t = so.transform(["LAST_OUTPUT: Exception thrown at 0x00007FFB12345678 in App.exe: 0xE06D7363: Microsoft C++ exception: std::runtime_error at memory location 0x000000A1B2C3D4E5."] + FR, None)
check("EXCEPTION: also for a C++ exception code (0xE06D7363)", t[0].startswith("EXCEPTION: Exception thrown at"))
t = so.transform(["LAST_OUTPUT: 'App.exe' (Win32): 'C:\\Windows\\System32\\x.dll' が読み込まれました。含める/除外するの設定でシンボルの読み込みが無効になっています。"] + FR, None)
check("a last output line that is not an exception: no EXCEPTION:, and LAST_OUTPUT: is removed (no noise)", not any(x.startswith("EXCEPTION:") or x.startswith("LAST_OUTPUT:") for x in t) and t[0].startswith("STACK: #0"))
t = so.transform(["LAST_OUTPUT: value check: 0xDEADBEEF: ok"] + FR, None)
check("a line with a hex number between colons is not an exception unless it is an exception code (0xC.. 0xE.. 0x8..)", not any(x.startswith("EXCEPTION:") for x in t))
t = so.transform(["EXCEPTION: System.NullReferenceException 参照が...", JA] + FR, None)
check("an existing EXCEPTION: (managed) is kept and not duplicated; LAST_OUTPUT: is removed", [x for x in t if x.startswith("EXCEPTION:")] == ["EXCEPTION: System.NullReferenceException 参照が..."] and not any(x.startswith("LAST_OUTPUT:") for x in t))
t = so.transform([JA, "INSPECT_SKIP: the mode is design (not break)."], None)
check("without STACK lines an exception-like LAST_OUTPUT: still becomes EXCEPTION: (no STACK needed)", t[0].startswith("EXCEPTION: 0x00007FFB1ACD16D2"))
src = ["DIRTY: C:\\p\\a.cpp", "DIRTY_COUNT: 1"]
check("output without LAST_OUTPUT: is unchanged (regression)", so.transform(src, None) == src)
PY
while IFS= read -r l; do
    case "$l" in
        "ok "*) PASS=$((PASS+1)) ;;
        "FAIL "*) FAIL=$((FAIL+1)); echo "$l" ;;
        *) FAIL=$((FAIL+1)); echo "FAIL: python error: $l" ;;
    esac
done < "$T/py.out"

# ---- CLI
printf '\xef\xbb\xbfSTACK: #0 Lib::Run at z:\\nightly\\LibA\\a.cpp:9 [module=LibA.dll]\r\nSTACK: #1 App::Go at c:\\ws\\Sln\\a.cpp:12 [module=App.exe]\r\nSOLUTION: c:\\ws\\Sln\\Sln.slnx\r\n' > "$T/in.txt"
out="$(python3 -I "$SCRIPT" "$T/in.txt")"; rc=$?
ok "CLI: rc=0, BOM and CR are removed, the summary is printed" "$([ $rc = 0 ] && ! grep -q $'\r' <<<"$out" && ! head -c 3 <<<"$out" | grep -q $'\xef\xbb\xbf' && grep -qx 'OWNER: top=ext (frame #0)' <<<"$out" && grep -qx 'BOUNDARY: #1 ours -> ext #0' <<<"$out" && echo 1 || echo 0)"
out="$(python3 -I "$SCRIPT" "$T/none.txt")"; rc=$?
ok "CLI: a missing file prints nothing, rc=0" "$([ $rc = 0 ] && [ -z "$out" ] && echo 1 || echo 0)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
