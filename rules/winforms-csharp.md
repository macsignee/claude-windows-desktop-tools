---
paths:
  - "**/*.Designer.cs"
  - "**/Forms/**/*.cs"
  - "**/Presenters/**/*.cs"
  - "**/*Presenter*.cs"
  - "**/I*View.cs"
---

# WinForms プログラミング規約 (ユーザー共通)

本規約は、WinForms を使用した業務アプリケーションを、複数人で継続的に保守できる状態にすることを目的とします。基本設計として **画面モデル (ViewModel に相当するもの) を必須**とし、画面 (Form) には値の出し入れだけを、画面モデルに振る舞いを、置きます。**WinForms の型がないと書けないもの** (ダイアログを開く、画面遷移の実行、フォーカス、UI スレッドへの戻し) だけは、**Presenter (任意)** に置きます (MVP の考え方を、画面モデルと併用する形)。画面モデルの考え方は、WPF (ViewModel)・MFC (ダイアログ) と共通です。

**適用の順序:**
1. プロジェクトの `CLAUDE.md` に、固有の決まりがあれば、それが最優先。
2. **WinForms のソリューション (`CLAUDE.md` が「WinForms (MVP)」。表記は、生成スクリプトの改訂まで、このまま) では、本規約を適用する。** 共通規約 (`csharp-common.md`。`.cs` を読むときに、自動で読み込まれる) の **C# の部分 (5 C# コーディング規約 / 10 非同期処理 / 11 依存性注入 / 12 例外処理 / 13 ログ / 15 コメント / 16 テスト / 17 禁止事項)** は、そのまま共通で使う。**WPF / XAML / MVVM に固有の節 (6 View / 7 ViewModel / 8 MVVM ライブラリ / 9 データバインディング / 14 XAML) は、適用しない。**
3. C# のクラスライブラリ (`CLAUDE.md` が「C# クラスライブラリ」) は、本規約の「3 層」と「6 テスト」と、`csharp-common.md` を使う。

**この文書は、`*.Designer.cs`、`Forms/` と `Presenters/` の下、`*Presenter*.cs`、`I*View.cs` を読むときに、読み込まれる** (WPF の規約は、読み込まれない)。**`ViewModels/` と `*ViewModel*.cs` は、WPF の規約が読み込まれるファイル名と同じなので、この文書の読み込みの対象に入れていない。WinForms の画面モデルを編集するときは、この文書 (2.2 / 2.4〜2.6 / 7.1) を、自分で読む。**
詳細な書式は、プロジェクトの `.editorconfig` が正 (なければ、`.claude/templates/dotnet/` のひな形)。
「**ツール群の補足**」は、このリポジトリのツール (`new-solution` / `csharp-test-first` / `winforms-check` / `add-package`) との対応。機械で判定できる項目は、**`winforms-check`** が確かめる (付録)。

## 1. 適用範囲
- WinForms アプリケーション、WinForms のクラスライブラリ (UserControl など)
- Form、UserControl、画面モデル、Presenter (任意)、業務ロジック、データアクセス処理
- 単体テスト、UI テスト (FlaUI)
- アプリケーション設定、ログ、例外処理

## 2. 基本方針

### 2.1 使用技術
- .NET (SDK 形式の `.csproj`)、C#、WinForms。ターゲットは、`net8.0-windows` 以降 (`UseWindowsForms`)。
- 単体テストは MSTest。UI テストは FlaUI (UIA3) + MSTest。
- `Nullable` と `ImplicitUsings` は有効 (`Directory.Build.props`)。

