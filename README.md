# claude-windows-desktop-tools

Claude Code (WSL) が、Windows 側の Visual Studio で、**C++ (GoogleTest) と .NET (WPF / WinForms / C# クラスライブラリ。MSTest) の、ビルドとテストを実行し、エラーや失敗を自分で直す**ためのツール一式。

- **使い方 (どのコマンドを打つか、承認の言い方、困ったとき) は、[`docs/USAGE.md`](docs/USAGE.md)。まず、これを読む。**
- C++ のみ、.NET のみ、混在のソリューションのどれでも、同じ Skill と同じウォッチャーで使う (ソリューションの中身から、自動で判定する。[設計メモ 4.24](docs/DESIGN.md))。
- **テスト先行 (TDD) の流れを支える。** ロジック層・ViewModel / Presenter では、テストを先に書いて Red を確認し、実装して Green にする。画面は、UI テストを先に書く (`/ui-test-first`)。1 タスクごとに、テストを数件まとめて回す (1 件ずつではない。→ 「2-5」)。
- 仕様の整理 (`/brainstorm` → `/update-from-ideas`) と機能の追加 (`/add-feature`) は、別リポジトリ [`claude-spec-workflow`](https://github.com/macsignee/claude-spec-workflow) (→ 「2-4」)。

Claude Code のサンドボックスからは、Windows 側の MSBuild やテスト exe を、直接実行できない。そこで、Windows 側にウォッチャーを常駐させ、Claude は、フラグファイルを置いて、結果ファイルを読むだけにしている。

```
Claude Code (WSL)  ──trigger_*.flag──▶  Windows: watch_and_build.ps1 ─▶ MSBuild / テスト exe
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
| [`skills/`](skills/) | Claude Code の Skill (13 個。→ 「2」) | `~/.claude/skills/` (WSL)、またはプロジェクトの `.claude/skills/` |
| [`rules/`](rules/) | ユーザー共通のコーディング規約 (5 つ。→ 「3」) | `~/.claude/rules/` (WSL)、またはプロジェクトの `.claude/rules/` |
| [`templates/`](templates/) | 規約が参照する、設定ファイルのひな形 (→ 「3」) | `~/.claude/templates/` (WSL)、またはプロジェクトの `.claude/templates/` |
| [`scripts/`](scripts/) | 規約が参照する道具 (→ 「3」) | `~/.claude/scripts/` (WSL)、またはプロジェクトの `.claude/scripts/` |
| [`host-tools/`](host-tools/) | Windows 側のウォッチャーと、起動・ビルド用の `.cmd` (→ 「4」) | Windows 側の任意のフォルダ (既定: `C:\tools\claude-watcher\`) |
| [`install/`](install/) | `install.sh` (配布先へ、バイトを変えずに、コピーする。→ 「5」) | — |
| [`tools/`](tools/) | `check-formats.sh` (文字コード・改行・BOM の検証) | — |
| [`tests/`](tests/) | 単体テスト (`*_test.sh`)。Windows は不要 (→ 「6」) | — |
| [`docs/`](docs/) | 設計と手順の文書 (→ 「7」) | — |

- `CHANGELOG.md`: 変更履歴。
- `VERSION`: 版。配布先にも置かれる (→ 「5」)。
- **配布先は、ホームでも、プロジェクトのリポジトリでもよい** (→ 「5-2」)。文書の `.claude/...` は、ホームの `~/.claude/...` と、プロジェクトの `.claude/...` の、どちらも指す。

## 2. Skill (`skills/`)

### 2-1. 早見

Skill は 13 個ある。**スラッシュで打って起動するもの**と、**依頼文に合わせて Claude が選ぶもの**がある (→ 「2-2」)。

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
- **`vs-debug`** (依頼文): Visual Studio で、ソリューションを開く・前面に出す・ブレークポイントを置く・デバッグ実行する。

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
    - `--layer-kind`: C++ の層の種類。`dll` / `lib` / `mfc-ext-dll` (MFC 拡張 DLL。メインが MFC のときだけ) / `mfc-std-dll` (MFC 標準 DLL。共有 MFC)。
    - `--gtest`: `auto` / `vcpkg` / `source` (C++。旧 NuGet 方式は廃止)。
    - `--tfm`: .NET の TFM (既定 `net10.0`)。`--namespace`: 名前空間。
    - `--spec <仕様書>`: 仕様書の「構成案」を読み込み、仕様書も取り込む。
  - **MFC のメイン (`mfc` / `mfc-mdi` / `mfc-dialog`) の構成は、Visual Studio のウィザードに合わせる** (v2.60.0)。`framework.h`・`targetver.h`・`pch.h`・`pch.cpp` (PCH を使う)、`res\` (`<名前>.rc2`、アプリのアイコン。SDI・MDI は文書のアイコンも)、`.vcxproj` の設定 (`MFCProj`、`Midl`、`ResourceCompile`、`LinkIncremental` など)、フィルター (ソース / ヘッダー / リソース。`res\` は `Image` と `None`)。ファイル名とクラス名 (`SampleApp` など) と、ドッキングウィンドウは、ウィザードと同じにしない。層・テストの `.vcxproj` と、Win32 の構成は、未対応 (x64 だけ)。
  - **WPF の MVVM の基底クラス**は、**自前の最小実装** (`ObservableObject` / `RelayCommand`。NuGet 不要) で、引数では、選べない。**推奨のライブラリは `CommunityToolkit.Mvvm`** で、替えるときは、あとから `add-package` で足して、置き換える (規約 `wpf-csharp.md` の 8)。**Prism は、使うのは自由だが、推奨しない** (商用利用の有償化と、ライブラリの更新の停滞のため)。`add-package` で入っても、`wpf-check` は、誤検出しない。
  - すでにソリューションがあるフォルダでは、テストの後付け (`--tests gtest` / `--tests mstest`) と、UI テストの後付け (`--ui-tests flaui`) だけができる。
  - スクリプト: `new_solution.py`、`gtest_once.sh <project_dir> [tag] [timeout_sec=180]` (GoogleTest のソース取得)。
- **`/new-solutions [create | sync-spec | resolve]`**: 作業フォルダ (`solutions.md` があり、`.sln` / `.slnx` がないフォルダ) の下に、同じ題材の、種類違いの複数のソリューション (WPF / WinForms / MFC など) を、候補として、まとめて作り、比べる。1 つだけ作るときは、`/new-solution`。
  - スクリプト: `new_solutions.py`。ウォッチャーを、候補ごとに起動する `host-tools/run_watchers.cmd` もある。
- **`/add-project [layer | tests | ui-host | ui-tests | platform] [名前 / Win32 / x64]`**: すでにあるソリューション (C++ / .NET) に、プロジェクトを足す。案を示して、**承認を得るまで、何も作らない。** ソリューションの新規作成は、`/new-solution`。
  - **`platform` (C++ だけ)**: 全部の `.vcxproj` と `.slnx` / `.sln` に、Win32 (または x64) の構成を足す (`scripts/add_platform.py`)。`.vcxproj` の形が想定と違うものが 1 つでもあれば、何も書かずに止まる。層・テスト・画面ホストは、そのソリューションのプラットフォームに、そろえて作られる。
  - 流れ:
    1. 現状を読む (`scripts/solution_state.py`。読み取りだけ)。
    2. 何を足すか質問する。
    3. 案 (`--dry-run`) を示して、承認を得る。
    4. 既存のスクリプト (`add_layer.py` / `add_project.py` / `add_ui_host.py` / `new_solution.py`) で作る。
    5. 使う側のプロジェクトに、参照を足す (`scripts/add_reference.py`。向き・循環・MFC の設定を検査して、断ることがある)。
    6. `CLAUDE.md` の「層:」「層の表」「テスト:」を合わせる。
    7. ビルド・テスト・静的検査で確かめる。
  - 足せるもの: 層 (ロジック・データ・ViewModel。C++ は DLL / 静的ライブラリ / MFC 拡張・標準 DLL) と、そのテスト。画面を持つ DLL + 画面ホスト (C++。`add_ui_host.py`。ロジック層の `Greeting`、UI テストも足す)。テストの後付け、UI テストの後付け。

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

- **TDD の範囲**: ロジック層・データ層・ViewModel / Presenter で、テストを先に書き、Red (失敗の理由が、アサーションであること) を確認し、実装して Green にする。テストの改変の検出 (`test_guard.py`)、テストの中身の点検 (`audit`、変異の確認) が、手順として、組み込まれている。
  - **画面 (View) は、テスト先行の対象外。** WPF の XAML・code-behind、WinForms の `Form` / `Designer.cs`、MFC の画面は、ViewModel / Presenter / 層に切り出してテストする。画面そのものは、UI テスト (FlaUI) を先に書く (`/ui-test-first`)。
  - サイクルの粒度: 1 タスク (1 つの層) ごとに、テスト 3〜8 件をまとめて書いて、Red → Green を回す。テスト 1 件ごとの往復ではない (ビルドとテストが、ウォッチャー経由で、数十秒〜数分かかるため)。
  - 整理 (リファクタリング) は、必要なときだけ、テストを変えずに行う。
  - `CLAUDE.md` の設定が `テスト: なし` のときは、テスト先行ではなく、「実装 → ビルド確認 → 手動確認」で進む (TDD ではない)。
- **`cpp-test-first`**: Windows デスクトップの C++ (MFC・Win32・DLL) で、GoogleTest のテストを先に書き、スタブで Red を確認する。Red のあと、`test_guard.py` で、テストの改変を検出する。
  - 頼み方: 「先にテストを書いて」「TDD で」など。
  - スクリプト: `add_layer.py <SLN_DIR> <Name> [--kind dll|lib|mfc-ext-dll|mfc-std-dll] [--tests none|gtest] [--tests-only] [--namespace NS] [--uses OTHER ...]` (層と、そのテストを足す)。
- **`csharp-test-first`**: WPF (MVVM) または WinForms (MVP) の C# で、MSTest のテストを先に書き、Red を確認する。WPF は ViewModel、WinForms は Presenter と `IView` の Fake でテストする。
  - ソリューションがない (空の) フォルダでも、まず、この Skill が使われ、`/new-solution` の実行を案内して止まる。
  - 守る手順: Red のあとの確認。Green の前の `test_guard.py snapshot`、実装のあとの `check`。`wpf-check` / `winforms-check`。報告の先頭にテストファイル。
  - 層やテストが足りないときの手順は、`references/setup.md`。スクリプト: `add_project.py <SLN_DIR> <Name> [--kind lib|data|logic|viewmodel] [--tests none|mstest] [--tests-only]`。
- **`/ui-test-first [作りたい画面・動作の説明]`**: 画面を、プロンプトで作りながら、UI テスト (FlaUI) を先に書き、実行して、直す、小さなループ。WinForms / WPF / MFC。スラッシュコマンドだけで起動する。
  - スクリプト: `uitest_once.sh` で、絞って (`--filter`)、長い制限時間 (`--ui-timeout`) で、実行する。

### 2-6. ビルドとテストの実行

ビルドとテストは、Windows 側のウォッチャーが実行する (→ 「4」)。Claude は、ウォッチャーに頼む合図 (フラグファイル) を置いて、結果のファイルを読み、失敗なら原因を読んで直して、もう一度実行する。

- **`auto-build`**: ビルドだけを実行する。ビルドエラーを読んで、ソースを直し、成功するまで繰り返す。テストは、実行しない。C++ でも、.NET でも、その混在でも、手順は同じ。
  - 頼み方: 「ビルドして」「ビルドエラーを直して」。
  - 結果: `SUCCESS` (成功)、`FAILED` (失敗。エラーの内容が付く)。
  - スクリプト: `build_once.sh <project_dir> [timeout_sec=180]`。
- **`build-test-loop`**: ビルドに続けて、テストを実行する。ビルドエラーやテストの失敗を読んで、実装を直し、全テストが通るまで繰り返す (テスト先行の流れの、Green)。GoogleTest (C++) と MSTest (.NET) で、結果の形は同じ。
  - 頼み方: 「テストまで通して」「テストが通るまで直して」。
  - 結果: `PASSED` (ビルド成功、全テスト成功。2 行目に `build: SUCCESS / tests: 6 passed` のような要約)、`FAILED` (テストの失敗。失敗したテストの一覧と詳細)、`BUILD_FAILED` (ビルドの失敗)、`TEST_TIMEOUT` (テストが制限時間内に終わらない。無限ループなどの疑い)。
  - 出力の末尾に付く行: `RESULT_INFO:` (どの実行の結果か)、`NOTE: 版の不一致` (ウォッチャーが、ホスト側が最後に変わった版より古いときだけ。警告だけで、実行は止めない。→ 「5」)、`TEST_GUARD:` (テストが改変されていないかの検査の結果。下の `test_guard.py`)。
  - スクリプト: `build_test_once.sh <solution_dir> [timeout_sec=300]`。
- 上の 2 つに共通の結果: `ENV_ERROR` (ビルドの環境などの、ソースのせいではない問題)、`WATCHER_NOT_RUNNING` (ウォッチャーが起動していない)、`TIMEOUT` (完了の印が、時間内に出ない)。ソースを直しても解決しないので、直さずに、止まって報告する。
- 上の 2 つに共通の止まる条件: スクリプトの実行は、通算で最大 5 回まで。同じ失敗が、修正のあとも、同じ内容で出たら、2 回目で止める。ユーザーの許可なしに、テストの削除・無効化 (`[Ignore]` など)・アサーションを弱めること・テストを通すためだけの細工 (固定の答えを返す、など) は、しない。
- **`references/fix-policy.md`**: 自動修正の方針。修正の前に、ユーザーの未コミットの変更と重なっていないかを確認する。直してよいものと止めるもの、警告の方針 (`ignore` / `report` / `fix`。既定は、報告だけ)、完了報告の項目を、決めている。`auto-build` と `build-test-loop` が、参照する。
- **`test_guard.py`**: テストの検査。
  - `snapshot <dir>` / `check <dir>`: Red を確認したテストを基準にコピーし、いまのテストと比べて、改変 (削除、`[Ignore]`、アサーションを弱める、など) を見つける。
  - `audit <dir>` (v2.57.0): 基準を使わず、テストの中身が、空洞でないかを調べる (アサーションがない、常に成功する、「null でない」だけ、期待値も実測値も呼び出しの結果、など)。形だけの検査。
  - テストが、本当に不具合を捕まえるかは、実装をわざと壊して確かめる (変異の確認。手順は `references/mutation-check.md`。必ず元に戻す)。
- **UI テスト (FlaUI) の実行**: ビルドとテストの流れには、含めない。求められたときと、`/ui-test-first` のループで、別に実行する。別のデスクトップで実行されるので、ユーザーの作業を止めず、失敗したときのスクリーンショットを、Claude が読める。
  - スクリプト: `uitest_once.sh <solution_dir> [timeout_sec=900] [--visible | --separate | --invisible] [--slowmo <ms>] [--filter <式>] [--ui-timeout <秒>] [--hold <秒>] [--preview] [--present]`。詳細は `references/ui-tests.md`。

### 2-7. 静的検査 (Windows 不要。読み取りだけ)

- **`mfc-check`**: MFC の次を検査する。
  - リソース ID の重複・未定義、メッセージマップとハンドラの不整合、ダイアログと DDX の不整合。
  - 層の依存の違反。
  - MFC の DLL (拡張 DLL・標準 DLL) の設定の食い違い。
- **`wpf-check`**: WPF の次を検査する。
  - バインディングのパスの誤り、`StaticResource` のキー、`InitializeComponent()` の呼び忘れ、`StartupUri` などの誤り。
  - 層の依存の違反、規約のうち機械で判定できる項目。
- **`winforms-check`**: WinForms の次を検査する。
  - `InitializeComponent()` の呼び忘れ、`Designer.cs` の `Name`、スレッド。
  - 層の依存、規約のうち機械で判定できる項目。
- 上の 3 つとも、スクリプトの引数は同じ: `<dir> [--json <out.json>] [--max-lines 40] [--all]`。
- **`ui-design-review`**: WPF / WinForms / MFC の画面を、UI デザインガイドライン (v2.10。規則 ID `UI-XXX-nnn`) に沿って、設計・レビューする。
  - ガイドライン本体は `references/`。
  - スクリプト: `ui_guideline_check.py PROJECT_DIR [--all] [--json FILE] [--fail-on-warning]` (一部の規則を静的に検査)。

### 2-8-1. Visual Studio の操作 (開く・ブレークポイント・デバッグ実行)

- **`vs-debug`**: WSL の Claude が、Windows の Visual Studio を操作する。ソリューションが開いていなければ、引数に渡して起動 / 開いていれば、前面に出す。追記・変更したコードの行 (git の差分) に、ブレークポイントを置く。**「デバッグを実行して」と言ったときだけ**、デバッグ実行を始める。
  - 頼み方: 「Visual Studio で開いて」「ブレークポイントを置いて」「デバッグを実行して」。
  - **編集の競合:** VS で未保存の編集があるファイルは、Claude は、編集しない (確認して、聞く)。デバッグ中は、編集もビルドもしない。
  - スクリプト: `vs_once.sh <solution_dir> [--status] [--changes] [--break 相対パス:行] [--clear] [--reload] [--debug]`。

### 2-8. パッケージの追加

- **`add-package`**: NuGet (`dotnet add package`)、vcpkg (マニフェストモード)、GitHub のソースの取り込み (ヘッダーのみのライブラリなど) で、ライブラリを足す。ホスト側に実行させる。
  - 頼み方: 「○○を追加して」「vcpkg で xxx を使いたい」。
  - スクリプト: `package_once.sh <solution_dir> [--timeout 秒] <操作>...`。
  - 操作の例: `nuget search <term>`、`vcpkg baseline`、`vcpkg install`、`fetch <owner/repo> <tag> <name> [<subfolder>]`。

## 3. 規約・ひな形・道具 (`rules/`、`templates/`、`scripts/`)

### 3-1. 規約 (`rules/`)

技術ごとに分けた 5 つの規約がある。**`paths` に合うファイルを Claude が読むときだけ、自動で読み込まれる** (読み込みを小さくするため)。

- **配布先**: `~/.claude/rules/` (または、プロジェクトの `.claude/rules/`)。
- **名前の方針**: 言語の共通 = `<言語>-common.md`、技術ごと = `<技術>-<言語>.md`。
- **`cpp-common.md`** (16KB): C++ の共通 (MFC・Win32・コンソール・DLL・ライブラリ)。
  - 読み込まれるファイル (`paths`): `*.cpp` `*.h` `*.hpp` `*.cc` `*.cxx`。
- **`mfc-cpp.md`** (5KB): MFC 固有。
  - 読み込まれるファイル: MFC のウィザードが作るファイル名 (`*Dlg` `*View` `*Doc` `MainFrm` `*Frame`) だけ。
  - MFC のプロジェクトの `CLAUDE.md` が、読むよう指示する。MFC を使わないプロジェクトには、適用しない。
- **`csharp-common.md`** (13KB): C# の共通 (コーディング規約、非同期、依存性注入、例外、ログ、コメント、テスト、禁止事項)。
  - 読み込まれるファイル: `*.cs`。章の番号は、WPF 規約のまま。
- **`wpf-csharp.md`** (28KB): WPF / XAML / MVVM 固有。
  - 読み込まれるファイル: `*.xaml` `*.xaml.cs` `ViewModels/` `*ViewModel*.cs` `Views/`。
- **`winforms-csharp.md`** (24KB): WinForms / MVP 固有。
  - 読み込まれるファイル: `*.Designer.cs` `Forms/` `Presenters/` `*Presenter*.cs` `I*View.cs`。
- **読み込みの大きさの目安**:
  - WinForms の Presenter = `csharp-common.md` + `winforms-csharp.md`。
  - WPF の ViewModel = `csharp-common.md` + `wpf-csharp.md`。
  - 画面と無関係の `.cs` = `csharp-common.md` だけ。
- **優先**: プロジェクトの `CLAUDE.md` に、固有の決まりがあれば、そちらが、優先される。書式の詳細は、プロジェクトの `.editorconfig` (C++ は `.clang-format`) が正。
- **配布**: `install/install.sh --rules-only`。

### 3-2. ひな形 (`templates/`)

規約が参照する、設定ファイルのひな形。

- **配布先**: `~/.claude/templates/` (または、プロジェクトの `.claude/templates/`)。
- **`templates/dotnet/.editorconfig`、`templates/dotnet/Directory.Build.props`**: C# / WPF 用。規約 (`csharp-common.md`) が参照する。
  - `/new-solution` が生成するものと、同じ内容。
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

Windows 側に置くツール。ビルド・テスト・UI テストの実行は、ここのウォッチャーが行う (→ 「2-6」)。**`run_watcher.cmd`、`watch_and_build.ps1`、`build-windows.cmd` の 3 ファイルと、`lib\` フォルダ (`watch_and_build.ps1` が読み込む 8 ファイル) は、同じフォルダに置く。** `install.sh` は、`lib\` も配る。

- **`run_watcher.cmd`**: 入口。プロジェクトのフォルダを指定して、ウォッチャーを起動する。
  - ダブルクリックでも、ドラッグ&ドロップでも、起動できる。
- **`watch_and_build.ps1`**: ウォッチャー本体 (フラグの監視ループ)。
  - 機能ごとの関数 (ビルド・テストの実行、GoogleTest の取得、パッケージ操作、UI テストの基盤) は、`lib\*.ps1` に分かれている。
- **`build-windows.cmd`**: Visual Studio の環境を読み込んで、MSBuild を実行する。
- **`run_watcher_visible.cmd [ProjectDir] [Solution] [Platform] [Configuration]`** (任意): UI テストを、**ユーザー自身のデスクトップで、目で見ながら**実行する設定で、ウォッチャーを起動する。引数は `run_watcher.cmd` と同じ。
  - 操作の間に、遅延を入れる (環境変数 `WATCH_UI_SLOWMO_MS`。既定 800 ms)。
  - 実行中は、PC を使いにくい。
- **`run_watchers.cmd [WorkFolder] [/list] [/windows]`** (任意。`/new-solutions` 用): 作業フォルダの直下の、候補 (`.sln` / `.slnx` のあるサブフォルダ) ごとに、ウォッチャーを起動する。
  - 既定は、Windows ターミナル (`wt.exe`) の 1 つのウィンドウに、候補ごとのタブ。`/windows` は、候補ごとのコンソール窓。`/list` は、候補の一覧。
  - タブ / 窓を閉じると、そのウォッチャーだけが止まる。
- **1 つのウォッチャーの範囲**: 1 つのプロジェクトと、1 つの Platform / Configuration 専用。
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
- **`host-tools/` の中身を変えたら、`host-tools/HOST_VERSION` を、その版に上げる。**

## 6. テスト (`tests/`)

- 全テスト: `for t in tests/*_test.sh; do bash $t; done` (2 分を超えることがある)。Windows は不要 (疑似ウォッチャー、疑似フォルダ、文字列の確認)。一覧は、`ls tests/*_test.sh`。
- 分類 (主なもの):

| 分類 | テスト |
|---|---|
| ウォッチャーと結果の変換 | `fake_watcher`、`host_tools_static`、`harness_note` (`RESULT_INFO` と `NOTE`)、`loop_hardening` (止めどき)、`summarize_build_log`、`summarize_test_log`、`gtest_once`、`uitest_once` |
| ソリューションの生成 | `new_solution` (C++)、`new_solution_wpf`、`new_solution_winforms`、`new_solution_csharp_dll`、`new_solution_spec_import`、`new_solutions`、`ui_tests_gen` |
| 層・プロジェクトの追加 | `add_layer`、`add_project`、`add_project_skill` (`/add-project` と `solution_state.py`)、`add_reference`、`add_ui_host` |
| テスト先行と、テストの検査 | `test_guard` (`snapshot` / `check` / `audit`)、`ui_test_first_skill`、`fix_policy` |
| 静的検査 | `mfc_check`、`wpf_check`、`winforms_check`、`wpf_menu_note`、`ui_guideline_check` |
| パッケージ | `package_once`、`cpp_pkg` |
| 規約・道具・文書 | `rules_split`、`convert_utf8_bom`、`usage_guide` (`docs/USAGE.md` と Skill の一覧のずれ) |

(各ファイルの名前は、`<名前>_test.sh`。)

- **`install.sh` を実際に実行するテストは、`--scripts-dir` などの配布先を、一時フォルダにする** (渡さないと、ホームの `~/.claude` を、上書きする。`rules_split_test.sh` が検査する)。

## 7. 文書 (`docs/`)

- [`USAGE.md`](docs/USAGE.md): 利用ガイド (どのコマンドを打つかの判断フロー、承認と差し戻しの言い方、困ったとき)。
- [`DESIGN.md`](docs/DESIGN.md): 設計メモ (契約、設計判断、取り下げた案)。
- [`TEST-PLAN.md`](docs/TEST-PLAN.md): テスト手順書 (実機の確認の手順と結果。「変更したときの、最低限の確認」を含む)。
- [`REMAINING-CHECKS.md`](docs/REMAINING-CHECKS.md): 実機の確認の状況 (確認済み、未了、廃止、保留) の正本。
- [`NEXT-STEPS.md`](docs/NEXT-STEPS.md): 次の作業 (再開用メモ。2026-11-08 時点で、必須の残りはない。任意の確認と、条件待ちのものだけ)。
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
- 検証済み: VS 2026 Enterprise、x64 / Debug。
- 実機の確認の状況 (確認済み・未了) は、[`docs/REMAINING-CHECKS.md`](docs/REMAINING-CHECKS.md) と、[`docs/TEST-PLAN.md`](docs/TEST-PLAN.md) の「状況」列。Skill 側のスクリプトと結果の変換は、疑似ウォッチャーでも検証している。

## 11. ライセンス

[MIT License](LICENSE.md)。共通の MSBuild 設定 (`Directory.Build.props` / `.targets`) は、別のリポジトリ [`macsignee/msbuild-common`](https://github.com/macsignee/msbuild-common) (同じく MIT) で管理している。
