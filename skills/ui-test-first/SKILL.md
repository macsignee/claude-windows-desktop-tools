---
name: ui-test-first
description: 画面 (UI) を、ユーザーのプロンプトで作りながら、UI テスト (FlaUI) を先に書き、実行して、直す、小さなループ。WinForms / WPF / MFC (C++)。UI テストは、ビルド → テストの流れとは別に、このループの中で、絞って (--filter)、長い制限時間 (--ui-timeout) で、実行する。「UI をテストファーストで作りたい」「画面を作りながら UI テストも書いて」「UI テストで確かめながら、画面を作って」といった依頼で使う。
argument-hint: "[作りたい画面・動作の説明]"
disable-model-invocation: true
---

# UI のテストファースト (/ui-test-first): 画面を作りながら、UI テストを先に書いて、繰り返し実行する

> **パスの書き方:** `<Skill群>` = この Skill のフォルダ (Base directory) の 1 つ上。ほかの Skill も、そこにある。コマンドでは、実際のパスに置き換える。

**プロンプトで、画面を作りながら、UI テスト (FlaUI) を先に書き、実行して、直す**ループ。1 サイクルは、「1 つの画面の、1 つのまとまった動作」。
連動の規則 (チェックで入力欄が有効になる、など) は、**純粋な関数の単体テスト** (`csharp-test-first` / `cpp-test-first`、`build-test-loop`) で確かめる。**UI テストは、画面が、規則と、つながっているか (煙テスト) と、主要な操作の流れ**を確かめる。

UI テストは、**ビルド → テストの流れには、含まれない** (遅く、制限時間を長く取る必要がある)。この Skill のループの中と、ユーザーが求めたときだけ、`uitest_once.sh` で実行する (**実行の指定・いつ実行するか・失敗したら・書き方は、`build-test-loop` の `references/ui-tests.md` を、先に読む**)。

## 前提
- カレントが、ソリューションフォルダ (`.sln` / `.slnx` があるフォルダ)。以降 `$SLN_DIR`。**なければ、`/new-solution` を案内して止まる。**
- **作業フォルダ (`solutions.md` があり、`.sln` / `.slnx` がないフォルダ) で起動しているとき** (複数の候補のソリューションを、比べているとき): `$SLN_DIR` は、カレントではなく、対象の候補。`SLN_DIR=$(python3 <Skill群>/new-solution/scripts/new_solutions.py resolve "$PWD" [<候補名>])` で決める (終了コード 2: 候補が複数 → 一覧を示して、ユーザーに質問する。3: 対象がない)。以降の `CLAUDE.md` や `docs/` は、`$SLN_DIR` の下 (その候補のコピー)。**他の候補は、読まない・書かない。** ウォッチャーは、その候補のフォルダで、起動されている必要がある。
- **画面が DLL にあり、呼び出す exe がない構成のときは、先に、画面ホストを足す** (`python3 <Skill群>/cpp-test-first/scripts/add_ui_host.py "$SLN_DIR"`。UI DLL・画面ホストの exe・UI テストが、一緒にできる。`cpp-test-first` の `DLL-LAYOUT.md`)。
- **UI テストのプロジェクト (`<アプリ>.UITests`) があること** (名前が `UITests` / `UiTests` で終わる、または FlaUI を参照。`CLAUDE.md` に「UI テスト (FlaUI)」の節がある)。**なければ、作る:** `python3 <Skill群>/new-solution/scripts/add_ui_tests.py "$SLN_DIR"` (ユーザーに確認してから。WPF / WinForms / MFC)。
- **`CLAUDE.md` の `- メイン:` で、フレームワークを判定する** (WinForms / WPF / MFC)。**`<アプリ>.UITests/uitest.settings` の `desktop=` を読む。** `visible` (WPF の既定) なら、**実行の前に、ユーザーに伝える:** 「UI テストを、あなたのデスクトップで実行します。実行中 (数分) は、マウスとキーボードに触らないでください」。`separate` なら、不要。
- ユーザーが、`run_watcher.cmd` を起動済みであること (なければ `WATCHER_NOT_RUNNING`。起動を依頼する)。ウォッチャーが古いと、`--filter` / `--ui-timeout` が無視される (`~/src/copy-host-tools.sh` で再配置して、再起動)。

