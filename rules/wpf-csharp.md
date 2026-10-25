---
paths:
  - "**/*.cs"
  - "**/*.xaml"
  - "**/*.csproj"
---

# WPF プログラミング規約 (ユーザー共通)

本規約は、WPF を使用した業務アプリケーションを、複数人で継続的に保守できる状態にすることを目的とします。基本設計として **MVVM を必須**とし、MVVM Toolkit や Prism などのライブラリは、プロジェクトの規模や要件に応じて、後から選択・導入できる構成とします。

**プロジェクトの `CLAUDE.md` に、固有の決まりがあれば、そちらを優先する。** 詳細な書式は、プロジェクトの `.editorconfig` が正 (なければ、`~/.claude/templates/dotnet/` のひな形)。
C++ / MFC の規約 (`cpp-mfc.md`) と、同じ方針の項目 (ファイルの形式、括弧、コメントの言語) は、そろえてある。
「**ツール群の補足**」は、このリポジトリのツール (`new-solution` / `wpf-test-first` / `wpf-check` / `add-package`) との対応や、規約を補う決まり。

## 1. 適用範囲
本規約は、次の成果物に適用する。

- WPF アプリケーション、WPF クラスライブラリ
- View、ViewModel、Model
- 業務ロジック、データアクセス処理
- 単体テスト
- XAML リソース、スタイル、テンプレート
- アプリケーション設定、ログ、例外処理

## 2. 基本方針

### 2.1 使用技術
次を標準とする。

| 項目 | 標準 |
|---|---|
| 言語 | C# |
| UI フレームワーク | WPF |
| 実行基盤 | サポート期間内の .NET |
| UI 定義 | XAML |
| アーキテクチャ | MVVM |
| パッケージ管理 | NuGet |
| テスト | xUnit、NUnit、MSTest のいずれか |

- 新規プロジェクトでは、特別な理由がない限り .NET Framework ではなく、**現在サポートされている .NET** を使用する。.NET 版 WPF では、最新の .NET API、言語機能、アクセシビリティ、信頼性、ツール改善などの恩恵を受けられる。
- **ツール群の補足:** `new-solution --type wpf` は、**MSTest** のプロジェクトを作る。ウォッチャー (`dotnet test --logger trx`) と、`wpf-test-first` が検証しているのは、MSTest (v3、VSTest モード) だけ。xUnit / NUnit は、動く見込みだが、未検証。**`TargetFramework` は、プロジェクトの `.csproj` を、先に確認する** (既定は `net10.0`、アプリは `net10.0-windows`。`--tfm` で変えられる)。
- **パッケージの追加は、`add-package` Skill で行う** (`.csproj` に、名前とバージョンを、推測で書かない。バージョンは、固定する)。
- **警告を消すための `#pragma warning disable` / `<NoWarn>` / `TreatWarningsAsErrors` の解除は、ユーザーの許可なしに、しない。**

### 2.2 MVVM の採用
すべての画面は、原則として次の 3 要素に分離する。

- **View:** 画面の構造、見た目、UI 固有動作
- **ViewModel:** 画面の状態、表示用データ、コマンド
- **Model:** 業務データ、業務ルール、外部サービスとの連携

**View は ViewModel を参照できるが、ViewModel から View を直接参照してはいけない。**

```
View
  ↓ Binding / Command
ViewModel
  ↓ Use / Call
Model・Service
```

MVVM によって、UI とプレゼンテーションロジック、業務ロジックを分離すると、テスト、保守、機能変更が容易になる。

## 3. ソリューション構成

### 3.1 基本構成 (小規模)
小規模なアプリケーションでは、次の構成を標準とする。

```
SampleApp.sln
├── SampleApp
│   ├── App.xaml
│   ├── App.xaml.cs
│   ├── Views
│   ├── ViewModels
│   ├── Models
│   ├── Services
│   ├── Behaviors
│   ├── Converters
│   ├── Resources
│   └── Infrastructure
└── SampleApp.Tests
    ├── ViewModels
    ├── Models
    └── Services
```

### 3.2 中規模以上の構成
業務規模が大きい場合は、責務ごとにプロジェクトを分割する。

```
SampleApp.sln
├── SampleApp.Presentation
│   ├── Views
│   ├── ViewModels
│   ├── Behaviors
│   └── Converters
├── SampleApp.Application
│   ├── Services
│   ├── UseCases
│   └── Interfaces
├── SampleApp.Domain
│   ├── Entities
│   ├── ValueObjects
│   └── DomainServices
├── SampleApp.Infrastructure
│   ├── Repositories
│   ├── FileSystem
│   └── ExternalServices
└── SampleApp.Tests
```

