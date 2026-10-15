# 変更履歴

形式: [バージョン] 日付 / 変更の要点。契約 (ファイル名・結果の値・終了コード) を変えたときは、そのことを明記する。

## [未リリース] 2026-10-15

### Skill (再配布が必要: `install/install.sh`)
- **ビルドエラーの要約 (`summarize_build_log.py`) を追加:** `cpp-auto-build` の `FAILED` と、`cpp-build-test-loop` の `BUILD_FAILED` で、`build_error.log` の先頭 40 行をそのまま出す代わりに、集約した要約を出す。
  - 同じ (コード, メッセージ) を 1 つにまとめ、件数 (`xN`) と代表の場所 (最大 3 つ) を出す。最初に出たエラー順 (連鎖エラーの原因は先頭側)。
  - 見出しに、総数・種類数・ファイル数・コンパイル/リンクの内訳。解釈できない行は、最大 5 行を `other:` として残す。出力は最大 40 行・1 行 400 文字。
  - 同じ内容を `.claude-logs/build_summary.json` にも書く (`.gitignore` 済み)。
  - `python3` がない場合や、解釈できるエラー行がない場合は、従来の生ログ表示に戻る。`ENV_ERROR` は従来どおり生ログ。
  - スクリプトは、2 つの Skill に同一のコピーを置く (`tests/summarize_build_log_test.sh` で一致を確認)。
- **テスト失敗の要約 (`summarize_test_log.py`) を追加 (`cpp-build-test-loop` のみ):** `FAILED` で、`test_error.log` の生の詳細の代わりに、集約した要約を出す。
  - **同じメッセージの失敗を 1 つにまとめる** (`xN`、テスト名は最大 5、場所は最大 3、出現順)。見出しに、失敗数とスイートごとの件数。`Expected` / `Which is` は `|` で区切って 1 行に。
  - 解釈できない行 (クラッシュの報告など) は、最大 8 行を `other:` に残す。全テスト名と、テストごとの場所・メッセージは、`.claude-logs/test_summary.json`。出力は最大 40 行。
  - 失敗したテスト名を 1 つも解釈できない (クラッシュなど) 場合と、`python3` がない場合は、従来の表示 (`Failed tests (N):` の一覧と詳細) に戻る。`TEST_TIMEOUT` / `ENV_ERROR` は従来どおり。
  - 従来の、失敗名を 50 件まで列挙する出力は、集約により、`tests:` が組ごとに最大 5 件になった (全名は JSON)。
- **警告の件数の通知 (成功時):** `SUCCESS` (`build_once.sh`) / `PASSED` (`build_test_once.sh`) の次の行に、警告があれば**1 行だけ**出す (`warnings: 12 (5 unique): C4244 x5, C4996 x3, C4101 x2, ... (+2 more)`)。警告がなければ、何も出ない。
  - `summarize_build_log.py` に、`--severity warning` (警告の集約)、`--root <dir>` (Windows のフルパスを相対パスに。`warnings.log` は、フルパスのまま)、`--oneline` を追加した。詳細は、同じスクリプトで読む。`.claude-logs/warnings_summary.json` にも書く。
  - **警告は、結果 (1 行目と終了コード) に影響しない。** 直すのは、ユーザーに頼まれたときだけ (`SKILL.md`)。**差分ビルドでは、再コンパイルされたファイルの警告だけ**が出る。`.claude-logs/warnings.log` がない (`-LogDir` で別の場所にした) 場合は、何も出ない。
- 両 `SKILL.md` に、「エラー出力の読み方 (要約形式)」を追加した (上の `[n]` から直す、`LNK` の扱い、`build_summary.json`、要約が出ない場合)。
- **契約 (ファイル名・結果の値・終了コード) の変更は、ない。** ホスト側ツール (ウォッチャー) の再配布は、不要。

