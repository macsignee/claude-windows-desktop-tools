---
name: ui-test-first
description: 画面 (UI) を、ユーザーのプロンプトで作りながら、UI テスト (FlaUI) を先に書き、実行して、直す、小さなループ。WinForms / WPF / MFC (C++)。UI テストは、ビルド → テストの流れとは別に、このループの中で、絞って (--filter)、長い制限時間 (--ui-timeout) で、実行する。「UI をテストファーストで作りたい」「画面を作りながら UI テストも書いて」「UI テストで確かめながら、画面を作って」といった依頼で使う。
argument-hint: "[作りたい画面・動作の説明]"
disable-model-invocation: true
---

# UI のテストファースト (/ui-test-first): 画面を作りながら、UI テストを先に書いて、繰り返し実行する

**プロンプトで、画面を作りながら、UI テスト (FlaUI) を先に書き、実行して、直す**ループ。1 サイクルは、「1 つの画面の、1 つのまとまった動作」。
連動の規則 (チェックで入力欄が有効になる、など) は、**純粋な関数の単体テスト** (`wpf-test-first` / `cpp-test-first`、`build-test-loop`) で確かめる。**UI テストは、画面が、規則と、つながっているか (煙テスト) と、主要な操作の流れ**を確かめる。

UI テストは、**ビルド → テストの流れには、含まれない** (遅く、制限時間を長く取る必要がある)。この Skill のループの中と、ユーザーが求めたときだけ、`uitest_once.sh` で実行する (`build-test-loop` の「UI テスト」)。

## 前提
- カレントが、ソリューションフォルダ (`.sln` / `.slnx` があるフォルダ)。以降 `$SLN`。**なければ、`/new-solution` を案内して止まる。**
- **UI テストのプロジェクト (`<アプリ>.UITests`) があること** (名前が `UITests` / `UiTests` で終わる、または FlaUI を参照。`CLAUDE.md` に「UI テスト (FlaUI)」の節がある)。**なければ、作る:** `python3 ~/.claude/skills/new-solution/scripts/add_ui_tests.py "$SLN"` (ユーザーに確認してから。WPF / WinForms / MFC)。
- **`CLAUDE.md` の `- メイン:` で、フレームワークを判定する** (WinForms / WPF / MFC)。**`<アプリ>.UITests/uitest.settings` の `desktop=` を読む。** `visible` (WPF の既定) なら、**実行の前に、ユーザーに伝える:** 「UI テストを、あなたのデスクトップで実行します。実行中 (数分) は、マウスとキーボードに触らないでください」。`separate` なら、不要。
- ユーザーが、`run_watcher.cmd` を起動済みであること (なければ `WATCHER_NOT_RUNNING`。起動を依頼する)。ウォッチャーが古いと、`--filter` / `--ui-timeout` が無視される (`~/src/copy-host-tools.sh` で再配置して、再起動)。

## 手順

### 1. 画面の、計画を立てる (**ここで、1 回、ユーザーの承認を取る**)
プロンプト (`$ARGUMENTS` と、会話) から、次を、**短い表**にして、示す。
- **部品:** コントロールの一覧と、**識別の名前** (下の表)。操作する部品には、必ず、名前を付ける。
- **操作と期待:** 「入力欄に A を入れる → ラベルが B になる」のような、**具体例** (3〜7 件)。境界値・異常系があれば、1〜2 件。
- **どこで確かめるか:** 規則 (純粋な関数の単体テスト) / 煙テスト (UI テスト)。**UI テストは、主要な流れに、絞る** (見た目、レイアウト、色は、対象外)。
- **実行の指定:** 絞り込みの式 (`--filter`)、制限時間 (`--ui-timeout`。重い画面は、長く)。

| フレームワーク | 部品の識別 (UIA の AutomationId) | View に書くもの |
|---|---|---|
| WinForms | コントロールの `Name` (変数名と同じ) | `*.Designer.cs` に、`Name` を付けた部品。`AccessibleName` (直前の `Label` が名前になる問題への対策) |
| WPF | `AutomationProperties.AutomationId` (または `x:Name`) | XAML。リスト・ツリーの項目のデータのクラスに `ToString()`。チェックは `Checked` / `Unchecked` |
| MFC (C++) | リソースのコントロール ID の数値 | `.rc` と `Resource.h`。テストでは、数値の文字列 (`"1007"`) で探す |

**承認を得てから、2. に進む** (承認されなければ、計画を直す)。承認のあとの、サイクルの中は、止まらずに進める。

