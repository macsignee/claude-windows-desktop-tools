# vs-debug: フレームの所有者の判定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `vs_once.sh --inspect` の `STACK:` の各フレームに、所有者の印 (`ours` / `ext` / `sys` / `unknown`) と、要約 (`OWNER:` / `BOUNDARY:`) を付け、`--frame N` でそのフレームの変数を読めるようにする。

**Architecture:** ホスト (PowerShell) は、事実 (`STACK:` の末尾に `[module=…]`、`frame N` の操作) を出すだけ。判定は、WSL 側の Python (`stack_owner.py`) が、`vs_once.sh` の出力を通して付ける (WSL には `pwsh` がないため、判定を、単体テストできるようにする)。

**Tech Stack:** Python 3 (標準ライブラリだけ)、bash (テスト)、PowerShell 5.1 (`host-tools/lib/vs-ide.ps1`)。

**Spec:** `docs/superpowers/specs/2026-11-26-vs-debug-stack-owner-design.md` (第 9 節の判断も、仕様の一部)。

## Global Constraints
- WSL に `pwsh` も `dotnet` もない。`.ps1` は、`tests/host_tools_static_test.sh` の流儀 (文字列の確認) で確かめ、動作は、最後の実機確認 (Task 5) で確かめる。
- `.ps1` は UTF-8 BOM + CRLF。`host-tools/lib/*.ps1` は 10 ファイルのまま。`host_tools_static_test.sh` の括弧の数の基準 (`{ }` -1 / `( )` +1 / `[ ]` 0) を壊さない。
- Python は、標準ライブラリだけ。`python3 -I` で動くこと (`import` は、標準のものだけ。同じフォルダのモジュールを `import` しない)。
- 所有者の語は `ours` / `ext` / `sys` / `unknown`。要約の行は `OWNER:` / `BOUNDARY:`。選択の行は `FRAME:`。
- `STACK:` の書き換え後の形: `STACK: #<n> [<所有者>] <関数> at <ファイル>:<行> (<モジュール>)` (`at …` と `(…)` は、あるときだけ)。ホストが出す元の形: `STACK: #<n> <関数> at <ファイル>:<行> [module=<モジュール>]` (`at …` と `[module=…]` は、あるときだけ)。
- 判定の規則は、設計書の 5-3 のとおり。**`SOLUTION:` の行がないときは、ours / ext を決められないので、システムでないものは `unknown`** (計画の判断)。パスは、`/` を `\` にして、小文字にして比べる。
- `--frame <N>`: N は 0〜99 の整数 (先頭の 0 は、10 進として読む)。`--inspect` か `--eval` が必要。`--step` / `--continue` / `--pause` / `--debug` と併用不可。`--status` とも併用不可。
- 版: `VERSION` と `host-tools/HOST_VERSION` を、**最後のタスク (Task 4) で 2.107.0 に上げる** (現在は 2.106.1 / 2.106.1)。
- ブランチ `feat/vs-debug-stack-owner` は、すでにある (設計書だけが未コミット。Task 1 のコミットに含める)。マージはユーザーが行う。コミットの末尾に `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。