参照方向は次のようにする。

```
Presentation → Application → Domain
Infrastructure → Application / Domain
```

**Domain から Presentation、WPF、データベース実装を参照してはいけない。**

### ツール群の補足: 生成される構成と、2 つの層のモデル
`new-solution --type wpf` が作る構成は、次のとおり。**アプリ (`Views/` `ViewModels/` `Resources/` を持つ) と、WPF 非依存のクラスライブラリの層**に分ける。

```
MyApp.slnx
├── MyApp                      WPF アプリ (App.xaml、Views、Resources。--layers に viewmodel がなければ ViewModels も)
├── ViewModels (+ .Tests)      --layers viewmodel
├── LogicLayer (+ .Tests)      --layers logic
└── DataLayer (+ .Tests)       --layers data
```

- **依存の向きのモデルは、プロジェクトの名前で決まる (`wpf-check` が検査する。混ぜない)。**
  - 名前が **`Presentation` / `Application` / `Domain` / `Infrastructure`** (`SampleApp.Domain` のように、末尾が一致するもの) → **3.2 の標準の依存**で検査する。Domain は、何も参照しない。Application は Domain だけ。Infrastructure は Application / Domain。Domain / Application / Infrastructure は、WPF に依存しない (`UseWPF` や `System.Windows` を使わない)。
  - それ以外 (`ViewModels` / `LogicLayer` / `DataLayer`) → **View → ViewModel → ロジック → データ**の向きで検査する (逆向きの参照を作らない)。
  - `--logic` / `--data` / `--viewmodel` で、名前による推定を、上書きできる。
- **3.2 の構成は、`new-solution --layers data:SampleApp.Domain,logic:SampleApp.Application,viewmodel:SampleApp.Presentation` のように、`.` 区切りの名前で作れる** (名前が、そのまま、名前空間になる)。`Infrastructure` や、3.2 の細かいフォルダ (`UseCases` `Entities` など) は、`wpf-test-first` の `add_project.py` (名前に `.` を含めてよい) と、手で、足す。
- 3.1 のフォルダ (`Models` `Services` `Behaviors` `Converters` `Infrastructure`) は、**必要になったときに作る** (空のフォルダを、先に作らない)。生成される小規模の構成は、`Views` / `ViewModels` / `Resources` と `App`。
- **ViewModel・ロジック・データのクラスライブラリは、WPF 非依存** (`net10.0`、`UseWPF` なし)。ViewModel が `System.Windows` の型を使うと、**ビルドが通らない**ので、型システムが、View への依存を防ぐ。
- テストは、**ライブラリごと**に `<名前>.Tests` (3.1 の `SampleApp.Tests` は、1 プロジェクトに、まとめた形)。

## 4. 命名規約

### 4.1 基本規則
| 対象 | 規則 | 例 |
|---|---|---|
| 名前空間 | PascalCase | `Company.Product.Views` |
| クラス | PascalCase | `CustomerService` |
| インターフェイス | `I` + PascalCase | `ICustomerService` |
| メソッド | PascalCase | `LoadCustomersAsync` |
| public プロパティ | PascalCase | `SelectedCustomer` |
| private フィールド | `_` + camelCase | `_customerService` |
| ローカル変数 | camelCase | `customerList` |
| 定数 | PascalCase | `DefaultTimeout` |
| 非同期メソッド | `Async` を付ける | `SaveAsync` |
| View | 機能名 + `View` | `CustomerListView` |
| ViewModel | 機能名 + `ViewModel` | `CustomerListViewModel` |
| Window | 機能名 + `Window` | `SettingsWindow` |
| UserControl | 機能名 + `View` | `SearchConditionView` |

- **ツール群の補足:** ファイル名は、型の名前と一致させる (`MainViewModel` は `MainViewModel.cs`。XAML は `MainWindow.xaml` と `MainWindow.xaml.cs`)。コマンドのプロパティは `XxxCommand`、コンバーターは `XxxConverter`。**定数は PascalCase** (すべて大文字にしない。C++ の `constexpr` の規則とは違う。.NET の慣習)。`public` なフィールドは、持たない (プロパティにする。**WPF は、フィールドをバインドできない**)。**`Async` は、イベントハンドラと、`ICommand` の実装を除く。**

### 4.2 boolean の命名
boolean 型には、状態や判定であることが分かる名前を付ける。

