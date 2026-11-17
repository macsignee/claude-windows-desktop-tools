# 契約テスト: Model の Fake と本物を、同じテストで確かめる (C# / MSTest)

画面が使う **Model** (データベース・API の違いを隠す、リポジトリのようなもの) は、UI テストの段階では、**Fake** (メモリ上の実装) で動かし、本物は、あとから作る (`ui-test-first` の「Model の差し替え」「結合」)。**Fake が、本物と、ずれないように、同じテストを、両方に通す。それが、契約テスト。** 契約テストは、**本物の Model の仕様書**でもある (本物は、契約テストを Red → Green にして、作る)。

## 置く場所と名前
- **インターフェースと Fake がある層の、テストのプロジェクト** (例: `DataLayer.Tests`)。
- **抽象クラス `<インターフェース名>ContractTests`** (契約。テスト本体) と、**実装ごとの、具体クラス `<実装名>ContractTests`** (`Create()` で、その実装を返すだけ)。

```csharp
[TestClass]
public abstract class OrderRepositoryContractTests
{
    /// <summary>空の状態の Model を返す。テストごとに、新しく作る (テスト同士が、影響しない)。</summary>
    protected abstract IOrderRepository Create();

    [TestMethod]
    public void Get_存在しないId_nullを返す()
    {
        var repo = Create();
        Assert.IsNull(repo.Get(999));
    }

    [TestMethod]
    public void Add_保存したあと_Getで同じ内容が返る()
    {
        var repo = Create();
        repo.Add(new Order(1, "りんご"));
        Assert.AreEqual("りんご", repo.Get(1)?.Name);
    }
}

[TestClass]
public class InMemoryOrderRepositoryContractTests : OrderRepositoryContractTests
{
    protected override IOrderRepository Create() => new InMemoryOrderRepository();
}
```

MSTest は、**抽象クラスの `[TestMethod]` を、具体クラスごとに、実行する** (実行される件数 = 契約のテスト数 × 具体クラスの数)。抽象クラスにも、`[TestClass]` を付ける。

## 何を書くか
- **インターフェースの、決めた意味だけ** (計画の「依存する Model」)。正常 (保存して取り出す)、存在しない、重複、**エラーの形** (どの例外を、どの条件で)、空の状態、並び順 (**決めたときだけ**)、境界 (空文字・上限)。
- **実装の内部 (SQL、キャッシュ、接続) には、触れない。** どの実装でも、成り立つことだけ。
- テスト名は、`メソッド_条件_期待`。非同期のインターフェースは、`async Task` のテスト。

## 流れ (Fake → 本物)
1. **契約を決める:** インターフェースと、その意味 (正常・異常の例) を、計画に書く。
2. **契約テスト + Fake:** 抽象クラスと、Fake の具体クラスを書き (Red)、Fake を作って Green にする (`build_test_once.sh`)。UI テストは、この Fake で回す。
3. **本物:** **本物の具体クラス** (`Create()` が、本物を返す) を足す → Red → 本物を実装 → Green。本物に固有の挙動 (接続エラー、トランザクション) は、**別の単体テスト**に書く。
4. **ずれたとき:** 契約テストが、Fake か本物で Red になったら、**契約 (インターフェースの意味) が正しい。** 実装を直す。契約そのものを変えるときは、ユーザーの承認を取り、**両方の実装と、テストに、反映する**。

## 本物が、外部 (データベース・API) を要するとき
- **開発用の接続先** (ユーザーが用意) を使う。**本番の接続先で、実行しない。** `Create()` は、テストごとに、空の状態 (専用のスキーマ・テーブルを作り直す、など) を用意する。
- **接続先が、まだ用意できない間は、本物の具体クラスを足さない。** 足す時期は、環境が整ってから (結合の関門)。**`[Ignore]` / `Assert.Inconclusive` / 条件で飛ばす書き方は、使わない** (`test_guard.py check` が、許可なしにしてはいけない変更として検出する)。
- 軽く済む代替 (インメモリの SQLite など) があれば、本物の具体クラスを、それで先に作ってよい (ユーザーに確認する)。

## テストの改変の検査 (`test_guard.py`)
- **具体クラスの追加** (本物の実装を、契約に通す) は、テストの追加で、問題ない。
- **抽象クラスの契約テストを、削る・弱める・飛ばす**のは、検査の対象 (許可なしにしてはいけない)。

