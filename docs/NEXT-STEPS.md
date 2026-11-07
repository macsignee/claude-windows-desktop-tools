# 次の作業 (再開用メモ)

2026-11-08 時点 (v2.59.4。`claude-spec-workflow` は v1.7.2)。**必須の残り作業は、ない。** 残っているのは、任意の確認、条件が整ってから行うもの、判断待ちのものだけ。
各項目の状況は `docs/REMAINING-CHECKS.md`、手順と結果は `docs/TEST-PLAN.md`、変更の一覧は `CHANGELOG.md`。以前の版のこのメモ (手順や依頼文) は、git の履歴にある。

## 1. 任意の確認

- **すぐに確認できるもの** (詳細は `REMAINING-CHECKS.md` の「2-2」):
  - **MFC の状態を使う関数を、MFC なしの exe から呼ぶ:** DLL008 の「実行時に壊れる」が、本当に起きるか (`CString`・ダイアログ・リソースなど。DC4 の実行時の確認 (2026-11-08) では、MFC の状態を使わない関数だけで、通った)。Claude が、確認用のソリューションで行う (ウォッチャーが要る)。
  - **SD の実行時:** `AFX_MANAGE_STATE` を外して、MFC のダイアログを使う関数にして動かす (生成の確認は、静的に済み、2026-11-08)。Claude が行う。
  - **Visual Studio での目視 (ユーザーの作業):** MX・SD のプロパティページ、UH4 (画面を持つ DLL の見た目)、AR (「参照」の画面)。
- **済み (2026-11-08):** DC4 の実行時 (MFC のメインは、`UseOfMfc` を外すと、ビルド `C1189` で止まる。テスト exe は DLL008 の対象外)、MX の `AFX_EXT_CLASS` (別の exe から使える。外すと LNK2019 / LNK2001)。
- **済み・閉じたもの (任意の確認には、含めない):** WS1〜WS4・CS1・CS2 は ✔ (2026-11-04)、SK2・SK3 は ✔ (2026-11-02)、**SK1 は、実機の確認を、行わない** (ユーザーの決定。TEST-PLAN 2-20)。
- **条件が整うまで保留 (△):** T6、N0、N3s、TG1、TG3、UG3・UG4・UG4b、WC4。理由と再開条件は、`REMAINING-CHECKS.md` の「2-3」。
- **確認用のフォルダの後片付け (ユーザーの作業):** `CSharpTF` の `wpfcutE`、`plchk`、`plchk2` ほか。ホームの `~/dcbak`、`~/mfcdlg-CLAUDE.md.bak`、`~/ap5-*.txt`。

## 2. 判断待ち・任意の機能

- **A: 既存コードから、仕様を逆生成する新 Skill。** 既存の MFC・WPF のプロジェクトを、仕様駆動 (`claude-spec-workflow`) へ移す予定があるかで、決める。作るなら大きい作業。
- **`ExtLayerApi.h` の注意書き:** 「公開ヘッダーは、自分で `<afxwin.h>` を include する」を足す (MX の確認で、プリコンパイル済みヘッダーのないテスト exe で、`BUILD_FAILED` になった。TEST-PLAN 2-25)。ひな形 (`new_solution.py` の生成部分) の変更と、テストが要る (配布が要る版)。
- **MFC の生成物の、残り (v2.60.x):**
  - **v2.61.0: Win32 の構成** (メイン・層・テスト・画面ホストの `.vcxproj`、`.slnx` の x86、GoogleTest の `x86-windows-static-md`)。環境で x86 のビルドができることは、確認済み (TEST-PLAN 2-36 の WZ4)。
  - **メニューとダイアログの文言を日本語にした (v2.60.4。決定済み。実機の確認 ✔、TEST-PLAN 2-37)。** **`/add-project ui-host` の画面ホストの `.rc` は、英語のまま** (直す候補)。
  - **`mfc-check` の MDI の静的検査:** `OnCreateClient` の上書きと、`IDR_MAINFRAME` のメニューの数 (v2.60.1 の不具合を、起動せずに見つける)。任意。
  - **`auto-build` / `build-test-loop` の SKILL:** 「`MSB4126` で、構成に `Win32` と出たら、ウォッチャーの Platform 引数を疑う」。任意。
- **UI ガイドライン (v2.26.0〜v2.27.0) の、残り:**
  - **「既知の指摘」の質問を、指摘ごとにする** (`ui-test-first`)。運用して、不都合が出たときに行う。
  - **`/new-solution` が作る `CLAUDE.md` に、ガイドラインの案内を 1 行足す** (任意)。
  - **見た目に近い規則の、静的な検出** (任意。例: UI-KEY-003 のタブ停止、UI-CTL-024 のパスワードの伏せ字)。
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
- **`claude-spec-workflow`** (v1.0.0〜v1.7.2): `/add-feature` が、`add-package` と連携し (v1.6.0)、層の追加を `/add-project` にそろえた (v1.7.0)。実機の確認 (`wpfcutE`) まで完了。

## 運用メモ (マージ・配置)

- **コミットは、ユーザーが明示的に指示したときだけ。push は、ユーザーが行う (`git push -u origin <ブランチ>` など)。マージも、ユーザーが決める。** 新しい作業は、`main` から、新しいブランチを切って行う。コミットの前に、`git branch --show-current` を確認する (別の端末で切り替えたブランチに、コミットしないため)。
- 配置: `./install/install.sh` (Skill・規約。`--skills-only` / `--rules-only` / `--host-only`)、`~/src/copy-host-tools.sh` (ホスト側ツール)。`claude-spec-workflow` の配布は、そのリポジトリの `install/install.sh`。**Skill やスクリプトを変えたら、再配置を忘れない** (確認のやり直しの、最大の原因だった)。配布のあとは、配布先の `VERSION` で、確かめる。
- 実機の確認は、**新しい Claude Code のセッション**で行う (起動中のセッションには、配布が反映されない。同じセッションで `/brainstorm` のあとに `/add-feature` を走らせると、前の結論が残り、質問が出ない)。
- 配布先 (`~/.claude/skills` など) は、**直接、編集しない** (リポジトリを直して、配り直す)。

## 前提 (`docs/DESIGN.md` 1.)

デバッグは VS で行う。ビルドする PC には、C++ ワークロード入りの VS がある。C++ / .NET のツールがない環境では、「Visual Studio Installer で、手で追加」と案内する (自動では追加できない)。
