# UI テスト (FlaUI): 実行と書き方の詳細

> `<Skill群>` の意味は、`SKILL.md` の冒頭の「パスの書き方」を参照。

`build-test-loop` の `SKILL.md` から分けた文書。**UI テストを、実行する・書く・足す・失敗を調べるときだけ読む** (ふだんの、ビルド → テストの流れでは、読まない)。`$SLN_DIR` などの用語は、`SKILL.md` と同じ。UI テストは、**ユーザーが求めたとき**と、**`/ui-test-first` のループの中**だけ実行する (ビルド → テストの流れには含めない。`PASSED` になっても、自動では、続けて実行しない)。

**UI テストは、ビルド → テスト (`build_test_once.sh`) の流れに、含めない。** 遅く、アプリを起動し、**制限時間を長く取る必要がある**ため、`PASSED` になっても、自動では、続けて実行しない。実行するのは、次のときだけ。
- **ユーザーが、UI テストの実行を求めたとき。**
- **`/ui-test-first` のループ** (画面を、プロンプトで作りながら、UI テストを先に書き、繰り返し実行する)。UI テストを先に書いて Red にする、UI テストファーストは、このループが担う (従来の「しない」は、取り下げた。DESIGN 4.38)。

## UI テストの、実行の指定 (どれも、ウォッチャーの再起動は、要らない)
`uitest_once.sh "$SLN_DIR" [待つ秒] [--filter 式] [--ui-timeout 秒] [--visible | --separate] [--slowmo ms]`
- **`--filter "FullyQualifiedName~クラス名"`:** `dotnet test --filter` の式で、**いま書いた UI テストだけ**を実行する (UI のループで、毎回、全部を走らせない)。式に、引用符・改行は、使えない。`~` は「含む」、`=` は「等しい」、`&` / `|` で組み合わせる。絞った結果が 0 件だと、何も実行されず、**`ENV_ERROR` (終了コード 4。`dotnet test` の「一致するテストはありません」が、そのまま出る)** になる (式の誤りは、これで気づける。実機で確認)。
- **`--ui-timeout 秒`:** ウォッチャーが、UI テストのプロジェクトを、強制終了するまでの時間 (既定 600 秒)。**UI テストが多い、重い画面は、長く** (例: `--ui-timeout 1800`)。指定しない既定は、`uitest.settings` の `timeout=` (プロジェクトごとの既定。例: `timeout=1800`) → ウォッチャーの `-UiTestTimeoutSec` / `WATCH_UI_TIMEOUT_SEC`。`--ui-timeout` が 780 以上なら、Skill 側の待ち時間も、自動で、`秒 + 120` に延びる。
- デスクトップ (`--visible` / `--separate`)、操作の間の待ち (`--slowmo`) は、上の「どのデスクトップで実行されるか」。
- **実行が、遅い・止まっているように見えるとき:** `.claude-logs/ui-timing.txt` (UI テストの各段階の時刻。実行ごとに作り直される) を読む。どの段階の間が、長いかが、分かる (ビルド完了から UI テスト開始までの空白、`dotnet test` の開始から終了まで、など)。
- **`--hold 秒` / `--preview [秒]` (目視確認):** UI テストは、いつもは、裏 (別のデスクトップ) で実行し、**見たいときだけ、その画面を、ユーザーのデスクトップに出す。** 生成される `PreviewUiTests.cs` (`[TestCategory("Preview")]`。アサーションなし) が、画面を、見せたい状態にして、`HoldForViewing()` を呼ぶ。`--hold N` は、`HoldForViewing` が、N 秒、待つ (ウィンドウを閉じると、早く終わる)。`--preview [N]` は、`--visible --hold N` (既定 60 秒) の省略形。例: `uitest_once.sh "$SLN_DIR" --filter "TestCategory=Preview" --preview`。ウォッチャーの制限時間は、`hold + 120` 秒以上に、自動で延びる。`UiTestBase.Snap("名前")` は、裏でも PNG を残す (Claude が、画像として読む)。`/ui-test-first` の「目視確認」に、手順。**既存の UI テストのプロジェクト (この機能より前に作ったもの) は、先に `python3 <Skill群>/new-solution/scripts/add_ui_tests.py <フォルダ> --refresh-support-files` で、`UiTestBase.cs` などを更新する** (旧い版のままだと、`HoldForViewing` / `Highlight` がなく、`--present` の赤い枠が出ず、操作の間隔が、約 3 倍になる。実機で確認)。
- **`--present` (デモとして再生):** `--visible` + `--slowmo 800` (指定がなければ) + **操作する要素を赤い枠で囲む** (`UiTestBase.Find` / `OpenModal` が描く。`UITEST_PRESENT=1`)。UI テストを、そのまま、見せられる形で、ゆっくり再生する。**再生するのは、`--filter` で指定したテストだけ** (`--filter` が必須。ないと `BAD_ARGS`)。`--separate` とは、同時に使えない。入力やボタンの押下は、UIA で、一瞬で行われる (マウスのカーソルは、動かない。枠と待ちで、見せる)。

