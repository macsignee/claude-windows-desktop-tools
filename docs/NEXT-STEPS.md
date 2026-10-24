# 次の作業 (再開用メモ)

2026-10-24 時点。C++ と WPF の統合 (v2.4.x〜v2.5.6) の実機の確認は、**WS10 (保留) を除いて、完了した** (v2.5.7)。
各項目の状況は `docs/REMAINING-CHECKS.md`、手順と結果は `docs/TEST-PLAN.md` (「状況の一覧」)。以前の版の、手順と依頼文は、git の履歴 (`docs/NEXT-STEPS.md`、2026-10-21 まで) にある。

## 残り

1. **WS10 (保留のまま閉じた、2026-10-24):** VS で、WPF アプリ + クラスライブラリの `.sln` を作り、`add_project.py` でライブラリ + テストを追加して、VS で開く。必要になったら、`docs/REMAINING-CHECKS.md` と TEST-PLAN の手順で確認する。
2. 省略していた項目 (U14c の (a)、U16 の C++ 側、WS8 の F5) は、2026-10-24 に、すべて確認済み。
3. **以前の版 (v2.0.0〜v2.3.0) の、未確認の項目:** C++ / MFC の、GoogleTest のソース取得 (G3 / G6 / G7 / G8) と、Skill (S / A / N / U / F / K 系)。ホスト側ツール (H4、T8、T9、R 系、M 系) は、2026-10-24 に確認済み。`docs/REMAINING-CHECKS.md` の 3.。

## main へのマージの前に

- push は、ユーザーが行う (`git push -u origin unify-dotnet`)。マージも、ユーザーが決める。
- 変更の一覧は、`CHANGELOG.md` の 2.4.x〜2.5.6 (ブランチ `unify-dotnet`、main から 20 コミット先)。
- 配置: `./install/install.sh` (Skill・規約。`--skills-only` / `--rules-only` / `--host-only`)、`~/src/copy-host-tools.sh` (ホスト側ツール)。**Skill やスクリプトを変えたら、再配置を忘れない** (確認のやり直しの、最大の原因だった)。

## マージのあとの予定 (2026-10-24 に決定。要件の整理と設計は、これから)

1. **GoogleTest の取得を vcpkg に一元化する** (下の節)。
2. **3 層構造のモジュール名の変更:** MFC / Win32、WPF で、ロジック層を `Command`、データ層を `Model` に改名する (現在の既定は `LogicLayer` / `DataLayer`)。**決めること:** 既存のソリューション (層の名前を、あとから変える手順は `DLL-LAYOUT.md`) の扱い、`--layers` の値 (`logic` / `data`) と、生成される名前の対応、WPF の `viewmodel` 層の名前との関係、名前空間・`CLAUDE.md`・Skill・`mfc-check` / `wpf-check` の層の判定、既存の記録 (TEST-PLAN) の名前。
3. **ダイアログのテスト:** FlaUI とユニットテストの、いずれかで、MFC / Win32、WPF の**メインウィンドウから表示されるダイアログ (モーダル、モードレス)** のテストを、実行できるようにする。**決めること:** FlaUI (UIA の `Window.ModalWindows` / トップレベルのウィンドウの検出、モーダル中の操作) とユニットテスト (ダイアログの ViewModel / ロジックの分離、`IDialogService` のモック。MFC は、ダイアログのクラスを、テスト可能にする分離) の、どちらを、どこまで。モードレスの検出 (別のトップレベルウィンドウ)。
4. **WinForms と C# の DLL への拡張:** WinForms、C# の DLL の、作成 (`new-solution`)・ビルド・テストを、できるようにする。**決めること:** `--type` の値 (`winforms`、`csharp-dll` など)、層とテストの構成 (WPF と同じ MSTest)、WinForms の UI テスト (FlaUI の UIA2 / UIA3、`AutomationId` は `Name`)、検査 (`wpf-check` に相当するもの)、規約 (`rules/`)、ウォッチャー (`.csproj` の判定は、すでに SDK 形式に対応)。WinForms の UI テストは、PoC を別に行う、と先に決めている (DESIGN 4.29)。

## マージのあとの作業: GoogleTest の取得を vcpkg に一元化する (2026-10-24 に決定。マージ後に開始)

**順序:** (1) 現状の問題点の修正 (スキップする項目は、記録に残す) → (2) コミットして、main へマージ → (3) 次の PoC から。

**案:** 優先順位は、**vcpkg (マニフェストモード、`x64-windows-static-md`) → (取得できないとき) `ThirdParty\googletest\` のソースを、静的ライブラリ `gtest` としてビルド**。ユーザーが、手でソースを置く方法も、そのまま残す。nuget (コピー) 方式の扱いは、PoC の後に決める。
**得られること:** 取得の入口が `trigger_package.flag` の 1 つになる (`trigger_gtest.flag` / `gtest_once.sh` を廃止できる)。版が `builtin-baseline` で固定される。バイナリキャッシュで、2 つ目以降が速い。
**注意:** vcpkg も GitHub からソースを取得する (ネットワークが全く届かないときは、フォールバックも失敗する)。フォールバックが効くのは、vcpkg 自体が使えないとき、または、vcpkg の取得経路だけが失敗するとき。フォールバックを残すと、プロジェクトの生成は 2 通り残る。

**PoC (実機、使い捨ての C++ ソリューションで) で確かめること:**

| 確認 | 内容 |
|---|---|
| (a) `gtest_main` のリンク | vcpkg では `gtest_main.lib` が `manual-link` に置かれ、自動ではリンクされない → テストプロジェクトに `main()` を書いた `main.cpp` を生成する案 |
| (b) Debug / Release のライブラリ名 | `gtestd.lib` / `gtest.lib`。vcpkg の MSBuild 統合が、構成ごとに選ぶか |
| (c) 並列ビルドでの競合 | `/m` で、複数のプロジェクトが、同時に `vcpkg install` を始めないか (先に明示的に `vcpkg install` を実行すれば、ビルド時は何もしない) |
| (d) CRT の整合 | `static-md` (`/MD`) は、NuGet の `rt-dyn` と同じ。MFC を静的リンクしているときの整合 |

PoC の手順: 使い捨ての C++ ソリューション (`MixTest` のコピー) で、`cpp_pkg.py add <dir> gtest` → `package_once.sh vcpkg install` → テストプロジェクトに `main.cpp` を足す → ビルド → 実行。
**影響する範囲:** `new_solution.py` (`gtest` に関する記述 46 か所)、`cpp_pkg.py` (`gtest` のプロジェクトを除外している箇所)、`cpp-test-first` の `add_layer.py`、`trigger_gtest.flag` / `gtest_once.sh`、`CLAUDE.md` のひな形、Skill 3 か所、DESIGN、テスト (`new_solution_test.sh` / `add_layer_test.sh` / `gtest_once_test.sh`)、実機の確認 (TEST-PLAN の N3 / N3a / N3b / N10 など)。
**PoC の結果によっては、「vcpkg に一元化しない」という結論もあり得る。**

## 前提 (docs/DESIGN.md 1.)

デバッグは VS で行う。ビルドする PC には、C++ ワークロード入りの VS がある。C++ / .NET のツールがない環境では、「Visual Studio Installer で、手で追加」と案内する (自動では追加できない)。