## Review Focus
1. ソリューションのパスの大文字小文字・区切り (`/`)・末尾の `\` の違い → 同じ場所として、`ours` になる。**Task 1。**
2. 関数名に ` at ` や空白・`<>`・`::`・`operator()` がある → 関数・ファイル・行を、取り違えない。**Task 1。**
3. `--frame` に、数字でない値・負の値・100 以上・併用不可の指定 → `BAD_ARGS` で、フラグを置かない。**Task 2。**
4. `STACK:` の行がない出力・`STACK_TRUNCATED:` がある出力 → 出力が、変わらない / 要約は、表示した範囲だけ。**Task 1。**
5. UNC パス (`\\server\share\…`) とマップしたドライブ (`z:\…`) のソース → `ext`。**Task 1。**

---

## ファイル構成
- Create: `skills/vs-debug/scripts/stack_owner.py`, `tests/stack_owner_test.sh` (Task 1)
- Modify: `skills/vs-debug/scripts/vs_once.sh`, `tests/vs_once_test.sh` (Task 2)
- Modify: `host-tools/lib/vs-ide.ps1`, `tests/host_tools_static_test.sh` (Task 3)
- Modify: `skills/vs-debug/SKILL.md`, `README.md`, `docs/USAGE.md`, `CHANGELOG.md`, `docs/TEST-PLAN.md`, `VERSION`, `host-tools/HOST_VERSION` (Task 4)

### Task 1: `stack_owner.py` (判定と、書き換え)

**Files:**
- Create: `skills/vs-debug/scripts/stack_owner.py`
- Test: `tests/stack_owner_test.sh` (新規。`tests/uitest_once_test.sh` と同じ `ok` / `PASS=` の形)

**Interfaces:**
- Produces (モジュールの関数。`tests/stack_owner_test.sh` が、`python3 -I -c` で `sys.path` に `skills/vs-debug/scripts` を足して呼ぶ):
  - `parse_frame(line: str) -> dict | None`: `STACK: #…` の行 → `{"n": int, "func": str, "file": str, "line": str, "module": str}` (ないものは `""`)。`STACK:` で始まらない行・`STACK_TRUNCATED:` は `None`。
  - `classify(file: str, module: str, solution_dir: str | None) -> str`: `"ours"` / `"ext"` / `"sys"` / `"unknown"`。
  - `transform(lines: list[str]) -> list[str]`: 出力の全行 → 書き換えた全行 (`STACK:` の行だけ書き換え、最後の `STACK:` / `STACK_TRUNCATED:` の行の直後に `OWNER:` と `BOUNDARY:` を挿入。`STACK:` の行がなければ、そのまま)。
  - CLI: `python3 -I stack_owner.py <ファイル>` → `transform` の結果を、標準出力へ (1 行 1 要素。ファイルは、BOM・CR を除いて読む)。ファイルがなければ、何も出さず rc=0。
- `SOLUTION:` の行 (`SOLUTION: c:\ws\Sln\Sln.slnx`) から、ソリューションのフォルダ (`c:\ws\Sln`) を求める (行は `transform` の入力に含まれる)。

- [ ] **Step 1: 失敗するテストを書く** (`tests/stack_owner_test.sh`。`python3 -I - <<'PY'` で、関数を直接呼び、`ok "<名前>" 1|0` で数える)
  - `classify` (solution_dir=`c:\ws\Sln`):
    - ソリューションの下のソース `C:\WS\Sln\UiLayer\a.cpp` (大文字小文字違い)、`c:/ws/sln/x.cpp` (`/`)、solution_dir に末尾 `\` → `ours`。
    - 外のソース `z:\nightly\LibA\src\a.cpp`、UNC `\\srv\share\LibA\a.cpp` → `ext`。
    - システムのソース (`C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.4\atlmfc\src\mfc\wincore.cpp`、`d:\a01\_work\1\s\src\vctools\crt\vcruntime\src\eh\x.cpp`、`C:\Windows\x.c`) → `sys`。
    - **静的ライブラリ**: file=`z:\nightly\LibA\src\a.cpp`、module=`C:\ws\Sln\x64\Debug\App.exe` (こちらの exe) → `ext` (ファイルを先に見る)。
    - ソースなし: module=`ntdll.dll` → `sys`、module=`MFC140UD.dll` → `sys`、module=`System.Private.CoreLib.dll` → `sys`、module=`C:\ws\Sln\x64\Debug\UiLayer.dll` → `ours`、module=`C:\Windows\System32\foo.dll` → `sys`、module=`z:\nightly\LibA\LibA.dll` → `ext`、module=`LibA.dll` (名前だけ) → `unknown`。ファイルもモジュールもない → `unknown`。
    - solution_dir=`None`: ソリューションの下に見える `C:\ws\Sln\a.cpp` → `unknown`、システムのソース → `sys`。
  - `parse_frame`: `STACK: #3 Foo<int>::operator() at c:\ws\Sln\a.cpp:54 [module=App.exe]` → func=`Foo<int>::operator()`、file=`c:\ws\Sln\a.cpp`、line=`54`、module=`App.exe`。関数名に ` at ` を含む `STACK: #1 handle at risk at c:\a.cpp:9` → func=`handle at risk`、file=`c:\a.cpp`。ファイルなし `STACK: #5 [External Code]` → func=`[External Code]`、file=``。`STACK_TRUNCATED: 27 more frames` → `None`。
  - `transform` (行のリストを渡す):
    - スタック `#0 ext (z:\…)`、`#1 sys (…\atlmfc\…)`、`#2 ours (c:\ws\Sln\…)` + `SOLUTION: c:\ws\Sln\Sln.slnx` → `STACK:` の行が `[ext]` / `[sys]` / `[ours]` 付きになり、最後の `STACK:` の直後に `OWNER: top=ext (frame #0)` と `BOUNDARY: #2 ours -> ext #0`。
    - `#0 ours` だけ → `OWNER: top=ours (frame #0)`、`BOUNDARY: none`。
    - `#0 sys`、`#1 sys`、`#2 ours` → `OWNER: top=ours (frame #2)`、`BOUNDARY: none`。全部 `sys` → `OWNER: top=sys (frame #0)`。
    - `#0 ext`、`#1 unknown`、`#2 ours` → `BOUNDARY: unknown (frame #1 has no symbols)`。
    - `STACK_TRUNCATED:` がある → その行の直後に、`OWNER:` と `BOUNDARY:` (表示したフレームだけが対象)。
    - `STACK:` の行がない出力 (`DIRTY:` などだけ) → 入力と同じ。
    - 書き換えた `STACK:` の形が、Global Constraints のとおり (`(<モジュール>)` は、あるときだけ)。
  - CLI: BOM + CRLF のファイルを渡しても、出力に BOM・CR がない。存在しないファイル → 何も出ず rc=0。
