#!/usr/bin/env python3
"""cpp_pkg.py - C++ のパッケージ (vcpkg のマニフェスト、ThirdParty のソース) の、ファイルの編集をする。

Usage:
  cpp_pkg.py setup <dir> [--linkage static-md|dynamic|static] [--project <名前>]... [--name <vcpkg の名前>]
  cpp_pkg.py add <dir> <ポート> [--features a,b] [--version-ge V]
  cpp_pkg.py remove <dir> <ポート>
  cpp_pkg.py list <dir>
  cpp_pkg.py include-dir <プロジェクト.vcxproj> <パス>
  cpp_pkg.py record-fetch <dir> <owner/repo> <タグ> <名前> [<サブフォルダ>]

ホスト側 (Windows) を呼ばずに、WSL で完結する、決まったファイルの編集だけを行う。ネットワークは使わない。
取得・ビルド (vcpkg install / fetch) は、ウォッチャー経由 (package_once.sh)。

  setup          <dir>/vcpkg.json を作り (なければ)、<dir> 以下の .vcxproj に、vcpkg のマニフェストモードの設定を足す
                 (VcpkgEnableManifest と、プラットフォーム別のトリプレット。既定は static-md = 静的ライブラリ + 動的 CRT /MD)。
                 gtest (ThirdParty のソースの静的ライブラリ) は、除く。--project で、対象を限る。
                 vcpkg 方式の GoogleTest (add_layer.py / new_solution.py が作るテスト exe) は、設定済みなので、飛ばす。.gitignore に vcpkg_installed/ を足す。
                 何度実行しても、同じ結果 (設定のあるプロジェクトは、飛ばす)。
  add / remove   vcpkg.json の dependencies を、足す / 消す。ポート名の実在は、確認しない (vcpkg install が確認する)。
  include-dir    .vcxproj の、すべての構成の AdditionalIncludeDirectories に、パスを足す (ThirdParty のヘッダー用)。
  record-fetch   fetch した内容を、ThirdParty.manifest (コミットする。別の PC で、再現できる) に記録し、.gitignore に
                 ThirdParty/<名前>/ を足す。

ファイルの文字コード (BOM) と改行は、保つ。終了コード: 0 = 成功 / 1 = 失敗 (内容の問題) / 2 = 引数が不正。
"""
import argparse
import json
import os
import re
import sys

SKIP_DIRS = {".git", ".vs", "bin", "obj", "packages", "node_modules", "ThirdParty", "vcpkg_installed", ".claude-logs",
             "x64", "x86", "Win32", "ARM64", "Debug", "Release"}
RE_PORT = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$")
RE_VER = re.compile(r"^[0-9][0-9A-Za-z.+-]{0,63}$")
RE_REPO = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$")
RE_TAG = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
RE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
RE_SEG = re.compile(r"^[A-Za-z0-9._-]+$")
RE_INC = re.compile(r"^[A-Za-z0-9$()_.\\/ -]+$")
LINKAGE = {"static-md": "-windows-static-md", "dynamic": "-windows", "static": "-windows-static"}
SCHEMA = "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json"


def die(msg, rc=1):
    print(msg)
    sys.exit(rc)


# ------------------------------------------------------------------ ファイルの入出力 (BOM と改行を保つ)
def read_keep(path):
    b = open(path, "rb").read()
    bom = b[:3] == b"\xef\xbb\xbf"
    text = (b[3:] if bom else b).decode("utf-8")
    nl = "\r\n" if "\r\n" in text else "\n"
    return text.replace("\r\n", "\n"), bom, nl


def write_keep(path, text, bom, nl):
    data = text.replace("\n", nl).encode("utf-8")
    open(path, "wb").write((b"\xef\xbb\xbf" if bom else b"") + data)


def add_gitignore(d, entry):
    """.gitignore に、行を足す (なければ作る。すでにあれば、何もしない)。戻り値: 足したら True"""
    p = os.path.join(d, ".gitignore")
    if os.path.exists(p):
        text, bom, nl = read_keep(p)
        if entry in [ln.strip() for ln in text.split("\n")]:
            return False
        if text and not text.endswith("\n"):
            text += "\n"
        write_keep(p, text + entry + "\n", bom, nl)
    else:
        write_keep(p, entry + "\n", False, "\n")
    return True


