# 旧 Presenter 構成のソリューションを、画面モデルへ移す手順

対象: v2.92.0 より前に `/new-solution` が作った WinForms のソリューション (`CLAUDE.md` が「WinForms (MVP)」。Form が `I<画面名>View` を実装し、`<画面名>Presenter` が振る舞いを持つ構成)。設計の正本は `docs/UI-MODEL-GUIDE.md`、規約は `rules/winforms-view-model.md`。

## 0. 移さなくてよい場合

- **「WinForms (MVP)」の表記は、いまも通用する** (`winforms-check` は、旧構成を、構成の違いとしては指摘しない。Presenter が WinForms の型やリポジトリを直接使っているときの警告 (WFL002・WFL005) は、旧構成でも出る)。動いている画面を、急いで移す必要はない。
- 移すのは、画面に**入力の検査・操作の失敗の表示・状態の再現 (Fake の画面)** を足すときや、画面を大きく直すときが向く。新しい画面は、最初から画面モデルで作る (旧構成と新構成は、1 つのソリューションに、画面単位で共存できる)。
- **Presenter は、廃止ではない。** WinForms の型がないと書けないもの (ダイアログを開く、画面遷移、フォーカス、UI スレッドへの戻し) は、画面モデルのあとも、Presenter に置く。

## 1. 旧構成と新構成の対応 (WinForms)

| 旧 (MVP) | 新 (画面モデル) |
|---|---|
| `IMainView` (`PersonName` / `Greeting` / `CanClear` のプロパティと、`NameChanged` / `ClearRequested` のイベント) | `IMainScreenModel` (`Name` / `Greeting` / `CanClear` / `IsValid`、`Validate()`、`Clear()`、`INotifyPropertyChanged`)。**View のインターフェースは、なくなる** |
| `MainPresenter` (View を受け取り、イベントで `Refresh()`) | `MainScreenModel` (状態を持ち、プロパティの変更で通知する。**View を知らない**) |
| 文章の直書き (`"こんにちは、…"`) | `MainMessages` (文章を作る 1 か所) |
| `MainForm : Form, IMainView` (コンストラクターで Presenter を作る) | `MainForm : Form` (**コンストラクターは引数なし**。`Bind(IMainScreenModel)` で結ぶ) |
| `MainPresenterTests` (`FakeMainView` を渡す) | `MainScreenModelTests` (Fake も、View の偽物も要らない。プロパティを設定し、状態・通知を確かめる) |
| `Presenters/` | `ScreenModels/` (ロジック層があれば、そちら。なければアプリの中) |

**画面の文言とコントロールの `Name` は、変えない。** UI テスト (FlaUI) は、そのまま通る。

## 2. 手順 (1 画面ずつ。テストが先)

1. **ブランチを切る。** 作業前に、ビルドとテストが通ることを確かめる (`build-test-loop`)。
2. **画面モデルのテストを書く (Red)。** 旧 `MainPresenterTests` の期待を、画面モデルの言葉に直す。`FakeMainView` に値を入れていたところは、`model.Name = "…"` にする。`Greeting` / `CanClear` を読んで検査する。`IMainScreenModel` と、中身が空の `MainScreenModel` (スタブ) を置き、**アサーションで失敗する**ことを確かめる (`csharp-test-first`)。
3. **画面モデルを実装する (Green)。** 旧 `Presenter.Refresh()` の計算を、**プロパティの読み取り**にする (`Greeting => …`)。**状態は、画面モデルだけが持つ** (`_name` など。旧では View のコントロールが持っていた)。プロパティの設定で、影響するプロパティの通知を出す (`Name` を変えたら、`Name` / `Greeting` / `CanClear` / `IsValid`)。`Clear()` は、`Name = ""`。
4. **入力の規則を、`Validate()` に移す。** 旧 Presenter や Form の中の `if` (長さ、形式) を、`Validate()` に集める。誤りは `ValidationResult` (`MemberNames` は欄の名前。空なら画面全体)。`IsValid` は `Validate()` の結果が空であること。**`Validate()` は純粋** (状態を変えない。同じ入力なら同じ結果)。
5. **文章を `MainMessages` に集める。** 画面モデルが作る文章 (案内、検査の誤り) だけ。Form の固定の文字は、リソースにしない。
6. **Form を直す。** `IMainView` の実装を外し、プロパティ (`PersonName` など) とイベントの宣言を消す。コンストラクターは `InitializeComponent()` だけにする。`Bind(model)` で、`model.PropertyChanged` → `Render()` を結び、`Render()` が、コントロールへ表示する (**値が同じなら、代入しない**。`TextChanged` の再入を避ける)。`TextChanged` / `Click` は、`model.Name = …` / `model.Clear()` を呼ぶだけ。**デザイナー (`*.Designer.cs`) は、触らない。**
7. **`Program.cs` (組み立てる場所) を直す。** `new MainPresenter(form)` を、`var model = new MainScreenModel(); form.Bind(model);` にする。リポジトリを使うなら、ここで渡す。
8. **旧 `IMainView` / `MainPresenter` / `MainPresenterTests` を消す。** 検査 (`winforms-check`) とビルド・テスト・UI テストを通す。
9. **`CLAUDE.md` の表記を「WinForms (ScreenModel)」に直す。** ただし、ソリューションに旧構成の画面が残っているうちは、そのままにしてよい。

