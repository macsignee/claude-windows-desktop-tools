# 契約テスト: Model の Fake と本物を、同じテストで確かめる (C++ / GoogleTest)

画面が使う **Model** (データベース・API の違いを隠す、リポジトリのようなもの) は、UI テストの段階では、**Fake** (メモリ上の実装) で動かし、本物は、あとから作る (`ui-test-first` の「Model の差し替え」「結合」)。**Fake が、本物と、ずれないように、同じテストを、両方に通す。それが、契約テスト。** 契約テストは、**本物の Model の仕様書**でもある。考え方と流れは、C# 版 (`csharp-test-first/CONTRACT-TESTS.md`) と同じ。

## 置く場所
インターフェースと Fake がある DLL の、テストのプロジェクト (`<DLL>Test`)。名前は、`<インターフェース名>Contract`。

## 型付きテスト (`TYPED_TEST`): 実装が、既定のコンストラクターで作れるとき
```cpp
template <typename T>
class OrderRepositoryContract : public ::testing::Test {};

// 実装を、ここに並べる。本物は、Fake が Green になったあとで、足す (Red → 実装 → Green)
using Implementations = ::testing::Types<InMemoryOrderRepository /*, SqlOrderRepository */>;
TYPED_TEST_SUITE(OrderRepositoryContract, Implementations);

TYPED_TEST(OrderRepositoryContract, Get_NoSuchId_ReturnsNull) {
    TypeParam repo;                       // 空の状態。テストごとに、新しく作る
    EXPECT_EQ(repo.Get(999), nullptr);
}

TYPED_TEST(OrderRepositoryContract, Add_ThenGet_ReturnsSameContent) {
    TypeParam repo;
    repo.Add(Order{1, L"りんご"});
    ASSERT_NE(repo.Get(1), nullptr);
    EXPECT_EQ(repo.Get(1)->name, L"りんご");
}
```

## 値でパラメータ化 (`TEST_P`): 作り方に、引数が要るとき
```cpp
using Factory = std::function<std::unique_ptr<IOrderRepository>()>;
class OrderRepositoryContract : public ::testing::TestWithParam<Factory> {};

TEST_P(OrderRepositoryContract, Get_NoSuchId_ReturnsNull) {
    auto repo = GetParam()();
    EXPECT_EQ(repo->Get(999), nullptr);
}

INSTANTIATE_TEST_SUITE_P(Fake, OrderRepositoryContract,
    ::testing::Values(Factory([] { return std::make_unique<InMemoryOrderRepository>(); })));
// 本物は、あとで、Values(...) に足す: Factory([] { return MakeSqlRepository(testConnection); })
```

## 何を書くか・流れ・注意
C# 版と同じ: **インターフェースの、決めた意味だけ** (正常・存在しない・重複・エラーの形・空・境界)。実装の内部に触れない。Fake で Green → 本物の実装を足して Red → Green。ずれたら、契約が正しい (変えるときは、ユーザーの承認)。本物が外部を要するときは、開発用の接続先 (本番では、実行しない)。**`GTEST_SKIP()` / `DISABLED_` で飛ばさない** (`test_guard.py check` の対象)。接続先が整うまで、本物は、`Types` / `Values` に足さない。

## 画面モデルの契約テスト (`<画面名>ScreenModelInterface`)
画面モデルにも、同じ形で契約テストを書く (名前は `<画面名>ScreenModelInterfaceContract`)。実装は、**本物の画面モデル (Fake リポジトリを渡す)** と、**Fake 画面モデル** (あるとき)。**ロジック先は、契約テストを先に書き、本物で Green にしてから、Fake 画面モデルを作る。**
- **書く内容:** C# 版と同じ (`csharp-test-first/CONTRACT-TESTS.md` の「画面モデルの契約テスト」)。C++ では、`GetErrors()` / `GetFailure()`、`Validate()` / `IsValid()`、`Commit()` (`bool`)、通知 (購読したハンドラーが、どの識別を、いつ受け取るか。スコープ (`BeginChange()`) の終わりにまとめて、識別ごとに 1 回、列挙の宣言順)。
- **失敗の契約:** `RepositoryException` を投げるリポジトリで、`Commit()` が `false`、`GetFailure()` が、その種別、状態は不変。`Duplicate` / `NotFound` は、本物と Fake の両方。`Unavailable` は、Fake だけ (`FailNext(種別)`)。
- 文章は、契約テストの対象外 (`MessageFormatterInterface` のテストで、列挙の全値に、日本語の表の行があることを確かめる)。

