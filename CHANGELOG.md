# 変更履歴

形式: [バージョン] 日付 / 変更の要点。契約 (ファイル名・結果の値・終了コード) を変えたときは、そのことを明記する。

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
