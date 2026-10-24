#!/usr/bin/env bash
# cpp_pkg_test.sh - cpp_pkg.py (vcpkg.json / .vcxproj / ThirdParty.manifest の編集) を、疑似プロジェクトで検証する。
# Windows も vcpkg も不要。Usage: tests/cpp_pkg_test.sh      (最後に PASS/FAIL の件数。失敗があれば rc=1)
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/add-package/scripts/cpp_pkg.py"
T="${TMPDIR:-/tmp}/cpppkg_$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }
has() { grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
run() { python3 -I "$S" "$@"; }

# Visual Studio が作る形の .vcxproj (BOM 付き UTF-8 + CRLF)
make_vcxproj() {  # $1=パス
    mkdir -p "$(dirname "$1")"
    python3 - "$1" <<'PY'
import sys
t = '''<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup Label="ProjectConfigurations">
    <ProjectConfiguration Include="Debug|x64">
      <Configuration>Debug</Configuration>
      <Platform>x64</Platform>
    </ProjectConfiguration>
  </ItemGroup>
  <PropertyGroup Label="Globals">
    <VCProjectVersion>17.0</VCProjectVersion>
    <ProjectGuid>{11111111-2222-3333-4444-555555555555}</ProjectGuid>
    <RootNamespace>App</RootNamespace>
  </PropertyGroup>
  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.Default.props" />
  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Debug|x64'">
    <ClCompile>
      <WarningLevel>Level3</WarningLevel>
      <AdditionalIncludeDirectories>$(ProjectDir)include;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
    </ClCompile>
    <Link>
      <SubSystem>Windows</SubSystem>
    </Link>
  </ItemDefinitionGroup>
  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Release|x64'">
    <ClCompile>
      <WarningLevel>Level3</WarningLevel>
    </ClCompile>
  </ItemDefinitionGroup>
  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.targets" />
</Project>
'''
open(sys.argv[1], "wb").write(b"\xef\xbb\xbf" + t.replace("\n", "\r\n").encode("utf-8"))
PY
}

D="$T/MyApp"
mkdir -p "$D"; make_vcxproj "$D/MyApp/MyApp.vcxproj"; make_vcxproj "$D/MyAppTest/MyAppTest.vcxproj"; make_vcxproj "$D/gtest/gtest.vcxproj"
printf '# x\r\nbin/\r\n' > "$D/.gitignore"

# ---------------------------------------------------------------- setup
out="$(run setup "$D")"; rc=$?
ok "setup: rc=0" $([ $rc = 0 ] && echo 1 || echo 0)
ok "setup: vcpkg.json created with the folder name (lowercase)" "$([ "$(has "$out" 'created vcpkg.json')" = 1 ] && python3 -c "
import json,sys
d=json.load(open('$D/vcpkg.json')); sys.exit(0 if d['name']=='myapp' and d['dependencies']==[] and d['version']=='0.1.0' else 1)" && echo 1 || echo 0)"
ok "setup: MyApp and MyAppTest patched" "$([ "$(has "$out" 'patched MyApp/MyApp.vcxproj')" = 1 ] && [ "$(has "$out" 'patched MyAppTest/MyAppTest.vcxproj')" = 1 ] && echo 1 || echo 0)"
ok "setup: gtest (third-party static lib) is skipped" "$([ "$(has "$out" 'gtest')" = 0 ] && ! grep -q Vcpkg "$D/gtest/gtest.vcxproj" && echo 1 || echo 0)"
ok "setup: manifest + static-md triplets for x64 / Win32 / ARM64" "$(f="$D/MyApp/MyApp.vcxproj"; [ "$(grep -c 'VcpkgEnableManifest>true' "$f")" = 1 ] && grep -q "'\$(Platform)'=='x64'\">x64-windows-static-md<" "$f" && grep -q "=='Win32'\">x86-windows-static-md<" "$f" && grep -q "=='ARM64'\">arm64-windows-static-md<" "$f" && echo 1 || echo 0)"
ok "setup: the block comes right after the Globals group (before the first Import)" "$(python3 - "$D/MyApp/MyApp.vcxproj" <<'PY' && echo 1 || echo 0
import sys,re
t=open(sys.argv[1],encoding='utf-8-sig').read()
sys.exit(0 if t.index('Label="Globals"') < t.index('Label="Vcpkg"') < t.index('<Import Project') else 1)
PY
)"
ok "setup: BOM and CRLF kept (no lone LF)" "$(f="$D/MyApp/MyApp.vcxproj"; [ "$(head -c3 "$f" | xxd -p)" = efbbbf ] && [ "$(grep -vc $'\r$' "$f")" = 0 ] && echo 1 || echo 0)"
ok "setup: the patched file is still well-formed XML" "$(python3 -c "
import xml.etree.ElementTree as ET; ET.parse('$D/MyApp/MyApp.vcxproj')" && echo 1 || echo 0)"
ok "setup: .gitignore gets vcpkg_installed/ (CRLF kept)" "$([ "$(grep -c '^vcpkg_installed/' "$D/.gitignore")" = 1 ] && [ "$(grep -vc $'\r$' "$D/.gitignore")" = 0 ] && echo 1 || echo 0)"
before="$(find "$D" -type f -exec md5sum {} + | sort | md5sum)"
out="$(run setup "$D")"
after="$(find "$D" -type f -exec md5sum {} + | sort | md5sum)"
ok "setup: idempotent (second run changes nothing)" "$([ "$before" = "$after" ] && [ "$(has "$out" 'kept    MyApp/MyApp.vcxproj')" = 1 ] && echo 1 || echo 0)"

