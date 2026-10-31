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
- **作業フォルダ (`solutions.md` があり、`.sln` / `.slnx` がないフォルダ) で起動しているとき** (複数の候補のソリューションを、比べているとき): `$SLN` は、カレントではなく、対象の候補。`SLN=$(python3 ~/.claude/skills/new-solution/scripts/new_solutions.py resolve "$PWD" [<候補名>])` で決める (終了コード 2: 候補が複数 → 一覧を示して、ユーザーに質問する。3: 対象がない)。以降の `CLAUDE.md` や `docs/` は、`$SLN` の下 (その候補のコピー)。**他の候補は、読まない・書かない。** ウォッチャーは、その候補のフォルダで、起動されている必要がある。
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
| `WATCHER_NOT_RUNNING` | 3 | フラグが 15 秒以内に回収されず、ウォッチャーが処理中の印もない | 停止し、ユーザーに、`run_watcher.cmd` の起動と、**対象のフォルダ (`$SLN`) が、ウォッチャーの対象と同じか**の確認を依頼 |
| `TIMEOUT` | 5 | 今回の実行の完了マーカーが、待ち時間内に出ない (ウォッチャーは、まだ処理を続けている) | **停止して報告。再試行しない** (下の「止めどき」。ウォッチャーが空いてから、次を実行する) |
| `BAD_ARGS` | 2 | 引数・フォルダの誤り | 引数を直して、再実行 (ソースは、直さない) |

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

## UI テスト (FlaUI): ビルド → テストの流れとは、別に、指定されたときだけ実行する

**UI テストは、ビルド → テスト (`build_test_once.sh`) の流れに、含めない。** 遅く、アプリを起動し、**制限時間を長く取る必要がある**ため、`PASSED` になっても、自動では、続けて実行しない。実行するのは、次のときだけ。
- **ユーザーが、UI テストの実行を求めたとき。**
- **`/ui-test-first` のループ** (画面を、プロンプトで作りながら、UI テストを先に書き、繰り返し実行する)。UI テストを先に書いて Red にする、UI テストファーストは、このループが担う (従来の「しない」は、取り下げた。DESIGN 4.38)。