### ツール・文書
- `tests/summarize_build_log_test.sh` に、警告の項目を追加した (9 項目。計 20 項目)。`tests/fake_watcher_test.sh` に、`PASSED` + 警告の行のケースを追加した。
- `tests/summarize_test_log_test.sh` を追加 (集約・パラメータ化テスト名・Linux 形式・上限・JSON・クラッシュ時のフォールバック。15 項目)。`cpp-build-test-loop/SKILL.md` に「テスト失敗の要約の読み方」を追加した。
- `tests/summarize_build_log_test.sh` を追加 (集約・並び・重複の除去・上限・JSON・フォールバック・コピーの一致。11 項目)。`tests/fake_watcher_test.sh` の `BUILD_FAILED` が要約形式になった。
- 実機の MSBuild / リンカのログでは、未確認 (サンプルのログのみ)。`docs/DESIGN.md` は未更新。

## [1.4.0] 2026-10-14

### Skill (再配布が必要: `install/install.sh`)
- **`new-solution` (`/new-solution`) を追加:** カレントのフォルダに、**フォルダ名と同名の `.slnx`** と、メインのプロジェクト (フォルダ名そのまま。`App` などは付けない) を作る。
  メインの種類は、MFC SDI / Win32 / コンソール / DLL / **静的ライブラリ**。**層 (`--layers`) とテスト (`--tests`) は、独立した 2 つの軸**で、引数で指定できる (省略したら質問。`--tests` は、必ず質問)。
  テストは、あとから後付けできる (すでにあるソリューションで `--tests gtest` を再実行)。設定は、`CLAUDE.md` の `層:` / `テスト:` に記録される。
  層の名前は、既定 (`LogicLayer` / `DataLayer`) で作り、変更は作成後 (`DLL-LAYOUT.md` に、変更するときの、直す箇所の一覧)。
- **流れを 3 段にした: `/brainstorm` (メモ) → `/update-from-ideas` (整理して、正式な仕様書) → `/add-feature` (実装)。**
  `/brainstorm` の成果物を、仕様書ではなく、**メモ (`docs/ideas/<機能名>.md`)** にした (決まらない項目は「未決」)。
  `/update-from-ideas` に、**新規作成モード (メモ → 仕様書)** を追加した (草案の全文を見せて承認。テストに落とせる具体さの点検。未決が残る間は `確定` にしない)。
  ソリューションがない場合は、仕様書のあとに、**構成案** (メインの種類・層・テスト・名前空間) と `/new-solution` のコマンドを提案する (仕様が先)。`/add-feature` は、メモだけがあるときに、`/update-from-ideas` を案内する。
- **`/add-feature` / `/brainstorm` / `cpp-test-first` が、テストの有無で動きを切り替える:** `テスト: あり` は、従来の TDD (Red → Green)。`テスト: なし` は、計画 → 承認 → 実装 → ビルド確認 → 手動確認。
  `cpp-test-first` のセットアップは、「層やテストを、あとから足すとき」に縮めた (最初の作成は `/new-solution`)。
- **`add_layer.py`:** `--tests none|gtest` (層だけ / 層 + テスト)、`--tests-only` (既存の DLL / 静的ライブラリにテストだけを足す)、`--kind dll|lib` (静的ライブラリ。公開マクロなし)、`--gtest-from` を追加。
  テストを作るとき、`packages\` に GoogleTest がなければ、**既存のもの (兄弟フォルダなど) を、コピーする** (ネットワークは使わない)。
  **exe のメインの名前が `Test` / `Tests` で終わる場合は、`<TargetName>` を `<名前>_Main` にする** (ウォッチャーが、アプリを、テストとして起動しないように)。
- 契約 (ファイル名・結果の値・終了コード) の変更は、ない。ホスト側ツールの再配布は、不要。

### ホスト側ツール (再配布が必要: `install/install.sh`)
- **`watch_and_build.ps1`: GoogleTest のソース取得 (`trigger_gtest.flag`) を追加。** Windows 側が GitHub から、固定タグのソースを取得して、`ThirdParty\googletest\` に置く
  (git clone、なければ zip。同じタグなら何もしない)。完了マーカー `gtest_result.txt` (`OK` / `FAILED`)、失敗時は `gtest_error.log`。`-GtestTag` (既定 `v1.17.0`)。
  **契約の拡張** (ファイル名の追加。既存の契約は変わらない)。DESIGN の契約表に追記。**手書きの PowerShell で、実機未確認** (TEST-PLAN の G1〜G8)。

- **`watch_and_build.ps1`: ビルド (`build-windows.cmd`) の出力が、別のコンソールに出る問題への対策。** `cmd.exe /c` を、専用の、表示しないコンソール (`CreateNoWindow`) で実行し、出力をパイプで受け取って、ウォッチャーの画面に、1 行ずつ流す
  (テストの出力と同じ画面)。バッチの `chcp` が、ウォッチャーのコンソールに影響しなくなる。`build-windows.cmd` は変更なし。**手書きで、実機未確認** (TEST-PLAN の H6〜H8、DESIGN 4.20)。

### Skill の追加機能
- **`--gtest auto|nuget|source`:** GoogleTest の入れ方。`source` は、ソースをソリューション内の静的ライブラリ `gtest` としてビルドする (NuGet 不要、新しい GoogleTest、ランタイムの不一致なし)。
  `auto` は、パッケージをコピーできれば `nuget`、できなければ `source` (取得は、`gtest_once.sh` でウォッチャーに依頼)。
- **`--layer-kind dll|lib`:** 層を、静的ライブラリにできる。 **`--layers logic:OrderLogic,data:OrderData`:** 層の名前を、作成時に指定できる (既定の動きは、変わらない)。
- **`--spec <仕様書>`:** 仕様書の `## 構成案` から、メインの種類・層・テスト・名前空間を読む (明示した引数が優先。未定の項目は、質問する)。`/update-from-ideas` の構成案を、この形式にした。
- `add_layer.py`: `--gtest`、`.cc` のソースの取り込み (GoogleTest 用)、`gtest` プロジェクトの生成。

