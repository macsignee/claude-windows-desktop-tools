# claude-windows-desktop-tools

Claude Code (WSL) が、Windows 側の Visual Studio で、**C++ (GoogleTest) と .NET (WPF / WinForms / C# クラスライブラリ。MSTest) の、ビルドとテストを実行し、エラーや失敗を自分で直す**ためのツール一式。

- C++ のみ、.NET のみ、混在のソリューションのどれでも、同じ Skill と同じウォッチャーで使う (ソリューションの中身から、自動で判定する。[設計メモ 4.24](docs/DESIGN.md))。
- テストを先に書いて Red を確認し (`cpp-test-first` / `csharp-test-first` / `ui-test-first`)、実装して Green にする (`build-test-loop`) という、TDD の流れにも使える。
- ソリューションの作成 (`/new-solution`) も、同じ Skill 群で行う。仕様の整理 (`/brainstorm` → `/update-from-ideas`) と機能の追加 (`/add-feature`) は、別リポジトリ [`claude-spec-workflow`](https://github.com/macsignee/claude-spec-workflow) に分けた (→ 「2-3」)。
- Claude Code のサンドボックスからは、Windows 側の MSBuild やテスト exe を、直接実行できない。そこで、Windows 側にウォッチャーを常駐させ、Claude は、フラグファイルを置いて、結果ファイルを読むだけにしている。

```
Claude Code (WSL)  ──trigger_*.flag──▶  Windows: watch_and_build.ps1 ─▶ MSBuild / テスト exe
                   ◀──*_result.txt / *_error.log──
```

## 1. フォルダの構成

- [`skills/`](skills/): Claude Code の Skill (12 個。→ 「2. Skill」)。配布先: `~/.claude/skills/` (WSL)。
- [`rules/`](rules/): ユーザー共通のコーディング規約 (4 つ。→ 「3. 規約 (rules)」)。配布先: `~/.claude/rules/` (WSL)。
- [`templates/`](templates/): 規約が参照する、設定ファイルのひな形 (→ 「4. ひな形 (templates)」)。配布先: `~/.claude/templates/` (WSL)。
- [`scripts/`](scripts/): 規約が参照する道具 (→ 「5. 道具 (scripts)」)。配布先: `~/.claude/scripts/` (WSL)。
- [`host-tools/`](host-tools/): Windows 側のウォッチャーと、起動・ビルド用の `.cmd` (→ 「6. ホスト側ツール」)。配布先: Windows 側の任意のフォルダ (既定: `C:\tools\claude-watcher\`)。
- [`install/`](install/): `install.sh` (配布先へコピーする。バイトを変えない。→ 「7. 配布」)。
- [`tools/`](tools/): `check-formats.sh` (文字コード・改行・BOM の検証)。
- [`tests/`](tests/): 単体テスト (`*_test.sh`。→ 「8. テスト」)。Windows は不要。
- [`docs/`](docs/): 設計と手順の文書 (→ 「9. 文書」)。
- `CHANGELOG.md`: 変更履歴。`VERSION`: 版 (配布先にも置かれ、ウォッチャーと Skill の版の照合に使う)。

## 2. Skill (`skills/`)

### 2-1. 起動のしかた

- **スラッシュコマンドだけで起動する Skill** (依頼文では、自動では、起動しない。`disable-model-invocation: true`): `/new-solution`、`/new-solutions`、`/ui-test-first`。
- **依頼文で、自動で選ばれる Skill** (引数なし。description に合う依頼で起動する): `auto-build`、`build-test-loop`、`cpp-test-first`、`csharp-test-first`、`mfc-check`、`wpf-check`、`winforms-check`、`add-package`、`ui-design-review` (`/ui-design-review [画面名 / ファイル / 規則 ID]` で、引数つきの起動も可)。
- Skill の一覧は、Claude Code の起動時に読み込まれる。**配布したあとは、セッションを、新しく起動する。**
- 各 Skill の下の `scripts/` は、Skill が内部で呼ぶスクリプト。`references/` は、必要なときだけ読む詳細 (読み込みを小さくするため)。

### 2-2. ソリューションを作る

- **`/new-solution`**: カレントのフォルダに、**1 つ**のソリューションを作る。フォルダ名と同名の `.slnx`、メインのプロジェクト、層、テストを作り、`CLAUDE.md` に設定 (メイン・層・テスト) を書く。
  - 引数 (すべて省略可。**省略した項目は、質問する。`--tests` は、必ず質問する。**):
    - `--type`: `wpf` / `winforms` / `csharp-dll` (C# のクラスライブラリ) / `mfc` (SDI) / `mfc-mdi` / `mfc-dialog` / `win32` / `console` / `dll` / `lib` (静的ライブラリ)。
    - `--layers`: `none` / `logic` / `data` / `logic,data`。WPF は、`viewmodel` も組み合わせられる (例: `data,logic,viewmodel`)。名前の指定は `logic:OrderLogic,data:OrderData` の形。**推奨は `data,logic`** (WPF も同じ)。`viewmodel` は、ViewModel をテストしたいときに足す。WinForms と `csharp-dll` は、`data` / `logic` だけ。
    - `--tests`: `none` / `gtest` (C++) / `mstest` (.NET。層のライブラリごとに `<名前>.Tests`)。
    - `--ui-tests`: `none` / `flaui` (`<アプリ名>.UITests`。WPF / WinForms / MFC で、省略すると質問する。ビルド → テストの流れには含めない)。
    - `--layer-kind`: `dll` / `lib` / `mfc-ext-dll` / `mfc-std-dll` (C++ の層の種類。`mfc-ext-dll` = MFC 拡張 DLL (メインが MFC のときだけ)、`mfc-std-dll` = MFC 標準 DLL (共有 MFC))。`--gtest`: `auto` / `vcpkg` / `source` (C++。旧 NuGet 方式は廃止)。`--tfm`: .NET の TFM (既定 `net10.0`)。`--namespace`: 名前空間。`--spec <仕様書>`: 仕様書の「構成案」を読み込み、仕様書も取り込む。
  - すでにソリューションがあるときは、テストの後付け (`--tests gtest` / `--tests mstest`) と、UI テストの後付け (`--ui-tests flaui`) だけができる。
  - スクリプト: `new_solution.py`、`gtest_once.sh <project_dir> [tag] [timeout_sec=180]` (GoogleTest のソース取得)。
- **`/new-solutions [create | sync-spec | resolve]`**: 作業フォルダ (`solutions.md` があり、`.sln` / `.slnx` がないフォルダ) の下に、同じ題材の、種類違いの複数のソリューション (WPF / WinForms / MFC など) を、候補として、まとめて作り、比べる。1 つだけ作るときは、`/new-solution`。
  - スクリプト: `new_solutions.py`。ウォッチャーを、候補ごとに起動する `host-tools/run_watchers.cmd` もある。

### 2-3. 仕様から機能まで

- **別リポジトリ [`claude-spec-workflow`](https://github.com/macsignee/claude-spec-workflow) に分けた** (v2.44.0): `/brainstorm` (壁打ち → `docs/ideas/`)、`/update-from-ideas` (仕様書 `docs/specs/` の作成・更新)、`/add-feature` (仕様書から、計画 → 承認 → Red → Green → 検証)。**この 3 つは、このリポジトリの Skill (`cpp-test-first`、`csharp-test-first`、`build-test-loop` など) と scripts を、前提にする。**
- **このリポジトリに残る、仕様書とのつなぎ:** `/new-solution --spec <仕様書>` と `new_solutions.py` が、仕様書 (`docs/specs/*.md`。「## 構成案」「具体例」「境界値と異常系」) を読んで、器と、テストケースの種を作る。**この形式は、このリポジトリが読む側。** `/new-solution` が `CLAUDE.md` に書く 3 行が、`claude-spec-workflow` の Skill の入口になる。
- 流れ: `/brainstorm` → `/update-from-ideas` → `/add-feature` (`claude-spec-workflow`)。`/new-solution --spec <仕様書>` で、器を先に作ってもよい。

### 2-4. テストを先に書く (TDD)

- **`cpp-test-first`** (自動。「先にテストを書いて」「TDD で」など): Windows デスクトップの C++ (MFC・Win32・DLL) で、GoogleTest のテストを先に書き、スタブで Red を確認する。Red のあと、`test_guard.py` で、テストの改変を検出する。
  - スクリプト: `add_layer.py <SLN_DIR> <Name> [--kind dll|lib|mfc-ext-dll|mfc-std-dll] [--tests none|gtest] [--tests-only] [--namespace NS] [--uses OTHER ...]` (層と、そのテストを足す)。
- **`csharp-test-first`** (自動): WPF (MVVM) または WinForms (MVP) の C# で、MSTest のテストを先に書き、Red を確認する。WPF は ViewModel、WinForms は Presenter と `IView` の Fake でテストする。
  - ソリューションがない (空の) フォルダでも、まず、この Skill が使われ、`/new-solution` の実行を案内して止まる。
  - 層やテストが足りないときの手順は、`references/setup.md`。スクリプト: `add_project.py <SLN_DIR> <Name> [--kind lib|data|logic|viewmodel] [--tests none|mstest] [--tests-only]`。
  - 守る手順: Red のあとの確認、Green の前の `test_guard.py snapshot`、実装のあとの `check`、`wpf-check` / `winforms-check`、報告の先頭にテストファイル。
- **`/ui-test-first [作りたい画面・動作の説明]`**: 画面を、プロンプトで作りながら、UI テスト (FlaUI) を先に書き、実行して、直す、小さなループ。WinForms / WPF / MFC。`uitest_once.sh` で、絞って (`--filter`)、長い制限時間 (`--ui-timeout`) で、実行する。

### 2-5. ビルドとテストの実行

- **`auto-build`** (自動): ビルドだけ (C++ / .NET 共通)。エラーを読んで、自動で直し、成功するまで繰り返す。スクリプト: `build_once.sh <project_dir> [timeout_sec=180]`。
- **`build-test-loop`** (自動): ビルド + テスト (GoogleTest / MSTest 共通。失敗の要約は、同じ形)。失敗を直し、全テストが通るまで繰り返す (Green)。
  - スクリプト: `build_test_once.sh <solution_dir> [timeout_sec=300]`。
  - **UI テスト (FlaUI) は、ビルド → テストの流れに含めない。** 求められたときと、`/ui-test-first` のループで、別に実行する (別のデスクトップで実行され、ユーザーの作業を止めない。失敗時のスクリーンショットを Claude が読める)。スクリプト: `uitest_once.sh <solution_dir> [timeout_sec=900] [--visible | --separate | --invisible] [--slowmo <ms>] [--filter <式>] [--ui-timeout <秒>] [--hold <秒>] [--preview] [--present]`。詳細は `references/ui-tests.md`。
  - `test_guard.py snapshot <dir>` / `check <dir>`: Red を確認したテストを基準にコピーし、テストの改変 (削除、`[Ignore]`、アサーションを弱める、など) を検出する。`build_test_once.sh` / `uitest_once.sh` の出力の末尾に `TEST_GUARD:` の行が出る。
  - 出力の末尾の `RESULT_INFO:` (どの実行の結果か) と、`NOTE: 版の不一致` (Skill とウォッチャーの版が違う。警告だけ)。

### 2-6. 静的検査 (Windows 不要。読み取りだけ)

- **`add_ui_host.py`** (`cpp-test-first/scripts/`): 画面を持つ MFC の DLL (標準 DLL・拡張 DLL) と、画面を開くだけの exe (画面ホスト)、ロジック層の `Greeting`、UI テストを、既存のソリューションに足す。呼び出す exe がない構成で、DLL の画面を UI テストで確かめる。
- **`mfc-check`** (自動): MFC の、リソース ID の重複・未定義、メッセージマップとハンドラの不整合、ダイアログと DDX の不整合、層の依存の違反、MFC の DLL (拡張 DLL・標準 DLL) の設定の食い違い。
- **`wpf-check`** (自動): WPF の、バインディングのパスの誤り、`StaticResource` のキー、`InitializeComponent()` の呼び忘れ、`StartupUri` などの誤り、層の依存の違反、規約のうち機械で判定できる項目。
- **`winforms-check`** (自動): WinForms の、`InitializeComponent()` の呼び忘れ、`Designer.cs` の `Name`、層の依存、スレッド、規約のうち機械で判定できる項目。
- 3 つとも、スクリプトの引数は同じ: `<dir> [--json <out.json>] [--max-lines 40] [--all]`。
- **`ui-design-review`** (自動。`/ui-design-review [画面名 / ファイル / 規則 ID]`): WPF / WinForms / MFC の画面を、UI デザインガイドライン (v2.10。規則 ID `UI-XXX-nnn`) に沿って、設計・レビューする。ガイドライン本体は `references/`。スクリプト: `ui_guideline_check.py PROJECT_DIR [--all] [--json FILE] [--fail-on-warning]` (一部の規則を静的に検査)。

### 2-7. パッケージの追加

- **`add-package`** (自動): NuGet (`dotnet add package`)、vcpkg (マニフェストモード)、GitHub のソースの取り込み (ヘッダーのみのライブラリなど) で、ライブラリを足す。ホスト側に実行させる。スクリプト: `package_once.sh <solution_dir> [--timeout 秒] <操作>...` (操作の例: `nuget search <term>`、`vcpkg baseline`、`vcpkg install`、`fetch <owner/repo> <tag> <name> [<subfolder>]`)。

## 3. 規約 (`rules/`)

- 配布先は `~/.claude/rules/`。**`paths` に合うファイルを Claude が読むときだけ、自動で読み込まれる** (読み込みを小さくするため、技術ごとに分けている)。
- 名前の方針: 言語の共通 = `<言語>-common.md`、技術ごと = `<技術>-<言語>.md`。
- `cpp-common.md` (16KB): C++ の共通の規約 (MFC・Win32・コンソール・DLL・ライブラリ)。`paths`: `*.cpp` `*.h` `*.hpp` `*.cc` `*.cxx`。
- `mfc-cpp.md` (5KB): MFC 固有の規約。`paths`: MFC のウィザードが作るファイル名 (`*Dlg` `*View` `*Doc` `MainFrm` `*Frame`) だけ。MFC のプロジェクトの `CLAUDE.md` が、読むよう指示する。MFC を使わないプロジェクトには、適用しない。
- `csharp-common.md` (13KB): C# の共通部分 (C# のコーディング規約、非同期、依存性注入、例外、ログ、コメント、テスト、禁止事項)。`paths`: `*.cs`。章の番号は、WPF 規約のまま。
- `wpf-csharp.md` (28KB): WPF / XAML / MVVM の固有部分。`paths`: `*.xaml` `*.xaml.cs` `ViewModels/` `*ViewModel*.cs` `Views/`。
- `winforms-csharp.md` (24KB): WinForms / MVP の固有部分。`paths`: `*.Designer.cs` `Forms/` `Presenters/` `*Presenter*.cs` `I*View.cs`。
- 読み込みの大きさの目安: WinForms の Presenter = `csharp-common.md` + `winforms-csharp.md`。WPF の ViewModel = `csharp-common.md` + `wpf-csharp.md`。画面と無関係の `.cs` = `csharp-common.md` だけ。
- プロジェクトの `CLAUDE.md` に、固有の決まりがあれば、そちらが、優先される。書式の詳細は、プロジェクトの `.editorconfig` (C++ は `.clang-format`) が正。
- 配布: `install/install.sh --rules-only`。

## 4. ひな形 (`templates/`)

- 配布先は `~/.claude/templates/`。
- `templates/dotnet/.editorconfig`、`templates/dotnet/Directory.Build.props`: C# / WPF 用。`/new-solution` が生成するものと、同じ内容。規約 (`csharp-common.md`) が参照する。
- `templates/cpp/.clang-format`、`.clang-tidy`、`.editorconfig`: C++ 用。`cpp-common.md` が参照する (Allman、インデント 4、`#include` の順序は変えない、関数は 100 行まで (`readability-function-size`)、`.cpp` / `.h` / `.hpp` は CRLF)。`/new-solution` (C++) は、生成しない。
- 手で直した既存のファイルは、上書きせず、番号付きのバックアップ (`*.~N~`) を残す。バックアップは、読み込まれない。消してよい。

## 5. 道具 (`scripts/`)

- 配布先は `~/.claude/scripts/`。規約 (`cpp-common.md`、`csharp-common.md`) が参照する。
- `convert_to_utf8_bom.py`: Shift-JIS (CP932) のソースを、UTF-8 (BOM 付き) / CRLF に変換する。
  - 使い方: `python3 -I ~/.claude/scripts/convert_to_utf8_bom.py [--apply] <ファイル>...`。既定は、検証だけ (書かない)。`--apply` で書き換える。
  - **手動で、ファイルを指定して、1 回だけ実行する** (規約の「変換だけの、別のコミット」)。ビルドの流れには、組み込まれていない。
  - 往復の確認 (CP932 に戻して一致) をして、確認できないファイルは、書かない。BOM 付きの UTF-8 は、スキップする。**BOM なしの UTF-8 (非 ASCII を含む) は、Shift-JIS ではないので、NG にして、書かない。** 存在しないファイルは、NG にして、続ける。

## 6. ホスト側ツール (`host-tools/`)

- Windows 側に置く。**`run_watcher.cmd`、`watch_and_build.ps1`、`build-windows.cmd` の 3 ファイルと、`lib\` フォルダ (`watch_and_build.ps1` が読み込む 8 ファイル) は、同じフォルダに置く。** `install.sh` は、`lib\` も配る。
- `run_watcher.cmd`: 入口。プロジェクトのフォルダを指定して、ウォッチャーを起動する (ダブルクリック、ドラッグ&ドロップも可)。
- `watch_and_build.ps1`: ウォッチャー本体 (フラグの監視ループ)。機能ごとの関数 (ビルド・テストの実行、GoogleTest の取得、パッケージ操作、UI テストの基盤) は、`lib\*.ps1` に分かれている。
- `build-windows.cmd`: Visual Studio の環境を読み込んで、MSBuild を実行する。
- `run_watcher_visible.cmd [ProjectDir] [Solution] [Platform] [Configuration]` (引数は `run_watcher.cmd` と同じ): UI テストを、**ユーザー自身のデスクトップで、目で見ながら**実行する設定で、ウォッチャーを起動する (任意)。操作の間に、遅延を入れる (環境変数 `WATCH_UI_SLOWMO_MS`。既定 800 ms)。実行中は、PC を使いにくい。
- `run_watchers.cmd [WorkFolder] [/list] [/windows]`: 作業フォルダの直下の、候補 (`.sln` / `.slnx` のあるサブフォルダ) ごとに、ウォッチャーを起動する (任意。`/new-solutions` 用)。既定は、Windows ターミナル (`wt.exe`) の 1 つのウィンドウに、候補ごとのタブ。`/windows` は、候補ごとのコンソール窓。`/list` は、候補の一覧。タブ / 窓を閉じると、そのウォッチャーだけが止まる。
- 1 つのウォッチャーは、1 つのプロジェクトと、1 つの Platform / Configuration 専用。
- 起動の仕方、引数、取り決め (フラグファイルと結果ファイル)、トラブルシューティングは、[`host-tools/README.md`](host-tools/README.md)。

## 7. 配布 (インストール)

- WSL のターミナルで、リポジトリのルートから実行する。
  ```bash
  install/install.sh --dry-run        # 何をコピーするかだけ表示する
  install/install.sh                  # すべて配る
  ```
- 配るもの (オプションなしは、すべて):
  - Skill → `~/.claude/skills` (`--skills-only`)。
  - ホスト側ツール → `/mnt/c/tools/claude-watcher` (`--host-only`)。
  - 規約・ひな形・道具 → `~/.claude/rules`、`~/.claude/templates`、`~/.claude/scripts` (`--rules-only`)。
  - **Skill だけを配っても、規約は、配られない。** 規約を変えたときは、`--rules-only` も、実行する。
- 配布先を変えるオプション: `--skills-dir DIR`、`--host-dir DIR`、`--rules-dir DIR`、`--templates-dir DIR`、`--scripts-dir DIR`。
- コピー前に、`tools/check-formats.sh` で形式を検証し、違反があれば中止する。コピー後に、`cmp` で同一性を確認する。
- 配布先は、**コピー先であって、編集する場所ではない。** 直すときは、このリポジトリを直して、配り直す。
- Skill を読み込ませるには、Claude Code のセッションを、新しく起動する。ホスト側を再配置したら、ウォッチャーを再起動する (起動時に読み込むため)。
- 配布先に、このリポジトリの版 (`VERSION`) も置く (各 Skill のフォルダと、ホスト側のフォルダ)。ウォッチャーは、起動バナーに版を出し、結果の `run_id.txt` に書く。Skill 側 (`*_once.sh`) が照合し、**不一致なら、出力の末尾に `NOTE:` を出す (警告だけ。実行は止めない)。**

## 8. テスト (`tests/`)

- 全テスト: `for t in tests/*_test.sh; do bash $t; done` (2 分を超えることがある)。Windows は不要 (疑似ウォッチャー、疑似フォルダ、文字列の確認)。
- ウォッチャーと結果の変換: `fake_watcher_test.sh`、`host_tools_static_test.sh`、`harness_note_test.sh` (`RESULT_INFO` と `NOTE`)、`loop_hardening_test.sh` (止めどき)、`summarize_build_log_test.sh`、`summarize_test_log_test.sh`、`gtest_once_test.sh`、`uitest_once_test.sh`。
- ソリューションの生成: `new_solution_test.sh` (C++)、`new_solution_wpf_test.sh`、`new_solution_winforms_test.sh`、`new_solution_csharp_dll_test.sh`、`new_solution_spec_import_test.sh`、`new_solutions_test.sh`、`add_layer_test.sh`、`add_project_test.sh`、`ui_tests_gen_test.sh`。
- テスト先行と改変の検出: `test_guard_test.sh`、`ui_test_first_skill_test.sh`。
- 静的検査: `mfc_check_test.sh`、`wpf_check_test.sh`、`winforms_check_test.sh`、`wpf_menu_note_test.sh`、`ui_guideline_check_test.sh`。
- パッケージ: `package_once_test.sh`、`cpp_pkg_test.sh`。
- 規約と道具: `rules_split_test.sh`、`convert_utf8_bom_test.sh`。
- **`install.sh` を実際に実行するテストは、`--scripts-dir` などの配布先を、一時フォルダにする** (渡さないと、ホームの `~/.claude` を、上書きする。`rules_split_test.sh` が検査する)。

## 9. 文書 (`docs/`)

- [`DESIGN.md`](docs/DESIGN.md): 設計メモ (契約、設計判断、取り下げた案)。
- [`TEST-PLAN.md`](docs/TEST-PLAN.md): テスト手順書 (実機の確認の手順と結果。「変更したときの、最低限の確認」を含む)。
- [`REMAINING-CHECKS.md`](docs/REMAINING-CHECKS.md): 実機の確認の状況 (確認済み、未了、廃止、保留) の正本。
- [`NEXT-STEPS.md`](docs/NEXT-STEPS.md): 次の作業 (古い部分がある。最新は、`CHANGELOG.md` と `TEST-PLAN.md`)。
- [`RECOMMENDED-SETTINGS.md`](docs/RECOMMENDED-SETTINGS.md): 推奨する Claude Code の設定 (テストファイルの編集と、`git commit` に、確認を付ける)。

## 10. ファイル形式 (重要)

- 文字コードと改行が崩れると、動かなくなる。`.gitattributes` で、git の自動変換を無効にしている。

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

## 11. 開発の進め方

- **このリポジトリが原本。** 作業コピーは、1 つの OS の git だけで扱う (WSL 側に置く)。同じフォルダを、Windows の git と WSL の git の両方で操作しない。
- 契約 (ファイル名・結果の値・終了コード) を変えるときは、ホスト側ツールと Skill を、**同じコミット**で直す。[`docs/DESIGN.md`](docs/DESIGN.md) の「契約」も更新する。
- 変更したときの、最低限の確認は、[`docs/TEST-PLAN.md`](docs/TEST-PLAN.md) の「変更したときの、最低限の確認」。
- 変更したら、`VERSION` と `CHANGELOG.md` を更新する。

## 12. 対応範囲

- テスト: C++ は **GoogleTest**、.NET は **MSTest (v3 以降、VSTest モード)**。xUnit / NUnit は動く見込みだが未検証。C++ の `CppUnitTestFramework` は対象外 ([理由](docs/DESIGN.md))。
- 対象外: ASP.NET Core などの Web、MAUI、Linux / macOS 向けの .NET、組み込みの C++ (Windows デスクトップの Visual Studio / MSBuild が対象)。
- 検証済み: VS 2026 Enterprise、x64 / Debug。**実機の確認の状況 (確認済み・未了) は、[`docs/REMAINING-CHECKS.md`](docs/REMAINING-CHECKS.md) と、[`docs/TEST-PLAN.md`](docs/TEST-PLAN.md) の「状況」列。** Skill 側のスクリプトと結果の変換は、疑似ウォッチャーでも検証している。
