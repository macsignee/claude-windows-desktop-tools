---
paths:
  - "**/*.Designer.cs"
  - "**/Forms/**/*.cs"
  - "**/Presenters/**/*.cs"
  - "**/*Presenter*.cs"
  - "**/I*View.cs"
---

# WinForms プログラミング規約 (ユーザー共通)

本規約は、WinForms を使用した業務アプリケーションを、複数人で継続的に保守できる状態にすることを目的とします。基本設計として **MVP (Model-View-Presenter) を必須**とし、画面 (Form) には値の出し入れだけを、Presenter に振る舞いを、置きます。

**適用の順序:**
1. プロジェクトの `CLAUDE.md` に、固有の決まりがあれば、それが最優先。
2. **WinForms のソリューション (`CLAUDE.md` が「WinForms (MVP)」) では、本規約を適用する。** 共通規約 (`csharp-common.md`。`.cs` を読むときに、自動で読み込まれる) の **C# の部分 (5 C# コーディング規約 / 10 非同期処理 / 11 依存性注入 / 12 例外処理 / 13 ログ / 15 コメント / 16 テスト / 17 禁止事項)** は、そのまま共通で使う。**WPF / XAML / MVVM に固有の節 (6 View / 7 ViewModel / 8 MVVM ライブラリ / 9 データバインディング / 14 XAML) は、適用しない。**
3. C# のクラスライブラリ (`CLAUDE.md` が「C# クラスライブラリ」) は、本規約の「3 層」と「6 テスト」と、`csharp-common.md` を使う。

**この文書は、`*.Designer.cs`、`Forms/` と `Presenters/` の下、`*Presenter*.cs`、`I*View.cs` を読むときに、読み込まれる** (WPF の規約は、読み込まれない)。
詳細な書式は、プロジェクトの `.editorconfig` が正 (なければ、`.claude/templates/dotnet/` のひな形)。
「**ツール群の補足**」は、このリポジトリのツール (`new-solution` / `csharp-test-first` / `winforms-check` / `add-package`) との対応。機械で判定できる項目は、**`winforms-check`** が確かめる (付録)。

## 1. 適用範囲
- WinForms アプリケーション、WinForms のクラスライブラリ (UserControl など)
- Form、UserControl、Presenter、業務ロジック、データアクセス処理
- 単体テスト、UI テスト (FlaUI)
- アプリケーション設定、ログ、例外処理

## 2. 基本方針

### 2.1 使用技術
- .NET (SDK 形式の `.csproj`)、C#、WinForms。ターゲットは、`net8.0-windows` 以降 (`UseWindowsForms`)。
- 単体テストは MSTest。UI テストは FlaUI (UIA3) + MSTest。
- `Nullable` と `ImplicitUsings` は有効 (`Directory.Build.props`)。

### 2.2 責務の分離 (MVP)
| 部品 | 役割 | 書いてよいもの | 書いてはいけないもの |
|---|---|---|---|
| **Form (View)** | 画面の表示と、入力の受け取り | コントロールの配置、値の出し入れ (プロパティ)、イベントの通知、画面固有の処理 (フォーカス、タブ順、アニメーション) | 業務ロジック、入力の検査の判断、データアクセス、`new Service()` |
| **IView** (インターフェース) | Presenter から見た Form の姿 | 値のプロパティ、イベント | WinForms の型 (`Control` / `Form` / `MessageBox`) |
| **Presenter** | 画面の振る舞い (表示する文字、ボタンの有効・無効、入力の検査、画面遷移の判断) | `IView` と、ロジック層のインターフェースの呼び出し | WinForms の型、`MessageBox`、`Application` |
| **ロジック / データ層** | 業務ロジック、データアクセス | 業務の処理 | WinForms への依存 (`UseWindowsForms`、`System.Windows.Forms`、`System.Drawing`) |

- **Form は、`IView` を実装して、イベントを通知するだけ**にする。ボタンの `Click` は、Form が受け取り、`ClearRequested` のようなイベントで Presenter に伝える。
- **Presenter は、WinForms を知らない。** テストでは、`IView` の偽物 (Fake) を作り、イベントを起こして、表示の結果を確かめる。
- (`winforms-check` の WFL001 / WFL002 / WFL004 が検査する。)