def find_vcxprojs(d):
    out = []
    for cur, ds, fs in os.walk(d):
        ds[:] = [x for x in ds if x not in SKIP_DIRS and not x.startswith(".")]
        out += [os.path.join(cur, f) for f in fs if f.lower().endswith(".vcxproj")]
    return sorted(out)


# ------------------------------------------------------------------ setup
def vcpkg_block(linkage, indent, nl):
    suf = LINKAGE[linkage]
    lines = [f'{indent}<PropertyGroup Label="Vcpkg">',
             f"{indent}  <VcpkgEnableManifest>true</VcpkgEnableManifest>",
             f"{indent}  <VcpkgTriplet Condition=\"'$(Platform)'=='x64'\">x64{suf}</VcpkgTriplet>",
             f"{indent}  <VcpkgTriplet Condition=\"'$(Platform)'=='Win32'\">x86{suf}</VcpkgTriplet>",
             f"{indent}  <VcpkgTriplet Condition=\"'$(Platform)'=='ARM64'\">arm64{suf}</VcpkgTriplet>",
             f"{indent}</PropertyGroup>"]
    return nl.join(lines)


# ポートごとに、MSVC で必要な前処理定義 (実機で判明: fmt は /utf-8 が無いと C2338)。
# /utf-8 は、ソースが CP932 だと文字化けするので、使わない。
PORT_DEFINES = {"fmt": ["FMT_UNICODE=0"]}
DEFINES_RE = re.compile(r'[ \t]*<ItemDefinitionGroup Label="VcpkgDefines">.*?</ItemDefinitionGroup>[ \t]*\n?', re.S)


def sync_defines(d, manifest):
    """vcpkg.json の依存に合わせて、Vcpkg 設定済みの各 .vcxproj の VcpkgDefines を作り直す。"""
    want = []
    for dep in manifest.get("dependencies", []):
        for x in PORT_DEFINES.get(dep_name(dep), []):
            if x not in want:
                want.append(x)
    for p in find_vcxprojs(d):
        text, bom, nl = read_keep(p)
        if "VcpkgEnableManifest" not in text:
            continue
        new = DEFINES_RE.sub("", text)
        if want and "</Project>" in new:
            block = ('  <ItemDefinitionGroup Label="VcpkgDefines">\n    <ClCompile>\n'
                     f'      <PreprocessorDefinitions>{";".join(want)};%(PreprocessorDefinitions)</PreprocessorDefinitions>\n'
                     '    </ClCompile>\n  </ItemDefinitionGroup>\n')
            i = new.rindex("</Project>")
            new = new[:i] + block + new[i:]
        if new != text:
            write_keep(p, new, bom, nl)
            print(f"defines {os.path.relpath(p, d).replace(os.sep, '/')}: {';'.join(want) or '(none)'}")


def cmd_setup(a):
    d = os.path.abspath(a.dir)
    if not os.path.isdir(d):
        die(f"BAD_ARGS: not a directory: {a.dir}", 2)
    projs = find_vcxprojs(d)
    if a.project:
        projs = [p for p in projs if os.path.splitext(os.path.basename(p))[0] in set(a.project)]
    else:
        projs = [p for p in projs if os.path.splitext(os.path.basename(p))[0].lower() != "gtest"]
    if not projs:
        die("no .vcxproj to set up (gtest is excluded; pass --project <name>)")
    manifest = os.path.join(d, "vcpkg.json")
    created = False
    if not os.path.exists(manifest):
        name = a.name or re.sub(r"[^a-z0-9-]+", "-", os.path.basename(d).lower()).strip("-") or "app"
        if not RE_PORT.match(name):
            die(f"invalid vcpkg name: {name} (lowercase letters, digits, hyphens)", 2)
        save_manifest(manifest, {"$schema": SCHEMA, "name": name, "version": "0.1.0", "dependencies": []})
        created = True
    print(("created " if created else "kept    ") + "vcpkg.json")
    for p in projs:
        text, bom, nl = read_keep(p)
        rel = os.path.relpath(p, d).replace(os.sep, "/")
        if "VcpkgEnableManifest" in text:
            print(f"kept    {rel} (already has VcpkgEnableManifest)")
            continue
        m = re.search(r'([ \t]*)<PropertyGroup Label="Globals"[^>]*>.*?</PropertyGroup>', text, re.S)
        if not m:
            print(f"SKIPPED {rel} (no <PropertyGroup Label=\"Globals\">)")
            continue
        block = vcpkg_block(a.linkage, m.group(1), "\n")
        text = text[:m.end()] + "\n" + block + text[m.end():]
        write_keep(p, text, bom, nl)
        print(f"patched {rel} (triplet: {a.linkage})")
    sync_defines(d, load_manifest(d)[1])
    if add_gitignore(d, "vcpkg_installed/"):
        print("added   vcpkg_installed/ to .gitignore")
    print("next: package_once.sh <dir> --timeout 1800 'vcpkg baseline' 'vcpkg install'  (baseline once; install builds the ports)")
    return 0


