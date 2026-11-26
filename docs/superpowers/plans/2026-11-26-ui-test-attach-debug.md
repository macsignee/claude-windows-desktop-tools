# UI テストのアタッチモード (デバッグのきっかけの UI 操作) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VS のデバッガーが起動したアプリに、UI テスト (FlaUI) がアタッチし、きっかけの UI 操作を撃って待たずに終わり、その後 `vs-debug` の `--inspect` / `--step` が通るようにする。

**Architecture:** ウォッチャーは `trigger_uitest.flag` の `attach=<プロセス名>` を受けたら、ソリューション全体のビルドと、アプリの強制終了を省き、UI テストのプロジェクトだけをビルドして実行する。UI テストのひな形 (`UiTestBase`) は、環境変数 `UITEST_ATTACH_PROCESS` で `Launch` を `Attach` に切り替え、`Trigger(Action)` の後の UI アクセスをコードで禁じる。`vs-debug` の `--debug` に `--no-wait` を足し、ブレークを待たずに返す。

**Tech Stack:** bash (テスト・スクリプト)、Python 3 (`add_ui_tests.py`。C# のひな形を文字列で持つ)、PowerShell 5.1 (`host-tools/`)、C# + FlaUI 5.0.0 (生成されるひな形)。

**Spec:** `docs/superpowers/specs/2026-11-26-ui-test-attach-debug-design.md` (第 9 節の「読み手の確認への答え」も、仕様の一部)。試作: `poc/attach-debug/`。

## Global Constraints
- 環境: WSL に `dotnet` と `pwsh` はない。**C# と PowerShell は、WSL では実行できない。** `.ps1` は、`tests/host_tools_static_test.sh` の流儀 (文字列の確認) で、C# のひな形は、`tests/ui_tests_gen_test.sh` の流儀 (生成物の文字列の確認) で確かめ、動作は、最後の実機確認 (Task 7) で確かめる。
- `.ps1` は UTF-8 BOM + CRLF。`host-tools/lib/*.ps1` は 10 ファイルのまま (増やさない。`host_tools_static_test.sh` が数える)。括弧の数の基準 (`{ }` -1 / `( )` +1 / `[ ]` 0) が、`host_tools_static_test.sh` にある: ps1 を変えたら、この基準を壊さない (壊れたら、原因を直す。基準を書き換えるのは、最後の手段で、理由を書く)。
- 生成する `.cs` は UTF-8 BOM + CRLF (既存のひな形の流儀)。ひな形のプレースホルダーは `__X__` 形式 (`fill()`)。C# の波括弧は、そのまま書ける。
- フラグ名 `attach=`、環境変数 `UITEST_ATTACH_PROCESS`、テストのカテゴリ `DebugTrigger`、メソッド `Trigger(Action fire)`。プロセス名は `[A-Za-z0-9_.-]+` だけ。
- `attach=` は、**desktop=visible 固定** (別のデスクトップは、不可)。制限時間の既定は 60 秒 (flag の `timeout=` が優先)。`--ui-timeout` で変更できる。
- アタッチ先は、**exe が `UITEST_SOLUTION_DIR` の下**にあるプロセスだけ。同名が 2 つ以上なら、選ばず失敗 (PID の一覧)。探し直しは、最大 15 秒。
- `Trigger` は、`fire` を別タスクで実行し、最大 3 秒待つ。戻らなくても、「止まった」と見なして戻る。
- アタッチモードの `StopApp` は、UIA を呼ばない (`Dispose`・スクリーンショットも)。アプリを閉じない・殺さない。
- テストが書く `ui-trace.txt` の行: `ATTACHED: <プロセス名> (pid <PID>)` と `TRIGGERED:` (行頭に、`HH:mm:ss.fff ` の時刻が付く。`UiTrace.Write` の形式)。`uitest_once.sh` が、これを拾う。
- 文だけで縛らず、コードで縛る (`Trigger` の後の `Find`、`uitest_once.sh` の `ATTACH_UNSUPPORTED:`)。
- 日本語の文言 (エラー文・コメント) は、通常の丁寧さで、簡潔に。コミットメッセージは、通常の日本語。
- マージは、ユーザーが行う。ブランチを作る前に `cat VERSION` を確認し、ブランチは `git switch -c` で作る。コミットの末尾に `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- 版: `VERSION` と `host-tools/HOST_VERSION` を、**最後のタスク (Task 6) で、2.106.0 に上げる** (現在は 2.105.6 / 2.105.1)。

## Review Focus
1. プロセス名に、空白・引用符・パス区切り・改行がある (`--attach "a b"`、`--attach 'x"y'`) → `BAD_ARGS` (フラグへの注入を防ぐ)。**Task 5 の `uitest_once_test.sh` が持つ。**
2. `--attach` と `--separate`、`--present`、`--hold` の併用 → `BAD_ARGS`。**Task 5。**
3. `Trigger` を 2 回呼ぶ、`Trigger` の前に `Find` する (これは許す)、`Trigger` の後に `Find` / `FindIn` / 2 回目の `Trigger` → 後の 2 つは、`AssertFailedException`。**Task 4 の生成物の確認が持つ。**
4. `attach=` で、UI テストのプロジェクトのビルドが失敗した → アプリは殺さず、`BUILD_FAILED` を返す。**Task 3 の静的な確認が持つ (失敗の経路でも `Stop-SolutionProcesses` を呼ばない)。**
5. 古いひな形の既存ソリューション (環境変数を、無視して、`Launch` する) → `ATTACH_UNSUPPORTED:` で失敗し、`--refresh-support-files` を案内する。**Task 5。**

---

## ファイル構成
- Modify: `skills/vs-debug/scripts/vs_once.sh`, `host-tools/lib/vs-ide.ps1`, `tests/vs_once_test.sh` (Task 1)
- Modify: `host-tools/lib/ui-settings.ps1`, `host-tools/lib/tests.ps1`, `host-tools/watch_and_build.ps1`, `tests/host_tools_static_test.sh` (Task 2・3)
- Modify: `skills/new-solution/scripts/add_ui_tests.py` (`BASE_CS`, `UiTrace` の周辺), `tests/ui_tests_gen_test.sh` (Task 4)
- Modify: `skills/build-test-loop/scripts/uitest_once.sh`, `tests/uitest_once_test.sh` (Task 5)
- Modify: `skills/vs-debug/SKILL.md`, `skills/build-test-loop/references/ui-tests.md`, `README.md`, `docs/USAGE.md`, `CHANGELOG.md`, `docs/TEST-PLAN.md`, `poc/attach-debug/README.md`, `VERSION`, `host-tools/HOST_VERSION` (Task 6)

### Task 1: `vs-debug` の `--no-wait`

**Files:**
- Modify: `skills/vs-debug/scripts/vs_once.sh` (引数の解釈と `OPS` の組み立て。`debug` の行は 168 行目付近)
- Modify: `host-tools/lib/vs-ide.ps1` (`'debug'` の処理。575 行目付近。受け付ける操作の一覧は 427 行目付近)
- Test: `tests/vs_once_test.sh`

**Interfaces:**
- Produces: `vs_once.sh <dir> ... --debug --no-wait` が、フラグに `debug nowait` の 1 行を書く (`--no-wait` なしは、今までどおり `debug`)。ウォッチャーは、`debug nowait` のとき、起動後 (モードが `run` になったら) すぐ戻り、`DEBUG_STARTED` と `DEBUG_MODE: run` を出す。`NOTE: no breakpoint was hit within ...` は出さない。

- [ ] **Step 1: 失敗するテストを足す** (`tests/vs_once_test.sh` の `run_case h_ok --break src/a.cpp:12 --debug` の近く)
  - `run_case h_ok --break src/a.cpp:12 --debug --no-wait` の後、`flag.copy` が `printf 'open\nbreak src/a.cpp:12\ndebug nowait\nstatus'` と等しい。
  - `bad --no-wait` (`--debug` なし) → `BAD_ARGS` (rc=2)。`bad --status --debug --no-wait` も rc=2 (既存の `--status` の併用禁止と同じ)。
  - `--no-wait` なしの既存ケースは、変わらない (`debug` の行)。
- [ ] **Step 2: 実行して失敗を確かめる**: `bash tests/vs_once_test.sh` → 新しいケースが FAIL。
- [ ] **Step 3: `vs_once.sh` を直す**: `--no-wait) NOWAIT=1; shift ;;` を足し、`--debug` なしなら `bad "--no-wait needs --debug"`。`OPS+=("debug")` を、`NOWAIT=1` のとき `debug nowait` にする。冒頭のコメントの `--debug` の行に、`--no-wait` の説明を足す。
- [ ] **Step 4: `vs-ide.ps1` を直す**: 受け付ける操作の検査 (`'debug'` を含む一覧) は、引数つき (`debug nowait`) を通す。`'debug'` の処理で、`$arg -eq 'nowait'` なら、`design`/`unknown` を抜ける待ちの後、**ブレークの待ち (`$VsBreakWaitSec`) と、`NOTE: no breakpoint ...` の行を省く**。`$arg` が `nowait` 以外なら、`debug takes no argument other than nowait` で失敗にする。
- [ ] **Step 5: 実行して成功を確かめる**: `bash tests/vs_once_test.sh && bash tests/host_tools_static_test.sh` → 失敗なし (括弧の数の基準も含む)。
- [ ] **Step 6: コミット**: `git switch -c feat/ui-test-attach-debug` (最初のコミットの前。`docs/superpowers/` の設計書・計画書も、このコミットに含める)、`git add docs/superpowers tests/vs_once_test.sh skills/vs-debug/scripts/vs_once.sh host-tools/lib/vs-ide.ps1`、`git commit -m "feat(vs-debug): --debug --no-wait (ブレークを待たずに返す) と、UI テストのアタッチの設計・計画"`。

### Task 2: ウォッチャーの設定の解釈 (`attach=`)

**Files:**
- Modify: `host-tools/lib/ui-settings.ps1` (`ConvertFrom-UiSettingsText`, `Resolve-UiRun`)
- Test: `tests/host_tools_static_test.sh`

**Interfaces:**
- Consumes: なし。
- Produces: `ConvertFrom-UiSettingsText` の戻り値に `Attach` (文字列。なければ空) を足す (`^attach\s*=\s*([A-Za-z0-9_.-]+)$` だけを受け付け、ほかは無視)。`Resolve-UiRun` の戻り値に `Attach` を足し、`Attach` が空でないとき: `Desktop = 'default'` (理由 `attach (needs your desktop)`)、`TimeoutSec` は、flag の `timeout=` がなければ 60 (uitest.settings の `timeout=` は、**使わない**)、`Filter` は、flag の `filter=` がなければ `TestCategory=DebugTrigger`。`Attach` が空のとき: `Filter` は、flag の `filter=` がなければ `TestCategory!=DebugTrigger` (通常の実行は、きっかけ専用のテストを除く)。**flag の `filter=` があれば、そのまま** (除かない)。

- [ ] **Step 1: 失敗する静的な確認を足す** (`host_tools_static_test.sh`。`ps | awk '/^function ConvertFrom-UiSettingsText/,/^}/'` の形で、関数ごとに切り出す)
  - `ConvertFrom-UiSettingsText` が `attach` の行を読み、正規表現が `[A-Za-z0-9_.-]+` に限られ、戻り値のハッシュに `Attach =` がある。
  - `Resolve-UiRun` が、`Attach` のとき、`60` と `TestCategory=DebugTrigger` を使い、`Attach` でないとき `TestCategory!=DebugTrigger` を使い、戻り値に `Attach =` がある。
- [ ] **Step 2: 実行して失敗を確かめる**: `bash tests/host_tools_static_test.sh` → 新しい確認が FAIL。
- [ ] **Step 3: 実装する**: 上の Interfaces のとおり。**通常の実行でも、`Filter` が、常に入る**ことになる: `tests.ps1` の「`no test matches the filter`」の文言 (`$script:UiRun.Filter` があるときに出る) が、通常の実行で、誤解を招かないか確かめ、必要なら、flag に `filter=` があったときだけ、その文言を出す (既定の `TestCategory!=DebugTrigger` では、通常の「no tests were executed」の文言にする)。`filter=` の既存の拒否 (引用符・末尾の `\`) は、そのまま。`Resolve-UiRun` の `present` の処理 (`present` は `Attach` と併用できない: `Attach` のとき `$present = $false`) を守る。
- [ ] **Step 4: 実行して成功を確かめる**: `bash tests/host_tools_static_test.sh` → 失敗なし。
- [ ] **Step 5: コミット**: `git commit -m "feat(host): trigger_uitest.flag の attach= を解釈する (ui-settings)"` (変更した 2 ファイルだけを `git add`)。

### Task 3: ウォッチャーの流れ (ビルドと強制終了を省く)

**Files:**
- Modify: `host-tools/watch_and_build.ps1` (UI テストの前処理 `Stop-SolutionProcesses` とビルド、実行後の後始末。525〜660 行目付近)
- Modify: `host-tools/lib/tests.ps1` (`Invoke-Tests` の環境変数と、タイムアウト時の `Stop-SolutionProcesses`)
- Test: `tests/host_tools_static_test.sh`

**Interfaces:**
- Consumes: Task 2 の `$script:UiRun.Attach`。
- Produces: `$script:UiRun.Attach` が空でないとき、(1) 実行の前の `Stop-SolutionProcesses` を呼ばない、(2) `Invoke-BuildScript` / `Invoke-ScopedBuild` の代わりに、**UI テストのプロジェクト (`Find-DotnetTestProjects -Ui`) だけを `Invoke-BuildScript -Target <proj>` でビルド**し、失敗したら、今のビルド失敗の経路 (`FAILED` / `BUILD_FAILED`) に合流する、(3) `Invoke-Tests -Ui` が、`$env:UITEST_ATTACH_PROCESS = <名前>` を渡し、(4) 実行の後の `Stop-SolutionProcesses` を呼ばない、(5) タイムアウトの経路 (`tests.ps1` の `if ($Ui) { Stop-SolutionProcesses }`) でも呼ばない、(6) 後始末の `Remove-Item Env:\...` の一覧に `UITEST_ATTACH_PROCESS` を足す、(7) `[UI]` の表示の行に `attach: <名前>` を足す。`UITEST_ATTACH_PROCESS` は、`Attach` が空のとき、**設定しない** (前回の値が残らないよう、`Remove-Item` する)。

- [ ] **Step 1: 失敗する静的な確認を足す** (`host_tools_static_test.sh`)
  - `watch_and_build.ps1` の UI テストの前処理に、`UiRun.Attach` を見て、`Stop-SolutionProcesses` を省く分岐がある。実行の後の `Stop-SolutionProcesses` も同じ (`Attach` が空でないときは呼ばない)。
  - 上の分岐に、UI テストのプロジェクトだけをビルドする経路 (`Find-DotnetTestProjects -Ui` と `Invoke-BuildScript -Target`) がある。
  - `tests.ps1` の `Invoke-Tests` が、`UITEST_ATTACH_PROCESS` を設定し、タイムアウトの `Stop-SolutionProcesses` が `Attach` のときは呼ばれない。後始末の `Remove-Item Env:\` の一覧に `UITEST_ATTACH_PROCESS` がある。
- [ ] **Step 2: 実行して失敗を確かめる**: `bash tests/host_tools_static_test.sh` → 新しい確認が FAIL。
- [ ] **Step 3: 実装する**: 上の Interfaces のとおり。ビルドを省いたことが分かるよう、`Write-Host "[UI] attach mode: ..."` の 1 行を出す。変更は、既存の `$runUiTests` の分岐の中に、最小に留める (関数を足すなら、`ui-settings.ps1` か `tests.ps1` へ。`lib` のファイルは、増やさない)。
- [ ] **Step 4: 実行して成功を確かめる**: `bash tests/host_tools_static_test.sh` → 失敗なし (括弧の数の基準を含む)。
- [ ] **Step 5: コミット**: `git commit -m "feat(host): attach のとき、ビルド全体とアプリの強制終了を省き、UI テストのプロジェクトだけをビルドする"`。

### Task 4: UI テストのひな形 (アタッチモード、`Trigger`)

**Files:**
- Modify: `skills/new-solution/scripts/add_ui_tests.py` (`BASE_CS` の `StartApp` / `StopApp` / `FindIn`、`UiTestBase` への `Trigger` の追加。`UiTrace` は、そのまま使う)
- Test: `tests/ui_tests_gen_test.sh`

**Interfaces:**
- Consumes: 環境変数 `UITEST_ATTACH_PROCESS`、`UITEST_SOLUTION_DIR` (ウォッチャーが渡す)。既存の `AppLocator.SolutionDir()`、`UiDialogs.GetAppWindow(App, Automation, TimeSpan)`、`UiTrace.Write(string)`。
- Produces (生成される `UiTestBase` のメンバー):
  - `protected static string? AttachProcess` (環境変数。空なら null)。`protected bool Attaching => AttachProcess != null`。
  - `StartApp`: `Attaching` なら、`Process` の一覧から、名前が `AttachProcess` で、`MainModule.FileName` が `AppLocator.SolutionDir()` の下のものを、最大 15 秒、150 ms おきに探す。0 件 → `AssertFailedException` (「`<名前>` のプロセスが、ソリューションの下に見つからない。VS で、デバッグを始めたか」)。2 件以上 → `AssertFailedException` (PID の一覧)。1 件 → `Application.Attach(pid)`、`Automation = new UIA3Automation()`、`MainWindow = UiDialogs.GetAppWindow(...)`、`UiTrace.Write($"ATTACHED: {AttachProcess} (pid {pid})")`。`APP_MODEL` などの、アプリへの環境変数の設定は、アタッチのときは、しない (起動済みのため、無意味)。`Attaching` でなければ、今までどおり `Launch`。
  - `protected void Trigger(Action fire)`: すでに `_triggered` なら `AssertFailedException`。`_triggered = true`。`Task.Run(fire)` を最大 3 秒待つ (例外は、再スロー。時間切れは、`UiTrace.Write("TRIGGERED: (fire did not return in 3000 ms; treated as stopped)")`)。戻ったら `UiTrace.Write("TRIGGERED:")`。
  - `FindIn`: `_triggered` なら、探す前に `AssertFailedException` (「きっかけ (`Trigger`) の後は、UI に触れない。止まったアプリは、UIA に応答しない。」)。ただし、アタッチモードでないときは、`Trigger` の後も `Find` を許す (`_triggered` を見るのは `Attaching` のときだけ)。
  - `StopApp`: `Attaching` なら、`UiTrace.Write($"=== {TestName}: {outcome}")` だけ書いて戻る (閉じない・殺さない・スクリーンショットなし・`Automation` の `Dispose` なし)。
  - 例: `MainWindowUiTests.cs` のひな形の先頭のコメントに、`[TestMethod, TestCategory("DebugTrigger")] public void Trigger_ClearButton() { ...; Trigger(() => UiDialogs.Click(Find("ClearButton"))); }` の形の例を、コメントで足す (WPF・WinForms・MFC の既存のコメントの流儀に合わせる)。

- [ ] **Step 1: 失敗するテストを足す** (`ui_tests_gen_test.sh`。WPF・WinForms・MFC の、生成された `UiTestBase.cs` のそれぞれで)
  - `UITEST_ATTACH_PROCESS` と `protected void Trigger(Action fire)` と `ATTACHED:` と `TRIGGERED:` が含まれる。
  - `Application.Attach(` が含まれる。`Attaching` の分岐の中の `StopApp` に `Kill` / `CloseMainWindow` がない (`awk` で `Attaching` の分岐を切り出して確かめる)。
  - `Trigger` の後の `Find` を禁じる文言 (`きっかけ`) が含まれる。
  - プレースホルダー (`__X__`) が残っていない。UTF-8 BOM + CRLF (既存の確認が、そのまま通る)。
  - `--refresh-support-files` で、古い `UiTestBase.cs` が、新しいものに置き換わる (既存の確認を、拡張)。
- [ ] **Step 2: 実行して失敗を確かめる**: `bash tests/ui_tests_gen_test.sh` → 新しい確認が FAIL。
- [ ] **Step 3: `BASE_CS` を実装する**: 上の Interfaces のとおり。C# の構文は、WSL で確かめられないので、既存の `StartApp` / `StopApp` の書き方 (名前空間・`using`・nullable の注釈) を、そのまま真似て、**短く、素直に**書く。`using System.Diagnostics;` など、足りない `using` は、`BASE_CS` の先頭に足す。
- [ ] **Step 4: 実行して成功を確かめる**: `bash tests/ui_tests_gen_test.sh && bash tests/new_solution_wpf_test.sh && bash tests/new_solution_winforms_test.sh` → 失敗なし。
- [ ] **Step 5: コミット**: `git commit -m "feat(ui-tests): UiTestBase のアタッチモードと Trigger (きっかけの後の UI アクセスを禁じる)"`。

### Task 5: `uitest_once.sh --attach`

**Files:**
- Modify: `skills/build-test-loop/scripts/uitest_once.sh`
- Test: `tests/uitest_once_test.sh`

**Interfaces:**
- Consumes: Task 4 が書く `ui-trace.txt` の行 (`ATTACHED: <名前> (pid N)` / `TRIGGERED:`。行頭に時刻)。Task 2 の `attach=<名前>` (flag の 1 行)。
- Produces: `uitest_once.sh <dir> [timeout] --attach <名前> [--ui-timeout N] [--filter 式] [--project 名前]`。flag に `attach=<名前>` と `desktop=visible` を書く。**併用不可 (BAD_ARGS、rc=2):** `--separate`、`--present`、`--hold`、`--preview`、`--slowmo`。プロセス名は `^[A-Za-z0-9_.-]+$` (違えば BAD_ARGS)。待ち時間の既定は、`--attach` のとき 180 秒 (ビルドは UI テストのプロジェクトだけで、制限時間は 60 秒のため)。結果の後、`ui-trace.txt` から、`ATTACHED:` と `TRIGGERED:` の行 (時刻を除く) を、`attach: ` を付けずに、そのまま出す。**`attach` で実行したのに、`ATTACHED:` の行がなければ**、1 行目を `ATTACH_UNSUPPORTED` に変え (rc=8)、`UiTestBase.cs が古い。add_ui_tests.py "<dir>" --refresh-support-files で更新する` を出す (ただし、結果が `BUILD_FAILED` / `TIMEOUT` / `WATCHER_NOT_RUNNING` などのときは、これを出さず、元の結果を返す)。`--attach` のとき、スクリーンショットの一覧は、出さない。

- [ ] **Step 1: 失敗するテストを足す** (`uitest_once_test.sh`。既存の疑似ウォッチャーの形に合わせる)
  - `--attach PS5`: flag の中身に、`attach=PS5` と `desktop=visible` が含まれる (`capture_watcher` の形)。
  - 疑似ウォッチャーが `ui-trace.txt` に `ATTACHED: PS5 (pid 12)` と `TRIGGERED:` を書いて `PASSED` → 出力に、両方の行が (時刻なしで) あり、rc=0。
  - `ATTACHED:` の行がない `PASSED` → 1 行目が `ATTACH_UNSUPPORTED` で、rc=8、`--refresh-support-files` を含む。
  - `BUILD_FAILED` → `ATTACH_UNSUPPORTED` にならない (元の結果のまま)。
  - BAD_ARGS (rc=2): `--attach` を名前なしで、`--attach "a b"`、`--attach 'x"y'`、`--attach PS5 --separate`、`--attach PS5 --present --filter x`、`--attach PS5 --hold 5`。
- [ ] **Step 2: 実行して失敗を確かめる**: `bash tests/uitest_once_test.sh` → 新しいケースが FAIL。
- [ ] **Step 3: 実装する**: 引数の解釈 (`--attach`)、併用の検査、flag への追記、待ち時間の既定、出力の後処理。冒頭の Usage のコメントに、`--attach` の説明を足す。`rc=8` が、ほかの終了コード (0〜7) と衝突しないことを、`build_test_once.sh` のコメントで確かめる (衝突するなら、空いている番号にして、テストと文書を合わせる)。
- [ ] **Step 4: 実行して成功を確かめる**: `bash tests/uitest_once_test.sh && bash tests/fake_watcher_test.sh` → 失敗なし (`fake_watcher_test.sh` の `FAILED` の表示は、疑似の失敗テストの想定出力)。
- [ ] **Step 5: コミット**: `git commit -m "feat(build-test-loop): uitest_once.sh --attach (ATTACHED / TRIGGERED の確認と ATTACH_UNSUPPORTED)"`。

### Task 6: Skill・文書・版

**Files:**
- Modify: `skills/vs-debug/SKILL.md`, `skills/build-test-loop/references/ui-tests.md`, `README.md`, `docs/USAGE.md`, `CHANGELOG.md`, `docs/TEST-PLAN.md`, `poc/attach-debug/README.md`, `VERSION`, `host-tools/HOST_VERSION`
- Test: 既存の文書の検査 (`tests/usage_guide_test.sh`, `tests/skill_paths_test.sh`, `tests/claude_md_size_test.sh`, `tests/ui_test_first_skill_test.sh`)

**Interfaces:**
- Consumes: Task 1〜5 のフラグ・引数・出力の名前 (`--no-wait`、`--attach`、`DebugTrigger`、`Trigger`、`ATTACHED:` / `TRIGGERED:`、`ATTACH_UNSUPPORTED`)。

- [ ] **Step 1: `vs-debug/SKILL.md` に節を足す**: 「UI 操作をきっかけにデバッグする」: 設計書の第 5 節の 4 手順、きっかけ専用のテストの書き方 (`DebugTrigger`、最後の操作が `Trigger`、その後に UI へ触れない)、できないこと (別のデスクトップ、きっかけの後の UIA の読み取り)、`ATTACH_UNSUPPORTED` のときの `--refresh-support-files`。`--no-wait` の行を、モードの表に足す。
- [ ] **Step 2: `ui-tests.md` に、`--attach` と `DebugTrigger` の説明を足す**。普通の実行が `DebugTrigger` を除くことも書く。
- [ ] **Step 3: `README.md` / `docs/USAGE.md` / `CHANGELOG.md`**: 機能の説明と、2.106.0 の項。`docs/TEST-PLAN.md` に、実機確認の項 (2-71: 第 10 節の 5 点。結果は空欄) を足す。`poc/attach-debug/README.md` に、**試作の結果の表** (設計書の第 3 節) と、「正式な実装は `uitest_once.sh --attach`」の 1 行を足す。
- [ ] **Step 4: 版を上げる**: `VERSION` を `2.106.0`、`host-tools/HOST_VERSION` を `2.106.0`。`grep -rn "2\.105\.6" --include=*.md --include=VERSION .` で、版を書いている箇所 (CHANGELOG と README の現行版など) を確かめ、合わせる。
- [ ] **Step 5: 全テストを実行する**: `for t in tests/*.sh; do bash $t || echo "FAILED: $t"; done` と `bash tools/check-formats.sh` → `FAILED:` は、`fake_watcher_test.sh` の想定出力だけ。
- [ ] **Step 6: コミット**: `git commit -m "docs: UI 操作をきっかけにしたデバッグ (--attach / --no-wait) の手順と、2.106.0"`。

### Task 7: 実機での確認 (ユーザーの作業を含む)

**Files:** なし (結果は、`docs/TEST-PLAN.md` の 2-71 に記録する)。

- [ ] **Step 1: 配布**: `./install/install.sh --host-only && ./install/install.sh --skills-only` (ユーザーがマージした後)。ウォッチャーを、確認用フォルダごとに、起動し直す。`cat ~/.claude/skills/vs-debug/VERSION` が 2.106.0 であること。
- [ ] **Step 2: WPF (PS5)**: `add_ui_tests.py "<PS5>" --refresh-support-files` で、ひな形を更新し、きっかけ専用のテスト (`Trigger_ClearButton`。`DebugTrigger`) を足す。`vs_once.sh "$SLN" --break PS5/ViewModels/MainViewModel.cs:<Clear の行> --debug --no-wait` → `uitest_once.sh "$SLN" --attach PS5` → `vs_once.sh "$SLN" --inspect`。**期待:** (a) `ATTACHED:` と `TRIGGERED:` が出る、(b) `--inspect` が、すぐ、`STOPPED:` と `LOCALS:` を返す、(c) アプリが、生きている (殺されていない)。
- [ ] **Step 3: MFC (MfcScope の UiLayerHost)**: 同じ手順。プロセス名は `UiLayerHost`。きっかけは、`UiDialogs.Click(Find("3004"))` (BM_CLICK の Post)。`OnClear()` に、ブレークポイントを置く。
- [ ] **Step 4: 縛りの確認**: きっかけの後に `Find` を呼ぶテストを、わざと書き、すぐ、「きっかけの後は、UI に触れない」で失敗すること。古いひな形 (更新前) で `--attach` → `ATTACH_UNSUPPORTED`。
- [ ] **Step 5: 普通の UI テスト** (`--attach` なし) が、今までどおり動き、`DebugTrigger` のテストを実行しないこと。
- [ ] **Step 6: 結果を、TEST-PLAN の 2-71 に記録し、コミットする** (ユーザーが、PR をマージする)。
