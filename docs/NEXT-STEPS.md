# 次の作業 (再開用メモ)

2026-10-25 時点。C++ と WPF の統合 (v2.4.x〜v2.5.6) の実機の確認は、**WS10 (保留) を除いて、完了した** (v2.5.7)。**WinForms と C# DLL への拡張 (v2.6.0〜v2.10.1) は、実装・実機の確認を終えて、main にマージし、push 済み** (マージコミット `6914e87`)。
各項目の状況は `docs/REMAINING-CHECKS.md`、手順と結果は `docs/TEST-PLAN.md` (「状況の一覧」)。以前の版の、手順と依頼文は、git の履歴 (`docs/NEXT-STEPS.md`、2026-10-21 まで) にある。

## 残り

1. **WS10 (保留のまま閉じた、2026-10-24):** VS で、WPF アプリ + クラスライブラリの `.sln` を作り、`add_project.py` でライブラリ + テストを追加して、VS で開く。必要になったら、`docs/REMAINING-CHECKS.md` と TEST-PLAN の手順で確認する。
2. 省略していた項目 (U14c の (a)、U16 の C++ 側、WS8 の F5) は、2026-10-24 に、すべて確認済み。
3. **以前の版 (v2.0.0〜v2.3.0) の、未確認の項目:** C++ / MFC の、GoogleTest のソース取得 (G3 / G6 / G7 / G8) と、Skill (S / A / N / U / F / K 系)。ホスト側ツール (H4、T8、T9、R 系、M 系) は、2026-10-24 に確認済み。**各項目の扱い (廃止・保留・小さく確認) と、保留の再開条件は、`docs/REMAINING-CHECKS.md` の 2. (2026-10-31 に整理)。**

## 運用メモ (マージ・配置)