# ------------------------------------------------------------------ add / remove / list
def load_manifest(d):
    p = os.path.join(os.path.abspath(d), "vcpkg.json")
    if not os.path.exists(p):
        die(f"vcpkg.json not found in {d} (run: cpp_pkg.py setup {d})")
    try:
        return p, json.load(open(p, encoding="utf-8-sig"))
    except json.JSONDecodeError as e:
        die(f"vcpkg.json is not valid JSON: {e}")


def save_manifest(p, data):
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def dep_name(dep):
    return dep if isinstance(dep, str) else dep.get("name")


def cmd_add(a):
    if not RE_PORT.match(a.port):
        die(f"BAD_ARGS: invalid port name: {a.port} (lowercase letters, digits, hyphens)", 2)
    feats = [f for f in (a.features.split(",") if a.features else []) if f]
    for f in feats:
        if not RE_PORT.match(f):
            die(f"BAD_ARGS: invalid feature name: {f}", 2)
    if a.version_ge and not RE_VER.match(a.version_ge):
        die(f"BAD_ARGS: invalid version: {a.version_ge}", 2)
    p, data = load_manifest(a.dir)
    deps = data.setdefault("dependencies", [])
    cur = next((x for x in deps if dep_name(x) == a.port), None)
    if cur is not None and not feats and not a.version_ge:
        print(f"already present: {a.port}")
        return 0
    if cur is None and not feats and not a.version_ge:
        deps.append(a.port)
        what = "added"
    else:
        obj = {"name": a.port} if cur is None else ({"name": cur} if isinstance(cur, str) else dict(cur))
        if feats:
            obj["features"] = sorted(set(obj.get("features", [])) | set(feats))
        if a.version_ge:
            obj["version>="] = a.version_ge
        if cur is None:
            deps.append(obj)
            what = "added"
        else:
            deps[deps.index(cur)] = obj
            what = "updated"
    save_manifest(p, data)
    sync_defines(os.path.dirname(p), data)
    note = "" if data.get("builtin-baseline") else "  (no builtin-baseline yet: run 'vcpkg baseline' via package_once.sh)"
    print(f"{what} {a.port} in vcpkg.json{note}")
    return 0


def cmd_remove(a):
    if not RE_PORT.match(a.port):
        die(f"BAD_ARGS: invalid port name: {a.port}", 2)
    p, data = load_manifest(a.dir)
    deps = data.get("dependencies", [])
    keep = [x for x in deps if dep_name(x) != a.port]
    if len(keep) == len(deps):
        die(f"{a.port} is not in vcpkg.json")
    data["dependencies"] = keep
    save_manifest(p, data)
    sync_defines(os.path.dirname(p), data)
    print(f"removed {a.port} from vcpkg.json")
    return 0


def cmd_list(a):
    p, data = load_manifest(a.dir)
    print(f"name: {data.get('name')}  baseline: {data.get('builtin-baseline', '(none)')}")
    for x in data.get("dependencies", []):
        if isinstance(x, str):
            print(f"  {x}")
        else:
            extra = []
            if x.get("features"):
                extra.append("features=" + ",".join(x["features"]))
            if x.get("version>="):
                extra.append("version>=" + x["version>="])
            print(f"  {x.get('name')}" + (f"  ({'; '.join(extra)})" if extra else ""))
    return 0


