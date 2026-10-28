# 変更履歴

形式: [バージョン] 日付 / 変更の要点。契約 (ファイル名・結果の値・終了コード) を変えたときは、そのことを明記する。

## [2.21.0] 2026-10-28 (Skill 側。GoogleTest の既定を vcpkg に変更。PoC と、生成物の実機での確認済み)

- **`--gtest auto` の既定を、vcpkg にした** (`new_solution.py` / `add_layer.py`)。判定: 既存の `gtest` プロジェクト → source / `packages\` に GoogleTest の NuGet パッケージがある (すでに旧方式) → nuget / **それ以外 → vcpkg**。以前の「兄弟フォルダの `packages\` をコピーできれば nuget」は、`--gtest nuget` を明示したときだけ。`--gtest vcpkg` を追加。
- **vcpkg 方式の生成物:** ソリューション直下の `vcpkg.json` に `gtest` (ネットワークは使わない。`builtin-baseline` は、ウォッチャー経由の `package_once.sh "vcpkg baseline" "vcpkg install"` で入る)、テスト exe の `.vcxproj` に `<PropertyGroup Label="Vcpkg">` (`x64-windows-static-md`)、テスト exe ごとに `main.cpp` (`gtest_main` は自動でリンクされないため)、`.gitignore` に `vcpkg_installed/`、`CLAUDE.md` に vcpkg の節。DLL の `.vcxproj` には、Vcpkg の設定を入れない。出力: `GTEST_MODE: vcpkg` / `GTEST_VCPKG: present | no-baseline | to-add`。
- **メインの exe の保護 (`protect_main_exes`):** vcpkg 方式のテスト exe を、アプリの exe と取り違えないよう、`vcxproj` のコメントの `GoogleTest` で、除く。
- **互換:** `cpp_pkg.py setup` は、vcpkg 方式のテスト exe を「設定済み」として飛ばし、ほかのプロジェクトに足す。nuget 方式・source 方式は、従来どおり使える。
- **違い:** 出力の「Running main() from ...」の行が出ない。`gtestd.lib` ではなく、構成ごとの `gtest.lib`。GoogleTest は C++17 以上が必要 (生成するプロジェクトは C++20)。結果の要約 (`PASSED` / `FAILED`) の形は、変わらない。
- **高速化:** vcpkg の既定のバイナリキャッシュのみ (PoC: 初回 35 秒、キャッシュありの再実行 12 秒)。共有フォルダ (`VCPKG_BINARY_SOURCES`) は、大きなライブラリ向けの任意の設定。
- **Skill:** `add-package` の「GoogleTest は対象外」を改め、`TIMEOUT` は「報告して止まる」(v2.20.0 の止めどきと整合。以前は「1 回だけ再試行」)。`new-solution` / `cpp-test-first` / `DLL-LAYOUT.md` を更新。

## [2.20.0] 2026-10-28 (ホスト側と Skill 側。自動修正ループの堅牢化: 批判的レビューの指摘への対応。ホスト側は実機で未確認)

- **実行 ID の照合:** スクリプト (`build_once.sh` / `build_test_once.sh` / `uitest_once.sh`) が、フラグの 1 行目に `run=<ID>` を書き、ウォッチャーが、結果のマーカーを書く直前に、同じ ID を `.claude-logs/run_id.txt` に書く。スクリプトは、一致する結果だけを受け取る (前の実行が、あとから書いた、古い結果を、今回の結果と取り違えない)。古いウォッチャーは、書かない → 従来どおり。**`TIMEOUT` (rc 5) は、再試行せず、停止して報告する** (以前は「1 回だけ再試行可」)。`TIMEOUT` のとき、回収されていないフラグは、取り下げる。
- **処理中の印:** ウォッチャーが、処理 (ビルド・テスト・gtest 取得・パッケージ操作) の間だけ、`.claude-logs/watcher_busy.txt` を置く (起動時に、残りを消す)。処理中は、`WATCHER_NOT_RUNNING` (rc 3) とは言わず、`TIMEOUT` まで待つ。`WATCHER_NOT_RUNNING` のメッセージに、対象のフォルダの確認を足した。
- **gtest の `[  PASSED  ] 0 tests.` を `ENV_ERROR` に** (テストが 1 件も実行されていない)。
- **Skill:** `build-test-loop` に「止めどき」の節 (回数の数え方、再試行しないもの、`TEST_TIMEOUT` の 2 回、**実装側の細工の禁止**、テストファイルの編集は機械的な追従だけ、実行 ID の説明)。`auto-build` / `build-test-loop` の表に、`TIMEOUT` (停止) と `BAD_ARGS` を整理。`wpf-test-first` / `cpp-test-first` に、ベースライン (Red の前)、**Green の完了条件 (新しいテストが、実際に実行されたこと)**、バグ修正ではスタブを置かない。`add-feature` に、止めどきの参照。
- **UI:** `uitest_once.sh` は、テストまで届いた実行 (rc 0 / 1 / 7) だけ、スクリーンショットと trace を表示する。待ち時間の既定 = 600 + UI テストのプロジェクトの数 × (`--ui-timeout`、なければ 600) + `--hold` + 120 (最低 900)。`--filter` の、末尾の `\` と CR を拒否。ウォッチャーは、フラグを UTF-8 で読み、`filter=` を、コメントを除く前に読む (`#` を含められる)。`UiTestBase`: `Find` が 5 秒まで探し直す、`StopApp` が null に強い、`Snap(名前, ウィンドウ)`。`UiDialogs` は `partial`。`ui-test-first`: `Preview_<画面>`、回帰は `TestCategory!=Preview`、ループの既定は `--separate` (メニューを開くテストは、別クラスで `--visible`)、visible の了承、`TEST_TIMEOUT` の扱い (`ui-trace.txt` の最後の行、延長は 1 回、2 回続いたら停止)、MFC の ID の探し方、後始末。
- **パスの大文字小文字を、実際のものに直す** (`build_once.sh` / `build_test_once.sh` / `package_once.sh` / `gtest_once.sh`。`resolve_true_case`)。WSL の `/mnt/c` は、大文字小文字を区別しないが、Claude Code のサンドボックスの書き込み許可は、区別して比較するため、パスの大文字小文字が、実際と違うと、結果ファイルの削除・フラグの書き込みが失敗し、古い結果を読んでいた (実機で確認、修正は、コンソールの Claude が、配置先で行い、それをリポジトリに取り込んだ)。
- **実機で確認 (2026-10-28):** 実行 ID、処理中の印、処理中のビルドが `TIMEOUT` になりフラグが取り下げられること、直後の実行が自分の結果を受け取ること、ウォッチャー停止時に前回の画像を出さないこと、gtest の 0 件が `ENV_ERROR` になること。
- DESIGN 4.40 (指摘と、直した内容、直していないこと)。
- テスト: `tests/loop_hardening_test.sh` (新規、20 件)、`tests/host_tools_static_test.sh` (37 件)、`tests/ui_tests_gen_test.sh` (61 件)、`tests/uitest_once_test.sh`。

## [2.19.0] 2026-10-27 (ホスト側と Skill 側。目視確認 (プレビュー): UI テストは裏で、見たい画面だけ、ユーザーのデスクトップに出す。ホスト側は実機で未確認)

- **`UiTestBase` に `HoldForViewing()` と `Snap(名前)` を追加** (生成される `UiTestBase.cs`)。`HoldForViewing` は、環境変数 `UITEST_HOLD_SEC` の秒数だけ、いまの画面を見せる (指定がなければ、すぐ戻る。ウィンドウを閉じると、早く終わる)。`Snap` は、裏でも、PNG を残す。**`PreviewUiTests.cs` (新規。`[TestCategory("Preview")]`、アサーションなし) を生成する。** `--refresh-support-files` は、なければ足し、あれば上書きしない。
- **`uitest_once.sh` に `--hold 秒` と `--preview [秒]` を追加** (`--preview` = `--visible --hold 60`)。flag の `hold=` として、ウォッチャーへ。**`watch_and_build.ps1`:** `hold=` (flag だけ) を読み、環境変数 `UITEST_HOLD_SEC` でテストへ渡す。制限時間は、`hold + 120` 秒以上に、自動で延ばす。`[UI]` の行に `hold` も表示。
- **`uitest_once.sh --present` (デモとして再生):** `--visible` + `--slowmo 800` (指定がなければ) + `present=1` (flag)。ウォッチャーが、環境変数 `UITEST_PRESENT` でテストへ渡す (ユーザーのデスクトップに、強制)。`UiTestBase.Find` / `OpenModal` が、操作する要素を、赤い枠で囲む (`Highlight`)。`--separate` とは、同時に使えない。**再生するのは、`--filter` で指定したテストだけ** (`--filter` が必須。ないと BAD_ARGS。ウォッチャーも、`filter=` がなければ、`present=1` を無視する)。
- `ui-test-first` Skill に「目視確認」の節 (裏で回す側は `--separate`、見せるときは `--preview`、見せる前に告知、Claude 用の `Snap`)。`build-test-loop/SKILL.md`、生成される `CLAUDE.md` にも追記。DESIGN 4.39。
- **ウォッチャー: `--filter` に一致するテストが 0 件のときの、`ENV_ERROR` の文言を、専用のものに** (`no test matches the filter: ...` と、式の書き方の注意。以前は、「GoogleTest / アダプタの不備」を疑わせる汎用の文言だった)。終了コードと、1 行目 (`ENV_ERROR`) は、変えない。
- **ウォッチャー: UI テストの各段階の時刻を、`.claude-logs\ui-timing.txt` に残す** (トリガーの検知、ビルド完了、WPF の描画設定、`Invoke-Tests`、`dotnet test` の開始・終了、デスクトップ用のランナーの初回のコンパイル)。ビルド完了から UI テスト開始までに、長い空白 (実機で、14.5 分が、1 回だけ) があったときの、原因の切り分け用。実行ごとに、作り直す。
- **修正 (リリース前に、実機で発見):** 空の `trigger_uitest.flag` で、ウォッチャーが落ちた (`Get-Content -Raw` が `$null` を返し、`$null -replace` が配列になって `Trim()` が失敗)。`$null` を `""` にしてから使う。静的テストを追加。
- **既存のプロジェクトは、`--refresh-support-files` で、`UiTestBase.cs` を更新する** (旧い版のままだと、`--present` の赤い枠が出ず、操作の間隔が約 3 倍になる)。
- **実機で確認 (WPF = 2026-10-27、WinForms と MFC = 2026-10-28。赤い枠は、目視):** `--refresh-support-files`、`--filter`、`--ui-timeout`、`--present` (赤い枠、`--filter` 必須)、`--preview` / `--preview 20` (ウィンドウを閉じると、早く終わる)、`--separate`。`--filter` が 0 件のときは、`ENV_ERROR` (終了コード 4)。WinForms も、MFC も、同じ項目を確認した (2026-10-28。MFC の赤い枠も、目視)。3 つのフレームワークで、実機で確認済み。
- テスト: `tests/ui_tests_gen_test.sh` に 5 件 (59)、`tests/uitest_once_test.sh` に 9 件 (25)、`tests/host_tools_static_test.sh` に 3 件 (30)、`tests/ui_test_first_skill_test.sh` に 3 件 (16)。

## [2.18.0] 2026-10-27 (ホスト側と Skill 側。UI テストを、ビルド → テストの流れから切り離し、`/ui-test-first` のループを作る。ホスト側は実機で未確認)

- **方針の変更:** **UI テストは、ビルド → テスト (`build_test_once.sh`) の流れに、含めない。** `PASSED` になっても、自動で、続けて実行しない。ユーザーが求めたときと、`/ui-test-first` のループの中だけ、`uitest_once.sh` で、別に実行する。`add-feature` / `cpp-test-first` / `wpf-test-first` / `build-test-loop` / `new-solution` の Skill、`rules/winforms-csharp.md`、生成される `CLAUDE.md` の記述を、そろえて変更した (以前の「Green のあとに、続けて実行する」「UI テストファーストは、しない」は、取り下げ。DESIGN 4.38)。
- **`/ui-test-first` (新規 Skill):** 画面を、プロンプトで作りながら、UI テストを先に書き、`--filter` で絞って、繰り返し実行する (計画で 1 回承認 → Red → 最小の View → 実装 → Green → 全 UI テストの回帰)。
- **`uitest_once.sh` に `--filter 式` と `--ui-timeout 秒` を追加** (flag の `filter=` / `timeout=` として、ウォッチャーへ。`--ui-timeout` が 780 以上なら、待ち時間は、`秒 + 120`)。**`watch_and_build.ps1`:** flag と `uitest.settings` の、`timeout=` (UI テストの制限時間。優先順: flag > `uitest.settings` > `-UiTestTimeoutSec` / `WATCH_UI_TIMEOUT_SEC`) と、flag の `filter=` (`dotnet test --filter`。UI テストのプロジェクトだけ。引用符・バッククォート・改行は、拒否) を読む。`[UI]` の行に、`timeout` と `filter` を表示。生成される `uitest.settings` に、`timeout=` の説明 (コメント) を足した。
- 生成される `CLAUDE.md` の「進め方」に、`/ui-test-first` を追加。README の Skill の説明を更新。
- テスト: `tests/ui_test_first_skill_test.sh` (新規、13 件)、`tests/uitest_once_test.sh` に 3 件 (16 件)、`tests/host_tools_static_test.sh` に 3 件 (27 件)、`tests/ui_tests_gen_test.sh` の文言を更新。