- **`/new-solution`: 新規作成のときに、`.gitattributes` も作る** (すでにあれば、上書きしない。後付けでは、作らない)。`* text=auto eol=crlf` を中心にした、拡張子を列挙しない最小版
  (保存は LF、作業フォルダは CRLF。`*.sh` だけ LF)。WSL の git と Windows の Git の、どちらで操作しても、同じ結果になる。既存のリポジトリには、自動で足さず、提案する。

- **既存プロジェクトの、改行コードの規則の検出と提案:** `new_solution.py --check-git` (読み取りだけ。状態: `ok` / `propose` / `lf-only` / `declined` / `not-a-repo` / `unknown`) と、`--add-gitattributes` (最小版を作る。git の操作はしない)。
  `/add-feature` の最初の読み取り確認が、`propose` のときだけ、1 回、提案する (追加する / 今回は見送る / 今後も見送る)。`/new-solution` に、「C. 改行コードの規則の確認と追加」を追加。

- **`/add-feature`: 改行コードの規則の確認を、手順の最初 (0a.) に、必ず実行する形にした** (実機で、提案が出なかった。確認のコマンドが、別の Skill の `scripts/` を指すだけで、パスが曖昧だったため、`~/.claude/skills/new-solution/scripts/new_solution.py` を明記し、状態ごとの行動を表にした)。
- **`/new-solution` が作る `.gitignore` に、ウォッチャーの一時ファイル (`.claude-logs/`、`trigger_*.flag`、`*_result.txt`、`*_error.log`) を追加** (実機で、`git add -A` に、これらが入っていた)。

### ツール・文書
- `tests/gtest_once_test.sh` を追加 (取得の結果の分岐。14 項目)。`tests/new_solution_test.sh` に、source 方式・層の種類と名前・`--spec` を追加 (129 項目。`.gitattributes` の生成、実際の git での動作、既存プロジェクトの検出と提案を含む)。
- `tests/new_solution_test.sh` を追加 (層・テストの組み合わせ、後付け、静的ライブラリ、不正な入力。72 項目)。`tests/add_layer_test.sh` に、`--tests none` / `--tests-only` を追加。
- `docs/DESIGN.md` に 4.18、`docs/TEST-PLAN.md` に 2-0c (N0〜N12、N6b) と、U8〜U13 を追加 (B1〜B3、A2 を、メモ → 仕様書の流れに合わせて修正)。

## [1.3.0] 2026-10-13

### Skill (再配布が必要: `install/install.sh`)
- **`cpp-test-first` を追加:** 実装の前に、GoogleTest のテストを先に書き、スタブで、**アサーションで失敗する (Red)** ことを確認する。
  `PASSED` (空振り) と `BUILD_FAILED` (スタブなし) を、正しい Red として扱わない。確認のあと、`cpp-build-test-loop` に引き渡す (Green)。
  実行は、`cpp-build-test-loop` の `build_test_once.sh` を使う。スクリプトは持たない。