## 手順

### 1. 画面の、計画を立てる (**ここで、1 回、ユーザーの承認を取る**)
プロンプト (`$ARGUMENTS` と、会話) から、次を、**短い表**にして、示す。

**先に、2 つを確認する (どちらも、読み取りだけ):**
- **既存の設計:** `docs/design/<画面>.md` (下の、承認のあとの記録) が、あれば読む。**あれば、その表を出発点にして、変更する行だけを示す** (作り直さない。ユーザーが、決めた案を、勝手に変えない)。
- **案を比べるか (任意):** 画面が**新規**で、部品の構成や配置が定まらず、ユーザーが迷っている (または「案を見たい」と言った) ときだけ。**2〜3 案**を、**部品の一覧と、配置の簡単な図 (文字で書く。画像や外部のツールは、使わない)** で示し、**各案の長所・短所を 1 行ずつ**添えて、**1 案を選んでもらう** (推奨案と理由を添える。AskUserQuestion が使えるなら、選択肢で)。選ばれた案を、下の 2 つの表に落とす。**1 案で足りるとき (定まっているとき) は、飛ばす。** 案の比較は、見た目の最終決定ではない (見た目の指摘は、目視確認のあとで、言葉で受ける)。
- **部品:** コントロールの一覧と、**識別の名前** (下の表)。操作する部品には、必ず、名前を付ける。**表の列は、「部品 / 種類 / 識別の名前 / 守る規則 ID」** (例: 名前の入力欄 / `TextBox` / `NameTextBox` / UI-ACC-001, UI-CTL-020)。
- **操作と期待:** 「入力欄に A を入れる → ラベルが B になる」のような、**具体例** (3〜7 件)。境界値・異常系があれば、1〜2 件。**表の列は、「# / 操作 / 期待 / 確認場所 / 守る規則 ID」** (該当する規則がない行は、「なし」と書く)。
- **どこで確かめるか:** 規則 (純粋な関数の単体テスト) / 煙テスト (UI テスト)。**UI テストは、主要な流れに、絞る** (見た目、レイアウト、色は、対象外)。
- **実行の指定:** 絞り込みの式 (`--filter`)、制限時間 (`--ui-timeout`。重い画面は、長く)。
- **画面の種類 (メインウィンドウか、ダイアログ・サブウィンドウか):** **メインウィンドウではない画面 (モーダルなダイアログ、モードレスなサブウィンドウ) のときは、先に `references/dialogs.md` を読み**、計画に、**種類・開き方 (開くボタンも、部品として含める)・閉じ方と結果・開くときの前提**の表を足す。
- **依存する Model (データベース・API などの違いを隠す、リポジトリのようなもの):** 画面が使う Model が、**まだ本物でない (これから作る)** ときは、**先に `references/model-switching.md` を読み**、計画に、**表 (Model (インターフェース) / 実装 (Fake / 本物) / 契約テスト (クラス名) / 状態 (Fake のみ / 本物あり / 結合済み))** を足す。**UI テストは、Fake (メモリ上の実装) で回し、本物ができたら、結合する** (環境変数 `APP_MODEL`、`uitest.settings` の `model=`)。
- **目視確認 (プレビュー):** 画面ごとに、**その画面を開いた状態を見せるテスト** (`Preview_<画面>`、`[TestCategory("Preview")]`) を 1 つ置く。いつもは、裏で実行し、見たいときだけ、ユーザーのデスクトップに出す (下の「目視確認」)。
- **ガイドライン (`/ui-design-review`):** UI デザインガイドラインに沿う。**上の 2 つの表 (部品、操作と期待) の、列「守る規則 ID」に、規則 ID (必須の規則を優先) を書く。規則 ID を、表の外の文に、まとめて書くだけにしない。** 表の下に、**付録 E の項目のうち、この画面に該当するものの番号**を、1 行で書く。対応: 5 コントロール一覧、6 キーボード、**7 状態の条件 (有効 / 無効 / 非表示 / 読取専用。例: 入力の有無で、ボタンが有効になる)**、8 画面の状態、9 ボタンの動作 (OK / 適用 / キャンセル / 閉じる)、10 入力検証、12 処理、15 アクセシビリティ。**既存の画面で、静的検査 (`ui_guideline_check.py`) の指摘が分かっているときは、必須の指摘のすべての規則 ID と、それぞれ「この場で直すか、別に直すか」を、承認の質問に含める** (一部だけ質問して、残りを黙って「別対応」にしない)。

