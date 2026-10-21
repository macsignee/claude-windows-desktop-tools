---
name: wpf-check
description: WPF のプロジェクトの「コンパイルは通るが、実行時に壊れる」部分 (バインディングのパスの誤り、StaticResource のキー不足・重複、InitializeComponent() の呼び忘れ、StartupUri や結合した辞書の Source の誤り、Converter の型の誤り、層の依存の違反) と、WPF プログラミング規約のうち機械で判定できる項目 (ViewModel の DI・ダイアログ、.Result / async void、空の catch / throw ex、曖昧な bool 名) を、静的に検査して、要約を返す手順。画面に何も表示されない、ボタンが反応しない、起動時に XamlParseException になる、XAML / ViewModel / App.xaml を編集した、ViewModel に WPF の型が混ざっていないか確かめたい、といった依頼で使う。Windows のウォッチャーは不要 (読み取りだけ)。
---

# WPF の「見えない部分」の検査 (wpf-check)

WPF は、XAML と C# が、**文字列 (バインディングのパス、リソースのキー、イベント名、Source の URI) で結ばれている**。
結びつきが崩れても、**コンパイルは通り、実行したときに、「画面に何も出ない」「ボタンが反応しない」「起動時に例外」**という形で現れる。
バインディングの誤りは、**例外にもならず、出力ウィンドウに、ログが出るだけ**で、AI は、実行時の画面を見られない。
このスキルは、その対応を、静的に検査する。ビルド (`auto-build`) とは別で、**ウォッチャーも、Windows も、要らない**。

コンパイルエラーになるもの (イベントハンドラの不足、`x:Name` の重複、XAML の文法の誤りなど) は、対象外。ビルドが教える (`MC` / `XDG` / `CS` のエラー)。

## 実行

```bash
python3 -I <このSkillのフォルダ>/scripts/wpf_check.py "$PROJ"
```

- `$PROJ`: ソリューションまたはプロジェクトのフォルダ。以下の `.csproj` を、プロジェクトとして検査する。
- 読み取りだけ。ファイルは、変えない。XAML / C# は、UTF-8 (BOM あり・なし)・UTF-16・CP932 のどれでも読める。`obj/` `bin/` と、生成物 (`*.g.cs` `*.designer.cs`) は、読まない。
- 既定は、error と warning だけを出す。`--all` で、info (参考) も出す。`--json <ファイル>` で、全件と、数 (XAML 数・バインディング数・リソース参照数) を JSON に書く。
- 層の判定は、プロジェクト名と、`.csproj` の `UseWPF` / `OutputType` / `TargetFramework` で決める。名前が違うときは、`--logic <名前>` / `--data <名前>` / `--viewmodel <名前>` で指定する。

| 終了コード | 意味 | 次の行動 |
|---|---|---|
| 0 | error なし (warning はあるかもしれない) | warning を、読んで、判断する |
| 1 | error あり | 下記の方針で、直す |
| 2 | 引数が不正 | フォルダを確認する |
| 3 | 検査する対象がない (WPF のプロジェクトも `.xaml` もない) | WPF のプロジェクトではない。報告して終わり |

## 出力の読み方

```
wpf-check: error 2 / warning 1 (3 projects: WpfApp, MyApp.ViewModels, MyApp.Logic)
[1] error   BND001 {Binding TotalTxt}: MainViewModel にプロパティ "TotalTxt" がない (もしかして: TotalText)
      WpfApp/MainWindow.xaml(16)
[2] error   UI001 MainWindow のコンストラクターが、InitializeComponent() を呼んでいない (画面が空になる)
      WpfApp/MainWindow.xaml.cs(7)
[3] error   RES002 StaticResource "PrimaryBrush" が、同じ辞書の後ろで定義されている (...)
      WpfApp/Themes/Colors.xaml(4)
```
- 見出し: 件数と、検査したプロジェクト。`[n]` は、重大度順 (error → warning → info)、同じ重大度の中では、プロジェクト・コード順。
- 2 行目は、`ファイル(行)`。ファイルは、`$PROJ` からの相対パス。バインディングの場合は、**XAML の、その属性の行**。
- 出力は最大 40 行。足りないときは、`--max-lines` を増やすか、`--json` を読む。

