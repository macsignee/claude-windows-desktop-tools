# 変更履歴

形式: [バージョン] 日付 / 変更の要点。契約 (ファイル名・結果の値・終了コード) を変えたときは、そのことを明記する。

## [2.66.0] 2026-11-09 (共通の `Directory.Build.*` は、外の正本を読んで置く。参照型と、`/add-project common`)

- **方針:** Claude は、共通の `Directory.Build.props` / `.targets` の中身を決めない。**外の正本 (`msbuild-common`) を読んで、ソリューションに合わせて置く。**
- **参照型を追加した (`msbuild-common/templates/reference/`)。** ソリューション直下に、外の正本を参照する薄いファイルだけを置く (コピーしない)。MSBuild は、Windows 側の環境変数 `MSBUILD_COMMON_DIR` で、正本を探す。未設定のときは、`__MSBUILD_COMMON_DIR_NOT_SET__\Common.props was not found` で止まる (黙って飛ばさない)。コピー型 (v2.65.0 の形) は、ソリューションだけで完結させたいときのために、残した。
- **正本の場所:** ソリューションの `CLAUDE.md` の「- MSBuild 共通: <パス>」 → 環境変数 `MSBUILD_COMMON_DIR` (WSL 側のパス。`C:\...` も、`/mnt/c/...` に直す) → 配布用のコピー (`skills/new-solution/msbuild-common/`)。**型 (`auto`):** 場所が、`CLAUDE.md` か環境変数なら参照型、配布用のコピーならコピー型。`--common copy|reference`、`--common-dir <パス>` で指定できる。参照型で場所がなければ、何も書かずに止まる (配布用のコピーは、Windows のビルドから見えない)。
- **共通の処理:** `skills/new-solution/scripts/msbuild_source.py` (場所の決定、型の決定、ファイルの読み込み、`CLAUDE.md` の節、Windows 側の環境変数の NOTE (`wslpath -w`))。`new_solution.py` は、これを使う。参照型では、`CLAUDE.md` に「- MSBuild 共通: <パス>」の行と、コピーしない旨の節を書き、案に、Windows 側の環境変数の設定の NOTE を出す。
- **`/add-project common` (`skills/add-project/scripts/add_common.py`) を追加した。** すでにあるソリューションに、同じものを足す。出力は `add_platform.py` と同じ形 (`+` 足す / `~` 書き換える / `=` すでに同じ / `!` 止まる)。`auto` は、すでにある薄いファイルの型を保つ。書き換えてよいのは、以前の `/new-solution` が作った `Directory.Build.props` (`Nullable` などを直接書くもの。効果は同じ)、型を切り替えるときの薄いファイル、古い版の `build\common\`、`CLAUDE.md` の自動生成の節だけ。**手で書いた `Directory.Build.props` / `.targets` は、書き換えず、止まる** (手で足す `Import` の行を示す)。`solution_state.py` の `ADDABLE` に `common` が出る。
- テスト: `tests/add_common_test.sh` (新規。28 件)、`tests/new_solution_common_test.sh` (77 件。参照型・`--common`・`--common-dir`・環境変数が不正、を足した)、`tests/msbuild_common_test.sh` (14 件。参照型の薄いファイル)。
- **未確認 (実機):** 参照型で `PASSED` になること、環境変数がないと止まること、Windows 側の環境変数が、ウォッチャーに届くこと、WSL と Windows のパスが同じフォルダを指すこと (TEST-PLAN 2-41)。**`install.sh --skills-only` での配布が要る。**

## [2.65.0] 2026-11-09 (`/new-solution` が、薄い `Directory.Build.props` / `.targets` と `build\common\` を作る)

- **`/new-solution` が、新規のソリューション (すべての種類) に、`msbuild-common` (v0.1.1) を置く。** ソリューション直下に、薄い `Directory.Build.props` / `Directory.Build.targets` (親のフォルダのファイルも読む)、`build\common\` に `Common.props`・`Dotnet.props`・`Common.targets`・`VERSION`。承認の案 (`+` の一覧) にも出る。
- **.NET (`wpf` / `winforms` / `csharp-dll`):** 以前の `Directory.Build.props` (`Nullable` / `ImplicitUsings` / `LangVersion` を直接書く) は、作らない。同じ設定は、`build\common\Dotnet.props` に移った (**効果は同じ**。MB1 で実機確認済み)。C++ は、設定を持たず、`ClaudeBuildInfo` (`/p:ClaudeBuildInfo=true` のときだけ) だけが使える (MB3 で確認済み)。
- **すでに `Directory.Build.props` / `.targets` があるフォルダでは、上書きしない** (`NOTE:` を出す。`build\common\` は作る)。`CLAUDE.md` に、「`build\common\` はコピー。手で編集しない」の節 (.NET は `Dotnet.props` の説明つき) を足す。
- **配布:** `install.sh` は `skills/` だけを配るため、正本 `msbuild-common/` のコピーを `skills/new-solution/msbuild-common/` に置いた。`tests/msbuild_common_test.sh` が、同じであることを確かめる (正本を変えたら、同期する)。**`install.sh --skills-only` での配布が要る。**
- `/add-project` (既存のソリューションへの追加) と `csharp-test-first/add_project.py` の `DIRECTORY_BUILD_PROPS` は、変えていない。
- テスト: `tests/new_solution_common_test.sh` (新規。10 種類すべて。正本と同じ、案への表示、`CLAUDE.md`、dry-run、既存の上書きなし)、`tests/msbuild_common_test.sh` (13 件)。`new_solution_wpf_test.sh` / `new_solution_csharp_dll_test.sh` は、`Directory.Build.props` の期待を更新。
- **実機の確認 (2026-11-09):** 10 種類のうち、`wpf`・`winforms`・`csharp-dll`・`mfc`・`win32`・`dll`・`lib`・`console` (既存の `Directory.Build.props` ありの場合) で、作成直後のベースラインが `PASSED` (TEST-PLAN 2-40 の CM1〜CM6)。`Nullable` の効きも確認。**未確認:** `mfc-mdi`・`mfc-dialog` (生成物は、`mfc` と同じ共通ファイルで、静的テストは通っている)。

## [2.64.1] 2026-11-09 (`msbuild-common` v0.1.1: ClaudeBuildInfo の出力先を直す)

- **実機の確認 MB1 で、`ClaudeBuildInfo` の出力先が、想定と違った。** WPF (.NET 10、SDK 形式) のソリューションに、薄いファイルと `build\common\` を置いて、ビルドとテストは `PASSED` (共通ファイルは、エラーなく読まれ、`common_version=0.1.0` が書かれた)。ただし、`claude-build-info.txt` が、`obj\` ではなく、**各プロジェクトのフォルダ直下**にできた。SDK 形式の `.csproj` では、`$(IntDir)` が空だったため。
- `Common.targets`: 出力先を、`$(IntDir)` → `$(IntermediateOutputPath)` → `$(MSBuildProjectDirectory)\obj\` の順に探す。C++ は、いままでどおり `$(IntDir)`。`VERSION` と `MsbuildCommonVersion` を 0.1.1 にした。
- テスト: `tests/msbuild_common_test.sh` に 1 件 (12 件)。
- **実機の確認 (2026-11-09):** 直したあと、3 つとも `obj\Debug\<TFM>\` にできた (MB1)。無効のときは、できない (MB2)。`Nullable` が効き、`CS8600` が出る (MB1)。C++ (MB3。`DPop3`) でも、薄いファイルでビルドとテストが `PASSED`、`obj\<プロジェクト>\x64\Debug\` に、`common_version=0.1.1` つきで、できた。**未確認:** MB3 の `platform=x64` の行そのもの (報告に含まれない)。MB1 の `.csproj` の `Dotnet.props` を、C++ が読まないことの直接の確認。

## [2.64.0] 2026-11-08 (`msbuild-common/`: Directory.Build.props / targets の共通設定のたたき台)

- **`msbuild-common/` を追加した (v0.1.0)。** MSBuild の標準の仕組み (`Directory.Build.props` / `Directory.Build.targets`) で、共通の設定を 1 か所に置くためのたたき台。将来、別のリポジトリに分けて、共通のベースにする。**スキルは、まだ、使っていない** (動きは、何も変わらない。配布も、要らない)。
  - `Common.props` (入口。版 `MsbuildCommonVersion`。`.csproj` のときだけ `Dotnet.props` を読む)、`Dotnet.props` (`Nullable`・`ImplicitUsings`・`LangVersion`。**いま `/new-solution` が作る `Directory.Build.props` と同じ内容**。`TargetFramework` は、置かない)、`Common.targets` (`ClaudeBuildInfo`: `/p:ClaudeBuildInfo=true` のときだけ、プロジェクト名・構成・Platform・出力ファイル・版を `$(IntDir)claude-build-info.txt` に書く。**既定では何もしない**)、`templates/` (ソリューション直下の薄い `Directory.Build.props` / `.targets`。親のフォルダのファイルも読む)、`VERSION`、`README.md`。
  - **置き方 (予定):** ソリューションに `build\common\` としてコピーして、コミットする (WSL の `~/.claude` は、Windows のビルドから見えない)。分けるときは、スキルのパスに触れていないので、そのまま移せる。
- テスト: `tests/msbuild_common_test.sh` (11 件。XML、版の一致、`Dotnet.props` が既存の `DIRECTORY_BUILD_PROPS` と同じ、既定では何もしない、薄いファイルの参照、スキルのパスに触れない)。
- **未確認:** MSBuild での実際の読み込みとビルド (WSL に MSBuild がないため、静的検査だけ)。実機 (ウォッチャーのある Windows) で、薄いファイルを置いて、ビルドが通ることと、`ClaudeBuildInfo` が書くことを、確かめる必要がある。
- **次の版の候補:** `/new-solution` が薄いファイルと `build\common\` を作る。`/add-project` で既存のソリューションに足す。C++ の `Cpp.props` (`OutDir`・`IntDir` など)。

## [2.63.2] 2026-11-08 (`/new-solution`: 了承の質問に、UI テストの選択肢を足さない)

- **`/new-solution` の SKILL (手順 3): `--ui-tests` が `none` のとき、案には「UI テスト: なし」の 1 行だけを書き、了承の質問の選択肢に、「FlaUI も一緒に作る」のような選択肢を足さない。** v2.63.0 で、UI テストの質問をやめたが、実機 (`uitest2`) で、Claude が、作成の了承の選択肢に「UIテスト (FlaUI) も一緒に作る」を足して、実質、もう一度尋ねていた。`flaui` と明示されたときは、案に書く (いままでどおり)。足したいときは、「その他」で書くか、あとから `/add-project ui-tests`。
- テスト: `tests/ui_test_first_skill_test.sh` に 1 件。スクリプトは、変えていない。**配布が要る** (`new-solution`)。

## [2.63.1] 2026-11-08 (`/new-solution`: .NET で、名前が Test / Tests で終わるフォルダを、エラーにする)

- **`new_solution.py`: `--type wpf` / `winforms` / `csharp-dll` で、フォルダ名 (= メインの名前) の末尾が `test` / `tests` (大文字小文字を問わない。例: `uitest`、`MyTests`) のとき、何も書かずに、終了コード 2 で止める** (別の名前を案内)。すでにソリューションがあるフォルダ (後付け) は、対象外。`--spec` の取り込みのあとで検査する。
- **原因:** ウォッチャーは、`.NET` のプロジェクトの名前が `(Test|Tests)$` に合うと、大文字小文字を区別せずに (`host-tools/lib/tests.ps1:76`)、テストのプロジェクトと見なす。`uitest` のアプリに `dotnet test` が走り、テストが 0 件で `ENV_ERROR` (終了コード 4) になった (v2.63.0 の実機の確認で発見。`uitest2` では起きない)。Python の検査 (`mfc_check.py`・`wpf_check.py` など) は、大文字小文字を区別するので、判定がずれていた。ウォッチャーは、変えていない。
- **C++ は、対象外。** C++ には、名前が `Test` で終わるメインを、`TargetName` で扱う仕組みがある (`MFCTDDTest`)。
- テスト: `tests/new_solution_test.sh` に 9 件 (`uitest`・`MyTests`・`apptest` で rc 2 と何も書かない、`uitest2` と C++ の `CppTest` は通る)。`SKILL.md` の「フォルダ名」に追記した。**配布が要る** (`new-solution`)。

## [2.63.0] 2026-11-08 (`/new-solution`: UI テストの質問をやめる。既定は `none`)

- **`/new-solution` の SKILL: `--ui-tests` を質問しない。** 引数にも構成案 (`UIテスト`) にも指定がなければ、wpf / winforms / mfc 系を含む、どの種類でも、既定の `none`。**`flaui` と明示されたときだけ作る。** あとから足すには、`/add-project ui-tests` か `--ui-tests flaui` (どちらも、いままでどおり)。v2.33.0 の「GUI の種類では必ず質問する」(TEST-PLAN 2-15 の UQ1〜UQ3) を、取り下げた。
- `/new-solutions` (複数候補) の質問の順から、`UIテスト` を外した (構成案の表の `UIテスト` 列は、そのまま。省略すると `none`)。README の `--ui-tests` の説明を合わせた。
- テスト: `tests/ui_test_first_skill_test.sh` の該当の 1 件を、新しい動きに書き換えた。
- スクリプト (`new_solution.py`) は変えていない (もともと既定は `none`)。**配布が要る** (`new-solution`・`new-solutions`)。UQ1〜UQ3 の期待 (質問が出る) は、古くなった。

## [2.62.4] 2026-11-10 (文書: Win32 の実機の確認 (W3・W5・W7) の記録。NEXT-STEPS の更新)

- **v2.62.0 の実機の確認 (TEST-PLAN 2-38) の W3・W5・W7 が ✔。これで W1〜W8 は、すべて済んだ。**
  - **W3:** MFC 拡張 DLL (`plW3`) と標準 DLL (`plW3b`) の層を、`x64,Win32` で作り、Win32 でビルド。拡張 DLL を参照するメインも、Win32 でリンクできた。PE はすべて 0x14c、`mfc-check` は 0 / 0。テストの実行 (`PASSED`) は、確認していない (ビルドだけ)。
  - **W5:** `win32`・`console`・`dll`・`lib` を、`x64,Win32` で作り、Win32 でビルド。PE はすべて 0x14c、`mfc-check` は 0 / 0。
  - **W7:** `--platforms Win32` で作り、層とテストを足した。ウォッチャーが x64 のままだと `MSB4126` で止まり、Claude は、Platform の食い違いと診断して、再起動を案内した。Win32 で `PASSED`。足した層・テストの `.vcxproj` は、Win32 だけ。
- **気づき:** ウォッチャーが起動済みなのに、Claude が質問ツールで起動を確認することがあった (1 回。結果には影響なし。SKILL に指示はない)。
- `docs/NEXT-STEPS.md` を、今の状態 (v2.62.4) に書き直した。
- 動作は変えていない (記録だけ)。配布は要らない。

## [2.62.3] 2026-11-10 (`add_platform.py`: x64 固有の記述が写るとき、注意を出す。W8 の実機の確認)

- **`add_platform.py` が、複製で、元のプラットフォームの名前 (x64 など) を含む行 (例: `..\lib\x64`) を、そのまま、新しいプラットフォームに写したとき、案の中に `【注意】x64 を含む記述が、そのまま Win32 に写った (確認すること)` を出す** ようにした。止めはしない。W8 の往復の確認で、本物のウィザードの `.vcxproj` 26 個には、該当がなかったが、手で設定したプロジェクトでは、起こりえるため。
- **W8 が ✔** (TEST-PLAN 2-38)。(a) 本物のウィザードの `.vcxproj` 26 個の往復の確認: エラー 0。差が出た 12 個は、元の Win32 の構成が、x64 と違っていた (x64 にだけ設定を足していた) ため。(b) 実機: ウィザードで作った `MFCFirstApp` の x64 だけのコピーに、あとから Win32 を足し、足した結果が、元のウィザードの `.vcxproj` と、行の集合まで一致、x64 と Win32 の両方で `SUCCESS` (Win32 は x86 の exe)。
- テスト: `tests/win32_platform_test.sh` に 4 件 (注意が出る・止めない・固有の記述がなければ出ない)。
- **配布が要る** (`add-project`)。残りの未実施: W3・W5・W7。

## [2.62.2] 2026-11-10 (文書: Win32 のあとからの追加 (W6) の実機の確認の記録)

- **W6 が ✔。** 既定 (x64 だけ) で作った `plLater` (MFC SDI + 層 2 つ + GoogleTest) に、`/add-project platform Win32` で、あとから Win32 を足し、x64 と Win32 の両方で、ビルドとテストが通った。続けて、`/add-project layer` で足した `ReportLayer` (とテスト) は、**Win32 と x64 の 4 構成で作られ**、Win32 で `PASSED` (3 件)、`mfc-check` は 0 / 0。**既定の実機の回帰 (W1 の既定側) も、同時に確認した。**
- **気づき (候補):** `auto-build` / `build-test-loop` の SKILL に、「結果を報告するときは、ビルドのログのソリューション構成の行 (`Debug|x86` / `Debug|x64`) から、Platform を書く」を足す (ウォッチャーは変えない)。Claude が、`SUCCESS` が x64 か Win32 か、判断できなかった。
- **未実施:** W3・W5・W7・W8。
- 動作は変えていない (記録だけ)。

## [2.62.1] 2026-11-10 (文書: Win32 の実機の確認 (W1・W2・W4) の記録)

- **v2.62.0 の実機の確認 (TEST-PLAN 2-38) のうち、W1・W2・W4 が ✔。** `--platforms x64,Win32` で作った MFC のソリューション (`plBoth`、層 2 つ + GoogleTest) を、x64 でビルド・テスト (`PASSED`)、ウォッチャーを Win32 で起動し直して、Win32 でビルド・テスト (`PASSED`。`Debug|x86`、vcpkg の `x86-windows-static-md`、`Win32\Debug\*Test.exe` は x86 (PE 0x14c))。Visual Studio で、ソリューション プラットフォームが x64 と x86 の 2 つ。
- **未実施:** W3 (MFC 拡張・標準 DLL の層を Win32 で)、W5 (MFC 以外)、W6 (あとから `/add-project platform Win32`)、W7 (Win32 のみ)、W8 (ウィザードで作ったプロジェクト)。
- 動作は変えていない (記録だけ)。

## [2.62.0] 2026-11-10 (C++ のプラットフォーム (Win32 / x64) の指定と、あとからの追加)

- **`/new-solution --platforms` を追加した** (`docs/DESIGN.md` 4.83)。C++ のとき、`x64` (**既定**) / `x64,Win32` (ウィザードと同じ 4 構成。`.slnx` は x64 と x86) / `Win32`。**質問はしない。** .NET と、すでにあるソリューションに指定すると、エラー。仕様書の構成案に `プラットフォーム:` のキー。
- **`/add-project platform <Win32 | x64>` を追加した** (`scripts/add_platform.py`)。すでにあるソリューションに、あとから、Win32 (または x64) を足す。全部の C++ の `.vcxproj` の構成を複製し、`.slnx` に `<Platform Name="x86" />`、`.sln` に構成の対応づけを足す。**結果は、最初から両方で作ったものと、同じ。** すでにあれば何もしない。**想定と違う形の `.vcxproj` が 1 つでもあれば、何も書かずに止まる。** `solution_state.py` に `PLATFORMS` と `ADDABLE` の `platform:...`。
- **層・テスト・画面ホストを、あとから足すとき、既存のソリューションのプラットフォームに、そろえる** (`add_layer.py`・`add_ui_host.py`・`new_solution.py --tests gtest`)。`.sln` の編集は、ソリューションの x86 を、プロジェクトの Win32 に対応づける。
- **既定 (x64 だけ) の `.vcxproj` の出力は、v2.60.4 と同じ** (バイト単位。192 通りで確認)。生成する `CLAUDE.md` に、プラットフォームの案内 (x64 だけ / 両方 / Win32 のみ、ウォッチャーの起動の仕方) を足した。`.gitignore` に `Win32/`。
- **ウォッチャーは、変えていない** (`Platform` 引数は、すでに Win32 に対応。引数なしは x64)。選択中のプラットフォームに従う案は、取り下げた。
- テスト: `tests/win32_platform_test.sh` を新設 (種類ごとの 4 構成、Win32 のみ、あとから追加と、最初から両方との一致、冪等、dry-run、想定外の形式、`.sln`、層・テストが、ソリューションにそろう、`solution_state`・SKILL・README)。
- **配布が要る** (`new-solution`、`cpp-test-first`、`add-project`)。**実機の確認は、未実施** (TEST-PLAN 2-38 の W1〜W7。vcpkg の x86 の gtest の取得を含む)。

## [2.60.4] 2026-11-10 (MFC の生成物のメニューとダイアログの文言を、日本語にした)

- **`--type mfc` / `mfc-mdi` / `mfc-dialog` の `.rc` を、日本語にした** (`docs/DESIGN.md` 4.82)。v2.60.1 の MDI の実機の確認で、「メニューが英語」という指摘があり、利用者が、日本語にすると決めた。ウィザードの日本語版の言い回しに合わせた。
  - メニュー: 「ファイル(&F)」「アプリケーションの終了(&X)」、MDI は「新規作成(&N)」「閉じる(&C)」「ウィンドウ(&W)」(「新しいウィンドウ」「重ねて表示」「上下に並べて表示」「アイコンの整列」)。ダイアログ: 「名前(&N):」「クリア(&C)」「OK」「キャンセル」。
  - **符号化:** `.rc` は、UTF-8 (BOM 付き)・CRLF、先頭近くに `#pragma code_page(65001)`、`LANGUAGE LANG_JAPANESE, SUBLANG_DEFAULT` (`ResourceCompile` の `Culture` 0x0411 と、そろった)。`res\<名前>.rc2` は、ASCII (BOM なし) のまま。
  - UI テストの生成は、AutomationId (ID の数値) で探すので、影響しない。
- **変えていないもの:** `/add-project ui-host` が作る画面ホストの `.rc` (英語)。**別に直す候補。**
- テスト: `tests/mfc_wizard_layout_test.sh` を、日本語・UTF-8 (BOM 付き)・`code_page`・`LANG_JAPANESE` を確かめるように直した。`tests/new_solution_test.sh`・`tests/ui_tests_gen_test.sh` の `.rc` の期待も、直した。
- **配布が要る** (`new-solution`)。**実機の確認 (TEST-PLAN 2-37 の JA1〜JA5) は、すべて ✔** (2026-11-10。SDI・MDI・ダイアログ。`rc.exe` が、UTF-8 (BOM 付き) + `code_page(65001)` の `.rc` を、警告なしでビルドし、メニューとダイアログの文字が、文字化けなしで表示され、MDI の「新規作成」「重ねて表示」「上下に並べて表示」とアクセスキーが動き、Visual Studio で、メニューとダイアログのリソースが、正しく表示された)。

## [2.60.3] 2026-11-10 (文書: v2.60.0〜v2.60.2 の実機の確認の完了を記録した)

- **MFC のメインの構成合わせ (v2.60.0〜v2.60.2) の実機の確認が、SDI・MDI・ダイアログの 3 種類とも、完了した** (TEST-PLAN 2-36 の WZ1〜WZ4)。ダイアログは、v2.60.2 の配布後に、新しいフォルダ (`mfcwDlg3`) で、手直しなしで、タイトルバーのアイコンと、ほかの動作が、すべて OK だった。
- 動作は変えていない (記録だけ)。

## [2.60.2] 2026-11-09 (不具合修正: `--type mfc-dialog` のアプリに、アプリのアイコンが付かない)

- **ダイアログベースのアプリに、`res\<名前>.ico` のアイコンが付かない不具合を直した。** v2.60.0 の実機の確認 (`mfcwDlg`) で見つかった。アイコンは、`.rc` に `IDR_MAINFRAME ICON` として入っていたが、**`CDialog` は、アイコンを、自動では読み込まない**ので、タイトルバーにも、タスクバーにも、出なかった (ウィザードのダイアログベースのアプリは、`OnInitDialog` で、`SetIcon` している)。生成する `CSampleDlg::OnInitDialog` に、`LoadIcon(IDR_MAINFRAME)` と、大・小の両方の `SetIcon` を足した。SDI と MDI は、`IDR_MAINFRAME` を、フレームが自動で読み込むので、変えていない (実機で、アイコンが付くことを確認済み)。
- **切り分けと確認 (実機):** タスクバーには、`SetIcon` なしでも、exe に埋め込んだアイコンが出る。出なかったのは、**タイトルバーの左端だけ**。`MfcwDlg2` (v2.60.1 で作成) の `OnInitDialog` に、同じ 3 行を手で足して、Visual Studio でビルドし、タイトルバーに、アイコンが表示されることを確認した。
- テスト: `tests/mfc_wizard_layout_test.sh` に 1 件。
- **配布が要る** (`new-solution`)。作成済みのダイアログのソリューションは、`OnInitDialog` に、同じ 3 行を、手で足す。
- 実機の確認 (TEST-PLAN 2-36): v2.60.0 の SDI・MDI・ダイアログは、ビルド・起動・見え方まで、確認した。MDI は 2 件、ダイアログは 1 件の不具合を、実機で見つけて、v2.60.1・v2.60.2 で直した。

## [2.60.1] 2026-11-09 (不具合修正: `--type mfc-mdi` のアプリが、起動時に ASSERT で止まる。「ファイル」→「新規」が、押せない)

- **`--type mfc-mdi` のアプリが、起動した直後に、`Debug Assertion Failed! ... winmdi.cpp, Line: 128` で止まる不具合を直した。** v2.60.0 の実機の確認 (`mfcwMdi`) で見つかった。ビルドと `mfc-check` は通っていた。**MDI は、これまで、実機で起動したことがなかった** (ビルドだけ確認していた)。つまり、v2.60.0 で入った不具合ではなく、**以前の版から、あった不具合**。
- **原因:** MFC の `CMDIFrameWnd::OnCreateClient` (既定の実装) は、メニューバーの「右から 2 番目」を Window メニューと推測する (`winmdi.cpp` 128 行目の `ASSERT(iMenu >= 0)`)。生成していた `IDR_MAINFRAME` のメニューは `File` だけなので、`iMenu` が -1 になり、`ASSERT` で止まる。
- **直し方:** 生成する `MainFrame` (MDI) が、`OnCreateClient` を上書きし、`CreateClient(lpcs, nullptr)` で、Window メニューを指定せずに、MDI のクライアント領域を作る。子ウィンドウが開いたあとの Window メニューは、`IDR_SAMPLETYPE` のメニューから、MFC が見つける。SDI とダイアログは、変えていない。
- **「ファイル」→「新規」が、押せない (disable) 不具合も直した** (同じ実機の確認で見つかった)。`CWinApp` のメッセージマップは、`ID_APP_EXIT` などだけで、**`ID_FILE_NEW` を割り当てない** (MFC の `appcore.cpp` で確認)。ウィザードのアプリは、アプリのクラスで割り当てている。生成する MDI の `CSampleApp` に、`DECLARE_MESSAGE_MAP` と `ON_COMMAND(ID_FILE_NEW, &CWinApp::OnFileNew)` を足した。起動時の最初の子ウィンドウは、`ProcessShellCommand` が `OnFileNew` を直接呼ぶので、割り当てがなくても、開いていた。「閉じる」は `CDocument`、「ウィンドウ」のコマンドは `CMDIFrameWnd` が持つので、直す必要はない。
- テスト: `tests/mfc_wizard_layout_test.sh` に 3 件 (MDI が `OnCreateClient` を上書きする / MDI が `ID_FILE_NEW` を割り当てる / SDI は `OnCreateClient` を上書きしない)。**実機で、起動して、子ウィンドウを開けることの確認は、未実施。**
- **配布が要る** (`new-solution`)。作成済みの MDI のソリューションは、`MainFrame` と `SampleApp` を、手で直す (上のとおり)。

## [2.60.0] 2026-11-09 (MFC のメイン (`mfc` / `mfc-mdi` / `mfc-dialog`) の構成を、Visual Studio のウィザードに合わせた)