- [ ] **Step 2: 実行して失敗を確かめる**: `bash tests/stack_owner_test.sh` → ファイルがないので、すべて FAIL (または、`stack_owner.py` がない旨のエラー)。
- [ ] **Step 3: `stack_owner.py` を実装する**: 上の Interfaces のとおり。システムの判定のパターンは、設計書の 5-3 の一覧を、定数 (タプル) にして持つ。モジュール名のパターンは、設計書の例を、正規表現 1 つにまとめる (広げてよい)。
- [ ] **Step 4: 実行して成功を確かめる**: `bash tests/stack_owner_test.sh` → `FAIL=0`。
- [ ] **Step 5: コミット**: 設計書・計画書も含める。`git add docs/superpowers skills/vs-debug/scripts/stack_owner.py tests/stack_owner_test.sh`、`git commit -m "feat(vs-debug): stack_owner.py (フレームの所有者の判定) と、設計・計画"`。

### Task 2: `vs_once.sh` の `--frame` と、出力への組み込み

**Files:**
- Modify: `skills/vs-debug/scripts/vs_once.sh` (引数の解釈・`OPS` の組み立て・`show`)
- Test: `tests/vs_once_test.sh`

**Interfaces:**
- Consumes: Task 1 の CLI `python3 -I "$SELF_DIR/stack_owner.py" <ファイル>`。
- Produces: `vs_once.sh <dir> --frame <N> --inspect|--eval "<式>"` が、フラグに `frame <N>` の行を、**`eval` / `inspect` の前** (`RUNOPS` の前) に書く (読み取り専用の経路と、`open` から始まる経路の、両方で)。`OK` のとき、`vs_output.txt` を、`stack_owner.py` に通して出す (`STACK:` がなければ、今までと同じ出力)。

