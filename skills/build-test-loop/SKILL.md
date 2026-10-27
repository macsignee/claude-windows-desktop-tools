---
name: build-test-loop
description: C++ (GoogleTest) と .NET / WPF (MSTest) のソリューションで、ビルドとテストの実行を Windows ホスト側のウォッチャー経由で行い、ビルドエラーやテスト失敗を自動修正して、全テストが通るまで繰り返す手順。C++ のみ、.NET のみ、混在のどれでも同じ手順で使う (テストの種類は、ウォッチャーが判定し、結果は共通の形式で返る)。xxx と xxxTest があるソリューションで、「テストまで通して」「テストが通るまで直して」といった依頼で使う。ビルドだけでよい場合は auto-build を使う。
---

# ビルド + テスト 自動修正ループ (C++ GoogleTest / .NET MSTest)

サンドボックスから msbuild やテスト exe を直接実行できないため、ホスト側の `run_watcher.cmd`
(watch_and_build.ps1) が `trigger_test.flag` を監視し、ビルド → テストの実行まで行う。
Claude はフラグを置いて結果を読むだけ。

| 種類 | テストの形 | ウォッチャーの実行 |
|---|---|---|
| C++ | `xxxTest.exe` (GoogleTest) | exe を実行 (`--gtest_output=xml` で、機械可読な結果も残す) |
| .NET / WPF | `xxx.Tests` などの MSTest プロジェクト | `dotnet test --no-build` (trx を残す) |

混在のソリューション (C++ の DLL + WPF のアプリなど) では、両方が実行され、**失敗の要約は、同じ形で 1 つにまとまる。** どちらのテストが落ちたかは、テスト名とファイルで分かる。

## 前提
- ユーザーが対象ソリューションのフォルダで `run_watcher.cmd` を起動済みであること。
- ソリューションフォルダ (.sln または .slnx があるフォルダ) を `$SLN` とする。Claude はこのフォルダをルートとして動く。
- xxxTest は同じソリューションにあり、xxx をプロジェクト参照している。ソリューションをビルドすれば
  xxx → xxxTest の順は MSBuild が自動で解決する (順序を自分で指定しない)。
- .NET のテストは、`Microsoft.NET.Test.Sdk` + MSTest (v3 以降。VSTest モード) のプロジェクト。`dotnet test` で、trx が出ること。
- ログ中のパスは `$SLN` からの相対パス (例: `MyAppTest/TestFoo.cpp(49)`)。そのまま開ける。

## 実行 (1回分)

必ず同梱スクリプトを使う。自分で flag を作ったり待機ループを書いたりしない。
**スクリプトは、この Skill のフォルダ (`~/.claude/skills/build-test-loop/scripts/`) のものだけを使う。** 同じ名前の古いコピー (ホーム直下の `cpp-build-test-loop/` など) を、探して使わない。古い版は、エラーの要約や `.claude-logs/*_summary.json` を出さず、`.claude-logs/test-results/` も扱えない。
失敗の要約 (`[ran N: passed X / failed Y / skipped Z]` の行と、`.claude-logs/test_summary.json`) が出ないときは、まず、古い版を実行していないか (スクリプトのパス) を確認する。

```bash
bash <このSkillのフォルダ>/scripts/build_test_once.sh "$SLN" 300
```

**重要 (トークン節約と打ち切り防止):** Bash ツールの既定タイムアウトは120秒で、300秒待つスクリプトが
途中で打ち切られる。次のどちらかで呼ぶ。
- `run_in_background: true` で実行し、完了通知を待つ (推奨。待機中は何も消費しない)。
- フォアグラウンドなら Bash の `timeout` を 320000 以上にする。

