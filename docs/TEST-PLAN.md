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

### 1-1b. ビルドの出力の表示 (`Invoke-BuildScript`)

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| H6 | ウォッチャーを起動して、`trigger_build.flag` を置く | **別のコンソール (ウィンドウ / タブ) が、開かない。** `[VS]` `[MSBuild]` `[BUILD]` と、MSBuild の出力が、**ウォッチャーの画面に**、ビルド中に、1 行ずつ流れる | ✗ |
| H7 | 日本語のエラーを含むビルド (構文エラーを 1 行入れる) | エラーメッセージの日本語が、文字化けせずに、ウォッチャーの画面に出る。ビルド後も、ウォッチャーの画面の表示が、乱れない (`chcp` の影響なし) | ✗ |
| H8 | H6 の結果 | `build_result.txt` (`SUCCESS` / `FAILED`)、`build_error.log` が、従来どおり (H1〜H3 と同じ)。終了コードが、環境エラー (10〜14) のときも、`[ENVIRONMENT ERROR ...]` が付く | ✗ |

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

### 1-2b. GoogleTest のソース取得 (`trigger_gtest.flag`)

Windows 側が GitHub に届く環境で行う。**手書きの PowerShell なので、最初の実機確認が必要。**

| # | 手順 | 期待結果 | 状況 |
|---|---|---|---|
| G1 | ウォッチャーを起動し、`New-Item trigger_gtest.flag -ItemType File` | フラグが消える。`ThirdParty\googletest\` に `include\gtest\gtest.h`、`src\gtest-all.cc`、`src\gtest_main.cc`、`LICENSE`、`VERSION.txt` (`v1.17.0`)。`gtest_result.txt` = `OK`。`gtest_error.log` なし | ✗ |
| G2 | G1 の直後に、もう一度、フラグを置く | **何も再取得せず**、すぐ `OK` (冪等。画面に `is already in`) | ✗ |
| G3 | フラグの 1 行目に、別のタグ (`release-1.12.1`) を書いて置く | そのタグのソースに、置き換わる。`VERSION.txt` が変わる | ✗ |
| G4 | フラグの 1 行目に、不正なタグ (`v1;calc`) | `FAILED`。`gtest_error.log` の先頭が `[ENVIRONMENT ERROR ...]`、`invalid GoogleTest tag`。**コマンドは、実行されない** | ✗ |
| G5 | 存在しないタグ (`v9.99.9`) | `FAILED`。git の失敗と、zip の失敗が、ログに残る | ✗ |
| G6 | ネットワークを切って (またはプロキシで遮断して) G1 | `FAILED`。ネットワークの失敗が、ログに残る。ウォッチャーは、止まらない | ✗ |
| G7 | git を PATH から外して G1 | zip のダウンロードで、取得できる | ✗ |
| G8 | G1 のあと、`trigger_test.flag` と同時に置く | gtest が先に処理され、そのあと、ビルド + テスト | ✗ |

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
| S11 | **同じ未宣言の識別子を、複数のファイルで使う** (例: ヘッダの宣言を消す)。`cpp-auto-build` で、ビルドさせる | `FAILED` の出力が、**要約形式**: 見出し `N errors (M unique) in K files`、同じエラーが `[1] ... xN` の 1 つにまとまり、場所が最大 3 つ。`build_error.log` は、生のまま残る。`.claude-logs/build_summary.json` ができる。Claude は、`[1]` から直し、1 回の再ビルドで、`SUCCESS` | ✗ |
| S12 | **リンクエラー**を起こす (例: 宣言だけで、定義がない関数を呼ぶ)。`cpp-auto-build` で、ビルドさせる | 見出しの内訳に `link N`。`LNK2019` と、続く `LNK1120` が、別の `[n]` として出る。場所が `Foo.obj` などの形でも、要約が崩れない。Claude は、宣言ではなく、定義 / ライブラリ指定を直す | ✗ |
| S13 | S3 の構文エラーを、`cpp-build-test-loop` で起こす | `BUILD_FAILED` の 2 行目以降が、S11 と同じ要約形式。直したあと、テストの段階 (`FAILED` / `PASSED`) に進む | ✗ |
| S14 | S11 の状態で、`PATH` から `python3` を外して (または、`summarize_build_log.py` を退避して) 実行する (WSL 側のみ) | 要約ではなく、**従来の生ログ** (最大 40 行) が出る。1 行目は `FAILED` のまま、rc=1 | ✗ |

### 2-0. `/brainstorm` と `/add-feature`

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| B1 | `/brainstorm 注文の税込み合計` | 質問が、**1 回に 1 つ**。具体例を先に聞く。コード・テスト・プロジェクト・**仕様書**を、作らない。決まらない項目は、「未決」として残す | ✗ |
| B2 | B1 で、メモに残してよいと伝える | `docs/ideas/<名前>.md` (`整理: 未`) が保存される。未決の件数が示され、`/update-from-ideas docs/ideas/<名前>.md` を案内して、自動では、進まない | ✗ |
| B3 | 未決を残したまま、`/update-from-ideas` で、確定したいと言う | 状態を `確定` にしない (未決事項の解消を、促す) | ✗ |
| A1 | `/add-feature` (引数なし) で、`確定` の仕様書が 1 つ | 「これでよいか」を確認する | ✗ |
| A2 | `下書き` の仕様書を渡す / メモだけで、仕様書がない | 実装に進まず、`/update-from-ideas` (メモだけなら、それで整理) を案内して止まる | ✗ |
| A3 | 確定した仕様書を渡す | 計画 (タスク、テストケースと仕様の対応、やらないこと) を示し、**承認を待つ。承認前に、ファイルを、何も作らない** | ✗ |
| A4 | A3 で、計画の修正を依頼 | 計画を直して、再び見せる | ✗ |
| A5 | 承認後、DLL / テスト exe がない状態 | セットアップ → ベースラインが緑 → タスク 1 へ | ✗ |
| A6 | タスクの Red のあと | **テストの確認のゲートで止まる** (計画の承認があっても、飛ばさない)。承認後に、Green に進む | ✗ |
| A7 | 実装中に、計画にない変更が必要になる状況 | 止まって、ユーザーに確認する (計画を直す) | ✗ |
| A8 | 完了 | 全体のビルド + 全テスト `PASSED`、**仕様書の例・境界値・異常系と、テストの対応表**、未確認のこと、テストファイルの一覧が、報告される。`git commit` は、しない | ✗ |
| A9 | 実装中に、仕様の変更を依頼する | 実装を止めて、仕様書を直す (`/brainstorm`) ことを促す | ✗ |

### 2-0c. `/new-solution`

空のフォルダ (例: `C:\...\MFCTDDTest`) を作り、そこで Claude Code を起動して試す。**手書きのプロジェクトが、Visual Studio / ウォッチャーでビルドできるかの、最初の実機確認。**

| # | 指定 | 期待する動き | 状況 |
|---|---|---|---|
| N0 | `/new-solution` (引数なし) | メインの種類、層、テストを**質問する** (`--tests` は、必ず質問)。案 (dry-run の内容) を示して了承を求める | ✗ |
| N1 | `--type mfc --layers none --tests none` | `MFCTDDTest.slnx` と `MFCTDDTest/` (MFC SDI) だけ。テストなし。**ビルドが `SUCCESS`** (`cpp-auto-build`) | ✗ |
| N2 | `--type mfc --layers logic,data --tests none` | メイン + `DataLayer` + `LogicLayer` (DLL)。テストなし。ビルドが `SUCCESS` | ✗ |
| N3 | `--type mfc --layers logic,data --tests gtest` | N2 + `DataLayerTest` / `LogicLayerTest`。GoogleTest が `packages\` にコピーされる。**ビルドとテストが `PASSED`** (2 つのテスト exe) | ✗ |
| N4 | N3 で、フォルダ名が `MFCTDDTest` (`Test` で終わる) | メインに `_Main` の `TargetName` が付く。**`MFCTDDTest_Main.exe` が、テストとして起動されない** (`PASSED`) | ✗ |
| N5 | `--type dll --layers none --tests gtest` | メイン DLL + `<名前>Test`。`PASSED` | ✗ |
| N6 | `--type win32 ...` / `--type console ...` | それぞれ、ビルドが通る | ✗ |
| N3s | N3 の `--gtest source` 版 (`/new-solution --type mfc --layers logic,data --tests gtest --gtest source`) | `gtest` プロジェクトが入る。作成後、ウォッチャーを起動して、`gtest_once.sh` で取得 → `PASSED`。**初回は、`gtest` のコンパイルで、少し長い** | ✗ |
| N3a | コピー元のない環境で `--gtest auto` | `GTEST_MODE: source` / `to-fetch`。ウォッチャーの起動後に、取得 → ベースライン → `PASSED` | ✗ |
| N3b | 取得が `FAILED` (ネットワーク遮断) | 報告して止まり、手動のコピーか、`nuget` 方式への切り替えを案内する | ✗ |
| N13 | `--layer-kind lib` (層を静的ライブラリ) | 層が静的ライブラリ。テストが、リンクできて、`PASSED` | ✗ |
| N14 | `--layers logic:OrderLogic,data:OrderData` | 指定した名前で作成される。ビルドとテストが通る | ✗ |
| N15 | `/new-solution --spec docs/specs/<名前>.md` (構成案あり) | 構成案の内容が、案に反映される (未定の項目は、質問する)。案を見せて、了承を得てから作成 | ✗ |
| N16 | 新規作成のあと、`.gitattributes` を確認し、`git init` → Visual Studio でファイルを編集・保存 → `git status` / `git diff` (WSL の git と Windows の Git の、両方で) | `.gitattributes` ができている (最小版)。**どちらの git でも、改行だけの差分が出ない**。`git ls-files --eol` で、保存が `i/lf` | ✗ |
| N17 | **既存の** C++ ソリューション (`.gitattributes` なし、CRLF のファイルあり) のフォルダで、`/add-feature` を開始 | 最初の読み取り確認で、**1 回だけ**、提案が出る (件数、最小版、導入の手順)。作業は止まらない。「追加する」→ ファイルができ、**git のステージ・コミットはされない**。`git add --renormalize .` を、自分で実行して、改行だけの変更であることを確認 | ✗ |
| N18 | N17 で「今後も見送る」 | `CLAUDE.md` に `- 改行コードの提案: 見送り` が足される。次の `/add-feature` では、提案が出ない | ✗ |
| N19 | LF のみのリポジトリ / git でないフォルダ / `.gitattributes` のあるリポジトリで `/add-feature` | 提案は、出ない (`lf-only` / `not-a-repo` / `ok`) | ✗ |
| N6b | `--type lib --layers none --tests gtest` | 静的ライブラリ + `<名前>Test`。**ビルドとテストが `PASSED`** (テスト exe が、`.lib` をリンクできる) | ✗ |
| N7 | `--type console --layers none --tests gtest` | 矛盾として、エラー (何も書かれない) | ✗ |
| N8 | N2 の後、`/new-solution --tests gtest` (後付け) | `DataLayerTest` / `LogicLayerTest` が増える。`CLAUDE.md` が `テスト: あり` に更新される。`PASSED` | ✗ |
| N9 | すでにソリューションがあるフォルダで、`--tests gtest` なしの `/new-solution` | 何も書かずに、「後付けだけできる」と案内して止まる | ✗ |
| N10 | GoogleTest のコピー元がない環境で、`--tests gtest` | `GTEST_PACKAGE: missing`。コピー元の指定か、Visual Studio での復元を依頼して待つ | ✗ |
| N11 | 作成した `.slnx` を、Visual Studio 2026 で開く | エラーなく開く。プロジェクト構成 (x64 の Debug / Release) が正しい | ✗ |
| N12 | N1〜N2 (テストなし) のあと `/brainstorm` → `/update-from-ideas` → `/add-feature` | テストなしの流れ (計画 → 承認 → 実装 → ビルド確認 → 手動確認)。Red / Green は、出てこない | ✗ |

### 2-0b. `/update-from-ideas`

| # | 準備 | 期待する動き | 状況 |
|---|---|---|---|
| U8 | **メモ** (B2 の出力) を渡す: `/update-from-ideas docs/ideas/<名前>.md` | メモを仕分け (取り込む / 保留 / 別機能 / 却下)、**仕様書の草案の全文**と、「テストに落とせる具体さか」の点検結果を示す。**承認前に、ファイルを作らない** | ✗ |
| U9 | U8 を承認 | `docs/specs/<名前>.md` ができる (未決が 0 件で、「確定」と言えば `確定`。残れば `下書き`)。メモの `整理:` が `済 (→ ...)` になる。メモは、残る | ✗ |
| U10 | U8 で、メモの内容が矛盾している / 足りない | 推測で埋めず、**1 回に 1 つ**質問する | ✗ |
| U11 | ソリューションがない状態で U9 | **構成案** (メインの種類・層・テスト・名前空間と根拠) と、`/new-solution ...` のコマンドを示す。テストは、ユーザーに確認する (`gtest` を勧める)。**自動で、作成しない** | ✗ |
| U12 | ソリューションがある状態で U9 | 構成案は、出さない。`/add-feature docs/specs/<名前>.md` を案内する | ✗ |
| U13 | `整理: 済` のメモを渡す | 対象にしない (ユーザーが明示した場合を除く) | ✗ |


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

`tests/gtest_once_test.sh` が、`gtest_once.sh` (GoogleTest の取得) の結果の分岐を、同様に検証する。

`tests/summarize_build_log_test.sh` が、`summarize_build_log.py` (ビルドエラーの要約) を検証する (11 項目)。同じエラーの集約と件数、最初に出た順、重複する場所の除去、BOM / CR / `N>` の除去、JSON、100 件でも最大 40 行、解釈できないログは rc=3 で何も出さない (生ログへの切り替え)、2 つの Skill のコピーが同一。実機の MSBuild のログでは、S11 / S12 で確認する。

期待する結果 (rc): `PASSED` 0 / `FAILED` 1 (失敗テスト名が先頭) / `BUILD_FAILED` 6 / ビルド環境エラー `ENV_ERROR` 4 /
`TEST_TIMEOUT` 7 / テスト環境エラー `ENV_ERROR` 4 / 失敗が多数 1 (名前 50 件 + `and N more`、詳細は上限あり) /
古いマーカーが消される 0 / `WATCHER_NOT_RUNNING` 3 / `TIMEOUT` 5 / `BAD_ARGS` 2。

## 4. 変更したときの、最低限の確認

| 変更したもの | 最低限、やること |
|---|---|
| `build_once.sh` / `build_test_once.sh` | `tools/check-formats.sh`、`tests/fake_watcher_test.sh` |
| `summarize_build_log.py` | 2 つの Skill のコピーを、同一にして、`tests/summarize_build_log_test.sh`、`tests/fake_watcher_test.sh`。出力の形式を変えたら、2 の S11 / S12 を、実機で (`SKILL.md` の読み方も) |
| `gtest_once.sh` / `watch_and_build.ps1` の gtest 部分 | `tools/check-formats.sh`、`tests/gtest_once_test.sh`。ps1 は、1-2b の G1 / G2 / G4 を、実機で |
| `new_solution.py` | `tools/check-formats.sh`、`tests/new_solution_test.sh`。生成するプロジェクトを変えたら、2-0c の N1〜N3 を、実機で |
| `add_layer.py` | `tools/check-formats.sh`、`tests/add_layer_test.sh`。生成する `.vcxproj` を変えたら、2-1 の F0 を、実機で |
| `watch_and_build.ps1` | 1-2 の T1 / T2 / T4 を、実機で。二重起動の防止を変えたときは 1-4 の M1 / M2 も |
| `build-windows.cmd` / `run_watcher.cmd` | 1-1 の H1 と、R1 を、実機で。CP932 のまま保存されているか (`check-formats.sh`) |
| `SKILL.md` | 新しいセッションで、2 の S1 と、変更に関係する項目 (例: 方針を変えたなら S4)。`cpp-test-first` なら、2-1 の F1 / F3 |
| 契約 (ファイル名・結果の値・終了コード) | ホスト側ツールと Skill の両方、1-2 と 2 の全項目 |