- **メインの構成をウィザードに合わせた** (`docs/DESIGN.md` 4.81)。参照は、ウィザードで作った `MFCSDISample` と `MFCFirstApp`。
  - **補助ファイルと PCH:** `framework.h`・`targetver.h`・`pch.h`・`pch.cpp` を作り、PCH を `Use` / `Create` にした。Common Controls 6.0 の指令は、ウィザードと同じく `framework.h` に移した (`pch.h` は `framework.h` を読むだけ)。
  - **`res\` フォルダ:** `res\<名前>.rc2`、アプリのアイコン `res\<名前>.ico`、SDI・MDI は文書のアイコン `res\<名前>Doc.ico` (16x16 の置き場所。あとで差し替える)。`.rc` が、アイコンと rc2 を読む。
  - **`.vcxproj` の設定:** `Keyword` を `MFCProj` に。`Midl`、`ResourceCompile` (`Culture` 0x0411、`$(IntDir)`)、`LinkIncremental`、`EnableSegmentHeap`、Release の `WholeProgramOptimization`、`ExtensionTargets` を足した。
  - **フィルター:** `res\` の `.ico` は `Image`、`.rc2` は `None` で、「リソース ファイル」の下に出す (フィルターの 3 つの構成は、もともと同じ)。
  - **残したもの:** `OutDir` / `IntDir` (ウォッチャーが探す場所)、`stdcpp20`、`EnableDpiAwareness`。
  - **合わせないもの (利用者の決定):** ファイル名・クラス名 (`SampleApp` などのまま)、ドッキングウィンドウ。**Win32 の構成と、層・テスト・画面ホストの `.vcxproj` は、v2.61.0 で行う** (x64 のみ)。MDI とダイアログは、SDI の規則から推定した。
- `tests/mfc_wizard_layout_test.sh` を新設 (3 種類 x 2 項目 + 層・テスト付き 3 項目)。`tests/ui_guideline_check_test.sh` は、Common Controls の指令を `framework.h` で確かめるように直した。
- **配布が要る** (`new-solution`、`cpp-test-first` の `add_layer.py`)。実機の確認 (3 種類を作って、ビルドして、起動して見る) は、未実施。

## [2.59.8] 2026-11-08 (文書: MX の `AFX_EXT_CLASS` の確認の記録)

- **MFC 拡張 DLL の生成 (v2.45.0) の `AFX_EXT_CLASS` を、実機で確認した** (`dllchk`。TEST-PLAN 2-25 の MX4、REMAINING-CHECKS)。`ExtLayer` に `class AFX_EXT_CLASS ExtGreeting : public CObject` (`CString`、`DECLARE_DYNAMIC`) を足し、別の exe (`ExtLayerTest`) から、ビルド・リンク・実行できた (`PASSED`、3 件。`mfc-check` は error 0 / warning 0)。**`AFX_EXT_CLASS` を外すと、`ExtLayerTest` のリンクで LNK2019 / LNK2001 になる** (`GetThisClass`・`GetRuntimeClass`・`Make`)。`ExtLayerApi.h` の注意書きは、正しい。
- **発見 (候補として記録):** 公開ヘッダーが `<afxwin.h>` を include していないと、プリコンパイル済みヘッダーのないテスト exe で、`BUILD_FAILED` になる。`ExtLayerApi.h` の注意書きに足す候補 (未着手。NEXT-STEPS)。
- `docs/NEXT-STEPS.md` を更新した (DC4 の実行時と MX の `AFX_EXT_CLASS` は、済み。残る任意の確認を整理)。
- 動作は変えていない (文書と記録だけ)。

## [2.59.7] 2026-11-08 (文書: DLL008 の「テスト exe も、同じ」の誤りを直した。DC4 の実行時の確認の記録)

- **`mfc-check` の SKILL の DLL008 の行を、実装に合わせて直した。** 以前は、「テスト exe も、同じ」と書いていたが、`mfc_check.py` の `check_mfc_dlls` は、名前が `Test` / `Tests` で終わるプロジェクトを、DLL の検査ごと、読み飛ばす。実機 (`dllchk`) で、`UseOfMfc` を `false` にした `ExtLayerTest` に、指摘が出ないことで、食い違いが分かった。「テストは、検査しない」と明記し、「実行時に壊れる」は、**MFC の状態 (`CString`・ダイアログ・リソースなど) を使う関数を呼ぶとき**の話だと、書き足した。
- **DC4 の実行時の確認が済んだ** (TEST-PLAN 2-28、REMAINING-CHECKS): (1) MFC のメインの `UseOfMfc` を外すと、`mfc-check` が DLL008 を出し、**ビルドが `C1189` で止まる**。(2) MFC なしのテスト exe (`ExtLayerTest`) は、`UseOfMfc` が `false` でも、MFC の状態を使わない関数だけを呼ぶなら、**ビルドも実行も通る**。MFC の状態を使う関数を呼んだときの実行時の挙動は、未確認。
- テスト: `tests/mfc_check_test.sh` に 2 件 (99 件)。名前が `Test` で終わる、`UseOfMfc=false` のプロジェクトに、DLL008 が出ないことと、SKILL の記述。
- 動作は変えていない (検査の動きは、そのまま。文書と記録だけ)。

## [2.59.6] 2026-11-08 (文書: SD の静的な確認の記録、NEXT-STEPS の訂正)

- **MFC 標準 DLL の生成 (v2.46.0) の `AFX_MANAGE_STATE` を、静的に確認した** (一時フォルダに生成して、ソースを読んだ)。エクスポート関数の最初の文が `AFX_MANAGE_STATE(AfxGetStaticModuleState());`、`CWinApp` 派生と `theApp`、`UseOfMfc` = `Dynamic`、`_USRDLL`、利用側への注意 (`LogicLayerApi.h`)。TEST-PLAN 2-26 の SD4 と、REMAINING-CHECKS の SD の行に記録した。実行時の確認と、Visual Studio の目視は、未実施のまま。
- **`docs/NEXT-STEPS.md` の誤りを直した。** 「任意の確認」に、すでに完了した WS1〜WS4・CS1・CS2・SK2・SK3 と、確認しないと決めた SK1 を、含めていた。実際に残る任意の確認 (DC4 の実行時、MX の `AFX_EXT_CLASS`、SD の実行時、Visual Studio での目視) に、書き直した。
- 動作は変えていない。

## [2.59.5] 2026-11-08 (文書: `docs/NEXT-STEPS.md` を、今の状態に書き換えた)

- **`docs/NEXT-STEPS.md` を書き換えた** (2026-10-31 の内容は、完了した作業が、残っているように読めた)。冒頭に、**必須の残りは、ない**と書き、次の 3 つに分けた: (1) 任意の確認 (REMAINING-CHECKS の 2-2・2-3、確認用フォルダの後片付け)、(2) 判断待ち・任意の機能 (A: 既存コードからの仕様の逆生成、UI ガイドラインの残り)、(3) 完了したものの要約 (v2.4.x〜v2.59.x、spec v1.0.0〜v1.7.2)。運用メモ (コミット・push・マージ、配置、新しいセッションでの確認、配布先を直接編集しない) を更新した。
- README の「7. 文書」の `NEXT-STEPS.md` の説明を直した。
- 動作は変えていない。

## [2.59.4] 2026-11-08 (文書: README の「2-1」「2-2」「3-1」「3-2」「4」を、「2-6」「2-7」と同じ書き方にそろえた)

- **README の書き方をそろえた。** 「太字の名前の箇条書き + 文章の説明 + サブ項目」(表は使わない) の形に。
  - 「2-1 早見」: 表を、「太字の名前 (起動の種類): ひとこと」の箇条書きに。
  - 「2-2 起動のしかた」: 各項目を、「太字の名前: 文 + サブ項目」に。
  - 「3-1 規約」: 表と、`paths` の別の箇条書きが、同じ内容を二重に書いていたので、規約ごとに 1 つの項目にまとめた。
  - 「3-2 ひな形」「4 ホスト側ツール」: 太字の名前の箇条書きに。冒頭に、1 文の説明を足した。
- 事実 (ファイル名、大きさ、引数、環境変数、既定値、注意) は、変えていない。動作も、変えていない。

## [2.59.3] 2026-11-08 (文書・SKILL: 「移す」の注意、REMAINING-CHECKS の見出し)

- **`/add-project` の切り出し:** 「編集のあるファイルを、新しい層へ移す」を選んだあと、層の側に生成されたサンプルのテスト (`MainViewModelTests` など) が、**失敗することがある** (編集した ViewModel が、サンプルの動きと違うため)。**テストを、黙って直さず、弱めず**、どのテストが、なぜ失敗したかを伝えて、直し方 (移した ViewModel の仕様に合わせて書き換える / 移すのをやめる) を確認する、と明記した。実機の確認 (CUT-B) で気づいた点の、積み残し。
- `docs/REMAINING-CHECKS.md` の見出しを、「2026-11-02 時点」から、「2026-11-02 に作成。以降は、随時更新。最新は、TEST-PLAN と CHANGELOG を優先」に直した (中身は、その後も更新してきたため)。
- テスト: `tests/add_project_skill_test.sh` に 1 件。

## [2.59.2] 2026-11-07 (文書: プロジェクトの `.claude/skills` への配布の、実機の確認 PL1・PL2)

- **v2.58.0 の実機の確認が済んだ** (TEST-PLAN 2-35)。プロジェクトだけに Skill があるときは、プロジェクトの `.claude/skills` のものが使われ、`new-solution` → `csharp-test-first` / `build-test-loop` の通しが動く (`PASSED`)。**ホームとプロジェクトの両方にあるときは、ホームが優先される。**
- README の「5-2」を、「どちらが使われるかは、Claude Code の規則による」から、確かめた規則 (ホームが優先。チームで共有するとき、メンバーのホームの古い Skill が優先される注意) に書き換えた。
- 動作は変えていない (文書と記録だけ)。

## [2.59.1] 2026-11-07 (文書: Prism の表現を、手で直した README にそろえた)

- ユーザーが `README.md` の `/new-solution` の項目 (WPF の MVVM の基底) を、手で直した。**直したあとの表現:** 「**Prism は、使うのは自由だが、推奨しない** (商用利用の有償化と、ライブラリの更新の停滞のため)」(以前は、「積極的には採用しないが、使うのは自由」と、「更新が遅く、有償のライセンスが求められる場合がある」)。
- 手で直した文に、**言葉の抜けがあった** (「使うのは自由推奨しない」と、つながっていた。「推奨しない」が、括弧の中にも重なっていた) ため、整えた。
- **ほかの場所も、同じ表現にそろえた:** `rules/wpf-csharp.md`、`skills/new-solution/SKILL.md`、生成する `CLAUDE.md` (`new_solution.py`)、`docs/DESIGN.md` 4.80 (見出しと、理由の記録。利用者の判断を、そのまま記録し、私は確認していない、と明記)、テスト (`new_solution_wpf_test.sh`、`wpf_check_test.sh` のコメント)。
- **README の構造の誤りを直した:** v2.59.0 で、私が、`--tests` と `--ui-tests` の間 (引数の 4 スペースのリストの途中) に、2 スペースのインデントの項目を入れていたため、`--ui-tests` 以降の引数が、その項目の下に入っていた。**引数のリストの後ろ (「すでにソリューションがあるフォルダでは」の前) に、移した。**
- 配布が要る (`--skills-only` と `--rules-only`。規約・SKILL・生成する `CLAUDE.md` の文言が変わったため)。

## [2.59.0] 2026-11-07 (WPF の MVVM の基底の明示。推奨は CommunityToolkit.Mvvm、Prism は積極的には採用しない)

- **MVVM の基底が、利用者に明示されていなかった** (自前の最小実装と、決まっていたが、`SKILL.md`・規約・DESIGN だけ) ため、**`/new-solution --dry-run` の出力に、「MVVM の基底」の行を足し**、README の `/new-solution`、生成する `CLAUDE.md`、`SKILL.md` の表にも書いた。
- **推奨のライブラリは、`CommunityToolkit.Mvvm`** (生成は、これまでどおり、自前の最小実装。`add-package` で、あとから、置き換える。ほかのライブラリを使うのは、自由)。**Prism は、積極的には採用しないが、使うのは自由** (利用者の判断: ライブラリの更新が遅く、有償のライセンスが求められる場合があるため)。規約 (`rules/wpf-csharp.md`) にも、その方針を書いた。
- **`wpf-check`:** `add-package` で Prism が入っても、引っかからない程度の、直しだけ。**DI コンテナへの登録を書いたファイル** (`IContainerRegistry` / `IServiceCollection` / `RegisterTypes` / `ConfigureServices` / `PrismApplication` など) は、**`DI001` の誤検出を、出さない** (名前に `ViewModel` を含むファイルでも)。`rules/csharp-common.md` の 11 に、「コンテナは、組み立てる場所だけで使う」。
- (一度、実装した `DI002` (サービスロケーターの検査) と、規約の Prism のレシピは、「積極的には採用しない」という方針に合わせて、削除した。)
- テスト: `tests/wpf_check_test.sh` に 2 件 (80 件。Prism 型が指摘 0 件、`ViewModel*.cs` の登録ファイルは `DI001` の対象外)。登録ファイルの対象外を外すと失敗することを確認 (変異テスト)。`tests/new_solution_wpf_test.sh` に 4 件 (65 件。`--dry-run` の「MVVM の基底」と Prism を載せないこと、WinForms にはないこと、生成する `CLAUDE.md`、規約の記述)。
- 契約の変更なし。ホスト側の変更なし。**配布が要る** (`--skills-only` と `--rules-only`)。DESIGN 4.80。

## [2.58.3] 2026-11-07 (文書: README の「2-3」「2-4」「2-5」「2-8」を、「2-6」「2-7」と同じ書き方にそろえた)

- 「2-6」「2-7」は、**太字の名前の箇条書きに、説明を文章で書き、サブ項目 (頼み方、結果、スクリプトなど) を付ける**書き方だった。「2-3」(`/new-solution`、`/new-solutions`、`/add-project`)、「2-4」(`claude-spec-workflow` の 3 つのコマンド)、「2-5」(TDD の範囲、`cpp-test-first`、`csharp-test-first`、`/ui-test-first`)、「2-8」(`add-package`) が、小見出し (`####`) + 段落の書き方で、違いが目立っていたため、そろえた。
- 内容の削除はしていない (4 つの節の、`` ` `` で囲んだ語を、書き換えの前後で比べて、抜けがないことを確認した)。
- 追記: 「2-3」の冒頭に、「この 3 つは、スラッシュコマンドだけで起動する」。「2-4」に、`/brainstorm` などの、1 文の説明。「2-5」の `/ui-test-first` に、「スラッシュコマンドだけで起動する」。「2-8」の `add-package` に、頼み方の例。
- 文書だけ。Skill・スクリプト・ホスト側の変更なし (配布は、要らない)。

## [2.58.2] 2026-11-07 (文書: README の「2-6. ビルドとテストの実行」を、「2-7」と同じ書き方で、分かりやすくした)

- **`auto-build` と `build-test-loop` の説明が、短すぎて、違いと、何が返るかが、分かりにくかった** (「ビルドだけ」「失敗の要約は、同じ形」「(Green)」など)ため、書き直した。
- **書き方は、「2-7」(静的検査) と、そろえた:** Skill ごとに、太字の名前の箇条書きに、説明を、**文章**で書き、そのあとに、サブ項目 (頼み方、結果、出力の末尾に付く行、スクリプト) を付ける。表は、使わない。
  - `auto-build`: ビルドだけ。結果は `SUCCESS` / `FAILED`。
  - `build-test-loop`: ビルドとテスト。結果は `PASSED` / `FAILED` / `BUILD_FAILED` / `TEST_TIMEOUT`。出力の末尾に付く行 (`RESULT_INFO`、`NOTE`、`TEST_GUARD`)。
  - 2 つに共通の、直さず止まる結果 (`ENV_ERROR` / `WATCHER_NOT_RUNNING` / `TIMEOUT`) と、止まる条件 (最大 5 回など)。
  - `references/fix-policy.md`、`test_guard.py`、UI テストの実行。
- 文書だけ。Skill・スクリプト・ホスト側の変更なし (配布は、要らない)。

## [2.58.1] 2026-11-07 (文書: README の TDD の説明)

- README の冒頭の「TDD の流れにも使える」を、**「テスト先行 (TDD) の流れを支える」に直した** (経緯: ビルド・テストの自動修正が、もとの目的で、テスト先行は、あとから足されたため、控えめな書き方が、残っていた。TDD に使えない、という意味ではない)。
- 「2-5」の先頭に、**TDD の範囲**を足した: できること (ロジック層・データ層・ViewModel / Presenter のテスト先行、`test_guard.py`、`audit` と変異の確認)、画面は、対象外 (UI テストを先に書く `/ui-test-first`)、サイクルの粒度 (1 タスクごとに、テスト 3〜8 件をまとめて)、整理は、必要なときだけ、`テスト: なし` のときは、TDD ではない。
- 文書だけ。Skill・スクリプト・ホスト側の変更なし (配布は、要らない)。

## [2.58.0] 2026-11-06 (Skill のパスを、配布先に固定せず、Skill のフォルダを基準にする。プロジェクトのリポジトリへの配布)

- **きっかけ:** 「配布先を、プロジェクトのリポジトリにできないか」。`install.sh` は、配布先を変えられたが、Skill の中のコマンドが、`~/.claude/skills/...` に固定されていた。
- **Skill のコマンドを、`<Skill群>` (= その Skill のフォルダの 1 つ上。Base directory) を基準に書き直した** (`skills/` の `SKILL.md` と `references/`。8 つの `SKILL.md` の冒頭に、「パスの書き方」を追加)。ホームの `~/.claude/skills/` でも、プロジェクトの `.claude/skills/` でも、同じに動く。
- 規約・ひな形・道具への言及を、`~/.claude/rules/...` から `.claude/rules/...` に (`rules/`、`templates/dotnet/.editorconfig` と `add_project.py` の同じ文、生成する `CLAUDE.md` の文)。生成する `CLAUDE.md` の中の Skill のパスは、Skill の名前で書く (`<Skill群>` が使えないため)。
- スクリプト: `solution_state.py` の `SCRIPTS` を、`__file__` から求める。`test_guard_note.sh` が、`test_guard.py` の実際のパスを出す。
- **README:** 配布先の表に「またはプロジェクトの `.claude/`」、「2-2」に `<Skill群>` の説明、「5. 配布」を、「5-1 ホームへ」「5-2 プロジェクトのリポジトリへ (チームで共有)」「5-3 版と警告」に分けた。`docs/USAGE.md` に一言。
- テスト: `tests/skill_paths_test.sh` (新規、8 件)。`convert_utf8_bom_test.sh`・`new_solution_winforms_test.sh` の期待のパスを `.claude/...` に更新。固定のパスを入れ直すと、4 件が失敗することを確認 (変異テスト)。
- 契約の変更なし。ホスト側の変更なし。`claude-spec-workflow` v1.5.0 も、同じ書き方に直した (同じ `skills/` フォルダに配ることが、前提)。DESIGN 4.79。**配布が要る** (`install/install.sh`)。
- **取り下げた案:** `install.sh` が、コピーのときに、パスを置換する (「バイトを変えずにコピー」を、やめる必要があるため)。

## [2.57.1] 2026-11-06 (文書: README.md の整理)

- **README.md を、読みやすく整理し直した (記録の変更。ユーザーの指示。内容の削除はしていない):**
  - 1 行が長い箇条書き (最長 545 → 216 文字、150 文字超の行 32 → 11) を、サブ項目に分けた。
  - 冒頭に、「まず読む」(`docs/USAGE.md`) と、目次を足した。
  - 「1. フォルダの構成」を、表 (フォルダ / 内容 / 配布先) にした。
  - 「2. Skill」に、**13 の Skill の早見表** (Skill / 起動 / ひとこと。短いセルだけ) を足し、各 Skill を、見出し + サブ項目 (用途・引数・スクリプト) にした。`静的検査` の節にあった、静的検査でないもの (`fix-policy.md`、`add_ui_host.py`) を、それぞれ、ビルドとテストの節、`/add-project` の節へ移した。
  - 旧「3. 規約」「4. ひな形」「5. 道具」を、「3. 規約・ひな形・道具」にまとめた (規約は、表)。節の番号を、12 から 10 に減らした。
  - **古かった記述を直した:** 規約の数 (4 → 5)、版の不一致の警告 (v2.56.0 の `HOST_VERSION` に合わせて、「ウォッチャーが、ホスト側が最後に変わった版より古いときだけ」)、`tests/` の一覧 (抜けていた `add_project_skill`・`add_reference`・`add_ui_host`・`usage_guide`・`fix_policy` を足し、分類の表にした)、`/add-project` の流れ (番号つき)、`audit` と `mutation-check.md`。
- テストは変更なし。`usage_guide_test.sh` と `rules_split_test.sh` (README を参照するもの) が通ることを確認した。Skill・スクリプト・ホスト側の変更なし (配布は、要らない)。

## [2.57.0] 2026-11-06 (テストの中身の点検 `test_guard.py audit` と、変異の確認)

- 他チームの運用ドラフトの、「テストが、形だけでなく、不具合を捕まえる中身を持つか」の点検から。
- **`test_guard.py audit <dir>` (新規のモード):** 基準を使わず、空洞なテストを、静的に探す。TQ001 error (アサーションがない。例外を期待するものを除く)、TQ002 error (常に成功する)、TQ003 warning (すべて「等しくない」「null でない」だけ)、TQ004 review (強いアサーションが、すべて、リテラルなしで、呼び出しが 2 つ以上)、TQ011 review (ヘルパーだけ)。`[TestCategory("Preview")]` の目視確認のテストは、対象外。終了コードは、`check` と同じ (error = 1)。
- **`skills/build-test-loop/references/mutation-check.md` (新規):** 形の検査と、**変異の確認** (中心の項目 1〜3 件について、実装をわざと 1 か所壊し、テストが落ちることを確かめる。ユーザーの了承、バックアップ、必ず元に戻す、`cmp`、上限 3 件、中断のときも先に戻す、生き残ったときは、テストの穴として報告)。
- `build-test-loop` / `cpp-test-first` / `csharp-test-first` の SKILL.md: Green のあと、報告の前に、`audit` を実行し、中心の項目は、変異の確認、を案内。確認していないときは、「変異の確認は、していない」と報告する。README に追記。
- テスト: `tests/test_guard_test.sh` に、audit の 13 件 (113 件。健全なテストで誤検出がない、TQ001〜TQ011 を C++ と C# で検出、例外を期待するテストと Preview は対象外、何も書かない、終了コード、文書の整合)。`Preview` の対象外を外すと、2 件が失敗することを確認 (変異テスト)。
- 変異の確認は、**自動化しない** (戻し忘れの危険。DESIGN 4.78)。契約の変更なし。ホスト側の変更なし (Skill とスクリプトの配布でよい)。DESIGN 4.78。

## [2.56.1] 2026-11-06 (文書: 利用ガイド `docs/USAGE.md`)

- 他チームの運用ドラフト (`spec-dev-template` 利用ガイド) との比較から、**使う人向けの案内**を足した。
- **`docs/USAGE.md` (新規):** (1) **どのコマンドを打つか** (判断フロー: ソリューションがあるか → 何をしたいか)。(2) **承認と差し戻しの言い方** (承認は、はっきりした肯定の返事だけ。ほかの質問への答えや、案への修正は、承認にならない。直す点は具体的に。確認の依頼に「進めてよい」を混ぜない。v2.55.1 の SKILL と同じ規則)。(3) **困ったとき** (使うときに迷う点の表。ウォッチャーの細かい症状は、`host-tools/README.md` の「7. トラブルシューティング」へ)。
- `README.md`: 冒頭と、文書の一覧 (9.) から `docs/USAGE.md` へ案内。
- テスト: `tests/usage_guide_test.sh` (10 件。USAGE.md が、すべての Skill に触れている、スラッシュ専用の Skill が載っている、3 つの節、承認の規則、README の導線、形式)。Skill の名前を消すと失敗することを確認。
- Skill・スクリプト・ホスト側の変更なし (配布は、要らない)。

## [2.56.0] 2026-11-05 (版の不一致の警告を、ホスト側が古いときだけにする。`HOST_VERSION`)

- **きっかけ:** Skill だけを配布すると、ホスト側のファイルが変わっていなくても、ウォッチャーの版が Skill の版より古いので、「版の不一致」の警告 (NOTE) が、毎回、出た。
- **追加:** `host-tools/HOST_VERSION` (1 行。ホスト側を最後に変えたときの版。いま 2.51.2)。`install.sh` が、各 Skill に `HOST_VERSION` を置く (リポジトリには置かない)。`skills/build-test-loop/scripts/harness_note.sh`: ウォッチャーの版が `HOST_VERSION` より**古いときだけ**、警告を出す (「ホスト側は、<版> 以上が必要」)。`HOST_VERSION` がない配布は、これまでと同じ (Skill の版と比べる)。
- **ホスト側を変えたら、`HOST_VERSION` をその版に上げる** (`host-tools/README.md` に追記)。
- テスト: `tests/harness_note_test.sh` に 6 件 (30 件。版の形式、各 Skill への配置、等しい・新しいときは警告なし、古いときは警告、`HOST_VERSION` なしの配布は従来どおり)。`harness_note.sh` の直しを外すと 3 件が失敗することを確認 (変異テスト)。
- 契約の変更なし (警告だけ。終了コードは 0 のまま)。ホスト側の変更なし (ウォッチャーの再配布は要らない)。DESIGN 4.77。

## [2.55.1] 2026-11-05 (`/add-project` の SKILL: 承認の取り違え、一部だけ同一の切り出し、質問のツールの失敗。実機の確認 CUT-A・CUT-B で発見)

- **`skills/add-project/SKILL.md`:** (1) **承認は、はっきりした肯定の返事だけ。** 案への質問・修正や、ほかの質問への答え (例: 「参照する層: LogicLayer」) は、承認ではない。案を直して、もう一度、承認を求める (別の質問への答えを承認として、削除まで進めた)。(2) **切り出しで、同一でないファイルが 1 つでもあれば、どのファイルも削除せず**、止まって聞く (一部だけ削除しない)。選択肢は、層へ移す / 名前を変える / 残して中止する。**利用者の編集を捨てて上書きする選択肢は、出さない。** (3) 質問のツールが失敗したときも、既定の名前で黙って進まず、チャットで名前を聞く。(4) ViewModel の層を作ったとき、`CLAUDE.md` の「アプリの構成」の行と「ViewModel 層を作っていない」の行も直す。
- テスト: `tests/add_project_skill_test.sh` に 4 件 (60 件)。記述を外すと失敗することを確認 (変異テスト)。
- 実機の確認 CUT-A ✔・CUT-B ✔ (中心) を、`TEST-PLAN` 2-31 に記録 (別のブランチ)。
- 契約の変更なし。スクリプトの変更なし。ホスト側の変更なし (Skill の配布でよい)。DESIGN 4.76。

## [2.55.0] 2026-11-05 (`/add-project`: 切り出し、「その他」の層の使う側、質問の順。実機の確認 AP4・AR4 で発見)

- **`skills/add-project/SKILL.md`:** (1) **切り出し** (アプリの中に、新しい層と同じ名前のフォルダがあるとき。例: WPF の `ViewModels/`): 名前空間の衝突を検出し、削除するファイルと書き換えるファイルを、範囲外の変更として案に書く。削除の前に、`diff` で同一かを確かめ、同一でなければ、削除せず止まる。手順 3 の「変わるのは…だけ」の例外に追加。(2) 「その他」の層の使う側の既定は、メイン。(3) 層を足すときの質問の順 (名前 → 役割 → 種類 → `--uses` → テスト → 使う側)。名前を聞かずに既定の名前で案を出さない。(4) 「追加した層」の行の名前は、`` ` `` で囲まない。
- **`skills/add-project/scripts/solution_state.py`:** 役割が `other` の層も、参照されていなければ、`SUGGEST_REF` (メイン -> その層) を出す。「追加した層」の行の検出が、名前を `` ` `` で囲んだ行にも効く。
- テスト: `tests/add_project_skill_test.sh` に 7 件 (56 件。`other` の層の `SUGGEST_REF`・参照後に消える、`` ` `` で囲んだ行の検出、SKILL の記述 4 件)。`solution_state.py` の直しを外すと 2 件が失敗することを確認 (変異テスト)。
- `tests/add_reference_test.sh` の 1 件の期待を更新 (役割が `other` の `ReportLib` は、足す前に、`SUGGEST_REF: Wpf -> ReportLib` を出す。これまでは出なかった)。
- 実機の確認 AP4 (`ViewModels` の層、切り出し)・AR4 (`ReportLib` の参照、.NET) ✔ を、`TEST-PLAN` 2-31・2-32 に記録 (別のブランチ)。
- 契約の変更なし。ホスト側の変更なし (Skill の配布でよい)。DESIGN 4.75。

## [2.54.0] 2026-11-05 (`- 層:` の「役割:名前」で、名前に役割の語がない層の役割を決める。実機の確認 AR3 で発見)

- **不具合:** 層のないソリューションに、ロジックとして `ExtLayer` を足すと、`CLAUDE.md` の `- 層:` は `なし` のまま、`solution_state.py` の役割は `other` になった (名前の語からしか判定せず、手順 6 が「その他」の層を `- 層:` に書かないため、選んだ役割が残らなかった)。`add_reference.py` の向きの検査と `mfc-check` の層の検査が、効かなかった。
- **修正:** `solution_state.py`: `- 層:` の `data|logic|viewmodel|ui` の `役割:名前` を、名前の判定より優先する (`explicit_roles`)。`add_reference.py` も、同じ関数を通す。`mfc_check.py`: `CLAUDE.md` の同じ行を読み、`--logic` / `--data` / `--ui` と同じ働きにする (`claude_layer_roles`)。`skills/add-project/SKILL.md` の手順 6: 名前に役割の語がない層も、選ばれた役割で `logic:ExtLayer` の形で書く。行が `なし` なら、置き換える。`skills/mfc-check/SKILL.md` に、自動で読むことを追記。
- テスト: `tests/add_project_skill_test.sh` に 5 件 (49 件。名前に語のない層は `other`、明示すると `logic`、向きの検査が従う、`mfc_check.py` が読む、SKILL の記述)。修正を外すと 3 件が失敗することを確認 (変異テスト)。
- 契約の変更なし (`CLAUDE.md` の `役割:名前` の形は、`new_solution.py` が、すでに使う)。ホスト側の変更なし (Skill の配布でよい)。DESIGN 4.74。

## [2.53.4] 2026-11-05 (修正: `ViewModel` を含む名前を、画面を持つ層としない。実機の確認 AR5 で発見)

- **不具合:** `mfc_check.py` と `add_ui_host.py` は、名前に `View` を含む層 (例: `ReportViewModel`) を、画面を持つ層 (UI DLL) とした。`solution_state.py` は `viewmodel` を先に判定して ViewModel の役割とする。そのため、`ViewModel` を含む名前の C++ の層は、`mfc-check` の LAY001 (ライブラリへの GUI の混入) の検査から外れていた。
- **修正:** `mfc_check.py` の `is_ui_name` と、`add_ui_host.py` の名前の NOTE の判定で、名前に `viewmodel` を含むものは、画面の層としない (`solution_state.py` と同じ規則)。
- テスト: `tests/mfc_check_test.sh` に 1 件 (97 件)、`tests/add_ui_host_test.sh` に 1 件 (36 件)。修正を外すと失敗することを確認 (変異テスト)。
- 契約の変更なし。ホスト側の変更なし (Skill のスクリプトだけの配布でよい)。DESIGN 4.73。

## [2.53.3] 2026-11-05 (`/add-project` の SKILL: 質問と `ui-host` の書き方。実機の確認 AP5・AR5 ✔)

- 実機の確認 AP5 (データ層が `--uses LogicLayer`)・AR5 (ロジック層への逆向きの参照) は ✔。向きの違反を案の前に指摘して止まり、何も書かない。`add_reference.py` も `rc=2` で断る。
- **`skills/add-project/SKILL.md`:** (1) 質問のツールは、選択肢が 2 つ以上のときだけ使う。自由入力は、チャットの文章で聞く (質問のツールの失敗が 3 回)。(2) C++ の層の役割の選択肢は、データ / ロジック / 画面 (UI) / その他。画面 (UI) は `ui-host` の流れへ。ViewModel の役割は .NET だけ。(3) 「やめる」と「進める」を、1 つの選択肢に混ぜない。(4) 手順 3 の「変わるのは…だけ」に、`ui-host` の例外 (ロジック層の `Greeting.h/.cpp` と、そのテストの `TestGreeting.cpp`、その `.vcxproj` / `.filters`) を追加。
- 契約の変更なし。ホスト側の変更なし (Skill だけの配布でよい)。

## [2.53.2] 2026-11-05 (`/add-project`: 選択肢が 1 つのときの質問)

- 実機の確認 AP2・AP3b で、`/add-project` が、選択肢が 1 つだけの質問 (例: テストを後付けできる層が `DataLayer3` だけ) を、質問のツールで出して、`Invalid tool parameters` で失敗した (そのあと、案の提示に進めたので、支障はなかった)。
- **修正 (`skills/add-project/SKILL.md` の手順 2):** 選択肢が 1 つしかないときは、質問のツールを呼ばず、その 1 つで進める案を、手順 3 の案の中で示して、承認を得る。
- 実機の確認 AP3b ✔ (v2.53.1 の修正が効いた。`TEST-PLAN` 2-31)。
- 契約の変更なし。ホスト側の変更なし (Skill だけの配布でよい)。

## [2.53.1] 2026-11-05 (修正: テストを後付けしたとき、`CLAUDE.md` の「追加した層」の行の「テストなし」が残る)

- **不具合 (実機の確認 AP3 で発見):** 層を足したとき、層の表がない `CLAUDE.md` には、「- 追加した層: DataLayer2 (dll)。データ役割。テストなし。…」の行を足す。のちに `/add-project tests` でテストを後付けしても、この行は「テストなし」のまま残った (手順 6 は、`- テスト:` の行しか直さず、`solution_state.py` も、この行の中身を検出できなかった)。
- **修正 (`skills/add-project/SKILL.md` の手順 6):** 「追加した層」の行 (層の表があれば、その行の「テスト」の列) に、**テストの有無を必ず書く**。**テストを後付けしたときは、その層の行の「テストなし」を、`テストあり (<名前>Test)` に直す。**
- **検出 (`skills/add-project/scripts/solution_state.py`):** 「- 追加した層: <名前> ...」の行が「テストなし」なのに、その層にテストがある (または逆) とき、`MISMATCH` を出す。存在しない層の行は、無視する。実物 (`CSharpTF/mfcdlg`) に実行して、`DataLayer2` の古い行が検出されることを確認した。
- テスト: `tests/add_project_skill_test.sh` に 5 件 (テストのない層は食い違いでない、後付け後の「テストなし」は `MISMATCH`、直すと消える、存在しない層の行は無視、SKILL.md の記述) を追加 (40 件)。変異テスト (検出を外す) で、失敗することを確認。
- 契約 (ミューテックス名・フラグ・結果ファイル・終了コード) の変更なし。ホスト側の変更なし (Skill だけの配布でよい)。

## [2.53.0] 2026-11-04 (機能追加: 使う側から新しい層への参照の追加 `add_reference.py`。`/add-project` の第 2 段)