### 2.3 組み立てる場所 (composition root)
- **Form と Presenter を作って結ぶのは、`Program.cs` の 1 か所**にする。Form の中で、Presenter や Service を `new` しない。
- DI コンテナを導入するときも、ここで構成する。依存は、**コンストラクターで、インターフェースを受け取る**。
- **ツール群の補足:** 生成されるアプリは、`Program.Main` で `ApplicationConfiguration.Initialize()` → `new MainForm()` → `new MainPresenter(form)` → `Application.Run(form)` の順。

## 3. ソリューション構成

### 3.1 標準の構成
```
Solution/
  Solution.slnx
  Directory.Build.props
  .editorconfig
  App/                       ← WinForms アプリ (View)
    Program.cs               ← composition root
    Forms/                   ← Form と、*.Designer.cs
    Presenters/              ← ロジック層がないときだけ (IMainView / MainPresenter)
  LogicLayer/                ← Presenter と業務ロジック (WinForms 非依存。net10.0)
  DataLayer/                 ← データアクセス (net10.0)
  LogicLayer.Tests/ …        ← MSTest
  App.UITests/               ← FlaUI (必要なとき)
```
- **依存の向き: アプリ → ロジック → データ。** 逆向きの参照は禁止 (`winforms-check` の WFL003)。
- **ロジック層・データ層は、WinForms 非依存** (`net10.0` などの Windows 非依存。`UseWindowsForms` / `-windows` を付けない。`System.Windows.Forms` / `System.Drawing` を使わない)。付けると、ビルドで落ちるのではなく、**黙って、依存が混ざる**ので、`winforms-check` の WFL001 が確かめる。
- ロジック層がない小さなアプリでは、`IMainView` / `MainPresenter` は、アプリの `Presenters/` に置く。**業務ロジックが増えたら、ロジック層に切り出す。**

### 3.2 層の名前
既定は `LogicLayer` / `DataLayer`。作成後に、個々の事情に応じて、リネームしてよい (手順は `DLL-LAYOUT.md`。名前を変えたら、プロジェクト・名前空間・`CLAUDE.md` をそろえる)。名前が既定と違うときは、`winforms-check` に、`--logic <名前>` / `--data <名前>` で伝える。

## 4. 命名規約