## [2.17.0] 2026-10-27 (Skill 側。ダイアログの UI テストの、第 2 弾の取り込み。単体テストのみ。生成した C# は、実機でコンパイルしていない)

- **`UiDialogs.cs` に、実機の PoC (WinForms / WPF / MFC) で確かめた方法を取り込んだ:** `SendMessage` を 5 秒のタイムアウトつきに (固まったアプリへの同期 SendMessage で、テストごと殺されるのを防ぐ)。`SelectTab(tab, 名前, 全タブの名前...)` / `SelectTab(tab, 順番)` (**WinForms / MFC は、タブの名前を、並び順で全部渡す**。UIA の TabItem は、信用できない)。`ClickColumnHeader` / `ListItems` / `SetNumeric` / `ToggleTreeNode` / `OpenDropDown` / `FindCalendar` / `PostKey` / `FocusAndKeys` / `Vk`。`PressDialogButton` は、失敗したら `ForceCloseDialog` で閉じる。`GetAppWindow` (入力インジケーターの小窓を除く。`UiTestBase` が使う)。**契約の変更:** `SelectTab(tab, name)` は、WinForms / MFC では、全タブの名前を、渡さないと、失敗する (WPF は、従来どおり)。
- **`winforms-check` WFD008 (新規):** `ListView` の `CheckBoxes = true` と `View.Tile`。 **`wpf-check` UI004 (新規):** UI テストがあるとき、`CheckBox` を `Click` だけで受けている。
- 規約: `rules/winforms-csharp.md` 6.3.1、`rules/wpf-csharp.md`。`build-test-loop/SKILL.md` に、「コントロール別の、実機の結果の表」と、第 2 弾の道具。生成される `CLAUDE.md` の UI テストの節にも追記。`docs/NEXT-STEPS.md` の「ダイアログのテスト」を、完了に。DESIGN 4.37。
- **実機で確認 (2026-10-27):** 生成した C# が、WinForms / WPF / MFC で、コンパイルでき (警告 0)、ひな形の UI テストが通った。`uitest.settings` どおりに、デスクトップが選ばれた (WPF = `Default`、他 = `ClaudeUiTest...`)。
- テスト: `tests/ui_tests_gen_test.sh` に 6 件、`tests/winforms_check_test.sh` に WFD008 の 2 件、`tests/wpf_check_test.sh` に UI004 の 2 件。

## [2.16.0] 2026-10-27 (ホスト側と Skill 側。UI テストのデスクトップの既定を、UI テストのプロジェクトの `uitest.settings` に持たせ、1 回ごとに、Claude から指定できる。ホスト側は実機で未確認)

- **`<アプリ>.UITests/uitest.settings` (新規):** UI テストを実行するデスクトップの既定 (`desktop=visible` = ユーザーのデスクトップ / `separate` (別名 `invisible`) = 別のデスクトップ、`slowmo=N`)。**`add_ui_tests.py` (と `new_solution.py --ui-tests flaui`) が、プロジェクトを作るときに書く: WPF は `visible`** (WPF のメニューのポップアップが、別のデスクトップでは、開かないため)、**それ以外は `separate`**。`--refresh-support-files` は、なければ足し、あれば上書きしない。WPF とそれ以外の切り替えを、ウォッチャーの判定でなく、このファイルに統一した。
- **`uitest_once.sh` に、`--visible` / `--separate` (別名 `--invisible`。WPF でも、別のデスクトップにする) / `--slowmo N` を追加** (ウォッチャーを `run_watcher_visible.cmd` に切り替えなくてよい)。指定は、`trigger_uitest.flag` の中身 (`desktop=visible|separate`、`slowmo=N`) として渡る (`build_test_once.sh` の環境変数 `BUILD_TEST_FLAG_CONTENT`)。`--visible` と `--separate` の同時指定、数字でない `--slowmo` は、`BAD_ARGS` (終了コード 2)。指定がなければ、フラグは空 (従来どおり)。
- **`watch_and_build.ps1`: `-UiTestDesktop` の既定値を `auto` に (`WATCH_UI_DESKTOP` の既定も同じ。`visible` = `default`、`invisible` = `separate` の別名を追加)。** 優先順: flag の指定 > `-UiTestDesktop` / `WATCH_UI_DESKTOP` (`default` / `separate`) > UI テストのプロジェクトの `uitest.settings` (複数あれば、1 つでも visible なら visible) > separate。`slowmo=` も同じ順。フラグは、消す前に読む。実行ごとに、`[UI] desktop: ... (理由)` を表示。**ウォッチャーに、フレームワークの判定はない。**
- **契約の変更:** ウォッチャーは、`uitest.settings` がないプロジェクトを、別のデスクトップで実行する (従来どおり)。**既存の WPF の UI テストのプロジェクトは、`uitest.settings` を足す (`add_ui_tests.py <フォルダ> --refresh-support-files`) まで、別のデスクトップのまま。**
- `wpf_menu_note.sh` の文言を変更 (`uitest.settings` に `desktop=visible` がなければ「書く」、あれば「設定に従い、ユーザーのデスクトップで実行される。触らない」。別のデスクトップの記録があるときだけ、2 行目)。`UiDialogs.cs` の失敗メッセージと、生成される `CLAUDE.md` の記述も、同様。`build-test-loop/SKILL.md` (実行前に、ユーザーに、触らないよう伝える)、`auto-build/SKILL.md`、`host-tools/README.md`、DESIGN 4.36 を更新。
- テスト: `tests/uitest_once_test.sh` (13 件)、`tests/wpf_menu_note_test.sh` (13 件)、`tests/ui_tests_gen_test.sh` に `uitest.settings` の 6 件 (49 件)、`tests/host_tools_static_test.sh` に文字列の確認を追加 (24 件)。

## [2.15.0] 2026-10-26 (ホスト側の変更。Linux では検証できない。単体の静的テストのみ。実機は未確認)

- **`watch_and_build.ps1`: `-UiTestTimeoutSec` の既定値を、環境変数 `WATCH_UI_TIMEOUT_SEC` から読む** (なければ 600。明示した引数が優先)。UI テストが多く、600 秒で `TEST_TIMEOUT` (強制終了) になるとき、`set WATCH_UI_TIMEOUT_SEC=1800` で長くできる。起動画面の `UI test` の行に、`timeout N s` と出る (既存の表示)。
- `host-tools/README.md`、`build-test-loop/SKILL.md` (「UI テストが多いとき」の節。分割・ログの 1 行ごとの書き出しも)、DESIGN 4.35 を更新。

## [2.14.0] 2026-10-26 (Skill 側。UI テストの道具 `UiDialogs` の取り込み。単体テストのみ。生成された C# は、実機でコンパイルしていない)

- **`add_ui_tests.py` が、`<アプリ>.UITests/UiDialogs.cs` を、作る** (WinForms / WPF / MFC で、実機で確かめた、ダイアログ・メニュー・コンボ・リスト・スライダー・スクロールバー・タブ・MessageBox・ファイルダイアログの操作を、`FrameworkId` とウィンドウハンドルの有無で、自動で切り替える)。`UiTestBase` に、`OpenModal` / `WaitModalClosed` / `WaitWindow` / `WaitWindowClosed` を足した。`--refresh-support-files` が、`UiDialogs.cs` も、作る (既存のプロジェクトへ、足せる)。WPF のメニューを、別のデスクトップで開こうとすると、`run_watcher_visible.cmd` を案内する失敗にする。
- 生成される `CLAUDE.md` の「UI テスト (FlaUI)」の節に、`UiDialogs` の使い方、「連動の規則は、純粋な関数の単体テスト、UI テストは、ダイアログごとに、煙テスト 1 件」、メニューの注意を追記。`build-test-loop/SKILL.md` に、「ダイアログ・メニュー・コンボなどの UI テスト」の節を追加。`rules/winforms-csharp.md` 6.3 に、「メニューの `Click` で、ダイアログを直接開かない (`BeginInvoke`)」「`AccessibleName`」を追記。DESIGN 4.34 (フレームワークごとの方法の表)。
- テスト: `tests/ui_tests_gen_test.sh` に 11 件 (43 件)。
- **実機で確認 (`UiHelpWf` / `UiHelpWpf` / `UiHelpMfc`、2026-10-26):** `UiDialogs.cs` を含む UITests のコンパイルは、3 つとも成功。WPF は、ひな形の UI テスト 3 件が通り、MFC は 1 件が通った。
- **修正 (実機で見つかった、既存の不具合): WinForms のメインの `MainForm.cs` が、`error WFO1000` でビルドできなかった** (既定の TFM を `net10.0` にしたため。.NET 9 以降の WinForms 解析が、デザイナーが保存しない公開プロパティ (`IMainView` の `PersonName` / `Greeting` / `CanClear`) を、エラーにする)。生成する `MainForm.cs` の 3 つのプロパティに、`[Browsable(false)]` と `[DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]` を付けた (`using System.ComponentModel;` を足した)。`tests/new_solution_winforms_test.sh` に 1 件 (40 → 41 件)。`rules/winforms-csharp.md` にも、追記。

## [2.13.0] 2026-10-26 (Skill 側。WPF のメニューがあるときの、ウォッチャーの使い方の通知。単体テストのみ)

- **`build-test-loop/scripts/wpf_menu_note.sh` (新規):** `UseWPF` のプロジェクトの XAML に、`Menu` / `MenuItem` / `ContextMenu` があるときだけ、「メニューの開閉を含む UI テストは、ウォッチャーを `run_watcher_visible.cmd` で起動して実行する (別のデスクトップでは、WPF のメニューのポップアップが開かない)」を、`NOTE:` の 2 行で知らせる。`build_once.sh` (auto-build) と `build_test_once.sh` (`uitest_once.sh` を含む) が、終了時に呼ぶ。**1 行目と終了コードは、変えない。** `bin` / `obj` の XAML と、WPF でないプロジェクトは、対象外。直近の UI テストが `desktop: Default` なら、出さない。
- `build-test-loop/SKILL.md` と `auto-build/SKILL.md` に、`NOTE:` が出たときの扱い (ユーザーに伝える) を追記。DESIGN 4.33。
- テスト: `tests/wpf_menu_note_test.sh` (新規、11 件)。

## [2.12.0] 2026-10-25 (Skill 側。既定の TFM を、`net8.0` から `net10.0` に。単体テストのみ。実機は未確認)

- **新規作成の既定の TFM が `net10.0` になった** (アプリは `net10.0-windows`、ライブラリとテストは `net10.0`)。方針: 明示しない限り、最新。`--tfm` / 構成案の `TFM:` で、変えられる。**ホストに SDK 10 が必要。** 既存のソリューションは、`.csproj` から TFM を読むので、影響しない (`add_project.py` / `add_ui_tests.py`)。
- **最新の版が STS (例: .NET 11) のときは、質問して決める:** `new-solution/SKILL.md` の手順に追加 (既定は、最新の LTS。スクリプトの挙動は、変えない)。
- `SKILL.md` / `PROJECT-LAYOUT.md` / `rules/*.md` の既定の記述と、生成物を検証する `tests/*.sh` の期待値を更新。DESIGN 4.32。

## [2.11.0] 2026-10-25 (Skill 側。`/brainstorm` → `/update-from-ideas` の成果を、`new_solution.py --spec` が、積極的に取り込む。単体テストのみ。実機は未確認)