**待機中は何もしない (厳守):** 実行を開始したら、**完了通知 (またはコマンドの終了) が来るまで、
ファイルを読まない・ディレクトリを一覧しない・追加のコマンドを実行しない。**
`build.log` / `test.log` / `build_result.txt` / `test_result.txt` など、ホスト側のファイルを、待機中に確認してはならない。
- これらは前回の実行の古い内容が残っていることがあり、見ても「成功」「実行中」を正しく判断できない。
- 結果は、スクリプトの出力 (1行目と終了コード) だけが正で、判断はそれだけで行う。
- 完了通知が来る前に「ビルドは成功した」「テスト実行中」などと、状況を推測して述べない。
- 実行中に、同じスクリプトを再度起動しない (ウォッチャーは1つずつ処理するため、結果が混ざって古い結果を拾う)。

スクリプトは古い結果ファイルを消し、`trigger_test.flag` を作り、`test_result.txt` の出現を待つ。
1行目が結果、終了コードも対応する。

| 1行目 | rc | 意味 | 次の行動 |
|---|---|---|---|
| `PASSED` | 0 | ビルド成功・全テスト成功。**2 行目に、要約 (`build: SUCCESS / tests: 6 passed (DataLayer.Tests 1, LogicLayer.Tests 5)`。スキップがあれば `6 passed, 1 skipped`)** | ループ終了。1〜2行で報告 (件数は、2 行目を、そのまま使う。ログを、別に読まなくてよい) |
| `BUILD_FAILED` | 6 | ビルドエラー | 2行目以降のエラー要約を読んで修正し、再実行 (読み方は下記) |
| `FAILED` | 1 | テスト失敗 | テスト失敗の要約 (読み方は下記) を読み、下記の方針で修正し、再実行 |
| `TEST_TIMEOUT` | 7 | テストが制限時間内に終わらない | 下記「`TEST_TIMEOUT` の扱い」に従う。テストの待ち時間を延ばして誤魔化さない |
| `ENV_ERROR` | 4 | 環境エラー (VS / .NET SDK / テストが見つからない、1 件も実行されない等) | **ソースもテストも直さず**、内容を報告して停止 |
| `WATCHER_NOT_RUNNING` | 3 | フラグが回収されない | 停止し、`run_watcher.cmd` の起動をユーザーに依頼 |
| `TIMEOUT` | 5 | 完了マーカーが出ない | 停止して報告 (長いビルドなら timeout を延ばして1回だけ再試行可) |

## エラー出力の読み方 (要約形式)
`BUILD_FAILED` の2行目以降は、`build_error.log` を集約した要約。
```
7 errors (4 unique) in 4 files; compile 5 / link 2
[1] C2065 'cnt': undeclared identifier  x4
    MyApp/Foo.cpp(49,5)  MyApp/Foo.cpp(50,9)  MyApp/Bar.cpp(12,3)  (+1 more)
```
- 見出し: 総数 / 種類数 / ファイル数 / コンパイルとリンクの内訳。
- `[n]` は同じ (コード, メッセージ) をまとめたもの。`xN` は件数、下の行は代表の場所 (最大3つ。`(+N more)` は省略分)。
- **最初に出たエラー順。上の `[n]` ほど原因の可能性が高い。** 下のほうは連鎖エラーのことが多いので、まず `[1]` から直し、再ビルドで確認する。
- `LNK` は定義・エクスポート・ライブラリ指定の問題。ソースの宣言だけ直しても消えない。
- `other:` は解釈できなかった行 (そのまま)。
- 同じ内容は `.claude-logs/build_summary.json` にもある。ログの再読ではなく、必要なら、これを読む。
- 要約が出ない (生ログのまま) 場合は、`python3` がないか、エラー行を解釈できなかった。生ログのとおりに読む。

## UI テスト (FlaUI): Green の「あとに」、追加で実行する

**流れ:** テスト先行 (Red) → ビルド → テスト (Green、`build_test_once.sh`) が `PASSED` になった**あとに、追加で**、UI テストを実行する。
**UI テストファースト (UI テストを先に書いて、Red にする) は、しない。** UI テストは、画面と、ViewModel・ロジックが、つながっているか、主要な操作の流れが通るか、の**最後の確認**で、`PASSED` のあとの、追加の段階。