| フレームワーク | 部品の識別 (UIA の AutomationId) | View に書くもの |
|---|---|---|
| WinForms | コントロールの `Name` (変数名と同じ) | `*.Designer.cs` に、`Name` を付けた部品。`AccessibleName` (直前の `Label` が名前になる問題への対策) |
| WPF | `AutomationProperties.AutomationId` (または `x:Name`) | XAML。リスト・ツリーの項目のデータのクラスに `ToString()`。チェックは `Checked` / `Unchecked` |
| MFC (C++) | リソースのコントロール ID の数値 | `.rc` と `Resource.h`。テストでは、数値の文字列 (`"1007"`) で探す |

**承認を得てから、2. に進む** (承認されなければ、計画を直す)。承認のあとの、サイクルの中は、止まらずに進める。

**承認されたら、設計を `docs/design/<画面>.md` に保存する** (計画の「触るファイル」に含めて示す。フォルダがなければ作る。UTF-8、BOM なし、LF)。**書式と書き方は `references/design-record.md`** (この記録は、設計の正本。UI テストの名前と「操作と期待」の `#` を対応させる。コードから、推測して書かない)。

### 2. UI テストを、先に書く (Red)
- `<アプリ>.UITests/<画面>UiTests.cs` に、`UiTestBase` を継承したクラスを、**計画の具体例の、1 件ごとに、1 つのテスト**で書く。**テスト名は、`画面_条件_期待`。**
- 操作は、`UiDialogs` の道具と、UIA のパターン (`Invoke` / `Value` / `Toggle`) だけ (**マウス・キーボードの入力は、使わない**)。ダイアログは `OpenModal`、ボタンは `UiDialogs.Click`、リスト・ツリー・スピン・日付・タブは、`ListItems` / `ClickColumnHeader` / `SetNumeric` / `ToggleTreeNode` / `OpenDropDown` / `SelectTab` など。**フレームワークごとの違いの表: `build-test-loop` の「コントロール別の、実機の結果の表」。**
- **ダイアログ・サブウィンドウの中の部品は、`Find(window, "Id")` で探す** (`var dlg = OpenModal(Find("EditButton")); Find(dlg, "OkButton")`。`Find("Id")` は、メインウィンドウの中だけ。詳しくは `references/dialogs.md`)。
- 期待値は、**仕様 (プロンプトの具体例) から、直接、書く** (実装の出力を、写さない)。待ちは `WaitFor` (固定の `Thread.Sleep` を使わない)。

- **プレビュー用のテストも、書く:** `PreviewUiTests.cs` に、`[TestMethod] [TestCategory("Preview")] public void Preview_<画面>()` を足す。**アサーションは置かない。** 画面を、見せたい状態にして (ダイアログなら `var dlg = OpenModal(...)`、タブなら `SelectTab`)、`Snap("名前", dlg)` (Claude 用の画像。ダイアログを撮るときは、`dlg` を渡す。省略すると、メインウィンドウ) と `HoldForViewing("画面の名前")` (ユーザーに見せる) を呼ぶだけ。