### 4.1 型・メンバー
- 型・メソッド・プロパティは PascalCase、private フィールドは `_camelCase`、インターフェースは `I` 接頭辞 (C# の共通規約。`.editorconfig` が、提案として示す)。
- Form は `<画面名>Form`、Presenter は `<画面名>Presenter`、View のインターフェースは `I<画面名>View`。

### 4.2 コントロール (最重要)
- **すべてのコントロールに、役割が分かる `Name` を付ける。** `<役割><型>` の形 (`NameTextBox` / `SaveButton` / `OrderGrid` / `StatusLabel`)。`textBox1` / `button1` のままにしない。
- **`Name` は、フィールド (変数) 名と同じ文字列にする** (`NameTextBox.Name = "NameTextBox";`)。デザイナーが、そうしてくれる。コードで作るときも、そろえる。
- **理由:** `Name` は、UI テスト (FlaUI) の **`AutomationId`** になる。Name が空・重複・変数名と違うと、UI テストが、要素を探せない (`winforms-check` の WFD002 / WFD003 / WFD005)。
- 画面のレイアウト用のコンテナ (`TableLayoutPanel` など) にも、`Name` を付ける。
- **`IView` のプロパティの名前は、`Form.Name` などの継承メンバーと、衝突させない** (`Name` ではなく、`PersonName` など、役割の名前にする)。

### 4.3 bool
- `IsXxx` / `HasXxx` / `CanXxx` / `ShouldXxx`。`Flag` / `Status` / `Check` は、使わない (`winforms-check` の NAM001)。

## 5. C# コーディング規約
`csharp-common.md` の「5 C# コーディング規約」を、そのまま適用する (ファイルは UTF-8 BOM + CRLF、インデントはスペース 4、Allman、`file_scoped` の名前空間、`Nullable` 有効、波括弧を常に付ける)。

### 5.1 WinForms 固有の補足
- **`*.Designer.cs` は、Visual Studio のデザイナーが書き直すファイル。** 手で書くときは、デザイナーが読める形を保つ:
  - `InitializeComponent()` の中は、**宣言 (生成、プロパティの代入、`Controls.Add`、イベントの `+=`) だけ。** `if` / `for` / `while` / `switch` / `try` を書かない (`winforms-check` の WFD007)。処理は、コンストラクター (`InitializeComponent()` のあと) に書く。
  - `InitializeComponent()` は、`*.Designer.cs` に置く (`winforms-check` の WFD006)。
  - 生成したコントロールは、`Controls.Add` / `AddRange` で、親に入れる (入れないと、画面に出ない。`winforms-check` の WFD004)。
  - 各コントロールの `// 名前` のコメントの形、`SuspendLayout` / `ResumeLayout` の対を、保つ。
- **Form のファイルは、Visual Studio に Form と認識させる。** `using System.Windows.Forms;` を**明示**し (`ImplicitUsings` に頼らない)、`.csproj` に `<Compile Update="Forms\<名前>.cs"><SubType>Form</SubType></Compile>` を書く。**どちらかが欠けると、Solution Explorer で通常の `.cs` のアイコンになり、「デザイナーの表示」が出ないことがある** (実機で確認。VS で新しい Form を追加すると、`.csproj.user` に `SubType` が書かれて、開けるようになる)。生成される `MainForm` は、両方を持つ。Form を手で足すときは、VS の「新しい項目」で足すのが確実。
- **Form のコンストラクターは、`InitializeComponent()` を呼ぶ。** 忘れると、画面が空になり、例外も出ない (`winforms-check` の WFD001)。
- **イベントハンドラーは、Designer の `+=` と、Form のメソッド名を、そろえる** (名前を変えたら、両方を直す。食い違うと、`CS0103` でビルドに失敗する)。ハンドラーの名前は、`<コントロール名>_<イベント名>` (`ClearButton_Click`)。
- ハンドラーは、**Presenter へのイベント通知だけ**にする。

## 6. 画面 (Form) 規約

### 6.1 レイアウトと DPI
- **`TableLayoutPanel` / `FlowLayoutPanel` と、`Dock` / `Anchor` で配置する。** 座標 (`Location`) の直指定で、並べない (DPI・フォント・ウィンドウの大きさで崩れる)。
- `AutoScaleMode = AutoScaleMode.Font` (または `Dpi`)、`MinimumSize` を設定する。高 DPI は、`ApplicationConfiguration.Initialize()` に任せる。
- 余白・フォントは、画面で、そろえる。画面ごとに、ばらばらの値を書かない。
- タブ順 (`TabIndex`) を、操作の順に、そろえる。キーボードだけで、操作できるようにする (`AcceptButton` / `CancelButton`、ショートカット)。

### 6.2 入力と表示
- 入力の検査 (必須、形式、範囲) の**判断は、Presenter** で行い、結果 (エラーの文字、色、有効・無効) を、`IView` のプロパティで、Form に伝える。
- `Form` の `Text`・ラベルの文字は、**日本語の固定文字列を、Form に書いてよい** (表示の見出し)。ただし、**状況で変わる文字** (挨拶、エラー) は、Presenter が決める。
- 項目が多い一覧は、`DataGridView` の仮想モード、または、ページングを、検討する。

### 6.3 ダイアログ
- **`MessageBox` / `OpenFileDialog` / `SaveFileDialog` / モーダル・モードレスの Form を、Presenter から直接開かない。** インターフェース (`IDialogService` など) に分け、Form (または、アプリ側の実装クラス) が実装する。Presenter のテストで、偽物に差し替えられる。
- ダイアログの Form (`ShowDialog()`) は、`using` で、破棄する。
- **ダイアログを開く処理は、メニュー (`ToolStripMenuItem`) の `Click` の中で、直接 `ShowDialog` / `MessageBox.Show` を呼ばず、`BeginInvoke` で、`Click` の処理が終わってから、行う。** UIA の `Invoke` (UI テスト・支援技術) は、`Click` の処理が終わるまで戻らず、その中で、ダイアログが閉じるまで戻らないと、以後の UIA の呼び出しが、すべて止まる (実機で確認)。通常のボタン (ウィンドウを持つ) は、UI テストが `BM_CLICK` で押すので、直接でよい。
- **Form に、`IView` のプロパティなど、公開プロパティを足したら、`[Browsable(false)]` と `[DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]` を付ける** (.NET 9 以降の WinForms 解析 `WFO1000` が、デザイナーが保存しない公開プロパティを、ビルドエラーにする)。
- **UI テストと支援技術のために、入力欄・ボタンには、`Name` (= AutomationId) を付け、直前の `Label` の文字が UIA の名前になることがあるので、`AccessibleName` を付ける。**
- (`winforms-check` の WFL002。)

### 6.3.1 リスト・ツリー・日付などの注意 (実機で確認。UI テストの道具は `UiDialogs`)
- **`ListView` は、`View = View.Tile` (並べて表示) と `CheckBoxes = true` を、同時にできない** (`NotSupportedException`。**未処理だと、モーダルの例外ダイアログで UI スレッドが止まり、UI テストが固まる**)。タイルにするときは、`CheckBoxes = false` にして、戻すときに、元に戻す。
- **`Program.cs` に、未処理の例外の受け口を置く** (9.1。`Application.SetUnhandledExceptionMode(CatchException)` と `ThreadException`)。例外のダイアログが出ず、UI テストが固まらない (ログに残る)。
- **UI テストで操作するコントロール:** 列ヘッダーによる並べ替え (`ColumnClick`) は、UIA の `Invoke` では起きない (UI テストは、ヘッダーへ `PostMessage`)。`TabControl` の `TabPage` は、UIA の `TabItem` が信用できない (UI テストは、順番で選ぶ)。`ToolStrip` の項目は、`AutomationId` が空 (表示名で探される)。**`TreeView` のチェックは、`AfterCheck` で受ける** (UI テストは、`Space` キーで切り替える)。**`DateTimePicker`** は、`ValueChanged` で受ける (チェック付きは、チェックの切り替えでも、`ValueChanged` が起きるとは、限らない)。
- (`winforms-check` の WFD008 が、`ListView` の `CheckBoxes = true` と `View.Tile` の組み合わせを、検出する。)

### 6.4 UserControl
- 再利用する UserControl は、**値のプロパティとイベントで、親とやり取りする**。親の Form を、直接参照しない。
- UserControl も、Presenter を持てる (小さな画面部品ごとに、`IView` を実装する)。

## 7. Presenter 規約
- **WinForms の型を使わない** (`Control` / `Form` / `MessageBox` / `Application` / `Timer` (`System.Windows.Forms.Timer`) / `Clipboard`)。`System.Windows.Forms` / `System.Drawing` の `using` も、書かない。
- コンストラクターで、`IView` と、必要なインターフェース (Service、`IDialogService`) を、受け取る。**`new` で、Service を作らない。**
- `IView` のイベントを購読して、状態を更新する。**Presenter の中で、状態を持つのは、画面の状態だけ**にする (業務の状態は、ロジック層)。
- 非同期の処理は、`async Task` で書き、結果を、`IView` に反映する。UI スレッドの扱い (`Invoke`) は、`IView` の実装 (Form) が、引き受ける (8.2)。
- `IView` は、**小さく**保つ。画面の部品を、そのまま露出しない (`TextBox` を返さない。値を返す)。

## 8. スレッド・非同期・長い処理

### 8.1 UI スレッドを、止めない
- **UI スレッドで、長い処理 (ファイル、ネットワーク、DB、重い計算) を実行しない。** `async` / `await` と、`Task.Run` (CPU の重い処理だけ) を使う。
- **`Thread.Sleep` を、Form のコードで呼ばない** (`await Task.Delay` にする。`winforms-check` の WFT002)。
- **`Application.DoEvents()` を使わない** (再入で、状態が壊れる。`winforms-check` の WFT001)。
- `.Result` / `.Wait()` / `GetAwaiter().GetResult()` で、非同期を同期待ちしない (デッドロック。`winforms-check` の ASY001)。`async void` は、イベントハンドラーだけ (ASY002)。

### 8.2 別スレッドから、コントロールを触らない
- コントロールは、**作ったスレッド (UI スレッド) からだけ**触れる。別スレッドからは、`Control.Invoke` / `BeginInvoke`、または、`async` / `await` (`SynchronizationContext` に戻る) を使う。
- **`Control.CheckForIllegalCrossThreadCalls = false` で、誤りを隠さない** (`winforms-check` の WFT003)。
- `BackgroundWorker` は、新しく書かない (`async` / `await` にする)。

## 9. 例外処理・ログ
`csharp-common.md` の「12 例外処理」「13 ログ」を、そのまま適用する (空の `catch` 禁止、`throw ex;` 禁止 (`throw;`)。`winforms-check` の EXC001 / EXC002)。

### 9.1 WinForms 固有の補足
- **未処理の例外の受け口を、`Program.cs` に、1 か所**作る: `Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException)`、`Application.ThreadException` (UI スレッド)、`AppDomain.CurrentDomain.UnhandledException` (それ以外)。ログを残し、ユーザーに、分かる文言で伝える。
- ハンドラーの中の例外を、握りつぶさない。Presenter が、`IView` を通して、エラーを表示する。

## 10. 設定・リソース
- 設定値 (接続先、パスなど) を、コードに、直接書かない。`appsettings.json` などの、設定ファイルから読む。
- 画像・文字列などのリソースは、リソース (`.resx`) に置く。**アイコンのデザイナー (`.resx`) を、手で書き換えない。**
- コントロールが `IDisposable` (`Font`、`Image`、`Brush` など) を、自分で作るときは、`Dispose` する。

## 11. 依存性注入
`csharp-common.md` の「11 依存性注入規約」の考え方を使う。**組み立ては、`Program.cs` (composition root)。** Form の中で、Service を `new` しない (`winforms-check` の WFL004)。小さなアプリでは、手で組み立てる (DI コンテナは、必要になってから)。

## 12. コメント規約
`csharp-common.md` の「15 コメント規約」を、そのまま適用する (コメントは日本語。「なぜ」を書く。`///` は、公開 API)。**`*.Designer.cs` の英語のコメントは、デザイナーが書くので、直さない。**

## 13. テスト規約

### 13.1 単体テスト (MSTest)
`csharp-common.md` の「16 テスト規約」を、そのまま適用する (`メソッド_条件_期待` の名前、1 テスト 1 検証、ファイルは `<クラス名>Tests.cs`)。
- **テストの対象は、Presenter と、ロジック層 / データ層。** `IView` の Fake を作り、イベントを起こして、表示 (プロパティ) の結果を確かめる (生成される `MainPresenterTests` が、手本)。
- **Form (`Forms/`) は、単体テストしない** (UI テスト、または、目視)。
- ロジック層がない構成では、`<アプリ名>.Tests` が、アプリを参照して、`Presenters/` をテストする (TFM は、アプリと同じ `-windows`)。

### 13.2 UI テスト (FlaUI)
- **操作するコントロールの `Name` が、`AutomationId`** (4.2)。`Find("NameTextBox")` で探し、`AsTextBox().Text = "..."` (ValuePattern) / `AsButton().Invoke()` (InvokePattern) で操作する。**マウス・キーボードの入力は、使わない。**
- **流れ: UI テストは、ビルド → テスト (Green) の流れに、含めない。** ユーザーが求めたとき (`build-test-loop` の `references/ui-tests.md`、`uitest_once.sh`)、または、画面を、プロンプトで作りながら、UI テストを先に書いて、繰り返し実行するとき (`/ui-test-first`) に、別に実行する。
- 失敗したら、`.claude-logs/ui-screenshots/*.png` を、画像として読んで、画面の状態を見る。**期待値を、画面の実際の状態に合わせて直すのは、仕様変更のときだけ。アサーションを、弱めない。**

## 14. 禁止事項
- Form に、業務ロジック、データアクセス、`new Service()` を書く
- Presenter / ロジック層 / データ層から、WinForms (`System.Windows.Forms` / `System.Drawing` / `MessageBox` / `Application`) を使う
- `Application.DoEvents()`、Form での `Thread.Sleep()`、UI スレッドでの同期待ち (`.Result` / `.Wait()`)
- `Control.CheckForIllegalCrossThreadCalls = false`
- `InitializeComponent()` の呼び忘れ、`*.Designer.cs` 以外への `InitializeComponent()`、`InitializeComponent()` の中の制御構文
- コントロールの `Name` が、空・重複・変数名と違う
- 座標の直指定だけで、画面を組む
- 空の `catch`、`throw ex;`、`async void` (イベントハンドラー以外)
- テストを通すために、アサーションを弱める・消す

## 15. コードレビュー確認項目
- [ ] Form が、`IView` の実装と、イベントの通知だけになっているか (業務ロジックが、混ざっていないか)
- [ ] Presenter が、WinForms の型を使っていないか。ダイアログは、インターフェース越しか
- [ ] 組み立ては、`Program.cs` の 1 か所か
- [ ] 層の依存の向き (アプリ → ロジック → データ) と、ロジック・データ層の WinForms 非依存
- [ ] コントロールに、役割が分かる `Name` があり、変数名と同じか
- [ ] `*.Designer.cs` が、デザイナーで開ける形か (`InitializeComponent()` に制御構文がない)
- [ ] UI スレッドを、止めていないか。別スレッドから、コントロールを触っていないか
- [ ] 例外を握りつぶしていないか。未処理の例外の受け口が、`Program.cs` にあるか
- [ ] レイアウトが、`Dock` / `Anchor` / `TableLayoutPanel` か。DPI で、崩れないか
- [ ] Presenter とロジックの単体テストがあるか。UI テストの `AutomationId` (= `Name`) が、そろっているか

## 付録: どの規則を、どのツールが確かめるか
**ツールは、機械で判定できる項目だけを、静的に確かめる。** それ以外 (責務の分離の妥当性、`IView` の大きさ、レイアウトの見た目、コメントの質など) は、レビュー (15 章) で確認する。

| 規則 | 確かめるもの |
|---|---|
| 2.2 / 3.1 参照方向、ロジック・データ層が WinForms に依存しない | `winforms-check` WFL001 / WFL003 |
| 2.2 / 7 / 6.3 Presenter が WinForms の型を使わない | `winforms-check` WFL002 |
| 2.3 / 11 Form で Service を `new` しない | `winforms-check` WFL004 |
| 4.2 コントロールの `Name` (空・重複・変数名との違い) | `winforms-check` WFD002 / WFD003 / WFD005 |
| 4.3 bool の名前 | `winforms-check` NAM001 |
| 5.1 `InitializeComponent()` の呼び出し・置き場所・中身、`Controls.Add` | `winforms-check` WFD001 / WFD006 / WFD007 / WFD004 |
| 8.1 / 8.2 UI スレッド、スレッドの誤りの隠蔽 | `winforms-check` WFT001 / WFT002 / WFT003、ASY001 / ASY002 |
| 9 例外 | `winforms-check` EXC001 / EXC002 |
| 5 書式、命名の一部、Nullable | `.editorconfig` (Visual Studio と `dotnet format`)、ビルドの警告 |
| 13 テスト | `build-test-loop` (実行)、`csharp-test-first` (先行。WinForms も同じ手順)、UI テストは `build-test-loop` の `references/ui-tests.md` |

- **Form / Designer / Presenter を編集したら、`winforms-check` を実行する** (ウォッチャーは、要らない)。ビルドとテストは、ウォッチャー経由 (`auto-build` / `build-test-loop`)。