# ------------------------------------------------------------------ include-dir
def cmd_include_dir(a):
    if not RE_INC.match(a.path):
        die(f"BAD_ARGS: invalid path (letters, digits, $ ( ) _ . \\ / space -): {a.path}", 2)
    if not os.path.isfile(a.project) or not a.project.lower().endswith(".vcxproj"):
        die(f"BAD_ARGS: not a .vcxproj: {a.project}", 2)
    text, bom, nl = read_keep(a.project)
    norm = lambda s: s.strip().replace("/", "\\").rstrip("\\").lower()
    changed, groups = 0, 0

    def fix_group(m):
        nonlocal changed, groups
        body = m.group(0)
        cm = re.search(r"([ \t]*)<ClCompile>(.*?)</ClCompile>", body, re.S)
        if not cm:
            return body
        groups += 1
        inner = cm.group(2)
        am = re.search(r"<AdditionalIncludeDirectories>(.*?)</AdditionalIncludeDirectories>", inner, re.S)
        if am:
            parts = [x for x in am.group(1).split(";") if x.strip()]
            if any(norm(x) == norm(a.path) for x in parts):
                return body
            new_inner = inner[:am.start(1)] + a.path + ";" + am.group(1) + inner[am.end(1):]
        else:
            child = re.search(r"\n([ \t]+)<", inner)
            ind = child.group(1) if child else cm.group(1) + "  "
            new_inner = f"\n{ind}<AdditionalIncludeDirectories>{a.path};%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>" + inner
        changed += 1
        new_cl = cm.group(1) + "<ClCompile>" + new_inner + "</ClCompile>"
        return body[:cm.start()] + new_cl + body[cm.end():]

    new = re.sub(r"<ItemDefinitionGroup\b.*?</ItemDefinitionGroup>", fix_group, text, flags=re.S)
    if groups == 0:
        die("no <ItemDefinitionGroup> with <ClCompile> found in the project")
    if changed:
        write_keep(a.project, new, bom, nl)
    print(f"include-dir {a.path}: {changed} of {groups} configurations changed" + ("" if changed else " (already present)"))
    return 0


# ------------------------------------------------------------------ record-fetch
def cmd_record_fetch(a):
    if not (RE_REPO.match(a.repo) and RE_TAG.match(a.tag) and RE_NAME.match(a.name)):
        die(f"BAD_ARGS: invalid repo / tag / name: {a.repo} {a.tag} {a.name}", 2)
    if a.sub:
        for seg in a.sub.replace("\\", "/").split("/"):
            if not RE_SEG.match(seg) or seg in (".", ".."):
                die(f"BAD_ARGS: invalid subfolder: {a.sub}", 2)
    d = os.path.abspath(a.dir)
    p = os.path.join(d, "ThirdParty.manifest")
    line = f"fetch {a.repo} {a.tag} {a.name}" + (f" {a.sub}" if a.sub else "")
    lines = []
    if os.path.exists(p):
        text, bom, nl = read_keep(p)
        lines = text.split("\n")
    else:
        bom, nl = False, "\n"
        lines = ["# ThirdParty のソース (fetch の記録)。別の PC では: package_once.sh <dir> --file ThirdParty.manifest"]
    lines = [ln for ln in lines if ln != ""]
    kept = [ln for ln in lines if not re.match(rf"^fetch \S+ \S+ {re.escape(a.name)}(\s|$)", ln)]
    replaced = len(kept) != len(lines)
    write_keep(p, "\n".join(kept + [line]) + "\n", bom, nl)
    added = add_gitignore(d, f"ThirdParty/{a.name}/")
    print(("updated " if replaced else "recorded ") + line + " in ThirdParty.manifest" + ("; added ThirdParty/%s/ to .gitignore" % a.name if added else ""))
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("setup"); s.add_argument("dir"); s.add_argument("--linkage", choices=list(LINKAGE), default="static-md")
    s.add_argument("--project", action="append", default=[]); s.add_argument("--name")
    s = sub.add_parser("add"); s.add_argument("dir"); s.add_argument("port"); s.add_argument("--features"); s.add_argument("--version-ge")
    s = sub.add_parser("remove"); s.add_argument("dir"); s.add_argument("port")
    s = sub.add_parser("list"); s.add_argument("dir")
    s = sub.add_parser("include-dir"); s.add_argument("project"); s.add_argument("path")
    s = sub.add_parser("record-fetch"); s.add_argument("dir"); s.add_argument("repo"); s.add_argument("tag"); s.add_argument("name")
    s.add_argument("sub", nargs="?", default="")
    a = ap.parse_args()
    return {"setup": cmd_setup, "add": cmd_add, "remove": cmd_remove, "list": cmd_list,
            "include-dir": cmd_include_dir, "record-fetch": cmd_record_fetch}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