### いつ実行するか
- **`build_test_once.sh` が `PASSED` になったら、UI テストのプロジェクトがあるかを、確かめる** (`ls "$SLN"` で、名前が `UITests` / `UiTests` で終わる、または FlaUI を参照するプロジェクト。`CLAUDE.md` に「UI テスト (FlaUI)」の節があれば、ある)。**あれば、続けて、実行する。なければ、何もしない。**
- UI テストは、**通常のテスト (`build_test_once.sh`) には、含まれない** (遅く、アプリを起動するため)。
- 実行するのは、**ソースを変えた (または、ユーザーが頼んだ) とき**。修正の途中の、毎回は、実行しない (Green になってから、1 回)。

```bash
bash <このSkillのフォルダ>/scripts/uitest_once.sh "$SLN" 900
```
使い方、出力の形、`FAILED` / `ENV_ERROR` / `TEST_TIMEOUT` の読み方は、`build_test_once.sh` と同じ。`run_in_background: true` で実行し、完了通知を待つ。

- **別のデスクトップで実行される** (ウォッチャーの既定。`WATCH_UI_DESKTOP=default` で、ユーザーのデスクトップ。下の「目で確かめる」)。ウィンドウは、ユーザーの画面に出ず、操作は UIA のパターンなので、**ユーザーに「触らないで」と頼む必要は、ない**。ユーザーのデスクトップで実行する設定のときだけ、フォーカスが奪われることがある、と伝える。
- **WPF のメニュー (実機で確認、2026-10-26):** WPF のメニューのポップアップは、**別のデスクトップ (ウォッチャーの既定) では、開かない** (`Expand()` も、状態が `Collapsed` のまま。ユーザーのデスクトップでは、開く)。WinForms / MFC のメニューは、別のデスクトップでも開く (WinForms は確認済み)。**WPF のプロジェクトの XAML に、メニュー (`Menu` / `MenuItem` / `ContextMenu`) があると、`build_once.sh` / `build_test_once.sh` (と、`uitest_once.sh`) の出力の最後に、`NOTE:` の 2 行が出る** (`scripts/wpf_menu_note.sh`。1 行目と終了コードは、変わらない。メニューがなければ、出ない。直近の UI テストが、ユーザーのデスクトップ (`desktop: Default`) なら、出ない)。**`NOTE:` が出たら、ユーザーに伝える:** メニューの開閉を含む UI テストは、ウォッチャーを `run_watcher_visible.cmd` で起動して、実行する。別のデスクトップでは、ボタン・単体テスト (規則と Presenter / ViewModel) で、確かめる。
- ウォッチャーが古い (UI テスト未対応) と、`WATCHER_NOT_RUNNING`。`~/src/copy-host-tools.sh` で再配置して、ウォッチャーを起動し直す。

### UI テストが多いとき (`TEST_TIMEOUT`)
- ウォッチャーの、UI テストの制限は、**テストプロジェクト 1 つあたり、既定 600 秒** (`uitest_once.sh` に渡す秒数 (既定 900) とは、別)。UI テストが多い (ダイアログ・ListView・グリッドなどの調査) と、`TEST_TIMEOUT` (`=== ...: TIMEOUT after 600s (killed) ===`) で、プロセスごと強制終了され、結果ファイル (trx) も、`ui-trace.txt` も、残らない。
- **対処:** (1) ユーザーに、ウォッチャーを、環境変数 `WATCH_UI_TIMEOUT_SEC` を設定して、起動し直してもらう (`set WATCH_UI_TIMEOUT_SEC=1800` → `run_watcher.cmd ...`)。起動画面の `UI test` の行に、`timeout 1800s` と出る。(2) 1 つのテストに、操作を詰め込まず、**分割する** (特に、項目が多い ListView の `FindAllDescendants` の繰り返しは、遅い)。(3) 調査のログは、**1 行ごとに、すぐ書く** (外から強制終了されても、それまでの結果が、残る)。