### 2.2 責務の分離 (画面モデル + 任意の Presenter)
```
Form ──(状態は直接読む・操作を呼ぶ)──▶ 画面モデル ──▶ リポジトリ (インターフェース)
  │                                     ▲
  └─(IView)─ Presenter (任意) ───────────┘
        ダイアログ・遷移の実行・フォーカス・UI スレッド
```
| 部品 | 役割 | 書いてよいもの | 書いてはいけないもの |
|---|---|---|---|
| **Form (View)** | 画面の表示と、入力の受け取り | コントロールの配置、画面モデルの状態の表示 (`BindingSource`、または通知を受けた代入)、画面モデルの操作の呼び出し、画面固有の処理 (タブ順、アニメーション) | 業務ロジック、入力の検査の判断、データアクセス、`new Service()` |
| **画面モデル** | 画面の状態、規則、操作とその実行可否、入力の検査、変更の通知、リポジトリの呼び出し | 状態のプロパティ、操作のメソッドと `CanXxx`、検査 (`Errors`)、`INotifyPropertyChanged`、リポジトリのインターフェースの呼び出し | WinForms の型、`MessageBox`、`Application`、UI スレッドの扱い |
| **IView** (任意。Presenter があるときだけ) | Presenter から見た Form の姿。**小さな窓口** | `ShowMessage`・`Close`・`SetFocus` のようなメソッド、イベント | **状態のプロパティ**、WinForms の型 (`Control` / `Form` / `MessageBox`) |
| **Presenter** (任意) | WinForms の型がないと書けないものだけ: ダイアログ (`IDialogService` 越し)、画面遷移の実行、フォーカス、UI スレッドへの戻し、Form の開閉 | `IView`、画面モデル、`IDialogService` の呼び出し | WinForms の型、`MessageBox`、`Application`、**状態**、**規則** |
| **ロジック / データ層** | 業務ロジック、データアクセス。**画面モデルは、ロジック層に置く** | 業務の処理 | WinForms への依存 (`UseWindowsForms`、`System.Windows.Forms`、`System.Drawing`) |

- **境界の判断基準:** **WinForms の型・機能がないと書けない → Presenter。別の UI (WPF・MFC) でも同じ内容になる → 画面モデル。** 画面遷移は、「どこへ進むか」の判断が画面モデル (結果として返す)、「開く」の実行が Presenter。
- **状態は、画面モデルだけが持つ。** `IView` に、状態のプロパティを写さない。Form は、画面モデルの状態を直接読む。
- **規則は、Presenter に置かない。** 入力の検査、実行可否、状況で変わる文言は、画面モデルが決める。
- **Presenter は、必要なときだけ置く。** 表示と操作の呼び出しだけで足りる単純な画面・ダイアログは、Form が、画面モデルに直接つなぐ。ダイアログ・遷移・フォーカスの処理が出てきたときに、足す。
- (`winforms-check` の WFL001 / WFL002 / WFL004 が検査する。**画面モデルをロジック層に置く限り、WinForms の混入は WFL001 が検査する。** `ViewModels/` や名前の末尾 `ViewModel` による検査は、まだない。)
- **画面モデルの契約** (2.4)、**ダイアログのデータの規則** (2.5)、**戻りの規則** (2.6) は、以下のとおり。

### 2.3 組み立てる場所 (composition root)
- **Form・画面モデル・Presenter (あるとき) を作って結ぶのは、`Program.cs` の 1 か所**にする。Form の中で、画面モデル・Presenter・Service を `new` しない。
- DI コンテナを導入するときも、ここで構成する。依存は、**コンストラクターで、インターフェースを受け取る**。
- **ツール群の補足:** 生成されるアプリは、現状、`Program.Main` で `ApplicationConfiguration.Initialize()` → `new MainForm()` → `new MainPresenter(form)` → `Application.Run(form)` の順 (画面モデルを足した形への改訂は、ひな形の段階で行う)。

### 2.4 画面モデルの契約
画面モデルは、次の五つを公開する。UI の枠組みによらない (WPF・MFC の画面モデルと同じ考え方)。