- **構成案のキーを拡張:** `UIテスト` (`none` | `flaui`)、`TFM` (.NET のみ。C++ では、注意を出して、読み飛ばす) を、`--spec` が読む。`層` は、`logic:OrderLogic,data` のように、名前つきでも書ける (従来から動いたが、書式を、`update-from-ideas` に明記した)。
- **仕様書の取り込み (新規 `scripts/spec_import.py`):** 新規作成のとき、`--spec` が、(1) 仕様書と `元:` のメモを `docs/specs/`・`docs/ideas/` に置く (すでにあれば何もしない)、(2) 「具体例」「境界値と異常系」の表から、テストケースの種 `docs/specs/<名前>.cases.md` を作る (E1.. / B1..。既存なら上書きしない)、(3) `CLAUDE.md` に「## 仕様書」の節を足す。`--dry-run` は、予定だけを示す。
- `update-from-ideas` の構成案の説明に、`winforms` / `csharp-dll` (層は logic / data のみ)、UIテスト、TFM を追加。`add-feature` は、ケースの種 (`.cases.md`) を読み、WinForms / C# DLL も対象と明記。
- テスト: `tests/new_solution_spec_import_test.sh` (新規)。

## [2.10.1] 2026-10-25 (Skill 側。`build_test_once.sh` の成功時の要約。単体テストのみ。再配置のあとの実機確認は未実施)

- **`build_test_once.sh` が、`PASSED` のとき、2 行目に、要約の 1 行を出す:** `build: SUCCESS / tests: 6 passed (DataLayer.Tests 1, LogicLayer.Tests 5)` (スキップがあれば `6 passed, 1 skipped`。ソースが 6 つを超えれば `... +N more`)。**1 行目の `PASSED` と、終了コードは、変えない** (Skill が読むのは 1 行目)。以前は、`PASSED` の 1 行だけで、テストの件数を知るために、ログファイルを別に読む必要があった。警告の行は、その次。`uitest_once.sh` も、同じ (`build_test_once.sh` を呼ぶため)。
- `summarize_test_log.py` に、`--passed-line --results-dir <dir>` を追加 (構造化された結果 (trx / GoogleTest の XML) から、1 行を出す。結果が 1 件もなければ、終了コード 3 で何も出さない。`<test_error.log>` は要らない)。`build_test_once.sh` の `show_passed_line` が呼ぶ。
- テスト: `tests/summarize_test_log_test.sh` (9 件追加。43 件)、`tests/fake_watcher_test.sh` (構造化された結果つきの PASSED のケースを追加)。
- `build-test-loop/SKILL.md` の `PASSED` の説明を更新。
- **実機で確認 (H9、2026-10-25、`WfFull`):** `PASSED` の次の行に、`build: SUCCESS / tests: 6 passed (DataLayer.Tests 1, LogicLayer.Tests 5)` が出た。`uitest_once.sh` は、未確認。

## [2.10.0] 2026-10-25 (ホスト側の変更。Linux では検証できない。単体の静的テストのみ。実機は未確認)

- **ウォッチャーが、ソリューション (`.sln` / `.slnx`) がなくても起動でき、トリガーのたびに、フォルダから探し直す:** これまでは、起動時に、ソリューションを探して、なければ終了していた。そのため、`new_solution.py` で作る**前**には、ウォッチャーを起動できず、生成のあとに、起動し直す手間があった (実機の確認で、何度も、ここで止まった: `WATCHER_NOT_RUNNING`)。
  - `watch_and_build.ps1`: `-SolutionPath` を、省略可能にした (明示したときは、従来どおり。存在しなければ、終了コード 2)。**`Update-SolutionState`** (新規) が、ソリューションのパス・フォルダ・プロジェクトの一覧・C++ / .NET の判定・Platform (`auto` の解決)・ビルドの機能 (`cpp` / `restore`)・種類の表示を、まとめて決め直す。起動時と、**ビルド / テスト / UI テスト / GoogleTest 取得 / パッケージの、各トリガーが来るたび**に、呼ぶ (起動後に、ソリューションができた・プロジェクトが増えた場合も、再起動が要らない。**以前は、プロジェクトの一覧だけを読み直していたので、C++ だけで起動したあとに、.NET の UI テストを足すと、`restore` が付かない可能性があった。これも、直る**)。`Find-SolutionFile` は、`.slnx` を優先し、`.sln` は拡張子を厳密に確認する (8.3 の短い名前で、`*.sln` が `.slnx` に一致する問題)。
  - **トリガーが来たときに、ソリューションがなければ、ビルドせずに、環境エラー (終了コード 2) として返す** (`build_result.txt` = `FAILED`、`build_error.log` の先頭が `[ENVIRONMENT ERROR ...]` と `ERROR: no .sln / .slnx found in ...`。テストのトリガーなら、`test_result.txt` = `BUILD_FAILED`)。契約 (結果の値・終了コード) は変えない。Skill 側のスクリプトも、変えない。 (`build_once.sh` は、`[ENVIRONMENT ERROR` で始まる `build_error.log` を、`ENV_ERROR` (終了コード 4) として返す。)
  - **実機で確認 (H1〜H4、2026-10-25、`LazySln`):** 空のフォルダで起動 → 生成の前のトリガーは、`FAILED` (環境エラー) で、ウォッチャーは終了しない → 生成 → 再起動なしで、ビルド `SUCCESS`・テスト `PASSED`・UI テスト `PASSED` (3 件)。**H6 (従来の使い方: 既存のソリューションのフォルダで起動) も確認:** ヘッダーにソリューションのパスと種類が出て、ビルド `SUCCEEDED`、テスト `PASSED` (6 件)。**H5 (引数なしの起動は、従来どおり、エラーで終了) も確認。** H7 / H8 は、未確認 (任意)。
  - `run_watcher.cmd`: ソリューションが見つからなくても、起動する (`-SolutionPath` を、見つかったときだけ渡す)。**ただし、フォルダの引数なしで起動して (`run_watcher.cmd` のあるフォルダが対象になる)、ソリューションがないときは、指定ミスの可能性が高いので、従来どおり、エラーで終了する。**
  - **自動のつながり:** ビルド、テスト、UI テストの各トリガーが、それぞれ、今までどおり動く (ビルドのあとにテスト、など)。トリガーを、自動で連鎖させる仕組みは、入れていない。
- 検証: `tests/host_tools_static_test.sh` (16 件): 構造の静的な確認 (BOM・CRLF・CP932、`-SolutionPath` が省略可能、`Update-SolutionState` が 4 か所で呼ばれる、ソリューションがないときのビルドの分岐、括弧の対応、`.cmd` の `SLN_ARG`)。**PowerShell が使えないので、実行は未確認** (TEST-PLAN H 系)。

## [2.9.3] 2026-10-25 (`winforms-check` の起動の誘導。WC4 の実機の結果を受けて)

- **WC4 の実機の結果 (2026-10-25):** 「ウィンドウは開くのですが、中が空です。原因を調べて、直してください」に対して、Claude は、**`winforms-check` の Skill を起動せず**、`MainForm.cs` などを直接読んで、`InitializeComponent()` の呼び忘れを見つけ、足して直した (コントロールを消さない、正しい直し方)。**直したあとに**、`winforms_check.py` を実行して 0 件を確認し、ビルド・テスト・UI テストも通した。規約 (`winforms-csharp.md`) は、自動で読み込まれていた。
- **直したこと:** `SKILL.md` の `description` に、依頼の言い方に近い言葉 (「ウィンドウは開くが中が空」「何も表示されない」「コントロールが出ない」) を足し、本文の冒頭に、「コードを読む前に、まず、これを実行する」と書いた。**効果: 「ウィンドウは開くが中が空」では、効いた** (新しいセッションで、診断の前に Skill が呼ばれ、`WFD001` を検出した)。**「UI テストが ClearButton を見つけられません」では、効かなかった** (`Explore` のサブエージェントで原因を調べ、Skill は修正の後の検証だけ。診断と修正は正しかった)。そのため、`description` と冒頭に、「UI テスト (FlaUI) が要素を見つけられない」「AutomationId が見つからない」「サブエージェントなどを始める前に」を足した。**再確認 (WC4c、2026-10-25 実機): 新しいセッションで、依頼の 3 秒後に、`Skill` ツールで `winforms-check` が呼ばれ、`WFD003` を検出して、`Name` をそろえた (サブエージェントより先)。効いた。**
- 補足: `.py` のスクリプトは、すべて実行権限なし (644) で、`SKILL.md` が `python3` で実行するよう書いている。直接実行すると `Permission denied` (終了コード 126) になるが、仕様どおり。

## [2.9.2] 2026-10-25 (VS のデザイナーが、生成した Form を認識しない問題を修正。実機で原因を切り分け)

- **生成した `MainForm.cs` が、VS で Form と認識されず、デザイナーが開けなかった (WF2 の実機で発見):** Solution Explorer で通常の `.cs` のアイコンになり、「デザイナーの表示」が出なかった。VS で新しい Form (`Form1`) を追加すると、`MainForm` も認識され、デザイナーが開けた。**そのときの差 (ディスク): `WfFull.csproj.user` が新規に作られ、`Forms\MainForm.cs` に `<SubType>Form</SubType>` が書かれた。`MainForm.resx` (空のテンプレート) も新規に作られた。`MainForm.cs` / `MainForm.Designer.cs` / `.csproj` は、変わっていない** (**ファイルスコープの名前空間は、原因ではなかった**)。
- **切り分け (未使用の 2 つのソリューションで):** (A) `MainForm.cs` に `using System.Windows.Forms;` を足すだけ、(B) `.csproj` に `<Compile Update="Forms\MainForm.cs"><SubType>Form</SubType></Compile>` を足すだけ、のどちらでも、VS が Form と認識し、デザイナーが開けた。**どちらが本当の原因かは、分かっていない** (何も足さない対照は、`WfFull` の最初の状態)。
- **修正: 両方を、生成する。** (1) `csproj_winforms` が、`Forms\MainForm.cs` に `SubType` = `Form` を、書く。(2) `main_form_cs` が、`using System.Windows.Forms;` を、明示する (`ImplicitUsings` に頼らない。`dotnet format` の並びに合わせて、System が先)。既存のソリューションは、VS でデザイナーを一度開けば、VS が `.csproj.user` に書く。
- **実機での確認 (WF2b、2026-10-25):** 新しく生成した `WfDsg` を、VS で開き、ビルドも Form の追加もせずに、「デザイナーの表示」で、デザイナーが開けた。**`.csproj.user` は作られなかった** (VS が `SubType` を、追加で書く必要がなかった)。ソリューションを開いた直後は、Form のアイコンになっておらず、デザイナーを開いたあとに、Form のアイコンになった (表示の遅れ)。
- `rules/winforms-csharp.md` 5.1 に、Form を VS に認識させる決まりを追記。
- テスト: `tests/new_solution_winforms_test.sh` (40 件)。

## [2.9.1] 2026-10-25 (UI テストのスクリーンショットの切れを修正。実機で、原因を確認。修正の確認は未実施)

- **UI テストのひな形 (`Screenshots.cs`): スクリーンショットの右下が切れる不具合を修正 (WF7 の実機で発見):** 失敗したテストの PNG が **380 x 230** で、タイトルバーの最大化ボタンの途中、テキストボックスの右端、**「クリア」ボタン (下端)** が写っていなかった。**原因: テストのプロセス (testhost) が DPI 非対応**で、UI Automation の矩形も `GetWindowRect` も、**縮小された値**で返る。`PrintWindow` は、ウィンドウの実際の大きさで描くので、小さすぎる `Bitmap` に、左上だけが入る。v2.8.0 の「UIA の矩形と `GetWindowRect` の大きいほう」は、**同じ縮小値なので、効かなかった** (v2.8.0 の説明にある「原因未確定」は、これ)。**修正: (1) アセンブリの読み込み時 (`[ModuleInitializer]`) に、`SetProcessDpiAwarenessContext(Per-Monitor V2)` で、テストのプロセスを DPI 対応にする (矩形が、実際の大きさで返る)。(2) できなかったとき (すでに決まっていた場合) は、`IsProcessDPIAware()` が false で、`GetDpiForWindow` が 96 より大きければ、矩形を `dpi / 96` 倍にする。** WPF / MFC のひな形も、同じ `Screenshots.cs` なので、同じ修正が入る。既存の `*.UITests` は、`add_ui_tests.py <フォルダ> --refresh-support-files` で更新する。
- **WPF でも、実機で確認 (WF8 後半、2026-10-25、`WpfShot`):** 失敗時のスクリーンショットが 500 x 275 (`Width` 400 / `Height` 220 × 125%) で、全体 (タイトルバー、テキストボックス、挨拶、「クリア」ボタン) が写り、白一色にならない。**MFC も、実機で確認** (`MFCSHot`: 498 x 272 で、ダイアログ全体が、画像いっぱいに写る。切れない。内容が小さく写る問題も、なし)。
- 気づいた点 (修正しない): `PrintWindow` は、ウィンドウの「見えない枠」(Windows 10 / 11 の、リサイズ用の透明な枠。左端に黒い帯として写る) も含める。見た目だけの問題で、内容は読める。
- テスト: `tests/new_solution_winforms_test.sh` (39 件)。