- **構成: MFC アプリ + ロジック DLL + データ DLL + DLL ごとのテスト exe (`<DLL名>Test.exe`)** を前提にした。
  対象の層を決める手順 (0.)、層ごとのテストの書き方 (ロジック: フェイク / データ: 一時フォルダの実ファイル)、DLL の公開マクロの付け忘れ (`LNK2019`) の扱い、
  層をまたぐ依頼は層ごとに順番に回す、を追加。構成と規約は、同梱の `DLL-LAYOUT.md`。
- **`brainstorm` (`/brainstorm`) と `add-feature` (`/add-feature`) を追加:** 壁打ちで仕様を固めて `docs/specs/<機能名>.md` に保存し、確定した仕様から、計画 → 承認 → テスト先行 (Red) → テストの確認 → 実装 (Green) → 検証を、ゲートを挟んで進める。
  どちらも、ユーザーが `/` で呼んだときだけ動く (`disable-model-invocation: true`)。`add-feature` は、手順の中身を、`cpp-test-first` と `cpp-build-test-loop` に任せる。
- **`update-from-ideas` (`/update-from-ideas`) を追加:** アイデアを、取り込む・保留・別機能・却下に仕分けて、承認後に、正式な仕様書へ反映する。
  確定した仕様に変更が入ると、状態が `変更あり (要再確定)` になり、変更履歴が残る。実装済みの場合は、影響を受けるテストを示して `/add-feature` に渡す。
  仕様書の状態に `変更あり (要再確定)` を追加し (`brainstorm` の様式)、`add-feature` / `cpp-test-first` が、これを未確定として扱う。
- **セットアップ (DLL とテスト exe がない場合) を追加:** Visual Studio で作った、ソリューション + MFC アプリから、データ層 → ロジック層の DLL と、各テスト exe を作る。
  生成は、同梱の `scripts/add_layer.py` (`.sln` / `.slnx` に対応、x64 のみ)。ベースラインが緑になってから、Red に進む。
- 契約 (ファイル名・結果の値・終了コード) の変更は、ない。ホスト側ツールの再配布は、不要。

### ホスト側ツール (再配布が必要)
- **`build-windows.cmd` / `watch_and_build.ps1`: MSBuild/cl.exe のビルド出力が文字化けする問題を修正。**
  `build-windows.cmd` の MSBuild.exe 呼び出しの直前後だけ `chcp 65001` / `chcp 932` を切り替え (ファイル自体は CP932 のままで、間に挟まる日本語の `rem` コメントは、この区間の外に置いた)。
  `watch_and_build.ps1` は、`[Console]::OutputEncoding = UTF8` を設定し、パイプで受け取る MSBuild/cl.exe の UTF-8 出力を正しく復号する。
  契約 (ファイル名・結果の値・終了コード) の変更は、ない。

### ツール
- `tests/add_layer_test.sh` を追加 (疑似ソリューションで、`add_layer.py` を検証)。`tools/check-formats.sh` が、`*.py` を検証する。

### 文書
- `docs/DESIGN.md` に 4.16、`docs/TEST-PLAN.md` に 2-0 (B1〜B3、A1〜A9)、2-0b (U1〜U7) と 2-1 (F0〜F13) を追加。README の構成表を更新。

## [1.2.0] 2026-10-13

### Skill (再配布が必要: `install/install.sh`)
- `cpp-auto-build` / `cpp-build-test-loop`: **「完了時の確認 (変更の報告)」を追加。** 完了時 (成功でも停止でも) に、変更したファイルを一覧し (`git -c core.fileMode=false --no-optional-locks status --short`)、
  **テストファイルの変更の有無を、報告の冒頭で明示する。** `git commit` / `git push` は、ユーザーの明示的な指示がない限り、実行しない。
  自分がファイルを編集していない場合は、実行しない。権限の確認が、拒否された場合に、別の方法で、同じ操作をしない、という規定も、追加した。
- 契約 (ファイル名・結果の値・終了コード) の変更は、ない。ホスト側ツールの再配布は、不要。

