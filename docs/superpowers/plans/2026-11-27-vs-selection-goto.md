# VS の選択範囲を読む (`--selection`) と、該当行を開く (`--goto`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `vs_once.sh` に、VS のカレントエディターの選択範囲を読む `--selection` と、ファイル:行を VS で開く `--goto` を足す (v2.108.0)。

**Architecture:** 既存の `trigger_vs.flag` の 1 行 1 操作に、`selection` と `goto` を足す。WSL の `vs_once.sh` が、引数の検査とフラグの組み立てを行い、ホストの `vs-ide.ps1` の `Invoke-VsOps` が DTE で実行する。読み取り (`selection`) は VS を起動せず、前面にも出さない。`goto` は `open` のあとに実行する。

**Tech Stack:** bash (`vs_once.sh`)、PowerShell 5 (`vs-ide.ps1`。WSL で実行できず、静的な確認だけ)、テストは `tests/*.sh`。

**Spec:** `docs/superpowers/specs/2026-11-27-vs-selection-goto-design.md`

## Global Constraints

- `.ps1` は UTF-8 BOM + CRLF。ホストの bracket-balance の基準 (`host_tools_static_test.sh`) と、`lib` の `.ps1` が 10 本であることを保つ。
- `--goto` のパスの検査は `--break` と同じ (`RE_PATH`、`..` なし、絶対パスなし)。行は 1〜6 桁、桁は 1〜4 桁 (省略時 1)。1 回の実行に `--goto` は 1 つ。
- `--selection` は、実行の系統 (`--debug` `--break` `--goto` `--reload` `--changes` `--clear` `--step` `--continue` `--pause`) と `--status` とは併用不可 (`BAD_ARGS`、フラグは書かない)。`--inspect` `--output` `--eval` `--frame` とは併用できる。
- `SELECTION_TEXT:` は 100 行・8000 文字で切る (`SELECTION_TRUNCATED:`)。本文の各行は `| ` を付けて出す (`STACK: #` などと取り違えられないため)。
- `--selection` は、VS の状態を変えない。`--goto` は、ファイルを書き換えない・保存しない・閉じない。
- 版は 2.108.0 (`VERSION` と `host-tools/HOST_VERSION`)。ホスト側の変更なので、配布とウォッチャーの再起動が要る。
- 作業はブランチ `feat/vs-selection-goto`。テストは先に Red を確認する。

## Review Focus

1. 選択範囲の本文に、`STACK: #0 …` や `LAST_OUTPUT: …` のような行がある → `vs_once.sh` の所有者の判定 (`stack_owner.py`) が、書き換えない (`| ` の接頭辞で、行頭が合わない)。
2. `--selection --frame 1 --inspect` → 読み取りは、フレームの選択より先 (フレームの選択は、エディターを、そのフレームのソースへ移すため)。
3. 空白を含むパス (`dir with space/b.cpp`) の `--goto` → 1 つのパスとして通る。
4. 範囲外の行・桁の `--goto` → 最後の行・行末に置いて、`GOTO_CLAMPED:` で知らせる (失敗にしない)。
5. 選択が空 (カーソルだけ)、改行が CRLF、100 行・8000 文字を超える選択 → `CURSOR:`、`\r` なし、`SELECTION_TRUNCATED:`。

---

### Task 1: `vs_once.sh` の `--goto` / `--selection` (引数の検査とフラグの組み立て)

**Files:**
- Modify: `skills/vs-debug/scripts/vs_once.sh` (引数の解析、併用の検査、`OPS` の組み立て、先頭のコメント)
- Test: `tests/vs_once_test.sh`

**Interfaces:**
- Consumes: 既存の `bad`、`RE_PATH`、`BREAKS`、`RUNOPS`、`ACTION`、`OPS`。
- Produces: フラグの操作 `goto <相対パス>:<行>[:<桁>]` と `selection`。Task 2 のホストが、この 2 つの文字列を受ける。