## [2.9.0] 2026-10-25 (WinForms の検査と規約。単体テストのみ。実プロジェクトでの誤検出の確認は未実施)

- **`winforms-check` を追加 (DESIGN 4.30 段階 4。独立した Skill。読み取りだけ。ウォッチャーも Windows も .NET も不要):** `winforms_check.py`。検査: `WFD001` (Form のコンストラクターが `InitializeComponent()` を呼ばない = 画面が空)、`WFD002` (Designer の `Name` の重複)、`WFD003` (`Name` が変数名と違う)、`WFD004` (生成したコントロールが `Controls.Add` に入っていない)、`WFD005` (UI テストがあるのに `Name` がない)、`WFD006` (`InitializeComponent()` が Designer.cs 以外にある)、`WFD007` (`InitializeComponent()` の中に制御構文)、`WFT001` (`DoEvents`)、`WFT002` (Form の `Thread.Sleep`)、`WFT003` (`CheckForIllegalCrossThreadCalls = false`)、`WFL001` (ロジック・データ層への WinForms の混入)、`WFL002` (Presenter が WinForms の型を使う)、`WFL003` (参照の向き)、`WFL004` (Form で Service を `new`)、`ASY001` / `ASY002` / `EXC001` / `EXC002` / `NAM001` (`wpf-check` と同じ)。出力と終了コード (0 / 1 / 2 / 3) は、`wpf-check` と同じ形。**`new-solution` が作る WinForms (層あり・ロジック層なし・アプリのみ・UI テストつき) は、指摘 0 件。**
- **`rules/winforms-csharp.md` を追加 (ユーザー共通。`paths` は `**/*.cs` `**/*.csproj`):** MVP (Form は `IView` の実装、Presenter に振る舞い)、composition root (`Program.cs`)、ソリューション構成と層の依存、コントロールの命名 (`Name` = AutomationId)、`Designer.cs` の扱い、レイアウトと DPI、ダイアログ (`IDialogService`)、スレッド、例外 (`Program.cs` の受け口)、テスト (Presenter は `IView` の Fake、UI テストは FlaUI)、禁止事項、レビュー項目、規則と検査の対応表 (付録)。C# の共通部分は、`wpf-csharp.md` の C# の章を使う。WPF / XAML / MVVM の章は、WinForms では適用しない。
- 生成する `CLAUDE.md` (WinForms) が、`winforms-check` と `winforms-csharp.md` を指す。`add-feature` / `wpf-test-first` / `new-solution` の `SKILL.md`、README、DESIGN を更新。
- テスト: `tests/winforms_check_test.sh` (27 件: 生成物は指摘 0 件、各コードを、わざと壊した複製で確認、`async void` のハンドラーは対象外、テストプロジェクトは共通の規則の対象外、`--json`、読み取り専用)。

## [2.8.0] 2026-10-25 (WinForms の UI テスト。PoC は実機で確認済み。生成したプロジェクトのビルドは未確認)

- **WinForms の FlaUI の PoC (DESIGN 4.30 段階 3。2026-10-25 実機):** 別のデスクトップで、(1) **`AutomationId` = コントロールの `Name`** (`NameTextBox` / `GreetingLabel` / `ClearButton` / `MainTable`)。Label の `Name` は表示の文字。(2) **UIA3:** `ValuePattern` で入れた文字が `TextChanged` を起こし、Presenter が挨拶を変える。`Invoke` でクリアが動く。ボタンの有効・無効 (`CanClear`) も見える。(3) **UIA2 も、7 手順すべて OK** (WPF は、別のデスクトップで `Invoke` が失敗した。WinForms は、UIA2 が本来の UIA なので動く)。UIA3 を標準にする方針は、変えない。(4) **`PrintWindow` が、内容を写した** (WPF のような白い画像にならない。ハードウェアアクセラレーションの対策は、要らない)。(5) 起動 約 1.1 秒。
- **`--ui-tests flaui` が WinForms で使える:** `add_ui_tests.py` が、`UseWindowsForms` の exe を、アプリとして判定する (`classify` の `winforms`)。標準の `MainForm` (`Designer.cs` に `NameTextBox` / `GreetingLabel` / `ClearButton` の `Name`) なら、入力 → 挨拶 → クリアのテスト (`TESTS_WINFORMS_CS`)。標準でなければ、ウィンドウが開くだけのテストと、`Name` を付けるよう促す NOTE。層の有無に関係なく使える。作成と同時 (`new-solution --type winforms ... --ui-tests flaui`) も、後付けもできる。`DefaultStartup` がなければ、WPF / WinForms の exe を優先して選ぶ。
- **スクリーンショットの大きさ:** UIA の矩形と `GetWindowRect` の大きいほうに合わせる (PoC で、UIA3 の 1 枚だけ、右下のボタンが切れた。原因は未確定 (DPI の違いを疑う)。**ひな形の変更は、WPF / MFC にも及ぶ**。実機で、切れないことと、他の画像が崩れないことを確認する)。
- テスト: `tests/new_solution_winforms_test.sh` (38 件)。TEST-PLAN: WF0 (PoC の記録)、WF7 / WF8 (生成した UI テスト)。

## [2.7.0] 2026-10-24 (単体テストのみ。コンパイルを含めて、実機は未確認)

- **`new-solution --type winforms` を追加 (DESIGN 4.30、段階 2):** WinForms (.NET、MVP) のソリューションを作る。メインは WinForms アプリ (`UseWindowsForms`、`Program.cs` が composition root、`Forms/MainForm.cs` + `MainForm.Designer.cs`)。層は `data` / `logic` だけ。`Form` は `IMainView` を実装し、画面の振る舞いは `MainPresenter` が持つ (ロジック層があればそこ、なければアプリの `Presenters/`)。ロジック層に、`MainPresenterTests` (Fake の View、4 件) が付く。`--ui-tests flaui` は、PoC のあとに対応するため、今はエラー。
- `add_project.py`: `presenter` の種類 (`lib_files` / `test_files` / `--kind presenter`、`read_lib_info` の `is_presenter`) と、`winforms_app_files` を追加。後付けの `--tests mstest` が、Presenter のあるロジック層に、`MainPresenterTests` を足す。
- **層を持たない構成 (`--layers none` / `data`) でも、Presenter をテストできる:** ロジック層がないとき、`--tests mstest` は、アプリの `Presenters/` を対象にした `<アプリ名>.Tests` (TFM はアプリと同じ `-windows`、名前空間 `<ルート>.Presenters.Tests`) を作る (`test_files` の `app-presenter`)。後付けも同じ (`libraries_without_tests` が、`Presenters/MainPresenter.cs` のある exe を対象にする。WPF のアプリは、対象外のまま)。`csharp-dll` は、層なしでも、メイン自身がテストの対象 (v2.6.0)。
- テスト: `tests/new_solution_winforms_test.sh` (29 件)。TEST-PLAN に 2-5 (CD1〜WF5) を追加 (実機は未確認)。

## [2.6.0] 2026-10-24 (単体テストのみ。実機は未確認)

- **`new-solution --type csharp-dll` を追加 (DESIGN 4.30、段階 1):** C# のクラスライブラリ (.NET) のソリューションを作る。メインがクラスライブラリで、`<メイン>.Tests` (MSTest) の対象になる。`--layers` は `data` / `logic` (`viewmodel` はエラー)、`--ui-tests` はエラー、`.slnx` に `DefaultStartup` なし。`--spec` の「メインの種類」にも使える。後付けの `--tests mstest` は、メイン自身も対象にする (既存の仕組みのまま)。`claude_md_csharp_dll` で、専用の `CLAUDE.md` を作る。
- テスト: `tests/new_solution_csharp_dll_test.sh` (15 件)。

## [2.5.7] 2026-10-24 (U16 の C++ 側で発見。実機で確認済み)

- **ウォッチャー: 古い DLL の検出が、Debug と Release を比べて、誤検出していた (U16 の C++ 側の実機で発見):** `MixTest` を、先に `Release` でビルド (T9a)、あとで `Debug` で起動すると、増分ビルドで書き換わらなかった `bin\Debug` の `Calc.Tests.dll` (10-21) が、`bin\Release` の同名の DLL (10-24) より古いと判定され、`ENV_ERROR` になった。**比べる対象を、構成のフォルダ名と、TFM のフォルダ名が同じもの (プラットフォームのフォルダだけが違うもの: `bin\Debug\net8.0` と `bin\x64\Debug\net8.0`) に限る。** U15 / U15b の、偽の成功の検出は、そのまま働く。

## [2.5.6] 2026-10-24 (H4 / T9a / T9b は実機で確認済み)

