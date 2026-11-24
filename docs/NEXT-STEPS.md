# 次の作業 (再開用メモ)

2026-11-24 時点 (v2.102.7。最新の引き継ぎは `docs/HANDOFF-2026-11-24.md`。以下の本文は、2026-11-19 時点の記述に、2026-11-23〜24 の更新を足したもの。v2.99.4 時点: `claude-spec-workflow` は v1.8.0)。**実装も、実機の確認も、済んでいる** (画面モデル v2.91.0〜v2.96.0、プロジェクト単位のビルド・テスト `--project` v2.98.x、`vs-debug` のデバッグ出力・ブレーク時の状態の取り込み v2.99.x、ui-host の日本語 `.rc`)。残っているのは、**判断待ち (「2」)、実機で未確認の小さなもの (「1」)、任意の確認、条件が整ってから行うもの**だけ。**現状の引き継ぎは `docs/HANDOFF-2026-11-18.md` (最初に読む)。**
各項目の状況は `docs/REMAINING-CHECKS.md`、手順と結果は `docs/TEST-PLAN.md`、変更の一覧は `CHANGELOG.md`。以前の版のこのメモ (手順や依頼文) は、git の履歴にある。
(画面モデルの旧い引き継ぎ `HANDOFF-2026-11-17.md` は、古く、不要。リポジトリには、ない。)

## 0. 画面モデルの仕上げ (済み。2026-11-17〜19)

- **MFC の SDI・MDI:** ひな形は、旧形のまま。Document/View (メインの `CView`) だけが、画面モデルの例外と、明記した (2026-11-17。ダイアログ・`CFormView`・画面 DLL は、画面モデルで作る)。Document/View への適用は、実アプリで必要になったとき。
- **実機で未確認 → 条件つきに整理 (2026-11-17。DESIGN 4.85):** **SM11** は、SM10 (v2.96.0 の生成物。`framework.h` の指令に `#ifdef UNICODE` がなく、ビルド `SUCCESS`) で確認済み。**MFC の言語切り替え (`SetThreadUILanguage`)** は、国際化 (下の「低優先・保留」) の一部で、実装がないので、確認する対象がない (国際化を実装するときに、実機で確認する)。**MFC のダイアログでの `ON_UPDATE_COMMAND_UI`** は、設計が使わない (ダイアログは、`OnModelChanged` の最後で `EnableWindow`。`ON_UPDATE_COMMAND_UI` は、メニュー・ツールバー用に限る。ダイアログのひな形には、メニューがない)。メニューを持つダイアログを作るときに、確認する。
- **規約サイズの余裕 (v2.96.8 で、広げた):** `csharp-test-first` の `SKILL.md` 31298/32000 (余裕 702)、WinForms の規約 + 共通 38230/40000 (1770)、WPF の規約 + 共通 42250/44000 (1750)。`csharp-test-first` の `SKILL.md` は、残りが、テストで中身を確かめている節 (空フォルダの案内、作業フォルダ、`test_guard`) なので、これ以上は、移せない。足すときは、`references` へ。
- **低優先・保留:** 国際化 (リソースへの移行、`APP_CULTURE`、Satellite DLL)、非同期 `Commit()`、`switch (nID)` の `mfc-check` の検査、C# で複数プロパティの変更をまとめる必要、MFC の `Observable` の継続的な検証。
- **決定 (ユーザー、2026-11-19。蒸し返さない):** (1) 画面モデルの名前は **`ScreenModel` のまま** (`FormModel` への変更案は、MFC の `CFormView` との紛らわしさ、WPF に Form がないこと、変更の費用の大きさで、見送った。変えるなら `WindowModel`)。(2) **規約の `paths` から Presenter を外した** (v2.98.14。`winforms-csharp.md` は `*.Designer.cs` と `Forms/`、`winforms-view-model.md` は `ScreenModels/` と `*ScreenModel*.cs` だけ)。(3) `claude-spec-workflow` の `brainstormF` に、検査・失敗の観点は、**足さない**。(4) VO2 (VS の英語の表示言語での `--output`) は、確認しない。

## 1. 実機の確認 (未了のものと、任意のもの)