## いつ実行するか
- **ユーザーが求めたとき、または `/ui-test-first` のループの中だけ。** `build_test_once.sh` が `PASSED` になっても、UI テストのプロジェクト (名前が `UITests` / `UiTests` で終わる、または FlaUI を参照。`CLAUDE.md` に「UI テスト (FlaUI)」の節がある) があっても、**ユーザーが求めていなければ、実行しない。**
- UI テストは、**通常のテスト (`build_test_once.sh`) には、含まれない**。
- 実行するのは、**ソースを変えたとき**。修正の途中の、毎回は、実行しない (直したら、`--filter` で、そのテストだけ)。

```bash
bash <このSkillのフォルダ>/scripts/uitest_once.sh "$SLN_DIR" 900
```
使い方、出力の形、`FAILED` / `ENV_ERROR` / `TEST_TIMEOUT` の読み方は、`build_test_once.sh` と同じ。`run_in_background: true` で実行し、完了通知を待つ。

- **どのデスクトップで実行されるかは、UI テストのプロジェクトの `uitest.settings` が決める (ウォッチャーの起動し直しは、要らない。フレームワークごとの違いを、ウォッチャーでなく、このファイルが持つ):** `<アプリ>.UITests/uitest.settings` に `desktop=visible` (ユーザーのデスクトップ) または `desktop=separate` (別のデスクトップ。`invisible` でも同じ)、`slowmo=N` を書く。**`add_ui_tests.py` が、プロジェクトを作るときに書く: WPF は `visible`** (WPF のメニューのポップアップが、別のデスクトップでは、開かないため)、**それ以外 (WinForms / MFC / C#) は `separate`** (ウィンドウが画面に出ず、ユーザーに「触らないで」と頼む必要は、ない)。ファイルがなければ、`separate`。`--refresh-support-files` は、ファイルがなければ足す (あれば、上書きしない)。**1 回ごとの指定 (ファイルより優先):** `uitest_once.sh <dir> [秒] --visible` (ユーザーのデスクトップ) / `--separate` または `--invisible` (別のデスクトップ。WPF でも。メニューを使わないテストや、ユーザーが PC を使いたいとき) / `--slowmo 800` (操作の間に待ちを入れる)。指定は、`trigger_uitest.flag` の中身 (`desktop=visible` / `desktop=separate` / `slowmo=N`) として、ウォッチャーに渡る。**優先順:** この 1 回ごとの指定 > ウォッチャーの設定 (`-UiTestDesktop` / `WATCH_UI_DESKTOP` で `default` / `separate` を指定したとき。`run_watcher_visible.cmd` は、`default` に固定する) > `uitest.settings` > `separate`。UI テストのプロジェクトが複数あるときは、1 つでも visible なら visible。ウォッチャーの画面に、`[UI] desktop: ... (理由)` と出る。**ユーザーのデスクトップで実行するとき (`desktop=visible` のプロジェクト、`--visible`) は、実行の前に、ユーザーに、「UI テストを、あなたのデスクトップで実行します。実行中 (数分) は、マウスとキーボードに触らないでください」と伝える** (フォーカスが奪われることがある)。**ウォッチャーが古い (この機能より前の版) と、flag の中身と `uitest.settings` が無視され、別のデスクトップで動く** → `~/src/copy-host-tools.sh` で再配置して、ウォッチャーを再起動する。
- **WPF のメニュー (実機で確認、2026-10-26):** WPF のメニューのポップアップは、**別のデスクトップでは、開かない** (`Expand()` も、状態が `Collapsed` のまま。ユーザーのデスクトップでは、開く)。WinForms / MFC のメニューは、別のデスクトップでも開く。**そのため、WPF の UI テストのプロジェクトには、`uitest.settings` に `desktop=visible` が書かれる** (上)。**WPF のプロジェクトの XAML に、メニュー (`Menu` / `MenuItem` / `ContextMenu`) があると、`build_once.sh` / `build_test_once.sh` (と、`uitest_once.sh`) の出力の最後に、`NOTE:` が出る** (`scripts/wpf_menu_note.sh`。1 行目と終了コードは、変わらない。メニューがなければ、出ない。直近の UI テストが、ユーザーのデスクトップ (`desktop: Default`) なら、出ない)。`desktop=visible` の `uitest.settings` が**ない**とき: 書くよう促す 1 行。**ある**とき: 設定に従い、ユーザーのデスクトップで実行される旨の 1 行 (ユーザーに、実行中は触らないよう伝える)。**直近の UI テストが、別のデスクトップで動いた記録があれば、2 行目:** ウォッチャーが古い (再配置して、再起動)、または `--separate` / `--invisible` を指定した。メニューを含むテストは、`--visible` で実行する。別のデスクトップでは、ボタン・単体テスト (規則と Presenter / ViewModel) で、確かめる。
- ウォッチャーが古い (UI テスト未対応) と、`WATCHER_NOT_RUNNING`。`~/src/copy-host-tools.sh` で再配置して、ウォッチャーを起動し直す。

## UI テストが多いとき (`TEST_TIMEOUT`)
- ウォッチャーの、UI テストの制限は、**テストプロジェクト 1 つあたり、既定 600 秒** (`uitest_once.sh` に渡す秒数 (既定 900) とは、別)。UI テストが多い (ダイアログ・ListView・グリッドなどの調査) と、`TEST_TIMEOUT` (`=== ...: TIMEOUT after 600s (killed) ===`) で、プロセスごと強制終了され、結果ファイル (trx) は、残らない (**`ui-trace.txt` は、1 行ずつ追記されるので、残る。最後の数行で、どのテストの、どの操作で、止まったかが、分かる**)。
- **対処:** (0) **ウォッチャーの再起動は、要らない:** `uitest_once.sh --ui-timeout 1800` (1 回だけ)、または、`uitest.settings` の `timeout=1800` (プロジェクトごとの既定)。**延ばすのは、1 回だけ。2 回続いて `TEST_TIMEOUT` なら、延長せずに、停止して報告する** (固まっている可能性が高い。`SKILL.md` の「止めどき」)。(1) 環境変数で、ウォッチャーの既定を変えるなら、ユーザーに、ウォッチャーを、環境変数 `WATCH_UI_TIMEOUT_SEC` を設定して、起動し直してもらう (`set WATCH_UI_TIMEOUT_SEC=1800` → `run_watcher.cmd ...`)。起動画面の `UI test` の行に、`timeout 1800s` と出る。(2) 1 つのテストに、操作を詰め込まず、**分割する** (特に、項目が多い ListView の `FindAllDescendants` の繰り返しは、遅い)。(3) 調査のログは、**1 行ごとに、すぐ書く** (外から強制終了されても、それまでの結果が、残る)。

## 動いたことを、確かめる (トレースと、目で見るモード)
- `uitest_once.sh` は、最後に、**操作の記録 (`.claude-logs/ui-screenshots/ui-trace.txt`)** から、テストごとの結果の行 (`=== テスト名: Passed` など) を出す。**UI テストが、実際に、起動して、操作したことの確認**に使う (`PASSED` と出ても、テストが 0 件でないこと、狙いのテストが動いたことを、行で確かめる)。記録は、`find: <AutomationId>` (探した要素)、`launched: <exe>`、`=== <テスト名>: start (desktop: ..., slowmo: ... ms)` などで、全文は、Read で読める。
- **ユーザーが「目で確かめたい」と言うとき:** `uitest_once.sh <dir> [秒] --visible --slowmo 800` で、実行する (ウォッチャーの起動し直しは、要らない。待ちは、`--slowmo 1500` などで変える)。ウィンドウが、画面に出て、入力や、ボタンが、順番に動くのが見える。**実行中、ユーザーは、PC を、快適には使えない** (マウスやキーボードの入力が、フォーカスを持つテスト対象のアプリに入ることがある)。`desktop=visible` のプロジェクト (WPF) は、`--slowmo` を付けなければ、待ちなしで、ユーザーのデスクトップで動く。(ウォッチャーを `run_watcher_visible.cmd` で起動する従来の方法も、使える。`WATCH_UI_DESKTOP=default`、`WATCH_UI_SLOWMO_MS=800` が、設定される。1 回ごとの `--separate` は、これより優先される。)
- すでに作ってある UI テストのプロジェクトで、この機能 (トレース、スローモーション) を使うには、`python3 -I <Skill群>/new-solution/scripts/add_ui_tests.py "$SLN_DIR" --refresh-support-files` で、ツールが持つ 4 つのファイル (`UiTestBase.cs` など) を、最新にする (テストの本体 `MainWindowUiTests.cs` は、触らない)。

## 失敗したら
1. 最後に出る **スクリーンショット (`.claude-logs/ui-screenshots/*.png`) を、Read ツールで画像として開き、画面に何が写っているかを確かめる** (入力欄の値、表示、ダイアログ、アプリが落ちていないか)。例外のメッセージだけでは、分からないことがある。
2. 原因を、次から切り分ける。

| 失敗の様子 | 疑うこと |
|---|---|
| `AutomationId 'xxx' の要素が、見つからない` | AutomationId の付け忘れ・綴り (WPF: `AutomationProperties.AutomationId`。MFC: コントロールの ID の数値。`IDC_STATIC` は ID で探せない)。`wpf-check` の UI002 |
| 表示が、変わらない | バインディングの誤り (`wpf-check`)、待ちが足りない (`WaitFor`) |
| メインウィンドウが、15 秒以内に出ない | exe が古い (先にビルド)、起動時の例外 (スクリーンショットに、ダイアログが写る) |
| `exe が、見つからない` | ビルドの出力の場所が、標準と違う (`AppLocator.cs` を調整) |
| 画像が、真っ黒 / 白い | 別のデスクトップの描画の問題。ウォッチャーが古い可能性 |

3. **アプリの不具合なら、アプリを直して**、単体テスト (`build_test_once.sh`) が通ることを確かめてから、`uitest_once.sh` からやり直す (`/ui-test-first` のループでは、同じ `--filter` で、`uitest_once.sh` を実行する)。**テストの書き方の誤りなら、テストを直す。** どちらか迷うときは、スクリーンショットで、画面の実際の状態を見て、判断する。
4. **UI テストを通すために、アサーションを弱めたり、テストを消したりしない。**
5. UI テストの修正の繰り返しは、**スクリプトの実行の合計で、5 回まで、同じ失敗は 3 回まで** (`SKILL.md` の「止めどき」。単体テストの回数とは、別に数える)。それでも通らなければ、スクリーンショットと原因の仮説を、報告して止まる。

## UI テストを書く・足すとき
- **UI テストのプロジェクトがなければ、ユーザーに、足してよいかを確認する** (`.slnx` / `.sln` が変わる)。足し方: `python3 -I <Skill群>/new-solution/scripts/add_ui_tests.py "$SLN_DIR" --dry-run` (何を作るかを見せる) → 了承 → `--dry-run` なしで実行。(新しいソリューションなら `/new-solution --ui-tests flaui`。)
- **何を書くか:** 仕様の**主要な操作の流れ** (起動して開く、入力して表示が変わる、ボタンで状態が変わる、ダイアログが開く・閉じる)。**画面あたり数件**。見た目 (レイアウト・色)、細かい計算 (単体テストで確かめる)、独自描画のコントロールは、対象にしない。
- **要素は AutomationId で探す** (`Find("NameTextBox")`)。**操作は UIA のパターン** (`Find("Id").AsTextBox().Text = "..."` (Value)、`.AsButton().Invoke()` (Invoke))。**マウス・キーボードの入力 (`Click()`、`Keyboard.Type`) は使わない** (別のデスクトップで動かず、ユーザーの作業と干渉する)。**待ちは `WaitFor(() => 条件)`** (固定の `Thread.Sleep` を使わない)。UIA3 を使う (UIA2 は、別のデスクトップで `Invoke` が失敗する)。
- 操作したいコントロールに AutomationId がなければ、**XAML に付ける** (ユーザーの了承を得てから)。名前は、役割が分かるもの。同じ画面の操作が増えたら、Page Object にまとめる。
- 名前: `対象_条件_期待`。既存のファイルの文字コード・改行に合わせる (新規は UTF-8 BOM 付き、CRLF)。

## ダイアログ・メニュー・コンボなどの UI テスト (`UiDialogs`)
- **生成される `UiDialogs.cs` (と、`UiTestBase.OpenModal` / `WaitWindow`) を使う。** WinForms / WPF / MFC で、実機で確かめた方法が、要素の `FrameworkId` と、ウィンドウハンドルの有無で、**自動で切り替わる** (`Invoke` / `Select` を、自分で直接呼ばない)。既存のプロジェクトへは、`add_ui_tests.py <フォルダ> --refresh-support-files` で、足せる。
- **何を、どこで、確かめるか:** 画面の連動の規則 (チェックで入力欄が有効になる、ラジオで項目が変わる、不正な入力でエラーが出る、など) は、**純粋な関数の単体テスト** (表で網羅)。UI テストは、**ダイアログごとに、煙テスト 1 件** (開く → 規則の結果が、実画面に反映されている → OK / キャンセルの結果が、メインに返る)。
- **`--present` (プレゼン) の赤い枠は、`Find` / `OpenModal` に加えて、`UiDialogs` の操作 (`Click`・`PressDialogButton`・`AnswerMessageBox`・`PickFile`・`SelectComboItem` など。ダイアログの中も) でも出る** (`UiTestBase` が `UiDialogs.OnTarget` に `Highlight` を設定する。同じ要素を、0.8 秒以内に続けて囲むときは、2 回目を省く)。
- **ダイアログ・サブウィンドウの中の部品は、`Find(window, "Id")` で探す** (`UiTestBase`。`OpenModal` / `WaitWindow` が返した window を渡す。`Find("Id")` は、メインウィンドウの中だけ)。同じ探し直し (5 秒)・操作の記録・プレゼンの赤い枠が、働く。
- **Model (リポジトリなど) の Fake / 本物は、`APP_MODEL` で切り替える。** `UiTestBase` が、起動の前に、環境変数 `APP_MODEL` (`fake` / `real`) を設定する (値: `UITEST_MODEL` > `uitest.settings` の `model=` > `fake`)。アプリの、組み立てる場所が読む (Release では読まない)。手順は、`ui-test-first` の「Model の差し替え」「結合 (Fake → 本物)」。
- 道具の一覧: `Click` / `WaitModal` / `WaitModalClosed` (ダイアログを開く、MessageBox・ファイルダイアログも同じ)、`WaitWindow` (モードレス)、`ExpandMenu` / `CollapseMenu` / `FindMenuItem` / `MenuCommand`、`SelectComboItem` (WinForms / MFC は、項目の一覧を渡す)、`SelectListItem`、`SetSlider`、`SetScrollBar`、`SelectTab`、`AnswerMessageBox`、`PickFile`、`DumpTree` (診断。深さと数に上限)。
- **第 2 弾 (ListView・スピン・ツリー・日付・タブ) の道具:** `ListItems` (ListItem と DataItem の両方) / `ClickColumnHeader` (列ヘッダー。WinForms / MFC は `SysHeader32` へ PostMessage、WPF は Invoke) / `SetNumeric` (スピン・NumericUpDown・TextBox) / `ToggleTreeNode` (ツリーのチェック) / `OpenDropDown` + `FindCalendar` (日付ピッカーのカレンダー) / `PostKey` + `Vk.*` + `FocusAndKeys` (キー。別のデスクトップでも動く PostMessage) / `SelectTab` (**WinForms / MFC は、タブの名前を、並び順で、全部渡す**。UIA の TabItem は信用できない) / `ForceCloseDialog` (`PressDialogButton` が失敗したときに自動で呼ぶ) / `GetAppWindow` (`UiTestBase` が使う。入力インジケーターの小窓を除く)。**`SendMessage` は、すべて 5 秒のタイムアウトつき** (固まったアプリに、同期の SendMessage をすると、テストごと、ウォッチャーの制限時間で殺される)。
- **注意 (実機で確認):** (1) ウィンドウを持つボタンは `BM_CLICK` の `PostMessage` (UIA の `Invoke` は、`ShowDialog` / `DoModal` の中で戻らず、WinForms / MFC では、以後の UIA が止まる)。(2) WinForms のメニュー項目は、アプリ側で、ダイアログを開く処理を、`BeginInvoke` で遅らせる。MFC のメニューは、`MenuCommand` (`WM_COMMAND`)。(3) **WPF のメニューは、別のデスクトップでは、開かない** (WPF の UI テストは、既定で、ユーザーのデスクトップ。ビルドの出力の `NOTE:` を参照)。(4) キーボード・マウスの入力は、別のデスクトップでは、拒否される。(5) MFC のスクロールバーは、UIA の値が 0〜100 に正規化される (位置は、`SetScrollBar` / `ScrollBarValue` が、`SBM_GETPOS` で扱う)。
- **コントロールに、`AccessibleName` / `AutomationProperties.Name` を付ける** (WinForms は、直前の `Label` の文字が、UIA の名前になる)。


## コントロール別の、実機の結果の表 (WinForms / WPF / MFC。`poc/dialog-flaui/README.md` に、根拠)
| 対象 | WinForms | WPF | MFC (Win32) |
|---|---|---|---|
| タブ | UIA の TabItem は信用できない (選択中が消える / 最後が出ない / 1 つ右を選ぶ) → `TCM_GETCURSEL` + 矢印キー | UIA の `SelectTabItem` | WinForms と同じ (Win32) |
| ListView の表示形式 | 5 形式とも、同じ ListItem。**タイルは `CheckBoxes` と両立しない (例外)** | 形式の切り替えがない (GridView + ItemsPanel / ItemTemplate で作る)。GridView は DataGrid として出て、項目は DataItem | 5 形式とも、同じ。タイルは、共通コントロール v6 のマニフェストが要る |
| ListView の項目 | 60 件すべて出る。`Invoke` / `Toggle` / `SelectionItem` / `ScrollItem` | **仮想化**で一部だけ (Scroll で出す)。**名前はデータの型名 → `ToString()` を実装**。項目自身に Toggle はなく、中の CheckBox | WinForms と同じ。60 件すべて |
| 列ヘッダーの並べ替え | `SysHeader32` へ `WM_LBUTTONDOWN/UP` を PostMessage (UIA の Invoke は効かない) | `HeaderItem` の Invoke | WinForms と同じ |
| チェックの通知 | `ItemChecked` | **`Checked` / `Unchecked` で受ける** (UIA の Toggle は `Click` を起こさない) | `LVN_ITEMCHANGED` (リスト) |
| チェック付きツリー | `Toggle` | ノードの中の CheckBox の `Toggle` | **UIA の Toggle は ToggleState が変わらない → 項目を選んで `VK_SPACE` (`TVN_KEYDOWN`)** |
| スピン / 数値 | NumericUpDown: `RangeValue` が効く。編集欄は、フォーカスが外れるまで確定しない。範囲外は自身で丸める | TextBox + RepeatButton (範囲の丸めは、規則が行う) | **上下ボタンの Invoke は効かず、RangeValue もない** → 編集欄の `SetValue`、`UDM_SETPOS32` |
| 日付ピッカー | `Value` / `ExpandCollapse` あり。フォーカス後に、矢印キーと数字 (PostMessage)。チェック付きは、`Right` で日付の欄へ | `DatePicker` 自身への `SetValue` が効く (内側の `PART_TextBox` は不可) | **Pane (Legacy だけ)**。フォーカス後に矢印キー |
| ドロップダウンのカレンダー | UIA の Invoke / DoDefaultAction は効かない → `PageDown` / 矢印 / `Enter` (PostMessage) | 日のセルは `Button` (`CalendarDayButton`、名前は `2026年1月15日`)。Invoke / SelectionItem。**別のデスクトップでも、ツリーに出る** | `VK_F4` で開き、WinForms と同じキー |
| MessageBox の OK | OK だけの MessageBox の OK は **id 2** (OK・キャンセルは 1 / 2) | 同じ | 同じ |
| TaskDialog | ボタンは `CommandButton_6` など。UIA の Invoke は例外 → ウィンドウハンドルへ `BM_CLICK` | (未確認) | (未確認) |
| ToolStrip / StatusStrip | `AutomationId` が空 → `ControlType` と表示名で探す | - | - |
| 主ウィンドウ | `App.GetMainWindow` が、まれに入力インジケーターの小窓を返す (MFC で確認) → `GetAppWindow` | 同じ | 同じ |

## 注意
- 実行の前後に、ウォッチャーが、テストが残したアプリのプロセスを終了する (別のデスクトップのときは、ジョブオブジェクトで、すべて終了する)。
- 別のデスクトップでは、**WPF の描画を、UI テストの間だけ、ソフトウェアレンダリングにする** (レジストリ `HKCU\Software\Microsoft\Avalon.Graphics\DisableHWAcceleration`。元の値を記録して、終了後に復元する)。
- MFC のダイアログ・ウィンドウは、標準のコントロール (ボタン、エディット、リスト、コンボ) は操作できる。オーナー描画・独自描画は取れない。C++ のソリューションに UI テスト (.NET) を足すと、C++ と .NET の混在になる (`docs/DESIGN.md` 4.24)。WinForms は、まだ対象にしていない。
