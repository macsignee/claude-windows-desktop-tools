# 規則とツールの対応表 (WinForms)

`rules/winforms-csharp.md` の付録だった表。規約のサイズを小さくするため、`winforms-check` の `references` に移した (v2.96.8)。規則の番号は、`winforms-csharp.md` の章・節。

**ツールは、機械で判定できる項目だけを、静的に確かめる。** それ以外 (責務の分離の妥当性、画面モデルと Presenter の境界、`IView` の大きさ、レイアウトの見た目、コメントの質など) は、レビュー (15 章) で確認する。

| 規則 | 確かめるもの |
|---|---|
| 3.1 参照方向、ロジック・データ層が WinForms に依存しない | `winforms-check` WFL001 / WFL003 |
| `winforms-view-model.md` 1・5 章 / 6.3 Presenter・画面モデルが WinForms の型を使わない | `winforms-check` WFL002 (アプリの中の画面モデル)、WFL001 (ロジック層) |
| `winforms-view-model.md` 1・5.1 画面モデルが WinForms の型を使わない | ロジック層に置く限り `winforms-check` WFL001。**`ScreenModels/`・名前による検査は未実装 (予定)** |
| `winforms-view-model.md` 4 章: Form・Presenter が、データアクセスを `new` しない・リポジトリを直接参照しない、層の参照の向き | `winforms-check` WFL004 / WFL005 / WFL003。それ以外の戻りの規則は、レビュー |
| 2.3 / 11 Form で Service を `new` しない | `winforms-check` WFL004 |
| 4.2 コントロールの `Name` (空・重複・変数名との違い) | `winforms-check` WFD002 / WFD003 / WFD005 |
| 4.3 bool の名前 | `winforms-check` NAM001 |
| 5.1 `InitializeComponent()` の呼び出し・置き場所・中身、`Controls.Add` | `winforms-check` WFD001 / WFD006 / WFD007 / WFD004 |
| 8.1 / 8.2 UI スレッド、スレッドの誤りの隠蔽 | `winforms-check` WFT001 / WFT002 / WFT003、ASY001 / ASY002 |
| 9 例外 | `winforms-check` EXC001 / EXC002 |
| 5 書式、命名の一部、Nullable | `.editorconfig` (Visual Studio と `dotnet format`)、ビルドの警告 |
| 13 テスト | `build-test-loop` (実行)、`csharp-test-first` (先行。WinForms も同じ手順)、UI テストは `build-test-loop` の `references/ui-tests.md` |
