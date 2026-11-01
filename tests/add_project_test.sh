#!/usr/bin/env bash
# add_project_test.sh - add_project.py (.NET のクラスライブラリ + MSTest プロジェクトの追加) を、疑似ソリューションで検証する。
# Windows も .NET も不要。.slnx と .sln (Visual Studio 形式) の両方。Usage: tests/add_project_test.sh
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AP="$ROOT/skills/csharp-test-first/scripts/add_project.py"
NS="$ROOT/skills/new-solution/scripts/new_solution.py"
T="${TMPDIR:-/tmp}/addproj_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
bom_crlf() { [ "$(head -c3 "$1" | xxd -p)" = efbbbf ] && [ "$(grep -vc $'\r$' "$1")" = 0 ]; }
wellformed() { python3 -c "import xml.etree.ElementTree as ET,sys; ET.parse(sys.argv[1])" "$1" 2>/dev/null; }

# ---------------------------------------------------------------- .slnx
D="$T/App"; mkdir -p "$D"
python3 "$NS" "$D" --type wpf --layers none --tests none >/dev/null
out="$(python3 "$AP" "$D" DataLayer --kind data)"; rc=$?
ok "slnx: DataLayer + DataLayer.Tests added (rc=0)" "$([ $rc = 0 ] && [ -f "$D/DataLayer/DataLayer.csproj" ] && [ -f "$D/DataLayer.Tests/DataLayer.Tests.csproj" ] && echo 1 || echo 0)"
ok "slnx: namespace = <solution>.Data (kind data)" "$([ "$(has "$out" '名前空間       : App.Data')" = 1 ] && grep -q 'namespace App.Data;' "$D/DataLayer/DataLayerInfo.cs" && grep -q 'namespace App.Data.Tests;' "$D/DataLayer.Tests/DataLayerInfoTests.cs" && echo 1 || echo 0)"
ok "slnx: both projects registered, startup mark untouched" "$([ "$(grep -c '<Project Path=' "$D/App.slnx")" = 3 ] && grep -q 'DataLayer/DataLayer.csproj' "$D/App.slnx" && grep -q 'DataLayer.Tests/DataLayer.Tests.csproj' "$D/App.slnx" && grep -q 'App/App.csproj" Id="[0-9a-f-]*" DefaultStartup="true"' "$D/App.slnx" && echo 1 || echo 0)"
ok "files are BOM + CRLF (cs / csproj) and csproj is well-formed XML" "$(bom_crlf "$D/DataLayer/DataLayer.csproj" && bom_crlf "$D/DataLayer/DataLayerInfo.cs" && bom_crlf "$D/DataLayer.Tests/DataLayerInfoTests.cs" && wellformed "$D/DataLayer.Tests/DataLayer.Tests.csproj" && echo 1 || echo 0)"
ok "test project: MSTest packages pinned, IsTestProject, reference to the library" "$(f="$D/DataLayer.Tests/DataLayer.Tests.csproj"; grep -q 'Microsoft.NET.Test.Sdk" Version="17.12.0"' "$f" && grep -q 'MSTest.TestAdapter" Version="3.6.4"' "$f" && grep -q 'MSTest.TestFramework" Version="3.6.4"' "$f" && grep -q '<IsTestProject>true' "$f" && grep -q '..\\DataLayer\\DataLayer.csproj' "$f" && echo 1 || echo 0)"
ok "library csproj has no WPF (no UseWPF) and the default TFM net10.0" "$(f="$D/DataLayer/DataLayer.csproj"; ! grep -q UseWPF "$f" && grep -q '<TargetFramework>net10.0</TargetFramework>' "$f" && echo 1 || echo 0)"