### 動いたことを、確かめる (トレースと、目で見るモード)
- `uitest_once.sh` は、最後に、**操作の記録 (`.claude-logs/ui-screenshots/ui-trace.txt`)** から、テストごとの結果の行 (`=== テスト名: Passed` など) を出す。**UI テストが、実際に、起動して、操作したことの確認**に使う (`PASSED` と出ても、テストが 0 件でないこと、狙いのテストが動いたことを、行で確かめる)。記録は、`find: <AutomationId>` (探した要素)、`launched: <exe>`、`=== <テスト名>: start (desktop: ..., slowmo: ... ms)` などで、全文は、Read で読める。
- **ユーザーが「目で確かめたい」と言うとき:** ユーザーのデスクトップで、操作の間に待ちを入れて、実行する。**ユーザーに、ウォッチャーを `run_watcher_visible.cmd` で、起動し直してもらう** (`WATCH_UI_DESKTOP=default`、`WATCH_UI_SLOWMO_MS=800` が、設定される。待ちは、`set WATCH_UI_SLOWMO_MS=1500` で変えられる)。ウィンドウが、画面に出て、入力や、ボタンが、順番に動くのが見える。**実行中、ユーザーは、PC を、快適には使えない** (マウスやキーボードの入力が、フォーカスを持つテスト対象のアプリに入ることがある)。確かめ終わったら、通常の `run_watcher.cmd` (別のデスクトップ) に戻す。
- すでに作ってある UI テストのプロジェクトで、この機能 (トレース、スローモーション) を使うには、`python3 -I ~/.claude/skills/new-solution/scripts/add_ui_tests.py "$SLN" --refresh-support-files` で、ツールが持つ 4 つのファイル (`UiTestBase.cs` など) を、最新にする (テストの本体 `MainWindowUiTests.cs` は、触らない)。

### 失敗したら
1. 最後に出る **スクリーンショット (`.claude-logs/ui-screenshots/*.png`) を、Read ツールで画像として開き、画面に何が写っているかを確かめる** (入力欄の値、表示、ダイアログ、アプリが落ちていないか)。例外のメッセージだけでは、分からないことがある。
2. 原因を、次から切り分ける。

| 失敗の様子 | 疑うこと |
|---|---|
| `AutomationId 'xxx' の要素が、見つからない` | AutomationId の付け忘れ・綴り (WPF: `AutomationProperties.AutomationId`。MFC: コントロールの ID の数値。`IDC_STATIC` は ID で探せない)。`wpf-check` の UI002 |
| 表示が、変わらない | バインディングの誤り (`wpf-check`)、待ちが足りない (`WaitFor`) |
| メインウィンドウが、15 秒以内に出ない | exe が古い (先にビルド)、起動時の例外 (スクリーンショットに、ダイアログが写る) |
| `exe が、見つからない` | ビルドの出力の場所が、標準と違う (`AppLocator.cs` を調整) |
| 画像が、真っ黒 / 白い | 別のデスクトップの描画の問題。ウォッチャーが古い可能性 |

3. **アプリの不具合なら、アプリを直して**、`build_test_once.sh` (Green) からやり直す。**テストの書き方の誤りなら、テストを直す。** どちらか迷うときは、スクリーンショットで、画面の実際の状態を見て、判断する。
4. **UI テストを通すために、アサーションを弱めたり、テストを消したりしない。**
5. UI テストの修正の繰り返しは、**3 回まで** (「ループのルール」とは、別に数える)。それでも通らなければ、スクリーンショットと原因の仮説を、報告して止まる。

