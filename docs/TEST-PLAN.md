# テスト手順書

実機 (Windows + WSL) で行う確認の手順と、期待する結果。
「状況」列は、**この手順書を作った時点 (v1.0.0) の実績**。変更したときは、該当する項目を再確認して、更新する。

凡例: ✔ 実機で確認済み / △ 一部のみ確認 / ✗ 未確認

## 0. 事前準備

- テスト用の C++ ソリューション (`MyApp.sln`): `MyApp` (本体) と `MyAppTest` (GoogleTest、`MyApp` をプロジェクト参照)。
- ホスト側ツール 3 ファイルを、同じフォルダに配置 (例: `C:\tools\cpp-watcher\`)。形式が崩れていないこと。
  ```powershell
  Get-Content C:\tools\cpp-watcher\watch_and_build.ps1 -Encoding Byte -TotalCount 3   # 239 187 191 なら BOM あり
  ```
- Skill を `~/.claude/skills/` (または、プロジェクトの `.claude/skills/`) に配置 → **新しいセッション**で起動。
- ウォッチャーの起動:
  ```bat
  C:\tools\cpp-watcher\run_watcher.cmd C:\path\to\MyApp
  ```
  ヘッダーに `QuickEdit : disabled` が出ること。

以下、`<SLN>` はソリューションフォルダ。PowerShell を、別のウィンドウで開いて、`cd <SLN>` する。

## 1. ホスト側ツール単体 (Claude を介さない)

### 1-1. ビルドのみ (`trigger_build.flag`)

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| H1 | ソースが正常な状態で、`New-Item trigger_build.flag -ItemType File` | フラグが消える。`build_result.txt` = `SUCCESS`。`build_error.log` なし。`test_result.txt` なし | ✔ |
| H2 | 構文エラーを 1 行入れて、同上 | `build_result.txt` = `FAILED`。`build_error.log` に `error C...` の行 (相対パス)、末尾に `Build failed with exit code: 1`。行頭に `2>` がない | ✔ |
| H3 | エラーを直して、同上 | 開始時に、前回の `build_result.txt` / `build_error.log` が消え、`SUCCESS` になる | ✔ |
| H4 | `build-windows.cmd` を一時的に別名にして、同上 | `FAILED`。`build_error.log` の先頭が `[ENVIRONMENT ERROR - not a source code problem]` | ✗ |

### 1-2. ビルド + テスト (`trigger_test.flag`)

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| T1 | 正常な状態で `trigger_test.flag` | `build_result.txt` = `SUCCESS`、`test_result.txt` = `PASSED`。`test_error.log` なし。`.claude-logs\test.log` に各テストの `[       OK ]` | ✔ |
| T2 | テストが落ちるバグを、ソースに入れて同上 | `test_result.txt` = `FAILED`。`test_error.log` に、失敗したテスト名・期待値・実際の値 (`file(line): error:`)、相対パス | ✔ |
| T3 | 構文エラーを入れて同上 | `test_result.txt` = `BUILD_FAILED`。`build_error.log` にエラー | ✔ (Skill 経由のループの中で確認) |
| T4 | ウォッチャーを `-TestTimeoutSec 5` で起動し、同上 | `TIMEOUT`。`test_error.log` に `TIMEOUT after 5s (killed)` と `Hung test ...`。テスト exe のプロセスが残らない (`Get-Process`) | ✔ |
| T5 | `-TestExePattern 'NoSuch\.exe$'` で起動し、同上 | `ENV_ERROR`。`test_error.log` の先頭が `[ENVIRONMENT ERROR ...]` | ✔ |
| T6 | 古い GoogleTest に、`--gtest_brief=1` を `-TestArgs` で渡して同上 | ヘルプだけが出ても、`PASSED` にならず、`ENV_ERROR` (`no gtest summary`) | △ (原因の発見までは実機。修正後の分岐は、単体では未実行) |
| T7 | ビルド中に、ウォッチャーのウィンドウをクリック/選択 | ビルドが止まらない。タイトルバーに `選択` と出ない | ✔ |
| T8 | 別のウォッチャーを、`.slnx` のソリューションで起動し、同上 | `.slnx` を自動検出して、ビルドが通る | ✗ |
| T9 | `-Platform Win32` / `-Configuration Release` で起動し、同上 | exe を `Win32\` / `Release\` から探して、実行する | ✗ |

### 1-3. 起動まわり (`run_watcher.cmd`)

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| R1 | `run_watcher.cmd <dir>` | ヘッダー (`Project / Solution / Build`) が出る。`.slnx` → `.sln` の順で自動検出 | ✔ (`.sln`) |
| R2 | 末尾に `\` を付けて渡す | 同じく起動する (引数が壊れない) | ✗ |
| R3 | フォルダをドラッグ&ドロップ | 起動する | ✗ |
| R4 | スペースを含むパス | 起動する | ✗ |
| R5 | **引数なし**で `run_watcher.cmd` を起動 (`.sln` がない場所に、cmd を置いた場合) | `ERROR: no .sln / .slnx found in ...`、`NOTE: no ProjectDir argument was given ...`、`Usage` と `Example` が出て、キー入力待ち → 終了コード 2 | ✔ (v1.0.1) |
| R6 | 存在しないフォルダを渡す | `ERROR: project folder not found: ...` と `Usage` が出る | ✗ |

### 1-4. 二重起動の防止 (`watch_and_build.ps1`)

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| M1 | ウォッチャーを起動したまま、**同じフォルダ**で、もう 1 つ `run_watcher.cmd` を起動 | 2 つ目のウィンドウに `ERROR: a watcher is already running for this folder: ...` と `Use that window, or close it first.` が出て、`Watcher exited with code 3.` で、キー入力待ち。1 つ目は動き続け、フラグを処理できる | ✗ |
| M2 | 1 つ目のウィンドウを閉じてから、もう一度起動 | 二重起動と判定されず、起動できる (ミューテックスが解放されている) | ✗ |
| M3 | 1 つ目を、タスクマネージャーなどで、強制終了してから、起動 | 同上 (異常終了しても、古いロックが残らない) | ✗ |
| M4 | **別のフォルダ**のウォッチャーが動いている状態で、このフォルダのウォッチャーを起動 | 干渉せずに、起動できる (ミューテックスは、フォルダごと) | ✗ |
| M5 | ps1 を直接起動し、`-TargetDir` の、大文字小文字や、末尾の `\` だけを変える | 同じフォルダとして扱われ、2 つ目は拒否される | ✗ |

## 2. Skill 経由 (Claude Code)

依頼文 (共通):
```
cpp-build-test-loop のSkillを使って、テストが通るまで直してください。
```

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| S1 | 正常な状態 | `PASSED` を受けて、修正せずに、1〜2行で報告して止まる | ✔ |
| S2 | 本体のロジックにバグ (テストが落ちる) | `FAILED` → **ソース側を直す** (テストは変えない) → 再実行 → `PASSED` で止まる。共通の原因を 1 回で直す | ✔ |
| S3 | 構文エラー + (別の) テストが落ちるバグ | `BUILD_FAILED` → 構文エラーを直す → `FAILED` → バグを直す → `PASSED` | ✔ |
| S4 | **テストの期待値を誤った値にする** (ソースは正しい) | ソースを変えずに、**変更前にユーザーへ確認**する (根拠を添えて)。承認後に 1 か所だけ直して `PASSED` | ✔ |
| S5 | ウォッチャーを起動しない | 約 15 秒で `WATCHER_NOT_RUNNING`。ソースを触らず、起動を依頼して止まる。再試行しない | ✔ |
| S6 | `-TestExePattern 'NoSuch\.exe$'` でウォッチャーを起動 | `ENV_ERROR`。ソースもテストも触らず、環境の問題として報告して止まる | ✔ |
| S7 | `-TestTimeoutSec` を、全体の実行時間より短くする | `TEST_TIMEOUT`。直前にソースを変えていなければ、直さず報告して止まる (制限時間の確認を依頼) | ✗ (ホスト側 T4 のみ) |
| S8 | ユーザー Skill (`~/.claude/skills`) のみ配置 (プロジェクト側は退避) | S1 と同じ動き (ユーザー Skill が使われる) | ✔ (S1 のみ) |

**観察する点 (すべての Skill 経由のテスト共通):**
- `build_test_once.sh` を、探し回らずに、`run_in_background: true` (または `timeout` 付き) で実行している。
- 完了通知が来るまで、ファイルを読まない・コマンドを追加しない。
- テストファイル (`Test*.cpp`) を、許可なしに変更していない。
- 報告が短い (成功: 1〜2行)。経過の説明が、少ない。
- 実行後の `git status` / `git diff` で、意図しない変更がない。

## 3. 疑似ウォッチャー (Windows 不要)

`tests/fake_watcher_test.sh` が、`build_test_once.sh` の結果の分岐を、ファイルを書くだけの偽のウォッチャーで検証する。
Skill のスクリプトを変えたときは、Windows に配る前に、これを実行する。

期待する結果 (rc): `PASSED` 0 / `FAILED` 1 (失敗テスト名が先頭) / `BUILD_FAILED` 6 / ビルド環境エラー `ENV_ERROR` 4 /
`TEST_TIMEOUT` 7 / テスト環境エラー `ENV_ERROR` 4 / 失敗が多数 1 (名前 50 件 + `and N more`、詳細は上限あり) /
古いマーカーが消される 0 / `WATCHER_NOT_RUNNING` 3 / `TIMEOUT` 5 / `BAD_ARGS` 2。

## 4. 変更したときの、最低限の確認

| 変更したもの | 最低限、やること |
|---|---|
| `build_once.sh` / `build_test_once.sh` | `tools/check-formats.sh`、`tests/fake_watcher_test.sh` |
| `watch_and_build.ps1` | 1-2 の T1 / T2 / T4 を、実機で。二重起動の防止を変えたときは 1-4 の M1 / M2 も |
| `build-windows.cmd` / `run_watcher.cmd` | 1-1 の H1 と、R1 を、実機で。CP932 のまま保存されているか (`check-formats.sh`) |
| `SKILL.md` | 新しいセッションで、2 の S1 と、変更に関係する項目 (例: 方針を変えたなら S4) |
| 契約 (ファイル名・結果の値・終了コード) | ホスト側ツールと Skill の両方、1-2 と 2 の全項目 |