### 3. 最小の View を置く (配線だけ) → ビルド → Red を確認する
- **部品を、名前つきで置くだけ** (動作は、まだ、書かない)。規則 (純粋な関数) と Presenter / ViewModel は、`csharp-test-first` / `cpp-test-first` の流れで、**先に、単体テスト (Red → Green) で作る** (`build_test_once.sh`。これは、UI テストと、別の流れ)。
- ビルド: `build_once.sh` (または、単体テストも含めて `build_test_once.sh`) で、ビルドが通ることを確認する。
- **UI テストを、絞って、実行する (Red):**
  ```bash
  bash <Skill群>/build-test-loop/scripts/uitest_once.sh "$SLN_DIR" --filter "FullyQualifiedName~<画面>UiTests" --separate --ui-timeout 1200
  ```
  **`--separate` (裏で実行) が、ループの、既定の指定** (WPF は、`--visible` より、1 件 約 5〜10 秒遅い。数件なら、`--visible` も選べる。`build-test-loop/references/ui-tests.md`)。 WPF は、`uitest.settings` の既定が visible (ユーザーのデスクトップを占有する) だが、**メニューを開く操作を含まないテスト**は、`--separate` で動く。**メニューを開く操作を含むテストは、別のクラス (`<画面>MenuUiTests`) に分け、WPF では `--visible` で実行する** (別のデスクトップでは、WPF のメニューのポップアップが開かず、「要素がない」という、偽の Red になる)。
  `run_in_background: true` で、完了通知を待つ。**Red の確認:** 失敗の理由が、**期待どおり** (要素がない、期待値と違う) であること。**コンパイルエラー、`ENV_ERROR`、フィルターが 0 件 (`ENV_ERROR`、終了コード 4。式の誤り) は、Red ではない** (先に直す)。
  **Red が確認できたら、基準を作る:** `python3 -I <Skill群>/build-test-loop/scripts/test_guard.py snapshot "$SLN_DIR"` (UI テストを、仕様として凍結する。**ユーザーが、テストの変更を承認したときだけ、やり直す**)。

### 4. 実装して、Green にする (ループ)
- View (動作) と、Presenter / ViewModel を、実装する。**1 回に、1 つのテストを、通す**ことを、目安にする。
- ビルド → **同じ `--filter`** (と `--separate`) で、`uitest_once.sh` を実行する。
- **失敗したら:** `.claude-logs/ui-screenshots/*.png` を、**Read ツールで、画像として読む** (画面の実際の状態)。`ui-trace.txt` (操作の記録) と、失敗メッセージも読み、原因を直す。**期待値を、画面の実際の状態に合わせて直すのは、仕様が変わったときだけ。アサーションを、弱めない。** `[Ignore]` / `Inconclusive` / `[Timeout]` の延長も、しない。
- **止めどきは、`build-test-loop` の「止めどき」に従う:** **1 つの画面の、1 サイクルで、`uitest_once.sh` の実行は、合計 5 回まで** (`BUILD_FAILED` / `FAILED` / `TEST_TIMEOUT` を通算)。**同じ失敗が、3 回続いたら**、止まって、報告する (試したこと、スクリーンショットで見たこと、次の案)。
  - **`TEST_TIMEOUT`:** まず、`.claude-logs/ui-screenshots/ui-trace.txt` の**最後の 10 行**を読む (どのテストの、どの操作で、止まったか。`TEST_TIMEOUT` でも、trace は、残る)。`--filter` を **1 つのテスト**に絞って、もう一度。**`--ui-timeout` を、延ばすのは、1 回だけ** (固まったアプリを、待っても、通らない。モーダルが `Invoke` で戻らない、ダイアログが閉じない、などを疑う)。**2 回続いたら、延長せずに、停止して報告する。**
  - **`TIMEOUT` (rc 5) / `WATCHER_NOT_RUNNING` (rc 3) / `ENV_ERROR` (rc 4):** 再試行せず、停止して報告する (ウォッチャーは、まだ、処理を続けている。ウォッチャーの画面で、終わったかを、ユーザーに確認してもらう)。**この場合、`uitest_once.sh` は、前回のスクリーンショットと trace を、表示しない** (古い結果と取り違えないため)。
- **毎回の実行の前後と、報告の前に、`python3 -I <Skill群>/build-test-loop/scripts/test_guard.py check "$SLN_DIR"` を実行する** (`build-test-loop` の「テストの改変の検査」)。error (テストの削除・`[Ignore]` / `Inconclusive`・アサーションを弱める・`[Timeout]` や待ちの延長・実行から外す設定) は、許可なしにしてはいけない変更。元に戻すか、止まって確認する。warning / review は、理由を報告する。
- **Green になったら:** その画面の、**全 UI テストを 1 回**実行して、回帰を確認する: `--filter "TestCategory!=Preview"` (**Preview のテストは、アサーションがなく、必ず通るので、回帰の件数に、混ぜない**。報告でも、Preview の件数は、別に書く)。静的な検査 (`winforms-check` / `wpf-check` / `mfc-check`) も、実行する。

