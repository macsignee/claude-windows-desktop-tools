# 4 層 + ライブラリ単位のテスト: ソリューションの構成と規約 (WPF)

(規約の全文は、ユーザー共通の `~/.claude/rules/wpf-csharp.md` (**WPF プログラミング規約**の、WPF / XAML / MVVM の部分) と、`csharp-common.md` (C# の共通部分)。この文書は、WPF の規約の、3 章 (ソリューション構成) を、このツール群の生成物に当てはめたもの。)

`csharp-test-first` が前提にする、ソリューションの構成。プロジェクトを新しく作る (ユーザーが了承した) ときと、
既存の構成が規約に合っているかを確認するときに読む。**ここに書いていることを、ユーザーの了承なしに、既存プロジェクトへ適用しない。**
(C++ / MFC の版は、`cpp-test-first` の `DLL-LAYOUT.md`。)

## 構成

```
View (WPF アプリ) ──▶ ViewModel ──▶ ロジック ──▶ データ (のインターフェース)
                         ▲              ▲              ▲
                ViewModel のテスト   ロジックのテスト   データのテスト
```

| プロジェクト | 種類 | TargetFramework | 参照するもの |
|---|---|---|---|
| View (WPF アプリ) | WinExe、`UseWPF` | `net10.0-windows` | ViewModel、ロジック、データ (組み立てる側) |
| `ViewModels` | クラスライブラリ | `net10.0` (**WPF 非依存**) | ロジック |
| `LogicLayer` | クラスライブラリ | `net10.0` (WPF 非依存) | データ |
| `DataLayer` | クラスライブラリ | `net10.0` (WPF 非依存) | なし |
| `<名前>.Tests` | MSTest | `net10.0` | 対応するライブラリ (プロジェクト参照) |

- **ロジックは、データ層の実装を知らない。** データ層の**インターフェース** (`IOrderRepository` など) にだけ依存する。実装は、View (アプリ) が組み立てて、ロジックに渡す。これで、ロジックのテストで、データ層をフェイクに差し替えられる。
  (.NET では、インターフェースと実装が、同じ `DataLayer` にあるので、ロジックから `DataLayer` への、プロジェクト参照は、ある。**使うのは、インターフェースだけ**、という規律で守る。厳密に分けたいときは、インターフェースだけの `*.Abstractions` ライブラリを作る。)
- **テストは、ライブラリ単位。** ライブラリ 1 つに、テストプロジェクト 1 つ。名前は、`<ライブラリ名>.Tests` (ウォッチャーの検出: `Microsoft.NET.Test.Sdk` を参照する、または名前が `Test` / `Tests` で終わる)。
- **View にテストは作らない。**
- **ViewModel を、WPF 非依存の、クラスライブラリに置く理由:** `net10.0` (Windows 非依存) のライブラリは、`System.Windows` の型 (`Window` / `MessageBox` / `Application`) を、**そもそも、使えない** (ビルドで落ちる)。型システムが、「ViewModel が、View に依存しない」ことを、強制する。テストも、STA スレッドや `Application` なしで、動く。
  `ICommand` / `INotifyPropertyChanged` / `ObservableCollection<T>` は、WPF 非依存なので、使える。`CommandManager.RequerySuggested` (WPF 専用) は、使えない → `RelayCommand.NotifyCanExecuteChanged()` を、明示的に呼ぶ。
- ViewModel 層を作らない構成 (`--layers` に `viewmodel` を含めない) では、ViewModel は、アプリの `ViewModels/` フォルダに入る。**そのままでは、テストできない。** テストしたくなったら、`ViewModels` ライブラリを作って、移す。

## アプリ (View) の構成 (規約 3.1)
```
MyApp/
├── App.xaml / App.xaml.cs     アプリの起点。App.xaml.cs の OnStartup が、画面と ViewModel を組み立てる (composition root)
├── Views/                     画面 (XAML とコードビハインド。業務ロジックを書かない)
├── ViewModels/                ViewModel 層を作らないときだけ。層を作ったら、そちらに置く
└── Resources/                 共通の色・余白・スタイル (Styles.xaml。App.xaml で MergedDictionaries に結合)
```
- `Models` / `Services` / `Behaviors` / `Converters` / `Infrastructure` は、**必要になったときに作る** (空のフォルダを、先に作らない)。
- **`DataContext` の設定は、`App.xaml.cs` の 1 か所** (`new MainWindow { DataContext = new MainViewModel() }`)。コードビハインドには、書かない。DI コンテナを導入したら、ここで構成する。
- **中規模以上 (規約 3.2: Presentation / Application / Domain / Infrastructure):** プロジェクト名を `SampleApp.Domain` のように、`.` で区切って作る (`new-solution --layers data:SampleApp.Domain,logic:SampleApp.Application,viewmodel:SampleApp.Presentation`、または `add_project.py`)。**名前が、標準の層の名前 (末尾が `Presentation` / `Application` / `Domain` / `Infrastructure`) だと、`wpf-check` は、標準の依存で検査する** (Presentation → Application → Domain、Infrastructure → Application / Domain。Domain は、何も参照しない。Domain / Application / Infrastructure は、WPF に依存しない)。それ以外の名前 (`ViewModels` / `LogicLayer` / `DataLayer`) は、View → ViewModel → ロジック → データの向き。**2 つのモデルを、1 つのソリューションで混ぜない。**

## 規約 (csproj と、ソリューション)

1. **SDK 形式の `.csproj`** (`<Project Sdk="Microsoft.NET.Sdk">`)。ファイルは、自動で含まれる (新しい `.cs` / `.xaml` を、`.csproj` に追加しない)。
2. **`Directory.Build.props` (ソリューション直下) で、`Nullable` / `ImplicitUsings` / `LangVersion` を、そろえる。** 各 `.csproj` には、`TargetFramework` と `RootNamespace` だけを書く。
3. **プロジェクト名 = フォルダ名 = `.csproj` の名前 = アセンブリ名。** `.` を含んでよい (`SampleApp.Domain`)。その場合、名前空間は、その名前のまま。型名 (`SampleAppDomainInfo`) では、`.` を除く。 XAML の `xmlns:vm="clr-namespace:NS.ViewModels;assembly=ViewModels"` の `assembly=` は、このアセンブリ名。
4. **名前空間:** ルート (ソリューション名) + 層 (`<ルート>.Data` / `.Logic` / `.ViewModels`)。画面は `<ルート>.Views`。テストは `<ライブラリの名前空間>.Tests`。ファイルスコープの名前空間 (`namespace X;`)。
5. **ソリューションは `.slnx`** (新規)。.NET だけなら、構成 (`Debug` / `Release` の `Any CPU`) は、書かない (Visual Studio の既定)。ウォッチャーは、`-Platform auto` で `AnyCPU` を使う。**WPF アプリに `DefaultStartup="true"`** (層は、ライブラリで、起動できない)。
6. **出力先は、既定のまま** (`bin/<Configuration>/<TargetFramework>/`)。ウォッチャーの `dotnet test --no-build` は、各プロジェクトの既定の出力先を使う。**出力先を `bin\x64\Debug` などのプラットフォーム別にしたときは、ウォッチャーの `-DotnetTestArgs:-p:Platform=x64` が要る (値が `-` で始まるので、コロンで結ぶ。`"-p:..."` と書くと、PowerShell が `-p` をパラメーター名と解釈して、起動に失敗する)。**
7. **MSTest の参照 (テストプロジェクト):** `Microsoft.NET.Test.Sdk` + `MSTest.TestAdapter` + `MSTest.TestFramework` (3 つとも、バージョンを固定)。`IsTestProject` を `true`、`IsPackable` を `false`。
   - **VSTest モード** (`dotnet test --logger trx`)。`Microsoft.Testing.Platform` モード (`MSTest.Sdk` や、`global.json` の `test.runner` の指定) は、ウォッチャーが、対象にしていない。
8. **パッケージの追加は、`add-package` Skill** (`.csproj` に、名前とバージョンを、推測で書かない)。

## 新しいライブラリとテストを、組で作るとき (了承を得た場合)

**同梱の `scripts/add_project.py` で作る (手書きしない)。** ソリューションの編集 (`.slnx` / `.sln`) は、ミスが出やすく、毎回の出力が揺れるため。

```bash
python3 <Skill>/scripts/add_project.py "$SLN_DIR" ViewModels --kind viewmodel --uses LogicLayer
```
- `.slnx` と `.sln` (Visual Studio が作った、構成が `Any CPU` / `x64` のもの) の両方に、追加できる。`.sln` では、プロジェクトの種類 (`{9A19103F-16F7-4668-BE54-9A1E7A4F7556}`) と、構成の対応付け (ソリューションの構成 → プロジェクトの `Any CPU`) も、足される。
- 作るファイル: `<Name>/<Name>.csproj`、`<Name>Info.cs` (ビルド確認用の、小さな公開クラス)、`<Name>.Tests/<Name>.Tests.csproj`、`<Name>InfoTests.cs` (ベースラインの 1 件)。`--kind viewmodel` では、`ObservableObject` / `RelayCommand` / `MainViewModel` と、`MainViewModelTests.cs` も。
- **ベースラインが緑 (`PASSED`) になってから**、本物のテストを書く。

## 層の名前を、あとから変えるとき
プロジェクトの名前は、フォルダ名・`.csproj` の名前・アセンブリ名・`RootNamespace`・名前空間・XAML の `assembly=`・`.slnx` の `Path`・`CLAUDE.md` の `- 層:` に現れる。**Visual Studio の「名前の変更」で、プロジェクトの名前と、`.slnx` を直し、次に、フォルダ名と、名前空間を直す。** 自分で、文字列の置換を、広い範囲に、しない (ユーザーの了承を得てから)。

## よくある失敗
| 症状 | 原因と対処 |
|---|---|
| ViewModel のライブラリが、`CS0234` / `CS0246` (`System.Windows` が、ない) | ViewModel が WPF の型を使っている。インターフェース (`IDialogService`) に分ける。**ライブラリに `UseWPF` を付けて、ごまかさない** (層の依存が、崩れる。`wpf-check` の `LAY001`) |
| テストが、`CS0122` (アクセスできない) | 新しい型が `internal` (既定)。`public` にする |
| `ENV_ERROR`: テストが 1 件も実行されない | `[TestClass]` / `[TestMethod]` の付け忘れ、`MSTest.TestAdapter` の参照漏れ、メソッドが `static` / `async void` / 引数あり |
| `FAILED`: `no test results: the test host crashed ...` | `--no-build` が、出力先を見つけられない (プラットフォーム別の出力先 → `-DotnetTestArgs`)。または、`TargetFramework` のランタイムが、ホストにない (`dotnet --list-runtimes` で確認) |
| `NU1101` / `NU1301` | パッケージ名の誤り / NuGet に届かない。`add-package` で名前を確かめる / ネットワークを確認する |
| 変更通知のテストが、`PropertyChanged` が上がらず落ちる (スタブ) | これは、正しい Red。実装で、`SetProperty` を呼ぶ |
| 画面に値が出ない (テストは通る) | バインディングの綴り、`DataContext`、`InitializeComponent()`。**`wpf-check`** |