| 項目 | 内容 | 例 |
|---|---|---|
| 状態 | Form が表示する値 (入力欄の値、表示専用の値、一覧、選択) | `Name`、`Greeting`、`Items` |
| 操作 | Form から呼ぶメソッド。**操作ごとに、実行できるか (`CanXxx`) も公開する** (ボタンの有効 / 無効になる) | `Save()` と `CanSave` |
| 検査 | 入力の誤りと、その文言。Form は表示するだけ | `Errors`、`HasErrors` |
| 変更の通知 | 状態・検査・実行可否が変わったことを、Form に知らせる (`INotifyPropertyChanged`) | `PropertyChanged` |
| 結果 | 確定・取消・失敗を、Form が閉じる・エラー表示に使える形で返す | `Commit()` の戻り値 |

- WinForms に `ICommand` は要らない (操作はメソッド、実行可否は `CanXxx`)。
- **通知は、呼び出されたスレッドで上げる。** UI スレッドへの戻しは、Form か Presenter が行う (8.2)。画面モデルは、UI スレッドを知らない。
- **Form の受け方:** 状態は `BindingSource` による `DataBindings`、または、通知を受けて、コントロールへ代入する。ボタンの `Click` は、画面モデルのメソッドを呼ぶ 1 行にする。実行可否は、通知を受けて `Enabled` に代入する。

### 2.5 ダイアログ・画面のデータ
- **ダイアログ・画面にも、画面モデルを置く。** 入力値のまとめ、ダイアログが返す結果のような**データのクラス**は、画面モデルが公開する値として、**ロジック層に、別のファイルで置く** (UI の型は使わない)。データ層 (データベース・API の違いを隠す、リポジトリ的なもの) には、置かない。純粋な規則 (入力の検査 `IsValid()` / `Validate()`、表示用の派生値) は、データのクラスか画面モデルが持つ。
- **モーダルなダイアログは、確定 (OK) するまで、渡されたデータを変更しない。** 編集中の値は、**画面モデルの内部**に持ち、入力中の検査は、その値で行う。**確定 (`Commit`) するまで、リポジトリにも書かない。** 取消・× では、何も変わらない。
- **モードレスなウィンドウは、OK がないので、持っているデータ (コピーでなく、共有するデータそのもの) を、入力のたびに、すぐ更新し、変更を通知する (`INotifyPropertyChanged`)。メインなど、ほかの画面も、すぐ追従する (逆向きも)。不正な値は、反映せず、エラーを示す (勝手に元に戻さない)。閉じても、変更は、取り消さない。「開く」を押し直したときは、すでにあるウィンドウを前面に出す (単一インスタンス。Presenter か、開くサービス `IXxxDialogService` が行う)。メインを閉じると、閉じる。共有するデータは、変更通知を持つクラス (ロジック層)。

### 2.6 戻りの規則
画面を作っている途中で、**画面モデルに、必要なものが足りない**と分かったら、Form・Presenter の中で補わない。**ロジック層に戻り、単体テストを先に書いて、画面モデルに足す。** 足りないのは、たとえば、画面に出す整形済みの文字列、確定前の一時的な値、実行可否の条件である。Form や Presenter に入れると、規則が、単体テストの外 (フォームを起動しないと確かめられない場所) に出る。
- 戻る回数を減らすには、最初から、画面モデルの契約 (2.4) の五つ (特に、実行可否・検査・通知) を、そろえておく。
- 画面モデルのインターフェースの意味を変えるときは、ユーザーの承認を取り、契約テストと、Fake (画面モデルの Fake があるとき) にも反映する。
- 機械で確かめられるのは、**Form が、`new XxxRepository()` などで、データアクセスを生成していないこと** (WFL004) と、層の参照の向き (WFL003) までである。**Form が、リポジトリ・データ層を、型として直接参照する検査は、まだない (予定)。** ほかは、レビュー (15 章) と、設計の記録に残した「戻った」履歴で確かめる。

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
    Presenters/              ← Presenter と IView (任意。WinForms の型を使うものは、ここ)
  LogicLayer/                ← 画面モデル (ViewModels/)・業務ロジック (WinForms 非依存。net10.0)
  DataLayer/                 ← データアクセス (net10.0)
  LogicLayer.Tests/ …        ← MSTest
  App.UITests/               ← FlaUI (必要なとき)