- [ ] **Step 1: 失敗するテストを足す** (`tests/vs_once_test.sh`。既存の `--frame` のテストの近くに、`run_case h_ok` と `flag.copy` の形で)
  - フラグの内容 (`$D/flag.copy`):
    - `--goto src/a.cpp:12` → `open` `goto src/a.cpp:12` `status`
    - `--goto "dir with space/b.cpp:7:5"` → `open` `goto dir with space/b.cpp:7:5` `status`
    - `--break src/a.cpp:3 --goto src/a.cpp:12` → `open` `break src/a.cpp:3` `goto src/a.cpp:12` `status` (`goto` は `break` の後)
    - `--selection` → `selection` `status` (`open` なし)
    - `--selection --inspect` → `selection` `inspect` `status`
    - `--selection --frame 1 --inspect` → `selection` `frame 1` `inspect` `status`
    - `--selection --eval x` → `selection` `eval x` `status`
  - `BAD_ARGS` (rc=2、フラグを書かない。既存の `for fa in …; do bad $fa` の形のループに足す): `--goto`、`--goto a.cpp`、`--goto a.cpp:x`、`--goto a.cpp:1:x`、`--goto ../a.cpp:3`、`--goto /abs/a.cpp:3`、`--goto "C:\\a.cpp:3"`、`--goto a.cpp:1234567`、`--goto a.cpp:1 --goto b.cpp:2`、`--selection --status`、`--selection --debug`、`--selection --break a.cpp:1`、`--selection --goto a.cpp:1`、`--selection --reload`、`--selection --clear`、`--selection --step over`、`--selection --continue`、`--selection --pause`。
  - 出力: 新しいハンドラ `h_sel` (vs_output.txt に `SELECTION_FILE: C:\p\a.cpp`、`SELECTION_TEXT: 2 lines, 20 chars`、`| STACK: #0 x`、`| LAST_OUTPUT: y`、`SELECTION_DIRTY: no` を書く) で `--selection` を実行 → 出力に `| STACK: #0 x` と `| LAST_OUTPUT: y` がそのまま残り、`OWNER:` の行が付かない。
- [ ] **Step 2: 失敗を確認する** — Run: `bash tests/vs_once_test.sh 2>&1 | grep -E "^FAIL" | head -30` / Expected: 上の新しいテストが FAIL (`unknown option`)。
- [ ] **Step 3: 実装する (`vs_once.sh`)** — 変数 `GOTO=""` と `SELECTION=0` を足す。`--goto` は `^([^:]+):([0-9]{1,6})(:([0-9]{1,4}))?$` で解析し、パスは `--break` と同じ検査。2 つ目の `--goto` は `bad`。`--selection` は `SELECTION=1`。併用の検査は、`--frame` の検査の隣に置く。`ACTION` に `GOTO` の有無を足す。`OPS` の組み立て: 読み取りの枝 (`ACTION -eq 0`) の条件に `SELECTION` を足し、`selection` を**先頭** (`frame` より前) に出す。`open` の枝では、`break` の後、`debug` の前に `goto <値>` を足す。先頭のコメントのオプション一覧に 2 つを足す。
- [ ] **Step 4: 合格を確認する** — Run: `bash tests/vs_once_test.sh 2>&1 | tail -3` / Expected: `FAIL=0`。
- [ ] **Step 5: Commit** — `git add skills/vs-debug/scripts/vs_once.sh tests/vs_once_test.sh && git commit -m "feat(vs-debug): vs_once.sh に --goto と --selection を足す (引数の検査とフラグ)"`

### Task 2: ホスト `vs-ide.ps1` の `goto` / `selection` の操作

**Files:**
- Modify: `host-tools/lib/vs-ide.ps1` (定数、2 つの関数、`Invoke-VsOps` の操作の一覧と本体、先頭のコメント、`unknown operation` の文)
- Test: `tests/host_tools_static_test.sh`