### UI テストの、実行の指定 (どれも、ウォッチャーの再起動は、要らない)
`uitest_once.sh "$SLN" [待つ秒] [--filter 式] [--ui-timeout 秒] [--visible | --separate] [--slowmo ms]`
- **`--filter "FullyQualifiedName~クラス名"`:** `dotnet test --filter` の式で、**いま書いた UI テストだけ**を実行する (UI のループで、毎回、全部を走らせない)。式に、引用符・改行は、使えない。`~` は「含む」、`=` は「等しい」、`&` / `|` で組み合わせる。絞った結果が 0 件だと、何も実行されず、**`ENV_ERROR` (終了コード 4。`dotnet test` の「一致するテストはありません」が、そのまま出る)** になる (式の誤りは、これで気づける。実機で確認)。
- **`--ui-timeout 秒`:** ウォッチャーが、UI テストのプロジェクトを、強制終了するまでの時間 (既定 600 秒)。**UI テストが多い、重い画面は、長く** (例: `--ui-timeout 1800`)。指定しない既定は、`uitest.settings` の `timeout=` (プロジェクトごとの既定。例: `timeout=1800`) → ウォッチャーの `-UiTestTimeoutSec` / `WATCH_UI_TIMEOUT_SEC`。`--ui-timeout` が 780 以上なら、Skill 側の待ち時間も、自動で、`秒 + 120` に延びる。
- デスクトップ (`--visible` / `--separate`)、操作の間の待ち (`--slowmo`) は、上の「どのデスクトップで実行されるか」。
- **実行が、遅い・止まっているように見えるとき:** `.claude-logs/ui-timing.txt` (UI テストの各段階の時刻。実行ごとに作り直される) を読む。どの段階の間が、長いかが、分かる (ビルド完了から UI テスト開始までの空白、`dotnet test` の開始から終了まで、など)。
- **`--hold 秒` / `--preview [秒]` (目視確認):** UI テストは、いつもは、裏 (別のデスクトップ) で実行し、**見たいときだけ、その画面を、ユーザーのデスクトップに出す。** 生成される `PreviewUiTests.cs` (`[TestCategory("Preview")]`。アサーションなし) が、画面を、見せたい状態にして、`HoldForViewing()` を呼ぶ。`--hold N` は、`HoldForViewing` が、N 秒、待つ (ウィンドウを閉じると、早く終わる)。`--preview [N]` は、`--visible --hold N` (既定 60 秒) の省略形。例: `uitest_once.sh "$SLN" --filter "TestCategory=Preview" --preview`。ウォッチャーの制限時間は、`hold + 120` 秒以上に、自動で延びる。`UiTestBase.Snap("名前")` は、裏でも PNG を残す (Claude が、画像として読む)。`/ui-test-first` の「目視確認」に、手順。**既存の UI テストのプロジェクト (この機能より前に作ったもの) は、先に `python3 ~/.claude/skills/new-solution/scripts/add_ui_tests.py <フォルダ> --refresh-support-files` で、`UiTestBase.cs` などを更新する** (旧い版のままだと、`HoldForViewing` / `Highlight` がなく、`--present` の赤い枠が出ず、操作の間隔が、約 3 倍になる。実機で確認)。
- **`--present` (デモとして再生):** `--visible` + `--slowmo 800` (指定がなければ) + **操作する要素を赤い枠で囲む** (`UiTestBase.Find` / `OpenModal` が描く。`UITEST_PRESENT=1`)。UI テストを、そのまま、見せられる形で、ゆっくり再生する。**再生するのは、`--filter` で指定したテストだけ** (`--filter` が必須。ないと `BAD_ARGS`)。`--separate` とは、同時に使えない。入力やボタンの押下は、UIA で、一瞬で行われる (マウスのカーソルは、動かない。枠と待ちで、見せる)。

### いつ実行するか
- **ユーザーが求めたとき、または `/ui-test-first` のループの中だけ。** `build_test_once.sh` が `PASSED` になっても、UI テストのプロジェクト (名前が `UITests` / `UiTests` で終わる、または FlaUI を参照。`CLAUDE.md` に「UI テスト (FlaUI)」の節がある) があっても、**ユーザーが求めていなければ、実行しない。**
- UI テストは、**通常のテスト (`build_test_once.sh`) には、含まれない**。
- 実行するのは、**ソースを変えたとき**。修正の途中の、毎回は、実行しない (直したら、`--filter` で、そのテストだけ)。

```bash
bash <このSkillのフォルダ>/scripts/uitest_once.sh "$SLN" 900
```
使い方、出力の形、`FAILED` / `ENV_ERROR` / `TEST_TIMEOUT` の読み方は、`build_test_once.sh` と同じ。`run_in_background: true` で実行し、完了通知を待つ。