## 検査の一覧と、直し方

| コード | 重大度 | 内容 | 直し方 |
|---|---|---|---|
| BND001 | error | `{Binding}` のパスが、DataContext の型にない。メソッド・非 public・static のプロパティの場合は、その旨が出る | 綴りを直す (「もしかして」を見る)。**ViewModel 側に足すのが、正しいとは限らない** (XAML の綴りの誤りのことが多い)。メソッドには、`ICommand` のプロパティ (`[RelayCommand]` なら `○○Command`) を足す。 |
| BND002 | error | public **フィールド**にバインドしている | `{ get; set; }` のプロパティにする (WPF は、フィールドをバインドできない)。 |
| BND003 | error / warning | 読み取り専用のプロパティに TwoWay でバインドしている。setter なしなら、明示の `Mode=TwoWay` も、`TextBox.Text` などの既定が TwoWay の項目も error (実機で、起動時の例外を確認)。setter が public でない場合は warning | `Mode=OneWay` にする、または setter を足す。**実行時に `InvalidOperationException`。** |
| BND004 | warning | ViewModel が `INotifyPropertyChanged` を実装していない | `ObservableObject` (CommunityToolkit.Mvvm) などを基底にし、`SetProperty` / `[ObservableProperty]` を使う。**値を変えても、画面が更新されない。** |
| BND900 | info | DataContext の型を、解決できない / 基底クラスが外部で、メンバーを知れない | 何もしない (検査を、省略したという印)。 |
| CMD001 | warning | `Command` に、`ICommand` でない型のプロパティをバインドしている | `ICommand` (`RelayCommand` など) のプロパティにする。 |
| RES001 | error / warning | `StaticResource` のキーが、どこにも定義されていない。**外部の辞書 (NuGet のテーマなど) があると、確実ではないので warning** | キーの綴りを直す、または辞書に足す。**起動時に `XamlParseException`。** |
| RES002 | error | `StaticResource` が、同じ辞書の、後ろで定義されたキーを参照している | 定義の順序を直す (参照される側を、先に)。または `DynamicResource` にする。**起動時に `InvalidOperationException` (実機で確認)。** |
| RES003 | error | 同じ辞書に、同じ `x:Key` が、複数ある | キーを変える。**読み込み時に例外。** |
| RES004 | warning | `DynamicResource` のキーが、どこにも定義されていない | キーの綴りを直す。**例外にならず、黙って既定値になる。** |
| RES005 | error | `MergedDictionaries` の `Source` が、プロジェクト内に見つからない | パスを直す (ファイルの移動・改名のあとに多い)。**読み込み時に例外。** |
| CNV001 | error | `Converter` に、`IValueConverter` / `IMultiValueConverter` を実装していないクラスを指定している | クラスにインターフェースを実装する。 |
| UI001 | error | code-behind のコンストラクターが、`InitializeComponent()` を呼んでいない | コンストラクターで、呼ぶ。**画面が、空になる (例外も出ない)。** |
| APP001 | error | `App.xaml` の `StartupUri` の XAML が、プロジェクト内に見つからない | パスを直す。**起動時に例外。** |
| LAY001 | error | ロジック層・データ層が、WPF に依存している (**プロジェクトの `UseWPF` / `-windows` は、ViewModel 層も対象**。ViewModel のソースの WPF の型は LAY002) (`UseWPF`、`-windows` の TargetFramework、`System.Windows` の名前空間、`MessageBox` など) | UI の処理を、ViewModel / View に移す。ロジックは、`net8.0` などの、Windows 非依存にする。 |
| LAY002 | warning | ViewModel が、View の型を使っている (`MessageBox.Show` / `OpenFileDialog` / `SaveFileDialog` / `Clipboard` / `.ShowDialog()` / `Application.Current` / `new XxxWindow(...)` / `System.Windows.Controls` / `...Views` の名前空間など) | `IDialogService` などの、抽象に分ける (テストしにくい。MSTest は、STA スレッドも `Application` もない)。 |
| LAY003 | error | プロジェクト参照の向きが、層 (View → ViewModel → ロジック → データ) に反する。**`Presentation` / `Application` / `Domain` / `Infrastructure` の名前のプロジェクトは、標準の依存** (Presentation → Application → Domain、Infrastructure → Application / Domain。Domain は、何も参照しない) | 参照を逆にするか、共通部分を下の層に移す。 |
| DI001 | warning | ViewModel 内で、`new XxxService()` / `new XxxRepository()` (`Client` `Provider` `Gateway` も) を生成している | コンストラクターで、インターフェースを受け取る (組み立ては、`App.xaml.cs`)。 |
| ASY001 | warning | `.Result` / `.Wait()` / `GetAwaiter().GetResult()` で、非同期処理を同期的に待っている | `await` にする (UI スレッドのデッドロックの恐れ)。 |
| ASY002 | warning | イベントハンドラ (引数に `sender` または `EventArgs`) 以外の `async void` | `Task` を返す。 |
| EXC001 | warning | 空の `catch` (コメントだけの `catch` を含む) | ログを書くか、再スローする。 |
| EXC002 | warning | `catch (Exception ex) { throw ex; }` | `throw;` にする (スタックトレースを保つ)。 |
| NAM001 | warning | `bool` のプロパティ・フィールドに、`Flag` / `Status` / `Check` という名前を付けている | `IsXxx` / `HasXxx` / `CanXxx` にする。 |
| UI003 | warning | `UserControl` が、`DataContext="{Binding RelativeSource={RelativeSource Self}}"` で、自分自身を `DataContext` にしている | 依存関係プロパティで、値を受け取る。 |
| XAML001 | info | XAML を、XML として解析できなかった | ビルドが、詳しいエラーを出す。そのファイルは、検査から外れている。 |

