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
| M1 | ウォッチャーを起動したまま、**同じフォルダ**で、もう 1 つ `run_watcher.cmd` を起動 | 2 つ目のウィンドウに `ERROR: a watcher is already running for this folder: ...` と `Use that window, or close it first.` が出て、`Watcher exited with code 3.` で、キー入力待ち。1 つ目は動き続け、フラグを処理できる | ✔ |
| M2 | 1 つ目のウィンドウを閉じてから、もう一度起動 | 二重起動と判定されず、起動できる (ミューテックスが解放されている) | ✔ |
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
| S9 | プロジェクトの `.claude/settings.json` に `permissions.ask` (`docs/RECOMMENDED-SETTINGS.md`) を設定し、Claude に、**テストファイルを編集**させる (例: S4 の流れ) | 編集の前に、**権限の確認ダイアログ**が出る。拒否すると、Claude が、別の方法 (別のツールやコマンド) で、同じ編集を、行わない | ✗ |
| S9a | S9 の続きで、**同じテストファイルを、もう一度、編集**させる | **2 回目も、確認が出る** (確認の単位は、ツール呼び出し 1 回ごと。公式の記載からの読み取り) | ✗ |
| S9b | S9 の確認ダイアログを、よく見る: 「**このセッションでは、許可**」のような選択肢が、あるか | **あるかどうかを、記録する** (公式に、明記されていない)。ある場合は、選んだあとに、同じファイルを編集させる | ✗ |
| S9c | S9b で、その選択肢を選んだあとの、編集 | **確認が止まるかを、記録する。** 止まる場合は、`ask` が事実上、無効になり、設定の目的が損なわれる。フックや `deny` との併用を、検討する (`docs/RECOMMENDED-SETTINGS.md` 4 章) | ✗ |
| S9d | `acceptEdits` (編集の自動承認) モードで、テストファイルを編集させる | **確認が出る** (公式: 明示的な `ask` ルールに一致するものは、どのモードでも、自動承認されない)。確認で「セッション許可」を選んだ場合の挙動は、記録する | ✗ |
| S9e | **本体のソース** (`DoubleBufferSample/` 配下) を、編集させる (例: S2) | **確認は、出ない。** テストプロジェクト以外の編集は、影響を受けない | ✗ |
| S9f | ビルドエラーの修正で、テストプロジェクトの `.vcxproj` を、編集させる | 確認が出る (`**/*Test/**` に一致するため)。ビルドの設定の修正でも、出ることを、把握しておく | ✗ |
| S10 | S2 (ソースのバグを直す) を実行する | 完了時の報告に、**変更ファイルの一覧**と、「テストファイルの変更なし」が、含まれる。`git commit` / `git push` は、実行されない。変更がない場合 (S1) は、「変更なし」で、`git status` を実行しない | ✗ |

### 2-0. `/brainstorm` と `/add-feature`

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| B1 | `/brainstorm 注文の税込み合計` | 質問が、**1 回に 1 つ**。具体例を先に聞く。コード・テスト・プロジェクトを、作らない。確定の合図まで `下書き` | ✗ |
| B2 | B1 で、確定と伝える | `docs/specs/<名前>.md` が、`状態: 確定` で保存される。`/add-feature docs/specs/<名前>.md` を案内して、自動では、進まない | ✗ |
| B3 | 未決事項を残したまま、確定したいと言う | 状態を `確定` にしない (未決事項の解消を、促す) | ✗ |
| A1 | `/add-feature` (引数なし) で、`確定` の仕様書が 1 つ | 「これでよいか」を確認する | ✗ |
| A2 | `下書き` の仕様書を渡す | 実装に進まず、`/brainstorm` を案内して止まる | ✗ |
| A3 | 確定した仕様書を渡す | 計画 (タスク、テストケースと仕様の対応、やらないこと) を示し、**承認を待つ。承認前に、ファイルを、何も作らない** | ✗ |
| A4 | A3 で、計画の修正を依頼 | 計画を直して、再び見せる | ✗ |
| A5 | 承認後、DLL / テスト exe がない状態 | セットアップ → ベースラインが緑 → タスク 1 へ | ✗ |
| A6 | タスクの Red のあと | **テストの確認のゲートで止まる** (計画の承認があっても、飛ばさない)。承認後に、Green に進む | ✗ |
| A7 | 実装中に、計画にない変更が必要になる状況 | 止まって、ユーザーに確認する (計画を直す) | ✗ |
| A8 | 完了 | 全体のビルド + 全テスト `PASSED`、**仕様書の例・境界値・異常系と、テストの対応表**、未確認のこと、テストファイルの一覧が、報告される。`git commit` は、しない | ✗ |
| A9 | 実装中に、仕様の変更を依頼する | 実装を止めて、仕様書を直す (`/brainstorm`) ことを促す | ✗ |