python3 "$AP" "$D" LogicLayer --kind logic --uses DataLayer >/dev/null
ok "--uses: ProjectReference to DataLayer" "$(grep -q '..\\DataLayer\\DataLayer.csproj' "$D/LogicLayer/LogicLayer.csproj" && echo 1 || echo 0)"
out="$(python3 "$AP" "$D" Bad --uses NoSuch)"; rc=$?
ok "--uses with a missing project -> rc=2, nothing written" "$([ $rc = 2 ] && [ ! -d "$D/Bad" ] && echo 1 || echo 0)"
before="$(cd "$D" && find . -type f -exec md5sum {} + | sort | md5sum)"
out="$(python3 "$AP" "$D" LogicLayer)"; rc=$?
ok "existing project -> rc=3, nothing changed" "$([ $rc = 3 ] && [ "$before" = "$(cd "$D" && find . -type f -exec md5sum {} + | sort | md5sum)" ] && echo 1 || echo 0)"
out="$(python3 "$AP" "$D" Orphan --tests none)"
ok "--tests none: library only" "$([ -f "$D/Orphan/Orphan.csproj" ] && [ ! -d "$D/Orphan.Tests" ] && [ "$(grep -c '<Project Path=' "$D/App.slnx")" = 6 ] && echo 1 || echo 0)"
out="$(python3 "$AP" "$D" Orphan --tests-only)"; rc=$?
ok "--tests-only: adds Orphan.Tests, namespace read from the csproj" "$([ $rc = 0 ] && [ -f "$D/Orphan.Tests/Orphan.Tests.csproj" ] && grep -q 'RootNamespace>App.Orphan.Tests<' "$D/Orphan.Tests/Orphan.Tests.csproj" && echo 1 || echo 0)"
out="$(python3 "$AP" "$D" Orphan --tests-only)"; rc=$?
ok "--tests-only again -> rc=3" "$([ $rc = 3 ] && echo 1 || echo 0)"

python3 "$AP" "$D" ViewModels --kind viewmodel --uses LogicLayer --tests none >/dev/null
python3 "$AP" "$D" ViewModels --tests-only >/dev/null
ok "viewmodel kind: base classes + MainViewModel, and --tests-only detects it (MainViewModelTests.cs)" "$([ -f "$D/ViewModels/ObservableObject.cs" ] && [ -f "$D/ViewModels/RelayCommand.cs" ] && [ -f "$D/ViewModels/MainViewModel.cs" ] && [ -f "$D/ViewModels.Tests/MainViewModelTests.cs" ] && grep -q 'namespace App.ViewModels;' "$D/ViewModels/MainViewModel.cs" && echo 1 || echo 0)"

python3 "$AP" "$D" Net10 --tfm net10.0 --mstest-version 3.9.0 --testsdk-version 17.14.0 >/dev/null
ok "--tfm / --mstest-version / --testsdk-version are applied" "$(grep -q 'net10.0</TargetFramework>' "$D/Net10/Net10.csproj" && grep -q 'MSTest.TestFramework" Version="3.9.0"' "$D/Net10.Tests/Net10.Tests.csproj" && grep -q 'Microsoft.NET.Test.Sdk" Version="17.14.0"' "$D/Net10.Tests/Net10.Tests.csproj" && echo 1 || echo 0)"

out="$(python3 "$AP" "$D" DryRun --dry-run)"
ok "--dry-run: lists files, writes nothing" "$([ "$(has "$out" 'dry-run')" = 1 ] && [ ! -d "$D/DryRun" ] && echo 1 || echo 0)"
out="$(python3 "$AP" "$D" 'Bad-Name')"; rc=$?
ok "invalid project name -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
mkdir -p "$T/none"; out="$(python3 "$AP" "$T/none" X)"; rc=$?
ok "no solution -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
mkdir -p "$T/two"; touch "$T/two/a.slnx" "$T/two/b.sln"; out="$(python3 "$AP" "$T/two" X)"; rc=$?
ok "two solutions -> rc=2 (ask the user which)" "$([ $rc = 2 ] && [ "$(has "$out" '複数ある')" = 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- .sln (Visual Studio 形式)
S="$T/Sln"; mkdir -p "$S/App"
cat > "$S/App/App.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net10.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
  </PropertyGroup>