## 画面モデルの契約テスト (`I<画面名>ScreenModel`)
画面モデルにも、同じ形で契約テストを書く (抽象クラス `I<画面名>ScreenModelContractTests` + 具体クラス)。具体クラスは、**本物の画面モデル (Fake リポジトリを渡す)** と、**Fake 画面モデル** (あるとき)。**ロジック先 (本物がある) は、契約テストを先に書き、本物で Green にしてから、Fake 画面モデルを作る** (本物を読んで Fake を書くと、偶然の挙動まで写す)。
- **書く内容 (インターフェースの、決めた意味だけ):** 状態の更新、操作とその実行可否 (`CanXxx`)、変更の通知 (どの識別が、いつ通知されるか)、`Validate()` / `IsValid`、`Commit()` と `Failure`、`Cancel()`。
- **検査の契約:** `Validate()` は純粋 (同じ入力なら、同じ結果。誤りは、規則を書いた順)。`IsValid` は `Validate()` の結果が空であることと一致する。`Commit()` は、誤りがあれば `false` を返し、通知を出す。誤りの `MemberNames` は、プロパティの名前と一致する (空 = 画面全体、先頭 = 主たる欄)。
- **失敗の契約:** `Commit()` で、リポジトリが `RepositoryException` を投げたら、`false` を返し、`Failure` が、その文章になる。画面モデルの状態は、変わらずに残る。**`Failure` は、次の編集、または次の `Commit()` の開始で消える。** `RepositoryException` 以外の例外は、握りつぶさず、そのまま伝わる。
- **リポジトリの失敗の契約 (リポジトリの契約テストに足す):** 本物でも再現できる失敗 (重複、見つからない) は、本物と Fake の両方に通す。再現できない失敗 (接続できない) は、**Fake だけのテスト**として、別に書く (Fake の `FailNext(...)` / `FailWhen(操作, ...)` で再現する)。
- **文章:** 画面モデルは、日本語の文章を作る。単体テストは、`MemberNames` と `ErrorMessage` (文章) で検査する (文言を直したら、テストも直す)。業務の生成文も、文言で検査する。


## Fake リポジトリの失敗の再現 (`FailNext` / `FailWhen`)
**ひな形は、リポジトリも Fake も生成しない** (決定 2026-11-17。サンプルの画面が、リポジトリを使わないため)。リポジトリを持つ画面を作るとき、利用者 (Claude) が、Fake に、次の形で足す。**インターフェースには足さない** (本物に「失敗させる」操作はない)。Fake を直接持つ単体テストだけが使う。

```csharp
public class FakeOrderRepository : IOrderRepository
{
    private readonly Queue<RepositoryException> _nextFailures = new();
    private readonly List<(string Operation, Func<object?[], bool> When, RepositoryException Error)> _rules = new();

    /// <summary>次の 1 回の呼び出しだけ失敗させる (その後は成功する。再試行の確認に使う)。</summary>
    public void FailNext(RepositoryException error) => _nextFailures.Enqueue(error);

    /// <summary>操作名 (nameof(Save) など) と、引数の条件に合う呼び出しを、失敗させる (条件に合う間、続く)。</summary>
    public void FailWhen(string operation, Func<object?[], bool> when, RepositoryException error) => _rules.Add((operation, when, error));

    private void ThrowIfFailing(string operation, params object?[] args)
    {
        if (_nextFailures.Count > 0) throw _nextFailures.Dequeue();
        foreach (var r in _rules)
            if (r.Operation == operation && r.When(args)) throw r.Error;
    }

    public void Save(Order order)
    {
        ThrowIfFailing(nameof(Save), order);   // 失敗するときは、状態を変える前に投げる
        // ... メモリ上に保存する
    }
}
```
- **使い方 (単体テスト):** `fake.FailNext(new RepositoryException("保存できませんでした"))` → 画面モデルの `Commit()` → `false`、`Failure` がその文章、状態は不変。もう一度 `Commit()` で、成功する (再試行できる)。
- **失敗する前に、状態を変えない** (本物のトランザクションの失敗と、同じ見え方にする)。
- **UI テスト (別プロセス) は、メソッドを呼べない。** アプリの組み立てる場所が、`APP_MODEL=fake:<シナリオ名>` を (Debug のときだけ) 読み、そのシナリオ用に `FailNext` / `FailWhen` を設定した Fake を渡す。シナリオ名と設定は、アプリごとに決める (ひな形にはない)。