### 2. UI テストを、先に書く (Red)
- `<アプリ>.UITests/<画面>UiTests.cs` に、`UiTestBase` を継承したクラスを、**計画の具体例の、1 件ごとに、1 つのテスト**で書く。**テスト名は、`画面_条件_期待`。**
- 操作は、`UiDialogs` の道具と、UIA のパターン (`Invoke` / `Value` / `Toggle`) だけ (**マウス・キーボードの入力は、使わない**)。ダイアログは `OpenModal`、ボタンは `UiDialogs.Click`、リスト・ツリー・スピン・日付・タブは、`ListItems` / `ClickColumnHeader` / `SetNumeric` / `ToggleTreeNode` / `OpenDropDown` / `SelectTab` など。**フレームワークごとの違いの表: `build-test-loop` の「コントロール別の、実機の結果の表」。**
- 期待値は、**仕様 (プロンプトの具体例) から、直接、書く** (実装の出力を、写さない)。待ちは `WaitFor` (固定の `Thread.Sleep` を使わない)。

### 3. 最小の View を置く (配線だけ) → ビルド → Red を確認する
- **部品を、名前つきで置くだけ** (動作は、まだ、書かない)。規則 (純粋な関数) と Presenter / ViewModel は、`wpf-test-first` / `cpp-test-first` の流れで、**先に、単体テスト (Red → Green) で作る** (`build_test_once.sh`。これは、UI テストと、別の流れ)。
- ビルド: `build_once.sh` (または、単体テストも含めて `build_test_once.sh`) で、ビルドが通ることを確認する。
- **UI テストを、絞って、実行する (Red):**
  ```bash
  bash ~/.claude/skills/build-test-loop/scripts/uitest_once.sh "$SLN" --filter "FullyQualifiedName~<画面>UiTests" --ui-timeout 1200
  ```
  `run_in_background: true` で、完了通知を待つ。**Red の確認:** 失敗の理由が、**期待どおり** (要素がない、期待値と違う) であること。**コンパイルエラー、`ENV_ERROR`、`tests: 0` (式の誤り) は、Red ではない** (先に直す)。

### 4. 実装して、Green にする (ループ)
- View (動作) と、Presenter / ViewModel を、実装する。**1 回に、1 つのテストを、通す**ことを、目安にする。
- ビルド → **同じ `--filter`** で、`uitest_once.sh` を実行する。
- **失敗したら:** `.claude-logs/ui-screenshots/*.png` を、**Read ツールで、画像として読む** (画面の実際の状態)。`ui-trace.txt` (操作の記録) と、失敗メッセージも読み、原因を直す。**期待値を、画面の実際の状態に合わせて直すのは、仕様が変わったときだけ。アサーションを、弱めない。** `[Ignore]` / `Inconclusive` / `[Timeout]` の延長も、しない。
- **同じ失敗が、3 回続いたら、止まって、報告する** (試したこと、スクリーンショットで見たこと、次の案)。
- **Green になったら:** その画面の、**全 UI テスト (`--filter` なし) を 1 回**実行して、回帰を確認する。静的な検査 (`winforms-check` / `wpf-check` / `mfc-check`) も、実行する。

### 5. 次のサイクルか、報告
- 次の動作 (計画の、次の具体例) があれば、2. に戻る。なければ、報告して、終わる。
- **報告:** 追加した画面とテスト (名前)、最後の実行結果 (件数)、**確認できていないこと** (見た目は、目視。**ユーザーが、目で確かめたいときは、`uitest_once.sh "$SLN" --visible --slowmo 800` で、実行する**)。

## 実行のコツ
- **制限時間:** 1 回の `uitest_once.sh` が、`TEST_TIMEOUT` になるときは、`--ui-timeout` を長くする。毎回の指定が面倒なら、`uitest.settings` に `timeout=1800` を書く。`--filter` で、絞る (全部を、毎回、走らせない)。調査用の、重いテストは、テストごとに `[Timeout]` を付け、ログを 1 行ごとに書く (killed されても、結果が残る)。
- **デスクトップ:** `--visible` / `--separate` で、1 回だけ、変えられる。WPF のメニューは、別のデスクトップでは、開かない。
- **フィルターの式の例:** `FullyQualifiedName~LoginDialog` (クラス名に含む)、`Name=Greeting_NameEntered_ShowsGreeting` (テスト名)、`FullyQualifiedName~Settings&Name~Ok` (組み合わせ)。引用符は、使えない。
- **道具が足りないとき:** `UiDialogs` に、ない操作は、PoC で、実機で確かめてから、足す (推測で、書かない)。