</Project>
XML
python3 - "$S/Sln.sln" <<'PY'
import sys
g = "{11111111-1111-1111-1111-111111111111}"
t = f'''
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project("{{9A19103F-16F7-4668-BE54-9A1E7A4F7556}}") = "App", "App\\App.csproj", "{g}"
EndProject
Global
\tGlobalSection(SolutionConfigurationPlatforms) = preSolution
\t\tDebug|Any CPU = Debug|Any CPU
\t\tDebug|x64 = Debug|x64
\t\tRelease|Any CPU = Release|Any CPU
\t\tRelease|x64 = Release|x64
\tEndGlobalSection
\tGlobalSection(ProjectConfigurationPlatforms) = postSolution
\t\t{g}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
\t\t{g}.Debug|Any CPU.Build.0 = Debug|Any CPU
\t\t{g}.Debug|x64.ActiveCfg = Debug|Any CPU
\t\t{g}.Debug|x64.Build.0 = Debug|Any CPU
\t\t{g}.Release|Any CPU.ActiveCfg = Release|Any CPU
\t\t{g}.Release|Any CPU.Build.0 = Release|Any CPU
\t\t{g}.Release|x64.ActiveCfg = Release|Any CPU
\t\t{g}.Release|x64.Build.0 = Release|Any CPU
\tEndGlobalSection
\tGlobalSection(SolutionProperties) = preSolution
\t\tHideSolutionNode = FALSE
\tEndGlobalSection
EndGlobal
'''
open(sys.argv[1], "wb").write(b"\xef\xbb\xbf" + t.lstrip("\n").replace("\n", "\r\n").encode("utf-8"))
PY
python3 "$AP" "$S" LogicLayer --kind logic >/dev/null; rc=$?
SLN="$S/Sln.sln"
ok "sln: rc=0, Project lines with the SDK-style C# type GUID for both projects" "$([ $rc = 0 ] && [ "$(grep -c 'Project("{9A19103F-16F7-4668-BE54-9A1E7A4F7556}") = "' "$SLN")" = 3 ] && grep -q '"LogicLayer", "LogicLayer\\LogicLayer.csproj"' "$SLN" && grep -q '"LogicLayer.Tests", "LogicLayer.Tests\\LogicLayer.Tests.csproj"' "$SLN" && echo 1 || echo 0)"
ok "sln: every solution configuration (Any CPU and x64) is mapped to the project's Any CPU (4 configs x 2 lines x 2 projects)" "$(python3 - "$SLN" <<'PY' && echo 1 || echo 0
import re, sys
t = open(sys.argv[1], encoding="utf-8-sig").read()
sec = t.split("GlobalSection(ProjectConfigurationPlatforms)")[1].split("EndGlobalSection")[0]
new = [l for l in sec.splitlines() if "11111111" not in l and "ActiveCfg" in l or ("Build.0" in l and "11111111" not in l)]
ok = len(new) == 16 and all(re.search(r"= (Debug|Release)\|Any CPU$", l.strip()) for l in new)
ok = ok and any("Debug|x64.ActiveCfg = Debug|Any CPU" in l for l in new)
sys.exit(0 if ok else 1)
PY
)"
ok "sln: BOM and CRLF kept, the original project untouched" "$([ "$(head -c3 "$SLN" | xxd -p)" = efbbbf ] && [ "$(grep -vc $'\r$' "$SLN")" = 0 ] && grep -c 'App\\App.csproj' "$SLN" | grep -q 1 && echo 1 || echo 0)"
ok "sln: the new projects sit before the Global section" "$(python3 - "$SLN" <<'PY' && echo 1 || echo 0
import sys
t = open(sys.argv[1], encoding="utf-8-sig").read()
sys.exit(0 if t.rindex("EndProject") < t.index("\nGlobal") else 1)
PY
)"

# ---------------------------------------------------------------- ひな形と定数の一致 / 構文
for f in .editorconfig Directory.Build.props; do
    ok "templates/dotnet/$f is identical to the generated one" "$(python3 - "$AP" "$ROOT/templates/dotnet/$f" "$f" <<'PY' && echo 1 || echo 0
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ap", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
const = m.EDITORCONFIG if sys.argv[3] == ".editorconfig" else m.DIRECTORY_BUILD_PROPS
sys.exit(0 if open(sys.argv[2], encoding="utf-8", newline="").read() == const else 1)
PY
)"
done

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