### UI テストを書く・足すとき
- **UI テストのプロジェクトがなければ、ユーザーに、足してよいかを確認する** (`.slnx` / `.sln` が変わる)。足し方: `python3 -I ~/.claude/skills/new-solution/scripts/add_ui_tests.py "$SLN" --dry-run` (何を作るかを見せる) → 了承 → `--dry-run` なしで実行。(新しいソリューションなら `/new-solution --ui-tests flaui`。)
- **何を書くか:** 仕様の**主要な操作の流れ** (起動して開く、入力して表示が変わる、ボタンで状態が変わる、ダイアログが開く・閉じる)。**画面あたり数件**。見た目 (レイアウト・色)、細かい計算 (単体テストで確かめる)、独自描画のコントロールは、対象にしない。
- **要素は AutomationId で探す** (`Find("NameTextBox")`)。**操作は UIA のパターン** (`Find("Id").AsTextBox().Text = "..."` (Value)、`.AsButton().Invoke()` (Invoke))。**マウス・キーボードの入力 (`Click()`、`Keyboard.Type`) は使わない** (別のデスクトップで動かず、ユーザーの作業と干渉する)。**待ちは `WaitFor(() => 条件)`** (固定の `Thread.Sleep` を使わない)。UIA3 を使う (UIA2 は、別のデスクトップで `Invoke` が失敗する)。
- 操作したいコントロールに AutomationId がなければ、**XAML に付ける** (ユーザーの了承を得てから)。名前は、役割が分かるもの。同じ画面の操作が増えたら、Page Object にまとめる。
- 名前: `対象_条件_期待`。既存のファイルの文字コード・改行に合わせる (新規は UTF-8 BOM 付き、CRLF)。

### ダイアログ・メニュー・コンボなどの UI テスト (`UiDialogs`)
- **生成される `UiDialogs.cs` (と、`UiTestBase.OpenModal` / `WaitWindow`) を使う。** WinForms / WPF / MFC で、実機で確かめた方法が、要素の `FrameworkId` と、ウィンドウハンドルの有無で、**自動で切り替わる** (`Invoke` / `Select` を、自分で直接呼ばない)。既存のプロジェクトへは、`add_ui_tests.py <フォルダ> --refresh-support-files` で、足せる。
- **何を、どこで、確かめるか:** 画面の連動の規則 (チェックで入力欄が有効になる、ラジオで項目が変わる、不正な入力でエラーが出る、など) は、**純粋な関数の単体テスト** (表で網羅)。UI テストは、**ダイアログごとに、煙テスト 1 件** (開く → 規則の結果が、実画面に反映されている → OK / キャンセルの結果が、メインに返る)。
- 道具の一覧: `Click` / `WaitModal` / `WaitModalClosed` (ダイアログを開く、MessageBox・ファイルダイアログも同じ)、`WaitWindow` (モードレス)、`ExpandMenu` / `CollapseMenu` / `FindMenuItem` / `MenuCommand`、`SelectComboItem` (WinForms / MFC は、項目の一覧を渡す)、`SelectListItem`、`SetSlider`、`SetScrollBar`、`SelectTab`、`AnswerMessageBox`、`PickFile`、`DumpTree` (診断。深さと数に上限)。
- **注意 (実機で確認):** (1) ウィンドウを持つボタンは `BM_CLICK` の `PostMessage` (UIA の `Invoke` は、`ShowDialog` / `DoModal` の中で戻らず、WinForms / MFC では、以後の UIA が止まる)。(2) WinForms のメニュー項目は、アプリ側で、ダイアログを開く処理を、`BeginInvoke` で遅らせる。MFC のメニューは、`MenuCommand` (`WM_COMMAND`)。(3) **WPF のメニューは、別のデスクトップでは、開かない** (ウォッチャーを `run_watcher_visible.cmd` で起動する。ビルドの出力の `NOTE:` を参照)。(4) キーボード・マウスの入力は、別のデスクトップでは、拒否される。(5) MFC のスクロールバーは、UIA の値が 0〜100 に正規化される (位置は、`SetScrollBar` / `ScrollBarValue` が、`SBM_GETPOS` で扱う)。
- **コントロールに、`AccessibleName` / `AutomationProperties.Name` を付ける** (WinForms は、直前の `Label` の文字が、UIA の名前になる)。