- **ウォッチャー: 起動後に `build-windows.cmd` が消えたとき、環境エラーにする (H4 の確認の準備で発見):** `cmd /c` が、見つからないバッチに対して返す終了コードは、ビルド失敗 (1) と区別できないことがある (`build_error.log` に `[ENVIRONMENT ERROR ...]` が付かない、または、古いログが読まれる)。`Invoke-BuildScript` が、実行の前にファイルの有無を確かめ、なければ `ERROR: build script not found: ...` と終了コード 2 (環境エラー) を返す。
- **`build-windows.cmd`: `-Platform Win32` で、`.sln` / `.slnx` のソリューション構成の名前に合わせる (T9b の実機で発見):** `DoubleBufferSample.sln` (VS 製) を `-Platform Win32` でビルドすると、`MSB4126: 指定されたソリューション構成 "Debug|Win32" は無効です` で失敗した (終了コード 6 `BUILD_FAILED`)。VS が作るソリューションでは、x86 のプラットフォームの名前が **`x86`** (プロジェクトの側が `Win32` に対応づく)。ソリューション構成の一覧 (`Debug|x86 = Debug|x86`、`.slnx` は `<Platform Name="x86" />`) に、`Win32` がなく `x86` があれば、MSBuild に `x86` を渡す。`.vcxproj` を直接ビルドするときと、`Win32` があるソリューションは、従来どおり `Win32`。
- **ウォッチャー: `Win32` のテスト exe を、`<ソリューション>\<Configuration>\` からも探す (T9b の実機で発見):** `Win32` のビルドが通っても、`build_test_once.sh` が `ENV_ERROR` (`no tests found for Debug|Win32`) になった。VS の既定の出力先は、x64 が `x64\Debug\`、**Win32 だけは `Debug\` (プラットフォームのフォルダが付かない)**。`Find-TestExes` が、`Win32\<Configuration>\` のあとに、`<Configuration>\` も探す (最初に、テスト exe が見つかった側)。

## [2.5.5] 2026-10-24 (U14b / U14c の (b) は実機で確認済み。案内の行を 2 行目に移した変更は、再確認していない)

- **`build-windows.cmd`: C++ ツールのない VS のとき、案内を出す (終了コード 11、契約は変えない):** `no Visual Studio with C++ x86/x64 tools found.` だけでは、対処が分からなかった。**「Visual Studio Installer で『変更』→『C++ によるデスクトップ開発』を追加する。自動では追加できない」**という `ERROR:` 行を足した (ウォッチャーは `ERROR:` 行を `build_error.log` に渡すので、Claude に伝わる)。C++ を要求しない場合 (`MSBuild` のある VS がない) も、VS (または Build Tools) のインストールを案内する。
- **逆の場合 (.NET のビルドツールのない環境、例: C++ のワークロードだけの VS) の案内 (`watch_and_build.ps1`):** `MSB4236` / `NETSDK1045` / `NETSDK1141` で `ENV_ERROR` になるとき、および `dotnet` が見つからないとき (テスト・パッケージ操作) に、**「Visual Studio Installer で『.NET デスクトップ開発』を追加する (または .NET SDK をインストールする)。自動では追加できない」**という `ERROR:` 行を、`build_error.log` / `test_error.log` / `package_error.log` に付ける (`$DotnetInstallHint`)。`NU1301` (ネットワーク) には付けない。
- `auto-build` の `ENV_ERROR` の行と、`host-tools/README.md` に、同じ対処を記載。C++ ツールなしの VS で動くかの確認 (U14) は、環境の前提に含まないため、対象外 (DESIGN 1.)。メッセージだけを、擬似的な `vswhere.exe` で確かめる (U14b)。

## [2.5.4] 2026-10-24 (U15b を含め、実機で確認済み)

- **ウォッチャー: 古い DLL を実行する「偽の成功」の検出 (U15 の実機で発見):** 出力先が `bin\x64\Debug` のプラットフォーム別の構成で、`-DotnetTestArgs` を付けないと、`dotnet test --no-build` は `bin\Debug` を探す。そこに過去のビルドの古い DLL があると、今回のビルドの成果物ではなく、古い DLL のテストが通って `PASSED` になった。**`Get-StaleTestAssemblies`:** 実行されたアセンブリ (trx の `storage`) と同名で、より新しい DLL が、プロジェクトの `bin` 配下の別の場所にあれば、`ENV_ERROR` (成功のとき。失敗のときは `FAILED` のまま、理由を `test_error.log` に追記) にして、`-DotnetTestArgs:-p:Platform=x64` を案内する。更新時刻とビルドの開始時刻は比べない (増分ビルドで DLL が書き換わらないのは、正常なため)。出力先を切り替えて使うと、古い側が新しい側に負けて、誤って `ENV_ERROR` になることがある (古い `bin` を消せば解消)。
- **`test_error.log` の `at at` の重複 (U7 の実機で発見):** trx のスタックトレースが、すでに `at` で始まっていたため、`at at ...` と出た。先頭の `at` / `場所` を取ってから付ける。
- **`-DotnetTestArgs` の書き方 (U15 の実機で発見):** `powershell -File` から `-DotnetTestArgs "-p:Platform=x64"` と書くと、値が `-` で始まるため、PowerShell が `-p` をパラメーター名と解釈して、`ambiguous` で起動に失敗する。**`-DotnetTestArgs:-p:Platform=x64` (コロンで結ぶ)** に、README・ヘルプ・PROJECT-LAYOUT を直した。
- **生成コードの `using` の並び (WS14 の実機で発見):** `dotnet format --verify-no-changes` が、`WpfUi15.UITests/MainWindowUiTests.cs` と `WpfUi15/App.xaml.cs` の 2 件 (`IMPORTS`) を指摘。`add_ui_tests.py` (`TESTS_WPF_CS`) と `add_project.py` (`app_xaml_cs`。Views / ViewModels の名前空間を並べ替える) を直した。新しく生成した `WpfFmt14` で `exit=0`。
- 記録: U7 / U8 / U13 / U15 / WS14、P14 / P15 / U6c / U12 を、実機で確認済み。

## [2.5.3] 2026-10-21 (実機で確認済み: UT14b、P6、P14、P15、U6c、U12)

- **ウォッチャー: WPF の描画設定の復元 (`Restore-WpfRendering`):** 異常終了のあと、次の起動で、「復元した」と表示したのに、レジストリも記録ファイルも、そのままだった (UT14b の実機で発見)。失敗を握りつぶさず (`-ErrorAction Stop`)、実際に戻ったかを確かめてから、記録を消し、メッセージを出す。失敗したときは、例外の種類と理由を表示する。
- **ウォッチャー: ネットワークに届かないときの判定 (P6 の実機で発見):** (1) 日本語 OS の、接続の失敗のメッセージ (`対象のコンピューターによって拒否されたため、接続できませんでした` など) が、環境エラーの判定に含まれず、`ENV_ERROR` でなく `FAILED` になった → 判定に、日本語のメッセージを追加。(2) PowerShell 5.1 の `Invoke-RestMethod` は、プロキシの環境変数を見ず、`nuget search` / `versions` だけが、プロキシを通らなかった → `HTTPS_PROXY` / `HTTP_PROXY` を、`DefaultWebProxy` に適用。
- `build_test_once.sh`: ウォッチャーが動いていないときの案内に、実際のフラグ名と、古いウォッチャーの可能性 (`copy-host-tools.sh` で再配置) を、出す。
- 記録: U9 / U10 (混在の GoogleTest + MSTest)、UT4 / UT6 / UT8 を、実機で確認済み。

## [2.5.2] 2026-10-21

- **`mfc-check` UI004** (warning): UI テストのプロジェクト (`*.UITests`) があるとき、ダイアログの操作できるコントロール (ボタン・エディット・コンボなど) の ID が `IDC_STATIC` (`-1`) のまま、または、同じダイアログで ID が重複している (UI テストの AutomationId = コントロール ID なので、ID で探せない)。静的テキスト・グループボックス・アイコンは、対象外。UI テストのプロジェクトがなければ、出ない。実プロジェクト (`MfcUi18` / `MfcDlgLayers` / `MfcSdiLayers`) で、誤検出なし。`mfc_check_test.sh` に 7 件を追加 (76 件)。
- 生成の出力の順序 (UI テストの足し込みが、本体より先に出る) を直した (標準出力のフラッシュ)。

## [2.5.1] 2026-10-21 (UI テストを、目で確かめるモード。UT20〜UT22 は実機で確認済み)

- **`run_watcher_visible.cmd`** (新規): UI テストを、ユーザーのデスクトップで、操作の間に待ち (`WATCH_UI_SLOWMO_MS`、既定 800 ms) を入れて、実行する。ウォッチャーに `-UiTestSlowMoMs` (環境変数 `WATCH_UI_SLOWMO_MS`)、テストへの環境変数 `UITEST_SLOWMO_MS`。
- **ひな形 (`add_ui_tests.py`):** `UiTestBase` が、操作の記録 (`ui-trace.txt`) を残し、スローモーション (要素を探すたびに待つ。ウィンドウを前面に出す。終了の前に、最後の状態を見せる)。`UiNative.cs` (新規: デスクトップ名、前面表示、トレース)。`Screenshots`: ユーザーのデスクトップで PrintWindow が空白なら、画面のコピーに切り替える。`--refresh-support-files`: 既存の UI テストのプロジェクトの、ツールが持つ 4 つのファイルを、最新にする。
- **`uitest_once.sh`:** 操作の記録から、テストごとの結果の行を出す (UI テストが、実際に動いたことの確認)。
- テスト: `ui_tests_gen_test.sh` (32 件)、`uitest_once_test.sh` (6 件)。

## [2.5.0] 2026-10-20 (UI テストの自動化。段階 1 と、段階 2 の WPF (UT15 / UT16 / UT19) は実機で確認済み。MFC (UT18) と、既存ソリューションへの後付け (UT17) も、2026-10-21 に実機で確認済み)

- **段階 2 — UI テストのひな形と Skill:**
  - **UI テストを Green のあとに実行させる指示を、強めた (UT19 の実機で、実行されなかったため):** `CLAUDE.md` の「UI テスト (FlaUI)」の節に、命令形で書く (`add_ui_tests.py` が書く。既存のソリューションは `--refresh-claude-md` で更新)。`wpf-test-first` / `cpp-test-first` の「Green へ引き渡す」にも追加。(UT19 の直接の原因は、Skill の再配布 (`install.sh --skills-only`) の忘れだった。)
  - **UI テストの流れ (ユーザーの決定 2026-10-21): UI テストファースト (UI テストを先に書く) は、しない。テスト先行 (Red) → ビルド → テスト (Green) の「あとに、追加で」、UI テストを実行する。** そのため、`ui-test-first` Skill は、作らない (作ってあったものを、削除)。UI テストの書き方・実行・失敗時のスクリーンショットの読み方は、`build-test-loop` の「UI テスト」に、まとめた。`add-feature` の検証 (全体) にも、「UI テストのプロジェクトがあれば、PASSED のあとに、`uitest_once.sh`」を追加。
  - `add_ui_tests.py` (既存のソリューションに `<アプリ名>.UITests` (MSTest + FlaUI.UIA3 5.0.0、`net8.0-windows`) を足す) は、`new-solution/scripts/` に置く (`UiTestBase` (起動・終了・失敗時のスクリーンショット)、`AppLocator`、`Screenshots` (PrintWindow)、ひな形のテスト)。
  - **`new-solution --ui-tests flaui`**: 作成と同時に、または、すでにあるソリューションに後付けで、足す。
  - **生成する WPF の View に、`AutomationProperties.AutomationId`** (`NameTextBox` / `GreetingText` / `ClearButton`) を付けた。
  - **`wpf-check` UI002** (warning): ソリューションに UI テストのプロジェクト (`*.UITests`) があるとき、操作できるコントロール (Button / TextBox など。テンプレート・スタイルの中は除く) に、AutomationId (または `x:Name`) がない。
  - **規約** (`rules/wpf-csharp.md`): UI テストの書き方を、テストの節と付録に追加。
  - テスト: `tests/ui_tests_gen_test.sh` (26 件)、`wpf_check_test.sh` に UI002 を追加 (76 件)。

- **UI テストの既定を、別のデスクトップ (`separate`) にした** (推奨に基づく。ユーザーの了承は、実機の確認後)。`WATCH_UI_DESKTOP=default` で、ユーザーのデスクトップに戻せる。
- **ウォッチャー: `-UiTestDesktop separate`** — UI テストを、**別のデスクトップ** (Win32 の `CreateDesktop`) で実行する。ユーザーの画面に、ウィンドウが出ず、フォーカスも奪わない (実行中に、マウス・キーボードを使っていてよい、を目指す)。`dotnet test` を、ジョブオブジェクト (`KILL_ON_JOB_CLOSE`) に入れ、終了後・時間切れのとき、テストが起動して残ったアプリを、すべて終了する。既定は `default` (従来どおり)。UIA / スクリーンショットが、別のデスクトップで動くかは、**実機の PoC で確認する** (TEST-PLAN UT9〜UT13)。

- **ウォッチャー (別のデスクトップ、PoC の実機で発見):** WPF を PrintWindow で撮ると、クライアント領域が白くなる (ハードウェアアクセラレーションの描画)。`-UiTestDesktop separate` のとき、UI テストの間だけ、HKCU `Avalon.Graphics` の `DisableHWAcceleration=1` を設定し、終わったら元に戻す。**元の値は、変更する前に、`%LOCALAPPDATA%\claude-watcher\wpf-hwaccel-backup.txt` に記録し、ウォッチャーが異常終了して記録が残っていたら、次の起動時に元に戻す** (ユーザーの提案)。
- **ウォッチャー (UT7 の実機で発見):** テストが制限時間を超えて強制終了されたとき、リダイレクト先の `test_stdout.tmp` を、子プロセス (テストが起動したアプリ) が開いたままで、**読み取りに失敗し、`TEST_TIMEOUT` でなく `ENV_ERROR` (`別のプロセスで使用されているため...`) になった**。出力の読み取りを、共有を許す方式に変更。UI テストが時間切れのとき、残ったアプリも終了する。(ウォッチャーが固まらないこと、時間切れで強制終了されることは、実機で確認済み。)

- **ウォッチャー:** `trigger_uitest.flag` を追加 (`docs/DESIGN.md` 4.29)。UI テストのプロジェクト (名前が `UITests` / `UiTests` で終わる、または FlaUI.* を参照) だけを実行し、通常のテスト (`trigger_test.flag`) からは除く。環境変数 `UITEST_*` でテストに実行環境を渡す。実行の前後に、ソリューションのフォルダの下の残ったアプリを終了する。`-UiTestTimeoutSec` (既定 600)。
- **`build-test-loop`:** `uitest_once.sh` を追加 (失敗時のスクリーンショットの一覧を出す)。`build_test_once.sh` は、環境変数 `BUILD_TEST_FLAG` でフラグ名を変えられる。
- **PoC (`poc/flaui/`):** 段階 1 の確認用に、環境変数のテストと、わざと失敗させるスイッチ (`UIPOC_FAIL=1`) を追加。

## [2.4.2] 2026-10-19

- **`wpf-check` LAY001:** ViewModel 層のプロジェクトの `UseWPF` / `UseWindowsForms` / `-windows` も、error にした (WS13 の実機で、検査の漏れを発見。ロジック・データ層だけが対象だった)。ViewModel のソースの WPF の型は、従来どおり LAY002 (warning)。

- **ウォッチャー (`watch_and_build.ps1`):** プロジェクトの一覧を、**起動時に 1 回だけ**読んでいたため、起動後に、テストプロジェクトを後付け (`new_solution.py --tests mstest`) すると、`no tests found` の `ENV_ERROR` になり、再起動が要った (WS8 / WS9 などで 4 回再現)。**トリガーごとに、`.slnx` / `.sln` を読み直す**ようにした (2026-10-20 実機で確認済み (WS21)。ホストへの再配置が要る)。

- **`build_once.sh` / `build_test_once.sh`:** 前回の `build_summary.json` / `test_summary.json` を、実行の最初に消す (U11 の実機で発見: ENV_ERROR / PASSED / SUCCESS では、JSON が更新されず、前回の失敗の内容が、今回の結果のように残った)。

- **`new-solution` (WPF) の修正 (WS19 の実機で発見):** 層の名前を変えた (`viewmodel:Std.Presentation`) とき、アプリの `App.xaml.cs` の `using` と、`MainWindow.xaml` の `xmlns:vm` が、**存在しない `<ルート>.ViewModels`** を指し、`CS0234` でビルドが通らなかった。ViewModel のプロジェクトがあるときは、その名前空間 (`layer_namespace`) を使う (`add_project.py` の `wpf_app_files`)。テスト (`new_solution_wpf_test.sh`) を足した。

- **`wpf-check` RES002:** 同じ辞書の中の `StaticResource` の前方参照を、warning から **error** に (W8 の実機で、起動時の `InvalidOperationException` を確認。説明文も訂正)。

- **`wpf-check` BND003:** setter なしの読み取り専用プロパティへの、`TextBox.Text` などの既定 TwoWay のバインドを、warning から **error** に (W4 の実機で、起動時の `InvalidOperationException` を確認)。setter が public でない場合は、warning のまま。

- **`add-package` (実機 P9 / P11 の結果):** (1) `vcpkg search` は、マニフェストモードでは `builtin-baseline` が要る → 手順に「先に `vcpkg baseline`」を明記。(2) fmt は MSVC で `/utf-8` を要求する (C2338) → `cpp_pkg.py` の `add` / `remove` / `setup` が、各 `.vcxproj` に `<ItemDefinitionGroup Label="VcpkgDefines">` で `FMT_UNICODE=0` を自動で入れる / 外す (`/utf-8` は CP932 のソースが文字化けするので使わない。ポート別の表は `PORT_DEFINES`)。

**Skill の本文だけの変更** (再配布が必要: `install/install.sh`)。スクリプトの変更はない。

- **`auto-build` / `build-test-loop`:** 「スクリプトは、この Skill のフォルダのものだけを使う。同名の古いコピーを、探して使わない。要約が出ないときは、まず、古い版を実行していないか確認する」を追加した。
  - **きっかけ (実機の確認 U7):** コンソールの Claude が、ホーム直下の古いコピー (`~/cpp-build-test-loop/scripts/build_test_once.sh`、10/12 の版) を実行し、失敗の要約 (`[ran N: ...]`) と `test_summary.json` が出ないのを、「ツールの不具合」と記録した。**現行の配布版は、実機の trx を使った検証で、期待どおりの要約と JSON を出す** (古いコピーは、要約の処理を持たない)。古いコピーは、ホーム直下の `cpp-auto-build/` と `cpp-build-test-loop/` に残っている (ユーザーが、退避する)。
- **`add-package`:** 「C++ の NuGet は、対象外 (`packages.config` も、VS 2026 の `PackageReference` (Experimental) も)。C++ は vcpkg」を、明記した。
  - **決定 (ユーザー、2026-10-19):** VS 2026 の「C++ の NuGet PackageReference」(`EnableNativePackageReferenceSupport`。公式の記事 2026-05-19) は、**Experimental なので、対応を見送る**。手元の VS 2026 (18.8.1) と公式の記事で、仕組みは確認した (DESIGN 4.26 の調査メモ)。再開の条件も、同じ場所に記録。
- 手順書: U4 / U5 / U6b / WS5 を ✔ (2026-10-19 実機)。P22 を ✔ (公式の記事で確認)。P23 / P24 を、見送り。U7 は △ (上の原因)。U8 は △ (MSTest の実機の trx を、解釈できることを確認)。

## [2.4.1] 2026-10-18

**実機 (WPF + MSTest の最初の実行) で見つかった、ホスト側の不具合を 2 つ直した。** 設計: `docs/DESIGN.md` 4.24 の末尾。契約 (ファイル名・結果の値・終了コード) の変更は、ない。**ホスト側ツールの再配布が必要** (3 ファイルをまとめて。ウォッチャーは、起動し直す)。修正は、実機で、まだ確認していない (TEST-PLAN の U6b / U6c)。

- **文字化け:** `dotnet test` の出力 (UTF-8) を、ANSI (CP932) として読んでいたため、日本語が化けていた (`縺ｮ繝・せ繝・`)。**`Read-ProcessOutput`** を追加: 出力をバイト列で読み、UTF-8 として厳密に解釈し、できなければ ANSI として解釈する (BOM は除く)。GoogleTest の出力 (ANSI) も、そのまま読める。構造化された結果 (trx / XML) は、影響を受けていない。
- **テストが実行されなかった (`bin\auto\Debug` で DLL が見つからない):** `run_watcher.cmd` の cmd 変数 `PLATFORM` (= `auto`) が、環境変数 `Platform` として子プロセスに継承され、MSBuild がプロパティとして読んでいた (`dotnet test --no-build` だけが影響を受けた。ビルドは `/p:Platform` を明示するので、無事だった)。**`watch_and_build.ps1` が、起動時に環境変数 `Platform` を削除する。`run_watcher.cmd` の変数名を `WATCH_PLATFORM` / `WATCH_CONFIG` に変えた** (CP932 のまま)。
- 手順書に、U6b (文字化け) と U6c (環境変数の漏れ) を追加。

## [2.4.0] 2026-10-18

**WPF プログラミング規約を適用した。** ユーザーが示した規約 (19 章) で、`rules/wpf-csharp.md` を置き換え、生成物と `wpf-check` を、規約に合わせた。設計: `docs/DESIGN.md` 4.28。契約 (ファイル名・結果の値・終了コード) の変更は、ない。ホスト側ツールの変更も、ない。

**生成した C# / XAML は、まだ、コンパイルしていない** (4.27 と同じ)。**`App.OnStartup` で画面を作る形と、`Resources/Styles.xaml` の結合は、実機で確認が要る** (TEST-PLAN の WS17 / WS18)。

### 規約 (再配布が必要: `install/install.sh`。既存の `~/.claude/rules/wpf-csharp.md` は、バックアップ (`~1~`) が残る)
- **`rules/wpf-csharp.md`:** ユーザーの規約の章立て (1〜19 章: 適用範囲、基本方針、ソリューション構成 3.1 / 3.2、命名、C#、View、ViewModel、MVVM ライブラリの選択 (Toolkit / Prism)、バインディング、非同期、DI、例外、ログ、XAML、コメント、テスト、禁止事項、レビュー確認項目、最終方針) に、全面的に置き換えた。このツール群で追加した決まり (ファイルの形式、書式、`obj/` の編集禁止、`add-package`、MSTest の書き方、層のモデル) は、各章の「ツール群の補足」に残した。**規約と食い違う場合は、規約を優先する。** 末尾に、**規則と、ツール (`wpf-check` のコード) の対応表** (付録)。
- **差異を、補足に明記した:** テストは、ツール群が検証しているのは MSTest だけ (xUnit / NUnit は、未検証)。生成される構成は、アプリ + ライブラリの層 + ライブラリごとのテスト (規約 3.2 に近い)。**層の依存のモデルは、名前で 2 つに分かれる (混ぜない)。**

### Skill (再配布が必要)
- **`new-solution --type wpf` の生成物を、規約に合わせた:**
  - アプリの構成 (3.1): `App.xaml(.cs)` / **`Views/`** (`MainWindow`。名前空間 `<ルート>.Views`) / `ViewModels/` (`viewmodel` 層がないとき) / **`Resources/Styles.xaml`** (`DefaultControlMargin` / `PrimaryButtonStyle`。`App.xaml` の `MergedDictionaries` で結合)。
  - **`DataContext` の設定を、`App.xaml.cs` の `OnStartup` (composition root) に移した** (`StartupUri` を、やめた。`MainWindow` のコードビハインドは、`InitializeComponent()` だけ)。
  - 画面は `Grid` (`Auto` / `*`、`MinWidth` / `MinHeight`)、バインディングは `Mode` を明示 (TwoWay / OneWay)。
  - **`.` 区切りのプロジェクト名** (`SampleApp.Domain` など。規約 3.2 の名前) に対応 (`new-solution --layers data:SampleApp.Domain,...`、`add_project.py`)。名前空間は、その名前のまま。型名では `.` を除く。`CLAUDE.md` の雛形に、アプリの構成と、規約の場所を追記。
- **`wpf-check`:** **標準の層** (名前が `Presentation` / `Application` / `Domain` / `Infrastructure` で終わるプロジェクト) は、規約 3.2 の依存 (Presentation → Application → Domain、Infrastructure → Application / Domain。Domain は、何も参照しない。Domain / Application / Infrastructure は WPF に依存しない) で検査する (LAY001 / LAY003)。`--logic` / `--data` / `--viewmodel` の明示は、名前による推定より優先する。
  - **新しい検査 (すべて warning):** DI001 (ViewModel 内の `new XxxService()` など)、ASY001 (`.Result` / `.Wait()` / `GetAwaiter().GetResult()`)、ASY002 (イベントハンドラ以外の `async void`)、EXC001 (空の `catch`)、EXC002 (`throw ex;`)、NAM001 (bool の `Flag` / `Status` / `Check`)、UI003 (UserControl が自分自身を `DataContext` にする)。**LAY002 を拡張** (`OpenFileDialog` / `SaveFileDialog` / `Clipboard` / `.ShowDialog()` / `Views` の名前空間)。
  - **機械で判定できない項目は、検査しない** (責務の分離の妥当性、メソッドの大きさ、コメントの質など)。**通ったことは、規約を満たすことを、意味しない。**
- `wpf-test-first/PROJECT-LAYOUT.md`: アプリの構成 (3.1)、composition root、規約 3.2 の名前を追記。`new-solution` / `wpf-check` の `SKILL.md` を更新。

### テスト・文書
- `tests/wpf_check_test.sh` を 47 → **72 項目** (新しい検査と、誤検出しない形、標準の層)、`tests/new_solution_wpf_test.sh` を 51 → **59 項目** (規約の構成、composition root、`Grid`、`Mode`、`.` 区切りの名前)。`docs/DESIGN.md` に 4.28、`docs/TEST-PLAN.md` に WS17〜WS20。

## [2.3.0] 2026-10-18

**WPF のソリューションの生成 (`new-solution --type wpf`)、テスト先行 (`wpf-test-first`)、規約 (`rules/wpf-csharp.md`) を追加。** C++ / MFC で作った一式を、WPF でも同じ流れで使えるようにする。設計: `docs/DESIGN.md` 4.27。

**生成した C# / XAML は、まだ、コンパイルしていない** (WSL に .NET がない。手で読んで確認し、`wpf-check` にかけて、指摘 0 件を確認した)。**MSTest の既定のバージョン (Test.Sdk 17.12.0、MSTest 3.6.4) が、nuget.org に実在することも、未確認。** 配布前に、`docs/TEST-PLAN.md` の 2-4 (**WS6 → WS2 → WS3 の順**) を、実機で確認する。契約 (ファイル名・結果の値・終了コード) の変更は、ない。ホスト側ツールの変更も、ない。

### Skill (再配布が必要: `install/install.sh`)
- **`new-solution`:** `--type wpf` を追加 (WPF、MVVM。.NET)。
  - **構成: View (WPF アプリ) → ViewModel → ロジック → データ。** 層は、`--layers` に `data` / `logic` / `viewmodel` を、組み合わせる (既定の名前 `DataLayer` / `LogicLayer` / `ViewModels`)。**層は、WPF 非依存のクラスライブラリ** (`net8.0`。ViewModel が `System.Windows` を、使えないことを、型で強制する)。`viewmodel` を作らないと、ViewModel は、アプリの `ViewModels/` フォルダ (テストできない)。
  - **`--tests mstest`:** 層のライブラリごとに `<名前>.Tests` (MSTest v3: `Microsoft.NET.Test.Sdk` + `MSTest.TestAdapter` + `MSTest.TestFramework`)。View は、テストしない。層がないと、エラー。`--tests gtest` と、C++ 用の引数 (`--layer-kind` / `--gtest` / `--toolset`) は、エラー。
  - 追加の引数: `--tfm` (既定 `net8.0`)、`--mstest-version`、`--testsdk-version`。**テストの後付け:** すでにある .NET のソリューションで `--tests mstest`。`--spec` は、`wpf` / `mstest` / `viewmodel` を読む。
  - 作るもの: `.slnx` (構成なし。アプリに `DefaultStartup`)、SDK 形式の `.csproj`、`Directory.Build.props` (`Nullable` / `ImplicitUsings` / `LangVersion`)、`.editorconfig`、サンプル (`MainWindow` と `MainViewModel`。自前の最小実装の `ObservableObject` / `RelayCommand`。NuGet 不要)、`CLAUDE.md` (`- テスト: あり (MSTest)`) / `.gitignore` / `.gitattributes`。
  - **C++ の経路は、変えていない** (`parse_layers` に、引数を足しただけ。WPF のコードは、`--type wpf` / `--tests mstest` のときだけ、読み込む)。
- **`wpf-test-first` を追加:** `cpp-test-first` の骨格 (ゲート・正しい Red の条件・ループの規則・完了時の報告) を、WPF に移した。WPF 固有: スタブは `NotImplementedException` にしない (例外で落ちるので、Red ではない)、ViewModel のスタブは通知を上げない、`.csproj` への追加は不要 (SDK 形式)、**View は、テストしない** (ViewModel への切り出し案を示して止まる)、実装のあとに `wpf-check`、パッケージは `add-package`。
  - `PROJECT-LAYOUT.md` (構成と規約、`.sln` / `.slnx`、よくある失敗)。
  - `scripts/add_project.py`: クラスライブラリ + `<名前>.Tests` を、**`.slnx` と、Visual Studio 形式の `.sln` の両方**に追加する (`.sln` は、プロジェクトの種類の GUID と、構成の対応付け (ソリューションの構成 → プロジェクトの `Any CPU`) も足す)。`--kind lib|data|logic|viewmodel`、`--tests-only`、`--uses`、`--dry-run`。既存は、上書きしない (rc=3)。
- **`add-feature` / `update-from-ideas`:** WPF に対応 (`CLAUDE.md` の `- メイン:` / `- テスト:` で、`cpp-test-first` と `wpf-test-first` を選ぶ。構成案の値に `wpf` / `mstest` / `viewmodel` を追加。**WPF か MFC かは、ユーザーが決める**)。

### 規約・ひな形 (新規)
- **`rules/wpf-csharp.md`** (ユーザー共通。`paths` は `**/*.cs` `**/*.xaml` `**/*.csproj`): C++ の規約 (`cpp-mfc.md`) と同じ方針の項目はそろえ (UTF-8 BOM + CRLF、Allman、コメントは日本語)、.NET の慣習の項目は合わせた (定数は PascalCase、private フィールドは `_camelCase`、`Async` の接尾辞)。**WPF 固有:** 層と MVVM (View に業務ルールを書かない、ViewModel は WPF の型を使わない、`INotifyPropertyChanged`、`ObservableCollection`、コマンド、`DataContext` の設定と `d:DataContext`、バインディングの綴り、リソースの順序、UI スレッド)、例外とリソース、MSTest の書き方 (命名、AAA、期待値の順、フェイク、`[Ignore]` の禁止)。**`wpf-check` の検査項目と、対応させた。**
- **`templates/dotnet/`:** `.editorconfig` (Allman、ファイルスコープの名前空間、命名、`utf-8-bom` (`.slnx` / `.json` / `.md` は BOM なし)) と `Directory.Build.props`。**生成の定数と同じ内容** (テストで一致を確認)。
- **`install/install.sh`:** 規約を `~/.claude/rules`、ひな形を `~/.claude/templates` に配る (`--rules-dir` / `--templates-dir` / `--rules-only`)。**既存のファイルは、上書きせず、番号付きのバックアップ (`~1~`) を残す** (同じ内容なら、何もしない)。先頭が `.` のファイルも、配る。

### ツール・文書
- `tests/add_project_test.sh` (24 項目)、`tests/new_solution_wpf_test.sh` (51 項目。**生成物が `wpf-check` で指摘 0 件**を、4 つの形で確認)。
- `docs/DESIGN.md` 4.27 (方針、層を、WPF 非依存のライブラリにする理由、MVVM の基底を自前にした理由、MSTest の参照と版、取り下げた案、検証の範囲)。`docs/TEST-PLAN.md` に 2-4 (WS1〜WS16)。`README.md` を更新。`.gitattributes` に、`templates/` `rules/` `tests/fixtures/`。

## [2.2.0] 2026-10-18

**パッケージの追加 (NuGet / vcpkg / ソースの取り込み) を、ホスト側に実行させる。** WSL からは、NuGet も vcpkg も、実行できないため。設計: `docs/DESIGN.md` 4.26。

**Windows 側 (`watch_and_build.ps1` の、パッケージの操作) は、実機で未検証。** WSL のサンドボックスから PowerShell を実行できない (括弧の対応のみ確認)。vcpkg のマニフェストモードと MSBuild の連携 (`vcpkg.json` を探す場所、`Label="Vcpkg"` の効き方) も、実機で未確認。**配布前に、`docs/TEST-PLAN.md` の 1-6 (P1 から) を、実機で確認する。**

### 契約の追加 (後方互換。既存のファイル名・結果の値・終了コードは、変えていない)
- `trigger_package.flag` (Claude): 各行が 1 操作 (`nuget search/versions/add/remove`、`vcpkg search/baseline/install`、`fetch`)。上から順に実行し、最初の失敗で止まる。
- `package_output.txt` / `package_error.log` / `package_result.txt` (ウォッチャー): 出力 / 失敗時のみ (環境の問題は、先頭が `[ENVIRONMENT ERROR ...]`) / 完了マーカー `OK` / `FAILED` (最後に書く)。
- ビルド・テスト・gtest 取得とは独立。**ビルドより先に処理される。**

### ホスト側ツール (再配布が必要。3 ファイルをまとめて)
- `watch_and_build.ps1`: パッケージの操作を追加。
  - **引数は、決まった文字だけを許可して、検証する** (ID・語・リポジトリ・タグ・名前・バージョン。`-` 始まりは拒否。プロジェクトは、ソリューションの下の、存在する `.csproj` などに限る)。
  - `nuget search` / `versions` は、nuget.org の REST API (ダウンロード数と `verified` も出す)。`nuget add` / `remove` は、`dotnet add / remove package` (結果のバージョンを、`.csproj` / `Directory.Packages.props` から読んで返す)。`NU1101` (名前の誤り) は、環境エラーにしない。
  - `vcpkg search / baseline / install`: VS 同梱の vcpkg (`VC\vcpkg\vcpkg.exe`。`-VcpkgExe` → `VCPKG_ROOT` → `vswhere` の順) を使う。トリプレットは、Platform から (既定 `x64-windows-static-md`)。
  - `fetch <owner/repo> <タグ> <名前> [<サブフォルダ>]`: GitHub のタグのソースを、`ThirdParty\<名前>\` に置く (GoogleTest の取得と、同じ構造。**GoogleTest の取得は、そのまま**)。
  - 新しい引数: `-PackageTimeoutSec` (既定 1800)、`-VcpkgExe`、`-VcpkgTriplet`。`Invoke-TestProcess` に、制限時間の引数を追加 (既定は、従来どおり)。

### Skill (再配布が必要: `install/install.sh`)
- **`add-package` を追加:** どの方法を使うかの判断 (NuGet / vcpkg / `fetch`。**GoogleTest は対象外**)、共通のルール (追加する前に、実在とバージョンを確認する。名指しされた名前だけを追加する。バージョンを固定する)、各手順、完了時の報告 (変更したファイル・バージョン。`git commit` はしない)。
  - `scripts/package_once.sh`: フラグを置いて、完了を待つ。**操作の形を、フラグを置く前に、検証する** (ウォッチャーと同じ規則。多重の防御)。`--file` (`ThirdParty.manifest` の再現)、`--timeout`。1 行目と終了コード: `OK` 0 / `FAILED` 1 / `BAD_ARGS` 2 / `WATCHER_NOT_RUNNING` 3 / `ENV_ERROR` 4 / `TIMEOUT` 5。
  - `scripts/cpp_pkg.py` (WSL で完結。ネットワーク不要): `setup` (`vcpkg.json` と、各 `.vcxproj` の `Label="Vcpkg"` (マニフェストモード + プラットフォーム別トリプレット)。gtest を除く。冪等。BOM・改行・インデントを保つ)、`add` / `remove` / `list` (`vcpkg.json`)、`include-dir` (全構成の `AdditionalIncludeDirectories`)、`record-fetch` (`ThirdParty.manifest` と `.gitignore`)。
- `auto-build`: ライブラリの不足が原因のエラー (`C1083` / 外部の `LNK2019` / `CS0246` / `NU1101`) は、`.csproj` / `.vcxproj` を、自分で書き換えず、`add-package` で追加する、という規則を追加。

### ガード・文書
- `docs/RECOMMENDED-SETTINGS.md`: **`add-package` の `permissions.ask`** (`Bash(*package_once.sh*)`、`Bash(*cpp_pkg.py*)`、`Edit(**/vcpkg.json)`、`Edit(**/*.vcxproj)`、`Edit(**/ThirdParty.manifest)`)。供給網への入口になるため。`cpp_pkg.py` は別のプロセスが書くので、`Edit` のルールが効かず、`Bash` にも `ask` が要る。**実機での確認は、未実施。**
- `docs/DESIGN.md` 4.26 (方針、引数の検証、取り違えへの対策、vcpkg の採用理由とトリプレット、**取り下げた案**、検証の範囲)。`docs/TEST-PLAN.md` に 1-6 (P1〜P21)。`README.md` / `host-tools/README.md` を更新。`.gitignore` に、新しい生成ファイル。

### テスト
- `tests/package_once_test.sh` (41 項目: 疑似ウォッチャー。操作の検証 (注入・`..`・絶対パス・`-` 始まりなど 17 種類を拒否)、結果の分岐、古い結果の除去、`--file`、出力の上限)、`tests/cpp_pkg_test.sh` (35 項目: 疑似の `.vcxproj`。BOM と CRLF の保持、冪等、XML の整合)。

## [2.1.0] 2026-10-18

### Skill (再配布が必要: `install/install.sh`)
- **`wpf-check` を追加 (独立した Skill。手動で実行する。ウォッチャーも Windows も .NET も不要。読み取りだけ):** WPF の「コンパイルは通るが、実行時に壊れる」部分を、静的に検査する (`scripts/wpf_check.py`)。`mfc-check` と同じ形 (出力・`--all` / `--json` / `--max-lines`・終了コード 0 / 1 / 2 / 3)。設計: `docs/DESIGN.md` 4.25。
  - **バインディング (BND / CMD):** `{Binding}` のパスが、DataContext の型にない (綴りの近い候補を添える)、public フィールド・メソッド・非 public・static へのバインド、読み取り専用プロパティへの TwoWay、`INotifyPropertyChanged` の未実装、`Command` に `ICommand` でない型。DataContext の型は、XAML の `DataContext` / `<X.DataContext>` / `DataTemplate` の `DataType` / code-behind の `DataContext = new Xxx()` / `= this` / コンストラクター引数 / `GetService<Xxx>()` / ウィンドウを作るコードから推定する。**基底クラスが外部 (`Window` や未知のクラス) の型は、「ない」と言わない** (`--all` の BND900)。`d:DataContext` だけが根拠なら warning。CommunityToolkit.Mvvm の `[ObservableProperty]` / `[RelayCommand]` が作るメンバーを知っている。
  - **リソース (RES / CNV):** `StaticResource` の未定義・同じ辞書の後ろで定義 (前方参照)、`x:Key` の重複、`DynamicResource` の未定義、結合した辞書の `Source` が見つからない、`Converter` が `IValueConverter` を実装していない。祖先の `Resources` → `App.xaml` の辞書の順に厳密に辿る。外部の辞書 (NuGet のテーマなど) やライブラリの XAML は、error を warning に下げる。コードから足されるキー (`Resources["X"] = ...`) は知っている。
  - **起動 (UI / APP):** code-behind のコンストラクターが `InitializeComponent()` を呼んでいない (例外も出ず、画面が空になる)、`StartupUri` が見つからない。
  - **層 (LAY):** ロジック層・データ層の WPF 依存 (`UseWPF` / `-windows` / `System.Windows` / `MessageBox`)、ViewModel の View 型の使用 (warning)、プロジェクト参照の向き (View → ViewModel → ロジック → データ)。`--logic` / `--data` / `--viewmodel` で層を指定できる。
  - **対象外:** コンパイルエラーになるもの (イベントハンドラの不足、`x:Name` の重複、XAML の文法)。ビルドが `MC` / `XDG` / `CS` で教える。
  - 実装: XAML は expat で読み (行番号・属性の順序・名前空間・属性の行)、C# は軽い字句解析 (コメント・文字列・raw 文字列を除き、型・メンバー・基底クラス・コンストラクターを取り出す)。
- **契約 (ファイル名・結果の値・終了コード) の変更は、ない。** ホスト側ツールの変更も、ない。

### ツール・文書
- `tests/wpf_check_test.sh` を追加 (47 項目。**正常なプロジェクトに指摘が出ないこと**と、不具合を 1 か所ずつ入れたときの各コード、BOM + CRLF の行番号、出力の上限、終了コード、読み取り専用)。
- `docs/DESIGN.md` に 4.25、`docs/TEST-PLAN.md` に 2-3 (W1〜W12) を追加。**実プロジェクトでは、まだ検証していない。** `mfc-check` の経験から、実プロジェクトで誤検出が見つかる可能性が高い (W1 を最初に)。
- BND003 (読み取り専用への TwoWay が、実行時に例外になるか)、RES002 (前方参照が、実行時に失敗するか) の、実際の動作は、未確認 (W4 / W8)。

## [2.0.0] 2026-10-18

**C++ と .NET (WPF + MSTest) の統合。** 1 つのウォッチャーと 1 組の Skill で、C++ のみ、.NET のみ、混在のソリューションを扱う (設計: `docs/DESIGN.md` 4.24)。

**Windows 側 (`watch_and_build.ps1` / `build-windows.cmd` / `run_watcher.cmd`) の変更は、実機で未検証。** WSL のサンドボックスから PowerShell を実行できなかったため、括弧の対応と、CP932 の `rem` 行の確認だけ行った。**配布前に、`docs/TEST-PLAN.md` の 1-5 (U1 の、C++ の回帰から) を、実機で確認する。**

### Skill の名前の変更 (配り直しと、旧名の削除が必要: `install/install.sh`)
- `cpp-auto-build` → **`auto-build`**、`cpp-build-test-loop` → **`build-test-loop`**。技術名を外した。**旧名の Skill が配布先に残ると、description が重なるので、手で削除する** (`install.sh` が、残っていれば知らせる)。`cpp-test-first` / `mfc-check` / `new-solution` は、変更なし。
- 両 Skill の本文を、.NET に対応させた: XAML / C# / NuGet / SDK のエラーコードの読み方、`obj/` の生成物 (`*.g.cs`) を直接編集しない、警告の抑制 (`#pragma warning disable` / `NoWarn` / `TreatWarningsAsErrors` の解除) でビルドを通さない、`.csproj` などの変更は最小限で報告する、MSTest での禁止事項 (`[Ignore]` / `Assert.Inconclusive` / `.runsettings` で外す / アサーションを弱める / `[Timeout]` の延長)、完了時の報告のテストファイルに `*Tests/` / `*Tests.cs` を追加。