### 文書
- `docs/RECOMMENDED-SETTINGS.md` を追加: テストファイルの編集と `git commit` に、確認を付ける、権限設定 (`permissions.ask`) の例、仕様、限界、フックを採用しない理由。
- `docs/DESIGN.md` に 4.15、`docs/TEST-PLAN.md` に S9 / S10 を追加。

## [1.1.0] 2026-10-13

### ホスト側ツール
- **`watch_and_build.ps1`: 二重起動の防止:** 同じプロジェクトフォルダで、すでにウォッチャーが動いていれば、メッセージを出して、**終了コード 3** で終了する
  (名前付きミューテックス。プロセスの終了で、自動的に解放される)。同じフラグを、2 つのウォッチャーが奪い合って、結果が混ざるのを防ぐ。
- 契約 (ファイル名・結果の値・Skill のスクリプトの終了コード) の変更は、ない。Skill の再配布は、不要。

## [1.0.1] 2026-10-12

### ホスト側ツール
- `run_watcher.cmd`: 引数なしで起動したときの、案内を改善した。
  - 従来は、`ERROR: no .sln / .slnx found in <このファイルのフォルダ>` とだけ出て、原因が分かりにくかった。
  - 引数なしで、このファイルのフォルダが対象になったことを、`NOTE:` で知らせ、使い方 (`Usage` と `Example`) も表示する。
  - プロジェクトフォルダが存在しない場合も、使い方を表示する。
- 契約 (ファイル名・結果の値・終了コード) の変更は、ない。Skill の再配布は、不要。

## [1.0.0] 2026-10-12

最初のリリース (実機で、動作を確認した状態)。

### ホスト側ツール
- `watch_and_build.ps1`: `trigger_build.flag` (ビルド) と `trigger_test.flag` (ビルド + GoogleTest) を監視する。
  結果は、`build_result.txt` / `test_result.txt` (完了マーカー) と、`build_error.log` / `test_error.log`。
- `build-windows.cmd`: vswhere で最新のリリース版 VS (C++) を検出し、VsDevCmd の環境で MSBuild を実行する。
  `.claude-logs/` に、`build.log` / `errors.log` / `warnings.log` を出力する。
- `run_watcher.cmd`: プロジェクトフォルダを指定して、ウォッチャーを起動する。`.slnx` / `.sln` を自動検出する。
- ログ中のパスを、ソリューションフォルダからの相対パスに変換する。
- テストの判定: 終了コード 0 でも `[  PASSED  ]` の行がなければ、`ENV_ERROR` (テストが走っていないのを、成功と誤認しない)。
- テストの制限時間 (既定 120 秒): 超えたら、子プロセスごと強制終了し、実行中のテスト名を `Hung test` として記録する。
- 起動時に、コンソールのクイック編集モードを無効化する (クリックで、ビルドが止まるのを防ぐ)。
- 文字コード: `.cmd` は CP932 (日本語のコメント付き)、`.ps1` は BOM 付き UTF-8。

### Skill
- `cpp-auto-build`: ビルドのみのループ (成功まで、最大 5 回)。
- `cpp-build-test-loop`: ビルド + テストのループ。ソース側を優先して直し、テストの期待値の誤りは、変更前にユーザーへ確認する。
  `ENV_ERROR` / `WATCHER_NOT_RUNNING` では、ソースもテストも直さずに止まる。
  `TEST_TIMEOUT` では、直前にソースを変更していない場合は、直さずに報告して止まる。
- 待機は、バックグラウンドで1回のコマンドにし、待機中は何も読まない (古い結果の誤読を防ぐ)。
- スクリプト (`build_once.sh` / `build_test_once.sh`): 制限時間が数値でない場合は、`BAD_ARGS` (rc=2) で、すぐ終了する
  (数値でないと、待機ループの比較が毎回エラーになり、永久に待ち続けるため)。

### リポジトリ
- `install/install.sh`、`tools/check-formats.sh`、`tests/fake_watcher_test.sh`、`docs/DESIGN.md`、`docs/TEST-PLAN.md`。

### 既知の制限
- GoogleTest のみ。実行が重なったときの、古い結果の誤読は、未対策 (`docs/DESIGN.md` 4.4)。
- `Win32` / `ARM64` / `Release` / `.slnx` での、フラグ経由の実行は、未確認 (`docs/TEST-PLAN.md`)。