### 注意
- 実行の前後に、ウォッチャーが、テストが残したアプリのプロセスを終了する (別のデスクトップのときは、ジョブオブジェクトで、すべて終了する)。
- 別のデスクトップでは、**WPF の描画を、UI テストの間だけ、ソフトウェアレンダリングにする** (レジストリ `HKCU\Software\Microsoft\Avalon.Graphics\DisableHWAcceleration`。元の値を記録して、終了後に復元する)。
- MFC のダイアログ・ウィンドウは、標準のコントロール (ボタン、エディット、リスト、コンボ) は操作できる。オーナー描画・独自描画は取れない。C++ のソリューションに UI テスト (.NET) を足すと、C++ と .NET の混在になる (`docs/DESIGN.md` 4.24)。WinForms は、まだ対象にしていない。

## テスト失敗の要約の読み方
`FAILED` の2行目以降は、テストの結果を集約した要約 (GoogleTest も MSTest も、同じ形)。
```
6 failed tests in 4 suites: TestPointD 2, TestLineD 1, WpfApp.Tests.CalcTests 2, ...  [ran 10: passed 2 / failed 6 / skipped 2]
[1] x2  Expected equality of these values: | 25.0 | Which is: 28
    tests: TestPointD.DistX, TestPointD.DistY
    at: App/TestGeo.cpp(49)  App/TestGeo.cpp(60)
[2] x2  Assert.AreEqual failed. Expected:<3>. Actual:<4>.
    tests: WpfApp.Tests.CalcTests.AddsTwoNumbers, WpfApp.Tests.CalcTests.SubtractsTwoNumbers
    at: WpfApp.Tests/CalcTests.cs(21)  WpfApp.Tests/CalcTests.cs(30)
```
- 見出し: 失敗数と、スイート (C++ はスイート名、.NET は、クラスの完全名) ごとの件数。`[ran N: ...]` は、実行・成功・失敗・スキップの件数。
- `[n]` は**同じメッセージの失敗をまとめたもの** (`xN` は件数)。`tests:` はテスト名 (最大5)、`at:` は失敗の場所 (最大3)。`(+N more)` は省略分。
- **同じ組の失敗は、同じ原因であることが多い。** 組の数だけ原因を探し、1つ直したら再実行して、残りを確認する。
- `Expected` / `Which is` の値は、`|` で区切って1行に並べてある。期待値と実際の値の対応は、`test_error.log` のとおり (必要なときだけ読む)。
- `other:` は解釈できなかった行 (クラッシュの報告など。そのまま)。
- 全テスト名と、テストごとの場所・メッセージは、`.claude-logs/test_summary.json` にある (共通の形式。`sources` に、テスト exe / プロジェクトごとの件数と、`framework` (`gtest` / `mstest`))。
- 元の機械可読な結果 (GoogleTest の XML、MSTest の trx) は、`.claude-logs/test-results/` にある。通常は読まない。
- 要約が出ない (従来の「Failed tests」の一覧と詳細) 場合は、`python3` がないか、失敗したテスト名を解釈できなかった (クラッシュなど)。そのまま読む。

## テスト失敗 (`FAILED`) の扱い
1. 失敗ごとに (または、組ごとに)、期待値 (`Expected`) と実際の値 (`Which is`)、ファイル・行を読む。
2. 該当テストと、テスト対象のソース (xxx 側) を、必要な範囲だけ読む。
3. **原則として、ソース (xxx) 側を直す。** テストは仕様の表明として扱う。
4. テストの期待値のほうが誤っている可能性がある場合 (仕様・他のテスト・コメントと矛盾するなど) は、
   **テストを変更する前にユーザーに確認する。** 理由 (どの仕様と矛盾するか) を添える。