### テスト結果の共通の形式
- **`summarize_test_log.py` が、GoogleTest の XML と MSTest の trx を、共通の形式に変換して集約する** (`--results-dir`、`--root`)。同じメッセージの失敗は、フレームワークをまたいで、1 つにまとまる。見出しに `[ran N: passed / failed / skipped]`。構造化された結果がなければ、従来のテキスト解釈に戻る。クラッシュの報告 (`(no gtest failure lines ...)`、`Hung test`) は、`other:` に併記する。壊れた XML は、`other:` に残し、読めるものは使う。
- **`test_summary.json` は schema 2** (`schema` / `structured` / `totals` / `sources` を追加。**従来のキー `failed` / `groups` / `tests` / `other` は、そのまま**)。
- `build_test_once.sh` が、`.claude-logs/test-results/` を、`--results-dir` に渡す。フラグを置く前に、前回の結果を消す。
- `summarize_build_log.py` (2 つの Skill のコピー): 診断コードの接頭辞を、1〜4 文字から **1〜8 文字**に広げた (`NETSDK1045` / `MSTEST0037` が、`other:` に落ちていた)。

### ホスト側ツール (再配布が必要。3 ファイルをまとめて)
- **契約の追加 (後方互換):** `.claude-logs/test-results/` (`<exe名>.xml`、`<プロジェクト名>.trx`)。**既存のファイル名・結果の値・終了コードの意味は、変えていない。** `ENV_ERROR` の意味を広げた (テストが見つからない (C++ も .NET も)、`dotnet` がない、.NET のテストが 1 件も実行されない)。
- `watch_and_build.ps1`:
  - ソリューションの中身 (`.vcxproj` / `.csproj` / `.vbproj` / `.fsproj`) を判定する。`-Platform` の既定が **`auto`** (C++ があれば `x64`、.NET だけなら `AnyCPU`)。`AnyCPU` を追加。
  - `build-windows.cmd` に、第 6 引数 `Features` (`cpp` / `restore`) を渡す。判定できなければ、従来どおり `cpp`。
  - GoogleTest の exe に `--gtest_output=xml:` を足す。.NET のテストプロジェクト (`Microsoft.NET.Test.Sdk` / `MSTest` を参照、`IsTestProject`、名前が `Test(s)` で終わる) を、`dotnet test --no-build --logger trx` で実行する。両方ある場合は両方を実行し、結果は 1 つの `test_result.txt`。trx の `executed` が 0 なら `ENV_ERROR`。
  - .NET の環境エラー (`MSB4236` `NETSDK1045` `NETSDK1141` `NU1301`) を、`[ENVIRONMENT ERROR ...]` にする。`NU1101` は、ソースの問題として、そのまま。
  - 新しい引数: `-DotnetTestArgs`、`-DotnetExe`。起動時のヘッダーに、`Solution` (種類) と `dotnet test` の行を追加。