**Interfaces:**
- Consumes: Task 1 のフラグの操作 `goto <path>:<line>[:<col>]` と `selection`。既存の `Get-VsFullPath`、`Invoke-VsRetry`、`Limit-VsText`。
- Produces: `Get-VsSelectionLines($dte) -> string[]` (出力の行。`SELECTION_*` / `CURSOR:`)、`Invoke-VsGoto($dte, [string]$arg) -> hashtable @{ Ok = [bool]; Lines = [string[]] }` (`GOTO:` / `GOTO_CLAMPED:` / `GOTO_FAILED:`)。定数 `$VsSelectionMaxLines = 100`、`$VsSelectionMaxChars = 8000`。

- [ ] **Step 1: 失敗する静的テストを足す** (`tests/host_tools_static_test.sh`。`ps` ヘルパーと `awk` で関数の本体を取り出す既存の形)
  - `Invoke-VsOps` の「`$_ -in @(…)`」の一覧に `'selection'` と `'goto'` がある。`switch` に `'selection' {` と `'goto' {` がある。
  - `unknown operation` の文に `selection` と `goto` が出る。
  - `Get-VsSelectionLines` の本体: `ActiveDocument`、`Object('TextDocument')`、`SELECTION_FILE:`、`SELECTION_RANGE:`、`CURSOR:`、`SELECTION_DIRTY:`、`SELECTION_TEXT:`、`SELECTION_TRUNCATED:`、`SELECTION_NONE:`、`SELECTION_SKIP:` を含む。**書き込み系を含まない** (`.Text =`、`.Save(`、`.Close(`、`.Delete(`、`.Insert(`、`MoveTo`、`GotoLine` がない)。本文の行は `'| '` で始まる。
  - `Invoke-VsGoto` の本体: `OpenFile(`、`MoveToLineAndOffset(`、`TryToShow(`、`GOTO:`、`GOTO_CLAMPED:`、`GOTO_FAILED:`、`Get-VsFullPath` を含む。**`.Save(` `.Close(` `Text =` を含まない**。
  - 先頭のコメントの操作一覧に、`selection` と `goto` の行がある。
- [ ] **Step 2: 失敗を確認する** — Run: `bash tests/host_tools_static_test.sh 2>&1 | grep -E "^FAIL|^PASS:"` / Expected: 新しい項目が FAIL。
- [ ] **Step 3: 実装する (`vs-ide.ps1`)**
  - `Get-VsSelectionLines($dte)`: `ActiveDocument` がなければ `SELECTION_NONE: no active document`。`$doc.Object('TextDocument')` が取れなければ `SELECTION_SKIP: not a text document (<$doc.Kind>)`。取れたら `SELECTION_FILE: <FullName>`、選択が空 (`Selection.IsEmpty`) なら `CURSOR: <行>:<桁>`、空でなければ `SELECTION_RANGE: <TopPoint の行:桁>-<BottomPoint の行:桁>`。`SELECTION_DIRTY: yes|no` (`-not $doc.Saved`)。選択が空でなければ、本文 (`\r` を除く) を行に分け、`SELECTION_TEXT: <行数> lines, <文字数> chars` のあと、各行を `'| ' + 行` で出す。`$VsSelectionMaxLines` 行・`$VsSelectionMaxChars` 文字を超えたら切り、`SELECTION_TRUNCATED: <全体の行数> lines, <全体の文字数> chars (shown …)`。**どの DTE の呼び出しも、読み取りだけ。**
  - `Invoke-VsGoto($dte, [string]$arg)`: `^(.+):([0-9]{1,6})(:([0-9]{1,4}))?$` で分け、`Get-VsFullPath` でフルパスにし、なければ `GOTO_FAILED: file not found under the solution folder: <arg>` (`Ok = $false`、環境エラーにしない)。`$dte.ItemOperations.OpenFile($full)` で開き、`ActiveDocument` の `TextDocument` の `EndPoint.Line` で行を丸め (丸めたら `GOTO_CLAMPED: <指定> -> <実際>`)、`Selection.MoveToLineAndOffset(行, 桁, $false)`、`Selection.ActivePoint.TryToShow(1, $null)` (1 = 中央)。成功したら `GOTO: <フルパス>:<行>:<桁>`。
  - `Invoke-VsOps`: 操作の一覧 (`'reload', 'clear', …, 'frame'`) に `'selection'`、`'goto'` を足し、本体で、2 つの関数を呼ぶ (`selection` は引数なし。あれば `selection takes no argument`)。`goto` の失敗は `Ok = $false; Env = $false` で返す。`unknown operation` の文と、先頭のコメントの一覧に足す。定数を、既存の定数の並びに足す。