```csharp
public bool IsEnabled { get; }
public bool HasErrors { get; }
public bool CanSave { get; }
```

次のような曖昧な名前は、使用しない。

```csharp
public bool Flag { get; }     // 禁止
public bool Status { get; }   // 禁止
public bool Check { get; }    // 禁止
```

(`wpf-check` の NAM001 が検出する。)

## 5. C# コーディング規約

### 5.1 Nullable 参照型
新規プロジェクトでは Nullable 参照型を有効にする。

```xml
<PropertyGroup>
  <Nullable>enable</Nullable>
  <ImplicitUsings>enable</ImplicitUsings>
  <UseWPF>true</UseWPF>
</PropertyGroup>
```

警告を安易に `!` で抑制してはいけない。

```csharp
// 非推奨
var name = customer!.Name;
```

`!` を使用する場合は、null にならない根拠が、コードまたはコメントから判断できるようにする。引数の検査は、`ArgumentNullException.ThrowIfNull`。

- **ツール群の補足:** `Nullable` / `ImplicitUsings` / `LangVersion` は、ソリューション直下の `Directory.Build.props` で、そろえる (各 `.csproj` には書かない)。`UseWPF` は、WPF アプリだけに付ける (層のライブラリには、付けない)。

### 5.2 var の使用
右辺から型が明確な場合は `var` を使用できる。

```csharp
var customer = new Customer();
var customers = await service.GetCustomersAsync();
```

型が分かりにくくなる場合は、明示する。

```csharp
Customer? selectedCustomer = FindCustomer(id);
```

組み込み型 (`int` `string` など) は、型を書く。

### 5.3 アクセス修飾子
**アクセス修飾子は、省略しない。**

```csharp
private readonly ICustomerService _customerService;

public CustomerViewModel(ICustomerService customerService)
{
    _customerService = customerService;
}
```

型を `public` にしないと、テストプロジェクトから見えない (`CS0122`)。

### 5.4 readonly
コンストラクターで設定後に変更しないフィールドは、`readonly` にする。

### 5.5 メソッドサイズ
1 つのメソッドには、1 つの処理目的だけを持たせる。

目安として、メソッドが次の状態になった場合は、分割を検討する。

- 30 行を大きく超える
- `if`、`for`、`try` のネストが深い
- メソッド名だけで処理を説明できない
- 複数の業務処理を連続して実行している

### ツール群の補足: 書式
- ファイルの形式: 手書き・新規の `.cs` / `.xaml` / `.csproj` は **UTF-8 (BOM 付き)、CRLF**。インデントは、`.cs` / `.xaml` がスペース 4、`.csproj` / `.props` がスペース 2。`.slnx` / `.json` / `.md` は BOM なし。
- **`obj/` と `bin/` と `*.g.cs` は、編集しない** (次のビルドで、上書きされる)。XAML のコンパイルエラー (`MC` / `XDG`) は、元の `.xaml` / `.cs` を直す。ウィザード生成の書式は、直さない (差分が、全行に広がるため)。
- 既存の **Shift-JIS の `.cs` は、編集の前に、UTF-8 (BOM 付き) に変換する** (`~/.claude/scripts/convert_to_utf8_bom.py`。変換だけの、別のコミット)。
- 括弧は **Allman** (開き括弧は、次の行の頭)。**`if` / `for` / `foreach` / `while` の本体は、1 行でも、波括弧を付ける。** 名前空間は、ファイルスコープ (`namespace X;`)。`using` は、名前空間の外、`System` が先頭。整形は `dotnet format`。
- **XAML:** 属性が多い要素 (目安: 3 個以上、または 100 文字超) は、**1 行に 1 属性**にする。属性の順は、`x:Name` / `x:Key` → レイアウト (`Grid.Row` `Margin` など) → 見た目 → バインディング → イベント。

## 6. View 規約

### 6.1 View の責務
View には、次の内容を記述する。

- レイアウト
- コントロール
- スタイル
- データバインディング
- UI 固有のアニメーション
- フォーカス制御
- ドラッグ操作などの UI 固有処理

WPF は、XAML による外観と、コードによる動作の分離を、基本機能として提供している。

### 6.2 コードビハインド
**コードビハインドに、業務ロジックを記述してはいけない。**

```csharp
// 禁止例
private void SaveButton_Click(object sender, RoutedEventArgs e)
{
    var customer = database.Customers.Find(CustomerId);
    customer.Name = NameTextBox.Text;
    database.SaveChanges();
}
```

コードビハインドには、以下のような View 固有処理のみ記述できる。