- **コミットは、ユーザーが明示的に指示したときだけ。push は、ユーザーが行う (`git push origin main` など)。マージも、ユーザーが決める。** 新しい作業は、`main` から、新しいブランチを切って行う。
- 変更の一覧は、`CHANGELOG.md` (2.4.x〜2.5.7: 統合 (PR #1)、2.6.0〜2.10.1: WinForms / C# DLL への拡張とその周辺 (`6914e87`))。
- 配置: `./install/install.sh` (Skill・規約。`--skills-only` / `--rules-only` / `--host-only`)、`~/src/copy-host-tools.sh` (ホスト側ツール)。**Skill やスクリプトを変えたら、再配置を忘れない** (確認のやり直しの、最大の原因だった)。

## マージのあとの予定 (2026-10-24 に決定。要件の整理と設計は、これから)

1. ~~**GoogleTest の取得を vcpkg に一元化する**~~ (下の節) → **PoC 完了 (2026-10-28)。既定を vcpkg にした (v2.21.0、DESIGN 4.41)。生成したソリューションも、実機で確認済み (2026-10-28、TEST-PLAN の N3v)。**
2. ~~**3 層構造のモジュール名の変更**~~ (MFC / Win32、WPF で、ロジック層を `Command`、データ層を `Model` に改名) → **取り下げ (2026-10-24)。** 既定の名前は、`LogicLayer` / `DataLayer` のまま。**ソリューションの作成後に、個々の事情に応じて、リネームする** (手順は `skills/cpp-test-first/DLL-LAYOUT.md` の「層の名前を、あとから変えるとき」。WPF は、名前を変えたら、プロジェクト・名前空間・`CLAUDE.md` をそろえる)。実装は、一度行い (単体テスト全通過)、方針の変更で、コミット前に破棄した。
3. ~~**ダイアログのテスト**~~ → **実機の調査は完了 (2026-10-27)。道具・規約・チェック・Skill への取り込みも完了 (v2.17.0)。** 方針: 連動の規則は、純粋な関数の単体テスト (DataRow)、UI テスト (FlaUI) は、ダイアログごとに煙テスト 1 件。**PoC (`poc/dialog-flaui*`、コミットしない)** で、WinForms / WPF / MFC の、ダイアログ (モーダル・モードレス)、メニュー、MessageBox・ファイルダイアログ、コンボ・リスト・スライダー・スクロールバー・タブ、DataGrid / ListView の 5 つの表示形式 (列ヘッダーの並べ替え・複数選択・仮想化)、スピン、チェック付きのリスト・ツリー、日付ピッカーとカレンダー、ToolStrip / StatusStrip、TaskDialog を、実機で確かめた (根拠は `poc/dialog-flaui/README.md`)。取り込み: `UiDialogs.cs` (`SendMessage` の 5 秒のタイムアウト、`SelectTab`、`ClickColumnHeader`、`SetNumeric`、`ToggleTreeNode`、`OpenDropDown`、`PostKey`、`ForceCloseDialog`、`GetAppWindow` ほか)、`winforms-check` (WFD008)、`wpf-check` (UI004)、`rules/winforms-csharp.md` 6.3.1、`rules/wpf-csharp.md`、`build-test-loop/SKILL.md` の「コントロール別の、実機の結果の表」、DESIGN 4.37。**残り:** (a) ~~生成した C# の、実機でのコンパイルと、ひな形のテストの再実行~~ → **確認済み (2026-10-27。WinForms 3 / WPF 3 / MFC 1 件通過、警告 0。DESIGN 4.37)。**(b) スタイルの見本 (WinForms `StylesForm`) の、WPF / MFC 版 (必要になったら)。(c) 「中程度」の優先度のコントロール (タブの配置スタイル、縦のスライダー、DomainUpDown など) は、必要になったら。
4. ~~**WinForms と C# の DLL への拡張**~~ → **完了 (2026-10-25。main にマージ済み。設計と結果は DESIGN 4.30、`CHANGELOG.md` 2.6.0〜2.10.1)。** `new-solution --type csharp-dll` / `--type winforms` (MVP。層なしでも、アプリ内の Presenter をテストできる)、WinForms の UI テスト (FlaUI)、`winforms-check` と `rules/winforms-csharp.md`、スクリーンショットの DPI 対応 (WinForms / WPF / MFC)、ウォッチャーの遅延検出、`build_test_once.sh` の要約の行。**実機で、必須・推奨の項目は、すべて確認済み。任意で未確認:** H7 (C++ のみで起動したあとに、.NET の UI テストを足す)、H8 (存在しない `-SolutionPath` の明示)、WC3 (手元の既存の WinForms プロジェクトでの `winforms-check`)、`uitest_once.sh` の要約の行、125% 以外の表示倍率・複数モニターでのスクリーンショット、各 UI テストで約 2 秒かかる待ちの原因 (3 件で 8 秒。許容)。TEST-PLAN の「未確認」の行 (節 1-8 の H7 / H8) を、参照。

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
| (e) `builtin-baseline` の解決 | VS 同梱の vcpkg は git のリポジトリではない。`builtin-baseline` を固定したとき、解決できるか。できなければ、別に vcpkg を取得して `VCPKG_ROOT` を向ける案 |
| (f) 初回の時間 | キャッシュなしの `vcpkg install` の所要時間 (`ui-timing` と同様に、開始と終了を記録) |
| (g) キャッシュありの時間 | `vcpkg_installed` を消して再実行したときの所要時間。ビルドが走らず、展開だけになるか |
| (h) 共有キャッシュ | ウォッチャーの環境変数 `VCPKG_BINARY_SOURCES="clear;files,<フォルダ>,readwrite"` を設定し、別のソリューションからも、ビルドなしで入るか |

PoC の手順: 使い捨ての C++ ソリューション (`MixTest` のコピー) で、`cpp_pkg.py add <dir> gtest` → `package_once.sh vcpkg install` → テストプロジェクトに `main.cpp` を足す → ビルド → 実行。
**高速化の方針 (2026-10-28):** ビルド済みの lib / ヘッダーを自前で置かず、vcpkg のバイナリキャッシュを使う。段階 1 = 既定のキャッシュ、段階 2 = 共有フォルダ (`VCPKG_BINARY_SOURCES`)、段階 3 = セットアップ時に標準のセット (gtest) を先に `vcpkg install` して温める。キーが揃うよう、`builtin-baseline`、vcpkg 本体、VS のバージョンを固定する。`vcpkg_installed` はソリューションごとに持ち、共有しない。(e)〜(h) の結果で、段階 2 / 3 を実装に入れるか決める。
**PoC の結果 (実機、2026-10-28。`GtestVcpkgPoc`、gtest 1.18.0、`x64-windows-static-md`、PlatformToolset v145、`stdcpp20`):** **vcpkg の gtest は採用できる。**

| 確認 | 結果 |
|---|---|
| (a) `gtest_main` | `lib\manual-link\` に置かれ、自動ではリンクされない。`main.cpp` なしでは `LNK2019 main` で失敗。`main.cpp` を足すと 2 件 PASSED。`gtest_main.lib` を直接リンクする方法でも PASSED (この場合のみ `Running main() from` が出る) |
| (b) ライブラリ名 | `gtestd.lib` はない。`debug\lib\gtest.lib` と `lib\gtest.lib` に分かれ、vcpkg の統合が構成ごとに `*.lib` を自動でリンクする。手当ては不要 |
| (c) 並列ビルド | `/m` で複数のノードが `vcpkg install --x-wait-for-lock` を同時に起動したが、ロック待ちが働き、エラーなし (インストールの実体は 1 回) |
| (d) CRT | Debug は `/MDd`、Release は `/MD`。LNK4098 などの警告なし。Release も 2 件 PASSED |
| (e) baseline | VS 同梱の vcpkg で `builtin-baseline` が付き、解決できた |
| (f) 初回 | キャッシュなし: 全体 35 秒 (vcpkg 自身の報告は 22 秒)。gtest はソースからビルド |
| (g) キャッシュあり | `vcpkg_installed` を消して再実行: 全体 12 秒 (vcpkg 自身は 0.2 秒)。`Restored 3 package(s)` |
| (h) 共有キャッシュ | `VCPKG_BINARY_SOURCES=clear;files,C:\vcpkg-cache,readwrite` で、復元できた。既定の archives には書かれない (`clear` が効く)。zip は 3 つ (gtest 約 14MB)。別のソリューションからの復元は、未確認 (g と同じ仕組みなので省略) |
| ログ | 要約は従来と同じ。生のログでは、`main.cpp` 方式では `Running main() from` が出ない |

**判断:**
- gtest は vcpkg に切り替える。条件: (1) テストプロジェクトに `main.cpp` (`gtest_main` ではなく、自前の `main()`) を生成する、(2) C++17 以上、(3) NuGet 方式の gtest は廃止し、フォールバックは `ThirdParty` のソース方式のまま残す (**v2.31.0 で、NuGet 方式を廃止した。DESIGN 4.50。実機の確認は、TEST-PLAN 2-14**)。
- 高速化: キャッシュありで約 23 秒短くなるだけ (固定の時間が 12 秒ある)。**既定のキャッシュ (段階 1) のみ採用。** 共有フォルダ (段階 2) は、`add-package` の手順書に、大きなライブラリ向けの任意の設定として書くだけにする。事前の温め (段階 3) はやらない。
- ベースラインの NuGet は、コピーした PoC では x64 の lib がなく、ビルドできなかった。元の NewClaudeProject で動いていたかは未確認 (コピーで `packages` が欠けた可能性)。件数の厳密な比較はできていない。
- 副次の発見: ウォッチャーの環境に `GTEST_FILTER=NoSuchTest*` が残ると、全テストが 0 件になる (ENV_ERROR)。ウォッチャーで gtest を実行する前に、`GTEST_FILTER` などを消す修正を、実装に含める。
- 実装は、これから (`new_solution.py`、`cpp_pkg.py`、`add_layer.py`、`gtest_once.sh`、`CLAUDE.md` のひな形、Skill、テスト、実機の確認)。

**影響する範囲:** `new_solution.py` (`gtest` に関する記述 46 か所)、`cpp_pkg.py` (`gtest` のプロジェクトを除外している箇所)、`cpp-test-first` の `add_layer.py`、`trigger_gtest.flag` / `gtest_once.sh`、`CLAUDE.md` のひな形、Skill 3 か所、DESIGN、テスト (`new_solution_test.sh` / `add_layer_test.sh` / `gtest_once_test.sh`)、実機の確認 (TEST-PLAN の N3 / N3a / N3b / N10 など)。
**PoC の結果によっては、「vcpkg に一元化しない」という結論もあり得る。**

## 前提 (docs/DESIGN.md 1.)

デバッグは VS で行う。ビルドする PC には、C++ ワークロード入りの VS がある。C++ / .NET のツールがない環境では、「Visual Studio Installer で、手で追加」と案内する (自動では追加できない)。

## UI デザインガイドライン (v2.26.0〜v2.27.0) の、あとの作業

`/ui-design-review` (DESIGN 4.45) を追加し (v2.26.0)、実機の確認 (TEST-PLAN 2-9。UG1〜UG5 と再確認) は、**すべて完了した** (v2.26.3)。**v2.27.0 で、生成するソリューションを、ガイドラインに合わせた** (DESIGN 4.46)。

1. **v2.27.0 の実機のビルドと実行の確認 (TEST-PLAN 2-10 の TP1〜TP4)。** 特に、WinForms の `ApplicationHighDpiMode` (動作が変わる)、MFC の `SetProcessDPIAware()` と Common Controls のコンパイラ指令 (ビルドが通るか)。
2. ~~UI-LOC-001 (表示文字列のリソース化) を、ひな形の既定にするか、決める~~ → **不要 (2026-10-31、ユーザーの決定)。ひな形は、ローカライズの仕組みを、入れない。** 生成直後の WPF の `UIG-LOC001` (1 件) は、既知の指摘として残す。ローカライズが要る画面だけ、本来の指摘として扱う (入れるなら、WPF は、`Strings.xaml` (または `.resx`)、ViewModel の文字列も対象)。
3. MFC の DPI 認識を、マニフェスト (`AdditionalManifestFiles` など) での宣言に移す (実機のビルドで、書き方を確かめてから)。
4. 「既知の指摘」の質問を、指摘ごとにする (`ui-test-first`。運用して不都合があれば)。
5. (任意) `/new-solution` が作る `CLAUDE.md` に、ガイドラインの案内を 1 行足す。
6. (任意) 検査の追加: 見た目に近い規則 (例: UI-KEY-003 のタブ停止、UI-CTL-024 のパスワードの伏せ字) の、静的な検出。
7. **ガイドラインの更新:** 新しい版が出たら、`skills/ui-design-review/references/UI-Design-Guidelines.md` を置き換え、`GUIDELINE_VERSION` (`ui_guideline_check.py`) を合わせる。規則 ID の対応は、テストが確かめる。