## 3. Presenter に残すもの

画面モデルへ移したあとに、Presenter に残るのは、**WinForms の型がないと書けないものだけ**。

- ダイアログを開く・画面遷移の実行 (`MessageBox` / 別の Form を開く)、フォーカスの移動、UI スレッドへの戻し。
- Presenter は、`IView` (View のインターフェース) 越しに Form を知るだけにして、WinForms の型を使わない。**状態と規則は、持たない** (画面モデルへ)。画面モデルの `Failure` / `Validate()` の結果を、画面に出す (ダイアログ、フォーカス) のは、Presenter か Form。

## 4. 検査と確認

- `winforms-check` (WFL001〜WFL005): 画面モデルが WinForms の型を使っていないこと (WFL001・WFL002)、層の参照の向き (WFL003)、Form・Presenter がリポジトリを直接使っていないこと (WFL004・WFL005) を確かめる。画面モデルは、リポジトリを呼んでよい (WFL005 の対象外)。
- UI テスト (FlaUI): 文言と `Name` を変えていなければ、そのまま通る。通らないときは、`Render()` の更新漏れ (通知を出し忘れたプロパティ) を疑う。
- 画面モデルの検査・失敗の表示を足すときは、`ui-test-first` (誤りの文章を出す UI テスト)、状態の再現は `APP_FAKE_SCREENS` (`ScreenModelSelector` に、シナリオを足す)。

## 5. WPF・MFC

**この節は、生成物の差分 (v2.93.0・v2.95.0) から書いた。旧構成の実際のソリューションでは、確認していない。**

- **WPF (v2.93.0 より前):** もともと `ViewModel` を持つ構成で、Presenter はない。足すのは、`ViewModelBase` (`Validate()` の結果を、`ErrorTexts[欄名]` と `ScreenErrorTexts` にする)、`ErrorTextMap`、`MainMessages`。既存の `ViewModel` を、`ViewModelBase` を継承する形にし、検査の規則を `Validate()` に集める。XAML は、誤りの表示 (`{Binding ErrorTexts[Name], Mode=OneWay}`) を足す。
- **MFC (v2.95.0 より前):** ダイアログの中に、状態と規則が混ざっている (`CSampleDlg` が、入力の検査も文章も持つ)。移すときは、状態と規則を、MFC を使わない `<画面名>ScreenModel` (ロジック層。`std::wstring`) に出し、ダイアログは、`ToCString` / `ToWString` (`ScreenModelUi.h`) で境界を越えて表示するだけにする。更新は `Observable` (`AddHandler` / `Raise`)、ハンドラーは ID ごと (`switch (nID)` を使わない)。**MFC の SDI・MDI (Document/View) は、画面モデルの対象外。** 規約は `rules/mfc-cpp.md`。

## 6. 未確認・未整備

- 自動の移行 (生成スクリプトによる書き換え) は、ない。手作業で、1 画面ずつ。
- 画面が多いソリューションの、移す順序の指針 (例: 検査や失敗の表示が要る画面から) は、使ってみて、決める。