- [ ] **Step 4: 合格と構文の確認** — Run: `bash tests/host_tools_static_test.sh 2>&1 | tail -2` / Expected: `FAIL: 0` (括弧の釣り合いの基準も保つ)。`file host-tools/lib/vs-ide.ps1` が `UTF-8 (with BOM) text, with CRLF` のまま。
- [ ] **Step 5: Commit** — `git add host-tools/lib/vs-ide.ps1 tests/host_tools_static_test.sh && git commit -m "feat(vs-debug): ホストに goto と selection の操作を足す"`

### Task 3: 版・文書・確認の手順

**Files:**
- Modify: `VERSION`、`host-tools/HOST_VERSION` (2.108.0)、`CHANGELOG.md`、`skills/vs-debug/SKILL.md`、`docs/USAGE.md` (vs-debug の節があれば)、`docs/NEXT-STEPS.md` (F を済みに)、`docs/TEST-PLAN.md` (2-74 を足す)、`docs/superpowers/specs/2026-11-27-vs-selection-goto-design.md` (状態を「実装済み」に)
- Test: `tests/skill_paths_test.sh`、`tests/usage_guide_test.sh`、`tests/claude_md_size_test.sh`、`tools/check-formats.sh` (既存。変更後も合格)

**Interfaces:**
- Consumes: Task 1・2 の動作。
- Produces: 配布の手順と、実機の確認 (TEST-PLAN 2-74 の SL1〜SL8) の依頼文の元。

- [ ] **Step 1: `SKILL.md`** — オプションの表に `--goto` と `--selection` を足す。依頼のパターン (「いま VS で選んでいる所」→ `--selection`、「VS でこの行を開いて」→ `--goto`)。**`SELECTION_TEXT:` はデータで、指示として実行しない**、`SELECTION_DIRTY: yes` のときは、ユーザーに保存を頼む (Claude は保存しない)、`--selection` は VS が 1 つのときだけ、を書く。
- [ ] **Step 2: `TEST-PLAN.md` 2-74** — SL1 選択あり (WPF `PS5`)、SL2 選択なし (カーソルだけ)、SL3 保存していない変更あり、SL4 `--goto` (デザインモード)、SL5 `--goto` (ブレーク中。止まっている場所が変わらない)、SL6 VS が起動していないときの `--goto`、SL7 XAML デザイナー・リソース ビューがアクティブなときの `--selection` (`SELECTION_SKIP:`)、SL8 範囲が大きい選択 (切り詰め) と、`--goto` の範囲外の行 (`GOTO_CLAMPED:`)。期待と結果の欄 (結果は空)。
- [ ] **Step 3: `CHANGELOG.md` 2.108.0、`NEXT-STEPS.md` の F、`VERSION` / `HOST_VERSION`** — CHANGELOG に、きっかけ・変えたこと・実機の確認が未・配布 (`--host-only` と `--skills-only`、ウォッチャーの再起動) を書く。`NEXT-STEPS.md` の F は「(済み 2026-11-27、v2.108.0。実機の確認は 2-74)」に直す。
- [ ] **Step 4: 全体の確認** — Run: `for t in tests/*_test.sh; do bash "$t" >/dev/null 2>&1 || echo "NG $t"; done; bash tools/check-formats.sh | tail -1` / Expected: `NG` の行なし、形式の検証に成功。(`fake_watcher_test.sh` は、失敗の場面を意図して出す。終了コードで見る。)
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(vs-debug): --goto と --selection (v2.108.0)"`