```csharp
private void Window_Loaded(object sender, RoutedEventArgs e)
{
    SearchTextBox.Focus();
}
```

許可される代表例は、次のとおり。

- フォーカス設定
- スクロール位置制御
- アニメーション開始
- ウィンドウサイズ・位置調整
- View 固有イベントから Behavior への受け渡し
- ViewModel に依存しない UI 処理

### 6.3 イベントよりコマンドを優先
ボタン、メニューなどのユーザー操作には、原則として `ICommand` を使用する。

```xml
<Button
    Content="保存"
    Command="{Binding SaveCommand}" />
```

WPF のコマンド機構は、入力操作と実行ロジックを分離するための仕組みである。
- **ツール群の補足:** コマンドは、`ICommand` を実装した**プロパティ** (`RelayCommand` など)。メソッドを、バインドしない (WPF は、メソッドを、バインドできない)。実行できる条件が変わったら、`NotifyCanExecuteChanged()`。

### 6.4 DataContext
XAML 内で、無制限に `DataContext` を上書きしてはいけない。

特に UserControl の内部で、次のように自身を `DataContext` へ設定する実装は、避ける。

```xml
<UserControl
    DataContext="{Binding RelativeSource={RelativeSource Self}}">
```

再利用可能な UserControl では、公開する値を**依存関係プロパティ**として定義し、親 View から継承される `DataContext` を破壊しないようにする。(`wpf-check` の UI003 が検出する。)

- **ツール群の補足:** **`DataContext` の設定は、1 か所 (組み立てる場所 = composition root) に決める。** 生成されるアプリは、`App.xaml.cs` の `OnStartup` で、`new MainWindow { DataContext = new MainViewModel() }` を行う (`MainWindow` のコードビハインドには、書かない)。DI コンテナを導入したら、ここで構成する。**XAML の先頭に、`d:DataContext="{d:DesignInstance Type=vm:MainViewModel, IsDesignTimeCreatable=True}"` を付ける** (デザイナーの補完と、`wpf-check` の検査のため)。

## 7. ViewModel 規約

### 7.1 ViewModel の責務
ViewModel には、次の内容を実装する。

- 表示データ
- 選択状態
- 入力状態
- コマンド
- 入力検証結果
- 処理中状態
- Service の呼び出し
- Model から View 向けデータへの変換

### 7.2 ViewModel で禁止する処理
ViewModel から、次を直接呼び出してはいけない。

- `MessageBox.Show`
- `Window.Show`
- `Window.ShowDialog`
- `OpenFileDialog`
- `SaveFileDialog`
- `Clipboard`
- `Application.Current.MainWindow`
- View や UI コントロールの直接参照

必要な場合は、インターフェイスを介する。

```csharp
public interface IMessageService
{
    void ShowInformation(string message);
    bool ShowConfirmation(string message);
}

public sealed class CustomerViewModel
{
    private readonly IMessageService _messageService;

    public CustomerViewModel(IMessageService messageService)
    {
        _messageService = messageService;
    }
}
```

- **ツール群の補足:** ViewModel を、**WPF 非依存のクラスライブラリ**に置くと、`System.Windows` の型は、そもそも使えない (ビルドで落ちる)。`ICommand` / `INotifyPropertyChanged` / `ObservableCollection<T>` は、WPF 非依存なので、使ってよい。`wpf-check` の LAY002 (ダイアログ・`Clipboard`・`Views` の名前空間の使用) が、アプリの中の ViewModel も、検査する。

### 7.3 コンストラクター
ViewModel のコンストラクターでは、重い処理を実行してはいけない。

禁止する処理の例:

- データベースアクセス
- Web API 呼び出し
- 大量データの読み込み
- 長時間かかるファイル処理

初期化処理は、非同期メソッドへ分離する。

```csharp
public async Task InitializeAsync(CancellationToken cancellationToken)
{
    Customers = await _customerService.GetCustomersAsync(cancellationToken);
}
```

### 7.4 ViewModel の状態
画面状態は、コントロールを直接操作せず、プロパティとして公開する。

```csharp
public bool IsBusy { get; private set; }
public string? ErrorMessage { get; private set; }
public Customer? SelectedCustomer { get; set; }
```

- **ツール群の補足:** ViewModel は、`INotifyPropertyChanged` を実装する (基底クラス `ObservableObject` など)。**値が変わるプロパティは、変更を通知する** (`SetProperty`)。通知しないと、画面が更新されない (エラーも出ない。`wpf-check` の BND004)。計算プロパティは、元の値が変わったときに、`OnPropertyChanged(nameof(...))`。コレクションは、`ObservableCollection<T>` を `{ get; }` (置き換えない) で公開する (`List<T>` は、追加・削除が、画面に反映されない)。

