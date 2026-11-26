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