5. **次のことは、ユーザーの明示的な許可なしにしない。**
   テストの削除、`DISABLED_` 化、`GTEST_SKIP()`、アサーションを弱める (`EXPECT_EQ` → `EXPECT_NE` など)、
   許容誤差を広げる、テスト側の期待値を実装の出力に合わせる。
   **MSTest では、次も同じ扱い:** `[Ignore]` の付与、`Assert.Inconclusive()` による飛ばし、`[TestCategory]` や `.runsettings` で実行から外す、
   `Assert.AreEqual` → `Assert.AreNotEqual` / `Assert.IsNotNull` への弱め、`[ExpectedException]` や `Assert.ThrowsException` の削除、タイムアウト (`[Timeout]`) の延長。
6. 複数のテストが失敗している場合は、共通の原因 (同じ関数の不具合) を先に探す。1つ直すと複数が通ることが多い。

## `TEST_TIMEOUT` の扱い
出力の `Hung test (was running when killed): Suite.Name` は、強制終了された時点で実行中だったテスト。
ただし、**制限時間 (ユーザーが `-TestTimeoutSec` で設定) が全体の実行時間より短いだけの場合も、
通常のテスト名が出る。** そのテストが壊れているとは限らない。

1. 直前にソースを変更した場合: 変更が無限ループ・デッドロック・待機のハングを作っていないかを、
   `Hung test` の対象コードと自分の変更箇所を中心に調べ、直して再実行する。
2. **直前にソースを変更していない場合、または2回続けて `TEST_TIMEOUT` になった場合は、
   ソースを触らずに停止して報告する。** 制限時間が短すぎる可能性があるため、
   ユーザーに制限時間 (`-TestTimeoutSec`、既定120秒) の確認を依頼する。
3. 制限時間の延長、テストの待ち時間の変更、テストの無効化は、ユーザーの許可なしにしない。

## ループのルール
1. ソースを修正したら `build_test_once.sh` を実行する。修正していない状態での再実行はしない。
2. **最大5回**まで。5回目も失敗なら、残りの失敗と試した修正を報告して停止する。
3. **同じテストが同じ内容 (同じ期待値・実際の値) で修正後も失敗する場合**は、2回目で止めて原因を調べる。
   ファイルが外部 (エディタの再保存など) で書き戻されている可能性も疑い、ユーザーに確認する。
4. 修正のたびに、ビルドエラーが出ていないかも見る (`BUILD_FAILED` は通常のビルドエラーとして直す)。
5. `.claude-logs/` の `build.log` / `test.log` (全文、フルパス) は、詳細が必要なときだけ読む。通常は不要。
6. 修正時はファイルの文字コード (UTF-8 BOM の有無など) と改行コードを変えない。無関係なリファクタリングはしない。

## トークン節約
- 成功時はログを読まない。報告も1〜2行。
- 失敗時の出力は、スクリプトが失敗テスト名の一覧 + 詳細を最大60行・1行400文字に制限している。
  足りないときだけ `test_error.log` を読む。
- ソースは、エラー・失敗箇所の前後だけを読む (ファイル全体を読み直さない)。
- 待機中・修正の合間に、経過の説明を書かない (どうしても必要な場合は、日本語で1行以内)。

## 完了時の確認 (変更の報告)
作業を終える前に (成功でも、停止でも)、変更したファイルを一覧して、報告に含める。ユーザーが、コミットの前に、`git diff` で、変更を確認できるようにするため。
**このセッションで、自分がファイルを編集していない場合は、実行せず、「変更なし」と報告する。**

1. 変更されたファイルの一覧を取る (読み取りだけ。ステージやコミットはしない)。
   ```bash
   git -c core.fileMode=false --no-optional-locks status --short
   ```
   - `-c core.fileMode=false` を付けるのは、WSL の git が、`/mnt/c` のファイルを実行権限つきと見て、ほぼ全ファイルを「変更あり」と表示してしまうため。
   - git のリポジトリでない場合や、コマンドが失敗した場合は、自分が編集したファイルの一覧で代える。
