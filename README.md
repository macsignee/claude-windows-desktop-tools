# claude-windows-desktop-tools

Claude Code (WSL) が、Windows 側の Visual Studio で、**C++ (MFC・Win32・DLL。GoogleTest) と .NET (WPF / WinForms / C# クラスライブラリ。MSTest) の、ソリューションの作成・ビルド・テスト・UI テストを実行し、エラーや失敗を自分で直す**ためのツール一式。Visual Studio そのものも、WSL から操作できる (開く・ブレークポイント・デバッグ実行。→ 「2-8」)。

- **使い方 (どのコマンドを打つか、承認の言い方、困ったとき) は、[`docs/USAGE.md`](docs/USAGE.md)。まず、これを読む。**
- C++ のみ、.NET のみ、混在のソリューションのどれでも、同じ Skill と同じウォッチャーで使う (ソリューションの中身から、自動で判定する。[設計メモ 4.24](docs/DESIGN.md))。
- **テスト先行 (TDD) の流れを支える。** ロジック層・データ層・画面モデル (WPF は ViewModel、WinForms・MFC は ScreenModel) では、テストを先に書いて Red を確認し、実装して Green にする。画面は、UI テストを先に書く (`/ui-test-first`)。1 タスクごとに、テストを数件まとめて回す (1 件ずつではない。→ 「2-5」)。
- **ソリューション全体でも、プロジェクト単位でも、回せる。** `--project OrderLogic` と書くだけで、その層と、名前から推測したテスト (`OrderLogicTest` / `OrderLogic.Tests` / `OrderLogic.UITests`) だけを、ビルド・実行する (→ 「2-6」)。
- **画面は、画面モデルを通して作る** (v2.92.0〜)。WPF は `ViewModel`、WinForms と MFC は `<画面名>ScreenModel` が、状態・入力の検査・失敗の表示を持ち、フォームは表示と操作の受け渡しだけをする。WinForms と MFC のダイアログ、WPF の画面とも、ひな形が、この構成で作る (→ 「2-3」。設計は [`docs/UI-MODEL-GUIDE.md`](docs/UI-MODEL-GUIDE.md))。
- 仕様の整理 (`/brainstorm` → `/update-from-ideas`) と機能の追加 (`/add-feature`) は、別リポジトリ [`claude-spec-workflow`](https://github.com/macsignee/claude-spec-workflow) (→ 「2-4」)。

Claude Code のサンドボックスからは、Windows 側の MSBuild やテスト exe を、直接実行できない。そこで、Windows 側にウォッチャーを常駐させ、Claude は、フラグファイルを置いて、結果ファイルを読むだけにしている。

```
Claude Code (WSL)  ──trigger_*.flag──▶  Windows: watch_and_build.ps1 ─▶ MSBuild / テスト exe / Visual Studio (DTE)
                   ◀──*_result.txt / *_error.log──
```

## 目次

1. [フォルダの構成](#1-フォルダの構成)
2. [Skill](#2-skill-skills)
3. [規約・ひな形・道具](#3-規約ひな形道具-rules--templates--scripts)
4. [ホスト側ツール](#4-ホスト側ツール-host-tools)
5. [配布 (インストール)](#5-配布-インストール)
6. [テスト](#6-テスト-tests)
7. [文書](#7-文書-docs)
8. [ファイル形式 (重要)](#8-ファイル形式-重要)
9. [開発の進め方](#9-開発の進め方)
10. [対応範囲](#10-対応範囲)

## 1. フォルダの構成

| フォルダ | 内容 | 配布先 |
|---|---|---|
| [`skills/`](skills/) | Claude Code の Skill (15 個。→ 「2」) | `~/.claude/skills/` (WSL)、またはプロジェクトの `.claude/skills/` |
| [`rules/`](rules/) | ユーザー共通のコーディング規約 (7 つ。→ 「3」) | `~/.claude/rules/` (WSL)、またはプロジェクトの `.claude/rules/` |
| [`templates/`](templates/) | 規約が参照する、設定ファイルのひな形 (→ 「3」) | `~/.claude/templates/` (WSL)、またはプロジェクトの `.claude/templates/` |
| [`scripts/`](scripts/) | 規約が参照する道具 (→ 「3」) | `~/.claude/scripts/` (WSL)、またはプロジェクトの `.claude/scripts/` |
| [`host-tools/`](host-tools/) | Windows 側のウォッチャーと、起動・ビルド用の `.cmd` (→ 「4」) | Windows 側の任意のフォルダ (既定: `C:\tools\claude-watcher\`) |
| [`install/`](install/) | `install.sh` (配布先へ、バイトを変えずに、コピーする。→ 「5」) | — |
| [`tools/`](tools/) | `check-formats.sh` (文字コード・改行・BOM の検証)、`token_report.py` (セッションのログの Token 集計。→ [`docs/USAGE.md`](docs/USAGE.md) の 4) | — |
| [`tests/`](tests/) | 単体テスト (`*_test.sh`)。Windows は不要 (→ 「6」) | — |
| [`docs/`](docs/) | 設計と手順の文書 (→ 「7」。`msbuild-common-repo-*` は、別リポジトリ `msbuild-common` の README・LICENSE・`install.sh` の控え) | — |

- `CHANGELOG.md`: 変更履歴。
- `VERSION`: 版。配布先にも置かれる (→ 「5」)。
- **配布先は、ホームでも、プロジェクトのリポジトリでもよい** (→ 「5-2」)。文書の `.claude/...` は、ホームの `~/.claude/...` と、プロジェクトの `.claude/...` の、どちらも指す。

## 2. Skill (`skills/`)

### 2-1. 早見

Skill は 15 個ある。**スラッシュで打って起動するもの**と、**依頼文に合わせて Claude が選ぶもの**がある (→ 「2-2」)。

- **`/new-solution`** (スラッシュ): ソリューションを 1 つ作る。
- **`/new-solutions`** (スラッシュ): 種類違いの候補を、まとめて作って比べる。
- **`/add-project`** (スラッシュ): すでにあるソリューションに、層・テスト・画面などを足す。
- **`/ui-test-first`** (スラッシュ): 画面を作りながら、UI テストを先に書く。
- **`cpp-test-first`** (依頼文): C++ で、テストを先に書いて Red を確認する。
- **`csharp-test-first`** (依頼文): WPF / WinForms で、テストを先に書いて Red を確認する。
- **`auto-build`** (依頼文): ビルドして、エラーを直す。
- **`build-test-loop`** (依頼文): ビルドとテストを通す (Green)。
- **`mfc-check`** (依頼文): MFC の、実行時に壊れる所を、静的に検査する。
- **`wpf-check`** (依頼文): WPF の、実行時に壊れる所を、静的に検査する。
- **`winforms-check`** (依頼文): WinForms の、実行時に壊れる所を、静的に検査する。
- **`ui-design-review`** (依頼文 / スラッシュ): 画面を、UI ガイドラインに沿って、設計・レビューする。
- **`add-package`** (依頼文): NuGet・vcpkg・GitHub のソースで、ライブラリを足す。
- **`vs-debug`** (依頼文): Visual Studio で、ソリューションを開く・前面に出す・ブレークポイントを置く・デバッグ実行する。VS の未保存の編集と、ぶつからないように、編集の前に確認する (→ 「2-8」)。
- **`git-remote`** (依頼文): 「push して」「fetch して」。**Windows の `git.exe` を、ウォッチャーに実行させる** (認証は VS の Git と同じ。GitHub 以外のリモートでも通る)。強制 push・削除・pull・merge は、持たない。コミットは、WSL の `git` (ユーザーが頼んだとき)。

### 2-2. 起動のしかた

Skill の起動には、スラッシュで打つものと、依頼文から自動で選ばれるものがある。

- **スラッシュコマンドだけで起動する Skill**: 依頼文では、自動では、起動しない (`disable-model-invocation: true`)。
  - 対象: `/new-solution`、`/add-project`、`/new-solutions`、`/ui-test-first`。
- **依頼文で、自動で選ばれる Skill**: description に合う依頼で起動する (「2-1」の「依頼文」)。
  - `ui-design-review` は、`/ui-design-review [画面名 / ファイル / 規則 ID]` で、引数つきの起動もできる。
- **Skill の一覧**: Claude Code の起動時に読み込まれる。
  - **配布したあとは、セッションを、新しく起動する。**
- **Skill の中のコマンドは、配布先のパスを、固定しない** (v2.58.0): `<Skill群>` を基準に書き、実行するときに、実際のパスに置き換える。
  - `<Skill群>` は、この Skill のフォルダの 1 つ上。Skill の読み込み時に、Base directory として示される。
  - ホームの `~/.claude/skills/` でも、プロジェクトの `.claude/skills/` でも、同じに動く。
- **`scripts/` と `references/`**: Skill の下にある。
  - `scripts/`: Skill が内部で呼ぶスクリプト。
  - `references/`: 必要なときだけ読む詳細 (読み込みを小さくするため)。

### 2-3. ソリューションを作る・足す

この 3 つは、スラッシュコマンドだけで起動する (依頼文では、起動しない)。

- **`/new-solution`**: カレントのフォルダに、**1 つ**のソリューションを作る。フォルダ名と同名の `.slnx`、メインのプロジェクト、層、テストを作り、`CLAUDE.md` に設定 (メイン・層・テスト) を書く。省略した引数は、質問する (`--tests` は、必ず質問する)。
  - 引数:
    - `--type`: `wpf` / `winforms` / `csharp-dll` (C# のクラスライブラリ) / `mfc` (SDI) / `mfc-mdi` / `mfc-dialog` / `win32` / `console` / `dll` / `lib` (静的ライブラリ)。
    - `--layers`: `none` / `logic` / `data` / `logic,data`。**推奨は `data,logic`** (WPF も同じ)。名前の指定は `logic:OrderLogic,data:OrderData` の形。WPF は、`viewmodel` も組み合わせられる (例: `data,logic,viewmodel`。ViewModel をテストしたいときに足す)。WinForms と `csharp-dll` は、`data` / `logic` だけ。
    - `--tests`: `none` / `gtest` (C++) / `mstest` (.NET。層のライブラリごとに `<名前>.Tests`)。
    - `--platforms`: C++ のプラットフォーム。`x64` (既定。質問しない) / `x64,Win32` (ウィザードと同じ 4 構成) / `Win32`。.NET に指定すると、エラー。あとから足すのは `/add-project platform Win32`。
    - `--ui-tests`: `none` / `flaui` (`<アプリ名>.UITests`)。省略すると `none` (質問しない)。`flaui` は、明示したときだけ。あとから足すには、`/add-project ui-tests`。ビルド → テストの流れには、含めない。
    - `--layer-kind`: C++ の層の種類。`dll` / `lib` / `mfc-lib` (MFC の静的ライブラリ) / `mfc-ext-dll` (MFC 拡張 DLL。メインが MFC のときだけ) / `mfc-std-dll` (MFC 標準 DLL。共有 MFC)。
    - `--gtest`: `auto` / `vcpkg` / `source` (C++。旧 NuGet 方式は廃止)。**vcpkg 方式 (既定) は、作成のあとに、`builtin-baseline` の固定と `gtest` の取得が要る** (`package_once.sh "$PWD" --timeout 1800 "vcpkg baseline" "vcpkg install"`。初回は数分)。`/new-solution` を通せば、続けて案内され、実行される。スクリプトを直接実行したときは、自分で実行する (しないと、ビルドが `requires a manifest with a specified baseline` で止まる)。
    - `--common` / `--common-dir`: 共通の MSBuild 設定 (`Directory.Build.props` / `.targets`) の置き方。`auto` (既定。外の正本の場所が決まれば参照型、なければコピー型) / `copy` / `reference`。外の正本は、別リポジトリ [`msbuild-common`](https://github.com/macsignee/msbuild-common)。場所は、環境変数 `MSBUILD_COMMON_DIR` (Windows 側。Visual Studio とウォッチャーが読む) か `--common-dir` (→ 「3-2」)。
    - `--check-git` / `--add-gitattributes`: Git の設定の点検と、最小の `.gitattributes` の追加 (→ 「2-8」)。
    - `--tfm`: .NET の TFM (既定 `net10.0`)。`--namespace`: 名前空間。
    - `--spec <仕様書>`: 仕様書の「構成案」を読み込み、仕様書も取り込む。
  - **MFC のメイン (`mfc` / `mfc-mdi` / `mfc-dialog`) の構成は、Visual Studio のウィザードに合わせる** (v2.60.0)。`framework.h`・`targetver.h`・`pch.h`・`pch.cpp` (PCH を使う)、`res\` (`<名前>.rc2`、アプリのアイコン。SDI・MDI は文書のアイコンも)、`.vcxproj` の設定 (`MFCProj`、`Midl`、`ResourceCompile`、`LinkIncremental` など)、フィルター (ソース / ヘッダー / リソース。`res\` は `Image` と `None`)。ファイル名とクラス名 (`SampleApp` など) と、ドッキングウィンドウは、ウィザードと同じにしない。**自作のクラスには、`C` 接頭辞を付けない** (`SampleApp`・`SampleDoc`・`SampleView`・`MainFrame`・`ChildFrame`・`SampleDlg`、標準 DLL の層の `<層の名前>App`。規約 `cpp-common.md` と同じ。MFC の標準クラス (`CWinApp`・`CDocument` など) は、そのまま)。Win32 の構成は、`--platforms` で選べる (層・テスト・画面ホストは、ソリューションのプラットフォームに、そろえて作られる)。**SDI・MDI は、初期状態の見た目と操作も、ウィザードに寄せた** (v2.103.0・v2.104.0。メニュー バーは、最初は隠れていて、Alt で現れる。ウィザードの実物と同じ動き。印刷・プレビュー・OLE は、寄せない)。生成する `CLAUDE.md` は、v2.105.0 から短い (Token の削減。→ [`docs/USAGE.md`](docs/USAGE.md) の 4)。
  - **画面は、画面モデルを通して作られる** (v2.92.0〜。設計の正本は [`docs/UI-MODEL-GUIDE.md`](docs/UI-MODEL-GUIDE.md)。例外は、MFC の SDI・MDI のメインの `CView` だけ)。画面モデルは、状態、入力の検査 (`Validate()` / `IsValid`)、操作の失敗の表示、変更の通知を持ち、フォームは、それを表示して、操作を渡すだけ。
    - **WPF:** `ViewModelBase` (検査の誤りを `ErrorTexts[欄名]` と `ScreenErrorTexts` にする。XAML は `{Binding ErrorTexts[Name]}`)、`MainMessages` (文章を 1 か所)。
    - **WinForms:** `Form` は引数なしのコンストラクターで、`Bind(IMainScreenModel)` で結ぶ。`IMainScreenModel` / `MainScreenModel` は、ロジック層の `ScreenModels/` (層がなければ、アプリの `ScreenModels/`)。`--tests mstest` で `MainScreenModelTests` が付く。Presenter は任意 (ダイアログを開く・フォーカスなど、WinForms の型が要るものだけ)。
    - **MFC (`mfc-dialog`、画面を持つ DLL):** `<画面名>ScreenModel` は MFC を使わない C++ (ロジック層。`std::wstring`) で、ダイアログは `ScreenModelUi.h` (`ToCString` / `ToWString`) で境界を越えて表示する。更新は `Observable`、ハンドラーは ID ごと。
    - 旧 Presenter 構成のソリューションは、移さなくてもよい。移す手順は [`docs/MIGRATION-SCREEN-MODEL.md`](docs/MIGRATION-SCREEN-MODEL.md)。
  - **WPF の MVVM の基底クラス**は、**自前の最小実装** (`ObservableObject` / `RelayCommand`。NuGet 不要) で、引数では、選べない。**推奨のライブラリは `CommunityToolkit.Mvvm`** で、替えるときは、あとから `add-package` で足して、置き換える (規約 `wpf-csharp.md` の 8)。**Prism は、使うのは自由だが、推奨しない** (商用利用の有償化と、ライブラリの更新の停滞のため)。`add-package` で入っても、`wpf-check` は、誤検出しない。
  - すでにソリューションがあるフォルダでは、テストの後付け (`--tests gtest` / `--tests mstest`) と、UI テストの後付け (`--ui-tests flaui`) だけができる。
  - スクリプト: `new_solution.py`、`gtest_once.sh <project_dir> [tag] [timeout_sec=180]` (GoogleTest のソース取得)。
- **`/new-solutions [create | sync-spec | resolve]`**: 作業フォルダ (`solutions.md` があり、`.sln` / `.slnx` がないフォルダ) の下に、同じ題材の、種類違いの複数のソリューション (WPF / WinForms / MFC など) を、候補として、まとめて作り、比べる。1 つだけ作るときは、`/new-solution`。
  - スクリプト: `new_solutions.py`。ウォッチャーを、候補ごとに起動する `host-tools/run_watchers.cmd` もある。
- **`/add-project [layer | tests | ui-host | ui-tests | platform | common] [名前 / Win32 / x64]`**: すでにあるソリューション (C++ / .NET) に、プロジェクトを足す。案を示して、**承認を得るまで、何も作らない。** ソリューションの新規作成は、`/new-solution`。
  - **`platform` (C++ だけ)**: 全部の `.vcxproj` と `.slnx` / `.sln` に、Win32 (または x64) の構成を足す (`scripts/add_platform.py`)。`.vcxproj` の形が想定と違うものが 1 つでもあれば、何も書かずに止まる。層・テスト・画面ホストは、そのソリューションのプラットフォームに、そろえて作られる。
  - **`common`**: 共通の MSBuild 設定 (`Directory.Build.props` / `.targets`) の後付け。外の正本 (`msbuild-common`) を読む薄いファイルを、すべてのプロジェクトに効かせる (`scripts/add_common.py`。質問はしない)。
  - 流れ:
    1. 現状を読む (`scripts/solution_state.py`。読み取りだけ。`CLAUDE.md` との食い違い (`MISMATCH`)、層の参照の向きの違反、`.slnx` に C++ のプラットフォームの宣言がないこと、を知らせる)。
    2. 何を足すか質問する。
    3. 案 (`--dry-run`) を示して、承認を得る。
    4. 既存のスクリプト (`add_layer.py` / `add_project.py` / `add_ui_host.py` / `new_solution.py`) で作る。.NET だけのソリューションに、C++ の層を足したときは、`.slnx` に `x64` の構成も足される (v2.98.2)。
    5. 使う側のプロジェクトに、参照を足す (`scripts/add_reference.py`。向き・循環・MFC の設定を検査して、断ることがある)。
    6. `CLAUDE.md` の「層:」「層の表」「テスト:」を合わせる。
    7. ビルド・テスト・静的検査で確かめる。
  - 足せるもの: 層 (ロジック・データ・ViewModel。C++ は DLL / 静的ライブラリ / MFC 拡張・標準 DLL) と、そのテスト。画面を持つ DLL + 画面ホスト (C++。`add_ui_host.py`。ロジック層の `Greeting` と、日本語の `.rc` のダイアログ、UI テストも足す)。テストの後付け、UI テストの後付け。
  - **混在のソリューションは、`/add-project` で作る** (正式な手順。WPF + C++ の層など)。まず、片方の言語で `/new-solution` を打ち、`/add-project` で、もう片方の層を足す (**`/add-project layer` は、名前の次に、言語を質問する。もう片方の言語を選ぶと、混在になる。** v2.105.6)。`/new-solution` は、言語が混ざる指定 (WPF に `--tests gtest` や `--layer-kind`、C++ に `--tests mstest`) を、エラーで止めて、そう案内する (v2.105.2)。例外は、C++ のメインに .NET の UI テストを足す `--ui-tests flaui` (作れる)。**C++ と C# の間の `ProjectReference` は、足さない** (`add_reference.py` が断る。`SUGGEST_REF` も出さない)。**WPF から C++ を呼ぶこと (P/Invoke など) は、禁止ではない。ひな形・自動の参照・検査が、ないだけで、P/Invoke は、自分で書く。**C++ のテスト (vcpkg) は、作成のあとに `builtin-baseline` の固定と取得が要る (Skill を通せば、案内される)。

### 2-4. 仕様から機能まで

仕様の整理と機能の追加は、別リポジトリ [`claude-spec-workflow`](https://github.com/macsignee/claude-spec-workflow) に分けた (v2.44.0)。

- **`/brainstorm`**: 壁打ちで、考えを整理して、`docs/ideas/` にメモを残す。
- **`/update-from-ideas`**: メモを整理して、仕様書 `docs/specs/` を作る・更新する。
- **`/add-feature`**: 仕様書から、計画 → 承認 → Red → Green → 検証、まで進める。
- この 3 つは、**このリポジトリの Skill (`cpp-test-first`、`csharp-test-first`、`build-test-loop` など) と scripts を、前提にする。**
- **このリポジトリに残る、仕様書とのつなぎ**: `/new-solution --spec <仕様書>` と `new_solutions.py` が、仕様書 (`docs/specs/*.md`。「## 構成案」「具体例」「境界値と異常系」) を読んで、器と、テストケースの種を作る。
  - 仕様書の形式は、このリポジトリが読む側。
  - `/new-solution` が `CLAUDE.md` に書く 3 行が、`claude-spec-workflow` の Skill の入口になる。
- 流れ: `/brainstorm` → `/update-from-ideas` → `/add-feature`。`/new-solution --spec <仕様書>` で、器を先に作ってもよい。

### 2-5. テストを先に書く (TDD)

- **TDD の範囲**: ロジック層・データ層・画面モデル (WPF は ViewModel、WinForms・MFC は ScreenModel) で、テストを先に書き、Red (失敗の理由が、アサーションであること) を確認し、実装して Green にする。テストの改変の検出 (`test_guard.py`)、テストの中身の点検 (`audit`、変異の確認) が、手順として、組み込まれている。
  - **画面 (View) は、テスト先行の対象外。** WPF の XAML・code-behind、WinForms の `Form` / `Designer.cs`、MFC の画面は、状態と規則を、画面モデルと層に置き、そちらをテストする。画面そのものは、UI テスト (FlaUI) を先に書く (`/ui-test-first`)。
  - サイクルの粒度: 1 タスク (1 つの層) ごとに、テスト 3〜8 件をまとめて書いて、Red → Green を回す。テスト 1 件ごとの往復ではない (ビルドとテストが、ウォッチャー経由で、数十秒〜数分かかるため)。
  - 整理 (リファクタリング) は、必要なときだけ、テストを変えずに行う。
  - `CLAUDE.md` の設定が `テスト: なし` のときは、テスト先行ではなく、「実装 → ビルド確認 → 手動確認」で進む (TDD ではない)。
- **`cpp-test-first`**: Windows デスクトップの C++ (MFC・Win32・DLL) で、GoogleTest のテストを先に書き、スタブで Red を確認する。Red のあと、`test_guard.py` で、テストの改変を検出する。
  - 頼み方: 「先にテストを書いて」「TDD で」など。
  - スクリプト: `add_layer.py <SLN_DIR> <Name> [--kind dll|lib|mfc-ext-dll|mfc-std-dll] [--tests none|gtest] [--tests-only] [--namespace NS] [--uses OTHER ...]` (層と、そのテストを足す)。
- **`csharp-test-first`**: WPF (MVVM) または WinForms (ScreenModel) の C# で、MSTest のテストを先に書き、Red を確認する。WPF は ViewModel、WinForms は ScreenModel (画面モデル) を直接呼んでテストする。画面モデルのテストは、View の偽物を要らず、プロパティを設定して、状態と通知を確かめる。リポジトリを持つ画面は、Fake のリポジトリを渡す (失敗の再現の書き方は `CONTRACT-TESTS.md`。ひな形には入れない)。
  - ソリューションがない (空の) フォルダでも、まず、この Skill が使われ、`/new-solution` の実行を案内して止まる。
  - 守る手順: Red のあとの確認。Green の前の `test_guard.py snapshot`、実装のあとの `check`。`wpf-check` / `winforms-check`。報告の先頭にテストファイル。
  - 層やテストが足りないときの手順は、`references/setup.md`。スクリプト: `add_project.py <SLN_DIR> <Name> [--kind lib|data|logic|viewmodel] [--tests none|mstest] [--tests-only]`。
- **`/ui-test-first [作りたい画面・動作の説明]`**: 画面を、プロンプトで作りながら、UI テスト (FlaUI) を先に書き、実行して、直す、小さなループ。WinForms / WPF / MFC。スラッシュコマンドだけで起動する。入力の誤りの文章や、操作の失敗の表示も、UI テストで確かめる (誤りの状態の再現は、Fake の画面モデル (`APP_FAKE_SCREENS`) で行う)。
  - **画面を作る流れ:**
    1. **計画を立てて、1 回だけ承認を取る。** プロンプトから、部品 (識別の名前と、守る UI ガイドラインの規則 ID)、操作と期待 (具体例 3〜7 件)、どこで確かめるか、を短い表にして示す。承認のあと、サイクルの中は、止まらずに進む。承認された設計は `docs/design/<画面>.md` に保存される (設計の正本。UI テストの名前と、「操作と期待」の番号が対応する)。すでにあれば、その表を出発点にして、変更する行だけを示す。
    2. **UI テストを先に書く (Red)。** 計画の具体例ごとに 1 テスト。操作は UIA のパターンだけ (マウス・キーボードの入力は使わない)。目視用に、アサーションのない `Preview_<画面>` も 1 つ置く。
    3. **最小の View (部品を名前つきで置くだけ) → ビルド → 絞って実行して、Red を確認する。** 規則と画面モデルは、先に、単体テストで作る (`csharp-test-first` / `cpp-test-first`)。
    4. **実装して Green にする。** 同じ `--filter` で、1 つずつ通す。失敗したら、スクリーンショットと `ui-trace.txt` を読んで直す (アサーションは弱めない)。実行は 1 サイクルで合計 5 回まで。Green のあと、その画面の全 UI テストと、静的検査 (`ui_guideline_check.py`、`*-check`) を実行する。
  - **画像 (手書きのスケッチ、ドローツールの図、既存の画面の写真) から作る流れ:** 画像を渡すと、Claude が、**先に画像を読み取り** (`references/sketch.md`)、**部品の一覧 (種類・文言・位置・確信の高低)** を見せる。読み取れなかった文字や曖昧な部品は、確信を「低」にして聞く。**画像から決まらないこと** (識別の名前、動作、画面の種類、データ、曖昧な箇所) は、**推測せずに、一覧にして確認する**。確認した内容を、上の計画の表にして、承認を得る。画像は `docs/design/images/<画面>-sketch.<拡張子>` に保存される (個人情報・社外秘が写っていないかを、保存の前に確かめる)。
    - 決まるのは**構造** (何が、どこに、どう並ぶか) だけ。色・フォント・正確な寸法は、同じにならない (標準の部品で、UI ガイドラインに沿う配置にする)。
    - 「スケッチと見比べて」と頼んだときだけ、できあがりを画像と見比べる。
  - **案を比べる (任意):** 新しい画面で、部品や配置が定まらないときは、2〜3 案を、部品の一覧と文字の配置図で示し、長所・短所を添える。1 案を選んで、計画にする。
  - **ダイアログ・サブウィンドウ:** 種類 (モーダル / モードレス)、開き方 (開くボタンも部品)、閉じ方と結果、開くときの前提を、計画に足す (`references/dialogs.md`)。
  - **データの層 (Model) が、まだ本物でないとき:** Fake (メモリ上の実装) で UI テストを回し、本物ができたら、同じ UI テストを `model=real` で通して結合する (`references/model-switching.md`)。
  - **目視 (プレビュー):** いつもは裏 (別のデスクトップ) で実行し、見たいときだけ `--preview` で、ユーザーのデスクトップに出す。実行の前に、ユーザーに伝えて、返事を待つ (`references/preview.md`)。
  - スクリプト: `uitest_once.sh` で、絞って (`--filter`)、長い制限時間 (`--ui-timeout`) で、実行する。

### 2-6. ビルドとテストの実行

ビルドとテストは、Windows 側のウォッチャーが実行する (→ 「4」)。Claude は、ウォッチャーに頼む合図 (フラグファイル) を置いて、結果のファイルを読み、失敗なら原因を読んで直して、もう一度実行する。

- **`auto-build`**: ビルドだけを実行する。ビルドエラーを読んで、ソースを直し、成功するまで繰り返す。テストは、実行しない。C++ でも、.NET でも、その混在でも、手順は同じ。
  - 頼み方: 「ビルドして」「ビルドエラーを直して」。
  - 結果: `SUCCESS` (成功)、`FAILED` (失敗。エラーの内容が付く)。
  - スクリプト: `build_once.sh <project_dir> [timeout_sec=180] [--project <名前>]`。
- **`build-test-loop`**: ビルドに続けて、テストを実行する。ビルドエラーやテストの失敗を読んで、実装を直し、全テストが通るまで繰り返す (テスト先行の流れの、Green)。GoogleTest (C++) と MSTest (.NET) で、結果の形は同じ。
  - 頼み方: 「テストまで通して」「テストが通るまで直して」。
  - 結果: `PASSED` (ビルド成功、全テスト成功。2 行目に `build: SUCCESS / tests: 6 passed` のような要約)、`FAILED` (テストの失敗。失敗したテストの一覧と詳細)、`BUILD_FAILED` (ビルドの失敗)、`TEST_TIMEOUT` (テストが制限時間内に終わらない。無限ループなどの疑い)。
  - 出力の末尾に付く行: `RESULT_INFO:` (どの実行の結果か)、`NOTE: 版の不一致` (ウォッチャーが、ホスト側が最後に変わった版より古いときだけ。警告だけで、実行は止めない。→ 「5」)、`TEST_GUARD:` (テストが改変されていないかの検査の結果。下の `test_guard.py`)。
  - スクリプト: `build_test_once.sh <solution_dir> [timeout_sec=300] [--project <名前>]`。
- 上の 2 つに共通の結果: `ENV_ERROR` (ビルドの環境などの、ソースのせいではない問題。`--project` の名前がソリューションにないとき、テストのプロジェクトがないときも、これ)、`WATCHER_NOT_RUNNING` (ウォッチャーが起動していない)、`TIMEOUT` (完了の印が、時間内に出ない)。ソースを直しても解決しないので、直さずに、止まって報告する。
- 上の 2 つに共通の止まる条件: スクリプトの実行は、通算で最大 5 回まで。同じ失敗が、修正のあとも、同じ内容で出たら、2 回目で止める。ユーザーの許可なしに、テストの削除・無効化 (`[Ignore]` など)・アサーションを弱めること・テストを通すためだけの細工 (固定の答えを返す、など) は、しない。
- **プロジェクト単位のビルド・テスト (`--project <名前>`。v2.98.0)**: ソリューション全体ではなく、**1 つの層と、そのテストだけ**を、ビルドして、実行する。層が多いソリューションで、無関係な層の失敗に、止められたくないときに使う。
  - 使い方: `build_test_once.sh "$SLN_DIR" 300 --project OrderLogic` (`build_once.sh` と `uitest_once.sh` も同じ)。Claude Code には、「`OrderLogic` だけ、ビルドとテストを回して」と頼む。**付けなければ、従来どおり、全体。** フラグの内容に `project=<名前>` の 1 行を書くだけで、ウォッチャーの再起動は要らない。
  - **テストの名前は、推測する** (設定はない): C++ は `<名前>Test`、.NET は `<名前>.Tests` (`Test` / `Tests` も可)、UI テストは `<名前>.UITests` (`UITests` / `.UiTests` / `UiTests` も可)。メインのアプリ (テストのないもの) は、ビルドだけならできる (テストまで頼むと、`ENV_ERROR`)。
  - **動き:** 本体 → テストの順に、MSBuild を 1 回ずつ、最初の失敗で止まる (本体が壊れていれば、テストはビルドしない)。実行されるのは、そのテストだけ (C++ はその exe、.NET はそのプロジェクトの `dotnet test`)。C++ の出力先は、全体のときと同じ (`$(SolutionDir)\x64\Debug\`)。単独の .NET プロジェクトは `AnyCPU` で、`bin\Debug` に出る。
  - **結果:** `RESULT_INFO:` に `scope=project=<名前>` (全体は `scope=solution`)。**古いウォッチャー (`HOST_VERSION` 2.98.0 より前) は、`project=` を読まず、全体を処理する**ので、`scope=` が違うときは、`NOTE:` で知らせる。
  - **効果:** 無関係な層の失敗に止められない、実行するテストが指定した層の分だけ、になる。**速さは、小さいソリューションでは、変わらない** (2 回の MSBuild 呼び出しの初期化が、省けた分を、打ち消す。実機の確認 2026-11-18)。使い方の詳細と、実機の確認は、`build-test-loop/references/project-scope.md`。
- **`references/fix-policy.md`**: 自動修正の方針。修正の前に、ユーザーの未コミットの変更と重なっていないかを確認する。直してよいものと止めるもの、警告の方針 (`ignore` / `report` / `fix`。既定は、報告だけ)、完了報告の項目を、決めている。`auto-build` と `build-test-loop` が、参照する。
- **`test_guard.py`**: テストの検査。
  - `snapshot <dir>` / `check <dir>`: Red を確認したテストを基準にコピーし、いまのテストと比べて、改変 (削除、`[Ignore]`、アサーションを弱める、など) を見つける。
  - `audit <dir>` (v2.57.0): 基準を使わず、テストの中身が、空洞でないかを調べる (アサーションがない、常に成功する、「null でない」だけ、期待値も実測値も呼び出しの結果、など)。形だけの検査。
  - テストが、本当に不具合を捕まえるかは、実装をわざと壊して確かめる (変異の確認。手順は `references/mutation-check.md`。必ず元に戻す)。
- **UI テスト (FlaUI) の実行**: ビルドとテストの流れには、含めない。求められたときと、`/ui-test-first` のループで、別に実行する。別のデスクトップで実行されるので、ユーザーの作業を止めず、失敗したときのスクリーンショットを、Claude が読める。
  - スクリプト: `uitest_once.sh <solution_dir> [timeout_sec=900] [--project <名前>] [--visible | --separate | --invisible] [--slowmo <ms>] [--filter <式>] [--ui-timeout <秒>] [--hold <秒>] [--preview] [--present]`。詳細は `references/ui-tests.md`。

### 2-7. 静的検査 (Windows 不要。読み取りだけ)

- **`mfc-check`**: MFC の次を検査する。
  - リソース ID の重複・未定義、メッセージマップとハンドラの不整合、ダイアログと DDX の不整合。
  - 層の依存の違反。
  - MFC の DLL (拡張 DLL・標準 DLL) の設定の食い違い。
  - 画面モデルが、ウィンドウのラッパー (`CWnd` / `CDialog` など)・`HWND`・リソース ID を使っていないこと (`SCM001`・`SCM002`)。MDI のメインの `OnCreateClient` と `IDR_MAINFRAME` のメニュー数 (`MDI001`。起動時の ASSERT を防ぐ)。
- **`wpf-check`**: WPF の次を検査する。
  - バインディングのパスの誤り、`StaticResource` のキー、`InitializeComponent()` の呼び忘れ、`StartupUri` などの誤り。
  - 層の依存の違反、規約のうち機械で判定できる項目。
- **`winforms-check`**: WinForms の次を検査する。
  - `InitializeComponent()` の呼び忘れ、`Designer.cs` の `Name`、スレッド。
  - 画面モデルが WinForms の型を使っていないこと、Form・Presenter がリポジトリを直接使っていないこと (`WFL001`〜`WFL005`)。
  - 層の依存、規約のうち機械で判定できる項目。
- 上の 3 つとも、スクリプトの引数は同じ: `<dir> [--json <out.json>] [--max-lines 40] [--all]`。
- **`ui-design-review`**: WPF / WinForms / MFC の画面を、UI デザインガイドライン (v2.10。規則 ID `UI-XXX-nnn`) に沿って、設計・レビューする。
  - ガイドライン本体は `references/`。
  - スクリプト: `ui_guideline_check.py PROJECT_DIR [--all] [--json FILE] [--fail-on-warning]` (一部の規則を静的に検査。例: パスワード欄の伏せ字 `UIG-CTL024`)。

### 2-8. Visual Studio との統合

Visual Studio (2022 / 2026) とは、次の 4 つの形でつながる。

- **ビルドとテストは、Visual Studio の MSBuild で行う。** ウォッチャーが、`build-windows.cmd` で VS の開発者環境 (`VsDevCmd`) を読み込み、`.sln` / `.slnx` (または、単独のプロジェクト) を、`MSBuild` に渡す。VS を、起動している必要はない。C++ も、SDK 形式の .NET (`/restore` を付ける) も、混在も、同じ経路。Platform は、既定の `auto` で、C++ があれば `x64`、.NET だけなら `AnyCPU` (→ 「4」)。
- **VS そのものを、WSL から操作する (`vs-debug`)。** WSL の Claude は、Windows の VS を直接は操作できないので、ウォッチャーに、`trigger_vs.flag` で依頼する。ウォッチャーは、VS の自動化の窓口 (DTE) を、**ソリューションのパスで**探す (「最初の VS」ではない)。
  - 頼み方: 「Visual Studio で開いて」「ブレークポイントを置いて」「デバッグを実行して」。
  - **開く・前面に出す:** ソリューションが開いていなければ、引数に渡して VS を起動する (読み込みの完了まで待つ)。開いていれば、そのウィンドウを前面に出す。
  - **ブレークポイント:** 追記・変更したコードの行 (git の差分。変更のかたまりごとに 1 つ、最大 10) に置く。置くのは、編集がすべて終わってから。このツールが置いたものだけを、消せる (ユーザーが手で置いたものは、消さない)。
  - **デバッグ実行:** **「デバッグを実行して」と言ったときだけ。** ブレークポイントを置く・開く、では、実行しない。実行前に、ビルドが成功していること。ブレークポイントに着くのを、最大 20 秒待ち、止まった場所 (関数・ファイル・行) を報告する。**デバッグ中は、ビルド・テスト・編集をしない** (exe が、ロックされる)。停止 (Shift+F5) は、ユーザーの操作。
  - **デバッグのログと、止まった時点の状態を、取り込む (v2.99.0):** `--output` で、VS の出力ウィンドウの「デバッグ」ペイン (`Debug.WriteLine`・`Trace`・`OutputDebugString`・MFC の `TRACE`) の最後の行を、`--inspect` で、ブレークで止まっているときの例外・呼び出し履歴・ローカル変数を、読み取る。Claude は、それを解析して、原因の候補と次の一手を報告する (頼まれなければ、ソースは直さない)。**どちらも読み取りだけで、VS を起動せず、前面にも出さない。** 全文は `vs_debug_output.txt` に残る (`.gitignore` 済み。ログには、個人情報などが含まれうる)。`Console.WriteLine` は、出力ウィンドウに出ない。頼み方: 「デバッグのログを見て」「止まっている変数を見て」。
  - **ステップ実行で、バグを探す (v2.101.0):** `--step over|into|out [歩数]` (F10・F11・Shift+F11)、`--continue` (F5)、`--pause`、`--eval "<式>"` (ウォッチ)。ブレークで止めて、**1 歩ごとの場所・ソースの行・変わった変数 (`CHANGED:`)** を、トレースとして読み、期待とのずれを探して、原因の候補を報告する (「ステップ実行して」「バグを探して」)。**ユーザーが求めたときだけ。1 回の依頼で、合計 30 歩まで。同じ場所に 3 回戻ったら、止まる。`--eval` は、読み取りだけ (代入・`++`・`--` を断る。関数の呼び出しは、了承なしに使わない)。デバッグの停止 (Shift+F5) は、ユーザーの操作** (Claude は、停止の操作を持たない)。モーダルダイアログなどで止まっても、ウォッチャーは固まらず、`STEP_TIMEOUT:` で返る。
  - **編集の競合:** VS と Claude が、同じファイルを、同時に編集すると、片方の変更が消える。**ファイルを編集する前に、`--status` で、VS の未保存の編集 (`DIRTY:`) を確かめる。** 未保存の編集があるファイルは、編集せずに、聞く。編集のあとは、VS が外部の変更を読み込む設定なら、何もしない。そうでなければ、`--reload` (未保存の編集がないものだけ、開き直す)。VS が 2 つ以上開いているときは、止まって聞く。
  - スクリプト: `vs_once.sh <solution_dir> [--status] [--changes] [--break 相対パス:行] [--clear] [--reload] [--debug] [--inspect] [--output [行数]] [--step over|into|out [歩数]] [--continue] [--pause] [--eval "<式>"]`。`HOST_VERSION` 2.90.0 以降のウォッチャーが要る (`--inspect` / `--output` は 2.99.0 以降、`--step` / `--continue` / `--pause` / `--eval` は 2.101.0 以降)。
- **VS と、同じ設定で、ビルドされる。** 生成するソリューションの `Directory.Build.props` / `.targets` は、薄い (共通の設定は、外の正本 `msbuild-common` を読む。→ 「3-2」)。VS で開いても、ウォッチャーでビルドしても、同じ設定になる。MFC のメインは、ウィザードの構成 (補助ファイル・`res\`・フィルターなど) に合わせてあり、VS のリソース ビューで、開ける (日本語の `.rc` は、UTF-8 (BOM 付き)・`#pragma code_page(65001)`)。
- **Git を、VS と WSL の両方で操作するときの決まり (`rules/git-wsl.md`)。** 改行・文字コードは、`.gitattributes` (`* text=auto eol=crlf`) が決める。WSL の `git` は、`core.autocrlf false`・`core.fileMode false` にする。**VS が Git を操作している間は、WSL の `git` を動かさない** (`index.lock`)。WSL で `git switch` / `git restore` したら、VS で「すべて再読み込み」する。`git commit` は、ユーザーが頼んだときだけ。`/new-solution --check-git` が、状態を点検する。

### 2-9. パッケージの追加

- **`add-package`**: NuGet (`dotnet add package`)、vcpkg (マニフェストモード)、GitHub のソースの取り込み (ヘッダーのみのライブラリなど) で、ライブラリを足す。ホスト側に実行させる。
  - 頼み方: 「○○を追加して」「vcpkg で xxx を使いたい」。
  - スクリプト: `package_once.sh <solution_dir> [--timeout 秒] <操作>...`。
  - 操作の例: `nuget search <term>`、`vcpkg baseline`、`vcpkg install`、`fetch <owner/repo> <tag> <name> [<subfolder>]`。

## 3. 規約・ひな形・道具 (`rules/`、`templates/`、`scripts/`)

### 3-1. 規約 (`rules/`)

技術ごとに分けた 7 つの規約がある。**`paths` に合うファイルを Claude が読むときだけ、自動で読み込まれる** (読み込みを小さくするため)。

- **配布先**: `~/.claude/rules/` (または、プロジェクトの `.claude/rules/`)。
- **名前の方針**: 言語の共通 = `<言語>-common.md`、技術ごと = `<技術>-<言語>.md`。
- **`cpp-common.md`** (18KB): C++ の共通 (MFC・Win32・コンソール・DLL・ライブラリ)。
  - 読み込まれるファイル (`paths`): `*.cpp` `*.h` `*.hpp` `*.cc` `*.cxx`。
- **`mfc-cpp.md`** (18KB): MFC 固有 (MFC のクラスのメンバー・コレクション、`CObject` 派生と名前空間、画面モデルと MFC のダイアログ (操作の受け方 = ID ごとのハンドラー、更新の経路、通知 `Observable`、Fake 画面モデルの切り替え))。
  - 読み込まれるファイル: MFC のウィザードが作るファイル名 (`*Dlg` `*View` `*Doc` `MainFrm` `*Frame`) だけ。
  - MFC のプロジェクトの `CLAUDE.md` が、読むよう指示する。MFC を使わないプロジェクトには、適用しない。
- **`csharp-common.md`** (14KB): C# の共通 (コーディング規約、非同期、依存性注入、例外、ログ、コメント、テスト、禁止事項)。
  - 読み込まれるファイル: `*.cs`。章の番号は、WPF 規約のまま。
- **`wpf-csharp.md`** (29KB): WPF / XAML / MVVM 固有。
  - 読み込まれるファイル: `*.xaml` `*.xaml.cs` `ViewModels/` `*ViewModel*.cs` `Views/`。
- **`winforms-csharp.md`** (25KB): WinForms 固有 (Form・Designer・スレッド・テストなど)。**WinForms の型を使うファイルだけ**で読み込まれる。
  - 読み込まれるファイル: `*.Designer.cs` `Forms/`。**画面モデル (`ScreenModels/`) では、読み込まれない** (画面モデルは、WinForms の型を使わない)。**任意の Presenter (`Presenters/` `*Presenter*.cs` `I*View.cs`) でも、読み込まれない** (v2.98.14。Presenter を書くときは、自分で読む)。
- **`winforms-view-model.md`** (18KB): WinForms の画面モデル (`ScreenModel`) と、任意の Presenter。画面モデルの契約、ダイアログのデータ、戻りの規則。
  - 読み込まれるファイル: `ScreenModels/` `*ScreenModel*.cs` (画面モデル)。Presenter では、読み込まれない (v2.98.14)。
- **`git-wsl.md`** (8KB): Git を、Visual Studio (Windows) と WSL の両方で操作するときの決まり (→ 「2-8」)。
  - 読み込まれるファイル: `.gitattributes`、`*.sln`、`*.slnx`。
- **読み込みの大きさの目安**:
  - WinForms の画面モデル (`ScreenModels/`) = `csharp-common.md` + `winforms-view-model.md`。
  - WinForms の Form = `csharp-common.md` + `winforms-csharp.md`。
  - WinForms の Presenter (任意) = `csharp-common.md` だけ。WinForms の型を使うものを書くときは、`winforms-csharp.md` と `winforms-view-model.md` を、自分で読む。
  - WPF の ViewModel = `csharp-common.md` + `wpf-csharp.md`。
  - 画面と無関係の `.cs` = `csharp-common.md` だけ。
- **優先**: プロジェクトの `CLAUDE.md` に、固有の決まりがあれば、そちらが、優先される。書式の詳細は、プロジェクトの `.editorconfig` (C++ は `.clang-format`) が正。
- **配布**: `install/install.sh --rules-only`。

### 3-2. ひな形 (`templates/`)

規約が参照する、設定ファイルのひな形。

- **配布先**: `~/.claude/templates/` (または、プロジェクトの `.claude/templates/`)。
- **`templates/dotnet/.editorconfig`、`templates/dotnet/Directory.Build.props`**: C# / WPF 用。規約 (`csharp-common.md`) が参照する。
  - `/new-solution` が生成するものと、同じ内容。
  - **共通の MSBuild 設定は、別リポジトリ [`msbuild-common`](https://github.com/macsignee/msbuild-common) が正本。** 生成するソリューションの `Directory.Build.props` / `.targets` は、薄いファイルで、正本の `Common.props` などを読む (参照型。場所は、環境変数 `MSBUILD_COMMON_DIR`)。環境変数がないと、ビルドが `__MSBUILD_COMMON_DIR_NOT_SET__\Common.props` が見つからない、で止まる。場所が決まらないときは、同じ内容を、`build\common\` にコピーする (コピー型)。後付けは `/add-project common`。
- **`templates/cpp/.clang-format`、`.clang-tidy`、`.editorconfig`**: C++ 用。`cpp-common.md` が参照する。
  - 内容: Allman、インデント 4、`#include` の順序は変えない、関数は 100 行まで (`readability-function-size`)、`.cpp` / `.h` / `.hpp` は CRLF。
  - `/new-solution` (C++) は、生成しない。
- **手で直した既存のファイル**: 配布のとき、上書きせず、番号付きのバックアップ (`*.~N~`) を残す。
  - バックアップは、読み込まれない。消してよい。

### 3-3. 道具 (`scripts/`)

- 配布先は `~/.claude/scripts/` (または、プロジェクトの `.claude/scripts/`)。規約 (`cpp-common.md`、`csharp-common.md`) が参照する。
- **`convert_to_utf8_bom.py`**: Shift-JIS (CP932) のソースを、UTF-8 (BOM 付き) / CRLF に変換する。
  - 使い方: `python3 -I ~/.claude/scripts/convert_to_utf8_bom.py [--apply] <ファイル>...`。既定は、検証だけ (書かない)。`--apply` で書き換える。
  - **手動で、ファイルを指定して、1 回だけ実行する** (規約の「変換だけの、別のコミット」)。ビルドの流れには、組み込まれていない。
  - 往復の確認 (CP932 に戻して一致) をして、確認できないファイルは、書かない。BOM 付きの UTF-8 は、スキップする。
  - **BOM なしの UTF-8 (非 ASCII を含む) は、Shift-JIS ではないので、NG にして、書かない。** 存在しないファイルは、NG にして、続ける。

## 4. ホスト側ツール (`host-tools/`)

Windows 側に置くツール。ビルド・テスト・UI テストの実行は、ここのウォッチャーが行う (→ 「2-6」)。**`run_watcher.cmd`、`watch_and_build.ps1`、`build-windows.cmd` の 3 ファイルと、`lib\` フォルダ (`watch_and_build.ps1` が読み込む 10 ファイル) は、同じフォルダに置く。** `install.sh` は、`lib\` も配る。

- **`run_watcher.cmd`**: 入口。プロジェクトのフォルダを指定して、ウォッチャーを起動する。
  - ダブルクリックでも、ドラッグ&ドロップでも、起動できる。
- **`watch_and_build.ps1`**: ウォッチャー本体 (フラグの監視ループ)。
  - 機能ごとの関数 (ビルド・テストの実行、プロジェクト単位の範囲の解決、GoogleTest の取得、パッケージ操作、UI テストの基盤、Visual Studio の操作、Git のリモートの操作) は、`lib\*.ps1` に分かれている。
  - 見るフラグ: `trigger_build.flag` / `trigger_test.flag` / `trigger_uitest.flag` / `trigger_gtest.flag` / `trigger_package.flag` / `trigger_vs.flag` / `trigger_git.flag`。ビルド・テスト・UI テストのフラグに、`project=<名前>` の行があれば、プロジェクト単位で処理する (→ 「2-6」)。
- **`build-windows.cmd`**: Visual Studio の環境を読み込んで、MSBuild を実行する。ソリューションでも、単独のプロジェクトでも、渡せる (.NET の単独のプロジェクトは `AnyCPU`)。
- **`run_watcher_visible.cmd [ProjectDir] [Solution] [Platform] [Configuration]`** (任意): UI テストを、**ユーザー自身のデスクトップで、目で見ながら**実行する設定で、ウォッチャーを起動する。引数は `run_watcher.cmd` と同じ。
  - 操作の間に、遅延を入れる (環境変数 `WATCH_UI_SLOWMO_MS`。既定 800 ms)。
  - 実行中は、PC を使いにくい。
- **`run_watchers.cmd [WorkFolder] [/list] [/windows]`** (任意。`/new-solutions` 用): 作業フォルダの直下の、候補 (`.sln` / `.slnx` のあるサブフォルダ) ごとに、ウォッチャーを起動する。
  - 既定は、Windows ターミナル (`wt.exe`) の 1 つのウィンドウに、候補ごとのタブ。`/windows` は、候補ごとのコンソール窓。`/list` は、候補の一覧。
  - タブ / 窓を閉じると、そのウォッチャーだけが止まる。
- **1 つのウォッチャーの範囲**: 1 つのプロジェクトと、1 つの Platform / Configuration 専用。Platform の既定は `auto` (C++ があれば `x64`、.NET だけなら `AnyCPU`)。
- **版**: 起動バナーと結果の `run_id.txt` に出る。ホスト側を変えたら、`HOST_VERSION` を上げる (→ 「5-3」)。`--project` は 2.98.0 以降、Visual Studio の操作は 2.90.0 以降が要る。
- **詳しい説明**: 起動の仕方、引数、取り決め (フラグファイルと結果ファイル)、トラブルシューティングは、[`host-tools/README.md`](host-tools/README.md)。

## 5. 配布 (インストール)

### 5-1. ホームへ配る (既定)

WSL のターミナルで、リポジトリのルートから実行する。

```bash
install/install.sh --dry-run        # 何をコピーするかだけ表示する
install/install.sh                  # すべて配る
```

- 配るもの (オプションなしは、すべて):
  - Skill → `~/.claude/skills` (`--skills-only`)。プロジェクトへ配るときは、`--skills-dir` (→ 「5-2」)。
  - ホスト側ツール → `/mnt/c/tools/claude-watcher` (`--host-only`)。
  - 規約・ひな形・道具 → `~/.claude/rules`、`~/.claude/templates`、`~/.claude/scripts` (`--rules-only`)。
  - **Skill だけを配っても、規約は、配られない。** 規約を変えたときは、`--rules-only` も、実行する。
- 配布先を変えるオプション: `--skills-dir DIR`、`--host-dir DIR`、`--rules-dir DIR`、`--templates-dir DIR`、`--scripts-dir DIR`。
- コピー前に、`tools/check-formats.sh` で形式を検証し、違反があれば中止する。コピー後に、`cmp` で同一性を確認する。
- 配布先は、**コピー先であって、編集する場所ではない。** 直すときは、このリポジトリを直して、配り直す。
- Skill を読み込ませるには、Claude Code のセッションを、新しく起動する。ホスト側を再配置したら、ウォッチャーを再起動する (起動時に読み込むため)。

### 5-2. プロジェクトのリポジトリへ配る (チームで共有する)

`--skills-dir` などで、配布先を、プロジェクトの `.claude/` にする。**チームのメンバーが、`git clone` するだけで、Skill と規約が使える。**

```bash
# Skill (プロジェクトの .claude/skills)
install/install.sh --skills-only --skills-dir <プロジェクト>/.claude/skills

# 規約・ひな形・道具 (プロジェクトの .claude/rules・templates・scripts)
install/install.sh --rules-only --rules-dir <プロジェクト>/.claude/rules \
  --templates-dir <プロジェクト>/.claude/templates --scripts-dir <プロジェクト>/.claude/scripts
```

- 配ったあと、プロジェクトの git で、コミットする。**更新するときは、このリポジトリを直して、配り直し、差分をコミットする** (プロジェクトの中の `.claude/` を、直接編集しない)。
- **ホスト側ツール (`host-tools/`) は、リポジトリに入れない。** Windows 側の 1 か所 (既定: `C:\tools\claude-watcher\`) に置き、全プロジェクトで、共有する (→ 「4」)。
- `claude-spec-workflow` の Skill も、同じ `<プロジェクト>/.claude/skills` に配ると、`/add-feature` などが、同じフォルダの `new-solution` や `build-test-loop` を、見つけられる (`<Skill群>` が同じになるため)。
- **ホームと、プロジェクトの両方に、同じ名前の Skill があると、ホーム (`~/.claude/skills`) のほうが使われる** (実機の確認、2026-11-07。`Base directory` も、実行されるスクリプトも、ホーム側だった)。プロジェクトに配った Skill を、チームで使うときは、**メンバーのホームに、同じ名前の古い Skill があると、そちらが優先される**ので、注意する。混乱を避けるため、どちらか一方にそろえる。プロジェクトにしかない Skill は、プロジェクトの `.claude/skills` のものが、使われる (`new-solution` から `csharp-test-first` / `build-test-loop` を呼ぶ通しも、動く)。
- Claude Code のサンドボックスは、`.claude/skills` などへの書き込みを、禁止していることがある。**配布は、ユーザーが、ターミナルで行う。**
- プロジェクトごとに、コピーが、独立する。**版が、プロジェクトごとに、ずれうる** (各 Skill のフォルダの `VERSION` で分かる)。

### 5-3. 版 (`VERSION`) と、警告 (`NOTE`)

- 配布先に、このリポジトリの版 (`VERSION`) と、**ホスト側が最後に変わった版 (`host-tools/HOST_VERSION`)** を置く (各 Skill のフォルダ。ホスト側のフォルダには `VERSION`)。
- ウォッチャーは、起動バナーに版を出し、結果の `run_id.txt` に書く。
- Skill 側 (`*_once.sh`) が照合し、**ウォッチャーの版が `HOST_VERSION` より古いときだけ、出力の末尾に `NOTE:` を出す** (警告だけ。実行は止めない)。Skill だけを配ったときは、出ない。
- `--project` を付けたのに、結果の `scope=` が `project=<名前>` でないときも、`NOTE:` (古いウォッチャーが、全体を処理した、という意味)。
- **`host-tools/` の中身を変えたら、`host-tools/HOST_VERSION` を、その版に上げる。**

## 6. テスト (`tests/`)

- 全テスト: `for t in tests/*_test.sh; do bash $t; done` (2 分を超えることがある)。Windows は不要 (疑似ウォッチャー、疑似フォルダ、文字列の確認)。一覧は、`ls tests/*_test.sh`。
- 分類 (主なもの):

| 分類 | テスト |
|---|---|
| ウォッチャーと結果の変換 | `fake_watcher`、`host_tools_static`、`harness_note` (`RESULT_INFO` と `NOTE`)、`loop_hardening` (止めどき)、`summarize_build_log`、`summarize_test_log`、`gtest_once`、`uitest_once`、`project_scope` (`--project`) |
| ソリューションの生成 | `new_solution` (C++)、`mfc_class_names` (MFC の自作クラスに `C` 接頭辞を付けない)、`new_solution_wpf`、`new_solution_winforms`、`new_solution_csharp_dll`、`new_solution_spec_import`、`new_solutions`、`ui_tests_gen` |
| 層・プロジェクトの追加 | `add_layer`、`add_project`、`add_project_skill` (`/add-project` と `solution_state.py`)、`add_reference`、`add_ui_host`、`add_common`、`win32_platform` |
| テスト先行と、テストの検査 | `test_guard` (`snapshot` / `check` / `audit`)、`ui_test_first_skill`、`fix_policy` |
| 静的検査 | `mfc_check`、`mfc_lib`、`mfc_cobject_rules`、`mfc_screen_model`、`mfc_wizard_layout`、`mfc_sdi_wizard_look`・`mfc_mdi_wizard_look` (SDI・MDI の初期状態)、`mfc_app_commands`、`wpf_check`、`winforms_check`、`wpf_menu_note`、`ui_guideline_check` |
| パッケージ | `package_once`、`cpp_pkg` |
| Visual Studio・Git・MSBuild の共通設定 | `vs_once` (`vs-debug`)、`git_once` (`git-remote`)、`git_wsl_rule`、`msbuild_common`、`new_solution_common` |
| 規約・道具・文書 | `rules_split`、`convert_utf8_bom`、`fix_cpp_encoding`、`skill_paths`、`usage_guide` (`docs/USAGE.md` と Skill の一覧のずれ)、`claude_md_size` (生成する `CLAUDE.md` の長さ。v2.105.0)、`token_report` (`tools/token_report.py`) |

(各ファイルの名前は、`<名前>_test.sh`。)

- **`install.sh` を実際に実行するテストは、`--scripts-dir` などの配布先を、一時フォルダにする** (渡さないと、ホームの `~/.claude` を、上書きする。`rules_split_test.sh` が検査する)。

## 7. 文書 (`docs/`)

- [`USAGE.md`](docs/USAGE.md): 利用ガイド (どのコマンドを打つかの判断フロー、承認と差し戻しの言い方、困ったとき)。
- [`DESIGN.md`](docs/DESIGN.md): 設計メモ (契約、設計判断、取り下げた案)。
- [`TEST-PLAN.md`](docs/TEST-PLAN.md): テスト手順書 (実機の確認の手順と結果。「変更したときの、最低限の確認」を含む)。
- [`REMAINING-CHECKS.md`](docs/REMAINING-CHECKS.md): 実機の確認の状況 (確認済み、未了、廃止、保留) の正本。
- [`UI-MODEL-GUIDE.md`](docs/UI-MODEL-GUIDE.md): UI と画面モデルの開発の手引き (WPF・WinForms・MFC 共通の考え方。契約、Fake、検査、MFC の通知)。設計の正本。
- [`MIGRATION-SCREEN-MODEL.md`](docs/MIGRATION-SCREEN-MODEL.md): 旧 Presenter 構成のソリューションを、画面モデルへ移す手順 (移さなくてもよい)。
- [`NEXT-STEPS.md`](docs/NEXT-STEPS.md): 次の作業 (現状と残り。2026-11-25 時点 (v2.105.1) で、実機の確認はすべて終わり、判断待ちのものだけ)。
- [`HANDOFF-2026-11-24-remaining.md`](docs/HANDOFF-2026-11-24-remaining.md): 引き継ぎ (最新。残作業の一覧、前提、決定済みのこと)。新しいセッションで、最初に読む。
- [`HANDOFF-2026-11-24-evening.md`](docs/HANDOFF-2026-11-24-evening.md): 2026-11-24 夜の引き継ぎ (Token 削減の測定と結論、マージしたもの、技術メモ)。
- [`HANDOFF-2026-11-24.md`](docs/HANDOFF-2026-11-24.md): 2026-11-23〜24 の引き継ぎ (作業、決定事項、サンドボックスの落とし穴)。
- [`HANDOFF-2026-11-18.md`](docs/HANDOFF-2026-11-18.md): 旧版の引き継ぎ (作業の約束事、画面モデルの採用までの経緯)。第 1 節の約束事は、今も有効。
- [`RECOMMENDED-SETTINGS.md`](docs/RECOMMENDED-SETTINGS.md): 推奨する Claude Code の設定 (テストファイルの編集と、`git commit` に、確認を付ける)。

## 8. ファイル形式 (重要)

文字コードと改行が崩れると、動かなくなる。`.gitattributes` で、git の自動変換を無効にしている。

| ファイル | 文字コード | 改行 |
|---|---|---|
| `*.cmd` | **CP932 (Shift_JIS)**、BOM なし | CRLF |
| `*.ps1` | UTF-8、**BOM あり** | CRLF |
| `*.sh` / `*.md` | UTF-8、BOM なし | **LF** |

- `.cmd` を、UTF-8 のエディタで開いて保存し直さない。編集するときは、CP932 を扱えるエディタを使う。
- 変更したら、必ず `tools/check-formats.sh` を実行する。
- `.cmd` の差分を読めるようにする (クローンごとに、1 回):
  ```bash
  git config diff.cp932.textconv "iconv -f cp932 -t utf-8"
  ```

## 9. 開発の進め方

- **このリポジトリが原本。** 作業コピーは、1 つの OS の git だけで扱う (WSL 側に置く)。同じフォルダを、Windows の git と WSL の git の両方で操作しない。
- 契約 (ファイル名・結果の値・終了コード) を変えるときは、ホスト側ツールと Skill を、**同じコミット**で直す。[`docs/DESIGN.md`](docs/DESIGN.md) の「契約」も更新する。
- 変更したときの、最低限の確認は、[`docs/TEST-PLAN.md`](docs/TEST-PLAN.md) の「変更したときの、最低限の確認」。
- 変更したら、`VERSION` と `CHANGELOG.md` を更新する。`host-tools/` を変えたときは、`host-tools/HOST_VERSION` も上げる。

## 10. 対応範囲

- テスト: C++ は **GoogleTest**、.NET は **MSTest (v3 以降、VSTest モード)**。xUnit / NUnit は動く見込みだが未検証。C++ の `CppUnitTestFramework` は対象外 ([理由](docs/DESIGN.md))。
- 対象外: ASP.NET Core などの Web、MAUI、Linux / macOS 向けの .NET、組み込みの C++ (Windows デスクトップの Visual Studio / MSBuild が対象)。
- 検証済み: VS 2026 Enterprise、x64 / Debug (C++ は、Win32 も。`vs-debug` の `--inspect` は、C++ の Release x64 でも)。WPF + C++ の混在、MFC (SDI・MDI)、UI テスト (FlaUI) を含む。
- 実機の確認の状況 (確認済み・未了) は、[`docs/REMAINING-CHECKS.md`](docs/REMAINING-CHECKS.md) と、[`docs/TEST-PLAN.md`](docs/TEST-PLAN.md) の「状況」列。Skill 側のスクリプトと結果の変換は、疑似ウォッチャーでも検証している。

## 11. ライセンス

[MIT License](LICENSE.md)。共通の MSBuild 設定 (`Directory.Build.props` / `.targets`) は、別のリポジトリ [`macsignee/msbuild-common`](https://github.com/macsignee/msbuild-common) (同じく MIT) で管理している。
