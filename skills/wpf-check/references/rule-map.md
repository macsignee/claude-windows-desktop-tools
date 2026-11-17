# 規則とツールの対応表 (WPF)

`rules/wpf-csharp.md` の付録だった表。規約のサイズを小さくするため、`wpf-check` の `references` に移した (v2.96.8)。規則の番号は、`wpf-csharp.md` の章・節。

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
| 16 テスト | `build-test-loop` (実行)、`csharp-test-first` (先行) |
| UI テスト (FlaUI) | `build-test-loop` の `references/ui-tests.md`(ビルド → テストの流れには含めず、求めたときと、`/ui-test-first` のループで、別に実行。書き方と、失敗時のスクリーンショット)。`wpf-check` UI002 (UI テストのプロジェクトがあるとき、操作するコントロールに AutomationId がない) |