## ループのルール
1. **XAML / ViewModel / `App.xaml` / `.csproj` の参照を編集したら、編集のあとで、実行する。** 編集していない状態で再実行しない。
2. error は、すべて直す。warning は、**自分が今回編集した箇所に関係するもの**だけ直し、ほかは、報告に 1 行で添える (無関係な修正はしない)。info は、読まない。
3. 直したら、再実行して、error が減ったことを確認する。**最大 3 回**。同じ error が残るなら、停止して、原因 (誤検出の疑いを含む) を報告する。
4. error がなければ (終了コード 0)、続けて、ビルドとテスト (`auto-build` / `build-test-loop`) に進んでよい。
5. **検査を通すために、バインディングやリソースを消さない・コメントアウトしない。** 直すのは、綴りと定義。画面の機能を減らして、指摘を消すのは、ユーザーの許可が要る。

## 編集のときの注意
- **ViewModel に足すか、XAML を直すかは、仕様で決める。** BND001 の「もしかして」が出るときは、ほぼ、XAML の綴りの誤り。出ないときは、仕様書 (`docs/` など) と、ほかの XAML の使い方を見てから、決める。
- CommunityToolkit.Mvvm の `[ObservableProperty] private string _name;` は、`Name` プロパティになる (`_` / `m_` を除き、先頭を大文字に)。`[RelayCommand] void Save()` は `SaveCommand`、`async Task LoadAsync()` は `LoadCommand` になる (`Async` を除く)。**フィールドの名前を変えたら、XAML のバインディングも、同時に直す。**
- `obj/` の生成物 (`*.g.cs` `*.g.i.cs`) は、直接編集しない。`.csproj` / `Directory.Build.props` / `global.json` の編集は、ユーザーの確認が要る設定のことがある (`docs/RECOMMENDED-SETTINGS.md`)。
- XAML の編集は、**属性の値の、`{` `}` と引用符を、壊さない**。文字コードと改行 (UTF-8 の BOM の有無、CRLF) を、変えない。