### 5. 次のサイクルか、報告
- 次の動作 (計画の、次の具体例) があれば、2. に戻る。なければ、報告して、終わる。
- **報告:** 追加した画面とテスト (名前)、最後の実行結果 (件数)、**確認できていないこと** (見た目は、目視。**ユーザーが、目で確かめたいときは、`uitest_once.sh "$SLN_DIR" --visible --slowmo 800` で、実行する**)。

## Model の差し替え (Fake ↔ 本物) と、結合

Model が、まだ本物でないときの、**Fake での UI テスト** (環境変数 `APP_MODEL`。Release では読まない) と、**本物への結合** (関門 = 単体テストと契約テストが `PASSED`、`model=real` に切り替え、同じ UI テストを再実行、Red の原因を分ける、結合後も Fake を捨てない) の手順は、**`references/model-switching.md`**。

## 目視確認 (プレビュー) と、デモ (`--present`)

UI テストは、**裏 (別のデスクトップ。`--separate`) で、静かに回し**、ユーザーが見たいときだけ、**ユーザーのデスクトップに出す** (`--preview`)。**実行の前に、ユーザーに伝えて、「出してよい」という返事を待つ。** `Snap("名前")` は、Claude が画面を見るための PNG。**デモとして再生する** ときは `--present` (`--filter` が必須)。手順・オプション・注意は、**`references/preview.md`**。

## 実行のコツ
- **ガイドラインの検査:** 画面が Green になったら、`python3 -I <Skill群>/ui-design-review/scripts/ui_guideline_check.py "$SLN_DIR"` (読み取りだけ) を実行し、warning を報告に添える (`/ui-design-review`)。**必須の規則を満たせないときは、自分で例外にせず、ユーザーに、例外申請を提案する。**
- **制限時間:** 1 回の `uitest_once.sh` が、`TEST_TIMEOUT` になるときは、`--ui-timeout` を長くする。毎回の指定が面倒なら、`uitest.settings` に `timeout=1800` を書く。`--filter` で、絞る (全部を、毎回、走らせない)。調査用の、重いテストは、**新しく**、テストごとに `[Timeout]` を付け、ログを 1 行ごとに書く (killed されても、結果が残る)。**既存の `[Timeout]` を、通すために延ばすのは、禁止** (`build-test-loop` の「止めどき」)。
- **デスクトップ:** `--visible` / `--separate` で、1 回だけ、変えられる。WPF のメニューは、別のデスクトップでは、開かない。
- **フィルターの式の例:** `FullyQualifiedName~LoginDialog` (クラス名に含む)、`Name=Greeting_NameEntered_ShowsGreeting` (テスト名)、`FullyQualifiedName~Settings&Name~Ok` (組み合わせ)。引用符は、使えない。
- **道具が足りないとき:** `UiDialogs` に、ない操作は、PoC で、実機で確かめてから、足す (推測で、書かない)。**`UiDialogs.cs` と `UiTestBase.cs` は、`--refresh-support-files` で、上書きされる** (プロジェクトの側で、直接、編集しない)。このプロジェクトだけの道具は、**別のファイル** `UiDialogsExtra.cs` に、`internal static partial class UiDialogs` として、足す (上書きされない)。共通の道具に足したいときは、ユーザーに、相談する (ツール群のリポジトリの変更)。
- **MFC の ID の探し方:** `grep -n "#define IDC_" <アプリ>/Resource.h` で、数値を調べる (`IDOK` = `"1"`、`IDCANCEL` = `"2"`)。**`IDC_STATIC` は、ID で探せない** (`Name` = 表示の文字で探す)。ID を、テストに、直接、書くので、`Resource.h` の ID を変えたら、テストも、直す。
- **後始末:** 作業が終わったら、**一時的な確認用のテスト・デバッグ用の `Snap` / `HoldForViewing` を、残さない** (`PreviewUiTests.cs` の、画面ごとのプレビューは、残す)。**ウォッチャーは、実行の前後に、ソリューションのフォルダの下の exe を、すべて終了させる** (ユーザーが、同じフォルダのアプリを、手元で動かしていると、終了される。実行の前に、一言、伝える)。