- **(済み 2026-11-24) `vs-debug` のステップ実行・式の評価 (v2.101.0、TEST-PLAN 2-63): SP1〜SP12 がすべて合格** (SP11 は観察。通しのバグ探しも合格)。**改善の候補 (小さい。ユーザーの判断待ち):** (1) 1 回の `--debug --inspect` で `INSPECT_SKIP: the mode is run` になることがあった (初回の起動が 20 秒を超えたとみられる。`$VsBreakWaitSec` を延ばす、または、`--inspect` の前に break を待つ)。生の出力が残っておらず、未確定。(2) 最適化されたモジュールの変数の長い文面 (6 行) を、短くする。(3) `int` の値が 16 進 (`0x00000003`) で出る。10 進にするか。(4) 続行の直後の `STOPPED:` に、場所が付かないことがある。
- **(済み 2026-11-23) `git-remote` (v2.102.x、TEST-PLAN 2-64): GR1〜GR5、GR8〜GR14 が合格。** 未確認は、GR6・GR7 (GitHub 以外のリモート、未サインイン。リモートがない)、GR9 の後半、GR12 の強制終了。**決定済み (2026-11-23、v2.102.4):** `rules/git-wsl.md` に、サンドボックスの空ファイルの注意書きを足した。`git-remote` の push の前の `--status` は、ユーザーが内容を指定したときは、省いてよい。**pull は、見送り (ユーザーの決定、2026-11-24)。** 運用は、`rules/git-wsl.md` に盛り込んだ (v2.102.6)。再検討の目安: 「取り込む前の確認」(B)、または `pull --ff-only` の条件つき実装 (C)。
- **(済み 2026-11-23) v2.100.0・v2.100.1 (MFC の `C` 接頭辞なし、SDI の `ID_FILE_OPEN`): TEST-PLAN 2-61 の CP1〜CP5 と 2-62 の MO3・MO4 は、すべて合格。** **未確認で残るのは、`vs-debug` のステップ実行・式の評価 (v2.101.0、TEST-PLAN 2-63 の SP1〜SP12。PowerShell を、一度も実行していない)。** 確認の順: PS5 に一時的なコード (`// SP-TEMP`) を足す → 既存機能の回帰 (`--debug --inspect --output`) → SP9 → SP1・SP2・SP10 → SP8 → SP3 → SP6・SP7 → SP5 → SP4 (モーダルダイアログ。最も危ない) → SP11 → SP12 (通し) → 一時的なコードを戻す。
- **次の予定 (ユーザー。着手の指示を待つ):** SDI・MDI などの初期状態を、Visual Studio のウィザードが作るものに近づける調整。着手の前に、ウィザードと離れているのが具体的にどこか、どのウィザードの設定を基準にするかを聞く。
- **プロジェクト単位のビルド・テスト (`--project <名前>`。DESIGN 4.92) の実機確認 (TEST-PLAN 2-58。2026-11-18): PS1〜PS9 は合格 (不具合 3 件を v2.98.1〜v2.98.3 で修正。PS6 の UI テストも合格)。PS11 は差なし。PS10 は省略。MFC のソリューションでも合格 (2026-11-18)。**実機の確認は、すべて終わった**。未確認は、大きいソリューションでの時間だけ。**
- **実機で未確認 (規約・Skill を、すでに変えたもの。小さい。GW1〜GW3 は済み):**
  - **(済み 2026-11-19) GW1〜GW3 (TEST-PLAN 2-54): `rules/git-wsl.md` (v2.88.0) の実機の確認は、すべて合格** (VS で作ったリポジトリで、Claude Code と VS を往復。規約の修正は不要)。
  - **`ExtLayerApi.h` の注意書き (v2.97.0):** 「公開ヘッダーは、自分で `<afxwin.h>` を include する」。Claude が、確認用ソリューションで行う。
  - **任意:** ST5 (`SetText` の、読み戻しが合わない部品のフォールバック)、UJ5 (VS のリソース ビューで、日本語の `.rc` を開く)、`--project` の、大きいソリューションでの時間。
  - **`vs-debug` の `--output` / `--inspect` (v2.99.x、TEST-PLAN 2-60): VO2 (英語の VS) を除いて、実機の確認は済み。** `STACK:` にファイルと行が付かないのは、`StackFrame` の `FileName` が `DTE2` 側にあるため (`STOPPED:` に、最上位の場所が出る)。
