---
paths:
  - "**/*.cs"
---

# C# 共通規約 (WPF / WinForms 共通)

WPF (`wpf-csharp.md`) と WinForms (`winforms-csharp.md`) の規約のうち、**C# の部分 (画面の技術に依らない章)** を、1 つにまとめたもの。**章の番号は、元の WPF 規約のまま** (ツールの検出コードと、規約を参照する文書が、この番号を使っているため。欠けている番号は、WPF / WinForms 固有の章)。
`.cs` を読むときに、自動で読み込まれる (画面の技術ごとの規約は、ファイル名で絞って、読み込まれる)。

**適用の順序:**
1. プロジェクトの `CLAUDE.md` に、固有の決まりがあれば、それが最優先。
2. 詳細な書式は、プロジェクトの `.editorconfig` が正 (なければ、`~/.claude/templates/dotnet/` のひな形)。
3. **例に、WPF の用語 (ViewModel、`wpf-check`、`Window` など) が出てくる。WinForms では、ViewModel を Presenter に、`wpf-check` を `winforms-check` に、読み替える** (対応は、`csharp-test-first` の SKILL.md の「読み替え」の表)。
4. 「**ツール群の補足**」は、このリポジトリのツール (`new-solution` / `csharp-test-first` / `wpf-check` / `winforms-check` / `add-package`) との対応や、規約を補う決まり。どの規則を、どのツールが確かめるかは、`wpf-csharp.md` / `winforms-csharp.md` の付録。

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
  - 新しい機能は、`csharp-test-first` で、テストを先に書く。

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