- **どのデスクトップで実行されるかは、UI テストのプロジェクトの `uitest.settings` が決める (ウォッチャーの起動し直しは、要らない。フレームワークごとの違いを、ウォッチャーでなく、このファイルが持つ):** `<アプリ>.UITests/uitest.settings` に `desktop=visible` (ユーザーのデスクトップ) または `desktop=separate` (別のデスクトップ。`invisible` でも同じ)、`slowmo=N` を書く。**`add_ui_tests.py` が、プロジェクトを作るときに書く: WPF は `visible`** (WPF のメニューのポップアップが、別のデスクトップでは、開かないため)、**それ以外 (WinForms / MFC / C#) は `separate`** (ウィンドウが画面に出ず、ユーザーに「触らないで」と頼む必要は、ない)。ファイルがなければ、`separate`。`--refresh-support-files` は、ファイルがなければ足す (あれば、上書きしない)。**1 回ごとの指定 (ファイルより優先):** `uitest_once.sh <dir> [秒] --visible` (ユーザーのデスクトップ) / `--separate` または `--invisible` (別のデスクトップ。WPF でも。メニューを使わないテストや、ユーザーが PC を使いたいとき) / `--slowmo 800` (操作の間に待ちを入れる)。指定は、`trigger_uitest.flag` の中身 (`desktop=visible` / `desktop=separate` / `slowmo=N`) として、ウォッチャーに渡る。**優先順:** この 1 回ごとの指定 > ウォッチャーの設定 (`-UiTestDesktop` / `WATCH_UI_DESKTOP` で `default` / `separate` を指定したとき。`run_watcher_visible.cmd` は、`default` に固定する) > `uitest.settings` > `separate`。UI テストのプロジェクトが複数あるときは、1 つでも visible なら visible。ウォッチャーの画面に、`[UI] desktop: ... (理由)` と出る。**ユーザーのデスクトップで実行するとき (`desktop=visible` のプロジェクト、`--visible`) は、実行の前に、ユーザーに、「UI テストを、あなたのデスクトップで実行します。実行中 (数分) は、マウスとキーボードに触らないでください」と伝える** (フォーカスが奪われることがある)。**ウォッチャーが古い (この機能より前の版) と、flag の中身と `uitest.settings` が無視され、別のデスクトップで動く** → `~/src/copy-host-tools.sh` で再配置して、ウォッチャーを再起動する。
- **WPF のメニュー (実機で確認、2026-10-26):** WPF のメニューのポップアップは、**別のデスクトップでは、開かない** (`Expand()` も、状態が `Collapsed` のまま。ユーザーのデスクトップでは、開く)。WinForms / MFC のメニューは、別のデスクトップでも開く。**そのため、WPF の UI テストのプロジェクトには、`uitest.settings` に `desktop=visible` が書かれる** (上)。**WPF のプロジェクトの XAML に、メニュー (`Menu` / `MenuItem` / `ContextMenu`) があると、`build_once.sh` / `build_test_once.sh` (と、`uitest_once.sh`) の出力の最後に、`NOTE:` が出る** (`scripts/wpf_menu_note.sh`。1 行目と終了コードは、変わらない。メニューがなければ、出ない。直近の UI テストが、ユーザーのデスクトップ (`desktop: Default`) なら、出ない)。`desktop=visible` の `uitest.settings` が**ない**とき: 書くよう促す 1 行。**ある**とき: 設定に従い、ユーザーのデスクトップで実行される旨の 1 行 (ユーザーに、実行中は触らないよう伝える)。**直近の UI テストが、別のデスクトップで動いた記録があれば、2 行目:** ウォッチャーが古い (再配置して、再起動)、または `--separate` / `--invisible` を指定した。メニューを含むテストは、`--visible` で実行する。別のデスクトップでは、ボタン・単体テスト (規則と Presenter / ViewModel) で、確かめる。
- ウォッチャーが古い (UI テスト未対応) と、`WATCHER_NOT_RUNNING`。`~/src/copy-host-tools.sh` で再配置して、ウォッチャーを起動し直す。

### UI テストが多いとき (`TEST_TIMEOUT`)
- ウォッチャーの、UI テストの制限は、**テストプロジェクト 1 つあたり、既定 600 秒** (`uitest_once.sh` に渡す秒数 (既定 900) とは、別)。UI テストが多い (ダイアログ・ListView・グリッドなどの調査) と、`TEST_TIMEOUT` (`=== ...: TIMEOUT after 600s (killed) ===`) で、プロセスごと強制終了され、結果ファイル (trx) は、残らない (**`ui-trace.txt` は、1 行ずつ追記されるので、残る。最後の数行で、どのテストの、どの操作で、止まったかが、分かる**)。
- **対処:** (0) **ウォッチャーの再起動は、要らない:** `uitest_once.sh --ui-timeout 1800` (1 回だけ)、または、`uitest.settings` の `timeout=1800` (プロジェクトごとの既定)。**延ばすのは、1 回だけ。2 回続いて `TEST_TIMEOUT` なら、延長せずに、停止して報告する** (固まっている可能性が高い。「止めどき」)。(1) 環境変数で、ウォッチャーの既定を変えるなら、ユーザーに、ウォッチャーを、環境変数 `WATCH_UI_TIMEOUT_SEC` を設定して、起動し直してもらう (`set WATCH_UI_TIMEOUT_SEC=1800` → `run_watcher.cmd ...`)。起動画面の `UI test` の行に、`timeout 1800s` と出る。(2) 1 つのテストに、操作を詰め込まず、**分割する** (特に、項目が多い ListView の `FindAllDescendants` の繰り返しは、遅い)。(3) 調査のログは、**1 行ごとに、すぐ書く** (外から強制終了されても、それまでの結果が、残る)。

### 動いたことを、確かめる (トレースと、目で見るモード)
- `uitest_once.sh` は、最後に、**操作の記録 (`.claude-logs/ui-screenshots/ui-trace.txt`)** から、テストごとの結果の行 (`=== テスト名: Passed` など) を出す。**UI テストが、実際に、起動して、操作したことの確認**に使う (`PASSED` と出ても、テストが 0 件でないこと、狙いのテストが動いたことを、行で確かめる)。記録は、`find: <AutomationId>` (探した要素)、`launched: <exe>`、`=== <テスト名>: start (desktop: ..., slowmo: ... ms)` などで、全文は、Read で読める。
- **ユーザーが「目で確かめたい」と言うとき:** `uitest_once.sh <dir> [秒] --visible --slowmo 800` で、実行する (ウォッチャーの起動し直しは、要らない。待ちは、`--slowmo 1500` などで変える)。ウィンドウが、画面に出て、入力や、ボタンが、順番に動くのが見える。**実行中、ユーザーは、PC を、快適には使えない** (マウスやキーボードの入力が、フォーカスを持つテスト対象のアプリに入ることがある)。`desktop=visible` のプロジェクト (WPF) は、`--slowmo` を付けなければ、待ちなしで、ユーザーのデスクトップで動く。(ウォッチャーを `run_watcher_visible.cmd` で起動する従来の方法も、使える。`WATCH_UI_DESKTOP=default`、`WATCH_UI_SLOWMO_MS=800` が、設定される。1 回ごとの `--separate` は、これより優先される。)
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

3. **アプリの不具合なら、アプリを直して**、単体テスト (`build_test_once.sh`) が通ることを確かめてから、`uitest_once.sh` からやり直す (`/ui-test-first` のループでは、同じ `--filter` で、`uitest_once.sh` を実行する)。**テストの書き方の誤りなら、テストを直す。** どちらか迷うときは、スクリーンショットで、画面の実際の状態を見て、判断する。
4. **UI テストを通すために、アサーションを弱めたり、テストを消したりしない。**
5. UI テストの修正の繰り返しは、**スクリプトの実行の合計で、5 回まで、同じ失敗は 3 回まで** (「止めどき」。単体テストの回数とは、別に数える)。それでも通らなければ、スクリーンショットと原因の仮説を、報告して止まる。

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
- **第 2 弾 (ListView・スピン・ツリー・日付・タブ) の道具:** `ListItems` (ListItem と DataItem の両方) / `ClickColumnHeader` (列ヘッダー。WinForms / MFC は `SysHeader32` へ PostMessage、WPF は Invoke) / `SetNumeric` (スピン・NumericUpDown・TextBox) / `ToggleTreeNode` (ツリーのチェック) / `OpenDropDown` + `FindCalendar` (日付ピッカーのカレンダー) / `PostKey` + `Vk.*` + `FocusAndKeys` (キー。別のデスクトップでも動く PostMessage) / `SelectTab` (**WinForms / MFC は、タブの名前を、並び順で、全部渡す**。UIA の TabItem は信用できない) / `ForceCloseDialog` (`PressDialogButton` が失敗したときに自動で呼ぶ) / `GetAppWindow` (`UiTestBase` が使う。入力インジケーターの小窓を除く)。**`SendMessage` は、すべて 5 秒のタイムアウトつき** (固まったアプリに、同期の SendMessage をすると、テストごと、ウォッチャーの制限時間で殺される)。
- **注意 (実機で確認):** (1) ウィンドウを持つボタンは `BM_CLICK` の `PostMessage` (UIA の `Invoke` は、`ShowDialog` / `DoModal` の中で戻らず、WinForms / MFC では、以後の UIA が止まる)。(2) WinForms のメニュー項目は、アプリ側で、ダイアログを開く処理を、`BeginInvoke` で遅らせる。MFC のメニューは、`MenuCommand` (`WM_COMMAND`)。(3) **WPF のメニューは、別のデスクトップでは、開かない** (WPF の UI テストは、既定で、ユーザーのデスクトップ。ビルドの出力の `NOTE:` を参照)。(4) キーボード・マウスの入力は、別のデスクトップでは、拒否される。(5) MFC のスクロールバーは、UIA の値が 0〜100 に正規化される (位置は、`SetScrollBar` / `ScrollBarValue` が、`SBM_GETPOS` で扱う)。
- **コントロールに、`AccessibleName` / `AutomationProperties.Name` を付ける** (WinForms は、直前の `Label` の文字が、UIA の名前になる)。


### コントロール別の、実機の結果の表 (WinForms / WPF / MFC。`poc/dialog-flaui/README.md` に、根拠)
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
5. **次のことは、ユーザーの明示的な許可なしにしない** (実装側の細工と、テストファイルの編集の扱いも含む: 下の「止めどき」の 5)。
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

## ループのルール (詳細は、下の「止めどき」)
1. ソースを修正したら `build_test_once.sh` を実行する。修正していない状態での再実行はしない。
2. **最大 5 回** (スクリプトの実行の合計。`BUILD_FAILED` / `FAILED` / `TEST_TIMEOUT` を通算)。5 回目も失敗なら、残りの失敗と試した修正を報告して停止する。
3. **同じテストが同じ内容 (同じ期待値・実際の値) で修正後も失敗する場合**は、2回目で止めて原因を調べる。
   ファイルが外部 (エディタの再保存など) で書き戻されている可能性も疑い、ユーザーに確認する。
4. 修正のたびに、ビルドエラーが出ていないかも見る (`BUILD_FAILED` は通常のビルドエラーとして直す)。
5. `.claude-logs/` の `build.log` / `test.log` (全文、フルパス) は、詳細が必要なときだけ読む。通常は不要。
6. 修正時はファイルの文字コード (UTF-8 BOM の有無など) と改行コードを変えない。無関係なリファクタリングはしない。

## テストの改変の検査 (`test_guard.py`): 「止めどき」5 の、テスト側の禁止事項を、機械で確かめる
禁止事項は、文章だけでは、守られたかを、確かめられない。**Red を確認したテストを、基準として、コピーしておき、いまのテストと比べる** (読み取りだけ。Windows もウォッチャーも、要らない)。

```bash
python3 -I ~/.claude/skills/build-test-loop/scripts/test_guard.py snapshot "$SLN"   # Red を確認した直後に、1 回 (ユーザーが、テストの変更を承認したときも、やり直す)
python3 -I ~/.claude/skills/build-test-loop/scripts/test_guard.py check    "$SLN"   # 修正のあと (ビルド・テストの前でよい) と、報告の前に
```

- **対象:** `*Test/` `*.Tests/` `*.UITests/` の中のファイル、`Test*.cpp` / `*Tests.cs`、`*.runsettings`、テストの `.csproj` / `.vcxproj`。`UiDialogs.cs` / `UiTestBase.cs` (支援ファイル) は、除く。基準は `.claude-logs/test_guard_base/`。
- **error (ユーザーの許可なしにしてはいけない変更):** テストの削除 (TMG001)、`[Ignore]` / `Assert.Inconclusive` / `GTEST_SKIP` / `DISABLED_` / 既存のテストへの `[TestCategory]` (TMG002)、アサーションがゼロ (TMG003)、アサーションを弱める (TMG005)、テストを実行から外す設定 (TMG009)。**終了コード 1。元に戻すか、止まってユーザーに確認する。**
- **warning:** アサーションの数が減った (TMG004)、許容誤差を広げた (TMG006)、`[Timeout]` の延長・`Sleep` の追加・待ち時間の延長 (TMG007)、`catch` の追加・例外を期待するアサーションの削除 (TMG008)。**正当な場合もある。理由を、報告する。**
- **review (機械では、正誤を判定できない):** アサーションの行の書き換え (TMG010。変更前後が並ぶ。**期待値を、実装の出力に合わせていないか**を確かめる)、Fake・ヘルパー・`[TestInitialize]` / `SetUp`・設定の変更 (TMG011)。
- **出力の「変更されたテストファイル」の一覧は、報告の先頭に書く** (「止めどき」5 の、機械的な追従の報告と、同じ)。
- **限界:** 鍵ではなく、検知器。基準のコピーを書き換えれば、すり抜ける (**基準を、勝手に、作り直さない。作り直すのは、ユーザーが承認したとき**)。ヘルパーへ判定を移す細工や、実装側の細工 (テストの入力値に対する固定の答え、`#ifdef TEST`) は、検出できない (そちらは、「止めどき」5 の実装側)。
- 終了コード: 0 = error なし / 1 = error あり / 2 = 引数が不正 / 3 = 基準がない・テストファイルがない。
- **`TEST_GUARD:` の行 (自動):** 基準があるとき、`build_test_once.sh` / `uitest_once.sh` は、出力の**末尾**に、`check` の結果を 1 行 (error のときは、数行) 足す。`TEST_GUARD: OK (...)` = 改変なし。`TEST_GUARD: REVIEW (...)` = warning / review がある (全文を見て、変更前後をユーザーに見せる)。`TEST_GUARD: ERROR (...)` = **error: 元に戻すか、止まって確認する** (「止めどき」5。承認されたら、`snapshot` をやり直す)。**この行が出ない = 基準がない** (Red の確認後に `snapshot` を取っていない、またはテストファーストの流れではない)。**出ないからといって、Green のあとに `snapshot` を取らない** (改変を、基準に取り込んでしまう)。1 行目と終了コードは、変わらない (`PASSED` のまま、`TEST_GUARD: ERROR` が付くことがある)。
- **`RESULT_INFO:` と `NOTE: 版の不一致` / `NOTE: ウォッチャーが古い` の行 (自動。v2.29.0):** `build_once.sh` / `build_test_once.sh` / `uitest_once.sh` / `package_once.sh` / `gtest_once.sh` は、出力の**末尾**に、結果の自己記述 (`RESULT_INFO: kind=… input=<フォルダ名> finished=<時刻> watcher=<版>`) を足す。**結果が、今回の実行のものか、どのソリューションのものか、を、この行で確かめる** (古い結果の取り違えの防止)。Skill とウォッチャーの版が違うとき、ウォッチャーが古いとき (版の表示なし) は、`NOTE:` の行が出る。**NOTE は警告で、結果と終了コードは変わらない。出たら、報告に 1 行添え、ユーザーに「`install/install.sh` で再配置し、ウォッチャーを再起動」を案内する** (テスト・修正のループは、そのまま続けてよい。ただし、ウォッチャー側の変更を、確認する依頼では、先に揃える)。

## 止めどき (停止の規則。`auto-build` / `build-test-loop` / `wpf-test-first` / `cpp-test-first` / `add-feature` / `ui-test-first` に共通)
1. **回数の数え方:** スクリプトを実行した回数の**合計**で数える (`BUILD_FAILED` / `FAILED` / `TEST_TIMEOUT` を通算)。**最大 5 回**まで。5 回目も失敗なら、残りの失敗と試した修正を報告して停止する。`add-feature` では、**タスクごと**に数え直す (ただし、1 回の依頼の全体で、**合計 15 回**を超えたら、止めて、報告する)。
2. **直さずに、停止して報告するもの (再実行しない):** `ENV_ERROR`、`WATCHER_NOT_RUNNING`、`TIMEOUT` (rc 5)、`BAD_ARGS` (rc 2。引数を直すだけは、よい)。**`TIMEOUT` (rc 5) は、再試行しない:** ウォッチャーは、まだ、処理を続けている (結果は、あとから書かれる)。**新しい実行は、ウォッチャーが、空いてから**にする (ユーザーに、ウォッチャーの画面で、終わったかを、確認してもらう)。実行 ID の照合 (下記) で、古い結果の誤読は、防いでいるが、ウォッチャーは、1 つずつ処理するので、重ねても、待たされるだけ。
3. **`TEST_TIMEOUT` が、2 回続いたら、延長せずに、停止して報告する** (`TEST_TIMEOUT` の扱い)。
4. **同じ失敗が、同じ内容で、修正後も出る場合は、2 回目で止めて**、原因を調べる (外部の書き戻しも疑う)。
5. **やってはいけないこと (ユーザーの明示的な許可なしに):**
   - **テスト側:** テストの削除、無効化 (`DISABLED_` / `GTEST_SKIP()` / `[Ignore]` / `Assert.Inconclusive`)、アサーションを弱める、許容誤差を広げる、期待値を実装の出力に合わせる、`[Timeout]` の延長、`[TestCategory]` や `.runsettings` で外す、テスト内への `try` / `catch` の追加 (失敗を飲み込む)、`Fake` / ヘルパー / `[TestInitialize]` / `SetUp` を、通るように変える。
   - **実装側 (テストを、通すためだけの細工):** テストの入力値を知っていて、その値に対して、固定の答えを返す (ハードコード)、`#ifdef` / `if (IsTest)` などの、テスト用の分岐、テストを `.vcxproj` / `.csproj` から外す・コンパイル対象から除く、`--gtest_filter` / `-TestArgs` / `--filter` を変えて、失敗するテストを実行から外す。
   - **テストファイルの編集は、機械的な追従 (`include` の追加、名前・シグネチャの変更への追従) 以外は、コンパイルエラーを直すためでも、事前に、ユーザーに確認する。** 機械的な追従をしたときは、報告の先頭に、書く。
   - **この禁止事項は、`test_guard.py` で、機械的に確かめられる** (上の「テストの改変の検査」)。Red を確認したら `snapshot`、修正のあとと報告の前に `check`。error は、許可なしにしてはいけない変更の、検出。
6. **実行 ID と処理中の印 (v2.20.0):** スクリプトは、フラグの 1 行目に `run=<ID>` を書く。ウォッチャーは、結果のマーカーを書く直前に、同じ ID を `.claude-logs/run_id.txt` に書き、スクリプトは、一致する結果だけを受け取る (前の実行が、あとから書いた古い結果を、今回の結果と取り違えない)。処理の間、ウォッチャーは `.claude-logs/watcher_busy.txt` を置く (処理中は、フラグの回収が遅れても、`WATCHER_NOT_RUNNING` にならず、`TIMEOUT` まで待つ。`TIMEOUT` のとき、回収されていないフラグは、取り下げる)。**古いウォッチャーでは、この照合は、働かない** (再配置して、再起動する)。

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