## 8. MVVM ライブラリの選択

### 8.1 基本原則
プロジェクト作成時点では、次のみを、設計上の必須要件とする。

> アプリケーションは MVVM 構造で実装する。

MVVM Toolkit または Prism の採用は、プロジェクトの規模と要件を確認した後に決定する。

### 8.2 MVVM Toolkit を選択するケース
次の場合に適している。

- 小規模から中規模
- 標準的な画面構成
- 軽量なライブラリを求める
- ViewModel、Command、通知処理を簡潔にしたい
- アプリケーション構造を独自に設計したい

MVVM Toolkit は、`ObservableObject`、`RelayCommand`、`AsyncRelayCommand`、`Messenger` などを提供する、軽量でモジュール化された MVVM ライブラリ。WPF でも利用でき、必要な部品だけを選択できる。

### 8.3 Prism を選択するケース
次の場合に適している。

- 中規模から大規模
- 複数モジュールで構成する
- 動的な画面切り替えが多い
- Region による画面合成を使用する
- モジュール間通信が必要
- 大規模な DI 管理が必要
- 複数チームで並行開発する

Prism は、MVVM、DI、Command、Event Aggregator、Navigation、Modularity、Region などを提供し、疎結合でテスト可能な WPF アプリケーションを構築するためのフレームワーク。

### 8.4 選択基準
| 判断項目 | MVVM Toolkit | Prism |
|---|---|---|
| アプリ規模 | 小～中規模 | 中～大規模 |
| 導入の容易さ | 比較的容易 | 設計知識が必要 |
| 構造の自由度 | 高い | Prism の構造に従う |
| Command・通知 | 対応 | 対応 |
| DI | 別途組み合わせ可能 | 統合されている |
| モジュール分割 | 独自実装 | 標準機能あり |
| Region 管理 | なし | あり |
| 画面ナビゲーション | 独自実装 | 標準機能あり |

途中でライブラリを選択できるようにするため、ViewModel や Service の責務を明確にし、**WPF 固有型や特定ライブラリの型を、業務ロジックへ漏らさない**設計とする。

- **ツール群の補足:** 生成されるソリューションの MVVM 基底クラス (`ObservableObject` / `RelayCommand`) は、**自前の最小実装** (NuGet 不要。ライブラリの選択を、後に残すため)。MVVM Toolkit を採用するときは、`add-package` で足して、置き換える (**自前の `ObservableObject.cs` を、削除しないと、名前が衝突して、`[ObservableProperty]` が解決されない**。`wpf-check` は、`[ObservableProperty]` / `[RelayCommand]` が生成するメンバーを、知っている)。Prism を採用するときは、`wpf-check` の DataContext の推定 (Region・ViewModelLocator) が効かない場合がある。

## 9. データバインディング規約

### 9.1 Binding Mode
Binding Mode は、必要に応じて明示する。

```xml
<TextBox
    Text="{Binding CustomerName,
                   Mode=TwoWay,
                   UpdateSourceTrigger=PropertyChanged}" />

<TextBlock
    Text="{Binding StatusMessage,
                   Mode=OneWay}" />
```

- **ツール群の補足:** 読み取り専用のプロパティへの TwoWay (明示、または `TextBox.Text` などの既定) は、実行時に例外になる (`wpf-check` の BND003)。

### 9.2 ElementName 参照
画面内の単純な UI 連携には、`ElementName` または `RelativeSource` を使用できる。

ただし、**業務上の状態を、UI 要素間の直接 Binding だけで管理してはいけない。**

### 9.3 Binding エラー
Binding エラーを放置してはいけない。

開発時に出力ウィンドウを確認し、次を解消する。

- プロパティ名の誤り
- `DataContext` の誤り
- Converter の型不一致
- `RelativeSource` の参照誤り
- `ElementName` の参照誤り

- **ツール群の補足:** `{Binding Name}` の `Name` は、ViewModel の public プロパティの綴りと、完全に一致させる (大文字小文字を含む。間違えても、例外にならず、何も表示されない)。**`wpf-check` の BND001 / BND002 が、パスの誤りと、フィールド・メソッド・非 public へのバインドを、静的に検出する** (綴りの近い候補も出す)。出力ウィンドウの確認は、実行時にしかできないので、省略しない。

### 9.4 Converter
Converter には、表示形式の変換のみ実装する。

