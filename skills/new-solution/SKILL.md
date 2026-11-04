---
name: new-solution
description: カレントのフォルダに、フォルダ名と同名の .slnx と、メインのプロジェクト (MFC (SDI / MDI / ダイアログベース) / Win32 / コンソール / DLL / 静的ライブラリ / WPF (MVVM)) を作る。層 (C++ はロジック・データの DLL または静的ライブラリ、WPF は ViewModel・ロジック・データのクラスライブラリ) を作るか、テスト (C++ は GoogleTest、WPF は MSTest) を導入するかを、それぞれ指定できる (引数、仕様書の構成案 --spec、または質問)。GoogleTest は、vcpkg (既定) か、ホスト側で取得したソースのビルド (source)。テストは、あとから後付けもできる (--tests gtest / --tests mstest の再実行)。「新しいプロジェクトを始めたい」「ソリューションを作りたい」「テストを導入したい」という依頼で使う。
argument-hint: "[--ui-tests none|flaui] [--type wpf|winforms|csharp-dll|mfc|mfc-mdi|mfc-dialog|win32|console|dll|lib] [--layers none|logic|data|logic,data|viewmodel を含む組み合わせ (wpf)] [--tests none|gtest|mstest] [--layer-kind dll|lib|mfc-ext-dll] [--gtest auto|vcpkg|source] [--tfm net10.0] [--spec <仕様書>]"
disable-model-invocation: true
---

# 新しいソリューションを作る (/new-solution)

**新規プロジェクトでは、仕様が先でもよい:** (別リポジトリ `claude-spec-workflow` の) `/brainstorm` → `/update-from-ideas` で、仕様書を固めると、`/update-from-ideas` が、**構成案** (メインの種類・層・テスト・名前空間) を、仕様書に書き、このコマンドの引数を、提案する。
**`--spec <仕様書>` で、その構成案を読み込める。** 器が先でも、よい。構成案のキーは、`メインの種類` / `層` / `層の種類` / `テスト` / `名前空間` / `UIテスト` (`none` | `flaui`) / `TFM` (.NET のみ)。
**新規作成のとき、`--spec` は、仕様書の内容も、ソリューションへ取り込む** (`scripts/spec_import.py`):
- 仕様書と、その `元:` のメモを、`docs/specs/`・`docs/ideas/` に置く (すでにそこにあれば、そのまま。既存のファイルは、上書きしない)。
- 仕様書の「具体例」「境界値と異常系」の表から、**テストケースの種 `docs/specs/<名前>.cases.md`** を作る (`- [ ] E1: 入力 → 期待` / `- [ ] B1: ケース → 振る舞い`)。**テストコードではない。** `/add-feature` の計画が、これを、テスト名・入力・期待値に確定する。
- `CLAUDE.md` に、「## 仕様書」の節 (仕様書とケースの種へのリンク) を足す。
`--dry-run` では、取り込む予定のファイルだけを示す。

カレントのフォルダを、ソリューションにする。**フォルダ名が、ソリューション名・メインのプロジェクト名**になる (例: `MFCTDDTest` → `MFCTDDTest.slnx`、`MFCTDDTest/MFCTDDTest.vcxproj`)。

**軸を、別々に決める。**