- **すぐに確認できるもの** (詳細は `REMAINING-CHECKS.md` の「2-2」):
  - **MFC の状態を使う関数を、MFC なしの exe から呼ぶ:** DLL008 の「実行時に壊れる」が、本当に起きるか (`CString`・ダイアログ・リソースなど。DC4 の実行時の確認 (2026-11-08) では、MFC の状態を使わない関数だけで、通った)。Claude が、確認用のソリューションで行う (ウォッチャーが要る)。
  - **SD の実行時:** `AFX_MANAGE_STATE` を外して、MFC のダイアログを使う関数にして動かす (生成の確認は、静的に済み、2026-11-08)。Claude が行う。
  - **Visual Studio での目視 (ユーザーの作業):** MX・SD のプロパティページ、UH4 (画面を持つ DLL の見た目)、AR (「参照」の画面)。
- **済み (2026-11-08):** DC4 の実行時 (MFC のメインは、`UseOfMfc` を外すと、ビルド `C1189` で止まる。テスト exe は DLL008 の対象外)、MX の `AFX_EXT_CLASS` (別の exe から使える。外すと LNK2019 / LNK2001)。
- **済み・閉じたもの (任意の確認には、含めない):** WS1〜WS4・CS1・CS2 は ✔ (2026-11-04)、SK2・SK3 は ✔ (2026-11-02)、**SK1 は、実機の確認を、行わない** (ユーザーの決定。TEST-PLAN 2-20)。
- **条件が整うまで保留 (△):** T6、N0、N3s、TG1、TG3、UG3・UG4・UG4b、WC4。理由と再開条件は、`REMAINING-CHECKS.md` の「2-3」。
- **済み (2026-11-17):** 確認用フォルダの後片付け。`CSharpTF` の確認用フォルダ (`SM1`〜`SM10`、`wpfcutE`、`plchk`、`mfcw*`・`mfcj*`・`plW*` ほか、すべて) と、ホームの `~/dcbak`、`~/mfcdlg-CLAUDE.md.bak`、`~/ap5-*.txt` を、削除した (ユーザーの作業。空になったことを確認した)。マージ済みのローカルブランチ (`claude-windows-desktop-tools` 21 本、`claude-spec-workflow` 10 本) も、削除した。
- **済み (v2.97.4):** PR #179 (`nsp-realmachine`。NSP001/DEC001 の実機確認 NS-1〜NS-3 の記録) の内容を、現在の `main` に入れ直した (TEST-PLAN 2-55 の NS-1〜NS-3 が ✔、`rules/mfc-cpp.md` に確認した事実)。#179 は、新しい PR で入れ直したと書いて、閉じる。

## 2. 判断待ち・任意の機能