- [ ] **Step 1: 失敗するテストを足す** (`tests/vs_once_test.sh`)
  - フラグ: `run_case h_ok --frame 2 --inspect` → `flag.copy` が `printf 'frame 2\ninspect\nstatus'`。`run_case h_ok --frame 3 --eval "x"` → `printf 'frame 3\neval x\nstatus'`。先頭の 0: `--frame 007 --inspect` → `frame 7`。
  - `BAD_ARGS` (rc=2。`bad` 関数の形): `--frame` だけ・`--frame abc --inspect`・`--frame -1 --inspect`・`--frame 100 --inspect`・`--frame 2` (`--inspect` も `--eval` もない)・`--frame 1 --inspect --step over`・`--frame 1 --inspect --continue`・`--frame 1 --inspect --pause`・`--frame 1 --inspect --debug`・`--frame 1 --status`。どれも、フラグを置かない。
  - 出力: 新しい疑似ウォッチャー `h_stack` (`vs_output.txt` に、`STACK: #0 Lib::Run at z:\nightly\LibA\a.cpp:9 [module=LibA.dll]` と `STACK: #1 App::Go at C:\p\a.cpp:12 [module=App.exe]` と `SOLUTION: C:\p\App.slnx` を、BOM + CRLF で書く) → 出力に、`STACK: #0 [ext] Lib::Run at z:\nightly\LibA\a.cpp:9 (LibA.dll)`、`STACK: #1 [ours] App::Go …`、`OWNER: top=ext (frame #0)`、`BOUNDARY: #1 ours -> ext #0` があり、BOM・CR がない。既存の `h_ok` の出力は、変わらない (今のテストが通る)。
- [ ] **Step 2: 実行して失敗を確かめる**: `bash tests/vs_once_test.sh` → 新しいケースが FAIL。
- [ ] **Step 3: `vs_once.sh` を直す**: `--frame) ...` の解釈 (`FRAME` を持つ。設計の検査は、`--no-wait` の検査の近くに)。`OPS` の 2 つの経路で、`RUNOPS` の前に `frame <N>` を足す。`show "$OUTFILE"` を、`STACK:` を含むときだけ、`sed 's/^\xEF\xBB\xBF//; s/\r$//'` で整えた内容を `stack_owner.py` に通して出す形にする (`MAX_OUT` の上限は、そのまま。通したあとの行に、適用する)。冒頭の使い方のコメントに `--frame` の説明を足す。
- [ ] **Step 4: 実行して成功を確かめる**: `bash tests/vs_once_test.sh && bash tests/stack_owner_test.sh` → 失敗なし。
- [ ] **Step 5: コミット**: `git add tests/vs_once_test.sh skills/vs-debug/scripts/vs_once.sh`、`git commit -m "feat(vs-debug): --frame N と、STACK への所有者の印・要約の組み込み"`。

### Task 3: ホスト側 (`vs-ide.ps1`): `[module=…]` と `frame` の操作

**Files:**
- Modify: `host-tools/lib/vs-ide.ps1` (`Get-VsInspectLines` の `STACK:` の行、操作の一覧、`'frame'` の処理)
- Test: `tests/host_tools_static_test.sh`

**Interfaces:**
- Produces: `STACK:` の行の末尾に、`Module` が取れたとき `[module=<値>]` (取れなければ、足さない)。操作 `frame <N>`: (1) `CurrentThread.StackFrames` の N 番目を `Debugger.CurrentStackFrame` に設定、(2) 成功したら `FRAME: #<N> <関数> at <ファイル>:<行>` を出す、(3) 範囲外は `FRAME_OUT_OF_RANGE: <N> (frames: <件数>)` で失敗、(4) ブレークでなければ `FRAME_SKIP: the mode is <mode> (not break).` を出して続ける、(5) **実行の最後 (成功・失敗・例外のどの経路でも) に、元のフレームへ戻す**、(6) 引数が整数でなければ失敗 (`frame takes a non-negative integer`)。

- [ ] **Step 1: 失敗する静的な確認を足す** (`host_tools_static_test.sh`。`ps | awk '/^function Get-VsInspectLines/,/^}/'` の形で切り出す)
  - `Get-VsInspectLines` が、`STACK:` の行に `[module=` を付け、`Module` を読む (`try` の中)。
  - 操作の一覧 (`'reload', 'clear', …, 'eval'` の行) に `'frame'` がある。`'frame' {` の処理があり、`FRAME_OUT_OF_RANGE`、`FRAME_SKIP`、`CurrentStackFrame` への設定、`FRAME:` の行を含む。
  - 元のフレームへ戻す処理が、`finally` (または、全経路を覆う形) にあり、元のフレームを保持する変数を、使っている。