| 軸 | 引数 | 値 |
|---|---|---|
| メインの種類 | `--type` | **`wpf` (WPF、MVVM。.NET)** / **`winforms` (WinForms、MVP。.NET)** / **`csharp-dll` (C# のクラスライブラリ。.NET。画面なし)** / `mfc` (MFC SDI) / `mfc-mdi` (MFC MDI) / `mfc-dialog` (MFC ダイアログベース) / `win32` (Win32 デスクトップ) / `console` / `dll` / `lib` (静的ライブラリ) |
| 層 | `--layers` | `none` / `logic` / `data` / `logic,data` (既定の名前: `LogicLayer` / `DataLayer`)。**`wpf` のときは、`viewmodel` (既定の名前 `ViewModels`) も、組み合わせられる** (例: `data,logic,viewmodel`)。名前は、`logic:OrderLogic,data:OrderData` のように指定できる。**`wpf` は、`SampleApp.Domain` のように、`.` を含む名前もよい** (規約 3.2 の `Presentation` / `Application` / `Domain` / `Infrastructure`。`wpf-check` が、標準の依存で検査する) |
| 層の種類 | `--layer-kind` | `dll` (既定) / `lib` (静的ライブラリ。公開マクロなし) / `mfc-ext-dll` (MFC 拡張 DLL。MFC の型・シリアライズを持ち込む層。**メインが MFC のときだけ**。`cpp-test-first` の `DLL-LAYOUT.md`)。全部の層に、同じ種類 |
| テスト | `--tests` | `none` / `gtest` (C++: 作った各 DLL / ライブラリに、`<名前>Test` と GoogleTest) / **`mstest` (WPF: 作った各クラスライブラリに、`<名前>.Tests` と MSTest)** |
| GoogleTest の入れ方 | `--gtest` | `auto` (既定。**vcpkg**) / `vcpkg` / `source` (旧 NuGet 方式 (`nuget`) は、v2.31.0 で廃止) (下の「GoogleTest」) |
| UI テスト | `--ui-tests` | `none` (既定) / **`flaui` (WPF / WinForms と、MFC などの C++ の GUI アプリ: `<アプリ名>.UITests` (MSTest + FlaUI) を足す)**。画面を、自動で操作して確かめたいときだけ。**ビルド → テストの流れには、含めず、ユーザーが求めたときだけ、別に実行する** (ウォッチャーの `trigger_uitest.flag`、`build-test-loop` の `uitest_once.sh`。画面をプロンプトで作りながら、UI テストを先に書いて繰り返すときは、`/ui-test-first`)。通常のテストには、含まれない。作成と同時に指定でき、**すでにあるソリューションに、後付けもできる** (`--ui-tests flaui` だけを指定)。書き方は、`build-test-loop` の `references/ui-tests.md` |

- **`winforms` (WinForms、MVP):** WPF と同じ経路 (SDK 形式の `.csproj`、`.slnx`、MSTest)。メインは WinForms アプリ (`net10.0-windows`、`UseWindowsForms`、`.slnx` の `DefaultStartup`)。**層は `data` / `logic` だけ** (`viewmodel` はエラー)。**MVP:** `Form` (`MainForm`) は `IMainView` を実装して、値の出し入れとイベントの通知だけをする。**画面の振る舞いは `MainPresenter`** が持つ (WinForms の型を使わない)。`IMainView` / `MainPresenter` は、**ロジック層があればそこ** (`--tests mstest` で `MainPresenterTests` の 4 件が付く)、なければ**アプリの `Presenters/` フォルダ** (テストできない)。`Program.cs` が composition root (`Form` と Presenter を作って結ぶ)。`MainForm.Designer.cs` は、VS のデザイナーの形 (コントロールに `Name` を付ける = UI Automation の `AutomationId`)。**`Form` (View) は、テストしない。** **ロジック層がないとき (`--layers none` / `data`) は、`--tests mstest` で、`<アプリ名>.Tests` が作られ、アプリの `Presenters/` をテストする** (アプリを参照するので、TFM はアプリと同じ `net10.0-windows`。名前空間は `<ルート>.Presenters.Tests`。`Info` クラスがないので、ベースラインは `MainPresenterTests` の 4 件)。**後付けの `--tests mstest` も、同じ** (WPF のアプリは、対象外のまま)。**`--ui-tests flaui` が使える** (`<アプリ名>.UITests`。UIA3。`AutomationId` は、コントロールの `Name`。標準の `MainForm` なら、入力 → 挨拶 → クリアのテストが付く。操作したいコントロールには、`Name` を付ける)。層の有無に関係なく使える (FlaUI は、アプリを参照せず、exe を起動して操作するため)。`CLAUDE.md` は、`winforms-check` と、規約 `winforms-csharp.md` を指す。**生成物は、`winforms-check` で、指摘 0 件** (出たら、生成の誤り)。
- **`csharp-dll` (C# のクラスライブラリ):** WPF と同じ経路 (SDK 形式の `.csproj`、`.slnx`、MSTest、NuGet の復元はビルドが行う)。**メイン自身がクラスライブラリで、テスト (`<メイン>.Tests`) の対象**になる (層がなくても、`--tests mstest` が使える)。`--layers` は `data` / `logic` だけ (`viewmodel` はエラー)。メインは、すべての層を参照する。`DefaultStartup` はない (exe がない)。`--ui-tests` は、エラー。`CLAUDE.md` は、`wpf-check` を挙げず、C# の規約 (`csharp-common.md`) を指す。
- 層とテストは、独立。`--layers logic,data --tests none` (層だけ、テストなし)、`--layers none --tests none` (メインだけ)、などができる。
- **`--tests gtest` は、テスト対象 (DLL / 静的ライブラリ) が必要。** メインが exe で `--layers none` の組み合わせは、エラー (層を作るか、`--tests none` にする)。メインが dll / lib なら、メイン自身がテスト対象になる。
- **層の名前は、既定のままでよい** (変更は、作成後にもできる。`DLL-LAYOUT.md` の「層の名前を、あとから変えるとき」)。作成時に指定するのは、ユーザーが望んだときだけ。

引数 (`$ARGUMENTS`) で指定された項目は、質問しない。**省略した項目は、質問する。特に `--tests` は、省略されたら、必ず質問する (黙って既定にしない)。**

## WPF (`--type wpf` のとき)

**C++ とは別の経路** (GoogleTest も、DLL も、`.vcxproj` も、使わない)。生成は、`csharp-test-first` Skill の `add_project.py` を、読み込んで行う (両方とも、配布されていること)。

| 項目 | 内容 |
|---|---|
| 構成 | **View (WPF アプリ) → ViewModel → ロジック → データ。** メインが WPF アプリ (`<フォルダ名>`、`net10.0-windows`)、層が **WPF 非依存のクラスライブラリ** (`net10.0`)。`--layers` の組み合わせで、足す層を決める (`data` / `logic` / `viewmodel`)。`viewmodel` を作らないと、ViewModel は、**アプリの `ViewModels/` フォルダ**に入る (テストできない。テストしたいなら、`viewmodel` を作る) |
| 層の依存 | データ ← ロジック ← ViewModel ← View。上の層は、すぐ下の層を参照する (アプリは、すべての層を参照する) |
| テスト | `--tests mstest`: **層のライブラリごとに** `<名前>.Tests` (MSTest v3)。**View (アプリ) には、作らない。** 層がないと、テスト対象がないので、エラー (層を作るか、`--tests none`) |
| 名前空間 | ルート = フォルダ名 (`--namespace` で変更)。層は `<ルート>.Data` / `.Logic` / `.ViewModels`、テストは `<名前空間>.Tests` |
| MVVM の基底 | **自前の最小実装** (`ObservableObject` / `RelayCommand`。NuGet 不要)。CommunityToolkit.Mvvm などは、`add-package` で足して、置き換える |
| アプリの構成 | **WPF プログラミング規約 3.1 に合わせる:** `App.xaml(.cs)` / `Views/` / `ViewModels/` (`viewmodel` 層がないとき) / `Resources/Styles.xaml` (共通の余白・スタイル。`App.xaml` で結合)。**`DataContext` は、`App.xaml.cs` の `OnStartup` (composition root) で設定する** (`MainWindow` のコードビハインドには、書かない)。画面は `Grid` レイアウト (`Auto` / `*`、`MinWidth` / `MinHeight`)、バインディングは `Mode` を明示 |
| サンプル | `MainWindow` (入力欄・表示・ボタン) と `MainViewModel` (`Name` / `Greeting` / `ClearCommand`)。`viewmodel` と `mstest` を作ると、`MainViewModelTests` (5 件) も付く。**サンプルは、消してよい** |
| 作るファイル | `<名前>.slnx` (構成は書かない。アプリに `DefaultStartup="true"`)、各 `.csproj` (SDK 形式)、`Directory.Build.props` (`Nullable` / `ImplicitUsings` / `LangVersion`)、`.editorconfig` (C# / XAML の書式。`~/.claude/rules/csharp-common.md` の「5 C# コーディング規約」と同じ)、`CLAUDE.md` / `.gitignore` / `.gitattributes` |
| 規約 | ユーザー共通の `~/.claude/rules/csharp-common.md` (C# の共通部分。`.cs` を扱うときに、自動で読み込まれる) と、`wpf-csharp.md` (WPF 固有。`.xaml`、`ViewModels/` `Views/` の下、`*ViewModel*.cs`) / `winforms-csharp.md` (WinForms 固有。`*.Designer.cs`、`Forms/` `Presenters/` の下、`*Presenter*.cs`、`I*View.cs`)。`install.sh` が配る (`install.sh --rules-only`) |
| 追加の引数 | `--tfm` (既定 `net10.0`。例: `net8.0`)、`--mstest-version` / `--testsdk-version` (既定は、実在を確認した版。新しい版は、`add-package` の `nuget versions` で確認して指定) |
| 使えない引数 | `--layer-kind` / `--gtest` / `--gtest-from` / `--toolset` (C++ 用。指定するとエラー)。`--tests gtest` もエラー |

- **NuGet の復元は、ウォッチャーのビルド (`/restore`) が行う。** ホストが nuget.org に届く必要がある。MSTest の参照が、初回のビルドで、取得される。
- 作成のあとの **ベースライン確認は、`build-test-loop` で `PASSED`** (テストなしなら、`auto-build` で `SUCCESS`)。GoogleTest の仕上げ (下の 5.) は、**ない**。
- **`wpf-check` (WinForms は `winforms-check`) を実行して、指摘がないこと**を、確認してよい (生成物は、指摘が出ないように作ってある。出たら、生成の誤り)。
- 最初に、Visual Studio で `.slnx` を開いて、問題がないか確認してもらうとよい (`DefaultStartup` で、アプリが、スタートアッププロジェクトになる。`.vs/` の個人の設定が、あれば、そちらが優先される)。

## GoogleTest (`--tests gtest` のとき)

| 方式 | 内容 | 要るもの |
|---|---|---|
| **vcpkg (既定)** | `vcpkg.json` (ソリューション直下) に `gtest` を入れ、テスト exe に **`main.cpp`** (自前の `main()`) を置く。トリプレット `x64-windows-static-md`。`builtin-baseline` で版を固定。2 回目以降は、vcpkg のバイナリキャッシュで、ビルドなしで入る | **ウォッチャー (Windows 側) が、GitHub に届くこと** (初回のみ。取得は `package_once.sh`) |
| **source** | **ソース** (`ThirdParty\googletest\`) を、ソリューション内の静的ライブラリ `gtest` としてビルド。vcpkg が使えないとき用 | **ウォッチャーが、GitHub に届くこと** |
| ~~nuget (旧方式)~~ | **廃止 (v2.31.0)**。`--gtest nuget` / `--gtest-from` は、エラー (終了コード 2)。`packages\` に旧方式のテストがあるソリューションは、そのまま使える | — |

- **`auto` (既定):** 既存の `gtest` プロジェクトがある → source / **それ以外 → vcpkg**。`packages\` に旧 NuGet 方式のテストがあっても、**新しいテストは vcpkg** (出力に、`NOTE: … 旧 NuGet 方式 …` が出る。既存のテストは、そのまま動く)。
- **vcpkg 方式の違い (source との):** 出力の「Running main() from ...」の行が出ない (自前の `main()`)。`gtestd.lib` ではなく、構成ごとのフォルダの `gtest.lib`。GoogleTest は C++17 以上が必要 (生成するプロジェクトは C++20)。要約 (`PASSED` / `FAILED` の形) は、変わらない。
- 方式は、ユーザーが指定してもよい。迷っていたら、`auto` で進める (案の提示で、どちらになるかを、見せる)。

## 前提
- **カレントが、対象のフォルダ。** このコマンドは、カレントにしか書き込まない (サンドボックスの制限。フォルダを作るのは、Claude Code を起動する前に、ユーザーが行う)。
  書き込みに失敗したら、回避せず、「作成先のフォルダで、Claude Code を、起動し直してください」と依頼して止まる。
- フォルダ名は、英数字と `_` のみ、先頭は英字か `_`。使えない名前なら、止まって、フォルダ名の変更を依頼する。
- 配布された `cpp-test-first` Skill の `scripts/add_layer.py` を、このコマンドのスクリプトが使う (両方とも、配布されていること)。

## モードの判定
カレントに `.sln` / `.slnx` が、あるか。(複数の候補を作る作業フォルダは、別のコマンド `/new-solutions`)

| 状態 | モード |
|---|---|
| ない (`solutions.md` もない) | **A. 新規作成** (この `/new-solution` は、**1 つのソリューション**を作る。種類違いの複数の候補を比べたいときは、`/new-solutions`) |
| ない + `solutions.md` がある | 作業フォルダ。「ここは、複数の候補の作業フォルダです。作成は `/new-solutions` で行います」と伝えて、止まる (**`.slnx` を作らない**) |
| 1 つある + `--tests gtest` (C++) / `--tests mstest` (.NET) | **B. テストの後付け** |
| 1 つある + それ以外 | 「すでにソリューションがあります。できるのは、テストの後付け (`--tests gtest` (C++) / `--tests mstest` (.NET)) だけです」と伝えて、止まる |
| 複数ある | 止まって、ユーザーに確認する |

## A. 新規作成

1. **引数を読み、省略した項目を質問する** (AskUserQuestion が使えるなら、選択肢で)。
   - **`--spec <仕様書>` があれば、まず、構成案を読む** (`--dry-run` の出力の先頭に、「構成案から読み取った: ...」が出る)。**読み取れなかった項目 (未定) と、明示されていない項目だけ、質問する。** 引数で明示した項目は、構成案より優先される。
   - **`--tfm` (.NET のみ。`--tfm` も構成案の `TFM:` もないとき):** 既定は、**最新の LTS** (`add_project.py` の `DEFAULT_TFM`、いま `net10.0`)。方針は「明示しない限り、最新」。**ただし、最新の版が STS (標準期間サポート。例: .NET 11) の場合は、質問して決める** (選択肢: 最新の LTS を使う (推奨。サポートが長い) / 最新の STS を使う (`--tfm net11.0`) / 版を指定する)。最新がどれか、LTS か STS かは、既定の記述に頼らず、公式の情報 (WebSearch など) で確かめる。**STS を選んだら、ホストに、その SDK が入っているか確かめてもらう** (`dotnet --list-sdks`)。`DEFAULT_TFM` が、最新の LTS より古くなっていたら、ユーザーに伝える。
   - **`--type` の質問は、2 段階にする** (質問の画面は、選択肢が 4 つまで。種類は 10 個あるので、先頭の 4 つだけを出さない): 先に系統 (.NET の画面つき (`wpf` / `winforms`) / MFC / C++ の画面なし・ライブラリ (`win32` / `console` / `dll` / `lib`) / `csharp-dll`)、次に系統の中の種類。
   - `--type`: MFC (SDI、推奨) / MFC MDI / MFC ダイアログベース / Win32 / コンソール / DLL / 静的ライブラリ。MFC は、**ドキュメントを扱うか**で選ぶ (1 つ: SDI、複数を同時に開く: MDI、ドキュメントなしの、設定・ツール型: ダイアログベース)。
   - `--layers`: `logic,data` (推奨) / `logic` / `data` / `none`。**WPF でも、推奨は `data,logic` (データ層 = Model を含める)。選択肢に、`viewmodel` を出さない。** ViewModel を**テストしたい**と言われたら、`viewmodel` を足した `data,logic,viewmodel` を提案する (`viewmodel` がないと、ViewModel は、アプリの `ViewModels/` に入り、テストできない。あとから足すこともできる: `csharp-test-first` の `references/setup.md`)。**`--layers` の指定がある場合は、そのまま使う** (層を、勝手に足さない)。
   - `--tests`: `gtest` / `none`。**必ず、質問する** (構成案が「未定」のときも)。(`gtest`: TDD の練習向き。`none`: ビルド確認だけの 3 層分離。)
   - `--ui-tests`: **`wpf` / `winforms` / `mfc` / `mfc-mdi` / `mfc-dialog` のとき、引数にも構成案 (`UIテスト`) にも指定がなければ、必ず、質問する。** 選択肢は、「なし (既定。UI テストは、あとから足せる)」と「FlaUI の UI テストを足す (`flaui`)」。**種類によって、質問を省かない** (以前は、WPF だけで質問が出て、WinForms では、出なかった。TEST-PLAN 2-15)。`csharp-dll` / `win32` / `console` / `dll` / `lib` では、質問しない (既定の `none`)。UI テストは、ビルド → テストの流れに含めない (上の表のとおり)。
   - **矛盾する組み合わせ** (exe + `--layers none` + `--tests gtest`) は、その場で指摘して、どちらかを変えてもらう。
2. **名前空間を決める** (層・DLL があるときだけ)。既定は、フォルダ名の大文字の頭文字 (例: `MFCTDDTest` → `mfctddt`)。読みにくいことがあるので、**案を示して、短い名前 (例: `tdd`) に変えるか、確認する。** 変える場合は、`--namespace` で渡す。
3. **案を示して、了承を得る (必ず止まる)。** 次の dry-run の出力を、要約して見せる。
   ```bash
   python3 <このSkillのフォルダ>/scripts/new_solution.py "$PWD" --type <..> --layers <..> --tests <..> [--layer-kind <..>] [--gtest <..>] [--namespace <..>] [--spec <..>] --dry-run
   ```
   ソリューション名、メイン、作る層 (名前・種類)、テスト、作るファイル、**GoogleTest の方式と状態** (`GTEST_MODE` / `GTEST_VCPKG` / `GTEST_SOURCE`。旧 NuGet 方式のテストが残るときは `NOTE`)、`MAIN_EXE_TARGETNAME` の予定 (あれば) を示す。
4. **作成する** (`--dry-run` を外して、同じ引数で実行)。**自分で、`.vcxproj` や `.slnx` を手書きしない。**
   - 終了コード 3 (すでにある) は、何も書かれていない。**既存のものを、上書きしない。**
   - 終了コード 2 は、組み合わせや入力の問題。内容をユーザーに伝える。
   - 出力の `MAIN_EXE_TARGETNAME: <名前> -> <名前>_Main` は、メインが exe で、名前が `Test` で終わるため、出力名を変えたという意味 (ウォッチャーが、アプリを、テストとして起動しないように)。**報告に明記する。**
5. **GoogleTest の仕上げ (`--tests gtest` のとき)。** 出力の `GTEST_MODE` で分かれる。
   - **`GTEST_MODE: vcpkg`**
     - `GTEST_VCPKG: present`: `vcpkg.json` に gtest と `builtin-baseline` がある。次へ (取得は、ビルドが行う。キャッシュがあれば、すぐ終わる)。
     - `GTEST_VCPKG: no-baseline`: **ウォッチャー経由で、baseline の固定と、取得を行う** (自分でフラグを置かない。長いので、`run_in_background: true`、完了通知が来るまで、ほかのコマンドを実行しない)。
       ```bash
       bash <add-package Skill のフォルダ>/scripts/package_once.sh "$PWD" --timeout 1800 "vcpkg baseline" "vcpkg install"
       ```
       初回は、gtest のビルドで、数十秒から数分 (実機の計測では、約 35 秒)。結果の表は、`add-package` Skill の「手順 2: vcpkg」と同じ (`TIMEOUT` は、報告して止まる。`ENV_ERROR` はネットワーク)。
   - **`GTEST_MODE: source`**
     - `GTEST_SOURCE: present`: 次へ。
     - `GTEST_SOURCE: to-fetch`: **ソースを、ウォッチャー経由で取得する。**
       1. **ウォッチャーが、起動していること** (起動していなければ、ここで依頼する。**ウォッチャーは、ソリューション (`.slnx`) ができたあとでないと、起動できない**)。
       2. 同梱のスクリプトで、取得する (**自分でフラグを置かない**)。`run_in_background: true` で実行し、完了通知が来るまで、ほかのコマンドを実行しない。
          ```bash
          bash <このSkillのフォルダ>/scripts/gtest_once.sh "$PWD" [タグ] 180
          ```
          | 1行目 | rc | 次の行動 |
          |---|---|---|
          | `OK` | 0 | 次へ |
          | `FAILED` | 1 | **環境の問題** (ネットワーク、プロキシ、タグ名、git)。ログの要点を報告して、止まる。選択肢を示す: (a) ネットワークを直して、もう一度 (b) `ThirdParty/googletest/{include,src}` に、ソースを手でコピー (c) vcpkg 方式に切り替える (**`gtest/` と `*Test/` を消して、`--gtest vcpkg` で作り直すので、ユーザーの了承を得てから**) |
          | `WATCHER_NOT_RUNNING` | 3 | 起動を依頼して、止まる |
          | `TIMEOUT` | 5 | 報告して止まる (長いネットワークなら、制限時間を延ばして、1 回だけ再試行してよい) |
          | `BAD_ARGS` | 2 | タグの形などを直す |
6. **ベースラインを確認する (ウォッチャーが起動していること):**
   - テストなし → `auto-build` の手順で、ビルドが成功すること (`SUCCESS`)。
   - テストあり → `build-test-loop` の手順で、ビルドとテストが、`PASSED` になること (各 DLL のベースライン用の 1 件のテスト)。**vcpkg 方式の `vcpkg install` と、source 方式の初回は、`gtest` のコンパイルで、少し長い。**
   - 失敗したら、それぞれの Skill の規則で直す。**手書きのプロジェクトの、最初のビルド**なので、設定の不備が出る可能性がある。環境の問題 (`ENV_ERROR`、ウォッチャー未起動) は、直さずに、報告する。
7. **報告して、終わる。** 作ったもの、モード (層・テスト・GoogleTest の方式)、確認の結果、`CLAUDE.md` に設定が書かれたこと、次の行動 (仕様書がすでにあれば **`/add-feature`**。なければ **`/brainstorm` (メモ) → `/update-from-ideas` (正式な仕様書)**) を、短く示す。自動で、次に進まない。
   - ユーザーに、Visual Studio で `.slnx` を開いて、問題がないか確認してもらうとよい、と添える。
   - **メインが exe のとき:** `.slnx` の `DefaultStartup="true"` を、メインに付けてある (最初に開くとき、メインが、スタートアッププロジェクトになる)。**ただし、`.vs/` の個人の設定 (`.suo`) が優先される。** 実行 (F5) で、「有効な Win32 アプリケーションではありません」が出たら、DLL が選ばれているので、メインを、右クリックの「スタートアップ プロジェクトに設定」で選び直す、と添える。

## B. テストの後付け (`--tests gtest` (C++) / `--tests mstest` (.NET)、すでにソリューションがある)

**.NET (WPF) のソリューションは、`--tests mstest`** (C++ の `gtest` は、エラー)。テストのない**クラスライブラリ**に、`<名前>.Tests` を足す (アプリ (View) には、足さない。名前空間と TFM は、既存の `.csproj` から読む)。dry-run で一覧を見せて、了承を得てから実行し、`build-test-loop` で `PASSED` を確認する。`CLAUDE.md` の `テスト:` は、`あり (MSTest)` に更新される。以下の 1.〜4. は、C++ の場合の説明 (GoogleTest の手順は、MSTest には、ない)。

1. **何が足されるかを、確認する:** dry-run で、テストのない DLL (層 / メイン DLL) の一覧と、作るファイル、GoogleTest の方式を、見せて、了承を得る。
   ```bash
   python3 <このSkillのフォルダ>/scripts/new_solution.py "$PWD" --tests gtest [--gtest <..>] --dry-run
   ```
   - テストを足せる DLL がない場合 (層がない、すべての DLL にテストがある) は、止まる。メインが exe で層がないなら、先に、層を作る (`/add-feature` の計画に含めるか、`cpp-test-first` の `add_layer.py`)。
2. **実行する** (`--dry-run` を外す)。既存の DLL の名前空間・参照は、スクリプトが、ファイルから読み取る。
3. **A の 5. と 6. と同じ** (GoogleTest の仕上げ、ベースラインの確認)。**`build-test-loop` で、`PASSED`。**
4. `CLAUDE.md` の `テスト:` の行が、`あり (GoogleTest)` に更新されたことを報告する。以降、`/add-feature` は、テスト先行で進む。

## C. 改行コードの規則 (`.gitattributes`) の確認と追加 (すでにあるプロジェクト)

**提案だけ。作るのは、ユーザーの了承を得てから。** 既存のリポジトリに足すと、保存が CRLF のファイルが、一斉に「変更あり」に見える (`git add --renormalize .` と、1 回のコミットが要る) ため。

1. **読み取りだけで、確認する:**
   ```bash
   python3 <このSkillのフォルダ>/scripts/new_solution.py "$PWD" --check-git
   ```
   1 行目の状態で、分かれる。

   | 状態 | 意味 | 次の行動 |
   |---|---|---|
   | `ok` | 規則がある | 何もしない |
   | `propose` | 規則がなく、CRLF のファイルがある | **提案する** (下の 2.) |
   | `lf-only` | 規則はないが、CRLF のファイルがない | 提案しない |
   | `declined` | `CLAUDE.md` に「- 改行コードの提案: 見送り」がある | 提案しない |
   | `not-a-repo` | git のリポジトリではない | 提案しない |
   | `unknown` | git の確認に失敗 (safe.directory の警告など) | 内容を報告するだけ。提案しない |

2. **`propose` のとき: 短く提案する (1 回だけ。作業を止めない)。** 件数、提案する最小版 (出力のとおり)、導入の手順を示して、選んでもらう:
   - **追加する:** `--add-gitattributes` で作る。**git の操作 (ステージ・コミット) は、しない。** ユーザーに、`git add --renormalize .` → `git status` で、改行だけの変更であることを確認 → 1 回コミット、を依頼する。
     それまでは、`git diff` に、改行だけの差分が、大量に出ることを、伝える。
     ```bash
     python3 <このSkillのフォルダ>/scripts/new_solution.py "$PWD" --add-gitattributes
     ```
   - **今回は見送る:** 何もしない (次回、また提案してよい)。
   - **今後も見送る:** `CLAUDE.md` に、`- 改行コードの提案: 見送り` の 1 行を足す (`## このソリューションの設定` の節の末尾)。以降、`declined` になり、提案しない。
3. 提案は、**作業の邪魔をしない**。選んでもらったあと、元の作業 (`/add-feature` など) に戻る。

この確認は、`/add-feature` の最初の読み取り確認でも、行われる。

## 設定の記録
作成時に、`CLAUDE.md` に、次の 3 行が書かれる。**`claude-spec-workflow` の `/brainstorm` / `/add-feature` / `/update-from-ideas` が、これを読んで、動きを切り替える。**
```
- メイン: <名前> (<種類>)
- 層: data,logic | なし      (既定でない名前は、data:OrderData,logic:OrderLogic のように記録)
- テスト: あり (GoogleTest) | あり (MSTest) | なし
```
`CLAUDE.md` が、すでにあれば、上書きしない (後付けのときは、`テスト:` の行だけを更新する)。

## 新規作成で、一緒に作るファイル
`CLAUDE.md` / `.gitignore` / **`.gitattributes`**。どれも、**すでにあれば、上書きしない。** 後付け (すでにソリューションがある) では、作らない。
- **`.gitattributes` (改行コードの規則):** `* text=auto eol=crlf` を中心にした、**最小版** (拡張子を列挙しない)。保存 (リポジトリ内) は LF に正規化、作業フォルダは CRLF (Visual Studio の既定)。`*.sh` だけ LF の例外。
  WSL の git と Windows の Git の、どちらで操作しても、同じ結果になる。変換したくないファイルは、末尾に 1 行足す (`*.xyz -text`)。
- **すでにあるソリューション (リポジトリ) に、`.gitattributes` がない場合は、自動では、作らない。** 追加すると、既存の CRLF のファイルが、一斉に「変更あり」に見えるため (`git add --renormalize .` と、1 回のコミットが要る)。
  必要なら、ユーザーに、提案する (内容と、導入の手順を示す。作るのは、了承を得てから)。

## しないこと
- カレントの外への書き込み。既存のソリューション・プロジェクトの上書き。
- ユーザーの了承なしの作成。`--tests` の、黙った既定値の採用。
- 自分で、フラグファイルを置く (取得は、`gtest_once.sh`)。
- 機能のコード、仕様書の作成 (別リポジトリ `claude-spec-workflow` の `/brainstorm` / `/update-from-ideas` / `/add-feature` の仕事)。
- `git commit` / `git push` / `git init`。