許可例:

- boolean から `Visibility` への変換
- 日付の表示形式変換
- ステータス値から表示色への変換

禁止例:

- データベースアクセス
- 業務判定
- ファイルアクセス
- 状態の更新
- Service の呼び出し

## 10. 非同期処理規約

### 10.1 async/await
I/O 処理は、原則として非同期で実装する。

```csharp
public async Task<Customer> GetCustomerAsync(
    int customerId,
    CancellationToken cancellationToken)
{
    return await _repository.GetAsync(customerId, cancellationToken);
}
```

### 10.2 async void
**`async void` は、UI イベントハンドラー以外で使用してはいけない。**

```csharp
// UI イベントなので許可
private async void Window_Loaded(object sender, RoutedEventArgs e)
{
    await ViewModel.InitializeAsync(CancellationToken.None);
}
```

ViewModel、Service、Repository では、`Task` または `Task<T>` を返す。(`wpf-check` の ASY002 が検出する。)

### 10.3 UI スレッドのブロック禁止
次を使用して、非同期処理を同期的に待機してはいけない。

```csharp
task.Wait();       // 禁止
task.Result;       // 禁止
```

また、UI スレッドで長時間処理を実行してはいけない。(`wpf-check` の ASY001 が、`.Result` / `.Wait()` / `GetAwaiter().GetResult()` を検出する。)

### 10.4 キャンセル
時間のかかる処理は、可能な限り `CancellationToken` を受け取る。

```csharp
public Task ImportAsync(
    string fileName,
    CancellationToken cancellationToken);
```

## 11. 依存性注入規約
Service や Repository を、ViewModel 内で直接生成してはいけない。

```csharp
// 禁止
public CustomerViewModel()
{
    _service = new CustomerService();
}
```

コンストラクターインジェクションを使用する。

```csharp
public CustomerViewModel(
    ICustomerService customerService,
    IMessageService messageService)
{
    _customerService = customerService;
    _messageService = messageService;
}
```

依存関係は、原則としてインターフェイスで受け取る。ただし、置き換えやテストの必要がない単純な値オブジェクトまで、機械的にインターフェイス化する必要はない。(`wpf-check` の DI001 が、ViewModel 内の `new XxxService()` / `new XxxRepository()` を検出する。)

- **ツール群の補足:** 依存を組み立てる場所は、`App.xaml.cs` (composition root)。ロジックのテストは、データ層を、**フェイク** (メモリ上の実装) に差し替える。

## 12. 例外処理規約

### 12.1 例外を握りつぶさない
次のような実装は、禁止する。

```csharp
try
{
    await SaveAsync();
}
catch
{
}
```
(`wpf-check` の EXC001 が検出する。コメントだけの `catch` も、握りつぶしと見なす。)

### 12.2 例外の責務
- **Repository:** データアクセス固有の例外を整理する
- **Service:** 業務上意味のある例外へ変換する
- **ViewModel:** ログ記録とユーザー通知を制御する
- **App:** 未処理例外を最終的に記録する

### 12.3 再スロー
スタックトレースを維持するため、再スローには `throw;` を使用する。

```csharp
catch (Exception ex)
{
    _logger.LogError(ex, "顧客情報の保存に失敗しました。");
    throw;
}
```

次は禁止する。

```csharp
throw ex;
```
(`wpf-check` の EXC002 が検出する。)

- **ツール群の補足:** `catch (Exception)` は、アプリの境界 (最上位) だけ。`IDisposable` は、`using` 宣言で確実に解放する。イベントの購読は、寿命の長いオブジェクトに対して、解除を忘れない (メモリリーク)。

## 13. ログ規約
ログには、次を記録する。

- アプリケーション起動・終了
- 重要な業務処理の開始・終了
- 外部サービス呼び出し失敗
- ファイル入出力失敗
- 未処理例外
- 復旧不能なデータ不整合

ログに、次を直接記録してはいけない。

- パスワード
- アクセストークン
- 秘密鍵
- 接続文字列
- 不要な個人情報
- クレジットカード情報

ログメッセージには、検索可能な固定文と、構造化パラメーターを使用する。

```csharp
_logger.LogInformation(
    "顧客情報を保存しました。CustomerId: {CustomerId}",
    customerId);
```

## 14. XAML 規約

### 14.1 レイアウト
基本レイアウトには `Grid` を使用する。

`Canvas` による固定座標配置は、作図機能など、固定座標が本質となる場合に限定する。

### 14.2 サイズ指定
次を優先する。