- [ ] **Step 2: 実行して失敗を確かめる**: `bash tests/host_tools_static_test.sh` → 新しい確認が FAIL。
- [ ] **Step 3: 実装する**: 上の Interfaces のとおり。`$dte.Debugger.CurrentStackFrame` の設定は、`Invoke-VsRetry` で包む。復元は、操作の実行ループ (`Invoke-VsFlag` 相当) の外側の `try / finally` に置き、`frame` を実行したときだけ、元のフレームを覚えておく。BOM + CRLF を保つ (`python3` で、バイトのまま置換する)。
- [ ] **Step 4: 実行して成功を確かめる**: `bash tests/host_tools_static_test.sh && bash tests/vs_once_test.sh` → 失敗なし (括弧の数の基準を含む)。
- [ ] **Step 5: コミット**: `git add host-tools/lib/vs-ide.ps1 tests/host_tools_static_test.sh`、`git commit -m "feat(host): STACK に module を足し、frame N の操作を足す (vs-ide)"`。

### Task 4: Skill・文書・版

**Files:**
- Modify: `skills/vs-debug/SKILL.md`, `README.md`, `docs/USAGE.md`, `CHANGELOG.md`, `docs/TEST-PLAN.md`, `VERSION`, `host-tools/HOST_VERSION`
- Test: 既存の文書の検査 (`tests/usage_guide_test.sh`, `tests/skill_paths_test.sh`, `tests/ui_test_first_skill_test.sh`)、全テスト

**Interfaces:**
- Consumes: Task 1〜3 の名前 (`stack_owner.py`、`--frame`、`OWNER:` / `BOUNDARY:` / `FRAME:`、`ours` / `ext` / `sys` / `unknown`)。

- [ ] **Step 1: `vs-debug/SKILL.md`**: スクリプトの表に `--frame <N>` の行 (併用の規則) を足す。「`--inspect` の出力」の説明に、`[ours]` などの印、`OWNER:`・`BOUNDARY:` を足す。依頼ごとの手順に、「原因が、こちらか、外のライブラリか」の節 (設計書の第 6 節の 1〜4。**ヒントであり、断定ではない**こと、`unknown` の意味、日次の配布の運用を含める) を足す。
- [ ] **Step 2: `README.md` / `docs/USAGE.md` / `CHANGELOG.md`**: 機能の説明と 2.107.0 の項 (ホスト側を変えた。再配布とウォッチャーの再起動が要る、と明記)。`docs/TEST-PLAN.md` に、2-72 (設計書の第 10 節の 5 点。結果は空欄) を足す。
- [ ] **Step 3: 版**: `VERSION` と `host-tools/HOST_VERSION` を `2.107.0` に。`grep -rn "2\.106\.1" --include=*.md . | grep -v "CHANGELOG\|HANDOFF\|TEST-PLAN\|superpowers"` で、現行の版を書いている箇所を確かめ、合わせる。
- [ ] **Step 4: 全テスト**: `for t in tests/*.sh; do bash $t >/dev/null 2>&1 || echo "FAILED: $t"; done; bash tools/check-formats.sh | tail -1` → `FAILED:` なし、`OK  形式の検証に成功`。
- [ ] **Step 5: コミット**: `git add skills docs README.md CHANGELOG.md VERSION host-tools`、`git commit -m "docs: フレームの所有者の判定 (--frame / OWNER / BOUNDARY) の手順と、2.107.0"`。

### Task 5: 実機での確認 (ユーザーの作業を含む。コードは変えない)
- [ ] **Step 1: 準備 (ユーザー)**: マージ後に `./install/install.sh --host-only` と `--skills-only`、ウォッチャーの再起動。**ソリューションの外**に、小さな DLL (外のライブラリ役。関数を 1 つ公開し、引数を使う) と、それを呼ぶ MFC のアプリを作る (または、既存の `ClaudePlayground` のものを使う)。
- [ ] **Step 2〜6: 設計書の第 10 節の 1〜5** を、順に行い、結果を `docs/TEST-PLAN.md` の 2-72 に記録する。**最初に確かめること:** `STACK:` の行の `[module=…]` が、名前か、パスか (取れなければ、足されない)。それに合わせて、`stack_owner.py` の規則 2 を調整する (調整したら、テストを先に足す)。
