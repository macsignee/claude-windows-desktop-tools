# cpp-claude-build-tools

Claude Code (WSL) が、Windows 側の Visual Studio で、**C++ (GoogleTest) と .NET / WPF (MSTest) の、ビルドとテストを実行し、エラーや失敗を自分で直す**ためのツール一式。C++ のみ、.NET のみ、混在のソリューションのどれでも、同じ Skill と同じウォッチャーで使う (ソリューションの中身から、自動で判定する。[設計メモ 4.24](docs/DESIGN.md))。
テストを先に書いて Red を確認し (`cpp-test-first`)、実装して Green にする (`build-test-loop`) という、TDD の流れにも使える。

Claude Code のサンドボックスからは、Windows 側の MSBuild やテスト exe を直接実行できない。
そこで、Windows 側にウォッチャーを常駐させ、Claude は、フラグファイルを置いて結果ファイルを読むだけにしている。

```
Claude Code (WSL)  ──trigger_*.flag──▶  Windows: watch_and_build.ps1 ─▶ MSBuild / テスト exe
                   ◀──*_result.txt / *_error.log──
```

## 構成

| フォルダ | 内容 | 配布先 |
|---|---|---|
| [`host-tools/`](host-tools/) | ウォッチャー (`watch_and_build.ps1`)、起動用 (`run_watcher.cmd`)、ビルド用 (`build-windows.cmd`)。**3 ファイルは同じフォルダに置く** | Windows 側の任意のフォルダ (例: `C:\tools\cpp-watcher\`) |
| [`skills/`](skills/) | Claude Code の Skill: `auto-build` (ビルドのみ。C++ / .NET 共通)、`build-test-loop` (ビルド + テスト、Green。UI テスト (FlaUI。WPF・MFC などの画面の操作を自動テスト) は、**この流れには含めず、求めたときと、`ui-test-first` のループで、別に実行する**。別のデスクトップで実行され、ユーザーの作業を止めない。失敗時のスクリーンショットを、Claude が読める。GoogleTest / MSTest 共通。失敗の要約は、同じ形)、`cpp-test-first` (テストを先に書き、Red を確認。**Red のあと、`build-test-loop/scripts/test_guard.py` で、テストの改変を検出する**)、`mfc-check` (MFC のリソース ID・メッセージマップ・層の依存の静的検査。Windows 不要)、`wpf-check` (WPF のバインディング・リソース・`InitializeComponent`・層の依存の静的検査。Windows 不要)、`winforms-check` (WinForms の `InitializeComponent`・`Designer.cs` の Name・層・スレッドの静的検査。Windows 不要)、`add-package` (NuGet / vcpkg / ソースの取り込みによる、パッケージの追加。ホスト側に実行させる)、`wpf-test-first` (WPF のテスト先行。MSTest。プロジェクト生成 `add_project.py`)、`ui-design-review` (`/ui-design-review`: UI デザインガイドライン (v2.10、草案) に沿った、画面の設計・レビュー。ガイドライン本体は `references/`。`ui_guideline_check.py` が、WPF・WinForms・MFC の一部の規則を静的に検査する。Windows 不要)、`brainstorm` (`/brainstorm`: 壁打ちで仕様を固める)、`add-feature` (`/add-feature`: 計画 → 承認 → テスト先行 → 実装 → 検証)、`update-from-ideas` (`/update-from-ideas`: アイデアを正式な仕様書へ反映)、`new-solution` (`/new-solution`: フォルダ名と同名の `.slnx` + メイン + 層 + テストの有無を指定して作成。**作業フォルダ (`solutions.md`) では、複数の候補を、まとめて作る (`new_solutions.py`)**) | `~/.claude/skills/` (WSL)。**旧名 `cpp-auto-build` / `cpp-build-test-loop` が残っていたら削除する** |
| [`docs/`](docs/) | [設計メモ](docs/DESIGN.md) (契約・設計判断・取り下げた案)、[テスト手順書](docs/TEST-PLAN.md)、[推奨する Claude Code の設定](docs/RECOMMENDED-SETTINGS.md) (テストファイルの編集と `git commit` に、確認を付ける) | |
| [`rules/`](rules/) `templates/` | ユーザー共通の規約 (`wpf-csharp.md`、`winforms-csharp.md`。C# / XAML を扱うときに、自動で読み込まれる) と、ひな形 (`templates/dotnet/`: `.editorconfig` / `Directory.Build.props`) | `~/.claude/rules/` `~/.claude/templates/` (WSL。**手で直した既存のファイルは、番号付きのバックアップを残す**) |
| [`tools/`](tools/) | `check-formats.sh`: 文字コード・改行・BOM の検証 | |
| [`tests/`](tests/) | `fake_watcher_test.sh`: Skill のスクリプトを、疑似ウォッチャーで検証。`mfc_check_test.sh`: `mfc-check` の各ルール、`wpf_check_test.sh`: `wpf-check` の各ルール (疑似の WPF プロジェクト)、`package_once_test.sh` / `cpp_pkg_test.sh`: `add-package` の操作の検証・結果の分岐と、`vcpkg.json` / `.vcxproj` の編集、`winforms_check_test.sh`: `winforms-check` の各ルール (生成したソリューションと、わざと壊した複製)、`new_solution_winforms_test.sh` / `new_solution_csharp_dll_test.sh`: WinForms / C# クラスライブラリの生成、`add_project_test.sh` / `new_solution_wpf_test.sh`: WPF のプロジェクト生成 (生成物を `wpf-check` にかけて、指摘 0 件を確認)、`add_layer_test.sh` / `new_solution_test.sh`: `cpp-test-first` と `/new-solution` のプロジェクト生成を、疑似フォルダで検証。`test_guard_test.sh`: `test_guard.py` (テストの改変の検出) の各コード、`new_solutions_test.sh`: `new_solutions.py` (作業フォルダの下に、候補ごとのソリューションを作る・同期する・対象を決める)、`gtest_once_test.sh`: GoogleTest 取得の、結果の分岐を、疑似ウォッチャーで検証 (どちらも Windows 不要)、`ui_guideline_check_test.sh`: `ui_guideline_check.py` の各コードの検出・非検出、参照文書と規則 ID の対応、Skill の記述、配布 (Windows 不要) | |
| [`install/`](install/) | `install.sh`: 配布先へコピーする (バイトを変えない) | |

使い方 (ウォッチャーの起動、引数、トラブルシューティング) は、[`host-tools/README.md`](host-tools/README.md)。

## 配布 (インストール)

WSL のターミナルで、リポジトリのルートから実行する。

```bash
install/install.sh --dry-run        # 何をコピーするかだけ表示する
install/install.sh                  # Skill -> ~/.claude/skills、ホスト側ツール -> /mnt/c/tools/cpp-watcher
```

- コピー前に、`tools/check-formats.sh` で形式を検証し、違反があれば中止する。コピー後に、`cmp` で同一性を確認する。
- 配布先は、**コピー先であって、編集する場所ではない。** 直すときは、このリポジトリを直して、配り直す。
- Skill を読み込ませるには、Claude Code のセッションを、新しく起動する。
- 配布先を変えるには、`--skills-dir DIR` / `--host-dir DIR`。

## ファイル形式 (重要)

文字コードと改行が崩れると、動かなくなる。`.gitattributes` で、git の自動変換を無効にしている。

| ファイル | 文字コード | 改行 |
|---|---|---|
| `*.cmd` | **CP932 (Shift_JIS)**、BOM なし | CRLF |
| `*.ps1` | UTF-8、**BOM あり** | CRLF |
| `*.sh` / `*.md` | UTF-8、BOM なし | **LF** |

- `.cmd` を、UTF-8 のエディタで開いて保存し直さない。編集するときは、CP932 を扱えるエディタを使う。
- 変更したら、必ず `tools/check-formats.sh` を実行する。
- `.cmd` の差分を読めるようにする (クローンごとに、1回):
  ```bash
  git config diff.cp932.textconv "iconv -f cp932 -t utf-8"
  ```

## 開発の進め方

- **このリポジトリが原本。** 作業コピーは、1 つの OS の git だけで扱う (WSL 側に置く)。同じフォルダを、Windows の git と WSL の git の両方で操作しない。
- 契約 (ファイル名・結果の値・終了コード) を変えるときは、ホスト側ツールと Skill を、**同じコミット**で直す。[`docs/DESIGN.md`](docs/DESIGN.md) の「契約」も更新する。
- 変更したときの、最低限の確認は、[`docs/TEST-PLAN.md`](docs/TEST-PLAN.md) の「変更したときの、最低限の確認」。
- 変更したら、`VERSION` と `CHANGELOG.md` を更新する。

## 対応範囲

- テスト: C++ は **GoogleTest**、.NET は **MSTest (v3 以降、VSTest モード)**。xUnit / NUnit は動く見込みだが未検証。C++ の `CppUnitTestFramework` は対象外 ([理由](docs/DESIGN.md))。
- 検証済み: VS 2026 Enterprise、x64 / Debug、C++ のみ (v1.6.0 まで)。**.NET / 混在 / 統合後のウォッチャーは、Windows 側で未検証** ([`docs/TEST-PLAN.md`](docs/TEST-PLAN.md) の 1-5)。Skill 側のスクリプトと結果の変換は、疑似ウォッチャーで検証済み。詳細は、同じ手順書の「状況」列。
- 1 つのウォッチャーは、1 つのプロジェクトと 1 つの Platform/Configuration 専用。