2. **テストファイル (`Test*.cpp`、`Test*.h`、`*Test/` 配下、.NET の `*Tests/` 配下と `*Tests.cs`) の変更があれば、報告の先頭で明示する** (ファイル名と、変更した理由)。
   ない場合は、「テストファイルの変更なし」と書く。
3. 「コミット前に、`git diff` で変更を確認してください」と、一言添える。
4. **`git commit` と `git push` は、ユーザーの明示的な指示がない限り、実行しない。**
5. プロジェクトの設定 (`.claude/settings.json`) で、テストファイルの編集や、`git commit` に、確認が出る設定になっていることがある。
   確認が出たら、何を、なぜ、行うのかを、簡潔に説明する。拒否されたら、同じ操作を、別の方法 (別のツールやコマンド) で、行わない。

## 警告の件数 (成功時)
成功 (`SUCCESS` / `PASSED`) のとき、警告があれば、1行目の次に、**1行だけ**件数が出る。警告がなければ何も出ない。**`PASSED` のときは、さらに、1行目の次 (警告の行の前) に、テストの要約の 1 行 (`build: SUCCESS / tests: N passed (プロジェクト名 件数, ...)`) が出る** (構造化された結果 (trx / XML) があるときだけ。1 行目の `PASSED` は、変わらない)。
```
warnings: 12 (5 unique): C4244 x5, C4996 x3, C4101 x2, ... (+2 more)
```
- 警告は、ビルドの成否に影響しない。**この行が出ても、ループは終了してよい。** 報告に、そのまま1行添える。
- **警告を直すのは、ユーザーに頼まれたときだけ。** 無関係な警告の修正は、リファクタリングと同じ扱い (しない)。自分が今回編集した行に由来する警告 (未使用の変数、型の縮小など) は、報告に、そう書いて、直すかを尋ねる。
- 詳細 (コード別の件数・場所) が必要なときだけ、次を実行する (読み取りだけ。`<このSkillのフォルダ>` はスクリプトと同じ場所):
  ```bash
  python3 -I <このSkillのフォルダ>/scripts/summarize_build_log.py "$SLN/.claude-logs/warnings.log" --severity warning --root "$SLN"
  ```
  同じ内容は、`.claude-logs/warnings_summary.json` にもある。
- **差分ビルドでは、再コンパイルされたファイルの警告だけが出る** (「すべての出力が最新」なら、件数も出ない)。件数が出ないことは、警告がないことを意味しない。

## 報告
- 成功: 回数と結果を1〜2行で (何を直したかを一言。警告の件数の行があれば、それも1行で)。続けて、「完了時の確認」の、変更ファイルと、テストファイルの変更の有無を、1行で。
- 失敗で停止: 最後のエラー、試した修正、停止理由。テストを変更したい場合は、その理由と案。変更したファイルも、同様に報告する。

## ホスト側の構成 (参考)
- `trigger_test.flag`: Claude が作る。ウォッチャーが検知して削除し、ビルド → テスト (GoogleTest の exe と、`dotnet test`) を行う。
- `build_result.txt`: ビルド終了時に `SUCCESS` / `FAILED`。`build_error.log`: ビルド失敗時のみ。
- `test_result.txt`: 完了マーカー (最後に書かれる)。`PASSED` / `FAILED` / `TIMEOUT` / `BUILD_FAILED` / `ENV_ERROR`。
- `test_error.log`: テスト失敗・タイムアウト・環境エラー時のみ。環境エラーは先頭が `[ENVIRONMENT ERROR - not a source code problem]`。
- `.claude-logs/`: `build.log` / `errors.log` / `warnings.log` / `test.log` (フルパスのまま)、`test-results/` (GoogleTest の XML と MSTest の trx)。
- `ENV_ERROR` には、「テストが 1 件も実行されなかった」(.NET: trx がない / `executed=0`、GoogleTest: 要約行がない) も含まれる。**ソースもテストも直さずに、報告して止まる** (`Microsoft.NET.Test.Sdk` や、テストアダプタ (MSTest) の参照の確認を、ユーザーに依頼する)。