- **`skills/add-project/scripts/add_reference.py` (新規):** `--from <使う側> --to <使われる側>` で、使う側のプロジェクトに参照を足す。**C++:** `ProjectReference` (`<Project>{GUID}</Project>` つき) と、全構成のインクルードパス (使われる側と、それが推移的に参照している層。テスト exe と同じ形)。**.NET:** `ProjectReference` を 1 行 (既存の並びの字下げに合わせる。なければ ItemGroup ごと)。`--include-only` (C++ だけ): パスだけ (ヘッダだけを使う層)。`--dry-run`。
- **断る (何も書かない。終了コード 2):** 自分自身、存在しない、言語が違う (C++ と C#)、UI テストのプロジェクト、テストのプロジェクトを参照、**層の向きの違反** (下の層から上の層)、**循環**、**MFC 拡張 DLL を、`UseOfMfc` のない使う側から参照する** (`mfc-check` の DLL008 を、書く前に検査)。すでにある参照は、終了コード 3 (冪等)。
- BOM と改行コードを保ち、対象のプロジェクトファイル 1 つだけを書き換える。
- **`/add-project` の手順 3・5:** 手順 3 の案に、参照の案 (使う側 → 新しい層。規則は `SUGGEST_REF` と同じ: 新しい層の役割のすぐ上の層、なければメイン) を含め、1 回の承認で、手順 5 で `add_reference.py` により足す (「案内だけ」を廃止)。足したあと、`solution_state.py` で `SUGGEST_REF` / `REF_ISSUES` が残らないことを確認する。
- テスト: `tests/add_reference_test.sh` (32 件。生成した C++ / MFC 拡張 DLL / WPF のソリューションで、XML・BOM・CRLF・GUID・全構成のインクルードパス・変わるファイルが 1 つだけ・冪等・各種の断り・`mfc-check` の error 0)。`tests/add_project_skill_test.sh` (35 件) に、SKILL.md の参照の記述を追加。変異テスト (循環の検査を外す、向きの検査を外す) で、失敗することを確認。
- 契約 (ミューテックス名・フラグ・結果ファイル・終了コード) の変更なし。ホスト側の変更なし (Skill だけの配布でよい)。
- **実機は未確認:** コンパイル・リンク・起動 (TEST-PLAN 2-32 の AR1〜AR5)。

## [2.52.0] 2026-11-04 (機能追加: プロジェクトを足す入口 `/add-project`、ソリューションの現状を読む `solution_state.py`)

- **`skills/add-project/SKILL.md` (新規。スラッシュコマンドだけで起動):** すでにあるソリューション (C++ / .NET) に、プロジェクトを足していく流れ。**現状を読む → 何を足すか質問 → 案 (`--dry-run`) を示して承認 (必ず止まる) → 既存のスクリプトで作る → 足りない参照の案内 → `CLAUDE.md` を合わせる → ビルド・テスト・静的検査で確かめる → 報告。** 足せるもの: 層 (C++ は DLL / 静的ライブラリ / MFC 拡張・標準 DLL、.NET は lib / data / logic / viewmodel) とそのテスト、画面を持つ DLL + 画面ホスト (C++)、テストの後付け、UI テストの後付け。作るのは、既存の `add_layer.py` / `add_project.py` / `add_ui_host.py` / `new_solution.py` (プロジェクトファイルの手書きはしない)。
- **`skills/add-project/scripts/solution_state.py` (新規。読み取りだけ):** 種類 (cpp / dotnet / mixed)、メイン、各プロジェクトの種類・役割・テスト・参照、`CLAUDE.md` との食い違い (`MISMATCH`)、層の参照の向きの違反 (`REF_ISSUES`)、参照されていない層と、参照するのが自然な使う側 (`SUGGEST_REF`)、足せるもの (`ADDABLE`、dry-run の例つき) を出す。`ViewModels` を、画面の層と取り違えない。
- **`CLAUDE.md` の更新:** `- 層:`、層の表、`- テスト:` の 3 か所だけ (書いてある層は、消さない)。`add_layer.py` / `add_project.py` が更新しなかった部分。
- **参照 (使う側 → 新しい層):** この版は、**案内だけ** (報告に `SUGGEST_REF`)。生成は、v2.53.0 (`add_reference.py`) の予定。
- `cpp-test-first` の `DLL-LAYOUT.md`、`csharp-test-first` の `PROJECT-LAYOUT.md`、`new-solution` の SKILL.md から、`/add-project` を案内。
- テスト: `tests/add_project_skill_test.sh` (32 件)。生成したソリューション 10 種 (MFC ダイアログ、テストなし、MFC 拡張・標準 DLL、画面ホスト、向きの違反、CLAUDE.md の食い違い、WPF、WinForms、C# クラスライブラリ、エラーの終了コード) で、出力を検証。変異テスト (`ViewModels` の役割の判定順を入れ替える) で、失敗することを確認。
- 契約 (ミューテックス名・フラグ・結果ファイル・終了コード) の変更なし。ホスト側の変更なし (Skill だけの配布でよい)。

## [2.51.2] 2026-11-04 (修正: `TargetPath` の問い合わせに `SolutionDir` を渡す)

- **不具合 (実機の確認 OD2b で発見):** v2.51.1 でも、`OutDir` を変えたテスト (`LogicLayerTest`) は、見つからなかった (`1 passed (DataLayerTest 1)`)。`out\bin\Debug\LogicLayerTest.exe` は、できていた。**原因 (実機の MSBuild の出力で確認):** `.vcxproj` を単体で MSBuild に渡すと、`SolutionDir` が空になり、`OutDir` が `$(SolutionDir)out\bin\...` のプロジェクトの `TargetPath` が、プロジェクトの下の別の場所 (`LogicLayerTest\out\bin\Debug\LogicLayerTest.exe`) を指す。`-p:SolutionDir=<ソリューション>\` を渡すと、exe がある `UiHostCheck\out\bin\Debug\LogicLayerTest.exe` になる。
- **修正 (`host-tools/lib/tests.ps1`):** `MSBuild -getProperty:TargetPath` に、`-p:SolutionDir=<ソリューションフォルダ>\` を渡す。
- 確認: OD2b は不合格 → 修正。OD2c は未実施。

## [2.51.1] 2026-11-04 (修正: 一部のテストだけ `OutDir` を変えたとき、そのテストを黙って飛ばしていた (v2.50.0 の `TargetPath` の探し直し))

- **不具合 (実機の確認 OD2 で発見):** `Find-TestExes` は、既定の出力先 (`<ソリューション>\<プラットフォーム>\<構成>\`) で、テスト exe が 1 つでも見つかると、そこで終わり、`TargetPath` の探し直しを呼ばなかった。`LogicLayerTest` だけ `OutDir` を変え、`DataLayerTest` が既定の場所に残る構成で、`DataLayerTest` の 1 件だけが実行され、**`LogicLayerTest` (3 件) が、黙って飛ばされた (結果は `PASSED`)。**
- **修正 (`host-tools/lib/tests.ps1`):** 既定の出力先で見つかった exe は、そのまま使い、**名前が `Test` / `Tests` で終わる `.vcxproj` のうち、`<プロジェクト名>.exe` が見つからなかったものだけ**、`MSBuild -getProperty:TargetPath` で探す (`Find-TestExesByTargetPath` に、見つかった exe 名を渡す)。結果は、重複なしで合わせる。**全部が既定の出力先に見つかるときは、MSBuild を呼ばない** (OD1 の構成は、v2.50.0 と同じ動作・同じ速さ)。
- 契約 (ミューテックス名・フラグ・結果ファイル・終了コード) の変更なし。ホスト側の変更なので、`install/install.sh` (引数なし) で配り、ウォッチャーを再起動する。
- 確認: OD1 ✔ (2026-11-04)。OD2 は不合格 → 修正。OD2b は未実施。

## [2.51.0] 2026-11-04 (機能追加: 画面の設計の記録 `docs/design/<画面>.md`、案の比較 (任意)。実際に使われている Skill 一式の `/design` の検討による)

- `/ui-test-first` の手順 1: **既存の設計 (`docs/design/<画面>.md`) を、先に読む** (あれば、変更する行だけを示す)。**新規で、構成が定まらないときだけ、2〜3 案を、部品の一覧と文字の配置図で比べる** (任意。画像・外部のツールは使わない)。
- **承認のあとに、設計を `docs/design/<画面>.md` に保存する** (選んだ案、部品、操作と期待、守る規則 ID、選ばなかった案と理由、変更履歴)。承認のゲートは、1 回のまま。
- `ui-design-review` の「画面を作る前」に、設計の記録の置き場所を 1 行追加。
- **取り入れなかったもの:** `/design` という Skill の新設 (Claude Design / frontend-design / Figma は Web 向けで、WinForms / WPF / MFC に合わない。点検は `ui-design-review` が持つ)、design-reviewer。
- 契約 (ファイル名・結果の値・終了コード) の変更なし。`claude-spec-workflow` v1.1.0 の `/add-feature` が、この記録を読む。

## [2.50.0] 2026-11-04 (機能追加: テスト exe を TargetPath で探す (ホスト側)、修正の方針 (`fix-policy.md`)。他部署の引き継ぎ資料 (`CLAUDE_HANDOFF.md`) の検討による。ホスト側と Skill 側。ホスト側は実機で未確認)

- **ホスト側 (`host-tools/lib/tests.ps1`): テスト exe を、MSBuild の `TargetPath` で、探し直す。** 既定の出力先 (`<ソリューション>\<プラットフォーム>\<構成>\`) に、`*Test.exe` が**見つからなかったときだけ**、名前が `Test` / `Tests` で終わる `.vcxproj` ごとに、`MSBuild -getProperty:TargetPath` で、実際の出力先を取る (`OutDir` を変えた既存のプロジェクトのため)。MSBuild は、vswhere で探す (`Get-MSBuildExe`)。`-getProperty` が使えない古い MSBuild や、失敗したときは、空を返す (従来どおり、「見つからない」)。**既定の出力先に見つかったときの動作は、変えない。**
- **`skills/build-test-loop/references/fix-policy.md` を追加 (`auto-build` / `build-test-loop` 共通):**
  1. **修正の前の確認:** 最初の修正の前に、1 回、`git status --short` と `git diff --stat` (読み取りだけ)。自分が編集していないファイルの未コミットの変更は、ユーザーの変更なので触らない。**修正の対象と重なるなら、修正せずに停止して報告する** (質問はしない)。
  2. **ビルドエラー:** 直してよいものと、停止して報告するもの (ツールの不足、パッケージの不足、署名・権限、プロジェクトファイルの大幅な変更、ABI・公開 API への影響、要件が曖昧、同じエラーが 2 回、未コミットの変更との競合)。
  3. **警告の方針:** `ignore` / `report` (既定) / `fix` (依頼で指定)。`fix` でも直してよいのは、安全なものだけ (未使用のローカル変数、明白な型変換、代替が明白な非推奨 API)。ABI・外部ライブラリ・生成コード・意図が不明なものは報告のみ。抑制で通すのは禁止 (従来のルール 8)。
  4. **テスト失敗:** 直してよいものと、停止して報告するもの (仕様が不明、フォーカス・DPI・ロケール・タイムゾーン・OS の状態に依存、フレーク、外部依存、非同期の競合、クラッシュ、修正後も 2 回続けて失敗)。削除・無効化・アサーションを弱めるのは、従来どおり禁止 (`test_guard.py`)。
  5. **完了報告の項目:** 環境・実行・修正・警告・ログ・停止したとき。成功だけなら 1〜2 行のまま。
- `auto-build` の SKILL.md (ループのルール 10、報告) と、`build-test-loop` の SKILL.md (止めどき 6) から、`fix-policy.md` を参照する。
- **検討して、採用しなかったもの (資料 `CLAUDE_HANDOFF.md`):** WSL から `cmd.exe` を直接呼ぶ方式 (サンドボックスが実行できない。ウォッチャー方式のまま)、Python の排除 (このリポジトリの生成・検査は Python)、`devenv.com`、Preview 版の VS (`VC_INCLUDE_PRERELEASE`。必要になったら)、環境変数による設定、ソリューションの順位付け、ZIP。**すでに満たしていたもの:** vswhere による VS の検出、リビルド・クリーン、`build.log` / `errors.log` / `warnings.log`、修正の上限 (5 回)、テストの改変の禁止 (`test_guard.py`)。
- テスト: `host_tools_static_test.sh` (+3 件: フォールバックの位置・内容、`Get-MSBuildExe`)、`fix_policy_test.sh` (12 件)。壊すと失敗することも確認した。DESIGN 4.66、TEST-PLAN 2-30。
- **実機で未確認 (TEST-PLAN 2-30 の OD1・OD2):** `-getProperty:TargetPath` が、実機の MSBuild (VS 18) で、期待どおりの値を返すこと。**Linux では、PowerShell を実行できない (静的テストのみ)。**

## [2.49.0] 2026-11-04 (機能追加: 画面を持つ DLL の、画面ホストと UI テスト (`add_ui_host.py`)。既存の動作・契約の変更なし。Skill の再配置が必要)

- **`cpp-test-first/scripts/add_ui_host.py` を追加:** 既存の C++ のソリューションに、**画面を持つ MFC の DLL (UI DLL)** と、**その画面を開くだけの exe (画面ホスト)** と、UI テスト (FlaUI) を足す。DLL は単体で起動できないので、UI テストは、ホストの exe を起動する (呼び出す exe がない構成や、画面を DLL が提供する構成のため)。
  - **UI DLL:** 標準 DLL (既定。`--kind mfc-std-dll`) か拡張 DLL (`mfc-ext-dll`)。サンプルのダイアログ `GreetingDialog` (名前 → 挨拶 → クリア)、`.rc`、`Resource.h` (ID は 3000 台)。標準 DLL の公開関数 `ShowGreetingDialog(HWND)` は、先頭で `AFX_MANAGE_STATE`。拡張 DLL は `AFX_EXT_CLASS`。**DLL に `.rc` を作るのは、初めて** (これまで、DLL の `.rc` は、作らない方針だった。画面を持つ DLL だけ、作る)。
  - **画面ホスト:** ダイアログが、そのまま、メインウィンドウになる。**標準 DLL のホストは、MFC なしの Win32 exe** (標準 DLL が、どの exe からも使えることの確認)。**拡張 DLL のホストは、MFC の exe (`UseOfMfc=Dynamic`)**。
  - **ViewModel 相当 (ロジック層の `Greeting`):** 画面に依存しない `MakeGreeting` を、ロジック層に足し、ダイアログが呼ぶ。ロジック層のテストに、単体テスト (`TestGreeting.cpp`) も足す。ロジック層は、名前に `Logic` を含む DLL を探す (`--logic` で指定、`none` で足さない)。ロジック層が MFC 標準 DLL のときは、`MakeGreeting` の先頭に `AFX_MANAGE_STATE` を入れる。ロジック層がなければ、ダイアログの中に書く (NOTE)。
  - **UI テスト:** `add_ui_tests.py --app <ホスト>` で `<ホスト>.UITests` を作り、`GreetingDialogUiTests.cs` (開いたとき・名前を入れたとき・クリアしたとき) を足す。部品は、コントロール ID の数値 (`"3002"` など) で探す。`CLAUDE.md` にも、節を足す。
- **`mfc-check`:** **名前に `Ui` / `View` / `Dialog` の語を含む DLL (または `--ui <名前>`) を、「画面を持つ層」として扱う。** ライブラリの GUI の使用 (LAY001 / LAY002) を指摘しない。層の向き (LAY003) は、メイン → 画面を持つ DLL → ロジック → データ (ロジック・データから画面、画面からメインへの参照は、error)。
- **既存の動作は、変えない:** `/new-solution` の層 (ロジック・データ)、`add_layer.py` の出力は、変更なし。
- テスト: `add_ui_host_test.sh` (35 件。標準 DLL・拡張 DLL・ロジックなし・`--logic none`・ロジックが標準 DLL・名前の NOTE・不正な引数・2 回目の rc=3。生成した一式が、`mfc-check` で、error 0 / warning 0)、`mfc_check_test.sh` (+5 件: 画面を持つ層)。生成側と検査を壊すと、テストが失敗することも確認した。DESIGN 4.65、TEST-PLAN 2-29。
- **実機で確認 (2026-11-04、TEST-PLAN 2-29。`UiHostCheck` (標準 DLL)・`UiHostExt` (拡張 DLL)):** 生成 ✔、ビルド `SUCCESS` ✔、単体テスト `PASSED` (4 件。`GreetingTest` を含む) ✔、**UI テスト `PASSED` (3 件。標準 DLL・拡張 DLL の両方)** ✔。ダイアログが DLL のリソースから開き、MFC の静的テキストの UIA の `Name` を読めた。**未確認 (任意):** UH4 (目視)。

## [2.48.0] 2026-11-04 (機能追加: `mfc-check` に、MFC の DLL の設定の検査 (DLL001〜DLL008)。既存の検査の出力・終了コードは変えない。Skill の再配置が必要)

- **`mfc-check` が、MFC の拡張 DLL・標準 DLL の、「コンパイルは通るが、実行時に壊れる」設定の食い違いを検出する** (v2.45.0 / v2.46.0 で、見送っていた件)。`.vcxproj` の `UseOfMfc` と `PreprocessorDefinitions` (構成ごと) と、ソースから判定する。
  - **error:** DLL001 (`_USRDLL` と `_AFXEXT` の併用)、DLL002 (拡張 DLL で `UseOfMfc` が `Dynamic` でない)、DLL005 (拡張 DLL に `AfxInitExtensionModule` がない)、DLL008 (拡張 DLL を参照する exe / DLL の `UseOfMfc` が `Dynamic` でない。MFC なしの exe も)。
  - **warning:** DLL003 (`UseOfMfc` が有効だが `_USRDLL` も `_AFXEXT` もない)、DLL004 (標準 DLL に `CWinApp` 派生・`theApp` がない)、DLL006 (拡張 DLL に `CDynLinkLibrary` / `AfxTermExtensionModule` がない)、DLL007 (**標準 DLL (共有 MFC) の公開関数が、先頭で `AFX_MANAGE_STATE` を呼んでいない**)。
- **既存の誤検出の修正:** MFC の DLL (拡張 DLL・標準 DLL) の層で、`afxwin.h` の include が、LAY002 の warning になっていた (拡張 DLL の `dllmain.cpp`。意図した include)。MFC の DLL では、info にした。
- **誤検出がないことの確認:** 生成した拡張 DLL・標準 DLL (`--layer-kind mfc-ext-dll` / `mfc-std-dll`) と、実物のウィザードの DLL (`MFCLibrary1`・`MFCLibrary2`) が、error 0 / warning 0。
- テスト: `mfc_check_test.sh` (+16 件: 正常な拡張 DLL・標準 DLL (共有/静的)・MFC なしの DLL が、指摘なし。各コードの検出。検査を壊すと、テストが失敗することも確認した)。`SKILL.md` に、表と限界を追記。DESIGN 4.64、TEST-PLAN 2-28。
- **限界:** プロパティシート (`.props`) で定義した `_AFXEXT` などは、読まない。DLL007 は、自由関数だけ (クラスのメンバー関数、`.def` でのエクスポートは、対象外)。

## [2.47.0] 2026-11-04 (規約の分割: C++ の共通と MFC 固有。生成物の `CLAUDE.md` が変わる。`install.sh --rules-only` と Skill の再配置が必要)

- **`rules/mfc-cpp.md` (163 行) を、`rules/cpp-common.md` (C++ の共通) と、`rules/mfc-cpp.md` (MFC 固有) に分けた** (v2.41.0 で「最初の MFC 以外の C++ プロジェクトが来たら」と見送っていた件。`--type win32` / `console` / `dll` / `lib` が、MFC の規約を読み込んでいた)。
  - **`cpp-common.md`:** 言語・ビルド、ファイルの形式、書式、コメント、命名、`override`、`::` を付ける Win32 API の呼び出し、ポインタ、COM (`CComPtr`)、`std::ranges`、テンプレート、関数の大きさ、既存コードの扱い。`paths` は、従来どおり、全部の C++ のファイル。MFC の名前が出る例は、MFC なしの例に直した。
  - **`mfc-cpp.md`:** MFC の動的リンクと `CString`、MFC のクラスの内側での `::` (同名メンバーとの衝突)、MFC が寿命を決めるオブジェクトの扱い、MFC のメンバーへのアクセス (`GetSafeHwnd` など)、MFC のコレクション (`CArchive`、イテレータの推奨)。**`paths` は、MFC のウィザードが作る名前 (`*Dlg` `*View` `*Doc` `MainFrm` `*Frame`) だけに絞った。** 規則の中身は、変えていない (移動と、MFC の名前の例の置き換えのみ)。
- **`/new-solution` が書く `CLAUDE.md` の「規約」の節:** `cpp-common.md` を指す。MFC のメインと、MFC の層 (`mfc-ext-dll` / `mfc-std-dll`) では、「`mfc-cpp.md` も読んでから書く」と指示する (`paths` が、ウィザードのファイル名だけなので、層の `.cpp` では自動で読み込まれないため)。それ以外 (`win32` / `console` / `dll` / `lib`) は、「MFC を使わない」「`mfc-cpp.md` は適用しない」と書く (`win32` は「Win32 API と C++」と明記)。
- **生成されるコードは、変えていない** (`--type win32` は、これまでも MFC なし。`UseOfMfc`・`afx` がないことを、テストで固定した)。
- **注意 (動作の変化):** 既存のプロジェクトの `CLAUDE.md` は、変わらない。MFC のプロジェクトで、ウィザード以外のファイル名の `.cpp` を、MFC の規約なしで編集する場合は、`CLAUDE.md` に、「`~/.claude/rules/mfc-cpp.md` も読む」の 1 行を足すとよい。
- テスト: `rules_split_test.sh` (共通と MFC 固有の分離、`paths`、MFC 固有の規則が共通に混ざらないこと、配布)、`new_solution_test.sh` (+6 件: win32 の MFC なし、`CLAUDE.md` の案内 4 種類)、`convert_utf8_bom_test.sh` (参照先を `cpp-common.md` に)。DESIGN 4.63、TEST-PLAN 2-27。

## [2.46.0] 2026-11-04 (機能追加: MFC 標準 DLL の生成。既定の動作・契約の変更なし。Skill の再配置が必要)

- **`add_layer.py --kind mfc-std-dll` と `new_solution.py --layer-kind mfc-std-dll` (仕様書の「層の種類: mfc-std-dll」も) で、MFC 標準 DLL (Regular DLL。共有 MFC) を生成できるようにした (ユーザーの決定。名前は `mfc-std-dll`、リンク方式は共有 MFC のみ)。**
  - **実物 (`MFCLibrary2`。Visual Studio の「MFC DLL」ウィザードの標準 DLL) を読んで、設定を合わせた:** `UseOfMfc=Dynamic`、`_USRDLL` (`_AFXEXT` なし)、`pch.h` (Use) / `pch.cpp` (Create)、`C<Name>App : public CWinApp` とグローバルな `theApp` (`<Name>.h` / `.cpp`。`dllmain.cpp` は作らない)、`framework.h` / `targetver.h`。全ファイル BOM 付き UTF-8 + CRLF。
  - **エクスポート関数の先頭に `AFX_MANAGE_STATE(AfxGetStaticModuleState());`** (共有 MFC のとき必須。ビルド確認用の関数に入れた。`Api.h` と `CLAUDE.md` にも注意を書く)。MFC のオブジェクトを DLL の境界で受け渡さない注意も書く。
  - **テスト exe は MFC なし** (標準 DLL は、MFC を自分で読み込む。`--tests-only` も同じ)。**メインは何でもよい** (拡張 DLL と違い、MFC なしの exe からも使える。`console` + 標準 DLL の層も作れる)。
  - **ウィザードとの違い (意図的。拡張 DLL と同じ):** `.def`、`.rc` / `.rc2`、`Resource.h`、x86 の構成は作らない。静的リンクは、選べない。
  - 既定 (`--kind dll`) と、拡張 DLL (`--kind mfc-ext-dll`) の出力は、変えていない (テストで確認)。
- `DLL-LAYOUT.md` (「MFC 標準 DLL を作るとき」を追加)、`new-solution/SKILL.md`、README を更新。
- テスト: `add_layer_test.sh` (+12 件: 設定の各項目、`AFX_MANAGE_STATE` が最初の文であること、BOM + CRLF、テスト exe が MFC なし、`--tests-only`、拡張 DLL の不変)、`new_solution_test.sh` (+7 件: 層・テスト・`CLAUDE.md`、`console` + 標準 DLL)。生成側を壊すと、テストが失敗することも確認した。
- **実機で確認 (2026-11-04、TEST-PLAN 2-26、`MfcStdCheck`):** SD1 生成 ✔、SD2 ビルド `SUCCESS` ✔、SD3 `PASSED` (tests: 2 passed)。MFC なしのコンソールのテスト exe が、標準 DLL (共有 MFC) をロードして通った。SD4 は、実物 `MFCLibrary2.vcxproj` との静的比較 ✔ (違いは意図的な `LOGICLAYER_EXPORTS` のみ)。**未確認 (任意):** Visual Studio のプロパティページ、`AFX_MANAGE_STATE` の挙動の確認。

## [2.45.0] 2026-11-04 (機能追加: MFC 拡張 DLL の生成。既定の動作・契約の変更なし。Skill の再配置が必要)

- **`add_layer.py --kind mfc-ext-dll` と `new_solution.py --layer-kind mfc-ext-dll` (仕様書の「層の種類: mfc-ext-dll」も) で、MFC 拡張 DLL を生成できるようにした (ユーザーの決定。名前は `mfc-ext-dll`)。** これまでは、常に MFC を使わない通常の DLL (`_USRDLL`) で、拡張 DLL にするには、`.vcxproj` と定型コードを、毎回、手で直していた。
  - **実物 (`MFCLibrary1`。Visual Studio の「MFC DLL」ウィザードの拡張 DLL) を読んで、設定を合わせた:** `UseOfMfc=Dynamic`、`_AFXEXT` (`_USRDLL` なし)、`pch.h` (Use) / `pch.cpp` (Create) / `dllmain.cpp` (NotUsing)、`dllmain.cpp` の定型コード (`AFX_EXTENSION_MODULE` / `AfxInitExtensionModule` / `CDynLinkLibrary` / `AfxTermExtensionModule`)、`framework.h` / `targetver.h`。全ファイル BOM 付き UTF-8 + CRLF。
  - **テスト exe も `UseOfMfc=Dynamic`** (同じ共有 MFC ランタイム。`_AFXEXT` は付けず、DPI のマニフェストも付けない)。`--tests-only` で後から足すときは、既存の DLL の `_AFXEXT` を見て同じにする。
  - **メインが MFC (`mfc` / `mfc-mdi` / `mfc-dialog`) のときだけ指定できる** (それ以外は、何も書かずに、エラー)。`CLAUDE.md` の「層と依存の向き」に、拡張 DLL の注意 (`AFX_EXT_CLASS`、`pch.h`) を書く。
  - **ウィザードとの違い (意図的):** `.def`、`.rc` / `.rc2`、`Resource.h`、x86 の構成は作らない。`framework.h` は最小限 (OLE・DB・DAO なし)。
  - 既定 (`--kind dll` / `--layer-kind` なし) の出力は、変えていない (テストで確認)。
- `DLL-LAYOUT.md` (「`add_layer.py` に拡張 DLL を生成するオプションがない」の記述を、生成の説明に置き換え)、`new-solution/SKILL.md`、README を更新。
- テスト: `add_layer_test.sh` (+13 件: 設定の各項目、BOM + CRLF、`--tests-only`、既定の不変)、`new_solution_test.sh` (+8 件: 層・テスト・`CLAUDE.md`、MFC 以外の拒否)。生成側を壊すと、テストが失敗することも確認した。
- **実機で確認済み (2026-11-04。TEST-PLAN 2-25 の MX1〜MX3 ✔、MX4 は静的比較 ✔):** `mfc-dialog` + 層 2 つ (拡張 DLL) + テストを生成 → `build_once.sh` = `SUCCESS` → `build_test_once.sh` = `PASSED` (2 件)。`UseOfMfc=Dynamic` のコンソールのテスト exe が、拡張 DLL を読み込めた。生成した `.vcxproj` の設定は、実物 `MFCLibrary1` と一致 (違いは、意図的な `LOGICLAYER_EXPORTS` のみ)。未実施 (任意): Visual Studio のプロパティページでの見比べ、`AFX_EXT_CLASS` クラスの利用。

## [2.44.0] 2026-11-04 (Skill の削除: `/brainstorm`・`/update-from-ideas`・`/add-feature` を、別リポジトリ `claude-spec-workflow` へ移した。ウォッチャーと契約の変更なし)

- **3 つの Skill を、`skills/` から除き、別リポジトリ `claude-spec-workflow` (v1.0.0。ローカル: `~/src/claude-spec-workflow`) へ移した (ユーザーの決定。ビルドツールとは、意味が合わないため)。** 履歴は持ち越さない (移す前の版は、このリポジトリの git の履歴にある)。Skill は 15 個から 12 個になった (スラッシュコマンドだけで起動する Skill は、6 個から 3 個: `/new-solution`・`/new-solutions`・`/ui-test-first`)。
- **このリポジトリに残したもの:** (1) `/new-solution --spec` / `spec_import.py` / `new_solutions.py` が、仕様書 (`docs/specs/*.md`) を読む処理 (仕様書の形式の、読む側)。(2) `/new-solution` が `CLAUDE.md` に書く 3 行 (`claude-spec-workflow` の Skill の入口)。(3) `cpp-test-first` / `csharp-test-first` の、`/add-feature` から呼ばれたときの記述。**新しいリポジトリの `/add-feature` は、このリポジトリの Skill と scripts を、前提にする** (逆向きの依存はない)。
- **配布:** `install.sh` は、もう 3 つを配らない。**配布先 (`~/.claude/skills/`) に、すでにある 3 つは、そのまま使える** (新しいリポジトリの `install/install.sh` が、同じ名前で配る。内容は、v2.43.0 と同じ。`/add-feature` の 1 行だけ、リポジトリ名を足した)。
- **`/add-feature` は、必須ではない (ユーザーの指示)。** `claude-spec-workflow` の `/brainstorm`・`/update-from-ideas` は、`/add-feature` なしで完結し、実装は、通常の依頼 (`cpp-test-first` / `csharp-test-first`) でもよい。`/new-solution` が `CLAUDE.md` に書く 3 行の 3 つ目 (`/add-feature`) にも、「任意」と書いた (`new_solution.py` の 4 か所)。
- README、`new-solution` の `SKILL.md` (3 か所。別リポジトリであることを明記) を直した。テストから、3 つの Skill の文面の確認を除いた (`loop_hardening_test.sh`、`ui_test_first_skill_test.sh`、`ui_guideline_check_test.sh`、`new_solution_winforms_test.sh`、`new_solutions_test.sh`。新しいリポジトリの `tests/skills_test.sh` に移した)。

## [2.43.0] 2026-11-04 (**ホスト側ツールの再配置が必要: `host-tools/lib\` が増えた。** ウォッチャーの動作と契約の変更なし。`watch_and_build.ps1` の整理)

- **`host-tools/watch_and_build.ps1` (1748 行) を、機能ごとの 8 ファイル (`host-tools/lib/*.ps1`) に分けた (ユーザーの決定。動作は変えない。関数の本文は、1 行も変えていない)。** 本体は 558 行 (`param`・パス解決・ソリューションの判定・二重起動の防止・クイック編集の無効化・監視ループ) になった。`lib\` は、本体が、`. $libPath` (ドットソース) で、同じスコープに読み込む。`$script:` の変数は、そのまま共有される。
  - `gtest.ps1` (GoogleTest の取得。117 行)、`package.ps1` (nuget / vcpkg / fetch。306 行)、`common.ps1` (実行 ID・処理中の印・外部プロセスの出力の読み取りなど。73 行)、`build.ps1` (`Invoke-BuildScript`。32 行)、`test-results.ps1` (trx の集計・失敗行・ハングの判定・完了マーカー。108 行)、`ui-settings.ps1` (`uitest.settings` と、デスクトップの解決。86 行)、`uitest-desktop.ps1` (別デスクトップの実行基盤・WPF のソフトウェアレンダリング。215 行)、`tests.ps1` (テストの実行。`Invoke-Tests` ほか。276 行)。
  - **`lib\` のファイルが 1 つでも欠けると、`ERROR: library script not found: ...` (終了コード 2) で起動しない。** `install.sh` は、`host-tools/` を、フォルダごと配る (`lib\` も含む)。手で配るときは、`lib\` ごとコピーする。**ウォッチャーの再起動が要る。**
  - 変えなかったもの: ミューテックス名、フラグ名、結果ファイルの形式、終了コード (2・3)、`build-windows.cmd`、`run_watcher*.cmd`。
- テスト: `host_tools_static_test.sh` (本体 + `lib` をつなげて検査。BOM + CRLF を全ファイルで。`lib` の 8 ファイルと読み込みの確認、本体に機能の関数が残っていないこと。`--host-only` が `lib\*.ps1` の 8 ファイルを配ること)、`harness_note_test.sh` と `loop_hardening_test.sh` (本体 + `lib` をつなげて検査) の対象を広げた。括弧の釣り合いの基準値は、分割の前後で同じ。
- README・`host-tools/README.md`・DESIGN 4.59・TEST-PLAN 2-24 (実機の確認 WS1〜WS4) を更新。

## [2.42.0] 2026-11-03 (**契約の変更: ウォッチャーのミューテックス名。ホスト側ツールの再配置と、ウォッチャーの再起動が必要。** リポジトリ名と、ホスト側の配布先の既定のフォルダ名の変更。スキルと規則の動作の変更なし。疑似フォルダと文字列の確認。**実機の確認は、ウォッチャーの起動と二重起動** (TEST-PLAN 2-23))

- **リポジトリ名を、`cpp-claude-build-tools` から `claude-windows-desktop-tools` に変更する** (ユーザーの決定。C++ 専用ではなくなったため。Windows デスクトップの C++ / MFC / Win32 / WPF / WinForms / C#)。GitHub での名前の変更、手元のフォルダの名前の変更、メモリの更新は、ユーザーの作業 (DESIGN 4.58 の手順)。
- **ウォッチャーのミューテックス名を、`Local\cpp-claude-build-tools-watcher-<hash>` から `Local\claude-windows-desktop-tools-watcher-<hash>` に変えた** (`host-tools/watch_and_build.ps1`。UTF-8 BOM + CRLF を保った)。**新旧のウォッチャーは、同じフォルダで、互いを排他しない。ウォッチャーを、すべて止めてから、再配置して、起動し直す。**
- **ホスト側の配布先の既定を、`/mnt/c/tools/cpp-watcher` (`C:\tools\cpp-watcher\`) から `/mnt/c/tools/claude-watcher` (`C:\tools\claude-watcher\`) に変えた** (`install.sh`)。`cpp` が、C++ 専用に見えるため。`--host-dir` で、配布先を、変えることは、これまでどおり。旧い配布先 (`C:\tools\cpp-watcher\`) は、**ユーザーが、手で削除する** (公開前で、旧名を使う人が、ほかにいないため、`install.sh` は、警告しない)。
- README、`host-tools/README.md`、DESIGN (契約の項とリポジトリ名)、TEST-PLAN の手順の例のパスを、新しい名前に直した。**履歴の記述 (CHANGELOG の過去の版、TEST-PLAN の過去の結果、引き継ぎ文書) の旧名は、書き換えていない。**
- 変えなかったもの: 言語固有の名前 (`cpp-test-first`、`mfc-cpp.md`、`templates/cpp/`、`add_layer.py` など)。
- テスト: `host_tools_static_test.sh` に 3 件 (ミューテックス名、既定の配布先、`--host-only` が 3 つのファイルと VERSION をコピーする)。`rules_split_test.sh` の再発防止の検査に、「`--host-only` で実際に実行するテストは、`--host-dir` を渡す」を足した。`new_solutions_test.sh` の、配置先のパスを固定で書かない検査を、新旧の名前の両方に。
- **旧名の警告を、すべて、削除した (ユーザーの指示。公開前で、旧名を使う人が、ほかにいないため):** `install.sh` の、旧い配布先 `cpp-watcher` (v2.42.0)、旧名の規則 `cpp-mfc.md` (v2.41.0)、旧名の Skill `cpp-auto-build` / `cpp-build-test-loop` / `wpf-test-first` (v2.0.0 / v2.32.0) の、3 つの警告と、環境変数 `OLD_HOST_DIR`、それらのテスト (`rules_split_test.sh`、`host_tools_static_test.sh`)。README の、旧名の併記と、旧名の削除の項も、外した。**手元の環境の旧いものは、手で削除する** (`~/.claude/rules/cpp-mfc.md` は、削除済み。`C:\tools\cpp-watcher\` は、残っている)。

## [2.41.0] 2026-11-03 (規則 (`rules/`) とひな形 (`templates/`) の取り込み。規則の 1 か所の誤りの修正と、改名。スクリプトの動作と契約の変更なし。疑似フォルダと文字列の確認。**実機の確認は、`install.sh` の出力の確認のみ** (TEST-PLAN 2-22))

- **C++ / MFC の規則を、リポジトリに取り込み、`rules/mfc-cpp.md` (19KB) にした。** もとは、`~/.claude/rules/cpp-mfc.md` (2026-10-16 作成。ユーザー個人の規則で、リポジトリの外にあり、`git` の履歴が、なく、`install.sh` も配らなかった)。`paths` は、`**/*.cpp` `**/*.h` `**/*.hpp` `**/*.cc` `**/*.cxx` で、すでに C++ に絞られている。
- **名前を、`wpf-csharp.md` / `winforms-csharp.md` の `<技術>-<言語>` に揃えた** (`cpp-mfc.md` → `mfc-cpp.md`。ユーザーの指示)。命名の方針: 言語の共通 = `<言語>-common.md` (`csharp-common.md`)、技術ごと = `<技術>-<言語>.md` (`wpf-csharp.md` / `winforms-csharp.md` / `mfc-cpp.md`)。
- **規則の誤りを、1 か所、直した (113 行目):** 「MFC のクラスの **`public`** メンバー変数 (`CWnd::m_hWnd`、`CView::m_pDocument`、…)」の `CView::m_pDocument` は、`protected` (Visual Studio 2022 の `afxwin.h`、MSVC 14.44.35207 の 4668〜4669 行目で確認)。「`public` / `protected` メンバー変数」に直し、`m_pDocument` に「(`protected`。派生クラスから触れる)」を添えた。助言 (`GetDocument()` を使う) は、そのまま。**ほかは、内容を変えていない。**
- **イテレータの記述を、「推奨」に直した (「コレクションと反復」。ユーザーの指示):** もとは、「MFC のコレクションの反復には、C++20 の反復子の要件を満たす `begin()` / `end()` (自由関数) を使い、…扱えるようにする」と、必須の書き方で、実装例として、ユーザーの PC の絶対パス (`C:\Workspace\macsignee\...\mfciterators.h`) を挙げていた。「**MFC のコレクションを、イテレータ (範囲 `for`、`std::ranges`) で操作できるようにする、ライブラリ・関数・クラスを使うことを、推奨する (必須ではない。使わなくてもよい)**」に直した。`mfciterators.h` は、「一例」とし、絶対パスを外した (「どれを使うかは、プロジェクトで決める」)。重複していた 2 つ目の記述 (「上記の `begin()` / `end()` があれば…」) は、「イテレータで操作できるコレクションは、`std::ranges` と `views` が、そのまま使える」に直した。
- **C++ のひな形を、取り込んだ:** `templates/cpp/.clang-format` / `.clang-tidy` / `.editorconfig` (`~/.claude/templates/cpp/` の、そのままのコピー。`mfc-cpp.md` の 12 行目と 156 行目が参照している)。批判的に確認し、`mfc-cpp.md` と食い違わないことを確かめた (Allman、インデント 4、`SortIncludes: Never`、`readability-function-size` = 100、CRLF、`charset` を書かない)。`install.sh` が、`~/.claude/templates/cpp/` に配る (配布先の既存のファイルと同じ内容なので、`same`)。
- **旧名の警告:** 配布先に、旧名の `cpp-mfc.md` が残っていると、`mfc-cpp.md` と同じ `paths` で、二重に読み込まれる。`install.sh` が、旧名を見つけたら、警告する (自動では、消さない)。**配布のあと、`rm ~/.claude/rules/cpp-mfc.md` が必要。**
- **変換の道具 `scripts/convert_to_utf8_bom.py` を、取り込み、2 点、直した:** Shift-JIS (CP932) のソースを、UTF-8 (BOM 付き) / CRLF に変換する。`mfc-cpp.md` (29 行目) と `csharp-common.md` (87 行目) が、参照している。セッション履歴に、実行が 15 件あり、実際に使われていた (MFC のプロジェクトのソースの変換など)。もとは、`~/.claude/scripts/` にあり、リポジトリの外だった。`install.sh` が、`~/.claude/scripts/` に配る (`--scripts-dir`。`--rules-only` に含まれる)。**ビルドの流れには、組み込まれていない。手動で、ファイルを指定して、1 回だけ実行する** (規則の「変換だけの、別のコミット」)。
  - **欠陥の修正 (1): BOM なしの UTF-8 を、Shift-JIS と誤認して、文字化けを、無警告で書き込んでいた。** UTF-8 の日本語は、CP932 としても、たまたま読めることが多く、往復の確認も、通ってしまう。実測で、日本語のコメント 16 行のうち、6 行が受理された (「`// 画像を読み込む`」が、「`// 逕ｻ蜒上ｒ隱ｭ縺ｿ霎ｼ繧\x80`」になる)。**UTF-8 として読めて、非 ASCII を含むファイルは、`NG` にして、書かない。** ASCII だけのファイルは、変換する (BOM が付く)。
  - **欠陥の修正 (2): 存在しないファイルを指定すると、`FileNotFoundError` のトレースバックで止まっていた。** `NG` にして、ほかのファイルを、続けて処理する。
  - 変換の部分 (CP932 の読み込み、往復の確認、単独の CR の拒否、CRLF への統一、BOM、末尾の改行) は、変えていない。
- **見送ったもの:** `mfc-cpp.md` の分割 (`cpp-common.md` との分割。最初の非 MFC の C++ プロジェクトを取り込むときに、検討する)。ひな形の修正 (下の気づき)。ソースの文字コードを、ビルドのたびに、検出する仕組み (規則は、「編集の前に、人が、変換する」運用)。C++ の `/new-solution` が、`.clang-format` / `.editorconfig` / `.clang-tidy` を、生成する (WPF は、`.editorconfig` を生成する)。
- **気づき (誤りではない):** ひな形の `.editorconfig` の `[*.{cpp,h,hpp}]` に、規則の `paths` にある `.cc` / `.cxx` が、ない。`.clang-format` の `ColumnLimit: 120` は、規則に書かれていない。`.editorconfig` に `trim_trailing_whitespace` がない (`templates/dotnet` は、`true`)。(規則の 135 行目の、ユーザーの PC の絶対パスは、上の「イテレータの記述」の修正で、外した。)
- **テストの副作用の修正:** `install.sh` が `scripts/` を配るようになったため、`--scripts-dir` を渡さないテスト (`rules_split_test.sh` の 2 か所、`harness_note_test.sh` の 1 か所) が、**実際の `~/.claude/scripts/convert_to_utf8_bom.py` を上書きした** (2026-11-03。旧い版が `.~1~` として残った)。3 か所に `--scripts-dir` (一時フォルダ) を渡すようにした。**再発防止:** `install.sh` を実際に実行する (ドライランでも `--skills-only` でもない) テストが、`--scripts-dir` を渡していないと失敗する検査を、`rules_split_test.sh` に足した。全テストを実行しても、実際の `~/.claude/rules` `scripts` `templates` が変わらないことを、確認した。
- **README.md を、箇条書きで、整理し直した (記録の変更。ユーザーの指示):** 「Skill」の欄が、1 つのセルに、すべての Skill を詰め込んでいて、引数も分からなかったため、**フォルダの構成 / Skill (起動のしかた、種類ごとの用途・引数・スクリプトの引数) / 規約 / ひな形 / 道具 / ホスト側ツール / 配布 / テスト / 文書 / ファイル形式 / 開発の進め方 / 対応範囲** の順に、書き直した。15 の Skill すべてと、規則 4 つ、ひな形 5 ファイル、道具 1 つ、テスト 28 本が、README に載っていることを、確認した。古かった記述を直した: `csharp-test-first` は「WPF のテスト先行」ではなく、WPF / WinForms。`ui-test-first` と `new-solutions` が、一覧になかった。「検証済み: C++ のみ (v1.6.0 まで)、.NET / 混在は未検証」は、現状と合わないため、`docs/REMAINING-CHECKS.md` (実機の確認の状況の正本) への参照に直した。
- テスト: `rules_split_test.sh` に、C++ の規則とひな形の検査 (新しい名前、`paths`、113 行目の修正、配布、旧名の警告、ひな形と規則の整合) と、上の再発防止の検査を足した (計 21 件)。`tests/convert_utf8_bom_test.sh` (新規。10 件。検証だけで書かない、`--apply` の変換、BOM 付きのスキップ、単独の CR、BOM なしの UTF-8 の拒否 (6 例)、存在しないファイル、CP932 として読めないバイト列、配布)。

## [2.40.0] 2026-11-03 (Skill 側と規則の記述の変更。スクリプトの動作と契約の変更なし。疑似フォルダと文字列の確認。**実機の確認は、未実施** (TEST-PLAN 2-21))

- **`build-test-loop` の「UI テスト (FlaUI)」の節 (24.6KB) を、`references/ui-tests.md` (25.1KB) に分けた。** `SKILL.md` は、53.3KB から 30.0KB に減った (約 44%)。本文には、入口 (約 1.2KB) だけを残した: UI テストは、ビルド → テストの流れに含めない (`PASSED` になっても、自動では、続けて実行しない) / 実行するのは、ユーザーが求めたときと、`/ui-test-first` のループの中だけ / UI テストのプロジェクトがあっても、求められていなければ、実行しない / `uitest_once.sh` の基本形 / **UI テストを、実行する・書く・足す・失敗を調べるときは、先に `references/ui-tests.md` を読む**。
- **理由:** `Skill(build-test-loop)` を読み込んだ 32 のセッション (この環境の履歴) のうち、`uitest_once.sh` を実際に実行したのは、5 つだけ (約 16%)。残りの 27 (約 84%) は、24.6KB を、使わずに読み込んでいた。`/new-solution` の作成のあとのベースライン確認でも、読み込まれる。
- 移した小見出し (見出しは、1 段上げて `##` にした): UI テストの、実行の指定 / いつ実行するか / UI テストが多いとき (`TEST_TIMEOUT`) / 動いたことを、確かめる (トレースと、目で見るモード) / 失敗したら / UI テストを書く・足すとき / ダイアログ・メニュー・コンボなどの UI テスト (`UiDialogs`) / コントロール別の、実機の結果の表 / 注意。参照文書の中の「止めどき」は、「`SKILL.md` の『止めどき』」に直した。
- **参照を更新した (10 か所):** 「`build-test-loop` の『UI テスト』」→「`build-test-loop` の `references/ui-tests.md`」 (`auto-build` / `add-feature` / `new-solution` / `cpp-test-first` / `csharp-test-first` / `ui-test-first` の SKILL.md、規則 (`wpf-csharp.md` / `winforms-csharp.md`)、**`add_ui_tests.py` が生成する UI テストの文書**)。`ui-test-first` には、「実行の指定・いつ実行するか・失敗したら・書き方は、`references/ui-tests.md` を、先に読む」を明記した。
- **規則 (`rules/`) の記述も変わった:** `install.sh --rules-only` も、必要。`--skills-only` だけでは、配布先の規則の参照が、古いまま (「UI テスト」の節を見る、と書かれたまま)。
- 見送ったもの: 「テストの改変の検査 (`test_guard.py`)」の節 (4.8KB) の分離。この節は、「テストを弱めない」という安全の規則の、機械による確認の説明で、基盤のスキルなので、今回の効果を見てから、検討する。
- テスト: `ui_test_first_skill_test.sh` の 2 件を、`references/ui-tests.md` を見るように直し、5 件足した (21 件)。

## [2.39.0] 2026-11-03 (Skill 側のみ。`csharp-test-first` の description と `SKILL.md`。契約の変更なし。文字列の確認のみ。**実機の確認は、行わない** (ユーザーの決定。TEST-PLAN 2-20))

- **SK1 (空のフォルダで、スキルが呼ばれず、応答が英語になった) への対応:**
  1. **description に 1 文を足した (約 0.2KB):** 「ソリューションが、まだない (空の) フォルダで頼まれたときも、まず、このスキルを使う (前提で止まり、`/new-solution` の実行を案内する)」。description は、常に Claude の前にあるので、スキルが選ばれる可能性を上げる。
  2. **「ソリューションがないとき」の規則を、足した (約 0.6KB):** 種類 (WPF / WinForms / C++) が分からないときは、ユーザーに聞く (C++ は `cpp-test-first`)。**空のフォルダで、サンドボックスの内側に見える、0 バイトのキャラクタ特殊ファイル (`.gitconfig`・`.idea`・`.vscode`・`.mcp.json`・`.claude/skills` など) は、書き込み禁止の目隠しで、プロジェクトのファイルではない。環境の不具合と判断しない** (ソリューションの有無は、`.slnx` / `.sln` の有無だけで決める)。案内の例の層を、v2.38.0 の推奨 (`data,logic`。ViewModel もテストするなら `data,logic,viewmodel`) に合わせた。
- **限界:** 規則 (2.) は、スキルが呼ばれたあとにだけ効く。description (1.) が、呼ばれる可能性を上げる保証は、ない。**応答が英語になる件は、リポジトリでは直さない** (日本語の文脈がないために起きた、と推測。Claude Code の `language` 設定が使えるはずだが、未確認。ユーザーの環境の設定)。
- `SKILL.md` は、31.4KB (v2.37.0 は 30.6KB)。サイズの上限のテストを、31000 から 32000 バイトに上げた。
- テスト: `new_solution_winforms_test.sh` に 1 件 (52 件)。

## [2.38.0] 2026-11-03 (Skill 側のみ。`new-solution` の SKILL.md の記述。スクリプトと契約の変更なし。文字列の確認のみ。**実機の確認は、未実施** (TEST-PLAN 2-19))

- **`/new-solution --type wpf` で `--layers` を省略したときの推奨を、`data,logic` と明記した** (データ層 = Model を含める)。**選択肢に、`viewmodel` を出さない。** ViewModel を**テストしたい**と言われたら、`viewmodel` を足した `data,logic,viewmodel` を提案する (`viewmodel` がないと、ViewModel は、アプリの `ViewModels/` に入り、テストできない。あとから足すこともできる: `csharp-test-first` の `references/setup.md`)。**`--layers` の指定がある場合は、そのまま使う** (層を、勝手に足さない)。
- **経緯:** 実機の確認 (SK2・SU2) で、ViewModel 層は作られるが、データ層 (Model) が作られないことに、違和感が出た。原因は、**既定ではなく、確認の手順で案内した引数** (`--layers logic,viewmodel`、`--layers logic`) だった。スクリプトには、`--layers` の既定がなく、省略するとエラーになる (既定は、`SKILL.md` の質問にだけある)。質問の経路では、すでに `viewmodel` は選択肢になく、`logic,data` が推奨だった。今回は、WPF でも同じ推奨であることと、`viewmodel` の扱いを、明記した。
- **実機の確認 (LY1) の結果:** 推奨は `data,logic`、`ViewModels` は作られず、期待どおり。ただし、Claude は、`viewmodel` を、「ViewModel もテストしたい場合」の説明つきの、推奨ではない選択肢として出した (文面は「出さない」)。**ユーザーは、許容し、文面は直さない**。
- **見送ったもの:** 層のプロジェクト名を `<ソリューション名>.<層名>` にする案 (規模が大きく、`wpf-check` / `winforms-check` が、プロジェクト名の正規表現で層を判定するため、ソリューション名が、判定に混ざる)。
- テスト: `new_solution_wpf_test.sh` に 1 件 (61 件)。

## [2.37.0] 2026-11-02 (Skill 側のみ。`csharp-test-first` の `SKILL.md` の分割。契約の変更なし。疑似フォルダと文字列の確認。**実機の確認は、未実施** (TEST-PLAN 2-18))

- **`csharp-test-first` の「セットアップ」(層やテストを、あとから足す手順。3.9KB) を、`references/setup.md` に分けた。** `SKILL.md` は、33.1KB から 30.2KB に減った (約 9%)。本文には、入口 (約 1KB) だけを残した: 足りないときだけ `references/setup.md` を読む / **自分で `.csproj` や `.sln` / `.slnx` を手書きしない、既存のプロジェクトを上書きしない、ベースラインが緑になる前に本物のテストを書かない** (読まなくても守る規則) / `テスト: なし` のときは使えない (案内して止まる)。
- **理由:** `csharp-test-first` を読み込んだ 9 つの実機のセッション (CT1〜CT3、CW1、RS4、SK2、SK2b など) の履歴で、`add_project.py` は、一度も実行されなかった。層とテストは、`/new-solution` が最初に作る。
- `add-feature` の参照 (`csharp-test-first` の「セットアップ」) を、`references/setup.md` に更新した。`install.sh` は、`references/` も、そのまま配る (`find -type f`)。
- **Red の報告に、1 文を足した** (手順 5): テストケースの一覧に出したテストを、Red の前に外したとき (スタブで通ってしまう、など) は、外したテストの名前と理由を書く。スタブで通るテストを残すときも、その旨を書く (真偽の対のテストは、片方が通ることがある)。SK2b で、Claude が、通ってしまったテストを、黙って削除し、件数が一覧と合わなかった。SU1 では、通るテストを残して報告した (報告は出ていたが、規則 (「すべて Red」) には反していた)。**スタブの直し方 (対のテストの扱い) までは、書かない** (3 回目が起きたら、検討する)。`SKILL.md` は、30.6KB。
- 見送った案: WinForms の読み替え表の分離 (WinForms の流れが、表が本文にあることで通っていた (CW1・RS4)。分離すると、読みに行くとは限らず、再確認が要る)。`build-test-loop` (53KB) の分割 (別の作業)。
- テスト: `new_solution_winforms_test.sh` に 4 件 (51 件)。

## [2.36.0] 2026-11-02 (Skill 側のみ。SKILL.md の変更と、変数名の変更。契約 (ファイル名・結果の値・終了コード) の変更なし。疑似フォルダと文字列の確認。実機の確認: SK2・SK3 は 2 回とも ✔、**SK1 (空のフォルダで、スキルが呼ばれない) は ✗ で、直し方は未決定** (TEST-PLAN 2-17))

- **案 4: 変数 `$SLN` を、`$SLN_DIR` に改名した** (`add-feature` / `add-package` / `build-test-loop` / `cpp-test-first` / `csharp-test-first` / `ui-test-first` / `ui-design-review` / `new-solutions` の SKILL.md、`DLL-LAYOUT.md`、`PROJECT-LAYOUT.md`、`test_guard_note.sh` の出力)。`$SLN` は、「ソリューションのフォルダ」だが、名前から `.sln` のファイルと読まれ、Claude が `.sln` / `.slnx` を探しに行った (TEST-PLAN 2-15 の CT1)。定義の行に、「`.slnx` / `.sln` のファイルのパスではなく、それを含むフォルダ。スクリプトの第 1 引数も、このフォルダ」を足した。`SLN_DIR=$(... resolve ...)` も同様。
- **案 3: `csharp-test-first` に、「ソリューションがないとき」を足した。** 止まり、テストもスタブも書かず、`/new-solution --type wpf` (または `winforms`) を、ユーザー自身が実行するよう案内する。**`/new-solution` を `Skill` ツールで呼ばない** (`disable-model-invocation` でエラーになる。CT1 で起きた)。Web・MAUI・Linux / macOS 向けの .NET は、対象外と伝える。
- **案 2: `csharp-test-first` に、「飛ばさない 5 つ」を足した** (冒頭。約 0.9KB): (1) Red のあと、「この Red を、仕様として確定してよいか」と聞いて待つ (「実装まで続けて」とあるときだけ省ける。「機能を追加して」「TDD で」では省けない)、(2) Green の前に `test_guard.py snapshot`、(3) 実装のあと、報告の前に `check`、`TEST_GUARD:` の行を報告に含める、(4) `wpf-check` / `winforms-check`、(5) 最後の報告の先頭に、テストファイルの一覧と、確認の依頼。CT3 では (1)(2)(3) が守られず、(5) は CT3・CW1 で守られなかった。CT1・CT2・CW1・RS4 では、(1)〜(3) が守られていた (実行ごとの揺れ)。
- 変更しなかったもの: `cpp-test-first` の「飛ばさない」の節 (実機で、守られなかった例が、確認されていない)。`docs/DESIGN.md` と TEST-PLAN の過去の記述の `$SLN` (当時の名前のまま)。
- テスト: `new_solution_winforms_test.sh` に 3 件。

## [2.35.0] 2026-11-02 (規則 (`rules/`) の変更。契約の変更なし。疑似フォルダと文字列の確認。**配布先の `~/.claude/rules/` の更新が必要 (`install.sh --rules-only`)。読み込みの条件 (`paths`) は、実機で確認済み (TEST-PLAN 2-16 の RS1〜RS3)**)

- **C# の規約を、3 つに分けた。** 2 つの規則とも `paths: "**/*.cs"` で、`.cs` を 1 つ読むと、WPF と WinForms の両方 (約 62.5KB) が読み込まれていたため。`paths` は、ファイル名しか見られず、WPF か WinForms かを、中身で振り分けられない。
  - **`rules/csharp-common.md` (新規。約 12.9KB):** C# の共通の章 (5 C# コーディング規約 / 10 非同期 / 11 依存性注入 / 12 例外 / 13 ログ / 15 コメント / 16 テスト / 17 禁止事項)。`paths` は `**/*.cs`。**章の番号は、元のまま** (ツールの検出コードと文書が、番号を使っているため。欠けた番号は、固有の章)。
  - **`rules/wpf-csharp.md` (約 27.7KB):** WPF / XAML / MVVM の章 (1〜4、6〜9、14、18、19、付録)。`paths` は、`**/*.xaml`、`**/*.xaml.cs`、`**/ViewModels/**/*.cs`、`**/*ViewModel*.cs`、`**/Views/**/*.cs`。`**/*.cs` と `**/*.csproj` を外した。
  - **`rules/winforms-csharp.md` (約 24.2KB):** `paths` は、`**/*.Designer.cs`、`**/Forms/**/*.cs`、`**/Presenters/**/*.cs`、`**/*Presenter*.cs`、`**/I*View.cs`。共通の章への参照を、`csharp-common.md` に変えた。
- **読み込みの大きさ (バイト数。概算):** WinForms の Presenter・Form = 62.5KB → 37.1KB (約 41% 減)。WPF の ViewModel・XAML = 62.5KB → 40.6KB (約 35% 減)。画面と無関係の `.cs` = 62.5KB → 12.9KB (約 79% 減)。
- **限界:** 振り分けは、**ファイル名と置き場所の規約** (`Forms/`、`Presenters/`、`ViewModels/`、`*Presenter*.cs` など) による。生成されるソリューションは、これに従う。名前が標準と違うと、共通の規則だけが読まれる (固有の規則は、`wpf-check` / `winforms-check` が、機械で確かめる)。`.csproj` を読むときの自動の読み込みは、なくなった。
- 参照を更新した: `new-solution` (SKILL.md、生成する `CLAUDE.md`)、`csharp-test-first` (SKILL.md、`PROJECT-LAYOUT.md`)、README、`add_project.py` と `templates/dotnet/.editorconfig` のコメント。**生成済みの `CLAUDE.md` は、書き換えない** (`wpf-csharp.md` を指していても、リンクは切れない)。
- テスト: `tests/rules_split_test.sh` (新規。13 件)。
- **配布:** `install.sh --skills-only` は、規則を配らない。`install.sh --rules-only` (または、オプションなし) が要る。**v2.32.0 でも、規則の再配布が必要だった** (配布先が、旧名 `wpf-test-first` のままになっていた。2026-11-02 に、`--rules-only` で更新済み)。

## [2.34.0] 2026-11-02 (Skill 側のみ。`csharp-test-first` の本文の変更。契約の変更なし。SKILL.md の文字列の確認のみ。**実機の確認は、未実施**)

- **`csharp-test-first` の本文に、WPF と WinForms の読み替え表を足した。** 本文は WPF の用語 (ViewModel、`PropertyChanged`、`App.xaml.cs`、`wpf-check`) で書かれ、WinForms の記述は 1 行だけだった。WinForms でうまく動いたのは、`CLAUDE.md` と `rules/winforms-csharp.md` を読んだ Claude の読み替えによる (TEST-PLAN 2-15 の知見 3)。
- 読み替え表: View = `Form` / `Designer.cs`、ViewModel = **Presenter** と `IView` (置き場所は、ロジック層、なければアプリの `Presenters/`)、通知とコマンド = `IView` のイベントとプロパティ、フェイク = `IView` の Fake (`RaiseXxx()`) とサービスの Fake、組み立てる場所 = `Program.cs`、検査 = `winforms-check`、規約 = `winforms-csharp.md`。**WinForms に、ViewModel 層は、ない** (`--kind viewmodel` は、使わない)。
- **`IView` にイベントや依存 (`IDialogService`) を足すと、既存のテストがコンパイルで落ちる** (Fake と `new MainPresenter(...)` の引数)。Fake と呼び出し箇所だけを、機械的に直し、期待値とアサーションは、変えない。直した箇所は、Red の報告に書く (CT2・CT3 の実機で、実際に起きた)。
- 前提の層の表、対象外の説明、セットアップ、手順 0 の表、手順 1 の観点、手順 2 のスタブ、手順 3 の規約の参照先に、WinForms の記述を足した。
- テスト: `new_solution_winforms_test.sh` に、2 件 (表の存在と、主な語)。

## [2.33.0] 2026-11-01 (Skill 側のみ。`/new-solution` の質問の変更。契約の変更なし。疑似フォルダでの検証 + SKILL.md の文字列の確認。**実機の確認は、未実施**)

- **`/new-solution`: `--ui-tests` を、画面つきの種類 (`wpf` / `winforms` / `mfc` / `mfc-mdi` / `mfc-dialog`) で、引数にも構成案にも指定がなければ、必ず質問する。** 実機の確認 (TEST-PLAN 2-15) で、WPF だけ「UI テスト (FlaUI) を含めますか?」と聞かれ、WinForms では聞かれず (Claude が「なし」と決めた) 、揺れていたため。仕様に、質問の規則がなかった。`csharp-dll` / `win32` / `console` / `dll` / `lib` は、質問しない。既定は `none`。UI テストを、ビルド → テストの流れに含めない方針は、そのまま。
- `/new-solutions` (複数の候補) は、変更なし (候補ごとに「UIテスト」を聞く規則が、すでにある)。
- テスト: `ui_test_first_skill_test.sh` に、1 件。

## [2.32.0] 2026-11-01 (Skill 側のみ。**Skill の名前の変更: `wpf-test-first` → `csharp-test-first`**。配布先の旧名は、手で削除する)

- **`wpf-test-first` を、`csharp-test-first` に改名した。** WinForms も、同じ手順 (Red → Green。`IView` の Fake で Presenter をテストする) で扱っていたが、名前と `description` が WPF だけに見え、WinForms の依頼で選ばれにくかったため。`winforms-test-first` は、作らない (手順が同じで、重複を避ける)。
- **`description` に、対象の範囲を書いた:** `csharp-test-first` = WPF / WinForms (Windows デスクトップの C#。ASP.NET Core などの Web、MAUI、Linux / macOS 向けの .NET は、対象外)。`cpp-test-first` = Windows デスクトップの C++ (Visual Studio / MSBuild。Web、Linux / macOS 向け、組み込みは、対象外)。`cpp-test-first` の名前は、そのまま。
- 参照を、すべて更新した (`add-feature` / `new-solution` (`add_project.py` を読み込むパスを含む) / `ui-test-first` / `build-test-loop` / `rules/` / テスト / README / DESIGN)。履歴の記述 (この CHANGELOG の過去の版、TEST-PLAN、HANDOFF) は、当時の名前のまま。
- `install/install.sh`: 配布先に `wpf-test-first` が残っていたら、旧名として警告する (自動では消さない)。**再配置のあと、`rm -r ~/.claude/skills/wpf-test-first` が必要。**
- **既存のソリューションの `CLAUDE.md` に、旧名 (`wpf-test-first`) が残っていることがある** (生成済みのファイルは、書き換えない)。新しく生成する `CLAUDE.md` は、新名。

## [2.31.0] 2026-10-31 (Skill 側のみ。**旧 NuGet 方式の GoogleTest を廃止。`--gtest nuget` / `--gtest-from` は、エラーになる (契約の変更)**。疑似フォルダで検証済み。**実機の確認は、済み (TEST-PLAN 2-14 の GN1〜GN4 すべて ✔。旧方式 (NuGet) と vcpkg 方式のテストが、同じソリューションで共存して、3 件通過)**)

- **旧 NuGet 方式 (`--gtest nuget`。兄弟フォルダの `packages\` から、GoogleTest 1.8.1.8 をコピーする方式) を廃止した。** `source` は、残す (ユーザーの決定。`ClaudeProject` が source 方式で、vcpkg が使えない環境の逃げ道を、残すため)。
- `--gtest nuget` と `--gtest-from` は、**エラー (終了コード 2。何も書かない)**。理由と代替 (vcpkg / source) を、案内する。出力の `GTEST_PACKAGE` と、テストの `packages.config` の生成も、なくなった。
- **`auto`:** 既存の `gtest` プロジェクト → source / それ以外 → vcpkg。**`packages\` に旧方式のテストがあるソリューションでも、新しいテストは vcpkg** (`NOTE: … 旧 NuGet 方式 …` を出す)。**既存の旧方式のソリューションは、壊さない** (`packages\` と既存のテストには、触らない)。
- Skill の説明 (`new-solution` / `cpp-test-first` の SKILL.md、`DLL-LAYOUT.md`) から、nuget の記述を削除。`new-solution` の `description` に、vcpkg (既定) を、書き足した。
- **テスト:** `add_layer_test.sh` と `new_solution_test.sh` を、vcpkg 前提に書き直した (nuget のコピー・`GTEST_PACKAGE` の検証を、「廃止のエラー」と「旧方式のソリューションでも、新しいテストは vcpkg」の検証に置き換えた)。全 26 本が通過。
- **実機の確認 (TEST-PLAN 2-14):** 旧方式の実ソリューション (`NewClaudeProject` のコピー) で、既存のテスト 2 件が通り (GN1)、新しい層を足すと vcpkg 方式になり (GN2)、vcpkg の取得のあと、旧方式の 2 件と vcpkg 方式の 1 件が共存して通った (GN3)。廃止のエラーも、確認した (GN4)。

## [2.30.0] 2026-10-31 (Skill 側のみ。生成する MFC のひな形の変更。ホスト側の変更なし。疑似フォルダで検証済み。**実機のビルド・実行の確認は、未実施 (TEST-PLAN 2-13)**)

- **MFC の DPI 認識を、`InitInstance` の `SetProcessDPIAware()` から、マニフェストでの宣言に移した** (ガイドライン UI-DPI-002 が望む形)。MFC のアプリ (SDI・MDI・ダイアログ) の `.vcxproj` の Debug・Release に `<Manifest><EnableDpiAwareness>true</EnableDpiAwareness></Manifest>` を入れ、3 つのひな形から `SetProcessDPIAware()` を外した。値は `true` (システム DPI 対応。従来 (v2.27.0 の TP2 で確認) と同じ動作)。
- **公式の資料 (MSBuild の MT タスク) で確認:** `EnableDPIAwareness` の既定は、`UseOfMfc` が `static` / `dynamic` のとき `true`。MFC は、もとから、システム DPI 対応で、`SetProcessDPIAware()` は、実質、冗長だった。
- **未確認:** vcxproj のメタデータ名が、そのまま効くか (MT タスクの資料は、パラメータ名だけ)。実機で、既定と区別できる値 (`PerMonitorHighDpiAware`) で、一度、確かめる (TEST-PLAN 2-13 の MF2)。
- **テスト:** `ui_guideline_check_test.sh` 91 件 (MFC 3 種類の vcxproj に `EnableDpiAwareness` が Debug・Release にあること、`SetProcessDPIAware` がないこと)。生成直後の MFC は、`ui_guideline_check` が 0 件。

## [2.29.0] 2026-10-31 (**ホスト側 (`watch_and_build.ps1`) と Skill 側の変更。契約の拡張 (後方互換)。Skill 側は、疑似ウォッチャーで検証済み。ホスト側の実機の確認は、未実施 (TEST-PLAN 2-12)**)

HANDOFF §6 の 1・3 (結果の自己記述と、版の不一致の検出)。古い結果の取り違えと、再配置の忘れによる古い版での確認を、減らす。**不一致は、警告 (NOTE) にとどめ、実行は止めない。**

- **版の配布:** `install.sh` が、配布先に `VERSION` を置く (各 Skill のフォルダ、ホスト側のフォルダ)。リポジトリには、置かない。
- **ウォッチャー:** `VERSION` (スクリプトと同じフォルダ) を読み、**起動バナーに版を出す** (なければ `unknown`)。結果のマーカーを書く直前の `run_id.txt` に、**2 行目以降**を足す: `watcher=<版>` / `kind=build|test|uitest|gtest|package` / `input=<ソリューションのフォルダ>` / `finished=<時刻>`。**1 行目の `run=<ID>` は、そのまま** (古い Skill は、1 行目だけを読む)。
- **Skill:** 新しい `build-test-loop/scripts/harness_note.sh` を、`build_once.sh` / `build_test_once.sh` (`uitest_once.sh` は、これを通る) / `package_once.sh` / `gtest_once.sh` が、終了時 (trap) に呼ぶ。出力の末尾に、`RESULT_INFO: kind=… input=<フォルダ名> finished=… watcher=<版>`、版が違えば `NOTE: 版の不一致: Skill=… / ウォッチャー=…`、`watcher=` がなければ `NOTE: ウォッチャーが古い (…)`、版が分からなければ NOTE。**1 行目・終了コードは、変えない。**
- **古い組み合わせ:** 古いウォッチャー + 新しい Skill = NOTE (動作は、従来どおり)。新しいウォッチャー + 古い Skill = 1 行目だけを読み、従来どおり。
- **テスト:** `tests/harness_note_test.sh` (23 件): 配布、`harness_note.sh` の全分岐、配布した Skill の `build_once.sh` を疑似ウォッチャー (新しい形・古い形・不一致) で動かす、`watch_and_build.ps1` の静的な確認。
- **実行権限の統一:** `package_once.sh` と `test_guard_note.sh` に、実行権限を付けた (以前は、`644`。`bash` なしで呼ぶと `Permission denied` になった。実機の確認 HV8 で見つかった)。`bash` 付きの実行は、これまでどおり。
- **実機の確認が要る:** ウォッチャーの再配置・再起動のあと、起動バナーの `Version`、`run_id.txt` の内容、`RESULT_INFO` の行 (TEST-PLAN 2-12)。

## [2.28.0] 2026-10-31 (Skill 側のみ。ひな形と UI テスト生成の変更。ホスト側の変更なし。疑似フォルダで検証済み。**MFC の実機のビルド・実行の確認は、未実施**)

- **`new-solution --type mfc-dialog` のひな形に、名前の入力欄を入れた (WPF・WinForms と同じ画面):** 名前の Edit (`IDC_NAME_EDIT` = 1001)、挨拶の静的テキスト (`IDC_GREETING_TEXT` = 1002)、「クリア」ボタン (`IDC_CLEAR_BUTTON` = 1003)。入力に応じて挨拶が変わり、入力が空のときは、クリアが無効になる。これまでの MFC のひな形は、OK・Cancel・静的テキストだけで、WPF・WinForms と整合していなかった。
- **`add_ui_tests.py`:** MFC のひな形のダイアログ (`Resource.h` に 3 つの ID) なら、コントロール ID の数値 (AutomationId) を埋め込んだ、「入力 → 挨拶 → クリア」のテストを出す。それ以外の C++ は、従来の汎用のテスト (ウィンドウが開くことだけ)。
- **テスト:** `ui_tests_gen_test.sh` (標準のダイアログと、SDI の汎用)、`new_solution_test.sh`。生成した MFC ダイアログは、`mfc-check` と `ui_guideline_check.py` で、指摘 0 件。
- **契約の変更:** `mfc-dialog` で生成するファイル (`Resource.h` / `.rc` / `SampleDlg.*`) の内容。UI テストのひな形の判定 (C++)。

## [2.27.1] 2026-10-31 (Skill 側のみ。ひな形と静的検査の修正。ホスト側の変更なし。疑似フォルダで検証済み。**実機の Narrator の再確認は、済み (「名前、編集、改行」と読まれた。TEST-PLAN TP4)**)

- **実機で見つかった誤り (TEST-PLAN TP4):** v2.27.0 の WPF のひな形は、名前の入力欄と `Label` を、`Label` の `Target` だけで結んでいた。`Target` は、アクセスキーでフォーカスを移す設定で、UI Automation の名前を与えない。**Narrator は、入力欄を「名前」と読まなかった。**
- **修正:** ひな形の `Label` に `x:Name="NameLabel"`、`TextBox` に `AutomationProperties.LabeledBy="{Binding ElementName=NameLabel}"` を追加。
- **静的検査 UIG-ACC001:** `Label` の `Target` を、アクセシブル名として認めない (v2.27.0 までは、見逃していた)。`AutomationProperties.Name` / `LabeledBy` だけを見る。SKILL.md と DESIGN の記述も訂正。
- **テスト:** `Label` の `Target` だけの入力欄が `UIG-ACC001` になること、生成した WPF に `LabeledBy` があることを追加 (`ui_guideline_check_test.sh` 88 件)。

## [2.27.0] 2026-10-31 (Skill 側のみ。生成するソリューションの、ひな形の変更。ホスト側の変更なし。疑似フォルダで検証済み。**実機のビルド・実行の確認は、未実施**)

- **`/new-solution` が作るソリューションを、UI デザインガイドラインの、静的に判定できる必須の規則に合わせた** (v2.26.x の `/ui-design-review` が、生成直後に、いつも出していた既知の指摘を、なくす):
  - **UI-DPI-002 (DPI 認識モードの明示):** WPF: `app.manifest` を生成し (`<dpiAware>true</dpiAware>`。WPF の既定と同じ、システム DPI 対応)、`.csproj` に `<ApplicationManifest>app.manifest</ApplicationManifest>`。WinForms: `.csproj` に `<ApplicationHighDpiMode>SystemAware</ApplicationHighDpiMode>` (`Program.cs` の `ApplicationConfiguration.Initialize()` が使う。VS の WinForms のひな形と同じ設定)。MFC (SDI / MDI / ダイアログ): `InitInstance` の先頭 (`CWinApp::InitInstance()` の前) で `SetProcessDPIAware()` (ビルドの設定に依存しない方法。マニフェストでの宣言が望ましいことは、コメントに書いた)。
  - **UI-CTL-100 (MFC の Common Controls 6.0):** `pch.h` に、Microsoft Learn「Build Requirements for Windows Common Controls」(MFC) の公式の書式のコンパイラ指令 (`#pragma comment(linker, "/manifestdependency:...")`。x86 / x64 / その他)。
  - **UI-ACC-001・UI-CTL-020 (WPF の入力欄):** 名前の入力欄の前に、見える `Label` (`Content="名前:"`、`Target` で `NameTextBox` に結ぶ) を置いた (`DockPanel`)。`TextBox` に `x:Name="NameTextBox"` を追加 (`AutomationId` は、そのまま)。
  - **UI-LOC-001 (表示文字列のリソース化) は、変えていない:** `.resx` などの、ローカライズの仕組みを、ひな形の既定にするかは、ユーザーの判断が要る。生成直後の WPF に、`UIG-LOC001` (warning) が、1 件残る。
- **検証:** 生成した 5 種類 (WPF / WinForms / MFC SDI・MDI・ダイアログ) に `ui_guideline_check.py` を実行し、WPF は `UIG-LOC001` の 1 件だけ、ほかは warning 0 件。`wpf-check` / `winforms-check` / `mfc-check` も 0 件。
- **テスト:** `tests/ui_guideline_check_test.sh` 86 件 (74 → 86: 生成物がガイドラインの検査を通ること、`app.manifest`・`ApplicationHighDpiMode`・`pch.h` の指令・`SetProcessDPIAware` の位置)。
- **未確認 (実機のビルドと実行が要る。TEST-PLAN 2-10 の TP1〜TP4):** (1) 生成した WPF・WinForms・MFC が、ビルドできる。(2) 起動した各アプリの DPI 認識が、システム (タスクマネージャーの「DPI 認識」の列)。(3) MFC のコントロールが、ビジュアルスタイルで表示される (Common Controls 6.0)。(4) WPF の名前欄の見た目 (ラベルとの配置)。
- 設計: `docs/DESIGN.md` 4.46。

## [2.26.3] 2026-10-31 (Skill 側のみ。ホスト側の変更なし。UG3c の軽微な点の反映)

- **実機の確認 UG3c (2026-10-31) は ✔。軽微な 2 点を、`ui-design-review` の `SKILL.md` に、注記した:**
  - **「確認方法」の使い分け:** 画面を操作していないのに、確認方法を「画面の確認」とした項目があった (UI-PRN 系、UI-KEY 系)。**「画面の確認」は、実際の画面を、起動して、操作・表示して、確かめたときだけ。** ソース・リソース・設定を読んだだけなら「実装の確認」。画面を操作できなかった項目は、「確認不能」にして、必要な資料に「画面の確認」と書く。
  - **「OS に追従するか」は、色指定やスタイルの有無では判定できない:** UI-CLR-005 (OS のライト / ダーク設定への追従) を、「独自の色指定がない」ことを理由に、確認した項目 (適合) に入れた (UG3 では、確認不能としていた)。UI-DPI-005 (OS のテキストのサイズ設定への追従) など、同じ種類の規則にも当てはまる。追従するかは、フレームワークと版による。画面で確かめられないときは、確認不能にする。
- **テスト:** `tests/ui_guideline_check_test.sh` 74 件 (72 → 74)。
- 設計: `docs/DESIGN.md` 4.45 (v2.26.3 の項)。

## [2.26.2] 2026-10-31 (Skill 側のみ。ホスト側の変更なし。UG4b の実機の確認の結果の反映)

- **実機の確認 UG4b (2026-10-31) は △:** `/ui-test-first` の計画で、**「守る規則 ID」の列が、表になかった** (規則 ID は、表の外の文に入った)。付録 E の項目の番号 (表の下に 1 行) と、静的検査の指摘 (UI-ACC-001) の「この場で直すか、別に直すか」の質問は、入った。**UI-DPI-002 / UI-LOC-001 は、質問せず、黙って「別対応」にした。** 付録 E の項目の対応に、誤り (ボタンの有効 / 無効を、「9 ボタンの動作」にした。正しくは「7 状態の条件」)。結果は、TEST-PLAN 2-9。
- **Skill (`ui-test-first`):** (1) **列「守る規則 ID」を、「部品」と「操作と期待」の、2 つの表の定義に入れた** (列の並びと、例を明記。該当なしは「なし」)。規則 ID を、表の外の文に、まとめて書くだけにしない。(2) 付録 E の項目の対応表に、**7 状態の条件 (有効 / 無効 / 非表示 / 読取専用)** と、10 入力検証を追加。(3) 静的検査の指摘は、**必須のすべてについて**、「この場で直すか、別に直すか」を、承認の質問に含める (一部だけ質問して、残りを黙って「別対応」にしない)。
- **Skill (`ui-design-review`):** 付録 F.2 の「適用した付録」は、**技術別の付録** (WinUI 3 = 付録 A)。WPF・WinForms・MFC の本文だけなら「なし」。付録 F (チェックリスト) は、書かない。(UG3b・UG4b で、2 回続けて、「付録 F」と書かれた)
- **テスト:** `tests/ui_guideline_check_test.sh` 72 件 (69 → 72)、`ui_test_first_skill_test.sh` 16 件は、通る。
- 設計: `docs/DESIGN.md` 4.45 (v2.26.2 の項)。

## [2.26.1] 2026-10-30 (Skill 側のみ。ホスト側の変更なし。v2.26.0 の実機の確認 (TEST-PLAN 2-9) の結果の反映)

- **実機の確認 (2026-10-30):** UG1 (生成直後は、既知の指摘だけ)・UG2 (既存の 12 フォルダで、異常終了なし・誤検出なし)・UG5 (配置の一致) は ✔。**UG3 (起動は、自動で ✔。報告の様式が違う)・UG4 (規則 ID が、表でなく、表の後ろに入った) は △。** 結果は、TEST-PLAN 2-9。
- **重大度の食い違いを直した (`ui_guideline_check.py`):** 方針は「必須の規則への指摘は warning、推奨は info」だが、`UIG-LOC001` / `UIG-TYP001` / `UIG-CTL003T` / `UIG-CTL101` が、必須の規則なのに info だった (UG3 で、UI-LOC-001 が実質的な不適合なのに、既定で見えなかった)。**前の 3 つを、warning にした。`UIG-CTL101` は、info のまま** (違反の検出ではなく、人の確認を促すだけ。方針の唯一の例外として、Skill に明記)。**影響:** 直書きの文字列がある WPF は、warning になる (`new-solution` の WPF の生成直後も、`UIG-LOC001` が出る。既知の未対応に追加)。
- **Skill (`ui-design-review`):** (1) **付録 F.2 の報告の様式を、そのまま埋められる形で、`SKILL.md` に埋め込んだ** (適合も、「確認した項目」に、1 行ずつ)。(2) **WPF の DPI の既定の注記:** 宣言がなくても、既定で、システム DPI 対応 (「既定で PerMonitorV2 相当」と書かない。UG3 の誤り)。(3) **規則の引用は、本文を `grep` で確かめてから書く** (存在しない節の引用、§2.6 にない根拠の例を、注意として追加)。(4) 既知の未対応に UI-LOC-001 (WPF)、実プロジェクトでの検証の結果を記載。
- **Skill (`ui-test-first`):** 計画の表に、**列「守る規則 ID」**と、表の下に、**付録 E の項目の番号**を求める形に改めた (UG4: 規則 ID が、表の後ろの 1 段落に入り、付録 E との対応がなかった)。既存の画面で、静的検査の指摘が分かっているときは、「この場で直すか、別に直すか」を、承認の質問に含める。
- **テスト:** `tests/ui_guideline_check_test.sh` 69 件 (60 → 69: 重大度 4 件、様式・注記・引用・計画の表の記述)。`ui_test_first_skill_test.sh` (16)、`wpf_check_test.sh` (78)、`winforms_check_test.sh` (29)、`mfc_check_test.sh` (76)、`tools/check-formats.sh` は、通る。
- 設計: `docs/DESIGN.md` 4.45 (v2.26.1 の項)。

## [2.26.0] 2026-10-30 (Skill 側のみ。ホスト側の変更なし。疑似プロジェクトで検証済み。実プロジェクトでの確認は、未実施)

- **UI デザインガイドライン (v2.10、草案) を取り込み、`/ui-design-review` の Skill を追加した。** `skills/ui-design-review/references/UI-Design-Guidelines.md` (ガイドライン本体。`install.sh` で、バイト単位で配布される)、`SKILL.md`、`scripts/ui_guideline_check.py`。
  - **使い方:** (1) 設計: 計画に、付録 E (仕様書テンプレート) の該当項目と、守る規則 ID を書く。(2) レビュー: 静的検査 + 付録 F のチェックリスト (判定は、適合 / 不適合 / 対象外 / 確認不能)。(3) 規則の確認: ID で `grep` する (**本文は約 1,200 行。全文は読まない**)。
  - **`ui_guideline_check.py` (読み取り専用。Windows 不要):** WPF (XAML)、WinForms (`*.Designer.cs`)、MFC (`.rc` / `.vcxproj`) の、静的に判定できる規則を検査する。**15 コード** (`UIG-KEY006` `UIG-CTL091` `UIG-LAY007` `UIG-CTL003` / `UIG-CTL003T` `UIG-ACC001` `UIG-LAY005` `UIG-TYP001` `UIG-LOC001` `UIG-DPI001` `UIG-DPI002` `UIG-CTL100` / `UIG-CTL100V` / `UIG-CTL100U` `UIG-CTL101`)。**必須の規則への指摘は warning、推奨は info (`--all`)。** 終了コード: 0 (指摘があっても 0) / 2 (引数) / 3 (対象なし)。`--fail-on-warning` で、warning があれば 1。`--json` あり。
  - **新規生成のソリューションの、既知の未対応:** UI-DPI-002 (WPF / WinForms / MFC)、UI-CTL-100 (MFC。`pch.h` に、Common Controls のコンパイラ指令がない)、UI-ACC-001 (WPF の入力欄に、アクセシブル名がない) を、満たしていない。**テンプレートは、変えていない** (実機のビルドで確かめられないため)。DESIGN 4.45、NEXT-STEPS。
- **Skill:** `ui-test-first` (計画の表に、付録 E の項目と、守る規則 ID。Green のあとに、静的検査)、`add-feature` (UI 層のタスク)、`wpf-check` / `winforms-check` / `mfc-check` (案内の節) に、`/ui-design-review` への参照を追加。
- **テスト:** `tests/ui_guideline_check_test.sh` 60 件 (各コードの、検出と非検出 / テンプレートの内側と `ResourceDictionary` の除外 / 異なる Common Controls の版の衝突 / 終了コード / `--json` / 読み取り専用 / 生成したソリューションでの動作 / 検査の規則 ID が、参照文書の、有効な規則であること / 版の一致 / Skill の記述 / 配布)。`ui_test_first_skill_test.sh` (16)、`wpf_check_test.sh` (78)、`winforms_check_test.sh` (29)、`mfc_check_test.sh` (76)、`tools/check-formats.sh` は、変更なしで通る。
- 設計: `docs/DESIGN.md` 4.45。

## [2.25.0] 2026-10-30 (ホスト側に、任意のファイルを 1 つ追加。既存のファイルは、変更なし)

- **`host-tools/run_watchers.cmd` を追加: 候補をまとめて起動する。** `run_watchers.cmd [作業フォルダ] [/list]`。作業フォルダの**直下**で、`.slnx` / `.sln` があるサブフォルダを候補として、同じフォルダの `run_watcher.cmd` を起動する (ウォッチャーは、1 つのフォルダ用)。**`wt.exe` (Windows ターミナル) があれば、名前つきのウィンドウ `watchers` の、候補ごとのタブ**。ないとき、または `/windows` のときは、候補ごとに別のコンソールのウィンドウ。`/list` は、一覧だけ。名前が `.` で始まるフォルダは、飛ばす。すでに動いている候補は、`watch_and_build.ps1` の二重起動の拒否が断る。ASCII + CRLF (CP932 でも安全)。`run_watcher.cmd` / `watch_and_build.ps1` は、変えていない (ウォッチャーの再起動は、要らない)。
- `new_solutions.py create` の「次の手順」に、候補が 2 つ以上のとき、`run_watchers.cmd "<作業フォルダ>"` の案内を追加。`/new-solutions` の Skill と、`host-tools/README.md` にも記載。
- テスト: `tests/host_tools_static_test.sh` 42 件 (構造の静的な確認のみ。cmd は WSL で実行できない)、`tests/new_solutions_test.sh` 122 件。**実機の確認は、TEST-PLAN の NS11。**

## [2.24.5] 2026-10-30 (Skill 側のみ。ホスト側の変更なし。`test_guard` の段階 2)

- **`build_test_once.sh` / `uitest_once.sh` の出力の末尾に、`TEST_GUARD:` の行を、自動で足す** (新しい `test_guard_note.sh`)。Claude が、`check` を実行し忘れても、テストの改変が、目に入る。基準 (`.claude-logs/test_guard_base/`) があるときだけ、`test_guard.py check` を実行して、`TEST_GUARD: OK (...)` / `REVIEW (...)` / `ERROR (...)` (error の行を、最大 5 行つけて、「元に戻すか、止まって確認する」)。**基準がないときは、何も出さない** (「作れ」と促すと、Green のあとに `snapshot` を取られて、改変が、基準に取り込まれるため)。**1 行目と終了コードは、変えない** (`PASSED` のまま、`TEST_GUARD: ERROR` が付くことがある)。`check` は読み取りだけで、出力の行は、結果を変えない。`uitest_once.sh` は、スクリーンショットと trace の一覧のあと (最後) に出す。
- `build-test-loop` の Skill に、`TEST_GUARD:` の行の読み方 (出ない = 基準なし。出ないからといって、`snapshot` を取らない) を追加。
- 採らなかった (段階 2 の残り): 実装側の細工 (テストの入力値に対する固定の答え、`#ifdef TEST`) の検査。基準が、ソースにも要り、誤検出の見込みが高いので、見送り。
- テスト: `tests/test_guard_test.sh` 99 件 (基準なし → 出さない / OK / ERROR + TMG005 / フォルダなし / スクリプトの呼び出し)。**実機の確認は、TEST-PLAN の TG5。**

## [2.24.4] 2026-10-30 (Skill 側のみ。ホスト側の変更なし。NS2 の実機の結果から)

- **起動したフォルダの大文字小文字が、実際のフォルダ名と違っても、止まらない** (`build_once.sh` / `build_test_once.sh` (`uitest_once.sh` を含む) / `gtest_once.sh` / `package_once.sh`)。原因: サンドボックスが書き込みを許すのは、**起動したときの綴り**だけなのに、スクリプトが、パスを**実際の綴り**に直していたため、フラグを書けなかった (v2.24.2 までは、`ENV_ERROR` で止めるだけだった)。対策: 実際の綴りに直したあと、パスが起動したフォルダ (`$PWD`) の中なら、**起動したときの綴りに戻す** (`align_to_launch_case`)。Windows 側は、大文字小文字を区別しないので、ウォッチャーは、同じフォルダとして扱う。起動したフォルダの外のパスは、従来どおり、実際の綴りに直す。`ENV_ERROR` (rc=4) は、ほかの原因で書けないときのために、残す。
- テスト: `tests/loop_hardening_test.sh` 53 件 (4 本のスクリプトで、綴りの合わせ方を、文字列で確認)。**実機の確認は、TEST-PLAN の NS10。**

## [2.24.3] 2026-10-30 (Skill 側のみ。NS3 の実機の結果から)

- **`/new-solutions` の Skill に、GoogleTest (vcpkg) の仕上げのコマンドを、直接書いた。** 実機 (NS3) で、`/new-solution` を読み込んでいないセッションが、「A. の 5. と同じ」という参照を、たどれず、手順を探して、調査 (Explore) に回った。`package_once.sh "$候補" --timeout 1800 "vcpkg baseline" "vcpkg install"` を、自分の中に書き、「調査に回らず、この手順を使う」と明記した。
- テスト: `tests/new_solutions_test.sh` 121 件。

## [2.24.2] 2026-10-30 (Skill 側のみ。ホスト側の変更なし。NS2 の実機の結果から)

- **フラグを書けなかったとき、待たずに、理由を出す** (`build_once.sh` / `build_test_once.sh` (`uitest_once.sh` を含む) / `gtest_once.sh` / `package_once.sh`)。実機 (NS2) で、Claude Code を、実際のフォルダ名と大文字小文字が違う `todo` (実際は `ToDo`) で起動したところ、サンドボックスが、フラグの書き込みを許さず、**フラグがない = 回収された、と判定して、結果を最大 300 秒待ち、`TIMEOUT` になった**。ウォッチャーは、何も出さず、理由は、ユーザーに見えなかった。
  - フラグを書いた直後に、置けたかを確認し、置けていなければ、**その場で、`ENV_ERROR` (終了コード 4。ソースやテストの問題ではない) と、「何も始まっていない。最初から、やり直す」と出して、終わる**。
  - 起動したフォルダ (`$PWD`) の大文字小文字が、実際の名前 (`resolve_true_case` が、ディスクの綴りから出す) と違えば、両方の名前を挙げて、「実際の名前で、Claude Code を、起動し直す」と案内する。同じなら、書き込みの権限の確認を案内する。固定の名前は、書かない。
  - 契約: 終了コード 4 (`ENV_ERROR`) の意味を広げた (これまでの値は、変わらない)。
- テスト: `tests/loop_hardening_test.sh` に、4 つのスクリプトの検査を追加 (49 件)。**大文字小文字の違いの案内は、Linux (大文字小文字を区別する) では再現できず、自動テストなし。実機 (WSL の `/mnt/c`) で確認する**。

## [2.24.1] 2026-10-30 (Skill 側のみ。NS9 の実機の結果から)

- **`/new-solutions` の質問の出し方を直した。** 実機 (NS9) で、質問が、候補をまたいで、項目ごとに並び (`TodoCore` の種類 → `TodoWpf` の層 → ...)、どの候補の質問か、分かりにくかった。**候補ごとに、まとめて聞く** (種類 → 層 → テスト → UIテスト)。見出しに、候補の名前を入れる。共通の項目 (仕様書、名前空間) は、最後。候補の数と名前の質問の選択肢は、DLL を含む例も出し、「その他」は出さない。
- **`create` の出力に、`run_watcher.cmd` の場所を、足した** (ホスト側ツールの配置先にある、と書く。**配置先のパスは、固定で書かない**: `--host-dir` で変えられ、WSL 側のスクリプトは、ホストの配置先を、知らない)。
- テスト 120 件。

## [2.24.0] 2026-10-30 (Skill 側のみ。ホスト側の変更なし。疑似フォルダで検証済み)

- **複数の候補を作る入口を、`/new-solution` から分けて、`/new-solutions` にした。** 複数のソリューションを作るのは、まれな使い方なので、`/new-solution` は、**1 つのソリューションを作るだけ** (v2.23.1 の「A か C かの質問」は、廃止。質問なしで、新規作成に入る)。
  - `/new-solutions` (新しい Skill): 作業フォルダの `solutions.md` から、候補ごとのソリューションを作る (`create` / `sync-spec` / `resolve`)。スクリプト (`new_solutions.py`) は、これまでの場所 (`new-solution/scripts/`) のまま。
  - `/new-solution` を、`solutions.md` があるフォルダで実行すると、「`/new-solutions` で行う」と伝えて止まる (`.slnx` を作らない)。
  - **種類は、exe だけでなく、DLL も選べる** (`dll` / `lib` / `csharp-dll`。層は `none` でもよい)。スクリプトは、すでに対応していた。Skill に種類の一覧を明記し、テストを足した。
- **テスト:** `tests/new_solutions_test.sh` に、DLL の候補の作成と、2 つの Skill の記述の検査を追加 (117 件)。

## [2.23.1] 2026-10-29 (Skill 側のみ。文書の修正)

- **`new-solution` の、最初のモードの選び方を直した。** `.sln` も `solutions.md` もないフォルダでは、モード判定の表が、**黙って A (新規作成) になり、作業フォルダそのものが、ソリューションになる** (`ToDo.slnx` ができる) 不備があった (`solutions.md` は、C. の中で作るため、初回は、C. に入れなかった)。**先に、「1 つのソリューションか、複数の候補を作る作業フォルダか」を、質問する**ようにした。ユーザーが、すでに「複数の種類を比べたい」と言っている場合は C.、`--type` などで内容が指定されている場合は A.。`tests/new_solutions_test.sh` に、記述の検査を足した。TEST-PLAN の NS1 に、期待を足した。

## [2.23.0] 2026-10-29 (Skill 側のみ。ホスト側の変更なし。疑似フォルダで検証済み。実機: NS1 (作業フォルダでの一括作成) は確認済み、NS2〜NS6 は未実施)

- **作業フォルダの下に、候補ごとのソリューションを、宣言ファイル (`solutions.md`) から、まとめて作る (`new_solutions.py`)。** 同じ題材を、種類を変えて (WPF / WinForms / MFC など) 作り、個別に比べる用途。作業フォルダ (例: `...\repos\ToDo`) の `docs/` に、壁打ちのメモと仕様書の正本がたまり、候補は、その下の独立したソリューションになる。ウォッチャーは、候補ごとに 1 つ (ホスト側は、変えない)。
  - `create [--dry-run]`: **1 つでも不正なら、何も作らない** (宣言の検査 + 候補ごとの `new_solution.py --dry-run`)。すでに `.slnx` がある候補は、触らない (行を足して再実行すると、足した分だけ作られる)。仕様書 (と「元:」のメモ) を、各候補に取り込み、ハッシュを `docs/specs/.spec-sync.json` に記録する。全候補の `CLAUDE.md` に、「## 比較の候補」の節 (自動生成。改行コードを保つ) を書く・更新する。GoogleTest (vcpkg) の仕上げと、最初のベースライン確認は、しない (候補ごとのウォッチャーが要る)。
  - `sync-spec [--dry-run]`: 作業フォルダの仕様書 (正本) の更新を、各候補のコピーへ反映する。**候補側で編集されたコピーは、上書きせず、衝突として報告する** (終了コード 1)。テストケースの種 (`*.cases.md`) は、更新しない。
  - `resolve <作業フォルダ> [<候補名>]`: 対象のソリューションのパスを、1 行で出す (カレントが、ソリューションなら、そのフォルダ。候補が複数で、名前がなければ、終了コード 2 と候補の一覧)。
- **Skill:** `new-solution` に「C. 作業フォルダ (複数の候補を、まとめて作る)」を追加。`auto-build` / `build-test-loop` / `add-package` / `cpp-test-first` / `wpf-test-first` / `ui-test-first` / `add-feature` の前提に、「作業フォルダで起動しているときは、`resolve` で対象の候補を決める」を追加 (`add-feature` の `"$PWD"` は `"$SLN"` に)。`update-from-ideas` は、作業フォルダでは、構成案を出さず、`sync-spec` を案内する。`brainstorm` に、作業フォルダの注記。
- **テスト:** `tests/new_solutions_test.sh` (宣言の検査 9 種類、何も作らない、冪等、行の追加、CRLF、同期の 6 状態、`resolve`、Skill の記述。疑似フォルダで、`new_solution.py` が実際に生成する)。
- 設計: `docs/DESIGN.md` 4.44。

## [2.22.0] 2026-10-29 (Skill 側のみ。ホスト側の変更なし。疑似プロジェクトで検証済み。実プロジェクトでの確認は、未実施)

- **`test_guard.py` を追加 (`build-test-loop/scripts/`)。「Red を確認したあとの、テストの改変」を、基準との比較で検出する** (読み取り専用。Windows もウォッチャーも不要)。`snapshot` で、テストファイルを `.claude-logs/test_guard_base/` にコピーし、`check` で、いまのテストと比べる。これまで、`build-test-loop` の「止めどき」5 の禁止事項は、文章だけで、守られたかを確かめるのは、人の `git diff` だけだった。
  - 検査: `TMG001` テストの削除 (error)、`TMG002` `[Ignore]` / `Inconclusive` / `GTEST_SKIP` / `DISABLED_` / 既存のテストへの `[TestCategory]` (error)、`TMG003` アサーションがゼロ (error)、`TMG004` アサーションの減少 (warning)、`TMG005` アサーションを弱める (error)、`TMG006` 許容誤差の拡大 (warning)、`TMG007` `[Timeout]` の延長・`Sleep` の追加・待ちの延長 (warning)、`TMG008` `catch` の追加・例外を期待するアサーションの削除 (warning)、`TMG009` テストを実行から外す設定 (error)、`TMG010` アサーション行の書き換え (review)、`TMG011` Fake・ヘルパー・Setup・設定の変更 (review)。終了コード 0 / 1 / 2 / 3。
  - テストは、`[TestMethod]` / `TEST` / `TEST_F` / `TEST_P` / `TYPED_TEST` を単位に、名前で突き合わせる。コメントは無視する。文字コード・改行だけの変更、アプリのソースの変更、支援ファイル (`UiDialogs.cs` / `UiTestBase.cs`) の変更では、指摘が出ない。
  - **承認の扱い:** ユーザーが改変を承認したら、`snapshot` をやり直す (基準の更新)。**鍵ではなく、検知器** (基準のコピーを書き換えられたら、すり抜ける。ヘルパーへの判定の移動と、実装側の細工は、検出できない)。
- **Skill:** `build-test-loop` に「テストの改変の検査」の節と、「止めどき」5 からの参照。`wpf-test-first` / `cpp-test-first` の 6. (テスト確定後に `snapshot`、実装のあと `check`)、`ui-test-first` の 3. / 4. (Red 確認後に `snapshot`、毎回の実行の前後に `check`)、`add-feature` の 5.-3。
- **テスト:** `tests/test_guard_test.sh` (92 項目: 誤検出がないこと 10 種類、各コードを 1 つずつ入れた検出、承認後の再 snapshot、`--json` / `--max-lines`、終了コード)。
- **設計の出どころ:** Copilot の「UI テストファースト開発の、ハーネスとガードの案」を、批判的に検討し、**取り入れたのは、「文章の規則を、機械判定にする」部分だけ** (`docs/DESIGN.md` 4.43)。

## [2.21.1] 2026-10-28 (ホスト側と Skill 側。実機で未確認)

- **`package_once.sh` / `gtest_once.sh` に、実行 ID の照合と、処理中の印を入れた** (v2.20.0 で、`build_once.sh` などに入れたものと同じ)。フラグに、実行 ID を **コメント行** で書く (gtest: 2 行目の `# run=<ID>`。1 行目は、タグのまま。package: 先頭の `# run=<ID>`。古いウォッチャーは、コメントを、タグや操作と取り違えない。新しい Skill と古いウォッチャーの組み合わせでも動く)。ウォッチャーは、結果のマーカーの直前に、同じ ID を `run_id.txt` に書く。古い実行 (`TIMEOUT` であきらめたが、ウォッチャーは続けていた `vcpkg install` など) が、あとで書いたマーカーを、今回の結果と取り違えない。
- **ウォッチャーが処理中 (`watcher_busy.txt`) のときは、`WATCHER_NOT_RUNNING` と誤報しない。** `TIMEOUT` では、回収されていないフラグを取り下げ、メッセージに「ウォッチャーが空くまで、次の実行をしない」と書く。`CLAUDE_PICKUP_WAIT` で、回収の待ち時間を変えられる (既定 15 秒)。
- **ウォッチャー:** `Get-RunIdFromFlag` が、コメント形式 (`# run=<ID>`) も読む。gtest / package のブロックが ID を読み、`Write-GtestMarker` / `Write-PackageMarker` が、マーカーの直前に `Write-RunId` を呼ぶ。gtest のフラグの 1 行目がコメントなら、既定のタグ。

## [2.21.0] 2026-10-28 (Skill 側。GoogleTest の既定を vcpkg に変更。PoC と、生成物の実機での確認済み)

- **`--gtest auto` の既定を、vcpkg にした** (`new_solution.py` / `add_layer.py`)。判定: 既存の `gtest` プロジェクト → source / `packages\` に GoogleTest の NuGet パッケージがある (すでに旧方式) → nuget / **それ以外 → vcpkg**。以前の「兄弟フォルダの `packages\` をコピーできれば nuget」は、`--gtest nuget` を明示したときだけ。`--gtest vcpkg` を追加。
- **vcpkg 方式の生成物:** ソリューション直下の `vcpkg.json` に `gtest` (ネットワークは使わない。`builtin-baseline` は、ウォッチャー経由の `package_once.sh "vcpkg baseline" "vcpkg install"` で入る)、テスト exe の `.vcxproj` に `<PropertyGroup Label="Vcpkg">` (`x64-windows-static-md`)、テスト exe ごとに `main.cpp` (`gtest_main` は自動でリンクされないため)、`.gitignore` に `vcpkg_installed/`、`CLAUDE.md` に vcpkg の節。DLL の `.vcxproj` には、Vcpkg の設定を入れない。出力: `GTEST_MODE: vcpkg` / `GTEST_VCPKG: present | no-baseline | to-add`。
- **メインの exe の保護 (`protect_main_exes`):** vcpkg 方式のテスト exe を、アプリの exe と取り違えないよう、`vcxproj` のコメントの `GoogleTest` で、除く。
- **互換:** `cpp_pkg.py setup` は、vcpkg 方式のテスト exe を「設定済み」として飛ばし、ほかのプロジェクトに足す。nuget 方式・source 方式は、従来どおり使える。
- **違い:** 出力の「Running main() from ...」の行が出ない。`gtestd.lib` ではなく、構成ごとの `gtest.lib`。GoogleTest は C++17 以上が必要 (生成するプロジェクトは C++20)。結果の要約 (`PASSED` / `FAILED`) の形は、変わらない。
- **高速化:** vcpkg の既定のバイナリキャッシュのみ (PoC: 初回 35 秒、キャッシュありの再実行 12 秒)。共有フォルダ (`VCPKG_BINARY_SOURCES`) は、大きなライブラリ向けの任意の設定。
- **Skill:** `add-package` の「GoogleTest は対象外」を改め、`TIMEOUT` は「報告して止まる」(v2.20.0 の止めどきと整合。以前は「1 回だけ再試行」)。`new-solution` / `cpp-test-first` / `DLL-LAYOUT.md` を更新。
## [2.20.1] 2026-10-28 (ホスト側。実機で確認済み)

- **ウォッチャーの起動時に、環境変数 `GTEST_*` を消す** (`GTEST_FILTER`、`GTEST_REPEAT`、`GTEST_SHUFFLE` など)。GoogleTest はこれらを自動で読むため、親のコマンドプロンプトに `GTEST_FILTER=NoSuchTest*` が残ると、全テストが 0 件になり、`ENV_ERROR` になる (GoogleTest の vcpkg 化の PoC で、原因の特定に時間がかかった)。消したときは `[ENV] removed ...` を表示する。絞り込みは、`-TestArgs --gtest_filter=...`。0 件の `ENV_ERROR` のメッセージにも、この旨を追記。

## [2.20.0] 2026-10-28 (ホスト側と Skill 側。自動修正ループの堅牢化: 批判的レビューの指摘への対応。ホスト側は実機で未確認)

- **実行 ID の照合:** スクリプト (`build_once.sh` / `build_test_once.sh` / `uitest_once.sh`) が、フラグの 1 行目に `run=<ID>` を書き、ウォッチャーが、結果のマーカーを書く直前に、同じ ID を `.claude-logs/run_id.txt` に書く。スクリプトは、一致する結果だけを受け取る (前の実行が、あとから書いた、古い結果を、今回の結果と取り違えない)。古いウォッチャーは、書かない → 従来どおり。**`TIMEOUT` (rc 5) は、再試行せず、停止して報告する** (以前は「1 回だけ再試行可」)。`TIMEOUT` のとき、回収されていないフラグは、取り下げる。
- **処理中の印:** ウォッチャーが、処理 (ビルド・テスト・gtest 取得・パッケージ操作) の間だけ、`.claude-logs/watcher_busy.txt` を置く (起動時に、残りを消す)。処理中は、`WATCHER_NOT_RUNNING` (rc 3) とは言わず、`TIMEOUT` まで待つ。`WATCHER_NOT_RUNNING` のメッセージに、対象のフォルダの確認を足した。
- **gtest の `[  PASSED  ] 0 tests.` を `ENV_ERROR` に** (テストが 1 件も実行されていない)。
- **Skill:** `build-test-loop` に「止めどき」の節 (回数の数え方、再試行しないもの、`TEST_TIMEOUT` の 2 回、**実装側の細工の禁止**、テストファイルの編集は機械的な追従だけ、実行 ID の説明)。`auto-build` / `build-test-loop` の表に、`TIMEOUT` (停止) と `BAD_ARGS` を整理。`wpf-test-first` / `cpp-test-first` に、ベースライン (Red の前)、**Green の完了条件 (新しいテストが、実際に実行されたこと)**、バグ修正ではスタブを置かない。`add-feature` に、止めどきの参照。
- **UI:** `uitest_once.sh` は、テストまで届いた実行 (rc 0 / 1 / 7) だけ、スクリーンショットと trace を表示する。待ち時間の既定 = 600 + UI テストのプロジェクトの数 × (`--ui-timeout`、なければ 600) + `--hold` + 120 (最低 900)。`--filter` の、末尾の `\` と CR を拒否。ウォッチャーは、フラグを UTF-8 で読み、`filter=` を、コメントを除く前に読む (`#` を含められる)。`UiTestBase`: `Find` が 5 秒まで探し直す、`StopApp` が null に強い、`Snap(名前, ウィンドウ)`。`UiDialogs` は `partial`。`ui-test-first`: `Preview_<画面>`、回帰は `TestCategory!=Preview`、ループの既定は `--separate` (メニューを開くテストは、別クラスで `--visible`)、visible の了承、`TEST_TIMEOUT` の扱い (`ui-trace.txt` の最後の行、延長は 1 回、2 回続いたら停止)、MFC の ID の探し方、後始末。
- **パスの大文字小文字を、実際のものに直す** (`build_once.sh` / `build_test_once.sh` / `package_once.sh` / `gtest_once.sh`。`resolve_true_case`)。WSL の `/mnt/c` は、大文字小文字を区別しないが、Claude Code のサンドボックスの書き込み許可は、区別して比較するため、パスの大文字小文字が、実際と違うと、結果ファイルの削除・フラグの書き込みが失敗し、古い結果を読んでいた (実機で確認、修正は、コンソールの Claude が、配置先で行い、それをリポジトリに取り込んだ)。
- **実機で確認 (2026-10-28):** 実行 ID、処理中の印、処理中のビルドが `TIMEOUT` になりフラグが取り下げられること、直後の実行が自分の結果を受け取ること、ウォッチャー停止時に前回の画像を出さないこと、gtest の 0 件が `ENV_ERROR` になること。
- DESIGN 4.40 (指摘と、直した内容、直していないこと)。
- テスト: `tests/loop_hardening_test.sh` (新規、20 件)、`tests/host_tools_static_test.sh` (37 件)、`tests/ui_tests_gen_test.sh` (61 件)、`tests/uitest_once_test.sh`。

## [2.19.0] 2026-10-27 (ホスト側と Skill 側。目視確認 (プレビュー): UI テストは裏で、見たい画面だけ、ユーザーのデスクトップに出す。ホスト側は実機で未確認)

- **`UiTestBase` に `HoldForViewing()` と `Snap(名前)` を追加** (生成される `UiTestBase.cs`)。`HoldForViewing` は、環境変数 `UITEST_HOLD_SEC` の秒数だけ、いまの画面を見せる (指定がなければ、すぐ戻る。ウィンドウを閉じると、早く終わる)。`Snap` は、裏でも、PNG を残す。**`PreviewUiTests.cs` (新規。`[TestCategory("Preview")]`、アサーションなし) を生成する。** `--refresh-support-files` は、なければ足し、あれば上書きしない。
- **`uitest_once.sh` に `--hold 秒` と `--preview [秒]` を追加** (`--preview` = `--visible --hold 60`)。flag の `hold=` として、ウォッチャーへ。**`watch_and_build.ps1`:** `hold=` (flag だけ) を読み、環境変数 `UITEST_HOLD_SEC` でテストへ渡す。制限時間は、`hold + 120` 秒以上に、自動で延ばす。`[UI]` の行に `hold` も表示。
- **`uitest_once.sh --present` (デモとして再生):** `--visible` + `--slowmo 800` (指定がなければ) + `present=1` (flag)。ウォッチャーが、環境変数 `UITEST_PRESENT` でテストへ渡す (ユーザーのデスクトップに、強制)。`UiTestBase.Find` / `OpenModal` が、操作する要素を、赤い枠で囲む (`Highlight`)。`--separate` とは、同時に使えない。**再生するのは、`--filter` で指定したテストだけ** (`--filter` が必須。ないと BAD_ARGS。ウォッチャーも、`filter=` がなければ、`present=1` を無視する)。
- `ui-test-first` Skill に「目視確認」の節 (裏で回す側は `--separate`、見せるときは `--preview`、見せる前に告知、Claude 用の `Snap`)。`build-test-loop/SKILL.md`、生成される `CLAUDE.md` にも追記。DESIGN 4.39。
- **ウォッチャー: `--filter` に一致するテストが 0 件のときの、`ENV_ERROR` の文言を、専用のものに** (`no test matches the filter: ...` と、式の書き方の注意。以前は、「GoogleTest / アダプタの不備」を疑わせる汎用の文言だった)。終了コードと、1 行目 (`ENV_ERROR`) は、変えない。
- **ウォッチャー: UI テストの各段階の時刻を、`.claude-logs\ui-timing.txt` に残す** (トリガーの検知、ビルド完了、WPF の描画設定、`Invoke-Tests`、`dotnet test` の開始・終了、デスクトップ用のランナーの初回のコンパイル)。ビルド完了から UI テスト開始までに、長い空白 (実機で、14.5 分が、1 回だけ) があったときの、原因の切り分け用。実行ごとに、作り直す。
- **修正 (リリース前に、実機で発見):** 空の `trigger_uitest.flag` で、ウォッチャーが落ちた (`Get-Content -Raw` が `$null` を返し、`$null -replace` が配列になって `Trim()` が失敗)。`$null` を `""` にしてから使う。静的テストを追加。
- **既存のプロジェクトは、`--refresh-support-files` で、`UiTestBase.cs` を更新する** (旧い版のままだと、`--present` の赤い枠が出ず、操作の間隔が約 3 倍になる)。
- **実機で確認 (WPF = 2026-10-27、WinForms と MFC = 2026-10-28。赤い枠は、目視):** `--refresh-support-files`、`--filter`、`--ui-timeout`、`--present` (赤い枠、`--filter` 必須)、`--preview` / `--preview 20` (ウィンドウを閉じると、早く終わる)、`--separate`。`--filter` が 0 件のときは、`ENV_ERROR` (終了コード 4)。WinForms も、MFC も、同じ項目を確認した (2026-10-28。MFC の赤い枠も、目視)。3 つのフレームワークで、実機で確認済み。
- テスト: `tests/ui_tests_gen_test.sh` に 5 件 (59)、`tests/uitest_once_test.sh` に 9 件 (25)、`tests/host_tools_static_test.sh` に 3 件 (30)、`tests/ui_test_first_skill_test.sh` に 3 件 (16)。

## [2.18.0] 2026-10-27 (ホスト側と Skill 側。UI テストを、ビルド → テストの流れから切り離し、`/ui-test-first` のループを作る。ホスト側は実機で未確認)

- **方針の変更:** **UI テストは、ビルド → テスト (`build_test_once.sh`) の流れに、含めない。** `PASSED` になっても、自動で、続けて実行しない。ユーザーが求めたときと、`/ui-test-first` のループの中だけ、`uitest_once.sh` で、別に実行する。`add-feature` / `cpp-test-first` / `wpf-test-first` / `build-test-loop` / `new-solution` の Skill、`rules/winforms-csharp.md`、生成される `CLAUDE.md` の記述を、そろえて変更した (以前の「Green のあとに、続けて実行する」「UI テストファーストは、しない」は、取り下げ。DESIGN 4.38)。
- **`/ui-test-first` (新規 Skill):** 画面を、プロンプトで作りながら、UI テストを先に書き、`--filter` で絞って、繰り返し実行する (計画で 1 回承認 → Red → 最小の View → 実装 → Green → 全 UI テストの回帰)。
- **`uitest_once.sh` に `--filter 式` と `--ui-timeout 秒` を追加** (flag の `filter=` / `timeout=` として、ウォッチャーへ。`--ui-timeout` が 780 以上なら、待ち時間は、`秒 + 120`)。**`watch_and_build.ps1`:** flag と `uitest.settings` の、`timeout=` (UI テストの制限時間。優先順: flag > `uitest.settings` > `-UiTestTimeoutSec` / `WATCH_UI_TIMEOUT_SEC`) と、flag の `filter=` (`dotnet test --filter`。UI テストのプロジェクトだけ。引用符・バッククォート・改行は、拒否) を読む。`[UI]` の行に、`timeout` と `filter` を表示。生成される `uitest.settings` に、`timeout=` の説明 (コメント) を足した。
- 生成される `CLAUDE.md` の「進め方」に、`/ui-test-first` を追加。README の Skill の説明を更新。
- テスト: `tests/ui_test_first_skill_test.sh` (新規、13 件)、`tests/uitest_once_test.sh` に 3 件 (16 件)、`tests/host_tools_static_test.sh` に 3 件 (27 件)、`tests/ui_tests_gen_test.sh` の文言を更新。

## [2.17.0] 2026-10-27 (Skill 側。ダイアログの UI テストの、第 2 弾の取り込み。単体テストのみ。生成した C# は、実機でコンパイルしていない)

- **`UiDialogs.cs` に、実機の PoC (WinForms / WPF / MFC) で確かめた方法を取り込んだ:** `SendMessage` を 5 秒のタイムアウトつきに (固まったアプリへの同期 SendMessage で、テストごと殺されるのを防ぐ)。`SelectTab(tab, 名前, 全タブの名前...)` / `SelectTab(tab, 順番)` (**WinForms / MFC は、タブの名前を、並び順で全部渡す**。UIA の TabItem は、信用できない)。`ClickColumnHeader` / `ListItems` / `SetNumeric` / `ToggleTreeNode` / `OpenDropDown` / `FindCalendar` / `PostKey` / `FocusAndKeys` / `Vk`。`PressDialogButton` は、失敗したら `ForceCloseDialog` で閉じる。`GetAppWindow` (入力インジケーターの小窓を除く。`UiTestBase` が使う)。**契約の変更:** `SelectTab(tab, name)` は、WinForms / MFC では、全タブの名前を、渡さないと、失敗する (WPF は、従来どおり)。
- **`winforms-check` WFD008 (新規):** `ListView` の `CheckBoxes = true` と `View.Tile`。 **`wpf-check` UI004 (新規):** UI テストがあるとき、`CheckBox` を `Click` だけで受けている。
- 規約: `rules/winforms-csharp.md` 6.3.1、`rules/wpf-csharp.md`。`build-test-loop/SKILL.md` に、「コントロール別の、実機の結果の表」と、第 2 弾の道具。生成される `CLAUDE.md` の UI テストの節にも追記。`docs/NEXT-STEPS.md` の「ダイアログのテスト」を、完了に。DESIGN 4.37。
- **実機で確認 (2026-10-27):** 生成した C# が、WinForms / WPF / MFC で、コンパイルでき (警告 0)、ひな形の UI テストが通った。`uitest.settings` どおりに、デスクトップが選ばれた (WPF = `Default`、他 = `ClaudeUiTest...`)。
- テスト: `tests/ui_tests_gen_test.sh` に 6 件、`tests/winforms_check_test.sh` に WFD008 の 2 件、`tests/wpf_check_test.sh` に UI004 の 2 件。

## [2.16.0] 2026-10-27 (ホスト側と Skill 側。UI テストのデスクトップの既定を、UI テストのプロジェクトの `uitest.settings` に持たせ、1 回ごとに、Claude から指定できる。ホスト側は実機で未確認)

- **`<アプリ>.UITests/uitest.settings` (新規):** UI テストを実行するデスクトップの既定 (`desktop=visible` = ユーザーのデスクトップ / `separate` (別名 `invisible`) = 別のデスクトップ、`slowmo=N`)。**`add_ui_tests.py` (と `new_solution.py --ui-tests flaui`) が、プロジェクトを作るときに書く: WPF は `visible`** (WPF のメニューのポップアップが、別のデスクトップでは、開かないため)、**それ以外は `separate`**。`--refresh-support-files` は、なければ足し、あれば上書きしない。WPF とそれ以外の切り替えを、ウォッチャーの判定でなく、このファイルに統一した。
- **`uitest_once.sh` に、`--visible` / `--separate` (別名 `--invisible`。WPF でも、別のデスクトップにする) / `--slowmo N` を追加** (ウォッチャーを `run_watcher_visible.cmd` に切り替えなくてよい)。指定は、`trigger_uitest.flag` の中身 (`desktop=visible|separate`、`slowmo=N`) として渡る (`build_test_once.sh` の環境変数 `BUILD_TEST_FLAG_CONTENT`)。`--visible` と `--separate` の同時指定、数字でない `--slowmo` は、`BAD_ARGS` (終了コード 2)。指定がなければ、フラグは空 (従来どおり)。
- **`watch_and_build.ps1`: `-UiTestDesktop` の既定値を `auto` に (`WATCH_UI_DESKTOP` の既定も同じ。`visible` = `default`、`invisible` = `separate` の別名を追加)。** 優先順: flag の指定 > `-UiTestDesktop` / `WATCH_UI_DESKTOP` (`default` / `separate`) > UI テストのプロジェクトの `uitest.settings` (複数あれば、1 つでも visible なら visible) > separate。`slowmo=` も同じ順。フラグは、消す前に読む。実行ごとに、`[UI] desktop: ... (理由)` を表示。**ウォッチャーに、フレームワークの判定はない。**
- **契約の変更:** ウォッチャーは、`uitest.settings` がないプロジェクトを、別のデスクトップで実行する (従来どおり)。**既存の WPF の UI テストのプロジェクトは、`uitest.settings` を足す (`add_ui_tests.py <フォルダ> --refresh-support-files`) まで、別のデスクトップのまま。**
- `wpf_menu_note.sh` の文言を変更 (`uitest.settings` に `desktop=visible` がなければ「書く」、あれば「設定に従い、ユーザーのデスクトップで実行される。触らない」。別のデスクトップの記録があるときだけ、2 行目)。`UiDialogs.cs` の失敗メッセージと、生成される `CLAUDE.md` の記述も、同様。`build-test-loop/SKILL.md` (実行前に、ユーザーに、触らないよう伝える)、`auto-build/SKILL.md`、`host-tools/README.md`、DESIGN 4.36 を更新。
- テスト: `tests/uitest_once_test.sh` (13 件)、`tests/wpf_menu_note_test.sh` (13 件)、`tests/ui_tests_gen_test.sh` に `uitest.settings` の 6 件 (49 件)、`tests/host_tools_static_test.sh` に文字列の確認を追加 (24 件)。

## [2.15.0] 2026-10-26 (ホスト側の変更。Linux では検証できない。単体の静的テストのみ。実機は未確認)

- **`watch_and_build.ps1`: `-UiTestTimeoutSec` の既定値を、環境変数 `WATCH_UI_TIMEOUT_SEC` から読む** (なければ 600。明示した引数が優先)。UI テストが多く、600 秒で `TEST_TIMEOUT` (強制終了) になるとき、`set WATCH_UI_TIMEOUT_SEC=1800` で長くできる。起動画面の `UI test` の行に、`timeout N s` と出る (既存の表示)。
- `host-tools/README.md`、`build-test-loop/SKILL.md` (「UI テストが多いとき」の節。分割・ログの 1 行ごとの書き出しも)、DESIGN 4.35 を更新。

## [2.14.0] 2026-10-26 (Skill 側。UI テストの道具 `UiDialogs` の取り込み。単体テストのみ。生成された C# は、実機でコンパイルしていない)

- **`add_ui_tests.py` が、`<アプリ>.UITests/UiDialogs.cs` を、作る** (WinForms / WPF / MFC で、実機で確かめた、ダイアログ・メニュー・コンボ・リスト・スライダー・スクロールバー・タブ・MessageBox・ファイルダイアログの操作を、`FrameworkId` とウィンドウハンドルの有無で、自動で切り替える)。`UiTestBase` に、`OpenModal` / `WaitModalClosed` / `WaitWindow` / `WaitWindowClosed` を足した。`--refresh-support-files` が、`UiDialogs.cs` も、作る (既存のプロジェクトへ、足せる)。WPF のメニューを、別のデスクトップで開こうとすると、`run_watcher_visible.cmd` を案内する失敗にする。
- 生成される `CLAUDE.md` の「UI テスト (FlaUI)」の節に、`UiDialogs` の使い方、「連動の規則は、純粋な関数の単体テスト、UI テストは、ダイアログごとに、煙テスト 1 件」、メニューの注意を追記。`build-test-loop/SKILL.md` に、「ダイアログ・メニュー・コンボなどの UI テスト」の節を追加。`rules/winforms-csharp.md` 6.3 に、「メニューの `Click` で、ダイアログを直接開かない (`BeginInvoke`)」「`AccessibleName`」を追記。DESIGN 4.34 (フレームワークごとの方法の表)。
- テスト: `tests/ui_tests_gen_test.sh` に 11 件 (43 件)。
- **実機で確認 (`UiHelpWf` / `UiHelpWpf` / `UiHelpMfc`、2026-10-26):** `UiDialogs.cs` を含む UITests のコンパイルは、3 つとも成功。WPF は、ひな形の UI テスト 3 件が通り、MFC は 1 件が通った。
- **修正 (実機で見つかった、既存の不具合): WinForms のメインの `MainForm.cs` が、`error WFO1000` でビルドできなかった** (既定の TFM を `net10.0` にしたため。.NET 9 以降の WinForms 解析が、デザイナーが保存しない公開プロパティ (`IMainView` の `PersonName` / `Greeting` / `CanClear`) を、エラーにする)。生成する `MainForm.cs` の 3 つのプロパティに、`[Browsable(false)]` と `[DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]` を付けた (`using System.ComponentModel;` を足した)。`tests/new_solution_winforms_test.sh` に 1 件 (40 → 41 件)。`rules/winforms-csharp.md` にも、追記。

## [2.13.0] 2026-10-26 (Skill 側。WPF のメニューがあるときの、ウォッチャーの使い方の通知。単体テストのみ)

- **`build-test-loop/scripts/wpf_menu_note.sh` (新規):** `UseWPF` のプロジェクトの XAML に、`Menu` / `MenuItem` / `ContextMenu` があるときだけ、「メニューの開閉を含む UI テストは、ウォッチャーを `run_watcher_visible.cmd` で起動して実行する (別のデスクトップでは、WPF のメニューのポップアップが開かない)」を、`NOTE:` の 2 行で知らせる。`build_once.sh` (auto-build) と `build_test_once.sh` (`uitest_once.sh` を含む) が、終了時に呼ぶ。**1 行目と終了コードは、変えない。** `bin` / `obj` の XAML と、WPF でないプロジェクトは、対象外。直近の UI テストが `desktop: Default` なら、出さない。
- `build-test-loop/SKILL.md` と `auto-build/SKILL.md` に、`NOTE:` が出たときの扱い (ユーザーに伝える) を追記。DESIGN 4.33。
- テスト: `tests/wpf_menu_note_test.sh` (新規、11 件)。

## [2.12.0] 2026-10-25 (Skill 側。既定の TFM を、`net8.0` から `net10.0` に。単体テストのみ。実機は未確認)

- **新規作成の既定の TFM が `net10.0` になった** (アプリは `net10.0-windows`、ライブラリとテストは `net10.0`)。方針: 明示しない限り、最新。`--tfm` / 構成案の `TFM:` で、変えられる。**ホストに SDK 10 が必要。** 既存のソリューションは、`.csproj` から TFM を読むので、影響しない (`add_project.py` / `add_ui_tests.py`)。
- **最新の版が STS (例: .NET 11) のときは、質問して決める:** `new-solution/SKILL.md` の手順に追加 (既定は、最新の LTS。スクリプトの挙動は、変えない)。
- `SKILL.md` / `PROJECT-LAYOUT.md` / `rules/*.md` の既定の記述と、生成物を検証する `tests/*.sh` の期待値を更新。DESIGN 4.32。

## [2.11.0] 2026-10-25 (Skill 側。`/brainstorm` → `/update-from-ideas` の成果を、`new_solution.py --spec` が、積極的に取り込む。単体テストのみ。実機は未確認)

- **構成案のキーを拡張:** `UIテスト` (`none` | `flaui`)、`TFM` (.NET のみ。C++ では、注意を出して、読み飛ばす) を、`--spec` が読む。`層` は、`logic:OrderLogic,data` のように、名前つきでも書ける (従来から動いたが、書式を、`update-from-ideas` に明記した)。
- **仕様書の取り込み (新規 `scripts/spec_import.py`):** 新規作成のとき、`--spec` が、(1) 仕様書と `元:` のメモを `docs/specs/`・`docs/ideas/` に置く (すでにあれば何もしない)、(2) 「具体例」「境界値と異常系」の表から、テストケースの種 `docs/specs/<名前>.cases.md` を作る (E1.. / B1..。既存なら上書きしない)、(3) `CLAUDE.md` に「## 仕様書」の節を足す。`--dry-run` は、予定だけを示す。
- `update-from-ideas` の構成案の説明に、`winforms` / `csharp-dll` (層は logic / data のみ)、UIテスト、TFM を追加。`add-feature` は、ケースの種 (`.cases.md`) を読み、WinForms / C# DLL も対象と明記。
- テスト: `tests/new_solution_spec_import_test.sh` (新規)。

## [2.10.1] 2026-10-25 (Skill 側。`build_test_once.sh` の成功時の要約。単体テストのみ。再配置のあとの実機確認は未実施)

- **`build_test_once.sh` が、`PASSED` のとき、2 行目に、要約の 1 行を出す:** `build: SUCCESS / tests: 6 passed (DataLayer.Tests 1, LogicLayer.Tests 5)` (スキップがあれば `6 passed, 1 skipped`。ソースが 6 つを超えれば `... +N more`)。**1 行目の `PASSED` と、終了コードは、変えない** (Skill が読むのは 1 行目)。以前は、`PASSED` の 1 行だけで、テストの件数を知るために、ログファイルを別に読む必要があった。警告の行は、その次。`uitest_once.sh` も、同じ (`build_test_once.sh` を呼ぶため)。
- `summarize_test_log.py` に、`--passed-line --results-dir <dir>` を追加 (構造化された結果 (trx / GoogleTest の XML) から、1 行を出す。結果が 1 件もなければ、終了コード 3 で何も出さない。`<test_error.log>` は要らない)。`build_test_once.sh` の `show_passed_line` が呼ぶ。
- テスト: `tests/summarize_test_log_test.sh` (9 件追加。43 件)、`tests/fake_watcher_test.sh` (構造化された結果つきの PASSED のケースを追加)。
- `build-test-loop/SKILL.md` の `PASSED` の説明を更新。
- **実機で確認 (H9、2026-10-25、`WfFull`):** `PASSED` の次の行に、`build: SUCCESS / tests: 6 passed (DataLayer.Tests 1, LogicLayer.Tests 5)` が出た。`uitest_once.sh` は、未確認。

## [2.10.0] 2026-10-25 (ホスト側の変更。Linux では検証できない。単体の静的テストのみ。実機は未確認)

- **ウォッチャーが、ソリューション (`.sln` / `.slnx`) がなくても起動でき、トリガーのたびに、フォルダから探し直す:** これまでは、起動時に、ソリューションを探して、なければ終了していた。そのため、`new_solution.py` で作る**前**には、ウォッチャーを起動できず、生成のあとに、起動し直す手間があった (実機の確認で、何度も、ここで止まった: `WATCHER_NOT_RUNNING`)。
  - `watch_and_build.ps1`: `-SolutionPath` を、省略可能にした (明示したときは、従来どおり。存在しなければ、終了コード 2)。**`Update-SolutionState`** (新規) が、ソリューションのパス・フォルダ・プロジェクトの一覧・C++ / .NET の判定・Platform (`auto` の解決)・ビルドの機能 (`cpp` / `restore`)・種類の表示を、まとめて決め直す。起動時と、**ビルド / テスト / UI テスト / GoogleTest 取得 / パッケージの、各トリガーが来るたび**に、呼ぶ (起動後に、ソリューションができた・プロジェクトが増えた場合も、再起動が要らない。**以前は、プロジェクトの一覧だけを読み直していたので、C++ だけで起動したあとに、.NET の UI テストを足すと、`restore` が付かない可能性があった。これも、直る**)。`Find-SolutionFile` は、`.slnx` を優先し、`.sln` は拡張子を厳密に確認する (8.3 の短い名前で、`*.sln` が `.slnx` に一致する問題)。
  - **トリガーが来たときに、ソリューションがなければ、ビルドせずに、環境エラー (終了コード 2) として返す** (`build_result.txt` = `FAILED`、`build_error.log` の先頭が `[ENVIRONMENT ERROR ...]` と `ERROR: no .sln / .slnx found in ...`。テストのトリガーなら、`test_result.txt` = `BUILD_FAILED`)。契約 (結果の値・終了コード) は変えない。Skill 側のスクリプトも、変えない。 (`build_once.sh` は、`[ENVIRONMENT ERROR` で始まる `build_error.log` を、`ENV_ERROR` (終了コード 4) として返す。)
  - **実機で確認 (H1〜H4、2026-10-25、`LazySln`):** 空のフォルダで起動 → 生成の前のトリガーは、`FAILED` (環境エラー) で、ウォッチャーは終了しない → 生成 → 再起動なしで、ビルド `SUCCESS`・テスト `PASSED`・UI テスト `PASSED` (3 件)。**H6 (従来の使い方: 既存のソリューションのフォルダで起動) も確認:** ヘッダーにソリューションのパスと種類が出て、ビルド `SUCCEEDED`、テスト `PASSED` (6 件)。**H5 (引数なしの起動は、従来どおり、エラーで終了) も確認。** H7 / H8 は、未確認 (任意)。
  - `run_watcher.cmd`: ソリューションが見つからなくても、起動する (`-SolutionPath` を、見つかったときだけ渡す)。**ただし、フォルダの引数なしで起動して (`run_watcher.cmd` のあるフォルダが対象になる)、ソリューションがないときは、指定ミスの可能性が高いので、従来どおり、エラーで終了する。**
  - **自動のつながり:** ビルド、テスト、UI テストの各トリガーが、それぞれ、今までどおり動く (ビルドのあとにテスト、など)。トリガーを、自動で連鎖させる仕組みは、入れていない。
- 検証: `tests/host_tools_static_test.sh` (16 件): 構造の静的な確認 (BOM・CRLF・CP932、`-SolutionPath` が省略可能、`Update-SolutionState` が 4 か所で呼ばれる、ソリューションがないときのビルドの分岐、括弧の対応、`.cmd` の `SLN_ARG`)。**PowerShell が使えないので、実行は未確認** (TEST-PLAN H 系)。

## [2.9.3] 2026-10-25 (`winforms-check` の起動の誘導。WC4 の実機の結果を受けて)

- **WC4 の実機の結果 (2026-10-25):** 「ウィンドウは開くのですが、中が空です。原因を調べて、直してください」に対して、Claude は、**`winforms-check` の Skill を起動せず**、`MainForm.cs` などを直接読んで、`InitializeComponent()` の呼び忘れを見つけ、足して直した (コントロールを消さない、正しい直し方)。**直したあとに**、`winforms_check.py` を実行して 0 件を確認し、ビルド・テスト・UI テストも通した。規約 (`winforms-csharp.md`) は、自動で読み込まれていた。
- **直したこと:** `SKILL.md` の `description` に、依頼の言い方に近い言葉 (「ウィンドウは開くが中が空」「何も表示されない」「コントロールが出ない」) を足し、本文の冒頭に、「コードを読む前に、まず、これを実行する」と書いた。**効果: 「ウィンドウは開くが中が空」では、効いた** (新しいセッションで、診断の前に Skill が呼ばれ、`WFD001` を検出した)。**「UI テストが ClearButton を見つけられません」では、効かなかった** (`Explore` のサブエージェントで原因を調べ、Skill は修正の後の検証だけ。診断と修正は正しかった)。そのため、`description` と冒頭に、「UI テスト (FlaUI) が要素を見つけられない」「AutomationId が見つからない」「サブエージェントなどを始める前に」を足した。**再確認 (WC4c、2026-10-25 実機): 新しいセッションで、依頼の 3 秒後に、`Skill` ツールで `winforms-check` が呼ばれ、`WFD003` を検出して、`Name` をそろえた (サブエージェントより先)。効いた。**
- 補足: `.py` のスクリプトは、すべて実行権限なし (644) で、`SKILL.md` が `python3` で実行するよう書いている。直接実行すると `Permission denied` (終了コード 126) になるが、仕様どおり。

## [2.9.2] 2026-10-25 (VS のデザイナーが、生成した Form を認識しない問題を修正。実機で原因を切り分け)

- **生成した `MainForm.cs` が、VS で Form と認識されず、デザイナーが開けなかった (WF2 の実機で発見):** Solution Explorer で通常の `.cs` のアイコンになり、「デザイナーの表示」が出なかった。VS で新しい Form (`Form1`) を追加すると、`MainForm` も認識され、デザイナーが開けた。**そのときの差 (ディスク): `WfFull.csproj.user` が新規に作られ、`Forms\MainForm.cs` に `<SubType>Form</SubType>` が書かれた。`MainForm.resx` (空のテンプレート) も新規に作られた。`MainForm.cs` / `MainForm.Designer.cs` / `.csproj` は、変わっていない** (**ファイルスコープの名前空間は、原因ではなかった**)。
- **切り分け (未使用の 2 つのソリューションで):** (A) `MainForm.cs` に `using System.Windows.Forms;` を足すだけ、(B) `.csproj` に `<Compile Update="Forms\MainForm.cs"><SubType>Form</SubType></Compile>` を足すだけ、のどちらでも、VS が Form と認識し、デザイナーが開けた。**どちらが本当の原因かは、分かっていない** (何も足さない対照は、`WfFull` の最初の状態)。
- **修正: 両方を、生成する。** (1) `csproj_winforms` が、`Forms\MainForm.cs` に `SubType` = `Form` を、書く。(2) `main_form_cs` が、`using System.Windows.Forms;` を、明示する (`ImplicitUsings` に頼らない。`dotnet format` の並びに合わせて、System が先)。既存のソリューションは、VS でデザイナーを一度開けば、VS が `.csproj.user` に書く。
- **実機での確認 (WF2b、2026-10-25):** 新しく生成した `WfDsg` を、VS で開き、ビルドも Form の追加もせずに、「デザイナーの表示」で、デザイナーが開けた。**`.csproj.user` は作られなかった** (VS が `SubType` を、追加で書く必要がなかった)。ソリューションを開いた直後は、Form のアイコンになっておらず、デザイナーを開いたあとに、Form のアイコンになった (表示の遅れ)。
- `rules/winforms-csharp.md` 5.1 に、Form を VS に認識させる決まりを追記。
- テスト: `tests/new_solution_winforms_test.sh` (40 件)。

## [2.9.1] 2026-10-25 (UI テストのスクリーンショットの切れを修正。実機で、原因を確認。修正の確認は未実施)

- **UI テストのひな形 (`Screenshots.cs`): スクリーンショットの右下が切れる不具合を修正 (WF7 の実機で発見):** 失敗したテストの PNG が **380 x 230** で、タイトルバーの最大化ボタンの途中、テキストボックスの右端、**「クリア」ボタン (下端)** が写っていなかった。**原因: テストのプロセス (testhost) が DPI 非対応**で、UI Automation の矩形も `GetWindowRect` も、**縮小された値**で返る。`PrintWindow` は、ウィンドウの実際の大きさで描くので、小さすぎる `Bitmap` に、左上だけが入る。v2.8.0 の「UIA の矩形と `GetWindowRect` の大きいほう」は、**同じ縮小値なので、効かなかった** (v2.8.0 の説明にある「原因未確定」は、これ)。**修正: (1) アセンブリの読み込み時 (`[ModuleInitializer]`) に、`SetProcessDpiAwarenessContext(Per-Monitor V2)` で、テストのプロセスを DPI 対応にする (矩形が、実際の大きさで返る)。(2) できなかったとき (すでに決まっていた場合) は、`IsProcessDPIAware()` が false で、`GetDpiForWindow` が 96 より大きければ、矩形を `dpi / 96` 倍にする。** WPF / MFC のひな形も、同じ `Screenshots.cs` なので、同じ修正が入る。既存の `*.UITests` は、`add_ui_tests.py <フォルダ> --refresh-support-files` で更新する。
- **WPF でも、実機で確認 (WF8 後半、2026-10-25、`WpfShot`):** 失敗時のスクリーンショットが 500 x 275 (`Width` 400 / `Height` 220 × 125%) で、全体 (タイトルバー、テキストボックス、挨拶、「クリア」ボタン) が写り、白一色にならない。**MFC も、実機で確認** (`MFCSHot`: 498 x 272 で、ダイアログ全体が、画像いっぱいに写る。切れない。内容が小さく写る問題も、なし)。
- 気づいた点 (修正しない): `PrintWindow` は、ウィンドウの「見えない枠」(Windows 10 / 11 の、リサイズ用の透明な枠。左端に黒い帯として写る) も含める。見た目だけの問題で、内容は読める。
- テスト: `tests/new_solution_winforms_test.sh` (39 件)。

## [2.9.0] 2026-10-25 (WinForms の検査と規約。単体テストのみ。実プロジェクトでの誤検出の確認は未実施)

- **`winforms-check` を追加 (DESIGN 4.30 段階 4。独立した Skill。読み取りだけ。ウォッチャーも Windows も .NET も不要):** `winforms_check.py`。検査: `WFD001` (Form のコンストラクターが `InitializeComponent()` を呼ばない = 画面が空)、`WFD002` (Designer の `Name` の重複)、`WFD003` (`Name` が変数名と違う)、`WFD004` (生成したコントロールが `Controls.Add` に入っていない)、`WFD005` (UI テストがあるのに `Name` がない)、`WFD006` (`InitializeComponent()` が Designer.cs 以外にある)、`WFD007` (`InitializeComponent()` の中に制御構文)、`WFT001` (`DoEvents`)、`WFT002` (Form の `Thread.Sleep`)、`WFT003` (`CheckForIllegalCrossThreadCalls = false`)、`WFL001` (ロジック・データ層への WinForms の混入)、`WFL002` (Presenter が WinForms の型を使う)、`WFL003` (参照の向き)、`WFL004` (Form で Service を `new`)、`ASY001` / `ASY002` / `EXC001` / `EXC002` / `NAM001` (`wpf-check` と同じ)。出力と終了コード (0 / 1 / 2 / 3) は、`wpf-check` と同じ形。**`new-solution` が作る WinForms (層あり・ロジック層なし・アプリのみ・UI テストつき) は、指摘 0 件。**
- **`rules/winforms-csharp.md` を追加 (ユーザー共通。`paths` は `**/*.cs` `**/*.csproj`):** MVP (Form は `IView` の実装、Presenter に振る舞い)、composition root (`Program.cs`)、ソリューション構成と層の依存、コントロールの命名 (`Name` = AutomationId)、`Designer.cs` の扱い、レイアウトと DPI、ダイアログ (`IDialogService`)、スレッド、例外 (`Program.cs` の受け口)、テスト (Presenter は `IView` の Fake、UI テストは FlaUI)、禁止事項、レビュー項目、規則と検査の対応表 (付録)。C# の共通部分は、`wpf-csharp.md` の C# の章を使う。WPF / XAML / MVVM の章は、WinForms では適用しない。
- 生成する `CLAUDE.md` (WinForms) が、`winforms-check` と `winforms-csharp.md` を指す。`add-feature` / `wpf-test-first` / `new-solution` の `SKILL.md`、README、DESIGN を更新。
- テスト: `tests/winforms_check_test.sh` (27 件: 生成物は指摘 0 件、各コードを、わざと壊した複製で確認、`async void` のハンドラーは対象外、テストプロジェクトは共通の規則の対象外、`--json`、読み取り専用)。

## [2.8.0] 2026-10-25 (WinForms の UI テスト。PoC は実機で確認済み。生成したプロジェクトのビルドは未確認)

- **WinForms の FlaUI の PoC (DESIGN 4.30 段階 3。2026-10-25 実機):** 別のデスクトップで、(1) **`AutomationId` = コントロールの `Name`** (`NameTextBox` / `GreetingLabel` / `ClearButton` / `MainTable`)。Label の `Name` は表示の文字。(2) **UIA3:** `ValuePattern` で入れた文字が `TextChanged` を起こし、Presenter が挨拶を変える。`Invoke` でクリアが動く。ボタンの有効・無効 (`CanClear`) も見える。(3) **UIA2 も、7 手順すべて OK** (WPF は、別のデスクトップで `Invoke` が失敗した。WinForms は、UIA2 が本来の UIA なので動く)。UIA3 を標準にする方針は、変えない。(4) **`PrintWindow` が、内容を写した** (WPF のような白い画像にならない。ハードウェアアクセラレーションの対策は、要らない)。(5) 起動 約 1.1 秒。
- **`--ui-tests flaui` が WinForms で使える:** `add_ui_tests.py` が、`UseWindowsForms` の exe を、アプリとして判定する (`classify` の `winforms`)。標準の `MainForm` (`Designer.cs` に `NameTextBox` / `GreetingLabel` / `ClearButton` の `Name`) なら、入力 → 挨拶 → クリアのテスト (`TESTS_WINFORMS_CS`)。標準でなければ、ウィンドウが開くだけのテストと、`Name` を付けるよう促す NOTE。層の有無に関係なく使える。作成と同時 (`new-solution --type winforms ... --ui-tests flaui`) も、後付けもできる。`DefaultStartup` がなければ、WPF / WinForms の exe を優先して選ぶ。
- **スクリーンショットの大きさ:** UIA の矩形と `GetWindowRect` の大きいほうに合わせる (PoC で、UIA3 の 1 枚だけ、右下のボタンが切れた。原因は未確定 (DPI の違いを疑う)。**ひな形の変更は、WPF / MFC にも及ぶ**。実機で、切れないことと、他の画像が崩れないことを確認する)。
- テスト: `tests/new_solution_winforms_test.sh` (38 件)。TEST-PLAN: WF0 (PoC の記録)、WF7 / WF8 (生成した UI テスト)。

## [2.7.0] 2026-10-24 (単体テストのみ。コンパイルを含めて、実機は未確認)

- **`new-solution --type winforms` を追加 (DESIGN 4.30、段階 2):** WinForms (.NET、MVP) のソリューションを作る。メインは WinForms アプリ (`UseWindowsForms`、`Program.cs` が composition root、`Forms/MainForm.cs` + `MainForm.Designer.cs`)。層は `data` / `logic` だけ。`Form` は `IMainView` を実装し、画面の振る舞いは `MainPresenter` が持つ (ロジック層があればそこ、なければアプリの `Presenters/`)。ロジック層に、`MainPresenterTests` (Fake の View、4 件) が付く。`--ui-tests flaui` は、PoC のあとに対応するため、今はエラー。
- `add_project.py`: `presenter` の種類 (`lib_files` / `test_files` / `--kind presenter`、`read_lib_info` の `is_presenter`) と、`winforms_app_files` を追加。後付けの `--tests mstest` が、Presenter のあるロジック層に、`MainPresenterTests` を足す。
- **層を持たない構成 (`--layers none` / `data`) でも、Presenter をテストできる:** ロジック層がないとき、`--tests mstest` は、アプリの `Presenters/` を対象にした `<アプリ名>.Tests` (TFM はアプリと同じ `-windows`、名前空間 `<ルート>.Presenters.Tests`) を作る (`test_files` の `app-presenter`)。後付けも同じ (`libraries_without_tests` が、`Presenters/MainPresenter.cs` のある exe を対象にする。WPF のアプリは、対象外のまま)。`csharp-dll` は、層なしでも、メイン自身がテストの対象 (v2.6.0)。
- テスト: `tests/new_solution_winforms_test.sh` (29 件)。TEST-PLAN に 2-5 (CD1〜WF5) を追加 (実機は未確認)。

## [2.6.0] 2026-10-24 (単体テストのみ。実機は未確認)

- **`new-solution --type csharp-dll` を追加 (DESIGN 4.30、段階 1):** C# のクラスライブラリ (.NET) のソリューションを作る。メインがクラスライブラリで、`<メイン>.Tests` (MSTest) の対象になる。`--layers` は `data` / `logic` (`viewmodel` はエラー)、`--ui-tests` はエラー、`.slnx` に `DefaultStartup` なし。`--spec` の「メインの種類」にも使える。後付けの `--tests mstest` は、メイン自身も対象にする (既存の仕組みのまま)。`claude_md_csharp_dll` で、専用の `CLAUDE.md` を作る。
- テスト: `tests/new_solution_csharp_dll_test.sh` (15 件)。

## [2.5.7] 2026-10-24 (U16 の C++ 側で発見。実機で確認済み)

- **ウォッチャー: 古い DLL の検出が、Debug と Release を比べて、誤検出していた (U16 の C++ 側の実機で発見):** `MixTest` を、先に `Release` でビルド (T9a)、あとで `Debug` で起動すると、増分ビルドで書き換わらなかった `bin\Debug` の `Calc.Tests.dll` (10-21) が、`bin\Release` の同名の DLL (10-24) より古いと判定され、`ENV_ERROR` になった。**比べる対象を、構成のフォルダ名と、TFM のフォルダ名が同じもの (プラットフォームのフォルダだけが違うもの: `bin\Debug\net8.0` と `bin\x64\Debug\net8.0`) に限る。** U15 / U15b の、偽の成功の検出は、そのまま働く。

## [2.5.6] 2026-10-24 (H4 / T9a / T9b は実機で確認済み)

- **ウォッチャー: 起動後に `build-windows.cmd` が消えたとき、環境エラーにする (H4 の確認の準備で発見):** `cmd /c` が、見つからないバッチに対して返す終了コードは、ビルド失敗 (1) と区別できないことがある (`build_error.log` に `[ENVIRONMENT ERROR ...]` が付かない、または、古いログが読まれる)。`Invoke-BuildScript` が、実行の前にファイルの有無を確かめ、なければ `ERROR: build script not found: ...` と終了コード 2 (環境エラー) を返す。
- **`build-windows.cmd`: `-Platform Win32` で、`.sln` / `.slnx` のソリューション構成の名前に合わせる (T9b の実機で発見):** `DoubleBufferSample.sln` (VS 製) を `-Platform Win32` でビルドすると、`MSB4126: 指定されたソリューション構成 "Debug|Win32" は無効です` で失敗した (終了コード 6 `BUILD_FAILED`)。VS が作るソリューションでは、x86 のプラットフォームの名前が **`x86`** (プロジェクトの側が `Win32` に対応づく)。ソリューション構成の一覧 (`Debug|x86 = Debug|x86`、`.slnx` は `<Platform Name="x86" />`) に、`Win32` がなく `x86` があれば、MSBuild に `x86` を渡す。`.vcxproj` を直接ビルドするときと、`Win32` があるソリューションは、従来どおり `Win32`。
- **ウォッチャー: `Win32` のテスト exe を、`<ソリューション>\<Configuration>\` からも探す (T9b の実機で発見):** `Win32` のビルドが通っても、`build_test_once.sh` が `ENV_ERROR` (`no tests found for Debug|Win32`) になった。VS の既定の出力先は、x64 が `x64\Debug\`、**Win32 だけは `Debug\` (プラットフォームのフォルダが付かない)**。`Find-TestExes` が、`Win32\<Configuration>\` のあとに、`<Configuration>\` も探す (最初に、テスト exe が見つかった側)。

## [2.5.5] 2026-10-24 (U14b / U14c の (b) は実機で確認済み。案内の行を 2 行目に移した変更は、再確認していない)

- **`build-windows.cmd`: C++ ツールのない VS のとき、案内を出す (終了コード 11、契約は変えない):** `no Visual Studio with C++ x86/x64 tools found.` だけでは、対処が分からなかった。**「Visual Studio Installer で『変更』→『C++ によるデスクトップ開発』を追加する。自動では追加できない」**という `ERROR:` 行を足した (ウォッチャーは `ERROR:` 行を `build_error.log` に渡すので、Claude に伝わる)。C++ を要求しない場合 (`MSBuild` のある VS がない) も、VS (または Build Tools) のインストールを案内する。
- **逆の場合 (.NET のビルドツールのない環境、例: C++ のワークロードだけの VS) の案内 (`watch_and_build.ps1`):** `MSB4236` / `NETSDK1045` / `NETSDK1141` で `ENV_ERROR` になるとき、および `dotnet` が見つからないとき (テスト・パッケージ操作) に、**「Visual Studio Installer で『.NET デスクトップ開発』を追加する (または .NET SDK をインストールする)。自動では追加できない」**という `ERROR:` 行を、`build_error.log` / `test_error.log` / `package_error.log` に付ける (`$DotnetInstallHint`)。`NU1301` (ネットワーク) には付けない。
- `auto-build` の `ENV_ERROR` の行と、`host-tools/README.md` に、同じ対処を記載。C++ ツールなしの VS で動くかの確認 (U14) は、環境の前提に含まないため、対象外 (DESIGN 1.)。メッセージだけを、擬似的な `vswhere.exe` で確かめる (U14b)。

## [2.5.4] 2026-10-24 (U15b を含め、実機で確認済み)

- **ウォッチャー: 古い DLL を実行する「偽の成功」の検出 (U15 の実機で発見):** 出力先が `bin\x64\Debug` のプラットフォーム別の構成で、`-DotnetTestArgs` を付けないと、`dotnet test --no-build` は `bin\Debug` を探す。そこに過去のビルドの古い DLL があると、今回のビルドの成果物ではなく、古い DLL のテストが通って `PASSED` になった。**`Get-StaleTestAssemblies`:** 実行されたアセンブリ (trx の `storage`) と同名で、より新しい DLL が、プロジェクトの `bin` 配下の別の場所にあれば、`ENV_ERROR` (成功のとき。失敗のときは `FAILED` のまま、理由を `test_error.log` に追記) にして、`-DotnetTestArgs:-p:Platform=x64` を案内する。更新時刻とビルドの開始時刻は比べない (増分ビルドで DLL が書き換わらないのは、正常なため)。出力先を切り替えて使うと、古い側が新しい側に負けて、誤って `ENV_ERROR` になることがある (古い `bin` を消せば解消)。
- **`test_error.log` の `at at` の重複 (U7 の実機で発見):** trx のスタックトレースが、すでに `at` で始まっていたため、`at at ...` と出た。先頭の `at` / `場所` を取ってから付ける。
- **`-DotnetTestArgs` の書き方 (U15 の実機で発見):** `powershell -File` から `-DotnetTestArgs "-p:Platform=x64"` と書くと、値が `-` で始まるため、PowerShell が `-p` をパラメーター名と解釈して、`ambiguous` で起動に失敗する。**`-DotnetTestArgs:-p:Platform=x64` (コロンで結ぶ)** に、README・ヘルプ・PROJECT-LAYOUT を直した。
- **生成コードの `using` の並び (WS14 の実機で発見):** `dotnet format --verify-no-changes` が、`WpfUi15.UITests/MainWindowUiTests.cs` と `WpfUi15/App.xaml.cs` の 2 件 (`IMPORTS`) を指摘。`add_ui_tests.py` (`TESTS_WPF_CS`) と `add_project.py` (`app_xaml_cs`。Views / ViewModels の名前空間を並べ替える) を直した。新しく生成した `WpfFmt14` で `exit=0`。
- 記録: U7 / U8 / U13 / U15 / WS14、P14 / P15 / U6c / U12 を、実機で確認済み。

## [2.5.3] 2026-10-21 (実機で確認済み: UT14b、P6、P14、P15、U6c、U12)

- **ウォッチャー: WPF の描画設定の復元 (`Restore-WpfRendering`):** 異常終了のあと、次の起動で、「復元した」と表示したのに、レジストリも記録ファイルも、そのままだった (UT14b の実機で発見)。失敗を握りつぶさず (`-ErrorAction Stop`)、実際に戻ったかを確かめてから、記録を消し、メッセージを出す。失敗したときは、例外の種類と理由を表示する。
- **ウォッチャー: ネットワークに届かないときの判定 (P6 の実機で発見):** (1) 日本語 OS の、接続の失敗のメッセージ (`対象のコンピューターによって拒否されたため、接続できませんでした` など) が、環境エラーの判定に含まれず、`ENV_ERROR` でなく `FAILED` になった → 判定に、日本語のメッセージを追加。(2) PowerShell 5.1 の `Invoke-RestMethod` は、プロキシの環境変数を見ず、`nuget search` / `versions` だけが、プロキシを通らなかった → `HTTPS_PROXY` / `HTTP_PROXY` を、`DefaultWebProxy` に適用。
- `build_test_once.sh`: ウォッチャーが動いていないときの案内に、実際のフラグ名と、古いウォッチャーの可能性 (`copy-host-tools.sh` で再配置) を、出す。
- 記録: U9 / U10 (混在の GoogleTest + MSTest)、UT4 / UT6 / UT8 を、実機で確認済み。

## [2.5.2] 2026-10-21

- **`mfc-check` UI004** (warning): UI テストのプロジェクト (`*.UITests`) があるとき、ダイアログの操作できるコントロール (ボタン・エディット・コンボなど) の ID が `IDC_STATIC` (`-1`) のまま、または、同じダイアログで ID が重複している (UI テストの AutomationId = コントロール ID なので、ID で探せない)。静的テキスト・グループボックス・アイコンは、対象外。UI テストのプロジェクトがなければ、出ない。実プロジェクト (`MfcUi18` / `MfcDlgLayers` / `MfcSdiLayers`) で、誤検出なし。`mfc_check_test.sh` に 7 件を追加 (76 件)。
- 生成の出力の順序 (UI テストの足し込みが、本体より先に出る) を直した (標準出力のフラッシュ)。

## [2.5.1] 2026-10-21 (UI テストを、目で確かめるモード。UT20〜UT22 は実機で確認済み)

- **`run_watcher_visible.cmd`** (新規): UI テストを、ユーザーのデスクトップで、操作の間に待ち (`WATCH_UI_SLOWMO_MS`、既定 800 ms) を入れて、実行する。ウォッチャーに `-UiTestSlowMoMs` (環境変数 `WATCH_UI_SLOWMO_MS`)、テストへの環境変数 `UITEST_SLOWMO_MS`。
- **ひな形 (`add_ui_tests.py`):** `UiTestBase` が、操作の記録 (`ui-trace.txt`) を残し、スローモーション (要素を探すたびに待つ。ウィンドウを前面に出す。終了の前に、最後の状態を見せる)。`UiNative.cs` (新規: デスクトップ名、前面表示、トレース)。`Screenshots`: ユーザーのデスクトップで PrintWindow が空白なら、画面のコピーに切り替える。`--refresh-support-files`: 既存の UI テストのプロジェクトの、ツールが持つ 4 つのファイルを、最新にする。
- **`uitest_once.sh`:** 操作の記録から、テストごとの結果の行を出す (UI テストが、実際に動いたことの確認)。
- テスト: `ui_tests_gen_test.sh` (32 件)、`uitest_once_test.sh` (6 件)。

## [2.5.0] 2026-10-20 (UI テストの自動化。段階 1 と、段階 2 の WPF (UT15 / UT16 / UT19) は実機で確認済み。MFC (UT18) と、既存ソリューションへの後付け (UT17) も、2026-10-21 に実機で確認済み)

- **段階 2 — UI テストのひな形と Skill:**
  - **UI テストを Green のあとに実行させる指示を、強めた (UT19 の実機で、実行されなかったため):** `CLAUDE.md` の「UI テスト (FlaUI)」の節に、命令形で書く (`add_ui_tests.py` が書く。既存のソリューションは `--refresh-claude-md` で更新)。`wpf-test-first` / `cpp-test-first` の「Green へ引き渡す」にも追加。(UT19 の直接の原因は、Skill の再配布 (`install.sh --skills-only`) の忘れだった。)
  - **UI テストの流れ (ユーザーの決定 2026-10-21): UI テストファースト (UI テストを先に書く) は、しない。テスト先行 (Red) → ビルド → テスト (Green) の「あとに、追加で」、UI テストを実行する。** そのため、`ui-test-first` Skill は、作らない (作ってあったものを、削除)。UI テストの書き方・実行・失敗時のスクリーンショットの読み方は、`build-test-loop` の「UI テスト」に、まとめた。`add-feature` の検証 (全体) にも、「UI テストのプロジェクトがあれば、PASSED のあとに、`uitest_once.sh`」を追加。
  - `add_ui_tests.py` (既存のソリューションに `<アプリ名>.UITests` (MSTest + FlaUI.UIA3 5.0.0、`net8.0-windows`) を足す) は、`new-solution/scripts/` に置く (`UiTestBase` (起動・終了・失敗時のスクリーンショット)、`AppLocator`、`Screenshots` (PrintWindow)、ひな形のテスト)。
  - **`new-solution --ui-tests flaui`**: 作成と同時に、または、すでにあるソリューションに後付けで、足す。
  - **生成する WPF の View に、`AutomationProperties.AutomationId`** (`NameTextBox` / `GreetingText` / `ClearButton`) を付けた。
  - **`wpf-check` UI002** (warning): ソリューションに UI テストのプロジェクト (`*.UITests`) があるとき、操作できるコントロール (Button / TextBox など。テンプレート・スタイルの中は除く) に、AutomationId (または `x:Name`) がない。
  - **規約** (`rules/wpf-csharp.md`): UI テストの書き方を、テストの節と付録に追加。
  - テスト: `tests/ui_tests_gen_test.sh` (26 件)、`wpf_check_test.sh` に UI002 を追加 (76 件)。

- **UI テストの既定を、別のデスクトップ (`separate`) にした** (推奨に基づく。ユーザーの了承は、実機の確認後)。`WATCH_UI_DESKTOP=default` で、ユーザーのデスクトップに戻せる。
- **ウォッチャー: `-UiTestDesktop separate`** — UI テストを、**別のデスクトップ** (Win32 の `CreateDesktop`) で実行する。ユーザーの画面に、ウィンドウが出ず、フォーカスも奪わない (実行中に、マウス・キーボードを使っていてよい、を目指す)。`dotnet test` を、ジョブオブジェクト (`KILL_ON_JOB_CLOSE`) に入れ、終了後・時間切れのとき、テストが起動して残ったアプリを、すべて終了する。既定は `default` (従来どおり)。UIA / スクリーンショットが、別のデスクトップで動くかは、**実機の PoC で確認する** (TEST-PLAN UT9〜UT13)。

- **ウォッチャー (別のデスクトップ、PoC の実機で発見):** WPF を PrintWindow で撮ると、クライアント領域が白くなる (ハードウェアアクセラレーションの描画)。`-UiTestDesktop separate` のとき、UI テストの間だけ、HKCU `Avalon.Graphics` の `DisableHWAcceleration=1` を設定し、終わったら元に戻す。**元の値は、変更する前に、`%LOCALAPPDATA%\claude-watcher\wpf-hwaccel-backup.txt` に記録し、ウォッチャーが異常終了して記録が残っていたら、次の起動時に元に戻す** (ユーザーの提案)。
- **ウォッチャー (UT7 の実機で発見):** テストが制限時間を超えて強制終了されたとき、リダイレクト先の `test_stdout.tmp` を、子プロセス (テストが起動したアプリ) が開いたままで、**読み取りに失敗し、`TEST_TIMEOUT` でなく `ENV_ERROR` (`別のプロセスで使用されているため...`) になった**。出力の読み取りを、共有を許す方式に変更。UI テストが時間切れのとき、残ったアプリも終了する。(ウォッチャーが固まらないこと、時間切れで強制終了されることは、実機で確認済み。)

- **ウォッチャー:** `trigger_uitest.flag` を追加 (`docs/DESIGN.md` 4.29)。UI テストのプロジェクト (名前が `UITests` / `UiTests` で終わる、または FlaUI.* を参照) だけを実行し、通常のテスト (`trigger_test.flag`) からは除く。環境変数 `UITEST_*` でテストに実行環境を渡す。実行の前後に、ソリューションのフォルダの下の残ったアプリを終了する。`-UiTestTimeoutSec` (既定 600)。
- **`build-test-loop`:** `uitest_once.sh` を追加 (失敗時のスクリーンショットの一覧を出す)。`build_test_once.sh` は、環境変数 `BUILD_TEST_FLAG` でフラグ名を変えられる。
- **PoC (`poc/flaui/`):** 段階 1 の確認用に、環境変数のテストと、わざと失敗させるスイッチ (`UIPOC_FAIL=1`) を追加。

## [2.4.2] 2026-10-19

- **`wpf-check` LAY001:** ViewModel 層のプロジェクトの `UseWPF` / `UseWindowsForms` / `-windows` も、error にした (WS13 の実機で、検査の漏れを発見。ロジック・データ層だけが対象だった)。ViewModel のソースの WPF の型は、従来どおり LAY002 (warning)。

- **ウォッチャー (`watch_and_build.ps1`):** プロジェクトの一覧を、**起動時に 1 回だけ**読んでいたため、起動後に、テストプロジェクトを後付け (`new_solution.py --tests mstest`) すると、`no tests found` の `ENV_ERROR` になり、再起動が要った (WS8 / WS9 などで 4 回再現)。**トリガーごとに、`.slnx` / `.sln` を読み直す**ようにした (2026-10-20 実機で確認済み (WS21)。ホストへの再配置が要る)。

- **`build_once.sh` / `build_test_once.sh`:** 前回の `build_summary.json` / `test_summary.json` を、実行の最初に消す (U11 の実機で発見: ENV_ERROR / PASSED / SUCCESS では、JSON が更新されず、前回の失敗の内容が、今回の結果のように残った)。

- **`new-solution` (WPF) の修正 (WS19 の実機で発見):** 層の名前を変えた (`viewmodel:Std.Presentation`) とき、アプリの `App.xaml.cs` の `using` と、`MainWindow.xaml` の `xmlns:vm` が、**存在しない `<ルート>.ViewModels`** を指し、`CS0234` でビルドが通らなかった。ViewModel のプロジェクトがあるときは、その名前空間 (`layer_namespace`) を使う (`add_project.py` の `wpf_app_files`)。テスト (`new_solution_wpf_test.sh`) を足した。

- **`wpf-check` RES002:** 同じ辞書の中の `StaticResource` の前方参照を、warning から **error** に (W8 の実機で、起動時の `InvalidOperationException` を確認。説明文も訂正)。

- **`wpf-check` BND003:** setter なしの読み取り専用プロパティへの、`TextBox.Text` などの既定 TwoWay のバインドを、warning から **error** に (W4 の実機で、起動時の `InvalidOperationException` を確認)。setter が public でない場合は、warning のまま。

- **`add-package` (実機 P9 / P11 の結果):** (1) `vcpkg search` は、マニフェストモードでは `builtin-baseline` が要る → 手順に「先に `vcpkg baseline`」を明記。(2) fmt は MSVC で `/utf-8` を要求する (C2338) → `cpp_pkg.py` の `add` / `remove` / `setup` が、各 `.vcxproj` に `<ItemDefinitionGroup Label="VcpkgDefines">` で `FMT_UNICODE=0` を自動で入れる / 外す (`/utf-8` は CP932 のソースが文字化けするので使わない。ポート別の表は `PORT_DEFINES`)。

**Skill の本文だけの変更** (再配布が必要: `install/install.sh`)。スクリプトの変更はない。

- **`auto-build` / `build-test-loop`:** 「スクリプトは、この Skill のフォルダのものだけを使う。同名の古いコピーを、探して使わない。要約が出ないときは、まず、古い版を実行していないか確認する」を追加した。
  - **きっかけ (実機の確認 U7):** コンソールの Claude が、ホーム直下の古いコピー (`~/cpp-build-test-loop/scripts/build_test_once.sh`、10/12 の版) を実行し、失敗の要約 (`[ran N: ...]`) と `test_summary.json` が出ないのを、「ツールの不具合」と記録した。**現行の配布版は、実機の trx を使った検証で、期待どおりの要約と JSON を出す** (古いコピーは、要約の処理を持たない)。古いコピーは、ホーム直下の `cpp-auto-build/` と `cpp-build-test-loop/` に残っている (ユーザーが、退避する)。
- **`add-package`:** 「C++ の NuGet は、対象外 (`packages.config` も、VS 2026 の `PackageReference` (Experimental) も)。C++ は vcpkg」を、明記した。
  - **決定 (ユーザー、2026-10-19):** VS 2026 の「C++ の NuGet PackageReference」(`EnableNativePackageReferenceSupport`。公式の記事 2026-05-19) は、**Experimental なので、対応を見送る**。手元の VS 2026 (18.8.1) と公式の記事で、仕組みは確認した (DESIGN 4.26 の調査メモ)。再開の条件も、同じ場所に記録。
- 手順書: U4 / U5 / U6b / WS5 を ✔ (2026-10-19 実機)。P22 を ✔ (公式の記事で確認)。P23 / P24 を、見送り。U7 は △ (上の原因)。U8 は △ (MSTest の実機の trx を、解釈できることを確認)。

## [2.4.1] 2026-10-18

**実機 (WPF + MSTest の最初の実行) で見つかった、ホスト側の不具合を 2 つ直した。** 設計: `docs/DESIGN.md` 4.24 の末尾。契約 (ファイル名・結果の値・終了コード) の変更は、ない。**ホスト側ツールの再配布が必要** (3 ファイルをまとめて。ウォッチャーは、起動し直す)。修正は、実機で、まだ確認していない (TEST-PLAN の U6b / U6c)。

- **文字化け:** `dotnet test` の出力 (UTF-8) を、ANSI (CP932) として読んでいたため、日本語が化けていた (`縺ｮ繝・せ繝・`)。**`Read-ProcessOutput`** を追加: 出力をバイト列で読み、UTF-8 として厳密に解釈し、できなければ ANSI として解釈する (BOM は除く)。GoogleTest の出力 (ANSI) も、そのまま読める。構造化された結果 (trx / XML) は、影響を受けていない。
- **テストが実行されなかった (`bin\auto\Debug` で DLL が見つからない):** `run_watcher.cmd` の cmd 変数 `PLATFORM` (= `auto`) が、環境変数 `Platform` として子プロセスに継承され、MSBuild がプロパティとして読んでいた (`dotnet test --no-build` だけが影響を受けた。ビルドは `/p:Platform` を明示するので、無事だった)。**`watch_and_build.ps1` が、起動時に環境変数 `Platform` を削除する。`run_watcher.cmd` の変数名を `WATCH_PLATFORM` / `WATCH_CONFIG` に変えた** (CP932 のまま)。
- 手順書に、U6b (文字化け) と U6c (環境変数の漏れ) を追加。

## [2.4.0] 2026-10-18

**WPF プログラミング規約を適用した。** ユーザーが示した規約 (19 章) で、`rules/wpf-csharp.md` を置き換え、生成物と `wpf-check` を、規約に合わせた。設計: `docs/DESIGN.md` 4.28。契約 (ファイル名・結果の値・終了コード) の変更は、ない。ホスト側ツールの変更も、ない。

**生成した C# / XAML は、まだ、コンパイルしていない** (4.27 と同じ)。**`App.OnStartup` で画面を作る形と、`Resources/Styles.xaml` の結合は、実機で確認が要る** (TEST-PLAN の WS17 / WS18)。

### 規約 (再配布が必要: `install/install.sh`。既存の `~/.claude/rules/wpf-csharp.md` は、バックアップ (`~1~`) が残る)
- **`rules/wpf-csharp.md`:** ユーザーの規約の章立て (1〜19 章: 適用範囲、基本方針、ソリューション構成 3.1 / 3.2、命名、C#、View、ViewModel、MVVM ライブラリの選択 (Toolkit / Prism)、バインディング、非同期、DI、例外、ログ、XAML、コメント、テスト、禁止事項、レビュー確認項目、最終方針) に、全面的に置き換えた。このツール群で追加した決まり (ファイルの形式、書式、`obj/` の編集禁止、`add-package`、MSTest の書き方、層のモデル) は、各章の「ツール群の補足」に残した。**規約と食い違う場合は、規約を優先する。** 末尾に、**規則と、ツール (`wpf-check` のコード) の対応表** (付録)。
- **差異を、補足に明記した:** テストは、ツール群が検証しているのは MSTest だけ (xUnit / NUnit は、未検証)。生成される構成は、アプリ + ライブラリの層 + ライブラリごとのテスト (規約 3.2 に近い)。**層の依存のモデルは、名前で 2 つに分かれる (混ぜない)。**

### Skill (再配布が必要)
- **`new-solution --type wpf` の生成物を、規約に合わせた:**
  - アプリの構成 (3.1): `App.xaml(.cs)` / **`Views/`** (`MainWindow`。名前空間 `<ルート>.Views`) / `ViewModels/` (`viewmodel` 層がないとき) / **`Resources/Styles.xaml`** (`DefaultControlMargin` / `PrimaryButtonStyle`。`App.xaml` の `MergedDictionaries` で結合)。
  - **`DataContext` の設定を、`App.xaml.cs` の `OnStartup` (composition root) に移した** (`StartupUri` を、やめた。`MainWindow` のコードビハインドは、`InitializeComponent()` だけ)。
  - 画面は `Grid` (`Auto` / `*`、`MinWidth` / `MinHeight`)、バインディングは `Mode` を明示 (TwoWay / OneWay)。
  - **`.` 区切りのプロジェクト名** (`SampleApp.Domain` など。規約 3.2 の名前) に対応 (`new-solution --layers data:SampleApp.Domain,...`、`add_project.py`)。名前空間は、その名前のまま。型名では `.` を除く。`CLAUDE.md` の雛形に、アプリの構成と、規約の場所を追記。
- **`wpf-check`:** **標準の層** (名前が `Presentation` / `Application` / `Domain` / `Infrastructure` で終わるプロジェクト) は、規約 3.2 の依存 (Presentation → Application → Domain、Infrastructure → Application / Domain。Domain は、何も参照しない。Domain / Application / Infrastructure は WPF に依存しない) で検査する (LAY001 / LAY003)。`--logic` / `--data` / `--viewmodel` の明示は、名前による推定より優先する。
  - **新しい検査 (すべて warning):** DI001 (ViewModel 内の `new XxxService()` など)、ASY001 (`.Result` / `.Wait()` / `GetAwaiter().GetResult()`)、ASY002 (イベントハンドラ以外の `async void`)、EXC001 (空の `catch`)、EXC002 (`throw ex;`)、NAM001 (bool の `Flag` / `Status` / `Check`)、UI003 (UserControl が自分自身を `DataContext` にする)。**LAY002 を拡張** (`OpenFileDialog` / `SaveFileDialog` / `Clipboard` / `.ShowDialog()` / `Views` の名前空間)。
  - **機械で判定できない項目は、検査しない** (責務の分離の妥当性、メソッドの大きさ、コメントの質など)。**通ったことは、規約を満たすことを、意味しない。**
- `wpf-test-first/PROJECT-LAYOUT.md`: アプリの構成 (3.1)、composition root、規約 3.2 の名前を追記。`new-solution` / `wpf-check` の `SKILL.md` を更新。

### テスト・文書
- `tests/wpf_check_test.sh` を 47 → **72 項目** (新しい検査と、誤検出しない形、標準の層)、`tests/new_solution_wpf_test.sh` を 51 → **59 項目** (規約の構成、composition root、`Grid`、`Mode`、`.` 区切りの名前)。`docs/DESIGN.md` に 4.28、`docs/TEST-PLAN.md` に WS17〜WS20。

## [2.3.0] 2026-10-18

**WPF のソリューションの生成 (`new-solution --type wpf`)、テスト先行 (`wpf-test-first`)、規約 (`rules/wpf-csharp.md`) を追加。** C++ / MFC で作った一式を、WPF でも同じ流れで使えるようにする。設計: `docs/DESIGN.md` 4.27。

**生成した C# / XAML は、まだ、コンパイルしていない** (WSL に .NET がない。手で読んで確認し、`wpf-check` にかけて、指摘 0 件を確認した)。**MSTest の既定のバージョン (Test.Sdk 17.12.0、MSTest 3.6.4) が、nuget.org に実在することも、未確認。** 配布前に、`docs/TEST-PLAN.md` の 2-4 (**WS6 → WS2 → WS3 の順**) を、実機で確認する。契約 (ファイル名・結果の値・終了コード) の変更は、ない。ホスト側ツールの変更も、ない。

### Skill (再配布が必要: `install/install.sh`)
- **`new-solution`:** `--type wpf` を追加 (WPF、MVVM。.NET)。
  - **構成: View (WPF アプリ) → ViewModel → ロジック → データ。** 層は、`--layers` に `data` / `logic` / `viewmodel` を、組み合わせる (既定の名前 `DataLayer` / `LogicLayer` / `ViewModels`)。**層は、WPF 非依存のクラスライブラリ** (`net8.0`。ViewModel が `System.Windows` を、使えないことを、型で強制する)。`viewmodel` を作らないと、ViewModel は、アプリの `ViewModels/` フォルダ (テストできない)。
  - **`--tests mstest`:** 層のライブラリごとに `<名前>.Tests` (MSTest v3: `Microsoft.NET.Test.Sdk` + `MSTest.TestAdapter` + `MSTest.TestFramework`)。View は、テストしない。層がないと、エラー。`--tests gtest` と、C++ 用の引数 (`--layer-kind` / `--gtest` / `--toolset`) は、エラー。
  - 追加の引数: `--tfm` (既定 `net8.0`)、`--mstest-version`、`--testsdk-version`。**テストの後付け:** すでにある .NET のソリューションで `--tests mstest`。`--spec` は、`wpf` / `mstest` / `viewmodel` を読む。
  - 作るもの: `.slnx` (構成なし。アプリに `DefaultStartup`)、SDK 形式の `.csproj`、`Directory.Build.props` (`Nullable` / `ImplicitUsings` / `LangVersion`)、`.editorconfig`、サンプル (`MainWindow` と `MainViewModel`。自前の最小実装の `ObservableObject` / `RelayCommand`。NuGet 不要)、`CLAUDE.md` (`- テスト: あり (MSTest)`) / `.gitignore` / `.gitattributes`。
  - **C++ の経路は、変えていない** (`parse_layers` に、引数を足しただけ。WPF のコードは、`--type wpf` / `--tests mstest` のときだけ、読み込む)。
- **`wpf-test-first` を追加:** `cpp-test-first` の骨格 (ゲート・正しい Red の条件・ループの規則・完了時の報告) を、WPF に移した。WPF 固有: スタブは `NotImplementedException` にしない (例外で落ちるので、Red ではない)、ViewModel のスタブは通知を上げない、`.csproj` への追加は不要 (SDK 形式)、**View は、テストしない** (ViewModel への切り出し案を示して止まる)、実装のあとに `wpf-check`、パッケージは `add-package`。
  - `PROJECT-LAYOUT.md` (構成と規約、`.sln` / `.slnx`、よくある失敗)。
  - `scripts/add_project.py`: クラスライブラリ + `<名前>.Tests` を、**`.slnx` と、Visual Studio 形式の `.sln` の両方**に追加する (`.sln` は、プロジェクトの種類の GUID と、構成の対応付け (ソリューションの構成 → プロジェクトの `Any CPU`) も足す)。`--kind lib|data|logic|viewmodel`、`--tests-only`、`--uses`、`--dry-run`。既存は、上書きしない (rc=3)。
- **`add-feature` / `update-from-ideas`:** WPF に対応 (`CLAUDE.md` の `- メイン:` / `- テスト:` で、`cpp-test-first` と `wpf-test-first` を選ぶ。構成案の値に `wpf` / `mstest` / `viewmodel` を追加。**WPF か MFC かは、ユーザーが決める**)。

### 規約・ひな形 (新規)
- **`rules/wpf-csharp.md`** (ユーザー共通。`paths` は `**/*.cs` `**/*.xaml` `**/*.csproj`): C++ の規約 (`cpp-mfc.md`) と同じ方針の項目はそろえ (UTF-8 BOM + CRLF、Allman、コメントは日本語)、.NET の慣習の項目は合わせた (定数は PascalCase、private フィールドは `_camelCase`、`Async` の接尾辞)。**WPF 固有:** 層と MVVM (View に業務ルールを書かない、ViewModel は WPF の型を使わない、`INotifyPropertyChanged`、`ObservableCollection`、コマンド、`DataContext` の設定と `d:DataContext`、バインディングの綴り、リソースの順序、UI スレッド)、例外とリソース、MSTest の書き方 (命名、AAA、期待値の順、フェイク、`[Ignore]` の禁止)。**`wpf-check` の検査項目と、対応させた。**
- **`templates/dotnet/`:** `.editorconfig` (Allman、ファイルスコープの名前空間、命名、`utf-8-bom` (`.slnx` / `.json` / `.md` は BOM なし)) と `Directory.Build.props`。**生成の定数と同じ内容** (テストで一致を確認)。
- **`install/install.sh`:** 規約を `~/.claude/rules`、ひな形を `~/.claude/templates` に配る (`--rules-dir` / `--templates-dir` / `--rules-only`)。**既存のファイルは、上書きせず、番号付きのバックアップ (`~1~`) を残す** (同じ内容なら、何もしない)。先頭が `.` のファイルも、配る。

### ツール・文書
- `tests/add_project_test.sh` (24 項目)、`tests/new_solution_wpf_test.sh` (51 項目。**生成物が `wpf-check` で指摘 0 件**を、4 つの形で確認)。
- `docs/DESIGN.md` 4.27 (方針、層を、WPF 非依存のライブラリにする理由、MVVM の基底を自前にした理由、MSTest の参照と版、取り下げた案、検証の範囲)。`docs/TEST-PLAN.md` に 2-4 (WS1〜WS16)。`README.md` を更新。`.gitattributes` に、`templates/` `rules/` `tests/fixtures/`。

## [2.2.0] 2026-10-18

**パッケージの追加 (NuGet / vcpkg / ソースの取り込み) を、ホスト側に実行させる。** WSL からは、NuGet も vcpkg も、実行できないため。設計: `docs/DESIGN.md` 4.26。

**Windows 側 (`watch_and_build.ps1` の、パッケージの操作) は、実機で未検証。** WSL のサンドボックスから PowerShell を実行できない (括弧の対応のみ確認)。vcpkg のマニフェストモードと MSBuild の連携 (`vcpkg.json` を探す場所、`Label="Vcpkg"` の効き方) も、実機で未確認。**配布前に、`docs/TEST-PLAN.md` の 1-6 (P1 から) を、実機で確認する。**

### 契約の追加 (後方互換。既存のファイル名・結果の値・終了コードは、変えていない)
- `trigger_package.flag` (Claude): 各行が 1 操作 (`nuget search/versions/add/remove`、`vcpkg search/baseline/install`、`fetch`)。上から順に実行し、最初の失敗で止まる。
- `package_output.txt` / `package_error.log` / `package_result.txt` (ウォッチャー): 出力 / 失敗時のみ (環境の問題は、先頭が `[ENVIRONMENT ERROR ...]`) / 完了マーカー `OK` / `FAILED` (最後に書く)。
- ビルド・テスト・gtest 取得とは独立。**ビルドより先に処理される。**

### ホスト側ツール (再配布が必要。3 ファイルをまとめて)
- `watch_and_build.ps1`: パッケージの操作を追加。
  - **引数は、決まった文字だけを許可して、検証する** (ID・語・リポジトリ・タグ・名前・バージョン。`-` 始まりは拒否。プロジェクトは、ソリューションの下の、存在する `.csproj` などに限る)。
  - `nuget search` / `versions` は、nuget.org の REST API (ダウンロード数と `verified` も出す)。`nuget add` / `remove` は、`dotnet add / remove package` (結果のバージョンを、`.csproj` / `Directory.Packages.props` から読んで返す)。`NU1101` (名前の誤り) は、環境エラーにしない。
  - `vcpkg search / baseline / install`: VS 同梱の vcpkg (`VC\vcpkg\vcpkg.exe`。`-VcpkgExe` → `VCPKG_ROOT` → `vswhere` の順) を使う。トリプレットは、Platform から (既定 `x64-windows-static-md`)。
  - `fetch <owner/repo> <タグ> <名前> [<サブフォルダ>]`: GitHub のタグのソースを、`ThirdParty\<名前>\` に置く (GoogleTest の取得と、同じ構造。**GoogleTest の取得は、そのまま**)。
  - 新しい引数: `-PackageTimeoutSec` (既定 1800)、`-VcpkgExe`、`-VcpkgTriplet`。`Invoke-TestProcess` に、制限時間の引数を追加 (既定は、従来どおり)。

### Skill (再配布が必要: `install/install.sh`)
- **`add-package` を追加:** どの方法を使うかの判断 (NuGet / vcpkg / `fetch`。**GoogleTest は対象外**)、共通のルール (追加する前に、実在とバージョンを確認する。名指しされた名前だけを追加する。バージョンを固定する)、各手順、完了時の報告 (変更したファイル・バージョン。`git commit` はしない)。
  - `scripts/package_once.sh`: フラグを置いて、完了を待つ。**操作の形を、フラグを置く前に、検証する** (ウォッチャーと同じ規則。多重の防御)。`--file` (`ThirdParty.manifest` の再現)、`--timeout`。1 行目と終了コード: `OK` 0 / `FAILED` 1 / `BAD_ARGS` 2 / `WATCHER_NOT_RUNNING` 3 / `ENV_ERROR` 4 / `TIMEOUT` 5。
  - `scripts/cpp_pkg.py` (WSL で完結。ネットワーク不要): `setup` (`vcpkg.json` と、各 `.vcxproj` の `Label="Vcpkg"` (マニフェストモード + プラットフォーム別トリプレット)。gtest を除く。冪等。BOM・改行・インデントを保つ)、`add` / `remove` / `list` (`vcpkg.json`)、`include-dir` (全構成の `AdditionalIncludeDirectories`)、`record-fetch` (`ThirdParty.manifest` と `.gitignore`)。
- `auto-build`: ライブラリの不足が原因のエラー (`C1083` / 外部の `LNK2019` / `CS0246` / `NU1101`) は、`.csproj` / `.vcxproj` を、自分で書き換えず、`add-package` で追加する、という規則を追加。

### ガード・文書
- `docs/RECOMMENDED-SETTINGS.md`: **`add-package` の `permissions.ask`** (`Bash(*package_once.sh*)`、`Bash(*cpp_pkg.py*)`、`Edit(**/vcpkg.json)`、`Edit(**/*.vcxproj)`、`Edit(**/ThirdParty.manifest)`)。供給網への入口になるため。`cpp_pkg.py` は別のプロセスが書くので、`Edit` のルールが効かず、`Bash` にも `ask` が要る。**実機での確認は、未実施。**
- `docs/DESIGN.md` 4.26 (方針、引数の検証、取り違えへの対策、vcpkg の採用理由とトリプレット、**取り下げた案**、検証の範囲)。`docs/TEST-PLAN.md` に 1-6 (P1〜P21)。`README.md` / `host-tools/README.md` を更新。`.gitignore` に、新しい生成ファイル。

### テスト
- `tests/package_once_test.sh` (41 項目: 疑似ウォッチャー。操作の検証 (注入・`..`・絶対パス・`-` 始まりなど 17 種類を拒否)、結果の分岐、古い結果の除去、`--file`、出力の上限)、`tests/cpp_pkg_test.sh` (35 項目: 疑似の `.vcxproj`。BOM と CRLF の保持、冪等、XML の整合)。

## [2.1.0] 2026-10-18

### Skill (再配布が必要: `install/install.sh`)
- **`wpf-check` を追加 (独立した Skill。手動で実行する。ウォッチャーも Windows も .NET も不要。読み取りだけ):** WPF の「コンパイルは通るが、実行時に壊れる」部分を、静的に検査する (`scripts/wpf_check.py`)。`mfc-check` と同じ形 (出力・`--all` / `--json` / `--max-lines`・終了コード 0 / 1 / 2 / 3)。設計: `docs/DESIGN.md` 4.25。
  - **バインディング (BND / CMD):** `{Binding}` のパスが、DataContext の型にない (綴りの近い候補を添える)、public フィールド・メソッド・非 public・static へのバインド、読み取り専用プロパティへの TwoWay、`INotifyPropertyChanged` の未実装、`Command` に `ICommand` でない型。DataContext の型は、XAML の `DataContext` / `<X.DataContext>` / `DataTemplate` の `DataType` / code-behind の `DataContext = new Xxx()` / `= this` / コンストラクター引数 / `GetService<Xxx>()` / ウィンドウを作るコードから推定する。**基底クラスが外部 (`Window` や未知のクラス) の型は、「ない」と言わない** (`--all` の BND900)。`d:DataContext` だけが根拠なら warning。CommunityToolkit.Mvvm の `[ObservableProperty]` / `[RelayCommand]` が作るメンバーを知っている。
  - **リソース (RES / CNV):** `StaticResource` の未定義・同じ辞書の後ろで定義 (前方参照)、`x:Key` の重複、`DynamicResource` の未定義、結合した辞書の `Source` が見つからない、`Converter` が `IValueConverter` を実装していない。祖先の `Resources` → `App.xaml` の辞書の順に厳密に辿る。外部の辞書 (NuGet のテーマなど) やライブラリの XAML は、error を warning に下げる。コードから足されるキー (`Resources["X"] = ...`) は知っている。
  - **起動 (UI / APP):** code-behind のコンストラクターが `InitializeComponent()` を呼んでいない (例外も出ず、画面が空になる)、`StartupUri` が見つからない。
  - **層 (LAY):** ロジック層・データ層の WPF 依存 (`UseWPF` / `-windows` / `System.Windows` / `MessageBox`)、ViewModel の View 型の使用 (warning)、プロジェクト参照の向き (View → ViewModel → ロジック → データ)。`--logic` / `--data` / `--viewmodel` で層を指定できる。
  - **対象外:** コンパイルエラーになるもの (イベントハンドラの不足、`x:Name` の重複、XAML の文法)。ビルドが `MC` / `XDG` / `CS` で教える。
  - 実装: XAML は expat で読み (行番号・属性の順序・名前空間・属性の行)、C# は軽い字句解析 (コメント・文字列・raw 文字列を除き、型・メンバー・基底クラス・コンストラクターを取り出す)。
- **契約 (ファイル名・結果の値・終了コード) の変更は、ない。** ホスト側ツールの変更も、ない。

### ツール・文書
- `tests/wpf_check_test.sh` を追加 (47 項目。**正常なプロジェクトに指摘が出ないこと**と、不具合を 1 か所ずつ入れたときの各コード、BOM + CRLF の行番号、出力の上限、終了コード、読み取り専用)。
- `docs/DESIGN.md` に 4.25、`docs/TEST-PLAN.md` に 2-3 (W1〜W12) を追加。**実プロジェクトでは、まだ検証していない。** `mfc-check` の経験から、実プロジェクトで誤検出が見つかる可能性が高い (W1 を最初に)。
- BND003 (読み取り専用への TwoWay が、実行時に例外になるか)、RES002 (前方参照が、実行時に失敗するか) の、実際の動作は、未確認 (W4 / W8)。

## [2.0.0] 2026-10-18

**C++ と .NET (WPF + MSTest) の統合。** 1 つのウォッチャーと 1 組の Skill で、C++ のみ、.NET のみ、混在のソリューションを扱う (設計: `docs/DESIGN.md` 4.24)。

**Windows 側 (`watch_and_build.ps1` / `build-windows.cmd` / `run_watcher.cmd`) の変更は、実機で未検証。** WSL のサンドボックスから PowerShell を実行できなかったため、括弧の対応と、CP932 の `rem` 行の確認だけ行った。**配布前に、`docs/TEST-PLAN.md` の 1-5 (U1 の、C++ の回帰から) を、実機で確認する。**

### Skill の名前の変更 (配り直しと、旧名の削除が必要: `install/install.sh`)
- `cpp-auto-build` → **`auto-build`**、`cpp-build-test-loop` → **`build-test-loop`**。技術名を外した。**旧名の Skill が配布先に残ると、description が重なるので、手で削除する** (`install.sh` が、残っていれば知らせる)。`cpp-test-first` / `mfc-check` / `new-solution` は、変更なし。
- 両 Skill の本文を、.NET に対応させた: XAML / C# / NuGet / SDK のエラーコードの読み方、`obj/` の生成物 (`*.g.cs`) を直接編集しない、警告の抑制 (`#pragma warning disable` / `NoWarn` / `TreatWarningsAsErrors` の解除) でビルドを通さない、`.csproj` などの変更は最小限で報告する、MSTest での禁止事項 (`[Ignore]` / `Assert.Inconclusive` / `.runsettings` で外す / アサーションを弱める / `[Timeout]` の延長)、完了時の報告のテストファイルに `*Tests/` / `*Tests.cs` を追加。

### テスト結果の共通の形式
- **`summarize_test_log.py` が、GoogleTest の XML と MSTest の trx を、共通の形式に変換して集約する** (`--results-dir`、`--root`)。同じメッセージの失敗は、フレームワークをまたいで、1 つにまとまる。見出しに `[ran N: passed / failed / skipped]`。構造化された結果がなければ、従来のテキスト解釈に戻る。クラッシュの報告 (`(no gtest failure lines ...)`、`Hung test`) は、`other:` に併記する。壊れた XML は、`other:` に残し、読めるものは使う。
- **`test_summary.json` は schema 2** (`schema` / `structured` / `totals` / `sources` を追加。**従来のキー `failed` / `groups` / `tests` / `other` は、そのまま**)。
- `build_test_once.sh` が、`.claude-logs/test-results/` を、`--results-dir` に渡す。フラグを置く前に、前回の結果を消す。
- `summarize_build_log.py` (2 つの Skill のコピー): 診断コードの接頭辞を、1〜4 文字から **1〜8 文字**に広げた (`NETSDK1045` / `MSTEST0037` が、`other:` に落ちていた)。

### ホスト側ツール (再配布が必要。3 ファイルをまとめて)
- **契約の追加 (後方互換):** `.claude-logs/test-results/` (`<exe名>.xml`、`<プロジェクト名>.trx`)。**既存のファイル名・結果の値・終了コードの意味は、変えていない。** `ENV_ERROR` の意味を広げた (テストが見つからない (C++ も .NET も)、`dotnet` がない、.NET のテストが 1 件も実行されない)。
- `watch_and_build.ps1`:
  - ソリューションの中身 (`.vcxproj` / `.csproj` / `.vbproj` / `.fsproj`) を判定する。`-Platform` の既定が **`auto`** (C++ があれば `x64`、.NET だけなら `AnyCPU`)。`AnyCPU` を追加。
  - `build-windows.cmd` に、第 6 引数 `Features` (`cpp` / `restore`) を渡す。判定できなければ、従来どおり `cpp`。
  - GoogleTest の exe に `--gtest_output=xml:` を足す。.NET のテストプロジェクト (`Microsoft.NET.Test.Sdk` / `MSTest` を参照、`IsTestProject`、名前が `Test(s)` で終わる) を、`dotnet test --no-build --logger trx` で実行する。両方ある場合は両方を実行し、結果は 1 つの `test_result.txt`。trx の `executed` が 0 なら `ENV_ERROR`。
  - .NET の環境エラー (`MSB4236` `NETSDK1045` `NETSDK1141` `NU1301`) を、`[ENVIRONMENT ERROR ...]` にする。`NU1101` は、ソースの問題として、そのまま。
  - 新しい引数: `-DotnetTestArgs`、`-DotnetExe`。起動時のヘッダーに、`Solution` (種類) と `dotnet test` の行を追加。
- `build-windows.cmd`: 第 6 引数 `Features`。`cpp` がなければ、VS の要求が MSBuild だけになり、`cl.exe` の確認もしない。`restore` で `/restore` (`Clean` では付けない)。`AnyCPU` (MSBuild には `Any CPU`)。**`Features` を省略した呼び出しは、従来と同じ動作** (`/p:Platform` を、引用符で囲む点だけが違う)。
- `run_watcher.cmd`: Platform の既定を `auto` に。

### ガード・文書
- `docs/RECOMMENDED-SETTINGS.md`: **.NET を含むプロジェクトの `permissions`** を追加。`ask`: `*Tests/**` `*.Tests/**` `*Tests.cs` `*Test.cs` (C++ 用の `*Test/**` は `MyApp.Tests/` に一致しないため)、`*.csproj` `Directory.Build.props` `Directory.Packages.props` `global.json` `*.runsettings`。`deny`: `obj/` `bin/` `*.g.cs` `*.g.i.cs` `packages.lock.json`。**実機での確認は、未実施。**
- `docs/DESIGN.md`: 4.24 (統合の方針、判定、テストの実行、共通の形式、**採らなかった案** (C++ のテストを `CppUnitTestFramework` に移す、`dotnet build` へのフォールバック)、検証の範囲)。契約の表、4.11、6 章を更新。`docs/TEST-PLAN.md`: 1-5 (U1〜U16) を追加。`README.md` / `host-tools/README.md` を更新。
- `install/install.sh`: 旧名の Skill が残っていれば、知らせる。

### テスト
- `tests/fixtures/` (GoogleTest の XML、MSTest の trx。**仕様から書いたサンプル。実機の出力で差し替える: TEST-PLAN の U8**) を追加。`tests/summarize_test_log_test.sh` を 15 → 34 項目、`tests/summarize_build_log_test.sh` を 20 → 26 項目 (.NET の診断コード)、`tests/fake_watcher_test.sh` に、構造化された結果の経路と、前回の結果が消えることを追加。

## [1.6.0] 2026-10-18

### Skill (再配布が必要: `install/install.sh`)
- **`/new-solution` に、メインの種類を 2 つ追加:** `--type mfc-mdi` (MFC MDI: `CMultiDocTemplate`・`CMDIFrameWnd`・`CMDIChildWnd`、`Window` メニュー付き) と、`--type mfc-dialog` (MFC ダイアログベース: `CDialog` 派生、`DoModal`、`IDD_SAMPLE_DIALOG` に OK / Cancel と静的テキスト)。`--type mfc` は、従来どおり SDI。層・テスト・GoogleTest の指定は、どの種類でも、同じ。
  - 生成物は、`mfc-check` で、error / warning 0 (`tests/new_solution_test.sh` で確認)。`--spec` の構成案 (`- メインの種類: mfc-mdi`) からも、読める。
  - 名前が `Test` で終わるときの出力名の変更 (`<名前>_Main`) は、新しい種類にも、効く。
- **生成する `.slnx` で、メイン (exe) に `DefaultStartup="true"` を付ける:** 層 (DLL) があると、Visual Studio が、スタートアッププロジェクトに、DLL (`DataLayer` など) を選び、F5 が「有効な Win32 アプリケーションではありません」で、失敗した (`MfcDlgLayers` の実機の確認で発見。`.slnx` で exe を先頭に置いても、効かなかった)。最初に開くときは、メインが選ばれる。個人の設定 (`.vs/` の `.suo`) が、すでにあれば、そちらが優先される。あわせて、生成する `CLAUDE.md` と、`/new-solution` の完了報告に、その旨と、選び直す手順を追加した。
- **実機の確認:** MFC の SDI / MDI / ダイアログベースの、三層 (層 2 つ、テストなし) を、ウォッチャー経由でビルドして、`SUCCESS`。
- **契約 (ファイル名・結果の値・終了コード) の変更は、ない。**

## [1.5.0] 2026-10-17

### Skill (再配布が必要: `install/install.sh`)
- **`mfc-check` を追加 (独立した Skill。手動で実行する。ウォッチャーも Windows も不要。読み取りだけ):** MFC の「コンパイルは通るが、実行時に壊れる」部分を、静的に検査する (`scripts/mfc_check.py`)。
  - **リソース (RES):** 未定義 ID、コマンド ID / 同じダイアログ内のコントロール ID / 同じ種類のリソースの、値の重複、`resource.h` の未使用 ID。リソース定義の名前だけが未定義の場合は、名前付きリソースとして、warning にする (RC は受け付けるため)。
  - **メッセージマップ (MAP):** ハンドラの宣言・定義の有無、`DECLARE_MESSAGE_MAP` と `BEGIN_MESSAGE_MAP` の対応、`afx_msg` の孤立、引数の数、ID の重複。
  - **UI との対応 (UI):** `ON_COMMAND` の ID が `.rc` のメニュー・アクセラレータ・ツールバーにあるか、コントロール通知・`DDX` の ID が `.rc` のダイアログにあるか。
  - **ダイアログ (DLG):** `DDX` / `DDV` の ID が、**そのクラスのダイアログ** (`IDD`) にあるか、`IDD` が `.rc` に DIALOG としてあるか、`DDX_Control` のメンバーの型がコントロールの種類と合うか (`EDITTEXT` に `CListCtrl` など)、ボタンにハンドラがあるか、既定ボタンが複数でないか、`OnInitDialog` / `DoDataExchange` が基底を呼んでいるか、ニーモニックの重複 (info)。ダイアログの ID は、`enum { IDD = ... }` か、コンストラクタの基底の初期化から読む。
  - **層の依存 (LAY):** ライブラリ (DLL / lib) での GUI のクラス・ヘッダーの使用、プロジェクト参照の向き (UI → ロジック → データ)。
  - **ダイアログ (DLG010):** 同じメンバーを、別の ID に対して、複数の `DDX_Control` に渡している (warning)。MFC の `DDX_Control` は、接続済みのメンバーを探さないので、2 回目以降は、実行時に、何も起きない (コピー&ペーストの誤りに多い)。実機の確認で見つけた。`else` / `case` / `default` をまたぐ呼び出しは、除く。
  - **ダイアログ (DLG009):** `AFX_DIALOG_LAYOUT` が、存在しないダイアログのもの (VS が残した不要な定義。info)。
  - **実プロジェクト (`DoubleBufferSample`) での検証で、誤検出を 4 種類修正:** 継承したハンドラ、宣言の末尾の `final` / `override`、入れ子のクラスのメッセージマップ (`BEGIN_MESSAGE_MAP(Outer::Inner, ...)`)、`AFX_DIALOG_LAYOUT` / `DESIGNINFO` の扱い。`ON_WM_CTLCOLOR_REFLECT` のハンドラ名 (`CtlColor`) も、直した。
  - **`.rc` は UTF-16 (BOM)・UTF-8・CP932 のどれでも読める** (ウィザード生成の `.rc` は UTF-16。`grep` では読めない)。出力は、ビルドの要約と同じ形式 (重大度順、最大 40 行、`--json`)。終了コード: 0 / 1 (error あり) / 2 / 3 (対象なし)。
  - 標準 ID は、`afxres.h` を読まず、接頭辞で判定する。基底クラスのハンドラ (`&CWinApp::OnFileNew`) は、宣言・定義の検査から外す。
- **契約 (ファイル名・結果の値・終了コード) の変更は、ない。** 既存の Skill とホスト側ツールは、変更していない。

### ツール・文書
- `tests/mfc_check_test.sh` を追加 (疑似プロジェクトで、全ルールの検出と、正常なプロジェクトの誤検出のなさ、層の依存、例外系、実プロジェクトでクラッシュしないこと。ダイアログの正常 / 異常のケースと、実プロジェクトで見つけた誤検出の再発防止を含む。69 項目。実プロジェクトのソースに、未コミットの変更がある間は、`error 0` の確認を、クラッシュしないことの確認に、切り替える)。
- `docs/DESIGN.md` に 4.23、`docs/TEST-PLAN.md` に K1〜K11 を追加 (実機の確認手順は、`DoubleBufferSample` の具体的な行で書いてある)。

## [1.4.1] 2026-10-15

### Skill (再配布が必要: `install/install.sh`)
- **ビルドエラーの要約 (`summarize_build_log.py`) を追加:** `cpp-auto-build` の `FAILED` と、`cpp-build-test-loop` の `BUILD_FAILED` で、`build_error.log` の先頭 40 行をそのまま出す代わりに、集約した要約を出す。
  - 同じ (コード, メッセージ) を 1 つにまとめ、件数 (`xN`) と代表の場所 (最大 3 つ) を出す。最初に出たエラー順 (連鎖エラーの原因は先頭側)。
  - 見出しに、総数・種類数・ファイル数・コンパイル/リンクの内訳。解釈できない行は、最大 5 行を `other:` として残す。出力は最大 40 行・1 行 400 文字。
  - 同じ内容を `.claude-logs/build_summary.json` にも書く (`.gitignore` 済み)。
  - `python3` がない場合や、解釈できるエラー行がない場合は、従来の生ログ表示に戻る。`ENV_ERROR` は従来どおり生ログ。
  - スクリプトは、2 つの Skill に同一のコピーを置く (`tests/summarize_build_log_test.sh` で一致を確認)。
- **テスト失敗の要約 (`summarize_test_log.py`) を追加 (`cpp-build-test-loop` のみ):** `FAILED` で、`test_error.log` の生の詳細の代わりに、集約した要約を出す。
  - **同じメッセージの失敗を 1 つにまとめる** (`xN`、テスト名は最大 5、場所は最大 3、出現順)。見出しに、失敗数とスイートごとの件数。`Expected` / `Which is` は `|` で区切って 1 行に。
  - 解釈できない行 (クラッシュの報告など) は、最大 8 行を `other:` に残す。全テスト名と、テストごとの場所・メッセージは、`.claude-logs/test_summary.json`。出力は最大 40 行。
  - 失敗したテスト名を 1 つも解釈できない (クラッシュなど) 場合と、`python3` がない場合は、従来の表示 (`Failed tests (N):` の一覧と詳細) に戻る。`TEST_TIMEOUT` / `ENV_ERROR` は従来どおり。
  - 従来の、失敗名を 50 件まで列挙する出力は、集約により、`tests:` が組ごとに最大 5 件になった (全名は JSON)。
- **警告の件数の通知 (成功時):** `SUCCESS` (`build_once.sh`) / `PASSED` (`build_test_once.sh`) の次の行に、警告があれば**1 行だけ**出す (`warnings: 12 (5 unique): C4244 x5, C4996 x3, C4101 x2, ... (+2 more)`)。警告がなければ、何も出ない。
  - `summarize_build_log.py` に、`--severity warning` (警告の集約)、`--root <dir>` (Windows のフルパスを相対パスに。`warnings.log` は、フルパスのまま)、`--oneline` を追加した。詳細は、同じスクリプトで読む。`.claude-logs/warnings_summary.json` にも書く。
  - **警告は、結果 (1 行目と終了コード) に影響しない。** 直すのは、ユーザーに頼まれたときだけ (`SKILL.md`)。**差分ビルドでは、再コンパイルされたファイルの警告だけ**が出る。`.claude-logs/warnings.log` がない (`-LogDir` で別の場所にした) 場合は、何も出ない。
- 両 `SKILL.md` に、「エラー出力の読み方 (要約形式)」を追加した (上の `[n]` から直す、`LNK` の扱い、`build_summary.json`、要約が出ない場合)。
- **契約 (ファイル名・結果の値・終了コード) の変更は、ない。** ホスト側ツール (ウォッチャー) の再配布は、不要。

### ツール・文書
- `tests/summarize_build_log_test.sh` に、警告の項目を追加した (9 項目。計 20 項目)。`tests/fake_watcher_test.sh` に、`PASSED` + 警告の行のケースを追加した。
- `tests/summarize_test_log_test.sh` を追加 (集約・パラメータ化テスト名・Linux 形式・上限・JSON・クラッシュ時のフォールバック。15 項目)。`cpp-build-test-loop/SKILL.md` に「テスト失敗の要約の読み方」を追加した。
- `tests/summarize_build_log_test.sh` を追加 (集約・並び・重複の除去・上限・JSON・フォールバック・コピーの一致。11 項目)。`tests/fake_watcher_test.sh` の `BUILD_FAILED` が要約形式になった。
- 実機の MSBuild / リンカのログでは、未確認 (サンプルのログのみ)。`docs/DESIGN.md` は未更新。

## [1.4.0] 2026-10-14

### Skill (再配布が必要: `install/install.sh`)
- **`new-solution` (`/new-solution`) を追加:** カレントのフォルダに、**フォルダ名と同名の `.slnx`** と、メインのプロジェクト (フォルダ名そのまま。`App` などは付けない) を作る。
  メインの種類は、MFC SDI / Win32 / コンソール / DLL / **静的ライブラリ**。**層 (`--layers`) とテスト (`--tests`) は、独立した 2 つの軸**で、引数で指定できる (省略したら質問。`--tests` は、必ず質問)。
  テストは、あとから後付けできる (すでにあるソリューションで `--tests gtest` を再実行)。設定は、`CLAUDE.md` の `層:` / `テスト:` に記録される。
  層の名前は、既定 (`LogicLayer` / `DataLayer`) で作り、変更は作成後 (`DLL-LAYOUT.md` に、変更するときの、直す箇所の一覧)。
- **流れを 3 段にした: `/brainstorm` (メモ) → `/update-from-ideas` (整理して、正式な仕様書) → `/add-feature` (実装)。**
  `/brainstorm` の成果物を、仕様書ではなく、**メモ (`docs/ideas/<機能名>.md`)** にした (決まらない項目は「未決」)。
  `/update-from-ideas` に、**新規作成モード (メモ → 仕様書)** を追加した (草案の全文を見せて承認。テストに落とせる具体さの点検。未決が残る間は `確定` にしない)。
  ソリューションがない場合は、仕様書のあとに、**構成案** (メインの種類・層・テスト・名前空間) と `/new-solution` のコマンドを提案する (仕様が先)。`/add-feature` は、メモだけがあるときに、`/update-from-ideas` を案内する。
- **`/add-feature` / `/brainstorm` / `cpp-test-first` が、テストの有無で動きを切り替える:** `テスト: あり` は、従来の TDD (Red → Green)。`テスト: なし` は、計画 → 承認 → 実装 → ビルド確認 → 手動確認。
  `cpp-test-first` のセットアップは、「層やテストを、あとから足すとき」に縮めた (最初の作成は `/new-solution`)。
- **`add_layer.py`:** `--tests none|gtest` (層だけ / 層 + テスト)、`--tests-only` (既存の DLL / 静的ライブラリにテストだけを足す)、`--kind dll|lib` (静的ライブラリ。公開マクロなし)、`--gtest-from` を追加。
  テストを作るとき、`packages\` に GoogleTest がなければ、**既存のもの (兄弟フォルダなど) を、コピーする** (ネットワークは使わない)。
  **exe のメインの名前が `Test` / `Tests` で終わる場合は、`<TargetName>` を `<名前>_Main` にする** (ウォッチャーが、アプリを、テストとして起動しないように)。
- 契約 (ファイル名・結果の値・終了コード) の変更は、ない。ホスト側ツールの再配布は、不要。

### ホスト側ツール (再配布が必要: `install/install.sh`)
- **`watch_and_build.ps1`: GoogleTest のソース取得 (`trigger_gtest.flag`) を追加。** Windows 側が GitHub から、固定タグのソースを取得して、`ThirdParty\googletest\` に置く
  (git clone、なければ zip。同じタグなら何もしない)。完了マーカー `gtest_result.txt` (`OK` / `FAILED`)、失敗時は `gtest_error.log`。`-GtestTag` (既定 `v1.17.0`)。
  **契約の拡張** (ファイル名の追加。既存の契約は変わらない)。DESIGN の契約表に追記。**手書きの PowerShell で、実機未確認** (TEST-PLAN の G1〜G8)。

- **`watch_and_build.ps1`: ビルド (`build-windows.cmd`) の出力が、別のコンソールに出る問題への対策。** `cmd.exe /c` を、専用の、表示しないコンソール (`CreateNoWindow`) で実行し、出力をパイプで受け取って、ウォッチャーの画面に、1 行ずつ流す
  (テストの出力と同じ画面)。バッチの `chcp` が、ウォッチャーのコンソールに影響しなくなる。`build-windows.cmd` は変更なし。**手書きで、実機未確認** (TEST-PLAN の H6〜H8、DESIGN 4.20)。

### Skill の追加機能
- **`--gtest auto|nuget|source`:** GoogleTest の入れ方。`source` は、ソースをソリューション内の静的ライブラリ `gtest` としてビルドする (NuGet 不要、新しい GoogleTest、ランタイムの不一致なし)。
  `auto` は、パッケージをコピーできれば `nuget`、できなければ `source` (取得は、`gtest_once.sh` でウォッチャーに依頼)。
- **`--layer-kind dll|lib`:** 層を、静的ライブラリにできる。 **`--layers logic:OrderLogic,data:OrderData`:** 層の名前を、作成時に指定できる (既定の動きは、変わらない)。
- **`--spec <仕様書>`:** 仕様書の `## 構成案` から、メインの種類・層・テスト・名前空間を読む (明示した引数が優先。未定の項目は、質問する)。`/update-from-ideas` の構成案を、この形式にした。
- `add_layer.py`: `--gtest`、`.cc` のソースの取り込み (GoogleTest 用)、`gtest` プロジェクトの生成。

- **`/new-solution`: 新規作成のときに、`.gitattributes` も作る** (すでにあれば、上書きしない。後付けでは、作らない)。`* text=auto eol=crlf` を中心にした、拡張子を列挙しない最小版
  (保存は LF、作業フォルダは CRLF。`*.sh` だけ LF)。WSL の git と Windows の Git の、どちらで操作しても、同じ結果になる。既存のリポジトリには、自動で足さず、提案する。

- **既存プロジェクトの、改行コードの規則の検出と提案:** `new_solution.py --check-git` (読み取りだけ。状態: `ok` / `propose` / `lf-only` / `declined` / `not-a-repo` / `unknown`) と、`--add-gitattributes` (最小版を作る。git の操作はしない)。
  `/add-feature` の最初の読み取り確認が、`propose` のときだけ、1 回、提案する (追加する / 今回は見送る / 今後も見送る)。`/new-solution` に、「C. 改行コードの規則の確認と追加」を追加。

- **`/add-feature`: 改行コードの規則の確認を、手順の最初 (0a.) に、必ず実行する形にした** (実機で、提案が出なかった。確認のコマンドが、別の Skill の `scripts/` を指すだけで、パスが曖昧だったため、`~/.claude/skills/new-solution/scripts/new_solution.py` を明記し、状態ごとの行動を表にした)。
- **`/new-solution` が作る `.gitignore` に、ウォッチャーの一時ファイル (`.claude-logs/`、`trigger_*.flag`、`*_result.txt`、`*_error.log`) を追加** (実機で、`git add -A` に、これらが入っていた)。

### ツール・文書
- `tests/gtest_once_test.sh` を追加 (取得の結果の分岐。14 項目)。`tests/new_solution_test.sh` に、source 方式・層の種類と名前・`--spec` を追加 (129 項目。`.gitattributes` の生成、実際の git での動作、既存プロジェクトの検出と提案を含む)。
- `tests/new_solution_test.sh` を追加 (層・テストの組み合わせ、後付け、静的ライブラリ、不正な入力。72 項目)。`tests/add_layer_test.sh` に、`--tests none` / `--tests-only` を追加。
- `docs/DESIGN.md` に 4.18、`docs/TEST-PLAN.md` に 2-0c (N0〜N12、N6b) と、U8〜U13 を追加 (B1〜B3、A2 を、メモ → 仕様書の流れに合わせて修正)。

## [1.3.0] 2026-10-13

### Skill (再配布が必要: `install/install.sh`)
- **`cpp-test-first` を追加:** 実装の前に、GoogleTest のテストを先に書き、スタブで、**アサーションで失敗する (Red)** ことを確認する。
  `PASSED` (空振り) と `BUILD_FAILED` (スタブなし) を、正しい Red として扱わない。確認のあと、`cpp-build-test-loop` に引き渡す (Green)。
  実行は、`cpp-build-test-loop` の `build_test_once.sh` を使う。スクリプトは持たない。
- **構成: MFC アプリ + ロジック DLL + データ DLL + DLL ごとのテスト exe (`<DLL名>Test.exe`)** を前提にした。
  対象の層を決める手順 (0.)、層ごとのテストの書き方 (ロジック: フェイク / データ: 一時フォルダの実ファイル)、DLL の公開マクロの付け忘れ (`LNK2019`) の扱い、
  層をまたぐ依頼は層ごとに順番に回す、を追加。構成と規約は、同梱の `DLL-LAYOUT.md`。
- **`brainstorm` (`/brainstorm`) と `add-feature` (`/add-feature`) を追加:** 壁打ちで仕様を固めて `docs/specs/<機能名>.md` に保存し、確定した仕様から、計画 → 承認 → テスト先行 (Red) → テストの確認 → 実装 (Green) → 検証を、ゲートを挟んで進める。
  どちらも、ユーザーが `/` で呼んだときだけ動く (`disable-model-invocation: true`)。`add-feature` は、手順の中身を、`cpp-test-first` と `cpp-build-test-loop` に任せる。
- **`update-from-ideas` (`/update-from-ideas`) を追加:** アイデアを、取り込む・保留・別機能・却下に仕分けて、承認後に、正式な仕様書へ反映する。
  確定した仕様に変更が入ると、状態が `変更あり (要再確定)` になり、変更履歴が残る。実装済みの場合は、影響を受けるテストを示して `/add-feature` に渡す。
  仕様書の状態に `変更あり (要再確定)` を追加し (`brainstorm` の様式)、`add-feature` / `cpp-test-first` が、これを未確定として扱う。
- **セットアップ (DLL とテスト exe がない場合) を追加:** Visual Studio で作った、ソリューション + MFC アプリから、データ層 → ロジック層の DLL と、各テスト exe を作る。
  生成は、同梱の `scripts/add_layer.py` (`.sln` / `.slnx` に対応、x64 のみ)。ベースラインが緑になってから、Red に進む。
- 契約 (ファイル名・結果の値・終了コード) の変更は、ない。ホスト側ツールの再配布は、不要。

### ホスト側ツール (再配布が必要)
- **`build-windows.cmd` / `watch_and_build.ps1`: MSBuild/cl.exe のビルド出力が文字化けする問題を修正。**
  `build-windows.cmd` の MSBuild.exe 呼び出しの直前後だけ `chcp 65001` / `chcp 932` を切り替え (ファイル自体は CP932 のままで、間に挟まる日本語の `rem` コメントは、この区間の外に置いた)。
  `watch_and_build.ps1` は、`[Console]::OutputEncoding = UTF8` を設定し、パイプで受け取る MSBuild/cl.exe の UTF-8 出力を正しく復号する。
  契約 (ファイル名・結果の値・終了コード) の変更は、ない。

### ツール
- `tests/add_layer_test.sh` を追加 (疑似ソリューションで、`add_layer.py` を検証)。`tools/check-formats.sh` が、`*.py` を検証する。

### 文書
- `docs/DESIGN.md` に 4.16、`docs/TEST-PLAN.md` に 2-0 (B1〜B3、A1〜A9)、2-0b (U1〜U7) と 2-1 (F0〜F13) を追加。README の構成表を更新。

## [1.2.0] 2026-10-13

### Skill (再配布が必要: `install/install.sh`)
- `cpp-auto-build` / `cpp-build-test-loop`: **「完了時の確認 (変更の報告)」を追加。** 完了時 (成功でも停止でも) に、変更したファイルを一覧し (`git -c core.fileMode=false --no-optional-locks status --short`)、
  **テストファイルの変更の有無を、報告の冒頭で明示する。** `git commit` / `git push` は、ユーザーの明示的な指示がない限り、実行しない。
  自分がファイルを編集していない場合は、実行しない。権限の確認が、拒否された場合に、別の方法で、同じ操作をしない、という規定も、追加した。
- 契約 (ファイル名・結果の値・終了コード) の変更は、ない。ホスト側ツールの再配布は、不要。

### 文書
- `docs/RECOMMENDED-SETTINGS.md` を追加: テストファイルの編集と `git commit` に、確認を付ける、権限設定 (`permissions.ask`) の例、仕様、限界、フックを採用しない理由。
- `docs/DESIGN.md` に 4.15、`docs/TEST-PLAN.md` に S9 / S10 を追加。

## [1.1.0] 2026-10-13

### ホスト側ツール
- **`watch_and_build.ps1`: 二重起動の防止:** 同じプロジェクトフォルダで、すでにウォッチャーが動いていれば、メッセージを出して、**終了コード 3** で終了する
  (名前付きミューテックス。プロセスの終了で、自動的に解放される)。同じフラグを、2 つのウォッチャーが奪い合って、結果が混ざるのを防ぐ。
- 契約 (ファイル名・結果の値・Skill のスクリプトの終了コード) の変更は、ない。Skill の再配布は、不要。

## [1.0.1] 2026-10-12

### ホスト側ツール
- `run_watcher.cmd`: 引数なしで起動したときの、案内を改善した。
  - 従来は、`ERROR: no .sln / .slnx found in <このファイルのフォルダ>` とだけ出て、原因が分かりにくかった。
  - 引数なしで、このファイルのフォルダが対象になったことを、`NOTE:` で知らせ、使い方 (`Usage` と `Example`) も表示する。
  - プロジェクトフォルダが存在しない場合も、使い方を表示する。
- 契約 (ファイル名・結果の値・終了コード) の変更は、ない。Skill の再配布は、不要。

## [1.0.0] 2026-10-12

最初のリリース (実機で、動作を確認した状態)。

### ホスト側ツール
- `watch_and_build.ps1`: `trigger_build.flag` (ビルド) と `trigger_test.flag` (ビルド + GoogleTest) を監視する。
  結果は、`build_result.txt` / `test_result.txt` (完了マーカー) と、`build_error.log` / `test_error.log`。
- `build-windows.cmd`: vswhere で最新のリリース版 VS (C++) を検出し、VsDevCmd の環境で MSBuild を実行する。
  `.claude-logs/` に、`build.log` / `errors.log` / `warnings.log` を出力する。
- `run_watcher.cmd`: プロジェクトフォルダを指定して、ウォッチャーを起動する。`.slnx` / `.sln` を自動検出する。
- ログ中のパスを、ソリューションフォルダからの相対パスに変換する。
- テストの判定: 終了コード 0 でも `[  PASSED  ]` の行がなければ、`ENV_ERROR` (テストが走っていないのを、成功と誤認しない)。
- テストの制限時間 (既定 120 秒): 超えたら、子プロセスごと強制終了し、実行中のテスト名を `Hung test` として記録する。
- 起動時に、コンソールのクイック編集モードを無効化する (クリックで、ビルドが止まるのを防ぐ)。
- 文字コード: `.cmd` は CP932 (日本語のコメント付き)、`.ps1` は BOM 付き UTF-8。

### Skill
- `cpp-auto-build`: ビルドのみのループ (成功まで、最大 5 回)。
- `cpp-build-test-loop`: ビルド + テストのループ。ソース側を優先して直し、テストの期待値の誤りは、変更前にユーザーへ確認する。
  `ENV_ERROR` / `WATCHER_NOT_RUNNING` では、ソースもテストも直さずに止まる。
  `TEST_TIMEOUT` では、直前にソースを変更していない場合は、直さずに報告して止まる。
- 待機は、バックグラウンドで1回のコマンドにし、待機中は何も読まない (古い結果の誤読を防ぐ)。
- スクリプト (`build_once.sh` / `build_test_once.sh`): 制限時間が数値でない場合は、`BAD_ARGS` (rc=2) で、すぐ終了する
  (数値でないと、待機ループの比較が毎回エラーになり、永久に待ち続けるため)。

### リポジトリ
- `install/install.sh`、`tools/check-formats.sh`、`tests/fake_watcher_test.sh`、`docs/DESIGN.md`、`docs/TEST-PLAN.md`。

### 既知の制限
- GoogleTest のみ。実行が重なったときの、古い結果の誤読は、未対策 (`docs/DESIGN.md` 4.4)。
- `Win32` / `ARM64` / `Release` / `.slnx` での、フラグ経由の実行は、未確認 (`docs/TEST-PLAN.md`)。