```
- **依存の向き: アプリ → ロジック → データ。** 逆向きの参照は禁止 (`winforms-check` の WFL003)。
- **ロジック層・データ層は、WinForms 非依存** (`net10.0` などの Windows 非依存。`UseWindowsForms` / `-windows` を付けない。`System.Windows.Forms` / `System.Drawing` を使わない)。付けると、ビルドで落ちるのではなく、**黙って、依存が混ざる**ので、`winforms-check` の WFL001 が確かめる。
- ロジック層がない小さなアプリでは、画面モデルは、アプリの `ViewModels/` に置いてよい (WinForms の型は使わない)。**業務ロジックが増えたら、ロジック層に切り出す。** Presenter は、`IView` を介して Form を知るだけで、WinForms の型を使わないので、ロジック層に置いてもよい。

### 3.2 層の名前
既定は `LogicLayer` / `DataLayer`。作成後に、個々の事情に応じて、リネームしてよい (手順は `DLL-LAYOUT.md`。名前を変えたら、プロジェクト・名前空間・`CLAUDE.md` をそろえる)。名前が既定と違うときは、`winforms-check` に、`--logic <名前>` / `--data <名前>` で伝える。

## 4. 命名規約

### 4.1 型・メンバー
- 型・メソッド・プロパティは PascalCase、private フィールドは `_camelCase`、インターフェースは `I` 接頭辞 (C# の共通規約。`.editorconfig` が、提案として示す)。
- Form は `<画面名>Form`、**画面モデルは `<画面名>ViewModel`** (名前は暫定。WPF の ViewModel と、呼び名をそろえる)、Presenter は `<画面名>Presenter`、View のインターフェースは `I<画面名>View`。

### 4.2 コントロール (最重要)
- **すべてのコントロールに、役割が分かる `Name` を付ける。** `<役割><型>` の形 (`NameTextBox` / `SaveButton` / `OrderGrid` / `StatusLabel`)。`textBox1` / `button1` のままにしない。
- **`Name` は、フィールド (変数) 名と同じ文字列にする** (`NameTextBox.Name = "NameTextBox";`)。デザイナーが、そうしてくれる。コードで作るときも、そろえる。
- **理由:** `Name` は、UI テスト (FlaUI) の **`AutomationId`** になる。Name が空・重複・変数名と違うと、UI テストが、要素を探せない (`winforms-check` の WFD002 / WFD003 / WFD005)。
- 画面のレイアウト用のコンテナ (`TableLayoutPanel` など) にも、`Name` を付ける。
- **画面モデルの状態、`IView` のメンバーの名前は、`Form.Name` などの継承メンバーと、衝突させない** (`Name` ではなく、`PersonName` など、役割の名前にする)。

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
- ハンドラーは、**画面モデルのメソッドの呼び出し (または、Presenter へのイベント通知) だけ**にする。

## 6. 画面 (Form) 規約

### 6.1 レイアウトと DPI
- **`TableLayoutPanel` / `FlowLayoutPanel` と、`Dock` / `Anchor` で配置する。** 座標 (`Location`) の直指定で、並べない (DPI・フォント・ウィンドウの大きさで崩れる)。
- `AutoScaleMode = AutoScaleMode.Font` (または `Dpi`)、`MinimumSize` を設定する。高 DPI は、`ApplicationConfiguration.Initialize()` に任せる。
- 余白・フォントは、画面で、そろえる。画面ごとに、ばらばらの値を書かない。
- タブ順 (`TabIndex`) を、操作の順に、そろえる。キーボードだけで、操作できるようにする (`AcceptButton` / `CancelButton`、ショートカット)。

### 6.2 入力と表示
- 入力の検査 (必須、形式、範囲) の**判断は、画面モデル**で行い、結果 (エラーの文字、有効・無効) は、画面モデルの検査・`CanXxx` として公開する。Form は、それを表示するだけ。色などの見た目は、Form が決めてよい。
- `Form` の `Text`・ラベルの文字は、**日本語の固定文字列を、Form に書いてよい** (表示の見出し)。ただし、**状況で変わる文字** (挨拶、エラー) は、画面モデルが決める。
- 項目が多い一覧は、`DataGridView` の仮想モード、または、ページングを、検討する。

### 6.3 ダイアログ
- **`MessageBox` / `OpenFileDialog` / `SaveFileDialog` / モーダル・モードレスの Form を、画面モデル・Presenter から直接開かない。** インターフェース (`IDialogService` など) に分け、Form (または、アプリ側の実装クラス) が実装する。テストで、偽物に差し替えられる。**ダイアログを開く「実行」は Presenter (または、アプリ側のサービス)、開くかどうか・どの値を渡すかの「判断」は、画面モデルの結果。**
- ダイアログの Form (`ShowDialog()`) は、`using` で、破棄する。
- **ダイアログを開く処理は、メニュー (`ToolStripMenuItem`) の `Click` の中で、直接 `ShowDialog` / `MessageBox.Show` を呼ばず、`BeginInvoke` で、`Click` の処理が終わってから、行う。** UIA の `Invoke` (UI テスト・支援技術) は、`Click` の処理が終わるまで戻らず、その中で、ダイアログが閉じるまで戻らないと、以後の UIA の呼び出しが、すべて止まる (実機で確認)。通常のボタン (ウィンドウを持つ) は、UI テストが `BM_CLICK` で押すので、直接でよい。
- **Form に、`IView` のメンバーなど、公開プロパティを足したら、`[Browsable(false)]` と `[DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]` を付ける** (.NET 9 以降の WinForms 解析 `WFO1000` が、デザイナーが保存しない公開プロパティを、ビルドエラーにする)。
- **UI テストと支援技術のために、入力欄・ボタンには、`Name` (= AutomationId) を付け、直前の `Label` の文字が UIA の名前になることがあるので、`AccessibleName` を付ける。**
- (`winforms-check` の WFL002。)

### 6.3.1 リスト・ツリー・日付などの注意 (実機で確認。UI テストの道具は `UiDialogs`)
- **`ListView` は、`View = View.Tile` (並べて表示) と `CheckBoxes = true` を、同時にできない** (`NotSupportedException`。**未処理だと、モーダルの例外ダイアログで UI スレッドが止まり、UI テストが固まる**)。タイルにするときは、`CheckBoxes = false` にして、戻すときに、元に戻す。
- **`Program.cs` に、未処理の例外の受け口を置く** (9.1。`Application.SetUnhandledExceptionMode(CatchException)` と `ThreadException`)。例外のダイアログが出ず、UI テストが固まらない (ログに残る)。
- **UI テストで操作するコントロール:** 列ヘッダーによる並べ替え (`ColumnClick`) は、UIA の `Invoke` では起きない (UI テストは、ヘッダーへ `PostMessage`)。`TabControl` の `TabPage` は、UIA の `TabItem` が信用できない (UI テストは、順番で選ぶ)。`ToolStrip` の項目は、`AutomationId` が空 (表示名で探される)。**`TreeView` のチェックは、`AfterCheck` で受ける** (UI テストは、`Space` キーで切り替える)。**`DateTimePicker`** は、`ValueChanged` で受ける (チェック付きは、チェックの切り替えでも、`ValueChanged` が起きるとは、限らない)。
- (`winforms-check` の WFD008 が、`ListView` の `CheckBoxes = true` と `View.Tile` の組み合わせを、検出する。)

### 6.4 UserControl
- 再利用する UserControl は、**値のプロパティとイベントで、親とやり取りする**。親の Form を、直接参照しない。
- UserControl も、画面モデルを持てる (小さな画面部品ごとに、画面モデルを持ち、親の画面モデルから渡す)。WinForms 固有の処理が要るときだけ、Presenter と `IView` を足す。

## 7. 画面モデル規約・Presenter 規約

### 7.1 画面モデル
- **WinForms の型を使わない** (`Control` / `Form` / `MessageBox` / `Application` / `Timer` / `Clipboard`、`System.Windows.Forms` / `System.Drawing` の `using` も)。**UI スレッド (`Invoke`) も知らない。**
- コンストラクターで、リポジトリなどのインターフェース (`IDialogService` は、画面モデルが使うときだけ) を、受け取る。**`new` で、Service を作らない。**
- 非同期の処理は、`async Task` で書く。実行中・失敗の状態も、状態として公開する。
- **単体テストを先に書く** (`csharp-test-first`)。リポジトリは、Fake を渡す。

### 7.2 Presenter (任意)
- **WinForms の型を使わない** (7.1 と同じ)。
- コンストラクターで、`IView`・画面モデル・必要なインターフェース (`IDialogService`) を、受け取る。**`new` で、Service を作らない。**
- 画面モデルの通知・結果に応じて、`IView` を呼ぶ (ダイアログを開く、閉じる、フォーカスを移す)。UI スレッドへの戻しは、`IView` の実装 (Form) が引き受ける (8.2)。
- `IView` は、小さく保つ。画面の部品を露出せず、状態のプロパティも足さない (足したくなったら、画面モデルに足す。2.6)。

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
- ハンドラーの中の例外を、握りつぶさない。画面モデルが、エラーを状態 (検査・失敗) として公開し、Form が表示する (ダイアログで知らせるときは、Presenter が `IDialogService` を通す)。

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
- **テストの対象は、画面モデル、Presenter (あるとき)、ロジック層 / データ層。** **画面モデルは、リポジトリの Fake を渡し、メソッドを呼んで、状態・実行可否・検査・通知を確かめる** (Form も `IView` の偽物も、要らない)。Presenter は、`IView` の Fake を作り、遷移・ダイアログ・フォーカスだけを確かめる (現状の生成物の `MainPresenterTests` は、改訂前の形)。
- **Form (`Forms/`) は、単体テストしない** (UI テスト、または、目視)。
- ロジック層がない構成では、`<アプリ名>.Tests` が、アプリを参照して、`ViewModels/` と `Presenters/` をテストする (TFM は、アプリと同じ `-windows`)。

### 13.2 UI テスト (FlaUI)
- **操作するコントロールの `Name` が、`AutomationId`** (4.2)。`Find("NameTextBox")` で探し、`AsTextBox().Text = "..."` (ValuePattern) / `AsButton().Invoke()` (InvokePattern) で操作する。**マウス・キーボードの入力は、使わない。**
- **流れ: UI テストは、ビルド → テスト (Green) の流れに、含めない。** ユーザーが求めたとき (`build-test-loop` の `references/ui-tests.md`、`uitest_once.sh`)、または、画面を、プロンプトで作りながら、UI テストを先に書いて、繰り返し実行するとき (`/ui-test-first`) に、別に実行する。
- 失敗したら、`.claude-logs/ui-screenshots/*.png` を、画像として読んで、画面の状態を見る。**期待値を、画面の実際の状態に合わせて直すのは、仕様変更のときだけ。アサーションを、弱めない。**

## 14. 禁止事項
- Form に、業務ロジック、データアクセス、`new Service()` を書く (画面モデルに足りないものを、Form・Presenter の中で補う)
- `IView` に、状態のプロパティを足す。Presenter に、規則を置く
- 画面モデル / Presenter / ロジック層 / データ層から、WinForms (`System.Windows.Forms` / `System.Drawing` / `MessageBox` / `Application`) を使う
- `Application.DoEvents()`、Form での `Thread.Sleep()`、UI スレッドでの同期待ち (`.Result` / `.Wait()`)
- `Control.CheckForIllegalCrossThreadCalls = false`
- `InitializeComponent()` の呼び忘れ、`*.Designer.cs` 以外への `InitializeComponent()`、`InitializeComponent()` の中の制御構文
- コントロールの `Name` が、空・重複・変数名と違う
- 座標の直指定だけで、画面を組む
- 空の `catch`、`throw ex;`、`async void` (イベントハンドラー以外)
- テストを通すために、アサーションを弱める・消す

## 15. コードレビュー確認項目
- [ ] Form が、画面モデルの表示と操作の呼び出しだけになっているか (業務ロジックが、混ざっていないか)
- [ ] 状態を、画面モデルだけが持っているか。`IView` に状態のプロパティがないか。規則が Presenter にないか
- [ ] 単純な画面に、不要な Presenter を置いていないか。画面モデルに足りないものを、Form・Presenter で補っていないか (戻りの規則)
- [ ] 画面モデル・Presenter が、WinForms の型を使っていないか。ダイアログは、インターフェース越しか
- [ ] 組み立ては、`Program.cs` の 1 か所か
- [ ] 層の依存の向き (アプリ → ロジック → データ) と、ロジック・データ層の WinForms 非依存
- [ ] コントロールに、役割が分かる `Name` があり、変数名と同じか
- [ ] `*.Designer.cs` が、デザイナーで開ける形か (`InitializeComponent()` に制御構文がない)
- [ ] UI スレッドを、止めていないか。別スレッドから、コントロールを触っていないか
- [ ] 例外を握りつぶしていないか。未処理の例外の受け口が、`Program.cs` にあるか
- [ ] レイアウトが、`Dock` / `Anchor` / `TableLayoutPanel` か。DPI で、崩れないか
- [ ] 画面モデル・Presenter (あるとき)・ロジックの単体テストがあるか。UI テストの `AutomationId` (= `Name`) が、そろっているか

## 付録: どの規則を、どのツールが確かめるか
**ツールは、機械で判定できる項目だけを、静的に確かめる。** それ以外 (責務の分離の妥当性、画面モデルと Presenter の境界、`IView` の大きさ、レイアウトの見た目、コメントの質など) は、レビュー (15 章) で確認する。

| 規則 | 確かめるもの |
|---|---|
| 2.2 / 3.1 参照方向、ロジック・データ層が WinForms に依存しない | `winforms-check` WFL001 / WFL003 |
| 2.2 / 7 / 6.3 Presenter が WinForms の型を使わない | `winforms-check` WFL002 |
| 2.2 / 7.1 画面モデルが WinForms の型を使わない | ロジック層に置く限り `winforms-check` WFL001。**`ViewModels/`・名前による検査は未実装 (予定)** |
| 2.6 Form が、データアクセスを `new` しない、層の参照の向き | `winforms-check` WFL004 / WFL003。**Form のデータ層の直接参照の検査は、未実装 (予定)。** それ以外の戻りの規則は、レビュー |
| 2.3 / 11 Form で Service を `new` しない | `winforms-check` WFL004 |
| 4.2 コントロールの `Name` (空・重複・変数名との違い) | `winforms-check` WFD002 / WFD003 / WFD005 |
| 4.3 bool の名前 | `winforms-check` NAM001 |
| 5.1 `InitializeComponent()` の呼び出し・置き場所・中身、`Controls.Add` | `winforms-check` WFD001 / WFD006 / WFD007 / WFD004 |
| 8.1 / 8.2 UI スレッド、スレッドの誤りの隠蔽 | `winforms-check` WFT001 / WFT002 / WFT003、ASY001 / ASY002 |
| 9 例外 | `winforms-check` EXC001 / EXC002 |
| 5 書式、命名の一部、Nullable | `.editorconfig` (Visual Studio と `dotnet format`)、ビルドの警告 |
| 13 テスト | `build-test-loop` (実行)、`csharp-test-first` (先行。WinForms も同じ手順)、UI テストは `build-test-loop` の `references/ui-tests.md` |

- **Form / Designer / 画面モデル / Presenter を編集したら、`winforms-check` を実行する** (ウォッチャーは、要らない)。ビルドとテストは、ウォッチャー経由 (`auto-build` / `build-test-loop`)。