- `Auto`
- `*`
- `MinWidth`
- `MaxWidth`
- `MinHeight`
- `MaxHeight`

画面全体を固定ピクセルだけで設計しないようにする。

### 14.3 共通値
色、余白、フォントサイズ、スタイルを、各画面へ直接記述せず、`ResourceDictionary` に配置する。

```xml
<Thickness x:Key="DefaultControlMargin">8</Thickness>

<Style x:Key="PrimaryButtonStyle"
       TargetType="Button">
    <Setter Property="Margin"
            Value="{StaticResource DefaultControlMargin}" />
    <Setter Property="MinWidth"
            Value="100" />
</Style>
```

- **ツール群の補足:** 共通のリソースは、`Resources/*.xaml` に置き、`App.xaml` の `MergedDictionaries` で結合する (生成される `Resources/Styles.xaml`)。**`StaticResource` は、定義より後ろで使う** (前方参照は、見つからない)。実行時に変えるものは `DynamicResource`。キーの綴りの誤りは、`wpf-check` の RES001 / RES004 が検出する。

### 14.4 名前
コードや Binding から参照しない UI 要素には、不要な `x:Name` を付けない。

## 15. コメント規約
コメントには、コードから読み取れない**理由**を記述する。

```csharp
// 外部システムが日単位で重複を許さないため、日付部分だけで比較する。
```

次のような、コードを読み上げるだけのコメントは避ける。

```csharp
// 顧客 ID を設定する
customer.Id = customerId;
```

public API や共通ライブラリには、必要に応じて XML ドキュメントコメントを記述する。

- **ツール群の補足:** **コメントは、日本語で記述する** (必要に応じて、英語も可)。ライブラリ (ロジック・データ・ViewModel) の `public` な型とメンバーには、`/// <summary>` (日本語) を付ける。コードを消すためのコメントアウトを、残さない。

## 16. テスト規約
単体テストの主対象は、次のとおり。

- ViewModel
- 業務ロジック
- Service
- Converter
- 入力検証
- 状態遷移
- Command の実行可否

ViewModel から View を分離することで、実画面を起動せずに、ロジックをテストできる。これは、MVVM を採用する主要な利点の一つである。

テストメソッド名は、条件と期待結果が分かる名前にする。

```csharp
[Fact]
public async Task SaveAsync_Nameが空の場合_保存せずエラーを設定する()
{
    // Arrange

    // Act

    // Assert
}
```

テストは、原則として AAA 形式で記述する。

- **Arrange:** 準備
- **Act:** 実行
- **Assert:** 検証

- **ツール群の補足 (MSTest の場合):** 属性は `[TestClass]` / `[TestMethod]` (上の例の `[Fact]` は xUnit)。プロジェクトは `<名前>.Tests`、ファイルは `<クラス名>Tests.cs`。テスト名は `メソッド_条件_期待` で、**条件と期待は、日本語でもよい**。
  - **テストは、ロジック・データ・ViewModel のクラスライブラリにだけ書く。** View (XAML とコードビハインド) は、対象にしない。対象が View に書かれていたら、ViewModel / ロジックに切り出す。
  - 期待値は、**仕様から導いた値を、直接、書く** (実装の出力を、写さない)。`Assert.AreEqual(期待値, 実際の値)` の順。浮動小数点は、許容誤差を指定する。非同期のテストは `async Task` (`async void` にしない)。
  - ロジックのテストは、データ層を、フェイクに差し替える。ファイル・DB・時刻・乱数に、直接、依存させない。データ層のテストが、ファイルを使うときは、一時フォルダに、テストごとに別のパスで作り、`[TestCleanup]` で必ず削除する。
  - **`[Ignore]`、`Assert.Inconclusive`、`.runsettings` での除外、アサーションを弱める、`[Timeout]` の延長は、ユーザーの許可なしに、しない** (`build-test-loop` と同じ)。
  - 新しい機能は、`wpf-test-first` で、テストを先に書く。

## 17. 禁止事項
以下を、原則として禁止する。

- コードビハインドへの業務ロジック記述
- ViewModel から View やコントロールを直接参照
- ViewModel から `MessageBox` やダイアログを直接表示
- ViewModel 内で Service を `new`
- UI スレッド上で長時間処理を実行
- `.Result` または `.Wait()` による非同期処理の同期待機
- `async void` を通常メソッドに使用
- 例外を空の `catch` で握りつぶす
- Binding エラーを放置
- Converter への業務ロジック記述
- ViewModel へのデータアクセス処理の直接記述
- パスワードや秘密情報のソースコード埋め込み
- 固定座標だけによる画面レイアウト
- 理由のない Singleton やグローバル変数
- 特定の MVVM ライブラリ型を Domain 層へ持ち込む