- **A: 既存コードから、仕様を逆生成する新 Skill。** 既存の MFC・WPF のプロジェクトを、仕様駆動 (`claude-spec-workflow`) へ移す予定があるかで、決める。作るなら大きい作業。
- **B: 混在のソリューション (WPF + C++ の層など) を、`/new-solution` が、正式に作れるようにするか。** いまは、WPF などに `add_layer.py` で C++ を足す、即席の形 (2026-11-18 の実機の確認で、`.slnx` に `x64` の構成がなく、全体のビルドが `MSB4126` になる不具合を見つけて、v2.98.2 で直した)。正式に作れるようにするか、「即席」と明記し続けるかを、決める。
- **E: MFC のひな形の、任意の改善 (v2.100.1 の引き継ぎ文書より。今回は、やらなかった):** (1) MDI の `SampleApp` のメッセージマップにも、`ON_COMMAND(ID_FILE_OPEN, &CWinApp::OnFileOpen)` を、予防的に足す (MDI の既定の `.rc` には「開く」がなく、今は症状が出ない。ユーザーが、あとから、足したときに、SDI と同じ不具合を踏む)。(2) `mfc-check` に、`CWinApp` 派生クラスのメッセージマップが、`.rc` のメニューの標準 ID (`ID_FILE_NEW`・`ID_FILE_OPEN`・`ID_FILE_PRINT_SETUP` ほか) を、結びつけているかの検査 (`APP001`) を足す (標準 ID を、接頭辞で「見つかった」扱いにする設計なので、今回の不具合を見逃した。優先度は低い)。
- **C: `--project` で、本体とテストの MSBuild を 1 回にまとめる** (固定の初期化の費用を減らす。小さいソリューションでは、差がなかった。遅くて困る例が出てから)。
- **D: アプリが、決まった場所にログのファイルを書く規約** (`vs-debug` の案 B。UI テストなど、VS を使わない実行でも、解析したくなったとき。ひな形と規約を、WPF・WinForms・MFC に足す。大きい)。
- **済み (v2.97.0。実機の確認は未):** `ExtLayerApi.h` (MFC 拡張 DLL の公開ヘッダーのひな形) に「公開ヘッダーは、自分で `<afxwin.h>` を include する」の注意書きを足した。
- **MFC の生成物の、残り (v2.60.x):**
  - **C++ のプラットフォーム (Win32 / x64) (v2.62.0。実機の確認 ✔、TEST-PLAN 2-38 の W1〜W8)。** `/new-solution --platforms` と `/add-project platform`。W3 (MFC 拡張・標準 DLL の層) は、ビルドだけの確認で、Win32 でのテストの実行は、確認していない (任意)。
  - **メニューとダイアログの文言を日本語にした (v2.60.4。決定済み。実機の確認 ✔、TEST-PLAN 2-37)。** **`/add-project ui-host` の `.rc` も、日本語にした (v2.97.0。UTF-8 BOM 付き、`#pragma code_page(65001)`、`LANG_JAPANESE`。メインの `.rc` と同じ書き方。実機の確認 ✔ (2026-11-18、TEST-PLAN 2-59): ビルド `SUCCESS`・`rc.exe` の警告なし、UI テスト `PASSED`、ダイアログの表示は、日本語のまま、文字化けなし)。**
  - **`mfc-check` の MDI の静的検査 (MDI001) は、済み (v2.97.1。静的テストのみ。実機の確認は不要: 検査自体が、実機で見つけた不具合の再発防止)。**
  - **`auto-build` / `build-test-loop` の SKILL:** `MSB4126` の注記を足した (v2.97.0。ウォッチャーの Platform 引数を疑う)。「ウォッチャーが起動済みかを、質問ツールで尋ねない (`WATCHER_NOT_RUNNING` のときだけ依頼する)」を入れるかは、再び出たら決める (W5 の `console` で 1 回)。
- **UI ガイドライン (v2.26.0〜v2.27.0) の、残り:**
  - **「既知の指摘」の質問を、指摘ごとにする** (`ui-test-first`)。運用して、不都合が出たときに行う。
  - **済み (v2.97.2):** `/new-solution` が作る `CLAUDE.md` (MFC・WPF・WinForms) に、`/ui-design-review` の案内を 1 行足した。
  - **見た目に近い規則の、静的な検出:** UI-CTL-024 (パスワードの伏せ字) は、済み (v2.97.2。`UIG-CTL024`。コントロールの名前による推測)。**UI-KEY-003 (タブ停止) は、足していない** (WPF の `Focusable` / `IsTabStop`、WinForms の `TabStop` の組み合わせが多く、誤検出が増えやすい。必要になったとき)。
  - **ガイドラインの更新:** 新しい版が出たら、`skills/ui-design-review/references/UI-Design-Guidelines.md` を置き換え、`GUIDELINE_VERSION` (`ui_guideline_check.py`) を合わせる。規則 ID の対応は、テストが確かめる。

## 3. 完了したもの (要約。詳細は DESIGN と CHANGELOG)