- `build-windows.cmd`: 第 6 引数 `Features`。`cpp` がなければ、VS の要求が MSBuild だけになり、`cl.exe` の確認もしない。`restore` で `/restore` (`Clean` では付けない)。`AnyCPU` (MSBuild には `Any CPU`)。**`Features` を省略した呼び出しは、従来と同じ動作** (`/p:Platform` を、引用符で囲む点だけが違う)。
- `run_watcher.cmd`: Platform の既定を `auto` に。

### ガード・文書
- `docs/RECOMMENDED-SETTINGS.md`: **.NET を含むプロジェクトの `permissions`** を追加。`ask`: `*Tests/**` `*.Tests/**` `*Tests.cs` `*Test.cs` (C++ 用の `*Test/**` は `MyApp.Tests/` に一致しないため)、`*.csproj` `Directory.Build.props` `Directory.Packages.props` `global.json` `*.runsettings`。`deny`: `obj/` `bin/` `*.g.cs` `*.g.i.cs` `packages.lock.json`。**実機での確認は、未実施。**
- `docs/DESIGN.md`: 4.24 (統合の方針、判定、テストの実行、共通の形式、**採らなかった案** (C++ のテストを `CppUnitTestFramework` に移す、`dotnet build` へのフォールバック)、検証の範囲)。契約の表、4.11、6 章を更新。`docs/TEST-PLAN.md`: 1-5 (U1〜U16) を追加。`README.md` / `host-tools/README.md` を更新。
- `install/install.sh`: 旧名の Skill が残っていれば、知らせる。