D2="$T/Dyn"; mkdir -p "$D2"; make_vcxproj "$D2/A/A.vcxproj"; make_vcxproj "$D2/B/B.vcxproj"
out="$(run setup "$D2" --linkage dynamic --project A)"
ok "setup --linkage dynamic --project A: only A, triplet x64-windows" "$([ "$(has "$out" 'patched A/A.vcxproj')" = 1 ] && ! grep -q Vcpkg "$D2/B/B.vcxproj" && grep -q '>x64-windows</VcpkgTriplet>' "$D2/A/A.vcxproj" && echo 1 || echo 0)"
mkdir -p "$T/Empty"; out="$(run setup "$T/Empty")"; rc=$?
ok "setup: no .vcxproj -> rc=1" "$([ $rc = 1 ] && [ "$(has "$out" 'no .vcxproj')" = 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- add / remove / list
out="$(run add "$D" fmt)"; rc=$?
ok "add: rc=0, string dependency" "$([ $rc = 0 ] && [ "$(has "$out" 'added fmt')" = 1 ] && python3 -c "
import json,sys; sys.exit(0 if json.load(open('$D/vcpkg.json'))['dependencies']==['fmt'] else 1)" && echo 1 || echo 0)"
ok "add: warns that there is no builtin-baseline yet" "$(has "$out" 'no builtin-baseline yet')"
run add "$D" fmt >/dev/null
ok "add: idempotent (still one fmt)" "$(python3 -c "
import json,sys; sys.exit(0 if json.load(open('$D/vcpkg.json'))['dependencies']==['fmt'] else 1)" && echo 1 || echo 0)"
run add "$D" boost-asio --features ssl --version-ge 1.84.0 >/dev/null
run add "$D" fmt --features foo >/dev/null
ok "add: object form with features and version>=; existing string upgraded to object" "$(python3 -c "
import json,sys
d=json.load(open('$D/vcpkg.json'))['dependencies']
a=[x for x in d if isinstance(x,dict) and x['name']=='boost-asio'][0]
f=[x for x in d if isinstance(x,dict) and x['name']=='fmt'][0]
sys.exit(0 if a['features']==['ssl'] and a['version>=']=='1.84.0' and f['features']==['foo'] else 1)" && echo 1 || echo 0)"
out="$(run list "$D")"
ok "list: shows dependencies with features / version" "$([ "$(has "$out" 'boost-asio  (features=ssl; version>=1.84.0)')" = 1 ] && [ "$(has "$out" 'baseline: (none)')" = 1 ] && echo 1 || echo 0)"
out="$(run add "$D" 'Bad_Name')"; rc=$?
ok "add: invalid port name -> rc=2" "$([ $rc = 2 ] && [ "$(has "$out" 'BAD_ARGS')" = 1 ] && echo 1 || echo 0)"
out="$(run add "$D" fmt --features 'a;b')"; rc=$?
ok "add: invalid feature -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
out="$(run remove "$D" fmt)"; rc=$?
ok "remove: rc=0" "$([ $rc = 0 ] && ! python3 -c "
import json,sys; sys.exit(0 if any((x if isinstance(x,str) else x['name'])=='fmt' for x in json.load(open('$D/vcpkg.json'))['dependencies']) else 1)" && echo 1 || echo 0)"
out="$(run remove "$D" fmt)"; rc=$?
ok "remove: absent port -> rc=1" "$([ $rc = 1 ] && echo 1 || echo 0)"
out="$(run add "$T/Empty" fmt)"; rc=$?
ok "add: no vcpkg.json -> rc=1 with the setup hint" "$([ $rc = 1 ] && [ "$(has "$out" 'cpp_pkg.py setup')" = 1 ] && echo 1 || echo 0)"
# builtin-baseline を、vcpkg が足した後でも、保たれる
python3 - "$D/vcpkg.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["builtin-baseline"] = "a" * 40; json.dump(d, open(p, "w"), indent=2)
PY
run add "$D" zlib >/dev/null
ok "add: builtin-baseline (written by vcpkg) is kept; no warning" "$(python3 -c "
import json,sys; sys.exit(0 if json.load(open('$D/vcpkg.json'))['builtin-baseline']=='a'*40 else 1)" && [ "$(has "$(run add "$D" zlib)" 'no builtin-baseline')" = 0 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- include-dir
P="$D/MyApp/MyApp.vcxproj"
out="$(run include-dir "$P" '$(SolutionDir)ThirdParty\json')"; rc=$?
ok "include-dir: rc=0, both configurations changed" "$([ $rc = 0 ] && [ "$(has "$out" '2 of 2 configurations changed')" = 1 ] && echo 1 || echo 0)"
ok "include-dir: prepended to the existing value (Debug) and created before other children (Release)" "$(python3 - "$P" <<'PY' && echo 1 || echo 0
import sys,re
t=open(sys.argv[1],encoding='utf-8-sig').read()
vals=re.findall(r'<AdditionalIncludeDirectories>(.*?)</AdditionalIncludeDirectories>',t)
sys.exit(0 if vals==[r'$(SolutionDir)ThirdParty\json;$(ProjectDir)include;%(AdditionalIncludeDirectories)', r'$(SolutionDir)ThirdParty\json;%(AdditionalIncludeDirectories)'] else 1)
PY
)"
ok "include-dir: BOM / CRLF kept, XML still well-formed" "$([ "$(head -c3 "$P" | xxd -p)" = efbbbf ] && [ "$(grep -vc $'\r$' "$P")" = 0 ] && python3 -c "
import xml.etree.ElementTree as ET; ET.parse('$P')" && echo 1 || echo 0)"
before="$(md5sum "$P")"; out="$(run include-dir "$P" '$(SolutionDir)ThirdParty\json')"
ok "include-dir: idempotent" "$([ "$before" = "$(md5sum "$P")" ] && [ "$(has "$out" 'already present')" = 1 ] && echo 1 || echo 0)"
out="$(run include-dir "$P" 'a;b')"; rc=$?
ok "include-dir: a path with ';' is rejected -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
out="$(run include-dir "$D/vcpkg.json" 'x')"; rc=$?
ok "include-dir: not a .vcxproj -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- record-fetch
out="$(run record-fetch "$D" nlohmann/json v3.11.3 json single_include)"; rc=$?
ok "record-fetch: rc=0, manifest line + .gitignore" "$([ $rc = 0 ] && grep -qx 'fetch nlohmann/json v3.11.3 json single_include' "$D/ThirdParty.manifest" && grep -q '^ThirdParty/json/' "$D/.gitignore" && echo 1 || echo 0)"
run record-fetch "$D" nlohmann/json v3.12.0 json single_include >/dev/null
run record-fetch "$D" fmtlib/fmt 11.0.2 fmt >/dev/null
ok "record-fetch: same name is replaced, others kept (2 fetch lines)" "$([ "$(grep -c '^fetch ' "$D/ThirdParty.manifest")" = 2 ] && grep -qx 'fetch nlohmann/json v3.12.0 json single_include' "$D/ThirdParty.manifest" && ! grep -q v3.11.3 "$D/ThirdParty.manifest" && echo 1 || echo 0)"
ok "record-fetch: .gitignore entry is not duplicated" "$([ "$(grep -c '^ThirdParty/json/' "$D/.gitignore")" = 1 ] && echo 1 || echo 0)"
out="$(run record-fetch "$D" 'bad repo' v1 x)"; rc=$?
ok "record-fetch: invalid repo -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
out="$(run record-fetch "$D" a/b v1 x '../etc')"; rc=$?
ok "record-fetch: '..' in the subfolder -> rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
ok "record-fetch: the manifest can be replayed with package_once.sh --file (every line is a valid operation)" "$(
    python3 - "$D/ThirdParty.manifest" <<'PY' && echo 1 || echo 0
import re, sys
for ln in open(sys.argv[1]):
    ln = ln.strip()
    if not ln or ln.startswith("#"):
        continue
    t = ln.split()
    assert t[0] == "fetch" and len(t) in (4, 5), ln
PY
)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