- **v2.97.0〜v2.99.3 (2026-11-17〜19):** 画面モデルの仕上げ (MDI001、UIG-CTL024、ui-host の日本語 `.rc`)、**プロジェクト単位のビルド・テスト `--project`** (実機で、不具合 3 件を見つけて直した。MFC・WPF + C++・UI テストで確認)、**`vs-debug` の `--output` / `--inspect`** (出力ウィンドウの「デバッグ」ペインと、ブレーク時の例外・呼び出し履歴・変数。`ToolWindows` が見えない問題を、診断で特定して直した)、README・USAGE・HANDOFF の更新、規約の `paths` から Presenter を外した。
- **C++ と WPF の統合、WinForms と C# DLL への拡張** (v2.4.x〜v2.10.1): 実機の確認まで完了。
- **GoogleTest の vcpkg への一元化** (v2.21.0。DESIGN 4.41)。旧 NuGet 方式は、v2.31.0 で廃止した (DESIGN 4.50)。
- **ダイアログのテスト** (v2.17.0)。**3 層のモジュール名の変更は、取り下げた** (既定の名前は `LogicLayer` / `DataLayer`。作成後に、個別にリネームする)。
- **UI デザインガイドライン** (`/ui-design-review`、v2.26.0〜v2.27.1): 実機の確認 (UG1〜UG5、TP1〜TP4) まで完了。MFC の DPI 認識は、マニフェストでの宣言にした (MF2・MF3 ✔)。ローカライズの仕組みは、ひな形に入れない (2026-10-31、決定)。
- **改名** (`claude-windows-desktop-tools`、v2.42.0)、**ウォッチャーの `lib\` 分割** (v2.43.0)、**仕様づくりの 3 Skill を `claude-spec-workflow` へ移動** (v2.44.0)。
- **MFC の拡張 DLL・標準 DLL の生成と `mfc-check` の DLL の検査、画面を持つ DLL の画面ホストと UI テスト** (v2.45.0〜v2.50.0)。
- **`/add-project`、`solution_state.py`、`add_reference.py`** (v2.52.0〜v2.55.1): 層・テスト・画面の追加、参照の追加、切り出し。実機の確認 (AP1〜AP6、AR1〜AR5、CUT-A〜D) まで完了。
- **`HOST_VERSION`** (v2.56.0)、**利用ガイド `docs/USAGE.md`** (v2.56.1)、**テストの中身の点検 `test_guard.py audit` と変異の確認** (v2.57.0)。
- **`<Skill群>` の表記と、プロジェクトの `.claude/skills` への配布** (v2.58.0): 実機の確認 (PL1・PL2) まで完了。両方にあるときは、ホームが優先される。
- **WPF の MVVM の基底の明示** (v2.59.0・v2.59.1): 推奨は CommunityToolkit.Mvvm。Prism は、使うのは自由だが、推奨しない。
- **`claude-spec-workflow`** (v1.0.0〜v1.8.0。v1.8.0 で、画面モデルの採用に追随した (`add-feature` の画面モデルのタスク、`update-from-ideas` の WinForms の表記)。`brainstormF` の、検査・失敗の観点は、足していない): `/add-feature` が、`add-package` と連携し (v1.6.0)、層の追加を `/add-project` にそろえた (v1.7.0)。実機の確認 (`wpfcutE`) まで完了。

## 運用メモ (マージ・配置)

- **コミットは、ユーザーが明示的に指示したときだけ。push は、ユーザーが行う (`git push -u origin <ブランチ>` など)。マージも、ユーザーが決める。** 新しい作業は、`main` から、新しいブランチを切って行う。コミットの前に、`git branch --show-current` を確認する (別の端末で切り替えたブランチに、コミットしないため)。
- 配置: `./install/install.sh` (Skill・規約。`--skills-only` / `--rules-only` / `--host-only`)、`~/src/copy-host-tools.sh` (ホスト側ツール)。`claude-spec-workflow` の配布は、そのリポジトリの `install/install.sh`。**Skill やスクリプトを変えたら、再配置を忘れない** (確認のやり直しの、最大の原因だった)。配布のあとは、配布先の `VERSION` で、確かめる。
- 実機の確認は、**新しい Claude Code のセッション**で行う (起動中のセッションには、配布が反映されない。同じセッションで `/brainstorm` のあとに `/add-feature` を走らせると、前の結論が残り、質問が出ない)。
- 配布先 (`~/.claude/skills` など) は、**直接、編集しない** (リポジトリを直して、配り直す)。

## 前提 (`docs/DESIGN.md` 1.)

デバッグは VS で行う。ビルドする PC には、C++ ワークロード入りの VS がある。C++ / .NET のツールがない環境では、「Visual Studio Installer で、手で追加」と案内する (自動では追加できない)。