### 2-0b. `/update-from-ideas`

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| U1 | 確定した仕様書 + `/update-from-ideas docs/specs/xxx.md 端数は切り上げにしたい` | アイデアを仕分けて (理由つき)、変更案を示し、**承認を待つ。承認前に、ファイルを変えない** | ✗ |
| U2 | `docs/ideas.md` に 3 件 (この機能の変更 / 別機能 / 矛盾するもの) | 取り込む・別機能に分かれる。矛盾するものは、どちらを採るか確認する。別機能は、`docs/ideas.md` に残る | ✗ |
| U3 | 承認後 | 該当する節だけが変わる。`変更履歴` に 1 行。**状態が `変更あり (要再確定)` になる**。再確定の確認が出る | ✗ |
| U4 | U3 のまま `/add-feature` | 実装に進まず、再確定を促して止まる | ✗ |
| U5 | 実装済みの仕様で、期待値が変わるアイデアを取り込む | 影響を受けるテスト・実装を一覧にし、`/add-feature` を案内する。**コードとテストは、変えない** | ✗ |
| U6 | `/add-feature` の実装中に、思いつきを伝える | 実装せずに、`docs/ideas.md` に書き留めて、タスクを続ける | ✗ |
| U7 | アイデアが何もない状態で実行 | 「反映するアイデアがありません」と伝えて終わる | ✗ |

### 2-1. `cpp-test-first` (テストを先に書く)

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| F0 | **セットアップ:** Visual Studio で、空の MFC SDI ソリューション (`ThreeLayerSample`) を作る。そのフォルダで Claude Code を起動し、「データ層とロジック層の DLL と、それぞれのテストを作って」と依頼 | 案 (名前・名前空間) を示して了承を求める → `add_layer.py` で、`DataLayer` / `DataLayerTest`、`LogicLayer` / `LogicLayerTest` を作る → (必要なら) NuGet 復元を依頼 → **ビルドが通り、`PASSED`** (2 つのテスト exe の、ベースラインの各 1 件)。MFC アプリへの配線は、しない。**この F0 が、手書きの `.vcxproj` の、最初の実機の確認** | ✗ |
| F1 | 本体にまだない、簡単な関数 (例: 税込み計算) の追加を、「先にテストを書いて」と依頼 | テストケースの一覧を示す → スタブ (期待値と異なる値を返す) とテストを書く → `FAILED` を、アサーションの失敗 (`Expected` / `Which is`) で確認 → 報告して、確認を待つ。**本物のロジックは、書かない** | ✗ |
| F2 | F1 の続きで、「実装まで続けて」と依頼 | 確認を待たずに、`cpp-build-test-loop` の手順で `PASSED` にする。**テストを変えない** | ✗ |
| F3 | 期待値が、スタブの値と同じになるテストを、混ぜる | `PASSED` (または、そのテストだけが通る) を、**異常として報告**し、実装に進まない | ✗ |
| F4 | 新しい `Test*.cpp` を作らせる (`.vcxproj` への追加が必要) | `.vcxproj` に追加している。追加漏れで、テストが走らないまま `PASSED` にならない | ✗ |
| F5 | 対象を、ダイアログのハンドラ (UI 層) にする | テストを書かずに止まり、ロジックの切り出し案を、示す | ✗ |
| F6 | バグ修正を依頼する | そのバグを再現するテストを、最初の1件にして、`FAILED` を確認してから、直す | ✗ |
| F7 | `permissions.ask` を設定した状態で、F1 | テストファイルの編集で確認が出る。拒否されたら、別の方法で、書かない | ✗ |
| F8 | **データ DLL** に、機能を追加する (例: `FileOrderRepository` に、id で検索する `FindById`) | `DataLayerTest` に書く (`LogicLayerTest` に書かない)。実ファイルは一時フォルダで、`TearDown` で削除する。`=== DataLayerTest.exe ===` の失敗で Red を確認する | ✗ |
| F9 | ロジック DLL に、データ層を使う機能を追加する | `LogicLayerTest` で、**フェイク**を使う (実の `FileOrderRepository` を使わない) | ✗ |
| F10 | F1 のスタブで、**公開マクロを付け忘れる** (誘導する) | `BUILD_FAILED` (`LNK2019`)。**Red とは呼ばず**、マクロを付けて、やり直す | ✗ |
| F11 | ロジックとデータの、両方にまたがる依頼 (例: 保存項目を増やし、その合計も出す) | **層ごとに、順番に**、Red → 確認 → Green を回す。まとめて Red にしない | ✗ |
| F12 | データ層のインターフェース (`IOrderRepository`) に、メソッドを追加する依頼 | 両方のテスト exe に影響が出る (フェイクと実装の両方)。**書いていない層の失敗を、「層をまたぐ影響」として報告する** | ✗ |
| F13 | ソリューションに、データのテスト exe がない状態で、データ層の機能を依頼 | テストを書かずに止まり、テスト exe の作成を、ユーザーに確認する。了承後に、規約どおりに作り、ベースラインが緑になってから Red に進む | ✗ |

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
| `add_layer.py` | `tools/check-formats.sh`、`tests/add_layer_test.sh`。生成する `.vcxproj` を変えたら、2-1 の F0 を、実機で |
| `watch_and_build.ps1` | 1-2 の T1 / T2 / T4 を、実機で。二重起動の防止を変えたときは 1-4 の M1 / M2 も |
| `build-windows.cmd` / `run_watcher.cmd` | 1-1 の H1 と、R1 を、実機で。CP932 のまま保存されているか (`check-formats.sh`) |
| `SKILL.md` | 新しいセッションで、2 の S1 と、変更に関係する項目 (例: 方針を変えたなら S4)。`cpp-test-first` なら、2-1 の F1 / F3 |
| 契約 (ファイル名・結果の値・終了コード) | ホスト側ツールと Skill の両方、1-2 と 2 の全項目 |