### テスト
- `tests/fixtures/` (GoogleTest の XML、MSTest の trx。**仕様から書いたサンプル。実機の出力で差し替える: TEST-PLAN の U8**) を追加。`tests/summarize_test_log_test.sh` を 15 → 34 項目、`tests/summarize_build_log_test.sh` を 20 → 26 項目 (.NET の診断コード)、`tests/fake_watcher_test.sh` に、構造化された結果の経路と、前回の結果が消えることを追加。

## [1.6.0] 2026-10-18

### Skill (再配布が必要: `install/install.sh`)
- **`/new-solution` に、メインの種類を 2 つ追加:** `--type mfc-mdi` (MFC MDI: `CMultiDocTemplate`・`CMDIFrameWnd`・`CMDIChildWnd`、`Window` メニュー付き) と、`--type mfc-dialog` (MFC ダイアログベース: `CDialog` 派生、`DoModal`、`IDD_SAMPLE_DIALOG` に OK / Cancel と静的テキスト)。`--type mfc` は、従来どおり SDI。層・テスト・GoogleTest の指定は、どの種類でも、同じ。
  - 生成物は、`mfc-check` で、error / warning 0 (`tests/new_solution_test.sh` で確認)。`--spec` の構成案 (`- メインの種類: mfc-mdi`) からも、読める。
  - 名前が `Test` で終わるときの出力名の変更 (`<名前>_Main`) は、新しい種類にも、効く。
- **生成する `.slnx` で、メイン (exe) に `DefaultStartup="true"` を付ける:** 層 (DLL) があると、Visual Studio が、スタートアッププロジェクトに、DLL (`DataLayer` など) を選び、F5 が「有効な Win32 アプリケーションではありません」で、失敗した (`MfcDlgLayers` の実機の確認で発見。`.slnx` で exe を先頭に置いても、効かなかった)。最初に開くときは、メインが選ばれる。個人の設定 (`.vs/` の `.suo`) が、すでにあれば、そちらが優先される。あわせて、生成する `CLAUDE.md` と、`/new-solution` の完了報告に、その旨と、選び直す手順を追加した。
- **実機の確認:** MFC の SDI / MDI / ダイアログベースの、三層 (層 2 つ、テストなし) を、ウォッチャー経由でビルドして、`SUCCESS`。
- **契約 (ファイル名・結果の値・終了コード) の変更は、ない。**

## [1.5.0] 2026-10-17

### Skill (再配布が必要: `install/install.sh`)
- **`mfc-check` を追加 (独立した Skill。手動で実行する。ウォッチャーも Windows も不要。読み取りだけ):** MFC の「コンパイルは通るが、実行時に壊れる」部分を、静的に検査する (`scripts/mfc_check.py`)。
  - **リソース (RES):** 未定義 ID、コマンド ID / 同じダイアログ内のコントロール ID / 同じ種類のリソースの、値の重複、`resource.h` の未使用 ID。リソース定義の名前だけが未定義の場合は、名前付きリソースとして、warning にする (RC は受け付けるため)。
  - **メッセージマップ (MAP):** ハンドラの宣言・定義の有無、`DECLARE_MESSAGE_MAP` と `BEGIN_MESSAGE_MAP` の対応、`afx_msg` の孤立、引数の数、ID の重複。
  - **UI との対応 (UI):** `ON_COMMAND` の ID が `.rc` のメニュー・アクセラレータ・ツールバーにあるか、コントロール通知・`DDX` の ID が `.rc` のダイアログにあるか。
  - **ダイアログ (DLG):** `DDX` / `DDV` の ID が、**そのクラスのダイアログ** (`IDD`) にあるか、`IDD` が `.rc` に DIALOG としてあるか、`DDX_Control` のメンバーの型がコントロールの種類と合うか (`EDITTEXT` に `CListCtrl` など)、ボタンにハンドラがあるか、既定ボタンが複数でないか、`OnInitDialog` / `DoDataExchange` が基底を呼んでいるか、ニーモニックの重複 (info)。ダイアログの ID は、`enum { IDD = ... }` か、コンストラクタの基底の初期化から読む。
  - **層の依存 (LAY):** ライブラリ (DLL / lib) での GUI のクラス・ヘッダーの使用、プロジェクト参照の向き (UI → ロジック → データ)。
  - **ダイアログ (DLG010):** 同じメンバーを、別の ID に対して、複数の `DDX_Control` に渡している (warning)。MFC の `DDX_Control` は、接続済みのメンバーを探さないので、2 回目以降は、実行時に、何も起きない (コピー&ペーストの誤りに多い)。実機の確認で見つけた。`else` / `case` / `default` をまたぐ呼び出しは、除く。
  - **ダイアログ (DLG009):** `AFX_DIALOG_LAYOUT` が、存在しないダイアログのもの (VS が残した不要な定義。info)。
  - **実プロジェクト (`DoubleBufferSample`) での検証で、誤検出を 4 種類修正:** 継承したハンドラ、宣言の末尾の `final` / `override`、入れ子のクラスのメッセージマップ (`BEGIN_MESSAGE_MAP(Outer::Inner, ...)`)、`AFX_DIALOG_LAYOUT` / `DESIGNINFO` の扱い。`ON_WM_CTLCOLOR_REFLECT` のハンドラ名 (`CtlColor`) も、直した。
  - **`.rc` は UTF-16 (BOM)・UTF-8・CP932 のどれでも読める** (ウィザード生成の `.rc` は UTF-16。`grep` では読めない)。出力は、ビルドの要約と同じ形式 (重大度順、最大 40 行、`--json`)。終了コード: 0 / 1 (error あり) / 2 / 3 (対象なし)。
  - 標準 ID は、`afxres.h` を読まず、接頭辞で判定する。基底クラスのハンドラ (`&CWinApp::OnFileNew`) は、宣言・定義の検査から外す。
- **契約 (ファイル名・結果の値・終了コード) の変更は、ない。** 既存の Skill とホスト側ツールは、変更していない。

### ツール・文書
- `tests/mfc_check_test.sh` を追加 (疑似プロジェクトで、全ルールの検出と、正常なプロジェクトの誤検出のなさ、層の依存、例外系、実プロジェクトでクラッシュしないこと。ダイアログの正常 / 異常のケースと、実プロジェクトで見つけた誤検出の再発防止を含む。69 項目。実プロジェクトのソースに、未コミットの変更がある間は、`error 0` の確認を、クラッシュしないことの確認に、切り替える)。
- `docs/DESIGN.md` に 4.23、`docs/TEST-PLAN.md` に K1〜K11 を追加 (実機の確認手順は、`DoubleBufferSample` の具体的な行で書いてある)。

## [1.4.1] 2026-10-15

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
