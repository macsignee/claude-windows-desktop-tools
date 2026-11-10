# Model (リポジトリ) の Fake ↔ 本物と、結合

`ui-test-first` の SKILL.md の手順 1 で、画面が使う **Model が、まだ本物でない (これから作る)** ときに、**先に**読む。本物ができたあとの、結合の手順も、ここ。

## 計画に足す表 (手順 1)

- **依存する Model (データベース・API などの違いを隠す、リポジトリのようなもの):** 画面が使う Model が、**まだ本物でない (これから作る)** ときは、計画に、**表 (Model (インターフェース) / 実装 (Fake / 本物) / 契約テスト (クラス名) / 状態 (Fake のみ / 本物あり / 結合済み))** を足す。**UI テストは、Fake (メモリ上の実装) で回す** (下の「Model の差し替え」)。本物の Model は、`csharp-test-first` / `cpp-test-first` の流れで、別に作り、結合は、下の「結合 (Fake → 本物)」で行う。

## Model の差し替え (Fake ↔ 本物)

画面が使う **Model** (データベース・API の違いを隠す、リポジトリのようなもの) は、**まだ、本物がない**ことが多い。UI テストは、**Fake** (メモリ上の実装) で回し、本物ができてから、結合する。
- **インターフェースに、依存する。** ViewModel / Presenter は、Model の**インターフェース**だけを知る (`new` しない。コンストラクターで受け取る)。Fake と本物は、同じインターフェースを実装する。**Fake は、メモリ上の、小さな実装** (決まった値、保存したら覚える。遅延・失敗は、必要なときだけ)。
- **切り替えは、起動の環境変数 `APP_MODEL` (`fake` / `real`)。** アプリの、**組み立てる場所** (WPF: `App.xaml.cs`、WinForms: `Program.cs`、MFC: `InitInstance`) で、読んで、選ぶ:
  ```csharp
  IOrderRepository repo = Environment.GetEnvironmentVariable("APP_MODEL") == "fake"
      ? new InMemoryOrderRepository(/* 初期データ */) : new SqlOrderRepository(connectionString);
  ```
  **Release のビルドでは、`APP_MODEL` を読まない** (`#if DEBUG`。Fake が、製品に、紛れ込まないため)。MFC は、`getenv("APP_MODEL")` を、`_DEBUG` のときだけ。
- **UI テストが、`APP_MODEL` を、アプリに渡す。** `UiTestBase` が、起動の前に設定する (`ModelMode`)。**値は、環境変数 `UITEST_MODEL` > `uitest.settings` の `model=` > `fake` (既定)。** 読まないアプリには、影響しない。`ui-trace.txt` の先頭に、`model: fake` と出る。
- **Fake は、アプリの側 (または、データ層) に置く** (テストのプロジェクトに置かない。exe が、起動したときに、使えるため)。名前: `InMemory<名前>Repository`。
- **Fake が、本物と、ずれないように:** Fake は、インターフェースの、決めた意味 (計画の「依存する Model」) だけを、まねる。**本物の振る舞いを、推測で、足さない。** **Fake と本物は、契約テスト (同じテストを、両方に通す) で、合わせる** (`csharp-test-first/CONTRACT-TESTS.md`、C++ は `cpp-test-first/CONTRACT-TESTS.md`)。契約テストを書いて、Fake で Green にしてから、UI テストを回す。

## 結合 (Fake → 本物)

本物の Model ができて、**その単体テストが `PASSED`** になったら、結合する。**UI テストを、本物でも通す** (Fake で通っていたテストを、そのまま)。
1. **関門:** 本物の Model の単体テストと、**契約テスト (Fake と本物の両方) が `PASSED`** (`build_test_once.sh`)。計画の「依存する Model」の状態が、「本物あり」。
2. **本物に切り替える:** `<アプリ>.UITests/uitest.settings` の `model=fake` を `model=real` に直す (または、`UITEST_MODEL=real`)。**UI テストのコードは、変えない。** 本物の接続先 (開発用のデータベース・API) の準備は、ユーザーに確認する (**本番の接続先で、実行しない**)。
3. **同じ UI テストを、再実行する** (`uitest_once.sh`、同じ `--filter`)。**Green → 結合済み。** 状態を「結合済み」に直す (設計の記録・計画の表)。
4. **Red になったら、原因を分ける:** (a) **Fake が、本物と、違う** (戻り値・順序・エラーの形) → Fake と、インターフェースの意味を直す (Model の単体テストが、先)。(b) **本物の不具合** → 本物を直す (単体テストが、先)。(c) **データ・時間の違い** (本物は、遅い、データが残る、並びが違う) → テストを、データに依存しない形にする (**アサーションを、弱めない**。仕様が変わったときだけ、ユーザーの承認で)。**どれも、`test_guard.py check` の対象** (UI テストの、削除・`Ignore`・弱めは、許可なしにしない)。
5. **結合したあとも、Fake を、捨てない。** 普段の UI テストは、`model=fake` (速く、安定) に戻す。**本物での UI テストは、主要な流れだけ**に絞り、結合の確認のときに、`model=real` で、回す。
