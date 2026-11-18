# 次の作業 (再開用メモ)

2026-11-18 時点 (v2.98.0。`claude-spec-workflow` は v1.8.0)。**画面モデル (PR A〜C。v2.91.0〜v2.96.0) は、実装・実機確認 (TEST-PLAN 2-57 の SM1〜SM10) とも済み。** 残っているのは、画面モデルの仕上げ (下の「0」)、任意の確認、条件が整ってから行うもの、判断待ちのものだけ。
各項目の状況は `docs/REMAINING-CHECKS.md`、手順と結果は `docs/TEST-PLAN.md`、変更の一覧は `CHANGELOG.md`。以前の版のこのメモ (手順や依頼文) は、git の履歴にある。
画面モデルの引き継ぎ (`docs/HANDOFF-2026-11-17.md`) の 5 章の A (画面モデルの仕上げ) は、すべて済み。B (低優先・保留) は、下の「0」に要約した。C (運用) は、2026-11-17 に済み (下の「1」)。D は、下の「2」。

## 0. 画面モデルの仕上げ (2026-11-17)

- **MFC の SDI・MDI:** ひな形は、旧形のまま。Document/View (メインの `CView`) だけが、画面モデルの例外と、明記した (2026-11-17。ダイアログ・`CFormView`・画面 DLL は、画面モデルで作る)。Document/View への適用は、実アプリで必要になったとき。
- **実機で未確認 → 条件つきに整理 (2026-11-17。DESIGN 4.85):** **SM11** は、SM10 (v2.96.0 の生成物。`framework.h` の指令に `#ifdef UNICODE` がなく、ビルド `SUCCESS`) で確認済み。**MFC の言語切り替え (`SetThreadUILanguage`)** は、国際化 (下の「低優先・保留」) の一部で、実装がないので、確認する対象がない (国際化を実装するときに、実機で確認する)。**MFC のダイアログでの `ON_UPDATE_COMMAND_UI`** は、設計が使わない (ダイアログは、`OnModelChanged` の最後で `EnableWindow`。`ON_UPDATE_COMMAND_UI` は、メニュー・ツールバー用に限る。ダイアログのひな形には、メニューがない)。メニューを持つダイアログを作るときに、確認する。
- **規約サイズの余裕 (v2.96.8 で、広げた):** `csharp-test-first` の `SKILL.md` 31298/32000 (余裕 702)、WinForms の規約 + 共通 38230/40000 (1770)、WPF の規約 + 共通 42250/44000 (1750)。`csharp-test-first` の `SKILL.md` は、残りが、テストで中身を確かめている節 (空フォルダの案内、作業フォルダ、`test_guard`) なので、これ以上は、移せない。足すときは、`references` へ。
- **低優先・保留:** 国際化 (リソースへの移行、`APP_CULTURE`、Satellite DLL)、非同期 `Commit()`、`switch (nID)` の `mfc-check` の検査、C# で複数プロパティの変更をまとめる必要、MFC の `Observable` の継続的な検証。

## 1. 任意の確認

- **プロジェクト単位のビルド・テスト (`--project <名前>`。DESIGN 4.92) の実機確認 (TEST-PLAN 2-58。2026-11-18): PS1〜PS5・PS7〜PS9 は合格 (不具合 3 件を v2.98.1〜v2.98.3 で修正)。PS11 は差なし。残り: PS6 (UI テスト、`uitest_once.sh --project`)、MFC のソリューションでの確認。PS10 は省略。**
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
- **済み (v2.97.0。実機の確認は未):** `ExtLayerApi.h` (MFC 拡張 DLL の公開ヘッダーのひな形) に「公開ヘッダーは、自分で `<afxwin.h>` を include する」の注意書きを足した。
- **MFC の生成物の、残り (v2.60.x):**
  - **C++ のプラットフォーム (Win32 / x64) (v2.62.0。実機の確認 ✔、TEST-PLAN 2-38 の W1〜W8)。** `/new-solution --platforms` と `/add-project platform`。W3 (MFC 拡張・標準 DLL の層) は、ビルドだけの確認で、Win32 でのテストの実行は、確認していない (任意)。
  - **メニューとダイアログの文言を日本語にした (v2.60.4。決定済み。実機の確認 ✔、TEST-PLAN 2-37)。** **`/add-project ui-host` の `.rc` も、日本語にした (v2.97.0。UTF-8 BOM 付き、`#pragma code_page(65001)`、`LANG_JAPANESE`。メインの `.rc` と同じ書き方。実機の確認 (ビルドと表示) は未)。**
  - **`mfc-check` の MDI の静的検査 (MDI001) は、済み (v2.97.1。静的テストのみ。実機の確認は不要: 検査自体が、実機で見つけた不具合の再発防止)。**
  - **`auto-build` / `build-test-loop` の SKILL:** `MSB4126` の注記を足した (v2.97.0。ウォッチャーの Platform 引数を疑う)。「ウォッチャーが起動済みかを、質問ツールで尋ねない (`WATCHER_NOT_RUNNING` のときだけ依頼する)」を入れるかは、再び出たら決める (W5 の `console` で 1 回)。
- **UI ガイドライン (v2.26.0〜v2.27.0) の、残り:**
  - **「既知の指摘」の質問を、指摘ごとにする** (`ui-test-first`)。運用して、不都合が出たときに行う。
  - **済み (v2.97.2):** `/new-solution` が作る `CLAUDE.md` (MFC・WPF・WinForms) に、`/ui-design-review` の案内を 1 行足した。
  - **見た目に近い規則の、静的な検出:** UI-CTL-024 (パスワードの伏せ字) は、済み (v2.97.2。`UIG-CTL024`。コントロールの名前による推測)。**UI-KEY-003 (タブ停止) は、足していない** (WPF の `Focusable` / `IsTabStop`、WinForms の `TabStop` の組み合わせが多く、誤検出が増えやすい。必要になったとき)。
  - **ガイドラインの更新:** 新しい版が出たら、`skills/ui-design-review/references/UI-Design-Guidelines.md` を置き換え、`GUIDELINE_VERSION` (`ui_guideline_check.py`) を合わせる。規則 ID の対応は、テストが確かめる。

## 3. 完了したもの (要約。詳細は DESIGN と CHANGELOG)

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