## 誤検出と限界
- **静的解析**。実行はしない。**検査するのは、「確実に壊れる」ものと「疑わしい」もの。通ったことは、動くことを意味しない** (見た目・レイアウト・スタイル・データの中身は、対象外)。
- **DataContext の型は、次の場所から、推定する:** XAML の `DataContext` 属性・`<X.DataContext>` (`{StaticResource}` で参照するリソースを含む)、`DataTemplate` の `DataType`、code-behind の `DataContext = new Xxx()` / `= this` / `= コンストラクター引数` / `GetService<Xxx>()`、ウィンドウを作るコードの `new MainWindow { DataContext = new Xxx() }`。**`d:DataContext` (デザイン時) だけが根拠のときは、error ではなく warning。** どれでも分からなければ、バインディングは、検査しない。
- **検査しないバインディング:** `Source` / `ElementName` / `RelativeSource` つき、`ControlTemplate` / `Style` の中、`DataType` のない `DataTemplate` の中、パスが `(` `/` `$` などを含む形、DataContext が別のバインディングで決まる場合 (型を辿れないとき)。
- **メンバーを知れない型は、「ない」と言わない。** 基底クラスが、プロジェクトの外にある (`Window`・`UserControl`・MvvmLight の `ViewModelBase`・未知の基底クラスなど) と、プロパティが足されている可能性があるので、BND001 は出さない (`--all` の BND900 で分かる)。`ObservableObject` / `BindableBase` / `ReactiveObject` などは、プロパティを足さないものとして、検査する。
- **C# の解析は、軽い字句解析。** 型・プロパティ・フィールド・メソッド・コンストラクターと、基底クラスの一覧を取り出す。部分クラス (`partial`) は、ファイルをまたいで、まとめる。ソースジェネレーターが作るメンバーは、`[ObservableProperty]` と `[RelayCommand]` だけ知っている。**ほかのジェネレーター (ReactiveUI.Fody など) や、リフレクション・`dynamic` で足されるメンバーは、知らない。**
- **リソースの検査 (RES001) は、見える範囲を、厳密に辿る:** その XAML の、祖先の `Resources` → `App.xaml` の `Application.Resources` (結合した辞書を含む)。`UserControl` は、親の `Window.Resources` を、読み込み時には見ない。**ライブラリ (`OutputType` が `Library`) の XAML は、アプリ側の辞書で解決される可能性があるので、warning にする。** コードで足されるキー (`Resources["X"] = ...` / `Resources.Add("X", ...)`) は、知っている。
- `{StaticResource {x:Type ...}}` / `{x:Static ...}` / `ComponentResourceKey` のように、キーが入れ子の形は、検査しない。
- **RES002 (前方参照) は、error:** `StaticResource` は、読み込み時に、定義済みのキーだけを解決する。後ろで定義されていると、起動時に例外になる (W8 の実機で確認)。
- 結合した辞書の `Source` は、相対パス・`/パス`・`pack://application:,,,/パス`・`/アセンブリ;component/パス` を解釈する。**アセンブリがソリューションの中にあれば、そのプロジェクトのファイルを探す。** それ以外 (NuGet のテーマなど) は、外部の辞書として扱い、RES001 を warning に下げる。
- **層の判定は、名前の推定:** `Logic` / `Domain` / `Core` → ロジック、`Data` → データ、`ViewModels` → ViewModel、`UseWPF` の exe → View。テストプロジェクト (`Test` / `Tests` で終わる) は、対象外。外れるときは、`--logic` / `--data` / `--viewmodel` で指定する。
- **実プロジェクトでの検証は、まだ。** 疑似プロジェクト (`tests/wpf_check_test.sh`) では、誤検出なし。実プロジェクトで、誤検出を見つけたら、報告に書き (どのコードの、どの書き方か)、ユーザーに伝える。