## 18. コードレビュー確認項目
レビューでは、最低限、次を確認する。

### 設計
- MVVM の責務が守られているか
- ViewModel が View を参照していないか
- 業務ロジックが Service または Model へ分離されているか
- DI 可能な構成になっているか

### C#
- Nullable 警告が残っていないか
- 非同期処理が正しく実装されているか
- 例外を握りつぶしていないか
- メソッドやクラスの責務が大きすぎないか
- 名前から役割を判断できるか

### XAML
- Binding エラーがないか
- 不要な `DataContext` の上書きがないか
- スタイルや色が共通化されているか
- 固定サイズに依存していないか
- キーボード操作や Tab 順が考慮されているか

### テスト
- ViewModel と業務ロジックにテストがあるか
- 正常系だけでなく異常系があるか
- 外部サービスが差し替え可能か
- **UI テスト (FlaUI) を書く場合 (ツール群の補足):** 画面の操作の流れを、主要なものに絞る。要素は **AutomationId** で探し (操作するコントロールに `AutomationProperties.AutomationId` を付ける)、操作は **UIA のパターン** (`Invoke` / `Value`) を使い、マウス・キーボードの入力を使わない。待ちは `WaitFor` (固定の `Thread.Sleep` を使わない)。UIA3 を使う。見た目 (レイアウト・色) は、対象にしない。同じ画面の操作が増えたら、Page Object にまとめる。失敗したときは、スクリーンショットを見る。

## 19. 規約上の最終方針
本規約では、次の方針を採用する。

- MVVM は必須とする
- WPF 標準機能だけでも、MVVM 構造を維持できるようにする
- Prism または MVVM Toolkit の採用は、プロジェクト作成後に決定できる
- 業務ロジックを、特定の MVVM ライブラリへ依存させない
- 小～中規模では、MVVM Toolkit を第一候補とする
- モジュール化や Region 管理が必要な中～大規模案件では、Prism を候補とする
- ライブラリを採用しても、本規約の責務分離を優先する

## 付録: どの規則を、どのツールが確かめるか
**ツールは、機械で判定できる項目だけを、静的に確かめる。** それ以外 (責務の分離の妥当性、メソッドの大きさ、コメントの質、キーボード操作など) は、レビュー (18 章) で確認する。

| 規則 | 確かめるもの |
|---|---|
| 3.2 参照方向、Domain が WPF に依存しない | `wpf-check` LAY001 / LAY003 (`Presentation` / `Application` / `Domain` / `Infrastructure` の名前は標準の依存、それ以外は View → ViewModel → ロジック → データ) |
| 4.2 bool の名前 | `wpf-check` NAM001 |
| 6.4 UserControl が自分自身を `DataContext` にしない | `wpf-check` UI003 |
| 7.2 ViewModel で禁止する処理 | `wpf-check` LAY002 (`MessageBox` / ダイアログ / `Clipboard` / `Application.Current` / `Views` の名前空間)、WPF 非依存のライブラリ (ビルドで) |
| 7.4 / 9.3 バインディング | `wpf-check` BND001〜BND004、CMD001 (パス、フィールド、読み取り専用への TwoWay、`INotifyPropertyChanged`) |
| 10.2 / 10.3 非同期 | `wpf-check` ASY002 / ASY001 |
| 11 DI | `wpf-check` DI001 |
| 12.1 / 12.3 例外 | `wpf-check` EXC001 / EXC002 |
| 14.3 リソース | `wpf-check` RES001〜RES005、CNV001 |
| 起動 | `wpf-check` UI001 (`InitializeComponent()`)、APP001 |
| 5.1 Nullable、書式、命名の一部 | `.editorconfig` (Visual Studio と `dotnet format`)、ビルドの警告 |
| 16 テスト | `build-test-loop` (実行)、`wpf-test-first` (先行) |
| UI テスト (FlaUI) | `build-test-loop` の「UI テスト」(Green のあとに、追加で実行。書き方と、失敗時のスクリーンショット)。`wpf-check` UI002 (UI テストのプロジェクトがあるとき、操作するコントロールに AutomationId がない) |

- **XAML / ViewModel / `App.xaml` を編集したら、`wpf-check` を実行する** (ウォッチャーは、要らない)。ビルドとテストは、ウォッチャー経由 (`auto-build` / `build-test-loop`)。
